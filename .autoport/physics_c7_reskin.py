#!/usr/bin/env python3
"""Cycle 7 — WEIGHT TRANSFER: give a physics joint authority over the geometry it represents.

Owner, 2026-08-07 07:50: Keira's chest "bouge un peu plus, mais elle est beaucoup plus FLASQUE
[...] et ne bouge PAS ASSEZ."  Cycle 6 answered that by raising the amplitude, and made it worse.
The skin-weight audit (.autoport/physics_c7_skinmap.py) says why, in the donor's own skinning
table and without any visual judgement:

    keira-hd  rBoob   90 verts, total weight 15.5, STRONGEST vertex 0.408, mean 0.172
              lBoob   94 verts, total weight 18.2, STRONGEST vertex 0.408, mean 0.193
              chest  1207 verts, total weight 854.7 — dominant on every one of those vertices

Not one breast vertex is majority-owned by the joint the solver moves.  Whatever the solver does
to rBoob reaches the screen at ~17% strength, and it reaches it UNEVENLY: the few vertices near
the centre carry 0.41 and the rim carries 0.02, so raising the amplitude moves the middle and
leaves the edge behind.  That is precisely "flasque" — a local dimple instead of a volume.  No
stiffness, damping, mass or firmness value can change it, which is why two cycles of tuning
produced "aucune difference".

So the fix is where the defect is: in the WEIGHTS.  For every vertex the artist already gave some
of the physics joint, this raises that share and takes it back from the body bone, KEEPING THE
ARTIST'S OWN SPATIAL PROFILE — the vertex the artist weighted most stays the one weighted most.
The breast then moves as a volume, and the base still blends into the chest, because a breast is
attached to a chest.

    s        = w_target / max(w_target)        the artist's normalised profile, untouched in shape
    w_target'= cap * s**shape                  re-scaled so the peak reaches `cap`
    the gain is taken from `from=` joints in proportion to what they hold, then the vertex is
    renormalised to sum 1.

`shape` < 1 widens the shoulder of the profile (more of the breast moves together), `shape` = 1
is a pure rescale.  `grow=` optionally dilates the support first, for a donor whose painted patch
is too small to be a volume at all.

This is the "injection d'os + transfert de poids" the phase prompt anticipated for stock rigs,
applied here to a joint that already exists but was painted decoratively.  Nothing else in the
model changes: same joints, same positions, same triangles.

Usage (called from scripts/shell/build_enhanced_models.sh between prep and hd_merc_swap):
  python3 .autoport/physics_c7_reskin.py --model keira-hd --in prepped.glb --out prepped.glb
  python3 .autoport/physics_c7_reskin.py --audit          # print what the config would do
"""
import argparse
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'scripts', 'shell'))
from retarget_hd_models import (read_glb, consolidate_buffers, read_accessor,  # noqa: E402
                                append_accessor, write_glb, gc_glb, skin_info)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
CFG = os.path.join(REPO, 'recharged_assets', 'physics_reskin.txt')
UNITS = 4096.0


def load_cfg(path=CFG):
    """-> {model: [dict(target, donors, cap, shape, grow)]}

    PAS DE FICHIER = PAS DE REGLE, et c'est un etat legitime : le depart propre du 2026-08-11
    (`f86d919800`, TABLE RASE) a supprime `recharged_assets/physics_reskin.txt`. `main()` sait
    deja traiter « aucune regle » — il recopie l'entree telle quelle (« no rule — passthrough »).
    Or l'ouverture etait INCONDITIONNELLE et levait FileNotFoundError avant tout filtrage, donc
    exit != 0, donc `scripts/shell/build_enhanced_models.sh:233` tuait TOUT le bake HD. Le mesh
    livre ne pouvait plus etre reconstruit depuis l'arbre : la paire livree n'etait pas
    reproductible, et aucune correction de ponderation n'aurait pu devenir visible."""
    out, cur = {}, []
    if not os.path.exists(path):
        return out
    for ln in open(path, errors='ignore'):
        ln = ln.split('#')[0].strip()
        if not ln:
            continue
        m = re.match(r'^\[model ([^\]]+)\]$', ln)
        if m:
            cur = m.group(1).split()
            for x in cur:
                out.setdefault(x, [])
            continue
        f = ln.split()
        if f[0] not in ('transfer', 'grade') or not cur:
            continue
        kv = dict(x.split('=', 1) for x in f[2:] if '=' in x)
        r = dict(kind=f[0],
                 target=f[1],
                 donors=[d for d in kv.get('from', '').split(',') if d],
                 cap=float(kv.get('cap', 0.9)),
                 shape=float(kv.get('shape', 1.0)),
                 grow=float(kv.get('grow', 0.0)),
                 # `grade` only: la marche de poids maximale toleree entre deux sommets VOISINS.
                 # 0.5 fait une bande d'exactement UNE rangee (un voisin de 1.00 monte a 0.50, et
                 # son propre voisin a 0.00) — c'est ce qui borne le risque de detacher la meche.
                 step=float(kv.get('step', 0.5)),
                 iters=int(kv.get('iters', 8)))
        for x in cur:
            out[x].append(r)
    return out


