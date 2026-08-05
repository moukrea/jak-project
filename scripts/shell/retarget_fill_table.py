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

    # ---- LOCAL-BIND FRAME MISMATCH (cycle 3): mode 1 vs mode 3 ---------------------------------
    # mode 1 replays the DRIVER's local delta in the DRIVER's local bind frame. That is only right
    # when the two rigs' LOCAL bind frames agree. Measured counter-examples: jak1 sage beard_lip
    # (82.2deg + 1.5x scale, parked above the head), dax/keira finger A-joints (86-178deg),
    # jak packStrapTop/Mid (17.1deg). Those joints get mode 3 ORIENT-COPY instead, whose rotation
    # comes from the mode-0 world product (its inv(R(C_e)).R(B_k) factor cancels the frame
    # mismatch) with the translation from the glue product (HD pivots/bone lengths kept).
    def _local_bind(bind, par, j):
        p = par[j]
        return (np.linalg.inv(bind[p]) @ bind[j]) if p >= 0 else bind[j].copy()

    def _polar_R(M3):
        """rotation factor of a 3x3 by polar decomposition (SVD), right-handed."""
        u, _s, vt = np.linalg.svd(M3)
        R = u @ vt
        if np.linalg.det(R) < 0:
            u = u.copy()
            u[:, -1] *= -1
            R = u @ vt
        return R

    def _ang_deg(R):
        return float(np.degrees(np.arccos(np.clip((np.trace(R) - 1.0) * 0.5, -1.0, 1.0))))

    def _scales(M3):
        return [float(np.linalg.norm(M3[:, c])) for c in range(3)]

    def _mode1_or_3(k, e, why):
        """mode 1 if the two LOCAL BIND FRAMES agree (pairwise), else mode 3 orient-copy.

        mode 1 replays the DRIVER's LOCAL delta at the HD joint's own pivot, so correctness
        requires the two LOCAL BIND FRAMES to AGREE — rotation (polar factor) and PAIRWISE
        scale ratios driver/HD — NOT that either frame has unit scale.
        CYCLE 4 FIX (owner 2026-08-05, Keira strap chest-clip): the old test demoted a joint
        whenever ANY local-bind scale differed from 1.0. Keira's four *Strap2 joints carry an
        IDENTICAL 0.103 local-bind scale on BOTH rigs and a 0.00deg rotation mismatch — their
        bind frames agree perfectly — yet they were demoted to mode 3, which DISCARDS the
        driver's translation keys (the straps are translation-keyed in every jak1 assistant
        anim) and dragged them 0.36-0.44 units through her chest. The pairwise test keeps them
        on mode 1, which reproduces the driver to ~1e-12.
        """
        lh = _local_bind(h_bind, hpar, k)[:3, :3]
        ld = _local_bind(e_bind, epar, int(e))[:3, :3]
        rm = _ang_deg(_polar_R(ld) @ _polar_R(lh).T)
        ds, hs = _scales(ld), _scales(lh)
        # pairwise driver-vs-HD scale agreement; a degenerate HD scale (h == 0) cannot be
        # compared -> fall back to the safe mode 3.
        smis = any((abs(h) < 1e-12) or (abs(d / h - 1.0) > 0.02) for d, h in zip(ds, hs))
        if rm > 1.0 or smis:
            return 3, ('orient-copy: rot_mismatch={:.2f}deg drv_scale={} hd_scale={} ({})'
                       .format(rm, '/'.join(f'{s:.3f}' for s in ds),
                               '/'.join(f'{s:.3f}' for s in hs), why))
        return 1, why
    for k in range(nh):
        nm, ti, e = hn[k], tier.get(k, 0), int(k2e[k])
        cat = _cat(nm)
        if e != 0xFF and ti == 0:                      # (a) authored --map pair
            mode[k], reason[k] = _mode1_or_3(k, e, f'authored --map -> {en[e]}')
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
            mode[k], reason[k] = _mode1_or_3(k, e, (f'{cat}-class (proportion-sensitive) -> {en[e]} '
                                                    f'pivot_err={perr:.4f} bone={blen:.4f}'))
        elif (nm == 'align' and k == 0) or (nm == 'prejoint' and k == 1) or SAFE_RE.search(nm):
            mode[k] = 0
        elif perr > thr:
            mode[k], reason[k] = _mode1_or_3(k, e, (f'pivot_err={perr:.4f} > thr={thr:.4f} '
                                                    f'(bone={blen:.4f}) vs {en[e]}'))
        else:
            mode[k] = 0
    ncens = [int((mode == m).sum()) for m in (0, 1, 2, 3)]
    print(f'MODES {args.name}: world={ncens[0]} local={ncens[1]} glue={ncens[2]} '
          f'orient={ncens[3]}')
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
    print(f'PARENT-ORDER {args.name}: PASS (all {ncens[1] + ncens[2] + ncens[3]} local/glue/orient '
          f'joints have '
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
        if mode[k] in (1, 3) and k2e[k] != 0xFF and tier.get(k, 0) in (0, 1, 2, 3):
            continue  # real (name- or author-derived) driver counterpart, retargeted local-delta
            #         # (mode 3 orient-copy has the same standing: a real, driven counterpart)
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
            elif mode[k] == 3:
                # mode 3 ORIENT-COPY, MIRROR of fill-jak-hd-bones! (goal_src/jak1/pc/jak-hd.gc):
                #   stored rows: tmp2 = hbind . bind-pose_drv[e] . A'_e   (= the mode-0 product)
                #   -> column form  P = A_e . IBM_e . B_k ; a STORED ROW r is column r of P, so
                #   "unit-normalize the basis rows" == unit-normalize P's 3x3 COLUMNS.
                #   translation row = the GLUE product's translation (Wp . Lk).
                # Rows are re-scaled to the HD BIND row length (runtime: blen/len with
                # blen = (vector-length (-> hbind vector r)), hbind = forward HD bind), NOT to
                # unit: that drops the DRIVER bind's scale leak while preserving the HD rig's own
                # world bind scale (jak 1.4 below 'main', keira strap chains 0.103).
                e = int(k2e[k])
                P = a_e[e] @ e_ibm[e] @ h_bind[k]
                B = P[:3, :3].copy()
                for c in range(3):
                    n = float(np.linalg.norm(B[:, c]))
                    blen = float(np.linalg.norm(h_bind[k][:3, :3][:, c]))
                    if n > 1e-6:
                        B[:, c] *= blen / n
                Wm[k] = np.eye(4)
                Wm[k][:3, :3] = B
                Wm[k][:3, 3] = (Wp @ Lk)[:3, 3]
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

    # ---- PROOF D: mode-3 ORIENT-COPY correctness (cycle 3) --------------------------------------
    # For EVERY mode-3 joint, rotate its mapped DRIVER joint by 40deg about an axis non-parallel to
    # the bone, refill with the RUNTIME's exact mode-3 math (fill_mixed above mirrors it), and check
    #   (a) LENGTH   the HD bone to its parent keeps its bind length (rel tol 1e-6)
    #   (b) STILL    at driver bind pose: rotation == the HD bind basis (rows at bind length) and
    #                translation == the glue-at-bind position. SPLIT tolerances: rotation 1e-6
    #                (the GLB inverse-bind matrices are float32, so bind orthonormality only holds
    #                to ~3e-8 — 1e-9 would sit under the input precision floor), translation 1e-9.
    #   (c) FOLLOW   the HD world rotation delta == the driver joint's world rotation delta (0.1deg)
    m3 = [k for k in range(nh) if mode[k] == 3]
    if not m3:
        print(f'PROOF D  orient-copy: no mode-3 joint in {args.name} — nothing to check (PASS)')
    else:
        def _rodrigues(axis, rad):
            a = axis / np.linalg.norm(axis)
            K = np.array([[0, -a[2], a[1]], [a[2], 0, -a[0]], [-a[1], a[0], 0]], float)
            return np.eye(3) + np.sin(rad) * K + (1 - np.cos(rad)) * (K @ K)

        def _bind_basis(k):
            """the HD bind 3x3 as the runtime reproduces it at bind pose: direction from the
            mode-0 product (= the bind itself), row lengths re-scaled to the bind row lengths."""
            B = h_bind[k][:3, :3].copy()
            for c in range(3):
                n = float(np.linalg.norm(B[:, c]))
                if n > 1e-6:
                    B[:, c] *= float(np.linalg.norm(h_bind[k][:3, :3][:, c])) / n
            return B

        Wbind = fill_mixed(e_bind)          # (b) driver AT BIND
        wa = wbr = wbt = wc = 0.0
        wa_j = wbr_j = wbt_j = wc_j = None
        fails = []
        for k in m3:
            e = int(k2e[k])
            p = hpar[k]
            # (b) stillness at bind
            br = float(np.abs(Wbind[k][:3, :3] - _bind_basis(k)).max())
            glue_bind = ((Wbind[p] if p >= 0 else np.eye(4))
                         @ ((np.linalg.inv(h_bind[p]) @ h_bind[k]) if p >= 0 else h_bind[k]))
            bt = float(np.linalg.norm(Wbind[k][:3, 3] - glue_bind[:3, 3]))
            bt = max(bt, float(np.linalg.norm(Wbind[k][:3, 3] - h_bind[k][:3, 3])))
            if br > wbr:
                wbr, wbr_j = br, hn[k]
            if bt > wbt:
                wbt, wbt_j = bt, hn[k]
            if br > 1e-6 or bt > 1e-9:
                fails.append(f'(b) STILL {hn[k]!r} rot_err={br:.3e} pos_err={bt:.3e}')
            # rotate the mapped driver joint about an axis NON-PARALLEL to its bone
            pe = epar[e]
            bd = (e_bind[e][:3, 3] - e_bind[pe][:3, 3]) if pe >= 0 else np.zeros(3)
            nb = float(np.linalg.norm(bd))
            bd = bd / nb if nb > 1e-9 else np.zeros(3)
            axis = min((np.eye(3)[i] for i in range(3)), key=lambda a: abs(float(a @ bd)))
            if abs(float(axis @ bd)) > 0.95:
                fails.append(f'(axis) {hn[k]!r}: no canonical axis non-parallel to the bone')
                continue
            R3 = _rodrigues(axis, np.deg2rad(40.0))
            piv = e_bind[e][:3, 3]
            Mr = np.eye(4)
            Mr[:3, :3] = R3
            Mr[:3, 3] = piv - R3 @ piv
            a_e = e_bind.copy()
            for d in descendants(epar, e):
                a_e[d] = Mr @ e_bind[d]
            Wk = fill_mixed(a_e)
            # (a) bone length to parent
            if p >= 0:
                want = float(np.linalg.norm(h_bind[k][:3, 3] - h_bind[p][:3, 3]))
                got = float(np.linalg.norm(Wk[k][:3, 3] - Wk[p][:3, 3]))
                rel = abs(got - want) / max(want, 1e-12)
                if rel > wa:
                    wa, wa_j = rel, hn[k]
                if rel > 1e-6:
                    fails.append(f'(a) LENGTH {hn[k]!r} bind={want:.6f} anim={got:.6f} rel={rel:.3e}')
            # (c) follow: HD world rotation delta == driver world rotation delta
            dR_hd = _polar_R(Wk[k][:3, :3]) @ _polar_R(Wbind[k][:3, :3]).T
            dR_drv = _polar_R(a_e[e][:3, :3]) @ _polar_R(e_bind[e][:3, :3]).T
            cerr = _ang_deg(dR_hd @ dR_drv.T)
            if cerr > wc:
                wc, wc_j = cerr, hn[k]
            if cerr > 0.1:
                fails.append(f'(c) FOLLOW {hn[k]!r} rot-delta mismatch = {cerr:.4f}deg '
                             f'(driver delta {_ang_deg(dR_drv):.3f}deg, hd {_ang_deg(dR_hd):.3f}deg)')
        print(f'PROOF D  orient-copy over {len(m3)} mode-3 joints (40deg synthetic driver rotation, '
              f'axis non-parallel to the bone):')
        print(f'  D(a) bone-length preservation : max rel err = {wa:.3e} (worst {wa_j!r})  '
              f'({"PASS" if wa <= 1e-6 else "FAIL"})')
        print(f'  D(b) stillness at bind pose   : max rot err = {wbr:.3e} (worst {wbr_j!r}, '
              f'tol 1e-6), max pos err = {wbt:.3e} (worst {wbt_j!r}, tol 1e-9)  '
              f'({"PASS" if (wbr <= 1e-6 and wbt <= 1e-9) else "FAIL"})')
        print(f'  D(c) driver rotation follow   : max angle err = {wc:.4f}deg (worst {wc_j!r})  '
              f'({"PASS" if wc <= 0.1 else "FAIL"})')
        for f in fails:
            print(f'PROOF D {args.name}: VIOLATION {f}')
        if fails:
            print(f'PROOF D {args.name}: FAIL ({len(fails)} assertion failures) — '
                  f'mode-3 orient-copy is NOT correct on this rig, no table emitted')
            sys.exit(3)
        print(f'PROOF D {args.name}: PASS ({len(m3)} mode-3 joints)')

    # ---- PROOF E: REAL-ANIMATION REPLAY GATE (cycle 4) ------------------------------------------
    # PROOFS A-D drive the rig with SYNTHETIC rigid rotations, so they are blind to the class of
    # defect that cost cycle 4: a joint that is TRANSLATION-KEYED in the real driver animations
    # being assigned mode 3, which reproduces only the driver's ORIENTATION and takes its position
    # from the HD glue product — i.e. it silently drops the driver's translation keys (Keira's four
    # *Strap2 joints, 0.36-0.44 units of drift straight through her chest).
    # The gate: replay the driver GLB's REAL animation channels (rotation + scale + TRANSLATION)
    # with full FK, fill the HD bones with each joint's ASSIGNED mode, and compare against the
    # mode-0 ground-truth product A_e . inv(C_e) . B_k. Any joint whose LOCAL BIND FRAMES AGREE
    # (rotation mismatch <= 1.0deg AND pairwise driver/HD scale ratios within 2%) has no excuse:
    # it must be translation-faithful (mode 0 or 1).
    # NUMERIC SUB-CLASS (deviation from the literal cycle-4 spec, measured): the 1e-6 replay bound
    # against the mode-0 product can only be enforced where that product IS the ground truth, i.e.
    # where the HD joint's WORLD BIND COINCIDES with the driver's (|B_k - C_e| <= 1e-6). mode 1
    # exists precisely to DEVIATE from mode 0 when the pivots differ (it re-anchors on the HD
    # parent to keep HD bone lengths), so bind-frame-agreeing joints with a real pivot offset
    # legitimately differ from mode 0 (measured on keira-hd: gogglesLeft/Right pivot_err=0.0389 ->
    # 3.8e-2, lEara/lEarb 0.10 -> 4e-6, LpantFlap 0.15 -> 2.5e-6). Keira's four *Strap2 joints sit
    # at |B_k - C_e| = 1e-15 and replay to ~1e-12 under mode 1 — clean separation, tol 1e-6.
    # Joints with a REAL bind mismatch legitimately ride mode 3 -> informational only.
    BIND_COINCIDE_TOL = 1e-6
    def _bind_frames_agree(k, e):
        lh = _local_bind(h_bind, hpar, k)[:3, :3]
        ld = _local_bind(e_bind, epar, int(e))[:3, :3]
        if _ang_deg(_polar_R(ld) @ _polar_R(lh).T) > 1.0:
            return False
        for d, h in zip(_scales(ld), _scales(lh)):
            if abs(h) < 1e-12 or abs(d / h - 1.0) > 0.02:
                return False
        return True

    e_anims = ejs.get('animations', []) or []
    if not e_anims:
        print(f'PROOF-E SKIP (no driver anims in GLB) [{args.name}]')
    else:
        e_nodes = ejs['nodes']
        e_joints = ejs['skins'][0]['joints']
        e_nparent = {}
        for _i, _nd in enumerate(e_nodes):
            for _c in _nd.get('children', []):
                e_nparent[_c] = _i

        def _compose(T, R, S):
            x, y, z, w = np.array(R, float) / max(float(np.linalg.norm(R)), 1e-30)
            R3 = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                           [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                           [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
            M = np.eye(4)
            M[:3, :3] = R3 @ np.diag(np.array(S, float))
            M[:3, 3] = np.array(T, float)
            return M

        def _rest_local(nd):
            if 'matrix' in nd:
                return np.array(nd['matrix'], float).reshape(4, 4).T
            return _compose(nd.get('translation', [0, 0, 0]), nd.get('rotation', [0, 0, 0, 1]),
                            nd.get('scale', [1, 1, 1]))

        def _samp(t, ts, vals):
            i = int(np.searchsorted(ts, t))
            i = min(max(i, 1), len(ts) - 1)
            t0, t1 = ts[i - 1], ts[i]
            f = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
            return vals[i - 1] * (1.0 - f) + vals[i] * f

        # PRECISION FLOOR of the mode-1 product: the driver GLB's stored (float32) inverse-bind
        # matrices are NOT exactly the inverse of the rig's own FK rest pose. De mixes the two
        # (De = IBM_e . C_pe . inv(A_pe) . A_e), so that inconsistency is the smallest replay error
        # physically reachable. Measured: sidekick 4.6e-7, assistant 1.16e-6, eichar 1.13e-6 — a
        # flat 1e-6 tolerance sits UNDER the input precision floor (same trap PROOF D(b) documents).
        # Tolerance = max(1e-6, 10 * that floor); the defect class it gates is 1e-1 (Keira straps),
        # i.e. 4+ orders of margin.
        def _fk_rest():
            Wn = {}
            stack = [(r, np.eye(4)) for r in range(len(e_nodes)) if r not in e_nparent]
            while stack:
                ni, P = stack.pop()
                M = P @ _rest_local(e_nodes[ni])
                Wn[ni] = M
                for c in e_nodes[ni].get('children', []):
                    stack.append((c, M))
            return np.array([Wn[j] for j in e_joints])

        eps_drv = float(np.abs(_fk_rest() - e_bind).max())
        GATE_TOL = max(1e-6, 10.0 * eps_drv)

        def _bind_coincides(k, e):
            return float(np.abs(h_bind[k] - e_bind[int(e)]).max()) <= BIND_COINCIDE_TOL

        gated_worst = 0.0
        gated_worst_j = None
        offenders = {}          # k -> (max err, anim name, assigned mode)
        info_worst = {}         # k -> max err (mode-3, real bind mismatch)
        n_gated = 0
        n_frames_total = 0
        for _ai, _an in enumerate(e_anims):
            chans = {}
            for ch in _an['channels']:
                smp = _an['samplers'][ch['sampler']]
                ts = np.array(read_accessor(ejs, ebin, smp['input']), float).reshape(-1)
                vs = np.array(read_accessor(ejs, ebin, smp['output']), float)
                chans.setdefault(ch['target']['node'], {})[ch['target']['path']] = (ts, vs)
            if not chans:
                continue
            times = sorted({float(x) for nd in chans.values() for p in nd.values() for x in p[0]})
            if len(times) > 200:                     # keep the runtime sane: stride to <= 200
                stride = int(np.ceil(len(times) / 200.0))
                times = times[::stride]
            n_frames_total += len(times)

            def _local_at(ni, t):
                nd = e_nodes[ni]
                if ni not in chans:
                    return _rest_local(nd)
                c = chans[ni]
                T = (_samp(t, *c['translation'])[:3] if 'translation' in c
                     else nd.get('translation', [0, 0, 0]))
                R = (_samp(t, *c['rotation'])[:4] if 'rotation' in c
                     else nd.get('rotation', [0, 0, 0, 1]))
                S = (_samp(t, *c['scale'])[:3] if 'scale' in c else nd.get('scale', [1, 1, 1]))
                return _compose(T, R, S)

            def _world_at(t):
                Wn = {}
                stack = [(r, np.eye(4)) for r in range(len(e_nodes)) if r not in e_nparent]
                while stack:
                    ni, P = stack.pop()
                    M = P @ _local_at(ni, t)
                    Wn[ni] = M
                    for c in e_nodes[ni].get('children', []):
                        stack.append((c, M))
                return np.array([Wn[j] for j in e_joints])

            for t in times:
                A = _world_at(t)
                Wm = fill_mixed(A)
                for k in range(nh):
                    e = int(k2e[k])
                    if e == 0xFF or mode[k] == 2:
                        continue
                    gt = A[e] @ e_ibm[e] @ h_bind[k]
                    err = float(np.abs(Wm[k] - gt).max())
                    if _bind_frames_agree(k, e):
                        numeric = _bind_coincides(k, e)
                        if numeric and err > gated_worst:
                            gated_worst, gated_worst_j = err, hn[k]
                        if mode[k] not in (0, 1) or (numeric and err > GATE_TOL):
                            prev = offenders.get(k)
                            if prev is None or err > prev[0]:
                                offenders[k] = (err, _an.get('name', f'anim{_ai}'), int(mode[k]),
                                                bool(numeric))
                    elif mode[k] == 3:
                        if err > info_worst.get(k, 0.0):
                            info_worst[k] = err
        gset = [k for k in range(nh)
                if int(k2e[k]) != 0xFF and mode[k] != 2 and _bind_frames_agree(k, int(k2e[k]))]
        n_gated = len(gset)
        n_numeric = sum(1 for k in gset if _bind_coincides(k, int(k2e[k])))
        for k in sorted(info_worst):
            print(f'  PROOF-E info mode3 k={k:3d} {hn[k]:<24s} (real bind mismatch) '
                  f'max abs err vs mode-0 = {info_worst[k]:.4e}')
        for k in sorted(offenders):
            err, anm, mo, numeric = offenders[k]
            print(f'PROOF-E {args.name}: VIOLATION k={k} {hn[k]!r} mode={mo} -> driver '
                  f'{en[int(k2e[k])]!r}: LOCAL BIND FRAMES AGREE but the joint is not '
                  f'translation-faithful — max abs replay err vs the mode-0 product = '
                  f'{err:.4e} (anim {anm!r}, tol {GATE_TOL:.0e}, bind-coincident='
                  f'{numeric}). A bind-identical joint must be mode 0 or 1; mode 3 '
                  f'discards the driver translation keys.')
        print(f'PROOF-E {args.name}: {"FAIL" if offenders else "PASS"} '
              f'({len(e_anims)} driver anims, {n_frames_total} frames checked, '
              f'{n_gated} bind-identical mapped joints gated for translation-faithfulness of '
              f'which {n_numeric} bind-coincident are gated numerically, {len(offenders)} '
              f'violations, max abs replay err over the numerically-gated class = '
              f'{gated_worst:.4e} (worst {gated_worst_j!r}, tol {GATE_TOL:.3e} = '
              f'max(1e-6, 10 x driver float32 bind floor {eps_drv:.3e})); '
              f'{len(info_worst)} mode-3 joints with real bind mismatch = informational)')
        if offenders:
            sys.exit(4)

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
                   'modes': {'world': ncens[0], 'local': ncens[1], 'glue': ncens[2],
                             'orient': ncens[3]},
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
              ';; -mode: 0 = world-delta, 1 = local-delta mapped, 2 = local-delta glue (e=255),\n'
              ';;        3 = orient-copy (mapped joint whose donor/driver LOCAL BIND FRAMES '
              'disagree).\n'
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
