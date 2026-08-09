#!/usr/bin/env python3
"""Cycle 14 — per-link EXTREMAL skinned-vertex offsets, in bone-local bind space.

Cycle 14 diagnosis: the audit measured BONES while the owner sees the MESH — the mayor's
bow links sat within tolerance while his skinned ribbon pierced his belly.  The runtime
therefore needs, per physics chain link, the handful of skinned vertices that stick out
FURTHEST from the link (perpendicular extremes in four quadrants, plus the axial tip
overhang), expressed in the bone's own bind-local frame so they can be carried by the
solved link transform every frame and tested against the body volumes at the SURFACE.

Everything geometric is reused from physics_c6_volumes.py (same GLB sources, same unit
convention: glTF metres x 4096 = game units, same WMIN vertex-ownership threshold).

Outputs:
  * recharged_assets/physics_mesh.txt                 the data file the C++ runtime parses
  * .autoport/reports/Grecharged-secondary-motion/mesh_extents_c14.txt   the audit

Usage:  python3 .autoport/physics_c14_meshsamples.py
"""
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import physics_c6_volumes as c6  # noqa: E402  (GLB loading, chains-file parsing, WMIN)
from retarget_hd_models import read_glb, consolidate_buffers, skin_info  # noqa: E402

REPO = c6.REPO
CHAINS = c6.CHAINS
WMIN = c6.WMIN
UNITS = c6.UNITS
PRUNE_MARGIN = 8.0            # a sample within (link radius + this) adds nothing beyond
                              # the existing center+radius test — dropped, and counted.
OUT_MESH = os.path.join(REPO, 'recharged_assets', 'physics_mesh.txt')
OUT_REPORT = os.path.join(REPO, '.autoport', 'reports', 'Grecharged-secondary-motion',
                          'mesh_extents_c14.txt')


def load_geometry_ibm(model):
    """c6.load_geometry plus each joint's inverseBindMatrix (glTF metres, column-major
    already transposed to row convention by skin_info)."""
    geo = c6.load_geometry(model)
    if geo is None:
        return None
    js, bufs = read_glb(geo['path'])
    binc = consolidate_buffers(js, bufs)
    _names, ibms, _parent = skin_info(js, binc)
    geo['ibms'] = ibms
    return geo


def to_bone_local(ibm, pts_game):
    """world bind position (GAME units) -> this bone's local frame (GAME units).

    The IBM is in GLB metres; the rotation part is unit-invariant and the translation
    scales by UNITS, so transforming the game-unit point directly with a scaled
    translation is exactly the metres-space transform followed by x4096."""
    return pts_game @ ibm[:3, :3].T + ibm[:3, 3] * UNITS


def joint_cloud(geo, j):
    """indices of vertices holding >= WMIN of their weight on joint j (same rule as
    c6.link_radius: a vertex may belong to several links, on purpose)."""
    J, W = geo['J'], geo['W']
    sel = np.zeros(len(geo['V']), dtype=bool)
    for c in range(J.shape[1]):
        sel |= (J[:, c] == j) & (W[:, c] >= WMIN)
    return np.flatnonzero(sel)


def perp_basis(axis):
    """two unit vectors orthogonal to axis (and each other) for quadrant binning."""
    ref = np.array([1.0, 0.0, 0.0]) if abs(axis[0]) < 0.9 else np.array([0.0, 1.0, 0.0])
    e1 = np.cross(axis, ref)
    e1 /= np.linalg.norm(e1)
    e2 = np.cross(axis, e1)
    return e1, e2


def link_radii_from_chain(ch, nlinks):
    """per-link radius from the chain line's radii= comma list (fallback radius=)."""
    fall = float(ch.kv('radius') or 0.0)
    rtxt = ch.kv('radii')
    if not rtxt:
        return [fall] * nlinks
    vals = [float(x) for x in rtxt.split(',') if x]
    if not vals:
        return [fall] * nlinks
    return [vals[min(i, len(vals) - 1)] for i in range(nlinks)]


