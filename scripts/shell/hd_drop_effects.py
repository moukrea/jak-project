#!/usr/bin/env python3
# scripts/shell/hd_drop_effects.py — DERIVE, from the joints a character's drop-spec NAMES, the
# list of donor merc EFFECTS whose drawn geometry belongs entirely to that prop.
#
# WHY THIS EXISTS (Gbuild-from-scratch, owner 2026-08-29: « un utilisateur qui build le jeu from
# scratch devrait pouvoir avoir le meme etat que nous »).
# ---------------------------------------------------------------------------------------------
# The welding-mask prop is removed from the DELIVERED model in two places, and until now the two
# used two different kinds of criterion:
#   * its JOINTS, by NAME, from the committed `recharged_assets/<char>-drop-joints.txt`
#     (scripts/shell/hd_drop_joints.py) — a named criterion, reproducible;
#   * its DRAWN GEOMETRY, by hardcoded EFFECT INDEX, spelled out in build_enhanced_models.sh as
#     `--drop-effect 0 --drop-effect 5` (keira-hd) and `--drop-effect 1 --drop-effect 5`
#     (keira3-hd) — a "suppression ponctuelle": four integers, hand-verified once, that name
#     nothing and that no re-rip, no decompiler change and no donor-order change can invalidate
#     LOUDLY. They would just silently delete somebody else's effect.
# This script replaces the four integers with the SAME named criterion the joints already use:
#
#     CRITERION — an effect is dropped IFF every one of its draws is skinned exclusively to
#     joints named in <char>-drop-joints.txt (closure: a named joint takes its whole subtree).
#
# and refuses to answer at all when the data does not support that criterion cleanly:
#   * prim/draw count or per-prim triangle count mismatch  -> FAIL (the prim[i] <-> flat draw[i]
#     order invariant `hd_merc_swap stamp` asserts is what makes the mapping meaningful at all);
#   * a dropped joint carrying weight in a KEPT prim       -> FAIL (the prop is not self-contained,
#     so dropping its effects would delete geometry that is not the prop);
#   * an effect only PARTIALLY owned by the prop           -> FAIL (dropping it would delete a
#     draw that is not the prop; keeping it would leave the prop on screen).
# Every one of those is the failure the four hardcoded integers could not report.
#
# INPUTS
#   --glb    the donor rig GLB *before* hd_drop_joints.py has run (the prop joints must still be
#            in the skin — after the drop their vertices are re-bound to a surviving ancestor and
#            the prop is no longer identifiable by joint name).
#   --audit  the stdout of `hd_merc_swap audit <donor_fr3> <donor_model>`, which lists the donor's
#            effects in order with their draws and triangle counts. That order IS the flat draw
#            order `do_stamp` pairs with the GLB primitives (tools/hd_merc_swap/main.cpp:281-320).
#   --model  the donor merc model name to select inside that audit output.
#   --spec   recharged_assets/<char>-drop-joints.txt
#
# OUTPUT (stdout, last line, machine-readable; empty list is legal and means "nothing to drop"):
#   DROP-EFFECTS <i> <j> ...
import argparse
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from retarget_hd_models import read_glb, consolidate_buffers, read_accessor, skin_info  # noqa: E402


def read_spec(path):
    out = []
    for raw in open(path):
        line = raw.split('#', 1)[0].strip()
        if line:
            out.append(line)
    return out


