#!/usr/bin/env python3
"""probe_hair_joint_deficit.py — WHERE does a hair strand run out of joints?

NATURE of what is measured : a LENGTH DISTRIBUTION along the strand axis (how the skinned
  vertex mass of a chain is spread from its root to beyond its last joint). It is NOT an
  amplitude and NOT a variance — the defect it serves ("la pointe ne bouge pas", "la nuque
  clipe dans le cou") is a question of WHICH GEOMETRY HAS A JOINT TO FOLLOW.
FRAME : the strand's own BIND frame — every vertex is projected on the axis of the chain's
  LAST bone, origin at that bone's head, unit = the bone's own length. A vertex at s=2.0 sits
  one whole bone-length PAST the last joint, so nothing articulates it.
BASELINE when the defect is ABSENT : a chain whose joints cover its geometry reads
  s_max <= 1.0 (all mass within the last bone) and orphan_frac = 0.

Reads the DONOR glb (the skinning source of truth, per-primitive JOINTS_0/WEIGHTS_0 — the
2026-08-13 lesson: primitive 0 is not the body). Prints a table and, with --spec, the derived
injection spec consumed by physics_inject_joints.py.
"""
import argparse
import json
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                '..', 'scripts', 'shell'))
from retarget_hd_models import (read_glb, consolidate_buffers,  # noqa: E402
                                read_accessor, skin_info)

CHAINS_FILE = 'recharged_assets/physics_chains.txt'


def load_chains(path=CHAINS_FILE):
    """Chain -> joint list, READ FROM THE DELIVERED DATA, never hand-listed here.

    The chain composition already lives in five places in this tree (this file, gen2's
    EXPECTED_GROUPS, the k2e arrays, *hd-joint-counts*, and physics_reskin.txt's `grade
    ... chain=`), and TWO of the 2026-08-13 defects were exactly that duplication drifting.
    A sixth copy inside the instrument would be the same mistake, and it would also make the
    probe blind to any chain it had not been told about.
    """
    out, cur = {}, None
    for ln in open(path, errors='ignore'):
        s = ln.strip()
        if s.startswith('chain '):
            cur = s.split()[1]
            out[cur] = []
        elif s.startswith('j ') and cur:
            out[cur].append(s.split()[1])
    return {k: v for k, v in out.items() if v}


CHAINS = load_chains() if os.path.exists(CHAINS_FILE) else {}

# The donor rip is in METRES, calibrated against a number the ENGINE publishes itself:
# `bones_m` for lbang is 0.4124, 0.0962, 0.1914 and the donor's own Lbanga->Lbangb->Lbangc
# bind distances are 0.0962 / 0.1914. Scale 1.0, measured, not assumed. (physics_chains.txt
# radii are a different unit -- game units, 4096/m -- and are not used here.)
U = 1.0


def gather(js, binc):
    """(joints, weights) bound to their own vertices, ONE entry per distinct attribute set.

    The donor rips 28 primitives that all reference the SAME POSITION/JOINTS_0/WEIGHTS_0
    accessors (they differ only by material and indices). Iterating primitives blindly counts
    every vertex 28 times — measured, and it is why a 167-vertex strand first read 36484.
    Keyed on the accessor triple, so a mesh that really does carry several attribute sets
    (the 2026-08-13 `prejoint` corruption) is still seen whole.
    """
    names, ibms, parent = skin_info(js, binc)
    nj = len(names)
    # bind world transform = inverse(IBM)
    bind = np.array([np.linalg.inv(m) for m in ibms])
    seen, pos_all, jw = set(), [], []
    for mesh in js.get('meshes', []):
        for p in mesh['primitives']:
            at = p['attributes']
            if 'JOINTS_0' not in at or 'WEIGHTS_0' not in at:
                continue
            key = (at['POSITION'], at['JOINTS_0'], at['WEIGHTS_0'])
            if key in seen:
                continue
            seen.add(key)
            P = read_accessor(js, binc, at['POSITION']).astype(np.float64)
            J = read_accessor(js, binc, at['JOINTS_0']).astype(np.int32)
            W = read_accessor(js, binc, at['WEIGHTS_0']).astype(np.float64)
            if W.max() > 1.5:                      # normalized ubyte/ushort
                W = W / W.max()
            pos_all.append(P)
            jw.append((J, W))
    return names, bind, parent, pos_all, jw, nj


