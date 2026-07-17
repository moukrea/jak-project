#!/usr/bin/env python3
# retarget_hd_models.py — Grecharged-hd-models2 (round 2)
#
# Proper NAME-BASED joint retarget of a ripped jak2 highres character GLB (donor)
# onto a jak1 rig (target), replacing round 1's find_closest weight-borrow (which
# produced garbled deformation on device).
#
# Both GLBs must come from the decompiler's rip_levels foreground exporter
# (fr3_to_gltf.cpp), which writes a skin whose joints[] are the art-joint-geo
# bones IN ORDER with their game names, plus inverseBindMatrices, and encodes
# JOINTS_0 values as (merc mats - 1).
#
# What this tool does:
#   1. Maps every donor joint to a target joint by NAME, in tiers:
#        T1 exact, T2 case-insensitive, T3 suffix-normalized (a/b/c <-> 1/2/3,
#        name <-> name+'1'), T4 nearest donor ANCESTOR that matches via T1-T3.
#   2. Re-poses the mesh from the donor bind pose onto the target bind pose:
#        v' = sum_i w_i * inv(IBM_target[k_i]) @ IBM_donor[d_i] @ v
#      (for T4 influences, d_i is the matched donor ancestor on BOTH sides, so
#      the geometry rides rigidly with that ancestor).
#   3. Rewrites JOINTS_0 as u8 = (target joint index - 1) and WEIGHTS_0 as f32,
#      merged per target joint, top-3 kept + renormalized, 4th slot zero-padded
#      (the merc replacement importer adds +2 -> merc mats = index + 1, keeps 3).
#   4. Computes welded area-weighted smooth normals on the re-posed mesh (the
#      rip carries no NORMAL; the importer requires one).
#   5. Optionally drops triangles majority-weighted to donor joints matching
#      --drop-joints (e.g. the bird riding jak2 Samos, absent from jak1 Samos).
#   6. Replaces the GLB skin with the TARGET skeleton (names + IBMs) so the
#      importer computes max_bones from the jak1 rig, and sets
#      extras.enable_custom_weights=1 on every mesh node so the importer uses
#      our weights instead of find_closest.
#
# The tool prints an honest per-tier weight report and FAILS (exit 2) if less
# than --min-named-weight (default 0.97) of total skin weight is name-matched
# (T1-T3) — a character that can't be cleanly remapped must not ship garbled.
import argparse
import base64
import json
import re
import struct
import sys

import numpy as np

COMP_FMT = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}
COMP_NP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16,
           5125: np.uint32, 5126: np.float32}
TYPE_N = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def read_glb(path):
    """Returns (json, buffers) with EVERY buffer materialized as bytes.

    The rip exporter (tinygltf) emits multi-buffer GLBs: buffer 0 rides the BIN
    chunk, the others are base64 data URIs.
    """
    d = open(path, 'rb').read()
    magic, ver, _length = struct.unpack('<III', d[0:12])
    assert magic == 0x46546C67 and ver == 2, f"not a GLB v2: {path}"
    off = 12
    js = None
    bin_chunk = b''
    while off < len(d):
        clen, ctype = struct.unpack('<II', d[off:off + 8])
        off += 8
        if ctype == 0x4E4F534A:  # JSON
            js = json.loads(d[off:off + clen])
        elif ctype == 0x004E4942:  # BIN
            bin_chunk = d[off:off + clen]
        off += clen
    buffers = []
    for i, buf in enumerate(js.get('buffers', [])):
        uri = buf.get('uri')
        if uri is None:
            assert i == 0, f"buffer {i} has no uri and is not the BIN chunk"
            buffers.append(bytes(bin_chunk))
        else:
            assert uri.startswith('data:'), f"external buffer uri unsupported: {uri[:40]}"
            b64 = uri.split(',', 1)[1]
            buffers.append(base64.b64decode(b64))
    return js, buffers


