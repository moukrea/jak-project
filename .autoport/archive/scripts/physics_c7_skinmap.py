#!/usr/bin/env python3
"""Cycle 7 — BONE <-> MESH CORRESPONDENCE.  Does the chain actually drive what the owner sees?

Owner, 2026-08-07 07:50, on the 07:17 build: "Il n'y a AUCUNE DIFFERENCE avec les builds
precedents."  Cycle 6 had measured Jak's left jacket flap 47.68 units deep inside the RIGHT leg
volume, changed the resolution order, and reported xleg=0.  His eyes say nothing moved.

That is the second counter falsified by direct observation in two days, so the supervisor's rule
applies: the likely fault is no longer "the fix was too weak", it is "we are not driving the
geometry he is looking at".  On jak-hd the chain `shirtL` drives exactly ONE joint, `shirtLthigh`.
If the visible flap is mostly skinned to the THIGH bone, the solver moves a handful of vertices,
the flap keeps riding the leg, and every counter in the file can be green while the screen is
unchanged.

This script settles that question in the DATA, before any parameter is touched:

  for every declared chain, take the geometry that physically sits where the chain sits (every
  mesh vertex within the chain's own measured link radius of its bind-pose joints) and rank the
  joints that skin it by the weight they carry.  Then state whether the chain's joints hold the
  MAJORITY of that weight.

  authority = (sum of skin weight held by the chain's joints over the region)
              / (total skin weight over the region)

  authority near 1.0  the chain owns its geometry; a solver change will be visible.
  authority near 0.0  the geometry is driven by an ANIMATED bone (a thigh, a skull, a collar).
                      No stiffness, damping or collider value can ever change what is drawn.
                      The chain must be extended to the dominant joints, or the joint injected.

Nothing here is a judgement call and nothing here is visual: it is the glTF skinning table, which
is the same table the runtime skins with.

Usage:
  python3 .autoport/physics_c7_skinmap.py                       # whole cast, writes the audit
  python3 .autoport/physics_c7_skinmap.py --only jak-hd,keira-hd
  python3 .autoport/physics_c7_skinmap.py --defects             # only the owner-named sites
"""
import argparse
import json
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts', 'shell'))

from physics_c6_volumes import load_geometry, CHAINS, seg_td  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
OUT = os.path.join(REPO, '.autoport', 'reports', 'Grecharged-secondary-motion', 'skinmap.txt')

# A vertex counts as "sitting on" a chain when it is within this much of the chain's bind-pose
# skeleton, on top of the chain's own measured link radius.  The link radius was itself derived
# from the thickness of the geometry the link carries (physics_c6_volumes.link_radius), so the
# region is the garment the chain is inside, not an arbitrary ball.
REGION_MARGIN = 60.0
DEFAULT_LINK_RADIUS = 160.0

# The owner's named defects, cycle 6 (01:20) + cycle 7 (07:50).  Each maps to the chain(s) that
# are supposed to be driving it.  The point of the table is to be REFUTABLE: if a site's chains
# turn out not to drive it, that is the finding.
DEFECTS = [
    ('jak jacket flap over the legs (crossed)', 'jak-hd', ['shirtL', 'shirtR']),
    ('jak collar into the shoulders',           'jak-hd', ['collarL', 'collarR']),
    ('jak back buckle through its own strap',   'jak-hd', ['packstrap']),
    ('jak hair (only the very tip moved)',      'jak-hd', ['hair']),
    ('jak ears',                                'jak-hd', ['earL', 'earR']),
    ('keira neck hair through the neck',        'keira-hd', None),   # resolved by name below
    ('keira goggles into the chest',            'keira-hd', None),
    ('keira front bangs through face/ears',     'keira-hd', None),
    ('keira chest (jiggle + firmness)',         'keira-hd', None),
    ('maia hair through the body',              'evilsis-lod0', None),
    ('daxter ears (step at mid-height)',        'dax-hd', None),
]
# name fragments used to resolve the chains of a site when the rig naming is not known up front
DEFECT_HINTS = {
    'keira neck hair through the neck':     ('back', 'nape', 'neck', 'nuque'),
    'keira goggles into the chest':         ('goggle', 'lunette', 'glass'),
    'keira front bangs through face/ears':  ('bang', 'front', 'meche', 'fringe'),
    'keira chest (jiggle + firmness)':      ('boob', 'chest', 'breast'),
    'maia hair through the body':           ('hair', 'pony', 'tail'),
    'daxter ears (step at mid-height)':     ('ear',),
}


