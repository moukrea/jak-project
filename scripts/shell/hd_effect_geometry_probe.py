#!/usr/bin/env python3
"""hd_effect_geometry_probe.py — per-EFFECT geometry probe on a ripped donor GLB.

Grecharged-hd-models4 CYCLE 5 item 1 (jakm-hd = "JAK 3 MASQUE BAISSE"). The owner's bar is that
the unmasked look must show the FACE UNCOVERED, and the owner rule of 2026-08-04 forbids captures
as a validation instrument: the proof has to be a physical measurement on the artifact.

The decompiler's merc GLB export stamps every primitive with `extras.goal_effect_idx`, so the GLB
carries the exact same effect partition as the fr3 MercModel. This tool measures, per effect:

  * vertex count and axis-aligned bounding box,
  * the fraction of its vertices that sit in the FACE BOX (a caller-supplied y/z window),

which is what distinguishes the jakc donor's TWO `jakc-scarf` effects: effect 0 is the static scarf
pulled UP OVER THE NOSE (it overlaps the face box) and effect 17 is the animated scarf hanging at
the NECK (it does not). Dropping effect 0 at append time is therefore provably "mask down, face
bare" — no pixels involved.

usage:
  hd_effect_geometry_probe.py <donor.glb> [--effects 0,17,16] [--face-box y0,y1,z0,z1]
  hd_effect_geometry_probe.py <donor.glb> --list          # bbox of every effect
"""
import argparse
import json
import struct
import sys


def load_glb(path):
    """Returns (json, buffers[]). The merc rip uses SEVERAL buffers: buffer 0 is the GLB BIN
    chunk, the rest are base64 data URIs, so a bufferView must be resolved through its buffer."""
    import base64
    d = open(path, 'rb').read()
    if d[:4] != b'glTF':
        sys.exit(f"not a GLB: {path}")
    off, chunks = 12, []
    while off < len(d):
        ln, ty = struct.unpack_from('<II', d, off)
        chunks.append((ty, d[off + 8:off + 8 + ln]))
        off += 8 + ln
    js = json.loads(chunks[0][1].decode('utf-8'))
    bins = [c[1] for c in chunks if c[0] == 0x004E4942]
    bufs = []
    for b in js['buffers']:
        uri = b.get('uri')
        if uri is None:
            bufs.append(bins.pop(0))
        elif uri.startswith('data:'):
            bufs.append(base64.b64decode(uri.split(',', 1)[1]))
        else:
            sys.exit(f"external buffer uri unsupported: {uri[:40]}")
    return js, bufs


def read_vec3(js, bufs, acc_idx):
    acc = js['accessors'][acc_idx]
    if acc['type'] != 'VEC3' or acc['componentType'] != 5126:
        sys.exit("POSITION accessor is not float32 VEC3 — unsupported rip")
    bv = js['bufferViews'][acc['bufferView']]
    blob = bufs[bv.get('buffer', 0)]
    base = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
    stride = bv.get('byteStride') or 12
    return [struct.unpack_from('<3f', blob, base + i * stride) for i in range(acc['count'])]


_IDX_FMT = {5121: ('<B', 1), 5123: ('<H', 2), 5125: ('<I', 4)}


def read_indices(js, bufs, acc_idx):
    """The merc rip shares ONE POSITION accessor across every primitive of the model, so a
    primitive's own geometry is only reachable through its index buffer."""
    acc = js['accessors'][acc_idx]
    fmt, sz = _IDX_FMT[acc['componentType']]
    bv = js['bufferViews'][acc['bufferView']]
    blob = bufs[bv.get('buffer', 0)]
    base = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
    return {struct.unpack_from(fmt, blob, base + i * sz)[0] for i in range(acc['count'])}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('glb')
    ap.add_argument('--effects', default='')
    ap.add_argument('--face-box', default='')
    ap.add_argument('--list', action='store_true')
    a = ap.parse_args()

    js, bufs = load_glb(a.glb)
    pos_cache = {}
    per_effect = {}
    for pr in js['meshes'][0]['primitives']:
        e = (pr.get('extras') or {}).get('goal_effect_idx')
        if e is None:
            sys.exit("rip has no extras.goal_effect_idx — re-rip with the merc exporter")
        pa = pr['attributes']['POSITION']
        if pa not in pos_cache:
            pos_cache[pa] = read_vec3(js, bufs, pa)
        allpos = pos_cache[pa]
        used = read_indices(js, bufs, pr['indices'])
        per_effect.setdefault(e, []).extend(allpos[i] for i in sorted(used))

    def bbox(vs):
        return tuple(min(v[i] for v in vs) for i in range(3)), tuple(max(v[i] for v in vs) for i in range(3))

    if a.list or not a.effects:
        for e in sorted(per_effect):
            lo, hi = bbox(per_effect[e])
            print(f"EFFECT {e:2d} verts={len(per_effect[e]):5d} "
                  f"x=[{lo[0]:+.3f},{hi[0]:+.3f}] y=[{lo[1]:+.3f},{hi[1]:+.3f}] z=[{lo[2]:+.3f},{hi[2]:+.3f}]")
        if not a.effects:
            return

    want = [int(x) for x in a.effects.split(',') if x != '']
    fb = None
    if a.face_box:
        y0, y1, z0, z1 = (float(x) for x in a.face_box.split(','))
        fb = (y0, y1, z0, z1)
    for e in want:
        vs = per_effect.get(e)
        if vs is None:
            print(f"EFFECT {e}: ABSENT")
            continue
        lo, hi = bbox(vs)
        line = (f"EFFECT {e:2d} verts={len(vs):5d} "
                f"y=[{lo[1]:+.3f},{hi[1]:+.3f}] z=[{lo[2]:+.3f},{hi[2]:+.3f}]")
        if fb:
            y0, y1, z0, z1 = fb
            n = sum(1 for v in vs if y0 <= v[1] <= y1 and z0 <= v[2] <= z1)
            line += f" in_face_box={n} ({100.0 * n / len(vs):.1f}%)"
        print(line)


if __name__ == '__main__':
    main()