def parse_audit(path, model):
    """-> list of (effect_index, num_triangles), in the donor's flat draw order."""
    flat, cur_model, cur_eff = [], None, None
    re_model = re.compile(r'^MODEL (\S+)\s')
    re_eff = re.compile(r'^\s+effect\[(\d+)\]')
    re_draw = re.compile(r'^\s+draw\[(\d+)\] tris=(\d+)')
    for raw in open(path):
        m = re_model.match(raw)
        if m:
            cur_model, cur_eff = m.group(1), None
            continue
        if cur_model != model:
            continue
        m = re_eff.match(raw)
        if m:
            cur_eff = int(m.group(1))
            continue
        m = re_draw.match(raw)
        if m and cur_eff is not None:
            flat.append((cur_eff, int(m.group(2))))
    return flat


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--glb', required=True)
    ap.add_argument('--spec', required=True)
    ap.add_argument('--audit', required=True)
    ap.add_argument('--model', required=True)
    ap.add_argument('--report', default=None)
    args = ap.parse_args()

    lines = [f'drop-effects derivation for model {args.model}',
             f'  rig   {args.glb}',
             f'  spec  {args.spec}',
             f'  audit {args.audit}']

    def emit(rc, tail=None):
        if tail:
            lines.append(tail)
        rep = '\n'.join(lines)
        print(rep)
        if args.report:
            open(args.report, 'w').write(rep + '\n')
        return rc

    wanted = read_spec(args.spec)
    if not wanted:
        return emit(2, f'  DROP-EFFECTS FAIL: {args.spec} names no joint')

    js, bufs = read_glb(args.glb)
    binc = consolidate_buffers(js, bufs)
    names, _ibms, parent = skin_info(js, binc)
    nj = len(names)
    name_to_j = {}
    for i, n in enumerate(names):
        name_to_j.setdefault(n, i)
    kids = {i: [] for i in range(nj)}
    for i, p in enumerate(parent):
        if p >= 0:
            kids[p].append(i)

    absent = [n for n in wanted if n not in name_to_j]
    drop_j = set()
    for n in wanted:
        if n not in name_to_j:
            continue
        stack = [name_to_j[n]]
        while stack:
            x = stack.pop()
            if x in drop_j:
                continue
            drop_j.add(x)
            stack += kids[x]
    if absent:
        lines.append(f'  joints already absent from this rig (idempotent): {absent}')
    if not drop_j:
        # Every named joint is gone: the rig has already been pruned, so the prop can no longer
        # be identified here. Saying "drop nothing" would silently ship the geometry.
        return emit(2, '  DROP-EFFECTS FAIL: no named joint is present in this rig — the criterion '
                       'cannot be evaluated (run this BEFORE hd_drop_joints.py, on the raw donor)')
    lines.append('  named joints, closed over their subtrees: '
                 + ', '.join(f'{names[j]}@{j}' for j in sorted(drop_j)))

    flat = parse_audit(args.audit, args.model)
    if not flat:
        return emit(2, f'  DROP-EFFECTS FAIL: no draw for MODEL {args.model} in {args.audit}')

    if len(js.get('meshes', [])) != 1:
        return emit(2, f'  DROP-EFFECTS FAIL: expected 1 mesh in the rip GLB, got '
                       f'{len(js.get("meshes", []))}')
    prims = js['meshes'][0]['primitives']
    if len(prims) != len(flat):
        return emit(2, f'  DROP-EFFECTS FAIL: {len(prims)} prims vs {len(flat)} donor draws — the '
                       'prim[i] <-> flat draw[i] order invariant is broken, refusing to derive')

    # per-prim: the set of skin joints carrying non-zero weight on the vertices it actually indexes
    acc_cache = {}

    def acc(i):
        if i not in acc_cache:
            acc_cache[i] = read_accessor(js, binc, i)
        return acc_cache[i]

    dropped_effects, kept_leak, partial = set(), [], []
    per_prim = []
    for pi, prim in enumerate(prims):
        eff, want_tris = flat[pi]
        idx = acc(prim['indices']).astype(np.int64).reshape(-1)
        tris = idx.size // 3
        if tris != want_tris:
            return emit(2, f'  DROP-EFFECTS FAIL: prim[{pi}] has {tris} tris but donor draw has '
                           f'{want_tris} — order invariant broken, refusing to derive')
        at = prim['attributes']
        if 'JOINTS_0' not in at or 'WEIGHTS_0' not in at:
            return emit(2, f'  DROP-EFFECTS FAIL: prim[{pi}] is not skinned (no JOINTS_0/WEIGHTS_0)')
        J = acc(at['JOINTS_0']).astype(np.int64)
        W = acc(at['WEIGHTS_0']).astype(np.float64)
        verts = np.unique(idx)
        used = set(int(j) for j in J[verts][W[verts] > 0.0])
        per_prim.append((pi, eff, tris, used))

    for pi, eff, tris, used in per_prim:
        whole = used.issubset(drop_j)
        touches = bool(used & drop_j)
        if whole:
            dropped_effects.add(eff)
        elif touches:
            kept_leak.append((pi, eff, sorted(names[j] for j in (used & drop_j))))

    if kept_leak:
        for pi, eff, js_ in kept_leak:
            lines.append(f'  !! prim[{pi}] (effect {eff}) is NOT wholly the prop yet carries weight '
                         f'from {js_}')
        return emit(2, '  DROP-EFFECTS FAIL: the named prop is not self-contained in its own '
                       'primitives — dropping its effects would delete geometry that is not the prop')

    for eff in sorted(dropped_effects):
        mine = [p for p in per_prim if p[1] == eff]
        not_prop = [p[0] for p in mine if not p[3].issubset(drop_j)]
        if not_prop:
            partial.append((eff, not_prop))
    if partial:
        for eff, ps in partial:
            lines.append(f'  !! effect {eff} is only PARTIALLY the prop — prims {ps} are not')
        return emit(2, '  DROP-EFFECTS FAIL: an effect mixes prop and non-prop draws; refusing to '
                       'derive an index list that would delete either too much or too little')

    for eff in sorted(dropped_effects):
        mine = [p for p in per_prim if p[1] == eff]
        lines.append(f'  effect {eff}: {len(mine)} draw(s), {sum(p[2] for p in mine)} tris, '
                     'every vertex weighted only to the named joints -> DROP')
    kept = sorted({p[1] for p in per_prim} - dropped_effects)
    lines.append(f'  effects kept: {kept}')
    return emit(0, 'DROP-EFFECTS ' + ' '.join(str(e) for e in sorted(dropped_effects)))


if __name__ == '__main__':
    sys.exit(main())