# ----------------------------------------------------------------------------------------------
def parse_chains(path=CHAINS):
    """-> {model: [ {name, joints[], radii[], family, keys{}} ]}, preserving file order."""
    out = {}
    models = []
    cur = None
    for ln in open(path, errors='ignore'):
        m = re.match(r'^\[model ([^\]]+)\]', ln)
        if m:
            models = m.group(1).split()
            for x in models:
                out.setdefault(x, [])
            cur = None
            continue
        if ln.startswith('chain '):
            f = ln.split()
            keys = dict(kv.split('=', 1) for kv in f[2:] if '=' in kv)
            radii = [float(x) for x in keys.get('radii', '').split(',') if x.strip()]
            cur = dict(name=f[1], joints=[], radii=radii, family=keys.get('family', '?'), keys=keys)
            for x in models:
                out[x].append(cur)
            continue
        if ln.startswith('j ') and cur is not None:
            cur['joints'].append(ln.split()[1])
    return out


def chain_region(geo, joints, radii):
    """Boolean mask over geo['V']: the geometry this chain sits in.

    SEEDED FROM THE SKIN, NOT FROM THE BONE.  The first version of this seeded the region on the
    chain's bind-pose bone positions, and reported "no mesh vertex sits on this chain" for Jak's
    hair, his jacket flaps and Keira's chest.  That was an artefact, not a finding: a bone lives
    INSIDE the body, so the nearest surface vertex to shirtLthigh is 397 units away while the
    chain's own link radius is 260 — the ball never reached its own skin.

    The region is therefore the chain's skinned cloud (every vertex the chain's joints hold any
    weight on) DILATED by the chain's measured link radius.  That is the garment the chain is part
    of: its own vertices plus the ones sitting against them, which is exactly the population whose
    ownership decides whether moving this chain moves anything visible.
    """
    names = list(geo['names'])
    idx = {n: i for i, n in enumerate(names)}
    ji = [idx[j] for j in joints if j in idx]
    if not ji:
        return None, []
    V, J, W = geo['V'], geo['J'], geo['W']
    seed = np.zeros(len(V), dtype=bool)
    for c in range(J.shape[1]):
        seed |= np.isin(J[:, c], ji) & (W[:, c] > 0)
    if not seed.any():
        return seed, ji                       # the chain skins nothing at all — a real finding
    r = (max(radii) if radii else DEFAULT_LINK_RADIUS) + REGION_MARGIN
    return dilate(V, seed, r), ji


def dilate(V, seed, r):
    """seed OR {v : dist(v, some seed) <= r}, via a uniform grid of cell size r.

    The brute-force form is |V| x |seed| distances, which is minutes per model over the cast.
    With cells of side r, only the 27 neighbouring cells can hold a point within r, so each
    vertex compares against a handful of candidates instead of the whole cloud.
    """
    mask = seed.copy()
    S = V[seed]
    if len(S) == 0:
        return mask
    org = V.min(axis=0)
    cell = np.floor((S - org) / r).astype(np.int64)
    grid = {}
    for i, c in enumerate(map(tuple, cell)):
        grid.setdefault(c, []).append(i)
    vc = np.floor((V - org) / r).astype(np.int64)
    r2 = r * r
    for vi in np.nonzero(~mask)[0]:
        cx, cy, cz = vc[vi]
        p = V[vi]
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    g = grid.get((cx + dx, cy + dy, cz + dz))
                    if not g:
                        continue
                    d = S[g] - p
                    if float((d * d).sum(axis=1).min()) <= r2:
                        mask[vi] = True
                        break
                else:
                    continue
                break
            else:
                continue
            break
    return mask


def driven_set(geo, ji, chain, other_chain_joints):
    """Joints this chain actually MOVES: its own, plus the descendants the solver rigidly
    re-glues onto them.

    jak-hd-physics.gc:3151-3200 runs a rigid descendant pass after the chain integration — a
    child of a moved joint is carried with it unless the chain opts out with nodesc=1.  Ignoring
    that pass reports a false root cause: Keira's `goggles` chain names only `gogglesMid`, but
    gogglesLeft/gogglesRight (252 verts each, weight ~1) are its children and ride it rigidly, so
    the goggles do move as one body.  A subtree owned by ANOTHER chain stops the walk — that
    geometry is driven, just not by this chain.
    """
    if chain['keys'].get('nodesc') == '1':
        return list(ji)
    kids = {}
    for k, p in enumerate(geo['parent']):
        kids.setdefault(int(p), []).append(k)
    out, stack = list(ji), list(ji)
    while stack:
        n = stack.pop()
        for k in kids.get(n, []):
            if k in out or k in other_chain_joints:
                continue
            out.append(k)
            stack.append(k)
    return out