def consolidate_buffers(js, buffers):
    """Merge all buffers into a single bytearray (future BIN chunk), rewriting
    bufferViews. Returns the bytearray."""
    out = bytearray()
    bases = []
    for b in buffers:
        while len(out) % 4:
            out.append(0)
        bases.append(len(out))
        out.extend(b)
    for bv in js.get('bufferViews', []):
        bv['byteOffset'] = bv.get('byteOffset', 0) + bases[bv['buffer']]
        bv['buffer'] = 0
    return out


def write_glb(path, js, bin_chunk):
    jb = json.dumps(js, separators=(',', ':')).encode()
    jb += b' ' * (-len(jb) % 4)
    bb = bytes(bin_chunk) + b'\0' * (-len(bin_chunk) % 4)
    total = 12 + 8 + len(jb) + 8 + len(bb)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total))
        f.write(struct.pack('<II', len(jb), 0x4E4F534A))
        f.write(jb)
        f.write(struct.pack('<II', len(bb), 0x004E4942))
        f.write(bb)


def read_accessor(js, bin_chunk, acc_idx):
    """bin_chunk: a single consolidated bytearray (bufferViews all on buffer 0)."""
    acc = js['accessors'][acc_idx]
    bv = js['bufferViews'][acc['bufferView']]
    assert bv['buffer'] == 0, 'call consolidate_buffers first'
    ncomp = TYPE_N[acc['type']]
    dt = COMP_NP[acc['componentType']]
    itemsize = np.dtype(dt).itemsize * ncomp
    stride = bv.get('byteStride') or itemsize
    base = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
    count = acc['count']
    if stride == itemsize:
        arr = np.frombuffer(bytes(bin_chunk[base:base + count * itemsize]), dtype=dt)
        arr = arr.reshape(count, ncomp)
    else:
        arr = np.zeros((count, ncomp), dtype=dt)
        for i in range(count):
            o = base + i * stride
            arr[i] = np.frombuffer(bytes(bin_chunk[o:o + itemsize]), dtype=dt)
    return arr.copy()


def append_accessor(js, bin_chunk, data, comp_type, type_str, minmax=False):
    data = np.ascontiguousarray(data)
    while len(bin_chunk) % 4:
        bin_chunk.append(0)
    off = len(bin_chunk)
    bin_chunk.extend(data.tobytes())
    bv_idx = len(js['bufferViews'])
    js['bufferViews'].append({'buffer': 0, 'byteOffset': off,
                              'byteLength': data.nbytes,
                              'target': 34962})
    acc_idx = len(js['accessors'])
    acc = {'bufferView': bv_idx, 'byteOffset': 0, 'componentType': comp_type,
           'count': int(data.shape[0]), 'type': type_str}
    if minmax:
        acc['min'] = [float(x) for x in data.min(axis=0)]
        acc['max'] = [float(x) for x in data.max(axis=0)]
    js['accessors'].append(acc)
    return acc_idx


def gc_glb(js, bin_chunk):
    """Drop accessors/bufferViews no longer referenced (old pool data, stripped
    animations) and rebuild the BIN chunk. Returns the new bytearray."""
    used_acc = set()
    for mesh in js.get('meshes', []):
        for p in mesh['primitives']:
            used_acc.update(p['attributes'].values())
            if 'indices' in p:
                used_acc.add(p['indices'])
    for skin in js.get('skins', []):
        if 'inverseBindMatrices' in skin:
            used_acc.add(skin['inverseBindMatrices'])
    used_bv = {js['accessors'][a]['bufferView'] for a in used_acc}
    used_bv.update(img['bufferView'] for img in js.get('images', []) if 'bufferView' in img)

    new_bin = bytearray()
    bv_remap = {}
    new_bvs = []
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

    acc_remap = {}
    new_accs = []
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
    for img in js.get('images', []):
        if 'bufferView' in img:
            img['bufferView'] = bv_remap[img['bufferView']]
    js['buffers'] = [{'byteLength': len(new_bin)}]
    return new_bin


