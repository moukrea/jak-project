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
    # --driver is the new name (any driver/companion rig); --eichar kept as deprecated alias.
    ap.add_argument('--driver', '--eichar', dest='driver',
                    default='decompiler_out/jak1/levels/common/eichar-lod0.glb')
    ap.add_argument('--name', default='jak-hd',
                    help='character name: drives <name>-k2e.json/.gc-snippet + the GOAL symbol')
    ap.add_argument('--emit-dir', default=None, help='write k2e.json + k2e.gc-snippet here')
    ap.add_argument('--map', action='append', default=[],
                    help='explicit HDjoint=DRIVERjoint pair(s), comma-separable, applied AFTER '
                         'name matching (tier 0 = authored). The class-D fix lane: beard/hair/'
                         'tongue chains whose names differ across games get REAL driver chains, '
                         'not an ancestor glue.')
    ap.add_argument('--accept-unmapped', action='append', default=[],
                    help="HDjointRegex=reason. The ONLY way a FACE/FINGER HD joint may stay on "
                         "ancestor fallback: an explicit, per-chain justification (owner "
                         "2026-08-04 ~11:30 definition-of-done). Recorded in the JSON output.")
    args = ap.parse_args()

    hjs, hbin, hn, h_ibm, hpar = load(args.hd)
    ejs, ebin, en, e_ibm, epar = load(args.driver)
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

    # authored explicit pairs override the name matcher (tier 0 = authored, strongest)
    e_index = {n: i for i, n in enumerate(en)}
    h_index = {n: i for i, n in enumerate(hn)}
    for spec in [s for arg in args.map for s in arg.split(',') if s]:
        src, dst = spec.split('=')
        if src not in h_index:
            print(f'FACE-FINGER-GATE {args.name}: FAIL --map {spec}: HD joint {src!r} not in rig')
            sys.exit(2)
        if dst not in e_index:
            print(f'FACE-FINGER-GATE {args.name}: FAIL --map {spec}: driver joint {dst!r} not in rig')
            sys.exit(2)
        k2e[h_index[src]] = e_index[dst]
        tier[h_index[src]] = 0

    mapped = int((k2e != 0xFF).sum())
    unmapped = [hn[k] for k in range(len(hn)) if k2e[k] == 0xFF]
    print(f'k->e map: {mapped}/{len(hn)} HD joints mapped; UNMAPPED({len(unmapped)}): {unmapped}')

    # ---- FACE-FINGER-GATE (owner definition-of-done, 2026-08-04 ~11:30) -------------------------
    # A character is NOT backported if face/finger chains ride an ancestor fallback (tier 4: glued
    # rigid at BIND pose -> Samos' forward beard, frozen faces) or are unmapped. Fail LOUDLY unless
    # each such joint carries an explicit --accept-unmapped justification.
    import re as _re
    FACE_RE = _re.compile(r'jaw|chin|mouth|tongue|teeth|tooth|lip|brow|cheek|uvula|nose|eyelid'
                          r'|eye|blink|face|smile|frown', _re.I)
    FINGER_RE = _re.compile(r'pinky|ring[A-Z0-9]|ring$|index|thumb|finger|middle', _re.I)
    BEARD_RE = _re.compile(r'beard|goatee|moustache|mustache', _re.I)  # owner DoD pt.5: extremity chains
    accepts = []
    for spec in [s for arg in args.accept_unmapped for s in arg.split(';') if s]:
        rx, _, why = spec.partition('=')
        accepts.append((_re.compile(rx), why or '(no reason given)'))
    violations, accepted = [], []
    for k in range(len(hn)):
        cat = ('face' if FACE_RE.search(hn[k]) else
               'finger' if FINGER_RE.search(hn[k]) else
               'beard' if BEARD_RE.search(hn[k]) else None)
        if cat is None:
            continue
        if tier.get(k, 0) in (0, 1, 2, 3) and k2e[k] != 0xFF:
            continue  # real (name- or author-derived) driver counterpart
        why = next((w for rx, w in accepts if rx.search(hn[k])), None)
        if why is not None:
            accepted.append((hn[k], cat, why))
        else:
            violations.append((hn[k], cat, tier.get(k, 0)))
    for nm, cat, ti in violations:
        print(f'FACE-FINGER-GATE {args.name}: VIOLATION {cat} joint {nm!r} tier={ti} '
              f'(ancestor-glue/unmapped) — map it (--map {nm}=<driverJoint>) or justify it '
              f'(--accept-unmapped "{nm}=<why>")')
    if violations:
        print(f'FACE-FINGER-GATE {args.name}: FAIL ({len(violations)} face/finger joints without a '
              f'real driver counterpart)')
        sys.exit(2)
    print(f'FACE-FINGER-GATE {args.name}: PASS '
          f'(face/finger joints all driver-mapped; accepted-unmapped={len(accepted)}'
          + (': ' + ', '.join(f'{n}[{w}]' for n, _c, w in accepted) if accepted else '') + ')')

    # synthesize a driver animation: rigid 40deg rotation of the subtree under a PROOF JOINT.
    # Not every rig has 'Rarm' (jak2/jak3 donors differ), so pick the first candidate present in
    # BOTH skeletons; if none matches, fall back to the highest-index driver joint that is the
    # mapped target of some HD joint (guarantees a non-empty mapped-and-moved class).
    PROOF_CANDIDATES = ['Rarm', 'Larm', 'Rshoulder', 'Lshoulder', 'Rthigh', 'Lthigh',
                        'chest', 'spine', 'neck', 'head']
    jr = None
    for cand in PROOF_CANDIDATES:
        if cand in hn and cand in en:
            jr = en.index(cand)
            break
    if jr is None:
        targets = [int(k2e[k]) for k in range(len(hn)) if k2e[k] != 0xFF]
        if not targets:
            print('PROOF: no HD joint is mapped at all — cannot pick a proof joint')
            sys.exit(1)
        jr = max(targets)
        print(f'proof joint: {en[jr]} (driver index {jr}) [fallback: no candidate in both rigs]')
    else:
        print(f'proof joint: {en[jr]} (driver index {jr})')
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
        json.dump({'hd_glb': args.hd, 'eichar_glb': args.driver,
                   'num_hd_joints': len(hn), 'mapped': mapped, 'rows': rows,
                   'authored_maps': [s for arg in args.map for s in arg.split(',') if s],
                   'accepted_unmapped': [{'joint': n, 'cat': c, 'reason': w}
                                         for n, c, w in accepted]},
                  open(os.path.join(args.emit_dir, f'{args.name}-k2e.json'), 'w'), indent=1)
        vals = ' '.join(str(int(x)) for x in k2e)
        # legacy symbol kept verbatim for jak-hd (goal_src/.../jak-hd.gc already references it).
        sym = '*jak-hd->eichar-joint*' if args.name == 'jak-hd' else f'*{args.name}->driver-joint*'
        word = 'eichar' if args.name == 'jak-hd' else 'driver'
        gc = (f';; {args.name} retarget map: HD game joint index -> {word} game joint index (255=none).\n'
              ';; generated by scripts/shell/retarget_fill_table.py — do not hand-edit.\n'
              f'(define {sym} (new \'static \'array uint8 {len(hn)}\n'
              f'  {vals}))\n')
        open(os.path.join(args.emit_dir, f'{args.name}-k2e.gc-snippet'), 'w').write(gc)
        print(f'emitted k2e table -> {args.emit_dir}/{args.name}-k2e.json + .gc-snippet ({len(hn)} joints)')


if __name__ == '__main__':
    main()