def analyse(geo, chain, other_chain_joints=frozenset()):
    """-> dict with the authority number and the joint ranking over the chain's region."""
    names = list(geo['names'])
    idx = {n: i for i, n in enumerate(names)}
    missing = [j for j in chain['joints'] if j not in idx]
    own = [idx[j] for j in chain['joints'] if j in idx]
    if not own:
        return dict(err='no joint of this chain exists in the rig', missing=missing)
    ji = driven_set(geo, own, chain, other_chain_joints)
    mask, _ = chain_region(geo, [names[i] for i in ji], chain['radii'])
    if mask is None:
        return dict(err='no joint of this chain exists in the rig', missing=missing)
    n = int(mask.sum())
    if n == 0:
        return dict(err='this chain skins NO mesh vertex at all — it drives an empty joint',
                    missing=missing, nregion=0)
    def breakdown(sel):
        J, W = geo['J'][sel], geo['W'][sel]
        tot = float(W.sum())
        per = {}
        for c in range(J.shape[1]):
            jc, wc = J[:, c], W[:, c]
            for b in np.unique(jc):
                w = float(wc[jc == b].sum())
                if w <= 0:
                    continue
                e = per.setdefault(int(b), [0.0, 0])
                e[0] += w
                e[1] += int(((jc == b) & (wc > 0)).sum())
        held = np.zeros(int(sel.sum()), dtype=float)
        for c in range(J.shape[1]):
            held += np.where(np.isin(J[:, c], ji), W[:, c], 0.0)
        return per, tot, held

    # SEED = only the vertices this chain actually skins. Its authority there answers "are my own
    # vertices mine, or does an ANIMATED bone hold them with me?" — the question that decides
    # whether moving the chain moves anything.
    seed = np.zeros(len(geo['V']), dtype=bool)
    for c in range(geo['J'].shape[1]):
        seed |= np.isin(geo['J'][:, c], ji) & (geo['W'][:, c] > 0)
    per_s, tot_s, held_s = breakdown(seed)
    auth_seed = sum(per_s.get(i, [0.0, 0])[0] for i in ji) / tot_s if tot_s > 0 else 0.0

    # REGION = seed dilated by the link radius: the whole garment cluster the chain is part of.
    per_r, tot_r, held_r = breakdown(mask)
    rank = sorted(per_r.items(), key=lambda kv: -kv[1][0])
    auth_reg = sum(per_r.get(i, [0.0, 0])[0] for i in ji) / tot_r if tot_r > 0 else 0.0

    # joints that hold real weight in this cluster and are NOT in the chain and are NOT an
    # animated body bone we could never take over -> candidates to ADD to the chain.
    cand = [(names[b], w / tot_r, c) for b, (w, c) in rank
            if b not in ji and w / tot_r >= 0.05]
    return dict(
        nseed=int(seed.sum()), nregion=n,
        authority=auth_reg, auth_seed=auth_seed,
        moved_any=int((held_r > 0.02).sum()),
        moved_major=int((held_r >= 0.5).sum()),
        seed_major=int((held_s >= 0.5).sum()),
        rank=[(names[b], w / tot_r, c) for b, (w, c) in rank[:8]],
        cand=cand[:5],
        chain_joints=[names[i] for i in own],
        carried=[names[i] for i in ji if i not in own],
        missing=missing,
    )


def others(geo, model_chains):
    """indices of every joint claimed by some chain of this model."""
    idx = {n: i for i, n in enumerate(geo['names'])}
    return {idx[j] for ch in model_chains for j in ch['joints'] if j in idx}