def process_link(geo, jidx, li, chain_idx, rad):
    """-> dict(samples=[(x,y,z)...], perp_max, axial_over, nverts) for link li of a chain
    whose resolved joint indices are chain_idx.  All numbers in GAME units, bone-local."""
    j = chain_idx[li]
    ibm = geo['ibms'][j]
    P = geo['P']
    cloud = joint_cloud(geo, j)
    if len(cloud) == 0:
        return dict(samples=[], perp_max=0.0, axial_over=0.0, nverts=0)
    off = to_bone_local(ibm, geo['V'][cloud])          # bone-local offsets, game units

    # sanity on the unit/matrix convention, in two parts, both asserted:
    #  1. IBM @ (this joint's own bind position) is 0 by definition of a bind matrix —
    #     a wrong transpose or an unscaled translation breaks this immediately.
    #  2. where the IBM is near-RIGID (singular values ~1), it preserves lengths, so
    #     |off_local| must match the world vertex-to-bone distance.  Some rigs carry
    #     genuine bind scale (keira-hd joints reach s=9.68); there the runtime's skinning
    #     uses that same scaled IBM, so the scaled offsets are the correct ones and only
    #     check 1 applies.
    self_local = to_bone_local(ibm, P[j][None, :])[0]
    span = float(np.max(np.linalg.norm(geo['V'][cloud] - P[j], axis=1))) + 1.0
    assert np.linalg.norm(self_local) <= max(1.0, 1e-3 * span), \
        'joint %s does not map to its own local origin (|%.3f|) — unit/IBM ' \
        'convention broken' % (geo['names'][j], float(np.linalg.norm(self_local)))
    sv = np.linalg.svd(ibm[:3, :3], compute_uv=False)
    if 0.99 <= sv.min() and sv.max() <= 1.01:
        world_d = np.linalg.norm(geo['V'][cloud] - P[j], axis=1)
        med_w = float(np.median(world_d))
        if med_w > 1.0:
            ratio = float(np.median(np.linalg.norm(off, axis=1))) / med_w
            assert 0.9 <= ratio <= 1.1, \
                'bone-local offsets do not match world distances (ratio %.3f) — ' \
                'unit/IBM convention broken for joint %s' % (ratio, geo['names'][j])

    # axis: bone-local direction toward the NEXT link joint (tip: FROM the previous
    # joint; single-link chain: from the parent bone).
    seglen = 0.0
    if li + 1 < len(chain_idx):
        nxt = to_bone_local(ibm, P[chain_idx[li + 1]][None, :])[0]
        axis, seglen = nxt, float(np.linalg.norm(nxt))
    elif li > 0:
        prv = to_bone_local(ibm, P[chain_idx[li - 1]][None, :])[0]
        axis = -prv                                    # direction FROM the previous joint
    else:
        p = geo['parent'][j]
        if p is not None and 0 <= p < len(P) and np.all(np.isfinite(P[p])):
            axis = -to_bone_local(ibm, P[p][None, :])[0]
        else:
            axis = np.array([0.0, 1.0, 0.0])
    n = float(np.linalg.norm(axis))
    axis = axis / n if n > 1e-6 else np.array([0.0, 1.0, 0.0])

    d_axial = off @ axis
    perp = off - np.outer(d_axial, axis)
    d_perp = np.linalg.norm(perp, axis=1)
    over = np.maximum(0.0, d_axial - seglen)           # mesh past the bone segment

    e1, e2 = perp_basis(axis)
    quad = (np.arctan2(perp @ e2, perp @ e1) >= 0).astype(int) * 2 \
        + (np.abs(np.arctan2(perp @ e2, perp @ e1)) > np.pi / 2).astype(int)
    picks = []
    for q in range(4):
        m = np.flatnonzero(quad == q)
        if len(m):
            picks.append(int(m[np.argmax(d_perp[m])]))
    ax_i = int(np.argmax(d_axial))
    if d_axial[ax_i] > seglen and ax_i not in picks:   # tip overhang: 5th sample
        picks.append(ax_i)

    thr = rad + PRUNE_MARGIN
    samples = []
    for i in picks:
        if d_perp[i] <= thr and over[i] <= thr:
            continue                                   # inside the center+radius test
        samples.append(tuple(round(float(x), 1) for x in off[i]))
    # dedupe (two quadrant maxima can round to the same vertex position)
    seen, uniq = set(), []
    for s in samples:
        if s not in seen:
            seen.add(s)
            uniq.append(s)
    return dict(samples=uniq[:5], perp_max=float(np.max(d_perp)),
                axial_over=float(np.max(over)), nverts=int(len(cloud)))


