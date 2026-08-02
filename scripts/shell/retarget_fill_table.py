#!/usr/bin/env python3
# retarget_fill_table.py — HD character ANIMATION-RETARGET pipeline, MILESTONE 1 (Jak).
#
# (1) Reuse the retarget NAME-MATCHER (scripts/shell/retarget_hd_models.py::build_joint_map)
#     to emit the k->e index table: HD game joint k -> eichar game joint e, 0xFF = no
#     counterpart. Because prep_hd_actor_glb.py keeps the fabricated game-joint index equal to
#     the rip skin index (align=0), and eichar loads normally, this table is in GAME JOINT
#     INDICES on both sides and is exactly what the companion's do-joint-math! needs.
#
# (2) OFFLINE NUMERIC PROOF of the companion's do-joint-math! fill (device-independent):
#         bone_hd[k].transform = M_eichar_anim[e] . inv_bind_eichar[e] . bind_hd[k]
#     then the stock bones-mtx-calc post-multiplies inv_bind_hd[k], giving palette_hd[k].
#     We synthesize an eichar animation (rigid rotation of the right-arm subtree), fill the HD
#     bones, skin real HD vertices, and measure:
#       PROOF A  palette_hd[k] == eichar skinning delta for every MAPPED joint  (exact follow)
#       PROOF B  HD verts on mapped+moved joints move; on mapped+still joints don't; on
#                UNMAPPED joints stay at rest (0 displacement).
#
# (3) Emit the k->e table as ready-to-paste GOAL static data + JSON to --emit-dir.
#
# Convention: GLB inverseBindMatrices = bind_pose_T_w (world -> bind-local) = joint.bind-pose
# in GOAL; bind = inverse(IBM). Work in GLB units throughout (the game's x4096/meters scale
# cancels in the delta).
import argparse
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from retarget_hd_models import (read_glb, consolidate_buffers, read_accessor,  # noqa: E402
                                skin_info, build_joint_map)


def load(p):
    js, b = read_glb(p)
    binc = consolidate_buffers(js, b)
    names, ibm, parent = skin_info(js, binc)
    return js, binc, names, np.array(ibm), parent