def resolve_defect_chains(chains, model, explicit, hints):
    if explicit:
        return explicit
    got = []
    for ch in chains.get(model, []):
        blob = (ch['name'] + ' ' + ' '.join(ch['joints'])).lower()
        if any(h in blob for h in hints):
            got.append(ch['name'])
    return got


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', default='')
    ap.add_argument('--defects', action='store_true')
    ap.add_argument('--out', default=OUT)
    a = ap.parse_args()

    chains = parse_chains()
    want = [x for x in a.only.split(',') if x] or sorted(chains)
    if a.defects:
        want = sorted({m for _, m, _ in DEFECTS})

    geos = {}
    lines = []
    lines.append('CYCLE 7 — BONE <-> MESH CORRESPONDENCE (skin-weight attribution)')
    lines.append('authority = share of the skin weight, over the geometry sitting ON the chain,')
    lines.append('            that the chain\'s own joints carry.  <0.50 = the chain does NOT')
    lines.append('            drive what is drawn there, and no solver value can change that.')
    lines.append('')

    summary = []
    for model in want:
        geo = geos.get(model)
        if geo is None:
            geo = load_geometry(model)
            geos[model] = geo
        if geo is None:
            lines.append(f'[{model}] NO GEOMETRY ON DISK — cannot audit')
            lines.append('')
            continue
        lines.append(f'[{model}]  src={geo["src"]}  verts={len(geo["V"])}  joints={len(geo["names"])}')
        occ = others(geo, chains.get(model, []))
        for ch in chains.get(model, []):
            r = analyse(geo, ch, occ - {i for i in occ if geo['names'][i] in ch['joints']})
            if r.get('err'):
                lines.append(f'  {ch["name"]:<14} !! {r["err"]}'
                             + (f'  (missing joints: {r["missing"]})' if r.get('missing') else ''))
                summary.append((model, ch['name'], None, r['err']))
                continue
            top = ', '.join(f'{n} {p*100:.1f}% ({c}v)' for n, p, c in r['rank'][:4])
            verdict = 'DRIVES' if r['auth_seed'] >= 0.5 else 'DOES NOT DRIVE'
            lines.append(
                f'  {ch["name"]:<14} fam={ch["family"]} joints={r["chain_joints"]} '
                f'seed={r["nseed"]}v region={r["nregion"]}v '
                f'authority(seed)={r["auth_seed"]:.3f} authority(region)={r["authority"]:.3f} {verdict}')
            lines.append(f'                 skinned by: {top}')
            lines.append(f'                 vertices the chain moves at all={r["moved_any"]}'
                         f'  dominates={r["moved_major"]}')
            if r['cand']:
                lines.append('                 NOT in the chain but holding this geometry: '
                             + ', '.join(f'{n} {p*100:.1f}%' for n, p, _ in r['cand']))
            summary.append((model, ch['name'], r['auth_seed'], verdict))
        lines.append('')

    # ---- the owner's named defects, called out by name ----
    lines.append('=' * 90)
    lines.append('OWNER-NAMED DEFECTS — does the chain drive the geometry he is looking at?')
    lines.append('=' * 90)
    defect_rows = []
    for title, model, explicit in DEFECTS:
        geo = geos.get(model)
        if geo is None:
            geo = load_geometry(model)
            geos[model] = geo
        if geo is None:
            lines.append(f'{title:<44} [{model}] no geometry on disk')
            continue
        names = resolve_defect_chains(chains, model, explicit, DEFECT_HINTS.get(title, ()))
        if not names:
            lines.append(f'{title:<44} [{model}] NO CHAIN DECLARED FOR THIS SITE')
            defect_rows.append((title, model, [], None))
            continue
        occ = others(geo, chains.get(model, []))
        for cn in names:
            ch = next((c for c in chains[model] if c['name'] == cn), None)
            if ch is None:
                continue
            r = analyse(geo, ch, occ - {i for i in occ if geo['names'][i] in ch['joints']})
            if r.get('err'):
                lines.append(f'{title:<44} [{model}] {cn}: {r["err"]}')
                continue
            top = ', '.join(f'{n} {p*100:.1f}%' for n, p, _ in r['rank'][:3])
            lines.append(f'{title:<44} [{model}] {cn}: authority(seed)={r["auth_seed"]:.3f} '
                         f'authority(region)={r["authority"]:.3f} '
                         f'{"DRIVES" if r["auth_seed"]>=0.5 else "DOES NOT DRIVE the majority of the skin weight"}')
            lines.append(f'{"":<44}   chain joints: {r["chain_joints"]}'
                         + (f' + carried rigidly: {r["carried"]}' if r['carried'] else ''))
            lines.append(f'{"":<44}   joints skinning it: {top}')
            if r['cand']:
                lines.append(f'{"":<44}   missing from the chain: '
                             + ', '.join(f'{n} {p*100:.1f}%' for n, p, _ in r['cand']))
            defect_rows.append((title, model, [cn], r['auth_seed']))
    lines.append('')

    bad = [s for s in summary if s[2] is not None and s[2] < 0.5]
    lines.append(f'CHAINS AUDITED: {len([s for s in summary if s[2] is not None])}'
                 f'   BELOW MAJORITY: {len(bad)}')
    for m, c, au, _ in sorted(bad, key=lambda x: x[2])[:40]:
        lines.append(f'   {m:<22} {c:<16} authority={au:.3f}')

    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    open(a.out, 'w').write('\n'.join(lines) + '\n')
    print('\n'.join(lines[-60:]))
    print(f'\nwritten: {a.out}')
    json.dump([dict(model=m, chain=c, authority=au) for m, c, au, _ in summary],
              open(a.out.replace('.txt', '.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()
