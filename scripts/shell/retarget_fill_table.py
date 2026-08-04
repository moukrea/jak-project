#!/usr/bin/env python3
# retarget_fill_table.py — HD character ANIMATION-RETARGET pipeline, MILESTONE 1 (Jak).
#
# v2: PER-JOINT RETARGET MODE (world-delta / local-delta / glue).
#   mode 0 WORLD-DELTA (legacy)  W_k = A_e . inv(C_e) . B_k
#     exact when the HD and driver bind PIVOTS coincide; tears chains when they don't
#     (measured: Keira mid-finger pivot error 0.05-0.085 > phalanx length; jak1 sage
#     beard_lip bind pivot parked 0.86 away from the HD beard root).
#   mode 1 LOCAL-DELTA MAPPED     W_k = W_par_hd(k) . L_k . Delta_e
#     the driver joint's LOCAL delta replayed at the HD joint's OWN pivot: bone lengths
#     and proportions are the HD rig's, motion is the driver's.
#   mode 2 LOCAL-DELTA GLUE       W_k = W_par_hd(k) . L_k
#     no real driver counterpart (tier-4 ancestor fallback / unmapped): the joint keeps its
#     bind-local transform under its already-retargeted HD parent (rides the chain, no tear).
#   with  B = HD bind world, C = driver bind world, A = driver animated world,
#         L_k = inv(B_par_hd(k)) . B_k,
#         Delta_e = inv(C_e) . C_par(e) . inv(A_par(e)) . A_e.
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

    import re as _re
    FACE_RE = _re.compile(r'jaw|chin|mouth|tongue|teeth|tooth|lip|brow|cheek|uvula|nose|eyelid'
                          r'|eye|blink|face|smile|frown', _re.I)
    FINGER_RE = _re.compile(r'pinky|ring[A-Z0-9]|ring$|index|thumb|finger|middle', _re.I)
    BEARD_RE = _re.compile(r'beard|goatee|moustache|mustache', _re.I)  # owner DoD pt.5: extremity chains
    # proportion-sensitive chains: same class-D failure as beards (pivots differ across games)
    CHAIN_RE = _re.compile(r'hair|bang|strap|tail|ear|flap|tongue|uvula', _re.I)
    # root/spine safety: these MUST stay world-delta so the body stays glued to the driver's
    # world positions (local-delta on the spine would let HD proportions drift the whole body).
    SAFE_RE = _re.compile(r'main|spine|chest|hips|pelvis|neck$|head$|collar|shoulder|thigh'
                          r'|knee|ankle|foot|elbow|arm$|hand$', _re.I)
    nh = len(hn)

    # ---- PER-JOINT RETARGET MODE ---------------------------------------------------------------
    def _cat(nm):
        return ('face' if FACE_RE.search(nm) else
                'finger' if FINGER_RE.search(nm) else
                'beard' if BEARD_RE.search(nm) else
                'chain' if CHAIN_RE.search(nm) else None)

    hpos = np.array([h_bind[k][:3, 3] for k in range(nh)])
    epos = np.array([e_bind[e][:3, 3] for e in range(len(en))])
    mode = np.zeros(nh, np.int32)
    reason = {}
    for k in range(nh):
        nm, ti, e = hn[k], tier.get(k, 0), int(k2e[k])
        cat = _cat(nm)
        if e != 0xFF and ti == 0:                      # (a) authored --map pair
            mode[k], reason[k] = 1, f'authored --map -> {en[e]}'
            continue
        if e == 0xFF:                                  # no counterpart at all
            mode[k], reason[k] = 2, 'unmapped (no driver counterpart)'
            continue
        if ti == 4:                                    # (b) ancestor fallback = not a real match
            mode[k], reason[k] = 2, f'tier4 ancestor fallback (would glue to {en[e]})'
            continue
        # (c) name-matched tier 1-3
        blen = float(np.linalg.norm(hpos[k] - hpos[hpar[k]])) if hpar[k] >= 0 else 0.0
        perr = float(np.linalg.norm(hpos[k] - epos[e]))
        thr = max(0.02, 0.25 * blen)
        if cat is not None:
            # (d) root/spine safety never applies to proportion-sensitive categories: the gate
            # below REQUIRES face/finger/beard joints to be mode 1, so the category wins.
            mode[k], reason[k] = 1, (f'{cat}-class (proportion-sensitive) -> {en[e]} '
                                     f'pivot_err={perr:.4f} bone={blen:.4f}')
        elif (nm == 'align' and k == 0) or (nm == 'prejoint' and k == 1) or SAFE_RE.search(nm):
            mode[k] = 0
        elif perr > thr:
            mode[k], reason[k] = 1, (f'pivot_err={perr:.4f} > thr={thr:.4f} '
                                     f'(bone={blen:.4f}) vs {en[e]}')
        else:
            mode[k] = 0
    ncens = [int((mode == m).sum()) for m in (0, 1, 2)]
    print(f'MODES {args.name}: world={ncens[0]} local={ncens[1]} glue={ncens[2]}')
    for k in range(nh):
        if mode[k] != 0:
            print(f'  mode{mode[k]} k={k:3d} {hn[k]:<24s} tier={tier.get(k, 0)} : {reason[k]}')

    # ---- PARENT ARRAYS + processing-order assert ------------------------------------------------
    hd_parent = np.array([hpar[k] if hpar[k] >= 0 else 255 for k in range(nh)], np.int32)
    drv_parent = np.full(nh, 255, np.int32)
    for k in range(nh):
        if mode[k] == 1:
            pe = epar[int(k2e[k])]
            drv_parent[k] = pe if pe >= 0 else 255
    bad_order = [k for k in range(nh) if mode[k] != 0 and hpar[k] >= 0 and hpar[k] >= k]
    for k in bad_order:
        print(f'PARENT-ORDER {args.name}: VIOLATION joint k={k} {hn[k]!r} mode={mode[k]} has '
              f'hd_parent={hpar[k]} >= k — parent-before-child fill order is impossible')
    if bad_order:
        print(f'PARENT-ORDER {args.name}: FAIL ({len(bad_order)} joints)')
        sys.exit(2)
    rootish = [k for k in range(nh) if mode[k] != 0 and hpar[k] < 0]
    print(f'PARENT-ORDER {args.name}: PASS (all {ncens[1] + ncens[2]} local/glue joints have '
          f'hd_parent < k' + (f'; {len(rootish)} parentless: '
                              f'{[hn[k] for k in rootish]}' if rootish else '') + ')')

    # ---- FACE-FINGER-GATE (owner definition-of-done, 2026-08-04 ~11:30) -------------------------
    # A character is NOT backported if face/finger chains ride an ancestor fallback (tier 4: glued
    # rigid at BIND pose -> Samos' forward beard, frozen faces) or are unmapped. Fail LOUDLY unless
    # each such joint carries an explicit --accept-unmapped justification.
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
        if mode[k] == 1 and k2e[k] != 0xFF and tier.get(k, 0) in (0, 1, 2, 3):
            continue  # real (name- or author-derived) driver counterpart, retargeted local-delta
        why = next((w for rx, w in accepts if rx.search(hn[k])), None)
        if why is not None:
            accepted.append((hn[k], cat, why))
        else:
            violations.append((hn[k], cat, tier.get(k, 0), int(mode[k])))
    for nm, cat, ti, mo in violations:
        print(f'FACE-FINGER-GATE {args.name}: VIOLATION {cat} joint {nm!r} tier={ti} mode={mo} '
              f'(ancestor-glue/unmapped) — map it (--map {nm}=<driverJoint>) or justify it '
              f'(--accept-unmapped "{nm}=<why>")')
    if violations:
        # the retarget MATH is independent of the mapping-completeness policy: run and print the
        # proofs first, then fail. Exit code is unchanged (2) and nothing is ever emitted.
        print(f'FACE-FINGER-GATE {args.name}: FAIL ({len(violations)} face/finger joints without a '
              f'real driver counterpart) — proofs below, then exit 2, no table emitted')
    else:
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

    # ---- PROOF C: mixed-mode fill (world/local/glue) --------------------------------------------
    # The tearing signature of world-delta on mismatched pivots is a CHANGE OF BONE LENGTH; the
    # local-delta modes must preserve every HD bone length exactly while still following the
    # driver's rotation.
    def fill_mixed(a_e):
        """full k-loop fill, parent-before-child; returns HD bone world matrices W_k."""
        Wm = np.zeros((nh, 4, 4))
        for k in range(nh):
            p = hpar[k]
            Wp = Wm[p] if p >= 0 else np.eye(4)
            Lk = (np.linalg.inv(h_bind[p]) @ h_bind[k]) if p >= 0 else h_bind[k].copy()
            if mode[k] == 0:
                e = int(k2e[k])
                Wm[k] = a_e[e] @ e_ibm[e] @ h_bind[k]
            elif mode[k] == 1:
                e = int(k2e[k])
                pe = epar[e]
                if pe >= 0:
                    De = e_ibm[e] @ e_bind[pe] @ np.linalg.inv(a_e[pe]) @ a_e[e]
                else:
                    De = e_ibm[e] @ a_e[e]
                Wm[k] = Wp @ Lk @ De
            else:
                Wm[k] = Wp @ Lk
        return Wm

    # pick the rotated driver joint: a FINGER joint that some mode-1 HD joint maps onto (the
    # class the local-delta mode exists for), else the highest-index mode-1 driver target.
    m1_targets = sorted({int(k2e[k]) for k in range(nh) if mode[k] == 1})
    if m1_targets:
        fings = [e for e in m1_targets if FINGER_RE.search(en[e])]
        if fings:
            jc = sorted(fings, key=lambda e: (-len(descendants(epar, e)), e))[0]
            why_c = 'finger joint (mode-1 mapped)'
        else:
            jc = max(m1_targets)
            why_c = 'highest-index mode-1 mapped driver joint (no shared finger joint)'
    else:
        jc = jr
        why_c = 'no mode-1 joint at all — reusing the PROOF A joint'
    print(f'PROOF C  rotated driver joint: {en[jc]} (driver index {jc}) [{why_c}], 40deg')
    subc = descendants(epar, jc)
    Mc = e_bind[jc] @ Rloc @ np.linalg.inv(e_bind[jc])
    e_animc = e_bind.copy()
    for d in subc:
        e_animc[d] = Mc @ e_bind[d]
    Wc = fill_mixed(e_animc)
    # which HD joints are driven (directly or through an hd-ancestor) by the rotated subtree
    moved = np.zeros(nh, bool)
    for k in range(nh):
        p = hpar[k]
        into = mode[k] != 2 and int(k2e[k]) != 0xFF and int(k2e[k]) in subc
        moved[k] = bool(into or (p >= 0 and moved[p]))

    # (a) BONE-LENGTH PRESERVATION over every local/glue joint
    blen_err, blen_worst, blen_n = 0.0, None, 0
    for k in range(nh):
        p = hpar[k]
        if mode[k] == 0 or p < 0:
            continue
        blen_n += 1
        got = float(np.linalg.norm(Wc[k][:3, 3] - Wc[p][:3, 3]))
        want = float(np.linalg.norm(h_bind[k][:3, 3] - h_bind[p][:3, 3]))
        if abs(got - want) > blen_err:
            blen_err, blen_worst = abs(got - want), (hn[k], want, got)
    ok_a = blen_err < 1e-6
    print(f'PROOF C(a) bone-length preservation over {blen_n} local/glue joints: '
          f'max abs err = {blen_err:.3e}  ({"PASS" if ok_a else "FAIL"})'
          + ('' if ok_a or blen_worst is None else
             f'  worst {blen_worst[0]!r} bind={blen_worst[1]:.6f} anim={blen_worst[2]:.6f}'))

    # (b) FOLLOW: HD joints whose ENTIRE hd-parent chain up to the subtree entry is mode-1 mapped
    # inside the rotated subtree must have their bone vector rotated by exactly the applied
    # rotation. The applied rotation is expressed in the ENTRY joint's own bind frame (that is the
    # whole point of local-delta: the pivot is the HD joint's), so the HD-world rotation is
    # G = B_entry . Rloc . inv(B_entry) — conjugated in the HD entry frame, not the driver one.
    inside = [k for k in range(nh) if mode[k] == 1 and int(k2e[k]) in subc]
    inside_set = set(inside)
    entry, foll = {}, []
    for k in inside:
        if hpar[k] < 0 or hpar[k] not in inside_set:
            continue                       # entry joint itself: its own bone does not rotate
        chain, a = [], hpar[k]             # walk up while parents stay mode-1-inside
        while a >= 0 and a in inside_set:
            chain.append(a)
            a = hpar[a]
        k0 = chain[-1]
        # the chain entry must be the HD counterpart of the ROTATED driver joint (it carries the
        # 40deg local delta); every joint below it carries Delta = identity.
        if int(k2e[k0]) != jc or any(int(k2e[j]) == jc for j in chain[:-1] + [k]):
            continue
        if hpar[k0] >= 0 and moved[hpar[k0]]:
            continue                       # ancestor above the entry also moves: not a clean case
        entry[k] = k0
        foll.append(k)
    if not foll:
        print('PROOF C(b) FOLLOW: no HD joint has its full hd-parent chain mode-1-mapped inside '
              'the rotated subtree (entry joints only) — nothing to check; relying on (a)+(c)')
    else:
        ferr = 0.0
        for k in foll:
            p = hpar[k]
            G = h_bind[entry[k]] @ Rloc @ np.linalg.inv(h_bind[entry[k]])
            vb = h_bind[k][:3, 3] - h_bind[p][:3, 3]
            va = Wc[k][:3, 3] - Wc[p][:3, 3]
            ferr = max(ferr, float(np.linalg.norm(va - G[:3, :3] @ vb)))
        print(f'PROOF C(b) FOLLOW: {len(foll)} in-subtree HD bones rotate by exactly the applied '
              f'40deg: max abs err = {ferr:.3e}  ({"PASS" if ferr < 1e-6 else "FAIL"})')

    # (c) STILLNESS: mode-1 joints with NO ancestor-or-self driving into the rotated subtree
    stillk = [k for k in range(nh) if mode[k] == 1 and not moved[k]]
    if not stillk:
        print('PROOF C(c) STILLNESS: no still mode-1 joint to check')
    else:
        serr = max(float(np.linalg.norm(Wc[k][:3, 3] - h_bind[k][:3, 3])) for k in stillk)
        print(f'PROOF C(c) STILLNESS: {len(stillk)} still mode-1 joints, max |pos delta| = '
              f'{serr:.3e}  ({"PASS" if serr < 1e-9 else "FAIL"})')

    if violations:
        print(f'FACE-FINGER-GATE {args.name}: FAIL ({len(violations)} face/finger joints: '
              + ', '.join(n for n, _c, _t, _m in violations) + ')')
        sys.exit(2)

    if args.emit_dir:
        os.makedirs(args.emit_dir, exist_ok=True)
        # mode 2 has NO driver counterpart by definition -> its e is emitted as 255.
        e_emit = np.array([255 if (mode[k] == 2 or k2e[k] == 0xFF) else int(k2e[k])
                           for k in range(nh)], np.int32)
        rows = [{'k': int(k), 'hd_name': hn[k],
                 'e': (None if e_emit[k] == 255 else int(e_emit[k])),
                 'e_name': (None if e_emit[k] == 255 else en[int(e_emit[k])]),
                 'tier': tier.get(k, 0),
                 'mode': int(mode[k]),
                 'mode_reason': reason.get(k, 'world-delta (name-matched, pivots agree)'),
                 'hd_parent': int(hd_parent[k]),
                 'drv_parent': int(drv_parent[k])} for k in range(nh)]
        json.dump({'version': 2, 'hd_glb': args.hd, 'eichar_glb': args.driver,
                   'num_hd_joints': len(hn), 'mapped': mapped,
                   'modes': {'world': ncens[0], 'local': ncens[1], 'glue': ncens[2]},
                   'rows': rows,
                   'authored_maps': [s for arg in args.map for s in arg.split(',') if s],
                   'accepted_unmapped': [{'joint': n, 'cat': c, 'reason': w}
                                         for n, c, w in accepted]},
                  open(os.path.join(args.emit_dir, f'{args.name}-k2e.json'), 'w'), indent=1)
        vals = ' '.join(str(int(x)) for x in e_emit)
        # legacy symbol kept verbatim for jak-hd (goal_src/.../jak-hd.gc already references it).
        sym = '*jak-hd->eichar-joint*' if args.name == 'jak-hd' else f'*{args.name}->driver-joint*'
        word = 'eichar' if args.name == 'jak-hd' else 'driver'

        def _arr(sy, a):
            return (f'(define {sy} (new \'static \'array uint8 {nh}\n'
                    f'  {" ".join(str(int(x)) for x in a)}))\n')

        gc = (f';; {args.name} retarget map v2: HD game joint index -> {word} game joint index '
              f'(255=none).\n'
              ';; generated by scripts/shell/retarget_fill_table.py — do not hand-edit.\n'
              ';; -mode: 0 = world-delta, 1 = local-delta mapped, 2 = local-delta glue (e=255).\n'
              ';; -hd-parent: HD rig parent joint index (255 = root/none), always < k.\n'
              f';; -drv-parent: {word} rig parent of the mapped {word} joint (255 = n/a).\n'
              + _arr(sym, e_emit)
              + _arr(f'*{args.name}-mode*', mode)
              + _arr(f'*{args.name}-hd-parent*', hd_parent)
              + _arr(f'*{args.name}-drv-parent*', drv_parent))
        open(os.path.join(args.emit_dir, f'{args.name}-k2e.gc-snippet'), 'w').write(gc)
        print(f'emitted k2e table -> {args.emit_dir}/{args.name}-k2e.json + .gc-snippet ({len(hn)} joints)')


if __name__ == '__main__':
    main()