def descendants(par, root):
    ch = {i: [] for i in range(len(par))}
    for i, p in enumerate(par):
        if p >= 0:
            ch[p].append(i)
    out, stack = set(), [root]
    while stack:
        x = stack.pop()
        out.add(x)
        stack += ch[x]
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--hd', default='decompiler_out/jak2/levels/introcst/jakone-highres-lod0.glb')
    ap.add_argument('--eichar', default='decompiler_out/jak1/levels/common/eichar-lod0.glb')
    ap.add_argument('--emit-dir', default=None, help='write k2e.json + k2e.gc-snippet here')
    args = ap.parse_args()

    hjs, hbin, hn, h_ibm, hpar = load(args.hd)
    ejs, ebin, en, e_ibm, epar = load(args.eichar)
    h_bind = np.array([np.linalg.inv(m) for m in h_ibm])
    e_bind = np.array([np.linalg.inv(m) for m in e_ibm])

    mapping = build_joint_map(hn, en, hpar)
    k2e = np.full(len(hn), 0xFF, np.int32)
    tier = {}
    for k in range(len(hn)):
        _d, t, ti = mapping.get(k, (None, None, 0))
        if t is not None:
            k2e[k] = t
            tier[k] = ti
    mapped = int((k2e != 0xFF).sum())
    unmapped = [hn[k] for k in range(len(hn)) if k2e[k] == 0xFF]
    print(f'k->e map: {mapped}/{len(hn)} HD joints mapped; UNMAPPED({len(unmapped)}): {unmapped}')

    # synthesize eichar animation: rigid 40deg rotation of the right-arm subtree about 'Rarm'
    jr = en.index('Rarm')
    sub = descendants(epar, jr)
    th = np.deg2rad(40.0)
    c, s = np.cos(th), np.sin(th)
    Rloc = np.array([[1, 0, 0, 0], [0, c, -s, 0], [0, s, c, 0], [0, 0, 0, 1]], float)
    M = e_bind[jr] @ Rloc @ np.linalg.inv(e_bind[jr])
    e_anim = e_bind.copy()
    for d in sub:
        e_anim[d] = M @ e_bind[d]
    e_delta = np.array([e_anim[e] @ e_ibm[e] for e in range(len(en))])

    bone_hd = h_bind.copy()
    for k in range(len(hn)):
        e = k2e[k]
        if e != 0xFF:
            bone_hd[k] = e_anim[e] @ e_ibm[e] @ h_bind[k]
    palette_hd = np.array([bone_hd[k] @ h_ibm[k] for k in range(len(hn))])

    maxerr = 0.0
    for k in range(len(hn)):
        e = k2e[k]
        if e != 0xFF:
            maxerr = max(maxerr, float(np.abs(palette_hd[k] - e_delta[e]).max()))
    print(f'PROOF A  mapped palette == eichar delta : max abs err = {maxerr:.3e}  '
          f'({"PASS" if maxerr < 1e-6 else "FAIL"})')

    a0 = hjs['meshes'][0]['primitives'][0]['attributes']
    pos = read_accessor(hjs, hbin, a0['POSITION']).astype(np.float64)
    J = read_accessor(hjs, hbin, a0['JOINTS_0']).astype(np.int64)
    W = read_accessor(hjs, hbin, a0['WEIGHTS_0']).astype(np.float64)

    def skin_disp(vidx):
        v = np.array([pos[vidx, 0], pos[vidx, 1], pos[vidx, 2], 1.0])
        out = np.zeros(4)
        wsum = 0.0
        for sl in range(4):
            w = W[vidx, sl]
            if w <= 0:
                continue
            out += w * (palette_hd[int(J[vidx, sl])] @ v)
            wsum += w
        if wsum > 0:
            out /= wsum
        return float(np.linalg.norm(out[:3] - v[:3]))

    def dom(vidx):
        return int(J[vidx, int(np.argmax(W[vidx]))])

    sub_hd = set(k for k in range(len(hn)) if k2e[k] != 0xFF and k2e[k] in sub)
    still_hd = set(k for k in range(len(hn)) if k2e[k] != 0xFF and k2e[k] not in sub)
    unmapped_hd = set(k for k in range(len(hn)) if k2e[k] == 0xFF)

    def sample(js_set, label, want_move):
        ds = []
        for vidx in range(len(pos)):
            if W[vidx].sum() > 0 and dom(vidx) in js_set:
                ds.append(skin_disp(vidx))
            if len(ds) >= 400:
                break
        if not ds:
            print(f'  {label:34s}: (no verts)')
            return
        ds = np.array(ds)
        print(f'  {label:34s}: n={len(ds):4d} mean|disp|={ds.mean():.4f} max={ds.max():.4f} '
              f'({"moves" if want_move else "REST"} expected)')

    print('PROOF B  HD vertex displacement bind->animated, by joint class:')
    sample(sub_hd, 'mapped->moved arm subtree', True)
    sample(still_hd, 'mapped->still rest of body', False)
    sample(unmapped_hd, 'UNMAPPED HD joints', False)

    if args.emit_dir:
        os.makedirs(args.emit_dir, exist_ok=True)
        rows = [{'k': int(k), 'hd_name': hn[k],
                 'e': (None if k2e[k] == 0xFF else int(k2e[k])),
                 'e_name': (None if k2e[k] == 0xFF else en[int(k2e[k])]),
                 'tier': tier.get(k, 0)} for k in range(len(hn))]
        json.dump({'hd_glb': args.hd, 'eichar_glb': args.eichar,
                   'num_hd_joints': len(hn), 'mapped': mapped, 'rows': rows},
                  open(os.path.join(args.emit_dir, 'jak-hd-k2e.json'), 'w'), indent=1)
        vals = ' '.join(str(int(x)) for x in k2e)
        gc = (';; jak-hd retarget map: HD game joint index -> eichar game joint index (255=none).\n'
              ';; generated by scripts/shell/retarget_fill_table.py — do not hand-edit.\n'
              f'(define *jak-hd->eichar-joint* (new \'static \'array uint8 {len(hn)}\n'
              f'  {vals}))\n')
        open(os.path.join(args.emit_dir, 'jak-hd-k2e.gc-snippet'), 'w').write(gc)
        print(f'emitted k2e table -> {args.emit_dir}/jak-hd-k2e.json + .gc-snippet ({len(hn)} joints)')


if __name__ == '__main__':
    main()