def successor_name(n):
    """backHair2 -> backHair3, Lbangc -> Lbangd, lKneeFlap -> lKneeFlap2.

    All three are the rig's OWN conventions: it already ships numeric pairs (lTopStrap /
    lTopStrap2, lBotStrap / lBotStrap2) alongside the lettered hair chains, so an unsuffixed
    joint's successor takes the '2'.
    """
    m = re.match(r'^(.*?)(\d+)$', n)
    if m:
        return "%s%d" % (m.group(1), int(m.group(2)) + 1)
    m = re.match(r'^(.*?)([a-c])$', n)
    if m:
        return m.group(1) + chr(ord(m.group(2)) + 1)
    return n + '2'


def chain_owned(jw_list, pos_list, jidxs, own=0.5):
    """Vertices the CHAIN owns: summed weight over all its joints > `own`.

    Ownership matters and a threshold of ~0 does not work: with 4 influences per vertex a
    stray 1e-4 weight on backHair1 pulls in geometry from across the body, and the strand
    then reads 1.11 m of "tail" on a 0.106 m bone. Majority ownership (>0.5) is the honest
    definition of "geometry this chain drives", and it reproduces the independently measured
    backhair tail (0.1326 m = 1.26 bone lengths).
    """
    js_set = set(jidxs)
    P, Wt = [], []
    for (J, W), pos in zip(jw_list, pos_list):
        m = np.isin(J, list(js_set))
        if not m.any():
            continue
        w = np.where(m, W, 0.0).sum(axis=1)
        sel = w > own
        if sel.any():
            P.append(pos[sel])
            Wt.append(w[sel])
    if not P:
        return np.zeros((0, 3)), np.zeros(0)
    return np.concatenate(P), np.concatenate(Wt)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--glb', default='decompiler_out/jak2/levels/lintcstb/keira-highres-lod0.glb')
    ap.add_argument('--spec', help='write the derived injection spec here (json)')
    ap.add_argument('--only', help='comma list of chains')
    ap.add_argument('--target', type=float, default=1.15,
                    help='stop appending once s_p95 <= this (bone lengths)')
    ap.add_argument('--max-add', type=int, default=3, dest='max_add')
    ap.add_argument('--emit-spec', dest='emit_spec',
                    help='write the injector spec (text) here')
    a = ap.parse_args()

    js, bufs = read_glb(a.glb)
    binc = consolidate_buffers(js, bufs)
    names, bind, parent, pos_list, jw_list, nj = gather(js, binc)
    idx = {n: i for i, n in enumerate(names)}

    print("# probe_hair_joint_deficit — glb=%s  joints=%d" % (a.glb, nj))
    print("# NATURE: length distribution along the strand axis.  FRAME: last bone's bind frame,")
    print("#   origin at its head, unit = that bone's length.  s>1.0 == geometry PAST the last joint.")
    print("# BASELINE (defect absent): s_p95 <= 1.0 and orphan (mass at s>1) == 0.")
    print()
    hdr = ("%-10s %-11s %6s %8s %8s %8s %8s %7s %7s" %
           ('chain', 'lastjoint', 'nvert', 'bone_m', 's_p50', 's_p95', 's_max', 'orphan', 'tail_m'))
    print(hdr)
    print('-' * len(hdr))

    want = set((a.only or '').split(',')) if a.only else set(CHAINS)
    spec = []
    for cname, jnames in CHAINS.items():
        if cname not in want:
            continue
        if any(n not in idx for n in jnames):
            print("%-10s MISSING joints in rig: %s" % (cname, [n for n in jnames if n not in idx]))
            continue
        # follow the chain past its declared end: an injected joint continues the rig's own
        # naming sequence, so the probe measures the chain as it now EXISTS rather than as it
        # was declared. Without this the "after" run would re-measure the "before" chain.
        jnames = list(jnames)
        while True:
            nxt = successor_name(jnames[-1])
            if nxt and nxt in idx:
                jnames.append(nxt)
            else:
                break
        ji = [idx[n] for n in jnames]
        # bone axis of the LAST link, in bind world space. A ONE-JOINT chain (chestL, the flaps,
        # the straps) has no previous link, so its bone runs from its RIG PARENT — which is
        # exactly what the engine uses as the chain's anchor (`*phys-anchor*`, set from the rig
        # parent of link 0). Skipping those chains would have hidden the same defect on every
        # single-link piece, which is most of what she WEARS.
        head = bind[ji[-1]][:3, 3]
        if len(ji) >= 2:
            prev = bind[ji[-2]][:3, 3]
        else:
            par = parent[ji[0]]
            if par < 0:
                print("%-10s single link with no rig parent — no bone axis" % cname)
                continue
            prev = bind[par][:3, 3]
        axis = head - prev
        blen = np.linalg.norm(axis)
        if blen < 1e-9:
            print("%-10s degenerate last bone" % cname)
            continue
        u = axis / blen

        # every vertex the CHAIN owns, projected on that axis
        P, W = chain_owned(jw_list, pos_list, ji)
        if not len(P):
            print("%-10s no majority-owned vertices" % cname)
            continue
        s = ((P - head) @ u) / blen + 1.0        # s=1 at the last joint, s=0 at its parent

        order = np.argsort(s)
        ss, ww = s[order], W[order]
        cw = np.cumsum(ww) / ww.sum()
        p50 = ss[np.searchsorted(cw, 0.50)]
        p95 = ss[np.searchsorted(cw, 0.95)]
        orphan = ww[ss > 1.0].sum() / ww.sum()

        tail_m = max(0.0, (p95 - 1.0)) * blen     # geometry past the last joint, in METRES
        print("%-10s %-11s %6d %8.4f %8.3f %8.3f %8.3f %6.1f%% %7.4f" %
              (cname, jnames[-1], len(P), blen / U, p50, p95, ss[-1], 100 * orphan, tail_m))

        # ---- DERIVED injection spec -------------------------------------------------
        # ONE rule, identical for every chain, no per-chain hand tuning (règle 4):
        #
        #   append ONE joint on the strand axis at s = s_p95 — the 95th percentile of the
        #   chain's own skinned mass.
        #
        # It converges by construction: after injection the articulated span reaches the point
        # that 95 % of the drawn geometry sits behind, so the distal half stops being carried
        # rigidly by a joint at the strand's MIDDLE. `residual_m` is the mass that still lies
        # past the new joint, published rather than hidden — it is the honest leftover.
        #
        # An earlier version appended joints iteratively at the centroid of the remaining tail.
        # It did not converge (each new bone is a fraction of the previous, so s_p95 in the new
        # unit barely drops) and asked for 3 joints per chain while still reading 1.33. Rejected
        # on its own measurement.
        s_new = float(p95)
        adds = []
        if s_new > a.target:
            pos = head + u * ((s_new - 1.0) * blen)
            resid = ww[ss > s_new].sum() / ww.sum()
            adds.append({'s': round(s_new, 3),
                         'bind_pos_m': [round(float(x), 6) for x in pos],
                         'new_bone_m': round(float((s_new - 1.0) * blen), 4),
                         'residual_mass_frac': round(float(resid), 4)})
        spec.append({'chain': cname, 'joints': jnames,
                     'last_bone_m': round(blen / U, 4),
                     's_p50': round(float(p50), 3), 's_p95': round(float(p95), 3),
                     's_max': round(float(ss[-1]), 3),
                     'orphan_frac': round(float(orphan), 4),
                     'nvert': int(len(P)),
                     'add': adds})

    if a.spec:
        json.dump(spec, open(a.spec, 'w'), indent=1)
        print("\nspec -> %s" % a.spec)

    if a.emit_spec:
        # successor name: backHair2 -> backHair3, Lbangc -> Lbangd. Same convention the rig
        # already uses, and 'd' is already in retarget_hd_models.SUFFIX_MAP.
        def successor(n):
            s = successor_name(n)
            if not s:
                raise SystemExit("no naming rule for %s" % n)
            return s

        lines = [
            "# %s — DERIVED by .autoport/probe_hair_joint_deficit.py."
            % os.path.basename(a.emit_spec),
            "# DO NOT HAND-EDIT: regenerate with",
            "#   python3 .autoport/probe_hair_joint_deficit.py \\",
            "#       --glb out/jak1/fr3/skin/keira-hd-lod0.glb --emit-spec %s" % a.emit_spec,
            "#",
            "# One appended joint per hair chain, at s = s_p95 of that chain's own skinned",
            "# mass, measured on the SHIPPED mesh (prep re-indexes joints; the raw donor rip",
            "# still carries the level's vertex pool and reads 3.6 m of 'hair'). Donor and",
            "# prepped bind spaces verified identical to 0.00000000 m, so these positions",
            "# apply to the donor unchanged.",
            "#",
            "# chain      parentJoint   newJoint      x            y            z    (metres)",
        ]
        for e in spec:
            if not e['add'] or e['chain'] not in want:
                continue
            add = e['add'][0]
            par = e['joints'][-1]
            lines.append("%-11s %-13s %-13s %11.6f %12.6f %12.6f" %
                         (e['chain'], par, successor(par), *add['bind_pos_m']))
            lines.append("#   s_p95 %.3f  new bone %.4f m  residual mass past it %.1f%%"
                         % (add['s'], add['new_bone_m'],
                            100 * add['residual_mass_frac']))
        open(a.emit_spec, 'w').write("\n".join(lines) + "\n")
        print("spec text -> %s" % a.emit_spec)


if __name__ == '__main__':
    main()
