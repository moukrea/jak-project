#!/usr/bin/env python3
# Grecharged-hd-eye-scale: bind-pose census of ALL geometry skinned to the eye joints,
# stock sidekick vs HD daxter-highres. The prior attempt measured only the iris-textured
# prims (bbox ratio 0.984); this measures the full skinned set — if the HD eyeball has a
# sclera ball skinned to Leye/Reye with no stock counterpart, the same joint scale grows
# a much larger absolute volume, and the two clouds can meet.
import sys

import numpy as np

sys.path.insert(0, __file__.rsplit('/', 2)[0] + '/scripts/shell')
from retarget_hd_models import read_glb, consolidate_buffers, read_accessor


def eye_census(glb_path, eye_name_frags=('eye',), wmin=0.05):
    js, bufs = read_glb(glb_path)
    binc = consolidate_buffers(js, bufs)
    skin = js['skins'][0]
    joints = skin['joints']
    names = [js['nodes'][j].get('name', f'j{j}') for j in joints]
    eye_slots = {}
    for si, nm in enumerate(names):
        low = nm.lower()
        if any(f in low for f in eye_name_frags) and 'brow' not in low and 'lid' not in low:
            eye_slots[si] = nm
    ibm = read_accessor(js, binc, skin['inverseBindMatrices']).reshape(-1, 4, 4)
    # bind-pose joint pivot = inverse(IBM) translation (glTF column-major storage)
    pivots = {}
    for si in eye_slots:
        m = ibm[si].T  # to row-major math orientation
        inv = np.linalg.inv(m)
        pivots[si] = inv[:3, 3]

    prims = []
    for mesh in js['meshes']:
        prims.extend(mesh['primitives'])
    out = {si: [] for si in eye_slots}
    total_v = 0
    for p in prims:
        a = p['attributes']
        if 'JOINTS_0' not in a:
            continue
        pos = read_accessor(js, binc, a['POSITION']).reshape(-1, 3)
        jix = read_accessor(js, binc, a['JOINTS_0']).reshape(-1, 4)
        wgt = read_accessor(js, binc, a['WEIGHTS_0']).reshape(-1, 4)
        total_v += len(pos)
        for si in eye_slots:
            m = ((jix == si) & (wgt > wmin)).any(axis=1)
            if m.any():
                out[si].append(pos[m])
    print(f'== {glb_path}')
    print(f'   joints={len(joints)} eye_joints={list(eye_slots.values())} total_verts={total_v}')
    clouds = {}
    for si, nm in eye_slots.items():
        if not out[si]:
            print(f'   {nm}: NO skinned verts (w>{wmin})')
            continue
        v = np.concatenate(out[si])
        piv = pivots[si]
        d = np.linalg.norm(v - piv, axis=1)
        bb = v.max(0) - v.min(0)
        clouds[nm] = v
        print(f'   {nm}: verts={len(v)} bbox=({bb[0]:.4f},{bb[1]:.4f},{bb[2]:.4f}) '
              f'pivot_dist mean={d.mean():.4f} max={d.max():.4f} pivot=({piv[0]:.3f},{piv[1]:.3f},{piv[2]:.3f})')
    ks = sorted(clouds)
    if len(ks) == 2:
        a, b = clouds[ks[0]], clouds[ks[1]]
        # exact min inter-cloud distance (clouds are small)
        dmin = min(np.linalg.norm(b - pa, axis=1).min() for pa in a)
        print(f'   bind gap {ks[0]}<->{ks[1]}: {dmin:.4f}')
    return clouds


for path in sys.argv[1:]:
    eye_census(path)
