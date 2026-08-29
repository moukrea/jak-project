#!/usr/bin/env python3
# scripts/shell/hd_drop_joints.py — remove named joints (and their whole subtree) from a rigged
# HD donor GLB, at the POINT OF PRODUCTION.
#
# WHY THIS EXISTS (Gkeira-visor-deliver, owner 2026-08-29: "Keira HD a toujours la visiere
# attachee").
# ---------------------------------------------------------------------------------------------
# The jak2/jak3 Keira donors carry a WELDING MASK prop she does not wear: `maskstrap` and its
# child `mask`, parented to the ROOT (`prejoint`, not the head) and posed at the model ORIGIN, at
# and below the soles of her feet. The previous cycle removed its DRAWN GEOMETRY from the shipped
# fr3 (`hd_merc_swap add --drop-effect`), which works and is delivered — but the two JOINTS stayed
# in the rig, so `keira-hd-ag.go` still declares them and the prop is still described by the
# skeleton the game loads.
#
# The joint list is shared by FOUR artefacts that must agree or the rig silently desynchronises:
#   `<char>-ag.go`  (build_actor, skeleton+names)      `<char>-k2e.json` (retarget table)
#   the appended merc model in the enhanced fr3         the `*<char>-hd-*` arrays in jak-hd.gc
# so the removal is done ONCE, here, on the single donor GLB all four are derived from — the same
# reason `physics_inject_joints.py` runs at this exact point (owner: "quand une perte se repete,
# on la rend impossible au point de production").
#
# WHAT IT DOES NOT DO, AND WHY. It does NOT delete primitives. `hd_merc_swap stamp` asserts
# prim-count == donor-draw-count and per-prim triangle counts, and `hd_merc_swap add` mirrors
# `--drop-effect` onto a FRESH donor-fr3 load to keep every index-based port (blerc, envmap,
# animslot) aligned; dropping prims here would break both. The prop's 173 vertices therefore stay
# in the intermediate pool, re-bound to the dropped joint's nearest surviving ancestor, and are
# erased from the DELIVERED model by the existing `--drop-effect` (proven by `hd_merc_swap audit`).
# Re-binding is rest-pose-neutral by construction: skinning composes M_j . IBM_j, which is the
# identity at rest for every j, so no surviving vertex moves.
#
# Usage:
#   python3 hd_drop_joints.py --in <rig>.glb --out <rig>.glb --spec <char>-drop-joints.txt
#                             [--report r.txt]
# Spec: one joint name per line; `#` comments; blank lines ignored. A named joint takes its whole
# subtree with it. Absent from the rig => reported as already-absent (idempotent), never a silent
# pass: the exit-0 path always prints the post-condition it verified.
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from retarget_hd_models import (read_glb, consolidate_buffers, read_accessor,  # noqa: E402
                                append_accessor, write_glb, skin_info)


def gc_keep_anims(js, bin_chunk):
    """gc_glb's job, but animation samplers are LIVE references here.

    `retarget_hd_models.gc_glb` only walks meshes/skins/images, because its one caller
    (`prep_hd_actor_glb.py`) pops `animations` first. This rig keeps its animation — the retarget
    table generator samples it for the FK rest pose — so dropping its accessors would leave
    dangling sampler indices in a file that still declares them.
    """
    used_acc = set()
    for mesh in js.get('meshes', []):
        for p in mesh['primitives']:
            used_acc.update(p['attributes'].values())
            if 'indices' in p:
                used_acc.add(p['indices'])
    for skin in js.get('skins', []):
        if 'inverseBindMatrices' in skin:
            used_acc.add(skin['inverseBindMatrices'])
    for anim in js.get('animations', []):
        for s in anim['samplers']:
            used_acc.add(s['input'])
            used_acc.add(s['output'])
    used_bv = {js['accessors'][a]['bufferView'] for a in used_acc}
    used_bv.update(img['bufferView'] for img in js.get('images', []) if 'bufferView' in img)

    new_bin = bytearray()
    bv_remap, new_bvs = {}, []
    for i, bv in enumerate(js.get('bufferViews', [])):
        if i not in used_bv:
            continue
        while len(new_bin) % 4:
            new_bin.append(0)
        start = bv.get('byteOffset', 0)
        nbv = dict(bv)
        nbv['byteOffset'] = len(new_bin)
        nbv['buffer'] = 0
        new_bin.extend(bin_chunk[start:start + bv['byteLength']])
        bv_remap[i] = len(new_bvs)
        new_bvs.append(nbv)

    acc_remap, new_accs = {}, []
    for i, acc in enumerate(js.get('accessors', [])):
        if i not in used_acc:
            continue
        nacc = dict(acc)
        nacc['bufferView'] = bv_remap[acc['bufferView']]
        acc_remap[i] = len(new_accs)
        new_accs.append(nacc)

    js['bufferViews'] = new_bvs
    js['accessors'] = new_accs
    for mesh in js.get('meshes', []):
        for p in mesh['primitives']:
            p['attributes'] = {k: acc_remap[v] for k, v in p['attributes'].items()}
            if 'indices' in p:
                p['indices'] = acc_remap[p['indices']]
    for skin in js.get('skins', []):
        if 'inverseBindMatrices' in skin:
            skin['inverseBindMatrices'] = acc_remap[skin['inverseBindMatrices']]
    for anim in js.get('animations', []):
        for s in anim['samplers']:
            s['input'] = acc_remap[s['input']]
            s['output'] = acc_remap[s['output']]
    for img in js.get('images', []):
        if 'bufferView' in img:
            img['bufferView'] = bv_remap[img['bufferView']]
    js['buffers'] = [{'byteLength': len(new_bin)}]
    return new_bin


