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
    """-> {model: [dict(target, donors, cap, shape, grow)]}"""
    out, cur = {}, []
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
        if f[0] != 'transfer' or not cur:
            continue
        kv = dict(x.split('=', 1) for x in f[2:] if '=' in x)
        r = dict(target=f[1],
                 donors=[d for d in kv.get('from', '').split(',') if d],
                 cap=float(kv.get('cap', 0.9)),
                 shape=float(kv.get('shape', 1.0)),
                 grow=float(kv.get('grow', 0.0)))
        for x in cur:
            out[x].append(r)
    return out


def apply_model(js, binc, rules, verbose=True):
    """Rewrite WEIGHTS_0 in place for every primitive.  Returns a list of report lines."""
    names, _, _ = skin_info(js, binc)
    idx = {n: i for i, n in enumerate(names)}
    rep = []

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

                # optional spatial dilation of the support, for a patch too small to be a volume
                if r['grow'] > 0:
                    S = P[sup]
                    for vi in np.nonzero(~sup)[0]:
                        d = S - P[vi]
                        if float((d * d).sum(axis=1).min()) <= r['grow'] ** 2:
                            wt[vi] = 1e-6          # joins the support at the very bottom of the profile
                    sup = wt > 0

                # Reference the profile on a high QUANTILE, not the max.  Normalising by the max
                # lets a single fully-owned vertex define the scale: jak-hd's MhairA peaks at 0.99
                # on one vertex while its mean is 0.364, so cap*(w/0.99)**shape landed BELOW the
                # existing weight almost everywhere and the transfer moved nothing (measured:
                # authority 0.364 -> 0.367).  p90 is robust to that outlier and still well inside
                # the patch the artist painted.
                wmax = float(np.quantile(wt[sup], 0.90))
                if wmax <= 1e-6:
                    wmax = float(wt.max())
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