def skin_info(js, bin_chunk):
    skin = js['skins'][0]
    joints = skin['joints']
    names = [js['nodes'][n].get('name', f'?{n}') for n in joints]
    ibm_raw = read_accessor(js, bin_chunk, skin['inverseBindMatrices']).astype(np.float64)
    # glTF matrices are column-major: element order m00 m10 m20 m30 m01 ...
    ibms = np.array([blk.reshape(4, 4).T for blk in ibm_raw])
    # joint-index parent map from node children lists
    node_parent = {}
    for ni, node in enumerate(js['nodes']):
        for c in node.get('children', []):
            node_parent[c] = ni
    node_to_joint = {n: i for i, n in enumerate(joints)}
    parent = []
    for n in joints:
        p = node_parent.get(n)
        parent.append(node_to_joint.get(p, -1) if p is not None else -1)
    return names, ibms, parent


SUFFIX_MAP = {'a': '1', 'b': '2', 'c': '3', 'd': '4'}


def name_variants(name):
    """Suffix-normalized variants for T3 matching (lEara->lEar1, lTopStrap->lTopStrap1)."""
    out = []
    m = re.match(r'^(.*?)([a-dA-D])$', name)
    if m and m.group(1):
        out.append(m.group(1) + SUFFIX_MAP[m.group(2).lower()])
    m = re.match(r'^(.*?)([1-4])$', name)
    if m and m.group(1):
        digit = int(m.group(2))
        out.append(m.group(1) + 'abcd'[digit - 1])
        if digit == 1:
            out.append(m.group(1))  # lTopStrap1 -> lTopStrap
    out.append(name + '1')  # lTopStrap -> lTopStrap1
    return out