def read_spec(path):
    out = []
    for raw in open(path):
        line = raw.split('#', 1)[0].strip()
        if line:
            out.append(line)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='inp', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--spec', required=True)
    ap.add_argument('--report', default=None)
    args = ap.parse_args()

    wanted = read_spec(args.spec)
    if not wanted:
        print(f'DROP-JOINTS FAIL: {args.spec} names no joint', file=sys.stderr)
        return 2

    js, bufs = read_glb(args.inp)
    binc = consolidate_buffers(js, bufs)
    names, ibms, parent = skin_info(js, binc)
    ibms = np.array(ibms)
    nj = len(names)
    joint_nodes = list(js['skins'][0]['joints'])
    name_to_j = {}
    for i, n in enumerate(names):
        name_to_j.setdefault(n, i)

    kids = {i: [] for i in range(nj)}
    for i, p in enumerate(parent):
        if p >= 0:
            kids[p].append(i)

    lines = [f'drop-joints {args.inp} -> {args.out}', f'  spec {args.spec}: {wanted}']
    absent = [n for n in wanted if n not in name_to_j]
    roots = [name_to_j[n] for n in wanted if n in name_to_j]

    drop = set()
    for r in roots:
        stack = [r]
        while stack:
            x = stack.pop()
            if x in drop:
                continue
            drop.add(x)
            stack += kids[x]
    if 0 in drop:
        print(f'DROP-JOINTS FAIL: joint 0 ({names[0]}) is in the drop set — that is the rig root',
              file=sys.stderr)
        return 2

    n_before_nodes = len(js['nodes'])
    if not drop:
        lines.append(f'  IDEMPOTENT: every named joint is already absent ({absent})')
        lines.append(f'  joints {nj} (unchanged), nodes {n_before_nodes} (unchanged)')
        if os.path.abspath(args.inp) != os.path.abspath(args.out):
            import shutil
            shutil.copyfile(args.inp, args.out)
        rep = '\n'.join(lines)
        print(rep)
        if args.report:
            open(args.report, 'w').write(rep + '\n')
        return 0

    lines.append('  dropping joints (name, skin index, subtree of a named root): '
                 + ', '.join(f'{names[j]}@{j}' for j in sorted(drop)))
    if absent:
        lines.append(f'  already absent (idempotent): {absent}')

    # nearest surviving ancestor of each dropped joint — where its vertex weight goes
    def surviving_ancestor(j):
        p = parent[j]
        while p >= 0 and p in drop:
            p = parent[p]
        return p
    anc = {j: surviving_ancestor(j) for j in drop}
    for j, a in anc.items():
        if a < 0:
            print(f'DROP-JOINTS FAIL: {names[j]} has no surviving ancestor to inherit its weights',
                  file=sys.stderr)
            return 2

    keep = [j for j in range(nj) if j not in drop]
    old2new = np.full(nj, -1, np.int64)
    for k, j in enumerate(keep):
        old2new[j] = k

    # ---- weight surgery on every (JOINTS_0, WEIGHTS_0) accessor pair the mesh uses -------------
    pairs = {}
    for mesh in js.get('meshes', []):
        for p in mesh['primitives']:
            at = p['attributes']
            if 'JOINTS_0' in at and 'WEIGHTS_0' in at:
                pairs.setdefault((at['JOINTS_0'], at['WEIGHTS_0']), []).append(p)
    moved_verts = 0
    moved_weight = 0.0
    for (ja, wa), prims in pairs.items():
        J = read_accessor(js, binc, ja).astype(np.int64)
        W = read_accessor(js, binc, wa).astype(np.float64)
        j_ct = js['accessors'][ja]['componentType']
        w_ct = js['accessors'][wa]['componentType']
        if w_ct != 5126:
            print(f'DROP-JOINTS FAIL: WEIGHTS_0 componentType {w_ct} is not float32 — '
                  'normalized integer weights are not handled', file=sys.stderr)
            return 2
        nv = J.shape[0]
        outJ = np.zeros_like(J)
        outW = np.zeros_like(W)
        for v in range(nv):
            acc = {}
            touched = False
            for s in range(4):
                w = float(W[v, s])
                if w <= 0.0:
                    continue
                j = int(J[v, s])
                if j in drop:
                    touched = True
                    moved_weight += w
                    j = anc[j]
                acc[j] = acc.get(j, 0.0) + w
            if touched:
                moved_verts += 1
            for s, (j, w) in enumerate(sorted(acc.items(), key=lambda kv: -kv[1])[:4]):
                nj_new = int(old2new[j])
                if nj_new < 0:
                    print(f'DROP-JOINTS FAIL: vertex {v} still references dropped joint {names[j]}',
                          file=sys.stderr)
                    return 2
                outJ[v, s] = nj_new
                outW[v, s] = w
        np_j = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32}.get(j_ct)
        if np_j is None:
            print(f'DROP-JOINTS FAIL: JOINTS_0 componentType {j_ct} unsupported', file=sys.stderr)
            return 2
        if int(outJ.max()) > np.iinfo(np_j).max:
            print('DROP-JOINTS FAIL: joint index overflows its component type', file=sys.stderr)
            return 2
        new_ja = append_accessor(js, binc, outJ.astype(np_j), j_ct, 'VEC4')
        new_wa = append_accessor(js, binc, outW.astype(np.float32), 5126, 'VEC4')
        for p in prims:
            p['attributes']['JOINTS_0'] = new_ja
            p['attributes']['WEIGHTS_0'] = new_wa
    lines.append(f'  weights re-bound to the nearest surviving ancestor: {moved_verts} vertices, '
                 f'{moved_weight:.4f} total weight -> '
                 + ', '.join(f'{names[j]}->{names[a]}' for j, a in sorted(anc.items())))

    # ---- rebuild the skin (joint list + inverse bind matrices) ---------------------------------
    new_ibm = np.zeros((len(keep), 16), np.float32)
    for k, j in enumerate(keep):
        new_ibm[k] = ibms[j].T.reshape(-1).astype(np.float32)   # row-major -> glTF column-major
    js['skins'][0]['inverseBindMatrices'] = append_accessor(js, binc, new_ibm, 5126, 'MAT4')
    dropped_nodes = {joint_nodes[j] for j in drop}
    js['skins'][0]['joints'] = [joint_nodes[j] for j in keep]

    # ---- delete the joint NODES and remap every node reference ---------------------------------
    keep_nodes = [i for i in range(len(js['nodes'])) if i not in dropped_nodes]
    nmap = {old: new for new, old in enumerate(keep_nodes)}
    new_nodes = []
    for old in keep_nodes:
        nd = dict(js['nodes'][old])
        if 'children' in nd:
            ch = [nmap[c] for c in nd['children'] if c in nmap]
            if ch:
                nd['children'] = ch
            else:
                nd.pop('children')
        new_nodes.append(nd)
    js['nodes'] = new_nodes
    for skin in js.get('skins', []):
        skin['joints'] = [nmap[n] for n in skin['joints']]
        if 'skeleton' in skin:
            if skin['skeleton'] in nmap:
                skin['skeleton'] = nmap[skin['skeleton']]
            else:
                skin.pop('skeleton')
    for sc in js.get('scenes', []):
        if 'nodes' in sc:
            sc['nodes'] = [nmap[n] for n in sc['nodes'] if n in nmap]
    kept_anims = []
    dropped_channels = 0
    for anim in js.get('animations', []):
        chans = []
        for c in anim['channels']:
            t = c['target'].get('node')
            if t is None or t not in nmap:
                dropped_channels += 1
                continue
            c = dict(c)
            c['target'] = dict(c['target'])
            c['target']['node'] = nmap[t]
            chans.append(c)
        if chans:
            anim = dict(anim)
            anim['channels'] = chans
            kept_anims.append(anim)
    if 'animations' in js:
        js['animations'] = kept_anims

    binc = gc_keep_anims(js, binc)
    write_glb(args.out, js, binc)

    # ---- post-condition, verified on the WRITTEN file, never on intent -------------------------
    vjs, vbufs = read_glb(args.out)
    vbin = consolidate_buffers(vjs, vbufs)
    vnames, _vibm, _vpar = skin_info(vjs, vbin)
    still = [n for n in wanted if n in vnames]
    if still:
        print(f'DROP-JOINTS FAIL: {still} still in the written rig', file=sys.stderr)
        return 2
    node_names = [n.get('name', '') for n in vjs['nodes']]
    still_nodes = [n for n in wanted if n in node_names]
    if still_nodes:
        print(f'DROP-JOINTS FAIL: {still_nodes} still a node in the written rig', file=sys.stderr)
        return 2
    lines.append(f'  skin joints {nj} -> {len(vnames)}   nodes {n_before_nodes} -> {len(vjs["nodes"])}'
                 f'   anim channels dropped {dropped_channels}')
    lines.append(f'  VERIFIED on the written file: {wanted} absent from skin.joints AND from nodes')
    rep = '\n'.join(lines)
    print(rep)
    if args.report:
        open(args.report, 'w').write(rep + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