def apply_model(js, binc, rules, verbose=True):
    """Rewrite WEIGHTS_0 in place for every primitive.  Returns a list of report lines."""
    names, _, _ = skin_info(js, binc)
    idx = {n: i for i, n in enumerate(names)}
    rep = []

    # Aretes du mesh, par jeu d'attributs. `grade` en a besoin : c'est un defaut de VOISINAGE
    # (« des polygones qui bougent et des polygones voisins parfaitement statiques »), donc il se
    # mesure et se corrige sur les aretes, pas sur des sommets pris isolement. On les collecte pour
    # TOUTES les primitives qui partagent le meme jeu d'attributs, car la boucle ci-dessous n'en
    # traite qu'une seule et les autres reutilisent son resultat.
    edges_by_key = {}
    for mesh in js.get('meshes', []):
        for pr in mesh.get('primitives', []):
            if 'indices' not in pr or int(pr.get('mode', 4)) != 4:
                continue
            at = pr['attributes']
            ind = np.asarray(read_accessor(js, binc, pr['indices'])).reshape(-1)
            e = edges_by_key.setdefault((at['JOINTS_0'], at['WEIGHTS_0']), set())
            for i in range(0, (len(ind) // 3) * 3, 3):
                a, b, c = int(ind[i]), int(ind[i + 1]), int(ind[i + 2])
                for u, v in ((a, b), (b, c), (a, c)):
                    e.add((u, v) if u < v else (v, u))

    # every primitive shares one attribute set in a prepped glb, but do not assume it
    seen = {}
    for mesh in js.get('meshes', []):
        for pr in mesh.get('primitives', []):
            at = pr['attributes']
            key = (at['JOINTS_0'], at['WEIGHTS_0'])
            if key in seen:
                at['WEIGHTS_0'] = seen[key]
                continue
            J = read_accessor(js, binc, at['JOINTS_0']).astype(np.int32)
            W = read_accessor(js, binc, at['WEIGHTS_0']).astype(np.float64)
            P = read_accessor(js, binc, at['POSITION']).astype(np.float64) * UNITS

            for r in rules:
                t = idx.get(r['target'])
                if t is None:
                    rep.append(f"  !! target joint {r['target']} not in rig — skipped")
                    continue
                wt = np.zeros(len(W))
                for c in range(J.shape[1]):
                    wt += np.where(J[:, c] == t, W[:, c], 0.0)
                sup = wt > 0
                if not sup.any():
                    rep.append(f"  !! {r['target']}: no vertex carries this joint — nothing to grow")
                    continue
                wmax = float(np.quantile(wt[sup], 0.90))
                if wmax <= 1e-6:
                    wmax = float(wt.max())

                if r['kind'] == 'grade':
                    # GRADUATION DE JONCTION (2026-08-12). Defaut PRIORITE 1 `hair-skinning`.
                    #
                    # Les sommets qui « cassent » ne sont PAS de la meche mal pesee : ils forment la
                    # bordure d'ancrage cuir chevelu / meche (contigus, moitie de leurs voisins dans
                    # la meche, a la base de la meche), et SPEC 2 exige qu'elle reste soudee. Le
                    # defaut est que la marche y est ABRUPTE — un sommet a 100 % `head` voisin d'un
                    # sommet a 100 % meche, sans bande de melange, donc cisaillement maximal des que
                    # la meche tourne. `backhair`, attache au meme crane, ne casse pas : sa jonction
                    # est graduee (marche max 0.451). C'est lui la reference, pas une theorie.
                    #
                    # On ne fait donc PAS ce que `transfer` fait : on n'augmente pas la propriete de
                    # la meche (c'est la regle jak-hd rejetee a l'epoque, qui DETACHAIT la coiffe du
                    # crane). On ne fait QUE remonter le cote BAS d'une arete trop raide, jamais
                    # baisser le cote haut — baisser le cote haut retirerait du mouvement, et le
                    # mouvement est ce que l'owner reclame.
                    #
                    # `step=0.5` borne la bande a UNE rangee par construction : un voisin de 1.00
                    # monte a 0.50, et le voisin de celui-la a 0.00. Le cuir chevelu au-dela n'est
                    # pas touche, et la rangee montee reste a moitie tenue par `head`.
                    ed = edges_by_key.get(key)
                    if not ed:
                        rep.append(f"  !! {r['target']}: aucune arete lisible — `grade` mesure un"
                                   f" VOISINAGE, il ne peut pas travailler sans les triangles")
                        continue
                    new = wt.copy()
                    for _ in range(r['iters']):
                        moved = 0.0
                        for (u, v) in ed:
                            hi, lo = (u, v) if new[u] > new[v] else (v, u)
                            d = new[hi] - new[lo] - r['step']
                            if d > 0.0:
                                new[lo] += d
                                moved += d
                        if moved <= 1e-9:
                            break
                    new = np.clip(new, 0.0, 1.0)
                    sup = new > wt + 1e-9          # la BANDE reellement graduee
                    if not sup.any():
                        rep.append(f"  -- {r['target']}: jonction deja graduee "
                                   f"(aucune marche > {r['step']})")
                        continue
                else:
                    # optional spatial dilation of the support, for a patch too small to be a volume
                    if r['grow'] > 0:
                        S = P[sup]
                        for vi in np.nonzero(~sup)[0]:
                            d = S - P[vi]
                            if float((d * d).sum(axis=1).min()) <= r['grow'] ** 2:
                                wt[vi] = 1e-6      # joins the support at the very bottom of the profile
                        sup = wt > 0

                    # Reference the profile on a high QUANTILE, not the max.  Normalising by the max
                    # lets a single fully-owned vertex define the scale: jak-hd's MhairA peaks at 0.99
                    # on one vertex while its mean is 0.364, so cap*(w/0.99)**shape landed BELOW the
                    # existing weight almost everywhere and the transfer moved nothing (measured:
                    # authority 0.364 -> 0.367).  p90 is robust to that outlier and still well inside
                    # the patch the artist painted.
                    s = np.clip(wt / wmax, 0.0, 1.0)
                    new = np.where(sup, r['cap'] * s ** r['shape'], 0.0)
                gain = np.maximum(new - wt, 0.0)
                if not (gain > 0).any():
                    rep.append(f"  -- {r['target']}: already at or above the target profile")
                    continue

                # a vertex may not have the target joint in its 4 slots yet (after grow=)
                slot = np.full(len(W), -1, dtype=np.int64)
                for c in range(J.shape[1]):
                    slot = np.where((J[:, c] == t) & (slot < 0), c, slot)
                need = (gain > 0) & (slot < 0)
                if need.any():
                    # steal the lightest slot
                    lightest = np.argmin(W, axis=1)
                    for vi in np.nonzero(need)[0]:
                        c = int(lightest[vi])
                        J[vi, c] = t
                        W[vi, c] = 0.0
                        slot[vi] = c

                # take the gain from the donors, proportionally to what they hold
                don = [idx[d] for d in r['donors'] if d in idx]
                took = np.zeros(len(W))
                for vi in np.nonzero(gain > 0)[0]:
                    avail = [(c, W[vi, c]) for c in range(J.shape[1])
                             if J[vi, c] in don and W[vi, c] > 0]
                    pool = sum(w for _, w in avail)
                    g = min(gain[vi], pool)
                    if g <= 0:
                        continue
                    for c, w in avail:
                        W[vi, c] -= g * (w / pool)
                    W[vi, slot[vi]] += g
                    took[vi] = g

                tot = W.sum(axis=1, keepdims=True)
                W = np.where(tot > 0, W / np.maximum(tot, 1e-12), W)
                after = W[np.arange(len(W)), np.maximum(slot, 0)]
                m0, m1 = float(wt[sup].mean()), float(after[sup].mean())
                rep.append(
                    f"  {r['target']:<10} verts={int(sup.sum())} p90 {wmax:.3f} "
                    f"mean {m0:.3f}->{m1:.3f} dominant {int((wt >= 0.5).sum())}->"
                    f"{int((after * sup >= 0.5).sum())} "
                    f"weight moved off {','.join(r['donors'])} = {took.sum():.1f}")
                # A rule that does not measurably move ownership is a rule that lies in the file.
                # Loud, not silent: the bake greps for '!!' and fails.
                if m1 - m0 < 0.05:
                    rep.append(f"  !! {r['target']}: transfer moved ownership by only "
                               f"{m1 - m0:+.3f} — the rule is inert, fix or drop it")

            acc_j = append_accessor(js, binc, J.astype(np.uint8), 5121, 'VEC4')
            acc_w = append_accessor(js, binc, W.astype(np.float32), 5126, 'VEC4')
            at['JOINTS_0'] = acc_j
            at['WEIGHTS_0'] = acc_w
            seen[key] = acc_w
    return rep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--model', required=True)
    ap.add_argument('--in', dest='inp', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--report', default='')
    a = ap.parse_args()

    cfg = load_cfg()
    rules = cfg.get(a.model, [])
    if not rules:
        print(f'[reskin] {a.model}: no rule — passthrough')
        if a.inp != a.out:
            open(a.out, 'wb').write(open(a.inp, 'rb').read())
        return 0

    js, bufs = read_glb(a.inp)
    binc = consolidate_buffers(js, bufs)
    rep = apply_model(js, binc, rules)
    binc = gc_glb(js, binc)
    write_glb(a.out, js, binc)
    txt = f'[reskin] {a.model}  {len(rules)} rule(s)\n' + '\n'.join(rep)
    print(txt)
    if a.report:
        open(a.report, 'w').write(txt + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