def build_joint_map(dn, tn, d_parent):
    """donor joint idx -> (d_eff, t_idx, tier). tier: 1 exact, 2 ci, 3 suffix, 4 ancestor."""
    t_exact = {n: i for i, n in enumerate(tn)}
    t_ci = {}
    for i, n in enumerate(tn):
        t_ci.setdefault(n.lower(), i)

    def match_name(n):
        if n in t_exact:
            return t_exact[n], 1
        if n.lower() in t_ci:
            return t_ci[n.lower()], 2
        for v in name_variants(n):
            if v in t_exact:
                return t_exact[v], 3
            if v.lower() in t_ci:
                return t_ci[v.lower()], 3
        return None, 0

    mapping = {}
    for dj, n in enumerate(dn):
        k, tier = match_name(n)
        if k is not None:
            mapping[dj] = (dj, k, tier)
            continue
        # T4: walk donor ancestors until one name-matches
        a = d_parent[dj]
        while a >= 0:
            k, _t = match_name(dn[a])
            if k is not None:
                mapping[dj] = (a, k, 4)
                break
            a = d_parent[a]
        if dj not in mapping:
            mapping[dj] = (None, None, 0)
    return mapping


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--donor', required=True)
    ap.add_argument('--target', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--drop-joints', default=None,
                    help='regex of DONOR joint names whose majority-weighted triangles are culled')
    ap.add_argument('--alias', default=None,
                    help='comma list donorJoint=donorJoint redirects applied before matching '
                         '(e.g. mask=head glues the mask to the head bone)')
    ap.add_argument('--max-unmatched-weight', type=float, default=0.01,
                    help='max fraction of kept weight with NO deterministic mapping '
                         '(nameless mats slots / no matchable ancestor) — the actual '
                         'garble risk. Ancestor fallback is deterministic and allowed.')
    ap.add_argument('--report', default=None)
    args = ap.parse_args()

    js, dbufs = read_glb(args.donor)
    binc = consolidate_buffers(js, dbufs)
    tjs, tbufs = read_glb(args.target)
    tbin = consolidate_buffers(tjs, tbufs)
    # animations are irrelevant to a merc mesh replacement and dominate file size
    js.pop('animations', None)

    dn, d_ibm, d_parent = skin_info(js, binc)
    tn, t_ibm, _tp = skin_info(tjs, tbin)
    t_ibm_inv = np.array([np.linalg.inv(m) for m in t_ibm])

    mapping = build_joint_map(dn, tn, d_parent)
    drop_re = re.compile(args.drop_joints) if args.drop_joints else None
    drop_set = {i for i, n in enumerate(dn) if drop_re and drop_re.search(n)}

    # donor-name redirects: influence (weights AND re-pose frame) moves to the
    # redirect donor joint, which then matches normally
    if args.alias:
        d_index = {n: i for i, n in enumerate(dn)}
        for spec in args.alias.split(','):
            src, dst = spec.split('=')
            if src not in d_index or dst not in d_index:
                print(f"alias {spec}: joint not in donor skin", file=sys.stderr)
                sys.exit(1)
            mapping[d_index[src]] = mapping[d_index[dst]]

    # per-(d_eff, t) pair re-pose matrices
    pair_ids = {}
    pair_mats = []

    def pair(d_eff, t_idx):
        key = (d_eff, t_idx)
        if key not in pair_ids:
            pair_ids[key] = len(pair_mats)
            pair_mats.append(t_ibm_inv[t_idx] @ d_ibm[d_eff])
        return pair_ids[key]

    # collect shared accessors across prims (rip shares one vertex set)
    prims = []
    for mesh in js['meshes']:
        prims.extend(mesh['primitives'])
    pos_acc = prims[0]['attributes']['POSITION']
    j_acc = prims[0]['attributes']['JOINTS_0']
    w_acc = prims[0]['attributes']['WEIGHTS_0']
    for p in prims:
        assert p['attributes']['POSITION'] == pos_acc, 'prims do not share POSITION accessor'
        assert p['attributes']['JOINTS_0'] == j_acc and p['attributes']['WEIGHTS_0'] == w_acc

    # NOTE: the rip exporter shares ONE level-wide vertex pool across every model
    # in the level; a model's prims merely index into it. Everything below first
    # culls dropped-joint triangles, then COMPACTS to the vertices this model
    # actually uses (otherwise metrics run over other models' vertices and the
    # importer ingests the whole level pool per prim).
    pos = read_accessor(js, binc, pos_acc).astype(np.float64)
    J = read_accessor(js, binc, j_acc).astype(np.int64)
    W = read_accessor(js, binc, w_acc).astype(np.float64)
    col_acc = prims[0]['attributes'].get('COLOR_0')
    uv_acc = prims[0]['attributes'].get('TEXCOORD_0')
    colors = read_accessor(js, binc, col_acc) if col_acc is not None else None
    uvs = read_accessor(js, binc, uv_acc) if uv_acc is not None else None

    # fraction of each pool vertex's weight sitting on dropped donor joints
    wsum = W.sum(axis=1)
    wsum[wsum <= 0] = 1.0
    if drop_set:
        drop_mask = np.isin(J, sorted(drop_set)) & (W > 0)
        pool_dropfrac = (W * drop_mask).sum(axis=1) / wsum
    else:
        pool_dropfrac = np.zeros(len(pos))

    # cull majority-dropped triangles, then compact to used vertices
    culled_tris = 0
    prim_tris = []
    for p in prims:
        idx = read_accessor(js, binc, p['indices']).reshape(-1)
        tris = idx.reshape(-1, 3)
        keep = ~(pool_dropfrac[tris] > 0.5).any(axis=1)
        culled_tris += int((~keep).sum())
        prim_tris.append(tris[keep])
    used = np.unique(np.concatenate([t.reshape(-1) for t in prim_tris]))
    old_to_new = np.full(len(pos), -1, dtype=np.int64)
    old_to_new[used] = np.arange(len(used))
    prim_tris = [old_to_new[t] for t in prim_tris]
    pos = pos[used]
    J = J[used]
    W = W[used]
    if colors is not None:
        colors = colors[used]
    if uvs is not None:
        uvs = uvs[used]
    n_verts = len(pos)

    tier_weight = {0: 0.0, 1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0}
    dropped_weight = 0.0
    unmatched_hits = {}
    new_pos = np.zeros_like(pos)
    out_j = np.zeros((n_verts, 4), dtype=np.uint8)
    out_w = np.zeros((n_verts, 4), dtype=np.float32)

    for i in range(n_verts):
        infl = {}   # t_idx -> weight
        mats = {}   # t_idx -> pair matrix id (first wins)
        for s in range(4):
            w = float(W[i, s])
            if w <= 0.0:
                continue
            dj = int(J[i, s])
            if dj >= len(dn):
                # merc mats slot beyond the ripped skin (nameless extras, e.g.
                # effect-local matrices) — nothing to remap by name
                tier_weight[0] += w
                unmatched_hits[f'#mats{dj + 1}'] = unmatched_hits.get(f'#mats{dj + 1}', 0.0) + w
                continue
            if dj in drop_set:
                dropped_weight += w
                continue
            d_eff, t_idx, tier = mapping.get(dj, (None, None, 0))
            tier_weight[tier] += w
            if t_idx is None:
                unmatched_hits[dn[dj]] = unmatched_hits.get(dn[dj], 0.0) + w
                continue
            infl[t_idx] = infl.get(t_idx, 0.0) + w
            mats.setdefault(t_idx, pair(d_eff, t_idx))
        if not infl:
            # fully dropped/unmatched vertex: bind rigidly to joint 3 (first real bone)
            new_pos[i] = pos[i]
            out_j[i, 0] = 2  # importer +2 -> mats 4; harmless, tris get culled below
            out_w[i, 0] = 1.0
            continue
        # re-pose with the full influence set
        total = sum(infl.values())
        v = np.array([pos[i, 0], pos[i, 1], pos[i, 2], 1.0])
        acc = np.zeros(4)
        for t_idx, w in infl.items():
            acc += (w / total) * (pair_mats[mats[t_idx]] @ v)
        new_pos[i] = acc[:3]
        # top-3 by weight, renormalized
        top = sorted(infl.items(), key=lambda kv: -kv[1])[:3]
        tsum = sum(w for _k, w in top)
        for s, (t_idx, w) in enumerate(top):
            assert t_idx >= 1, f'vertex bound to joint 0 ({tn[0]})'
            out_j[i, s] = t_idx - 1        # importer adds +2 -> merc mats = t_idx + 1
            out_w[i, s] = w / tsum

    # welded, area-weighted smooth normals on the re-posed compacted mesh
    keys = np.round(new_pos, 4)
    _uniq, weld = np.unique(keys, axis=0, return_inverse=True)
    norm_acc_w = np.zeros((weld.max() + 1, 3))
    for tris in prim_tris:
        a = new_pos[tris[:, 0]]
        b = new_pos[tris[:, 1]]
        c = new_pos[tris[:, 2]]
        fn = np.cross(b - a, c - a)  # length == 2*area -> area weighting
        for corner in range(3):
            np.add.at(norm_acc_w, weld[tris[:, corner]], fn)
    lens = np.linalg.norm(norm_acc_w, axis=1, keepdims=True)
    lens[lens < 1e-12] = 1.0
    norm_w = norm_acc_w / lens
    normals = norm_w[weld].astype(np.float32)

    # write compacted attribute + index accessors and point every prim at them
    new_pos_acc = append_accessor(js, binc, new_pos.astype(np.float32), 5126, 'VEC3', minmax=True)
    new_nrm_acc = append_accessor(js, binc, normals, 5126, 'VEC3')
    new_j_acc = append_accessor(js, binc, out_j, 5121, 'VEC4')
    new_w_acc = append_accessor(js, binc, out_w, 5126, 'VEC4')
    new_col_acc = (append_accessor(js, binc, colors, js['accessors'][col_acc]['componentType'],
                                   'VEC4') if colors is not None else None)
    new_uv_acc = (append_accessor(js, binc, uvs.astype(np.float32), 5126, 'VEC2')
                  if uvs is not None else None)
    for p, tris in zip(prims, prim_tris):
        assert (tris >= 0).all(), 'culled triangle referencing an unused vertex'
        p['indices'] = append_accessor(js, binc,
                                       tris.reshape(-1, 1).astype(np.uint32), 5125, 'SCALAR')
        p['attributes']['POSITION'] = new_pos_acc
        p['attributes']['NORMAL'] = new_nrm_acc
        p['attributes']['JOINTS_0'] = new_j_acc
        p['attributes']['WEIGHTS_0'] = new_w_acc
        if new_col_acc is not None:
            p['attributes']['COLOR_0'] = new_col_acc
        if new_uv_acc is not None:
            p['attributes']['TEXCOORD_0'] = new_uv_acc

    # enable custom weights on every mesh node
    for node in js['nodes']:
        if 'mesh' in node:
            node.setdefault('extras', {})['enable_custom_weights'] = 1

    # replace the skin with the TARGET skeleton (importer max_bones = 3 + len(joints))
    tskin = tjs['skins'][0]
    node_off = len(js['nodes'])
    t_joint_nodes = tskin['joints']
    t_local = {n: i for i, n in enumerate(t_joint_nodes)}
    for n in t_joint_nodes:
        tnode = tjs['nodes'][n]
        nn = {'name': tnode.get('name', '?')}
        if 'matrix' in tnode:
            nn['matrix'] = tnode['matrix']
        kids = [node_off + t_local[c] for c in tnode.get('children', []) if c in t_local]
        if kids:
            nn['children'] = kids
        js['nodes'].append(nn)
    t_ibm_raw = read_accessor(tjs, tbin, tskin['inverseBindMatrices']).astype(np.float32)
    new_ibm_acc = append_accessor(js, binc, t_ibm_raw, 5126, 'MAT4')
    js['skins'] = [{'joints': [node_off + i for i in range(len(t_joint_nodes))],
                    'skeleton': node_off,
                    'inverseBindMatrices': new_ibm_acc}]
    binc = gc_glb(js, binc)
    write_glb(args.out, js, binc)

    total_w = sum(tier_weight.values()) + dropped_weight
    named_w = tier_weight[1] + tier_weight[2] + tier_weight[3]
    considered = total_w - dropped_weight
    named_frac = named_w / considered if considered > 0 else 0.0
    unmatched_frac = tier_weight[0] / considered if considered > 0 else 1.0
    lines = []
    lines.append(f"retarget {args.donor} -> {args.target}")
    lines.append(f"  verts={n_verts} donor_joints={len(dn)} target_joints={len(tn)}")
    lines.append(f"  weight by tier: exact={tier_weight[1]:.1f} ci={tier_weight[2]:.1f} "
                 f"suffix={tier_weight[3]:.1f} ancestor={tier_weight[4]:.1f} "
                 f"unmatched={tier_weight[0]:.1f} dropped={dropped_weight:.1f}")
    lines.append(f"  name-matched (T1-T3): {named_frac:.4f}; UNMATCHED (garble-risk) "
                 f"fraction: {unmatched_frac:.4f} (gate <= {args.max_unmatched_weight})")
    if culled_tris:
        lines.append(f"  culled {culled_tris} triangles on dropped joints "
                     f"({sorted(dn[i] for i in drop_set)})")
    if args.alias:
        lines.append(f"  aliases applied: {args.alias}")
    t4 = sorted(((dn[dj], m[0], m[1]) for dj, m in mapping.items() if m[2] == 4),
                key=lambda x: x[0])
    if t4:
        lines.append("  ancestor-fallback joints: " +
                     ", ".join(f"{n}->{tn[t]}" for n, _e, t in t4))
    if unmatched_hits:
        lines.append("  UNMATCHED joints carrying weight: " +
                     ", ".join(f"{n}({w:.1f})" for n, w in sorted(unmatched_hits.items())))
    max_move = float(np.linalg.norm(new_pos - pos, axis=1).max())
    lines.append(f"  re-pose max vertex displacement: {max_move:.4f}")
    report = "\n".join(lines)
    print(report)
    if args.report:
        with open(args.report, 'w') as f:
            f.write(report + "\n")
    if unmatched_frac > args.max_unmatched_weight:
        print(f"FAIL: unmatched weight {unmatched_frac:.4f} > {args.max_unmatched_weight} — "
              f"refusing to ship a garble-risk retarget", file=sys.stderr)
        sys.exit(2)


if __name__ == '__main__':
    main()