def main():
    lines, sections = c6.parse_chains_file(CHAINS)
    mesh_out = [
        '# physics_mesh.txt — per-link extremal skinned-vertex offsets '
        '(bone-local bind space, game units)',
        '# generated by .autoport/physics_c14_meshsamples.py — derived data, '
        'DO NOT hand-tune',
    ]
    rep = []
    failed_models = []       # (model, reason)
    empty_links = []         # (model, chain, link, joint name)
    total_ms = 0
    models_processed = 0     # alias names of sections whose geometry loaded
    per_chain_samples = {}   # (model, chain) -> total samples
    per_chain_extents = {}   # (model, chain) -> list of (rad, perp_max, axial_over)

    for sec in sections:
        model = sec.names[0]
        geo, err = None, None
        for nm in sec.names:
            try:
                geo = load_geometry_ibm(nm)
            except Exception as e:  # noqa: BLE001 — recorded, never silently skipped
                err = '%s: %s' % (type(e).__name__, e)
                geo = None
            if geo is not None:
                break
        if geo is None:
            failed_models.append((model, err or 'no GLB found (hd_anim k2e / '
                                                'decompiler_out levels)'))
            continue
        models_processed += len(sec.names)
        nmap = {n: i for i, n in enumerate(geo['names'])}
        mesh_out.append('model ' + ' '.join(sec.names))
        for ch in sec.chains:
            idx = [nmap.get(jn) for _, jn in ch.joints]
            rads = link_radii_from_chain(ch, len(idx))
            key = (model, ch.name)
            per_chain_samples.setdefault(key, 0)
            per_chain_extents.setdefault(key, [])
            for li, (j, (_, jname)) in enumerate(zip(idx, ch.joints)):
                if j is None or not np.all(np.isfinite(geo['P'][j])):
                    empty_links.append((model, ch.name, li,
                                        jname + ' (joint not in rig)'))
                    continue
                r = process_link(geo, j, li, idx if all(
                    x is not None for x in idx) else
                    [x if x is not None else j for x in idx], rads[li])
                if r['nverts'] == 0:
                    empty_links.append((model, ch.name, li, jname))
                rep.append('%s %s %d radii_p25=%.0f mesh_perp_max=%.1f '
                           'mesh_axial_over=%.1f nverts=%d nsamples=%d'
                           % (model, ch.name, li, rads[li], r['perp_max'],
                              r['axial_over'], r['nverts'], len(r['samples'])))
                per_chain_samples[key] += len(r['samples'])
                per_chain_extents[key].append((rads[li], r['perp_max'],
                                               r['axial_over']))
                if r['samples']:
                    total_ms += 1
                    mesh_out.append('ms %s %d %d %s' % (
                        ch.name, li, len(r['samples']),
                        ' '.join('%.1f %.1f %.1f' % s for s in r['samples'])))
            ext = per_chain_extents[key]
            if ext:
                rep.append('SUMMARY %s %s linkrad_min=%.0f linkrad_max=%.0f '
                           'meshext_min=%.1f meshext_max=%.1f'
                           % (model, ch.name,
                              min(e[0] for e in ext), max(e[0] for e in ext),
                              min(max(e[1], e[2]) for e in ext),
                              max(max(e[1], e[2]) for e in ext)))

    # ---- write outputs ----
    os.makedirs(os.path.dirname(OUT_REPORT), exist_ok=True)
    with open(OUT_MESH, 'w') as f:
        f.write('\n'.join(mesh_out) + '\n')
    with open(OUT_REPORT, 'w') as f:
        f.write('MESH EXTENTS AUDIT (cycle 14) — per chain link: the link radius the\n'
                'runtime already tests vs the measured extent of the skinned mesh the\n'
                'link actually carries. units: game units (4096 = 1 m).\n\n')
        f.write('\n'.join(rep) + '\n')
        f.write('\nmodels processed (alias names): %d\n' % models_processed)
        f.write('ms lines emitted: %d\n' % total_ms)
        f.write('\nMODELS WITH NO GEOMETRY (%d):\n' % len(failed_models))
        for m, why in failed_models:
            f.write('  %s — %s\n' % (m, why))
        f.write('\nLINKS WITH EMPTY CLOUD (%d):\n' % len(empty_links))
        for m, cn, li, jn in empty_links:
            f.write('  %s %s link %d joint %s\n' % (m, cn, li, jn))

    # ---- validation: fail loudly, never a vacuous zero ----
    problems = []
    if models_processed < 50:
        problems.append('models processed %d < 50' % models_processed)
    if total_ms < 300:
        problems.append('ms lines %d < 300' % total_ms)
    for cn in ('chestR', 'chestL'):
        if per_chain_samples.get(('keira-hd', cn), 0) < 1:
            problems.append('keira-hd %s produced 0 samples' % cn)
    for cn in ('tieL', 'tieR'):
        key = ('mayor-lod0', cn)
        if per_chain_samples.get(key, 0) < 1:
            problems.append('mayor-lod0 %s produced 0 samples' % cn)
            continue
        ext = per_chain_extents.get(key, [])
        if not any(p > r or a > r for r, p, a in ext):
            problems.append(
                'mayor-lod0 %s: no link with mesh extent beyond its radius — measured '
                '%s' % (cn, '; '.join('link%d rad=%.0f perp=%.1f axial=%.1f'
                                      % (i, r, p, a)
                                      for i, (r, p, a) in enumerate(ext))))
    if problems:
        print('VALIDATION FAILED:')
        for p in problems:
            print('  ' + p)
        print('outputs written anyway for inspection: %s , %s'
              % (OUT_MESH, OUT_REPORT))
        return 1

    print('OK: %d alias models across %d sections, %d ms lines, %d failed models, '
          '%d empty-cloud links' % (models_processed,
                                    len(sections) - len(failed_models),
                                    total_ms, len(failed_models), len(empty_links)))
    print('wrote %s (%d bytes)' % (OUT_MESH, os.path.getsize(OUT_MESH)))
    print('wrote %s (%d bytes)' % (OUT_REPORT, os.path.getsize(OUT_REPORT)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
