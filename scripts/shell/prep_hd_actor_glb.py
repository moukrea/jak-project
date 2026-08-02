#!/usr/bin/env python3
# prep_hd_actor_glb.py — HD character ANIMATION-RETARGET pipeline, MILESTONE 1 (Jak).
#
# Convert a decompiler-ripped HD character GLB (fr3_to_gltf.cpp foreground export) into a
# form the EXISTING `build_actor` emitter (goalc/build_actor -> *-ag.go) accepts, WITHOUT
# re-rigging. The HD model KEEPS ITS OWN SKELETON + AUTHORED WEIGHTS — that is the whole
# point of the animation-retarget design: hidden eichar drives the animation, the visible HD
# skin has its own bones, and a companion process fills the HD bones from eichar per frame.
#
# This is DISTINCT from scripts/shell/retarget_hd_models.py, which RE-RIGS the HD mesh onto
# the jak1 eichar skeleton (the "merc swap" brick approach). Here we do NOT re-rig.
#
# The rip GLB and build_actor disagree on three conventions; this tool bridges them:
#   1. JOINTS_0 component type: the rip writes u32 (5125); build_actor wants u8 (5121).
#   2. The synthetic "align" joint: the rip skin INCLUDES align at skin index 0, but
#      build_actor::convert_joints PREPENDS its own synthetic align and treats gltf joint 0
#      as the "prejoint". So we DROP align (skin index 0) and decrement joint indices, which
#      reproduces the game's (align, prejoint, main, ...) joint numbering exactly. As a result
#      the fabricated game-joint index == the ORIGINAL rip skin joint index (align stays 0).
#   3. The rip shares ONE level-wide vertex POOL across every model in the level; a model's
#      prims only index into it. We COMPACT to the vertices this model actually uses.
#
# Everything else (positions, authored normals, UVs, colours, the HD skeleton IBMs/tree, the
# authored per-vertex weights) is preserved. build_actor then fabricates a valid art-group .go
# (art-joint-geo = HD bind poses + tree + names; merc-ctrl shell; identity art-joint-anim).
#
# Usage:
#   python3 prep_hd_actor_glb.py --in <ripped-hd>.glb --out <prepped>.glb [--report r.txt]
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from retarget_hd_models import (read_glb, consolidate_buffers, read_accessor,  # noqa: E402
                                append_accessor, write_glb, gc_glb, skin_info)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='inp', required=True, help='ripped HD GLB (fr3_to_gltf export)')
    ap.add_argument('--out', required=True, help='build_actor-ready GLB')
    ap.add_argument('--report', default=None)
    args = ap.parse_args()

    js, bufs = read_glb(args.inp)
    binc = consolidate_buffers(js, bufs)
    js.pop('animations', None)

    names, ibms, parent = skin_info(js, binc)
    ibms = np.array(ibms)
    assert names[0] == 'align', f'expected skin joint 0 == align, got {names[0]}'

    prims = []
    for mesh in js['meshes']:
        prims.extend(mesh['primitives'])
    a0 = prims[0]['attributes']
    pos = read_accessor(js, binc, a0['POSITION']).astype(np.float32)
    nrm = read_accessor(js, binc, a0['NORMAL']).astype(np.float32)
    J = read_accessor(js, binc, a0['JOINTS_0']).astype(np.int64)
    W = read_accessor(js, binc, a0['WEIGHTS_0']).astype(np.float32)
    uv = read_accessor(js, binc, a0['TEXCOORD_0']).astype(np.float32) if 'TEXCOORD_0' in a0 else None
    col_ct = js['accessors'][a0['COLOR_0']]['componentType'] if 'COLOR_0' in a0 else None
    col = read_accessor(js, binc, a0['COLOR_0']) if 'COLOR_0' in a0 else None
    for p in prims:
        assert p['attributes']['POSITION'] == a0['POSITION'], 'prims do not share the pool'

    # 1) compact to the vertices THIS model uses (union of its prim indices)
    prim_tris = [read_accessor(js, binc, p['indices']).reshape(-1, 3) for p in prims]
    used = np.unique(np.concatenate([t.reshape(-1) for t in prim_tris]))
    old2new = np.full(len(pos), -1, np.int64)
    old2new[used] = np.arange(len(used))
    prim_tris = [old2new[t] for t in prim_tris]
    pos, nrm, J, W = pos[used], nrm[used], J[used], W[used]
    if uv is not None:
        uv = uv[used]
    if col is not None:
        col = col[used]
    n_verts = len(pos)

    # sanity: no weight on align(0)/prejoint(1) — dropping align must be lossless
    for jid in (0, 1):
        m = (J == jid) & (W > 0)
        assert not m.any(), f'model has vertices weighted to skin joint {jid} ({names[jid]}) — cannot drop align'

    # 2) drop align (skin index 0), decrement joint indices. zero-weight slots -> 0.
    out_j = np.zeros((n_verts, 4), np.uint8)
    out_w = W.astype(np.float32).copy()
    for s in range(4):
        pos_w = W[:, s] > 0
        out_j[pos_w, s] = (J[pos_w, s] - 1).astype(np.uint8)
        out_w[~pos_w, s] = 0.0
    assert int(J[W > 0].min()) >= 2, 'a positive-weight slot referenced align/prejoint'

    # 3) rebuild the skin without align: new joint i = old joint i+1; parents decremented.
    new_names = names[1:]
    new_parent = [(p - 1) if p >= 1 else -1 for p in parent[1:]]
    node_off = len(js['nodes'])
    kids = {i: [] for i in range(len(new_names))}
    for i, p in enumerate(new_parent):
        if p >= 0:
            kids[p].append(i)
    for i, nm in enumerate(new_names):
        nn = {'name': nm}
        if kids[i]:
            nn['children'] = [node_off + c for c in kids[i]]
        js['nodes'].append(nn)
    new_ibm_colmajor = np.zeros((len(new_names), 16), np.float32)
    for i in range(len(new_names)):
        new_ibm_colmajor[i] = ibms[i + 1].T.reshape(-1).astype(np.float32)  # ibms row-major -> glTF col-major
    new_ibm_acc = append_accessor(js, binc, new_ibm_colmajor, 5126, 'MAT4')
    js['skins'] = [{'joints': [node_off + i for i in range(len(new_names))],
                    'skeleton': node_off,
                    'inverseBindMatrices': new_ibm_acc}]

    # attach the new skin to the mesh node(s); strip stale extras
    for node in js['nodes']:
        if 'mesh' in node:
            node['skin'] = 0
            node.pop('extras', None)

    # 4) write compacted attributes and re-point prims
    acc_pos = append_accessor(js, binc, pos, 5126, 'VEC3', minmax=True)
    acc_nrm = append_accessor(js, binc, nrm, 5126, 'VEC3')
    acc_j = append_accessor(js, binc, out_j, 5121, 'VEC4')
    acc_w = append_accessor(js, binc, out_w, 5126, 'VEC4')
    acc_uv = append_accessor(js, binc, uv, 5126, 'VEC2') if uv is not None else None
    acc_col = append_accessor(js, binc, col, col_ct, 'VEC4') if col is not None else None
    for p, tris in zip(prims, prim_tris):
        p['indices'] = append_accessor(js, binc, tris.reshape(-1, 1).astype(np.uint32), 5125, 'SCALAR')
        at = p['attributes']
        at['POSITION'] = acc_pos
        at['NORMAL'] = acc_nrm
        at['JOINTS_0'] = acc_j
        at['WEIGHTS_0'] = acc_w
        if acc_uv is not None:
            at['TEXCOORD_0'] = acc_uv
        if acc_col is not None:
            at['COLOR_0'] = acc_col

    binc = gc_glb(js, binc)
    write_glb(args.out, js, binc)

    lines = [f'prep {args.inp} -> {args.out}',
             f'  verts={n_verts} (compacted from the level pool) prims={len(prims)}',
             f'  skin joints: {len(names)} (with align) -> {len(new_names)} (align dropped; build_actor re-adds it)',
             f'  JOINTS_0 u32->u8, decremented; fabricated game joints: [align, {new_names[0]}, {new_names[1]}, ...]',
             f'  positive-weight joint idx range (post-drop): {int(out_j[out_w>0].min())}..{int(out_j[out_w>0].max())}']
    rep = '\n'.join(lines)
    print(rep)
    if args.report:
        open(args.report, 'w').write(rep + '\n')


if __name__ == '__main__':
    main()
