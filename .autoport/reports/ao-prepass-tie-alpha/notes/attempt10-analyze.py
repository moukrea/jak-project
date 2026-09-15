#!/usr/bin/env python3
"""DIRECTIVES v775512c234
Bounded offline geometry/depth diagnostic. Never writes proof.txt.
Unique geometric candidates are NOT evidence of alpha survival or an owner verdict.
Depth input is little-endian float32 window reverse-Z, lower-left tight rows.
"""
import argparse
import collections
import hashlib
import json
import pathlib
import struct
import sys

import numpy as np

RESTART = 0xffffffff
D24 = 16777215
MAX_VERTICES = 4 * 1024 * 1024
MAX_INDICES = 8 * 1024 * 1024


def fnv(data):
    value = 14695981039346656037
    for byte in data:
        value = ((value ^ byte) * 1099511628211) & 0xffffffffffffffff
    return value


class Reader:
    def __init__(self, path):
        self.path, self.data, self.pos = path, path.read_bytes(), 0

    def take(self, size):
        if size < 0 or size > len(self.data) - self.pos:
            raise ValueError(f"{self.path}: truncated at {self.pos}")
        data = self.data[self.pos:self.pos + size]
        self.pos += size
        return data

    def number(self, fmt):
        return struct.unpack('<' + fmt, self.take(struct.calcsize('<' + fmt)))[0]

    def string(self):
        size = self.number('Q')
        if size > 65536:
            raise ValueError('oversized string')
        return self.take(size).decode('utf8')


def geometry(path):
    r = Reader(path)
    magic = r.take(8)
    if magic not in (b'AOHUTG01', b'AOHUTF01') or r.number('I') != 0x01020304:
        raise ValueError(f'{path}: unsupported format')
    geo, tree = r.number('I'), r.number('I')
    family = 'tie' if magic == b'AOHUTG01' else 'tfrag'
    kind = None if family == 'tie' else r.number('I')
    strips = r.number('I')
    nv, nd = r.number('Q'), r.number('Q')
    if nv > MAX_VERTICES or nd > MAX_INDICES:
        raise ValueError('geometry limit exceeded')
    np_, stride = (r.number('Q'), r.number('I')) if family == 'tie' else (0, 0)
    if stride not in (0, 8):
        raise ValueError('unknown sway stride')
    level = r.string()
    if family == 'tie':
        categories = [r.number('I') for _ in range(r.number('I'))]
        protos = [r.string() for _ in range(np_)]
        dtype = np.dtype([('pos', '<f4', 3), ('uv', '<f4', 2), ('normal', '<u4'),
                          ('matrix', '<i4'), ('group', '<u4'), ('source', '<u4'),
                          ('sway', 'u1', 8)])
    else:
        categories, protos = [], []
        dtype = np.dtype([('pos', '<f4', 3), ('uv', '<f4', 2), ('normal', '<u4')])
    vertices = np.frombuffer(r.take(nv * dtype.itemsize), dtype=dtype)
    draws = []
    for _ in range(nd):
        mode, texture = r.number('I'), r.number('i')
        first = None if family == 'tie' else r.number('Q')
        count = r.number('Q')
        if count > MAX_INDICES:
            raise ValueError('draw index limit exceeded')
        if family == 'tie':
            indices = np.frombuffer(r.take(count * 16), dtype='<u4').reshape(-1, 4)
        else:
            effective = np.frombuffer(r.take(count * 4), dtype='<u4')
            indices = np.column_stack((effective, effective))
        draws.append(dict(mode=mode, texture=texture, first=first, indices=indices))
    if r.pos != len(r.data):
        raise ValueError(f'{path}: trailing bytes ({len(r.data)-r.pos})')
    return dict(family=family, geo=geo, tree=tree, kind=kind, level=level, strips=strips,
                vertices=vertices, draws=draws, protos=protos, categories=categories,
                sha256=hashlib.sha256(r.data).hexdigest())


def triangles(pairs, mode):
    """Yield submission positions; degenerates advance strip parity as on GL."""
    if mode == 4:  # GL_TRIANGLES
        if len(pairs) % 3:
            raise ValueError('incomplete triangle list')
        for i in range(0, len(pairs), 3):
            idx = (i, i + 1, i + 2)
            if RESTART in pairs[list(idx), 0]:
                raise ValueError('restart inside triangle list')
            if len(set(int(pairs[j, 0]) for j in idx)) == 3:
                yield idx
    elif mode == 5:  # GL_TRIANGLE_STRIP
        start = 0
        for i, pair in enumerate(pairs):
            if pair[0] == RESTART:
                start = i + 1
            elif i >= start + 2:
                idx = (i - 2, i - 1, i) if (i - start) % 2 == 0 else (i - 1, i - 2, i)
                if len(set(int(pairs[j, 0]) for j in idx)) == 3:
                    yield idx
    else:
        raise ValueError(f'unsupported primitive mode {mode}')


def primitive_ordinals(pairs, mode):
    """GPU ordinal table: restart resets strip assembly/parity, never the counter.

    Degenerate primitives occupy ordinals. A new call creates a new counter.
    This is separate from triangles(), which intentionally omits degenerates.
    """
    result = []
    if mode == 4:
        if len(pairs) % 3 or np.any(pairs[:, 0] == RESTART):
            raise ValueError('invalid triangle-list primitive stream')
        return [(i, i+1, i+2) for i in range(0, len(pairs), 3)]
    if mode != 5:
        raise ValueError('unsupported primitive stream mode')
    start = 0
    for i, pair in enumerate(pairs):
        if pair[0] == RESTART:
            start = i+1
        elif i >= start+2:
            result.append((i-2, i-1, i) if (i-start) % 2 == 0 else (i-1, i-2, i))
    return result


def project(positions, ubo):
    """tfrag3.vert operations, column-major pc_camera, including overwritten w."""
    f = np.frombuffer(ubo, dtype='<f4')
    if len(f) not in (20, 56):
        raise ValueError('projection must have 80 bytes or UBO 224 bytes')
    cols = f[:16].reshape(4, 4)
    relative = np.asarray(positions, dtype=np.float32) - (f[36:39] if len(f) == 56 else f[16:19])
    result = np.tile(-cols[3], (len(relative), 1))
    result[:, 3] = 0
    for axis in range(3):
        result = result - relative[:, axis:axis + 1] * cols[axis]
    result[:, 1] *= np.float32(512.0 / 448.0)
    if not np.all(np.isfinite(result)):
        raise ValueError('nonfinite projection')
    return result.astype(np.float64)


def clip_triangle(clip):
    """Homogeneous six-plane clipping; preserves original primitive identity."""
    polygon = list(clip)
    for axis, sign in ((0, 1), (0, -1), (1, 1), (1, -1), (2, 1), (2, -1)):
        output = []
        if not polygon:
            break
        previous = polygon[-1]
        dp = previous[3] + sign * previous[axis]
        for current in polygon:
            dc = current[3] + sign * current[axis]
            if (dc >= 0) != (dp >= 0):
                output.append(previous + (current - previous) * (dp / (dp - dc)))
            if dc >= 0:
                output.append(current)
            previous, dp = current, dc
        polygon = output
    if len(polygon) < 3 or any(v[3] <= 0 for v in polygon):
        return []
    return [np.array((polygon[0], polygon[i], polygon[i + 1]))
            for i in range(1, len(polygon) - 1)]


def screen_triangle(clip, viewport):
    ndc = clip[:, :3] / clip[:, 3:4]
    x, y, width, height = viewport
    return np.column_stack((x + (ndc[:, 0] + 1) * width / 2,
                            y + (ndc[:, 1] + 1) * height / 2,
                            (ndc[:, 2] + 1) / 2))


def compatible(screen, x, y, depth):
    """Interior centre and D24 interval compatibility, no adjustable tolerance.

    Exact edge centres are unresolved; we do not emulate GPU subpixel fill rules.
    Compatibility cannot certify shader FP arithmetic or fragment survival.
    """
    a, b, c = screen
    den = (b[1]-c[1])*(a[0]-c[0]) + (c[0]-b[0])*(a[1]-c[1])
    if den == 0:
        return False, False
    u = ((b[1]-c[1])*(x-c[0]) + (c[0]-b[0])*(y-c[1])) / den
    v = ((c[1]-a[1])*(x-c[0]) + (a[0]-c[0])*(y-c[1])) / den
    w = 1-u-v
    if min(u, v, w) < 0:
        return False, False
    if min(u, v, w) == 0:
        return False, True
    z = u*a[2] + v*b[2] + w*c[2]
    q = round(float(depth) * D24)
    return (q-0.5)/D24 <= z <= (q+0.5)/D24, False


def classify_candidates(candidates):
    unique = sorted(set(candidates))
    return ('missing' if not unique else 'unique-geometric' if len(unique) == 1 else 'ambiguous', unique)


def records(path):
    for line in path.read_text().splitlines():
        if line.strip():
            yield dict(part.split('=', 1) for part in line.split())


def color_capture(directory, frame, width, height):
    """Read the three actual MRT outputs only after metadata/hash verification."""
    rows = list(records(directory / 'color.meta'))
    meta = {k: v for r in rows if len(r) == 1 for k, v in r.items()}
    if meta.get('format') not in ('ao-hut-color-f32-v1', 'ao-hut-color-f32-v2'):
        raise ValueError('unknown color capture format')
    if meta.get('status') != 'complete' or int(meta['render_frame']) != frame or \
            int(meta['width']) != width or int(meta['height']) != height or \
            meta.get('origin') != 'lower-left' or meta.get('alpha') != 'post-discard':
        raise ValueError('color capture status, frame, dimensions or origin mismatch')
    stages = {r['stage']: r for r in rows if 'stage' in r}
    outputs = []
    for name in ('identity', 'contribution', 'normal'):
        filename = f'color-{name}.rgba32f'
        data = (directory / filename).read_bytes()
        if len(data) != width*height*16 or int(stages[filename]['bytes']) != len(data) or \
                fnv(data) != int(stages[filename]['fnv1a64']):
            raise ValueError(f'{filename}: byte count/hash mismatch')
        outputs.append(np.frombuffer(data, dtype='<f4').reshape(height, width, 4))
    # Metadata records the last use of each draw id. A depth-off last use is not
    # evidence about the scene depth and is deliberately not used as an identity.
    allowed = set()
    for r in rows:
        if 'draw_id' in r:
            state = dict(term.split(':', 1) for term in r['state'].split(',') if ':' in term)
            if state.get('depthwrite') == '1':
                allowed.add(int(r['draw_id']))
    return outputs, allowed, meta


def source_map(g):
    result = {}
    for di, draw in enumerate(g['draws']):
        if draw['first'] is None:
            raise ValueError('TIE original fullfirst missing; need tie-draw-offsets.txt')
        for local, index in enumerate(draw['indices']):
            full = draw['first'] + local
            if full in result:
                raise ValueError('overlapping original draw ranges')
            result[full] = (di, local, index)
    return result


def contact_inert(contact_on, indices, effective_vertices):
    if contact_on == '0':
        return True
    if contact_on != '1' or indices is None:
        return False
    return bool(np.all(indices[effective_vertices] == 0))


def load_contact_indices(directory, g, proof=None):
    stem = f"contact-indices-{g['geo']}-{g['tree']}"
    path = directory / (stem+'.u32')
    if not path.exists() or proof is None:
        return None
    prefix = f"ao_hut_contact_indices_{g['geo']}_{g['tree']}_"
    meta = {k[len(prefix):]: v for k, v in proof.items() if k.startswith(prefix)}
    if not all(k in meta for k in ('io_error', 'count', 'buffer', 'hash', 'path')):
        return None
    data = path.read_bytes()
    if int(meta['io_error']) != 0 or int(meta['buffer']) <= 0 or \
            len(data) != len(g['vertices'])*4 or int(meta['count']) != len(g['vertices']) or \
            pathlib.PurePosixPath(meta['path']).name != path.name or fnv(data) != int(meta['hash']):
        raise ValueError(f'{stem}: incomplete or inconsistent contact index archive')
    return np.frombuffer(data, dtype='<u4')


def read_proof(path, archive):
    proof = {}
    for line in path.read_text().splitlines():
        if '=' not in line:
            continue
        key, value = line.split('=', 1)
        if key in proof and proof[key] != value:
            raise ValueError('conflicting proof values')
        proof[key] = value
    if not proof.get('proof_run_id') or pathlib.PurePosixPath(proof.get('ao_hut_archive_directory', '')).name != archive.name:
        raise ValueError('proof does not identify this archive directory')
    return proof


def summarize_populations(geos, submissions, payload, color, depth, frame, pass_name):
    """Full-image vectorized draw populations; instance lists are candidates, not labels."""
    identity, contribution, normal = color
    valid = np.all(np.isfinite(identity), axis=2) & np.isfinite(depth) & (depth > 1e-9) & (depth <= 1)
    valid &= (identity[:, :, 3] > 0) & (identity[:, :, 3] <= 16777216)
    valid &= identity[:, :, 3] == np.floor(identity[:, :, 3])
    # Invalid values are masked before integer conversion: never turn NaN into id zero.
    ys, xs = np.nonzero(valid)
    z = identity[ys, xs, 2].astype(np.float64)
    match = np.rint(z * D24) == np.rint(depth[ys, xs].astype(np.float64) * D24)
    mismatched = int(np.count_nonzero(~match))
    ys, xs = ys[match], xs[match]
    ids, inverse, counts = np.unique(identity[ys, xs, 3].astype(np.uint32), return_inverse=True, return_counts=True)
    size = len(ids)
    xmin, xmax = np.full(size, depth.shape[1]), np.full(size, -1)
    ymin, ymax = np.full(size, depth.shape[0]), np.full(size, -1)
    np.minimum.at(xmin, inverse, xs); np.maximum.at(xmax, inverse, xs)
    np.minimum.at(ymin, inverse, ys); np.maximum.at(ymax, inverse, ys)
    observed = {}
    n = normal[ys, xs]
    normal_ok = np.all(np.isfinite(n), axis=1) & (n[:, 3] == 1)
    nn = np.bincount(inverse[normal_ok], minlength=size)
    sums = [np.bincount(inverse[normal_ok], weights=n[normal_ok, axis], minlength=size) for axis in range(3)]
    up = np.abs(n[:, 1])
    wall = np.bincount(inverse[normal_ok & (up < .2)], minlength=size)
    slope = np.bincount(inverse[normal_ok & (up >= .2) & (up < .9)], minlength=size)
    horizontal = np.bincount(inverse[normal_ok & (up >= .9)], minlength=size)
    sao = contribution[ys, xs, 3]
    sao_ok = np.isfinite(sao)
    sao_sum = np.bincount(inverse[sao_ok], weights=sao[sao_ok], minlength=size)
    sao_count = np.bincount(inverse[sao_ok], minlength=size)
    for j, probe in enumerate(ids):
        observed[int(probe)] = dict(probe_id=int(probe), pixels=int(counts[j]),
            bounds_px=[int(xmin[j]), int(ymin[j]), int(xmax[j]), int(ymax[j])],
            normal_valid_pixels=int(nn[j]), normal_mean=[float(s[j]/nn[j]) if nn[j] else None for s in sums],
            normal_abs_y_bins=[int(wall[j]), int(slope[j]), int(horizontal[j])],
            sao_mean=float(sao_sum[j]/sao_count[j]) if sao_count[j] else None,
            submissions=[])
    checked_payloads = set()
    for r in submissions:
        probe = int(r.get('probe_id', 0))
        if int(r['render_frame']) != frame or r['pass'] != pass_name or probe not in observed:
            continue
        key = (r['family'], int(r['geo']), int(r['tree']))
        if key not in geos:
            observed[probe]['submissions'].append(dict(error='geometry missing', key=list(key)))
            continue
        g = geos[key]
        count, offset = int(r['count']), int(r['payload_offset'])
        if count > MAX_INDICES or int(r['payload_ok']) != 1:
            raise ValueError('summary payload invalid')
        chunk = payload[offset:offset+count*8]
        stamp = (offset, count, int(r['payload_hash']))
        if stamp not in checked_payloads:
            if len(chunk) != count*8 or fnv(chunk) != stamp[2]:
                raise ValueError('summary payload hash mismatch')
            checked_payloads.add(stamp)
        pairs = np.frombuffer(chunk, dtype='<u4').reshape(-1, 2)
        pairs = pairs[pairs[:, 0] != RESTART]
        if not len(pairs):
            continue
        effective = np.unique(pairs[:, 0])
        if effective[-1] >= len(g['vertices']):
            raise ValueError('summary effective vertex out of range')
        xyz = g['vertices']['pos'][effective]
        if not np.all(np.isfinite(xyz)):
            raise ValueError('summary nonfinite geometry')
        entry = dict(family=g['family'], geo=g['geo'], tree=g['tree'], seq=int(r['seq']),
            depth_write=int(r['depth_write']), projection_kind=r.get('projection_kind', 'unknown'),
            geometry_sha256=g['sha256'], world_bounds_units=[xyz.min(axis=0).tolist(), xyz.max(axis=0).tolist()],
            source_draws=[], instance_candidates=[])
        for di in range(int(r['draw_begin']), int(r['draw_end'])):
            d = g['draws'][di]
            first = d['first']
            if first is None:
                entry['source_draws'].append(dict(draw=di, error='fullfirst missing'))
                continue
            selected = pairs[(pairs[:, 1] >= first) & (pairs[:, 1] < first+len(d['indices']))]
            if not len(selected):
                continue
            source = d['indices'][selected[:, 1]-first]
            if not np.array_equal(source[:, 1], selected[:, 0]):
                raise ValueError('summary original/effective correspondence mismatch')
            entry['source_draws'].append(dict(draw=di, texture=d['texture'], index_count=len(selected)))
            if g['family'] == 'tie':
                original = source[:, 0]
                vertices = g['vertices'][original]
                # Group by prototype and ORIGINAL matrix/group, then use EFFECTIVE positions.
                instance_keys = np.column_stack((source[:, 3], vertices['matrix'], vertices['group']))
                unique, inv = np.unique(instance_keys, axis=0, return_inverse=True)
                for k, (proto, matrix, group) in enumerate(unique):
                    positions = g['vertices']['pos'][selected[inv == k, 0]]
                    pi = int(proto)
                    entry['instance_candidates'].append(dict(draw=di, prototype=pi,
                        prototype_name=g['protos'][pi] if pi < len(g['protos']) else None,
                        original_matrix=int(matrix), original_group=int(group),
                        world_bounds_units=[positions.min(axis=0).tolist(), positions.max(axis=0).tolist()]))
        observed[probe]['submissions'].append(entry)
    return dict(directives='DIRECTIVES v775512c234', diagnostic_only=True, scope='draw populations; instance candidates',
        frame=frame, pass_name=pass_name, contact_labels='unassigned', normal_abs_y_bin_edges=[0, .2, .9, 1],
        color_depth_mismatch_pixels=mismatched, observed_draws=[observed[k] for k in sorted(observed)],
        limitations=['normal bins describe shader normals, never wall/roof labels',
                     'instance bounds describe submitted geometry, not per-instance pixel attribution'])


def gpu_attribution(geos, submissions, payload, color, allowed_ids, depth, frame, roi):
    """Resolve v2 fragment IDs to the ORIGINAL primitive stream, without CPU z."""
    x0, y0, rw, rh = roi
    counters = collections.Counter()
    wanted = collections.defaultdict(set)
    pixel_keys = {}
    for y in range(y0, y0+rh):
        for x in range(x0, x0+rw):
            value, d = color[0][y, x], float(depth[y, x])
            if not np.all(np.isfinite(value)) or not np.isfinite(d) or not 1e-9 < d <= 1:
                counters['pixels_invalid_depth_or_identity'] += 1
                continue
            encoded, probe = float(value[0]), float(value[3])
            if encoded != int(encoded) or probe != int(probe) or not 1 <= encoded <= 16777216 or not 1 <= probe <= 16777216:
                counters['pixels_invalid_primitive_id'] += 1
                continue
            if int(probe) not in allowed_ids:
                counters['pixels_draw_metadata_unresolved'] += 1
                continue
            if round(float(value[2])*D24) != round(d*D24):
                counters['pixels_color_scene_depth_mismatch'] += 1
                continue
            key = (int(probe), int(encoded)-1)
            pixel_keys[(x, y)] = key
            wanted[key[0]].add(key[1])
    mappings = collections.defaultdict(set)
    unresolved = collections.defaultdict(set)
    primitives, source_maps = {}, {}
    for r in submissions:
        probe = int(r.get('probe_id', 0))
        if int(r['render_frame']) != frame or r['pass'] != 'color' or probe not in wanted:
            continue
        counters['submissions_selected'] += 1
        if r.get('projection_kind') != 'pc_camera' or r.get('depth_write') != '1':
            for ordinal in wanted[probe]:
                unresolved[(probe, ordinal)].add('submission_state_not_supported')
            continue
        count, offset = int(r['count']), int(r['payload_offset'])
        if count > MAX_INDICES or int(r['payload_ok']) != 1:
            raise ValueError('GPU identity submission payload invalid')
        chunk = payload[offset:offset+count*8]
        if len(chunk) != count*8 or fnv(chunk) != int(r['payload_hash']):
            raise ValueError('GPU identity submission payload hash mismatch')
        pairs = np.frombuffer(chunk, dtype='<u4').reshape(-1, 2)
        table = primitive_ordinals(pairs, int(r['mode']))
        key = (r['family'], int(r['geo']), int(r['tree']))
        if key not in geos:
            for ordinal in wanted[probe]:
                if ordinal < len(table):
                    unresolved[(probe, ordinal)].add('missing_geometry')
            continue
        g = geos[key]
        if key not in source_maps:
            source_maps[key] = source_map(g)
        for ordinal in wanted[probe]:
            if ordinal >= len(table):
                continue  # This smaller submission cannot have produced this ordinal.
            positions = table[ordinal]
            vi = [int(pairs[i, 0]) for i in positions]
            k = (probe, ordinal)
            if len(set(vi)) != 3:
                # Degenerates consume an ordinal but cannot emit a fragment.
                counters['submission_ordinal_degenerate'] += 1
                continue
            entries = [source_maps[key].get(int(pairs[i, 1])) for i in positions]
            if any(e is None for e in entries) or len(set(e[0] for e in entries)) != 1:
                raise ValueError('GPU primitive source range invalid')
            if any(int(e[2][1]) != v for e, v in zip(entries, vi)) or max(vi) >= len(g['vertices']):
                raise ValueError('GPU primitive effective/original mismatch')
            source_draw = entries[0][0]
            if not int(r['draw_begin']) <= source_draw < int(r['draw_end']):
                raise ValueError('GPU primitive outside declared draw range')
            original = [int(e[2][0]) for e in entries]
            if max(original) >= len(g['vertices']):
                raise ValueError('GPU primitive original vertex out of range')
            local = [e[1] for e in entries]
            identity = f"{g['family']}:{g['geo']}:{g['tree']}:{source_draw}:" + ','.join(map(str, sorted(local)))
            xyz = g['vertices']['pos'][vi]
            if not np.all(np.isfinite(xyz)):
                raise ValueError('GPU primitive nonfinite geometry')
            instance = dict(source_vertices=original)
            stationary = g['family'] == 'tfrag' and r.get('contact_on') == '0' and r.get('sway_amp') == '0'
            if g['family'] == 'tie':
                sources = g['vertices'][original]
                proto = sorted(set(int(e[2][3]) for e in entries))
                instance.update(matrices=sorted(set(int(v) for v in sources['matrix'])),
                    groups=sorted(set(int(v) for v in sources['group'])), prototypes=proto,
                    prototype_names=[g['protos'][v] if v < len(g['protos']) else None for v in proto])
                weights = [struct.unpack('<h', g['vertices'][i]['sway'][:2].tobytes())[0] for i in vi]
                stationary = (not any(weights) or r.get('sway_amp') == '0') and contact_inert(r.get('contact_on', 'unknown'), g.get('contact_indices'), vi)
            n = np.cross(xyz[1].astype(float)-xyz[0], xyz[2].astype(float)-xyz[0])
            length = float(np.linalg.norm(n))
            if length == 0:
                counters['submission_source_degenerate'] += 1
                continue
            n /= length
            record = primitives.setdefault(identity, dict(identity=identity, family=g['family'], geo=g['geo'], tree=g['tree'],
                source_draw=source_draw, local_indices=local, full_source_offsets=[int(pairs[i, 1]) for i in positions],
                effective_vertices=vi, instance=instance, geometry_sha256=g['sha256'], xyz=xyz.tolist(),
                face_normal=n.tolist(), static_world_positions_qualified=bool(stationary), submissions=[]))
            record['static_world_positions_qualified'] &= bool(stationary)
            record['submissions'].append(dict(seq=int(r['seq']), probe_id=probe, primitive_ordinal=ordinal,
                                               ubo_hash=r.get('ubo_hash'), projection_hash=r.get('projection_hash'),
                                               viewport=r.get('viewport')))
            mappings[k].add(identity)
    pixels = []
    used = set()
    for (x, y), key in sorted(pixel_keys.items()):
        ids = sorted(mappings[key])
        reasons = sorted(unresolved[key])
        status = 'unresolved-submission' if reasons else 'missing' if not ids else 'gpu-unique' if len(ids) == 1 else 'gpu-ambiguous'
        counters['pixels_'+status] += 1
        value = dict(x=x, y=y, probe_id=key[0], primitive_ordinal=key[1], status=status, candidates=ids,
                     unresolved_sources=reasons, depth_scene_matches_mrt=True)
        contribution, normal = color[1][y, x], color[2][y, x]
        if np.all(np.isfinite(contribution)) and np.all(np.isfinite(normal)):
            value.update(color_delta_rgb=contribution[:3].tolist(), color_sao=float(contribution[3]),
                         color_normal=normal[:3].tolist(), color_normal_valid=float(normal[3]))
        else:
            counters['color_payload_nonfinite'] += 1
        pixels.append(value)
        used.update(ids)
    return dict(directives='DIRECTIVES v775512c234', diagnostic_only=True, identity_format='gpu-primitive-v2',
        frame=frame, roi=list(roi), counters=dict(counters), pixels=pixels,
        primitives=[primitives[i] for i in sorted(used)], cpu_depth_used_for_identity=False,
        contact_labels='unassigned; physical qualification and owner defect remain separate',
        limitations=['ambiguous submissions remain unresolved', 'dynamic vertices have only archived rest positions',
                     'primitive counter semantics require device support; no global defect value is produced'])


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('archive', type=pathlib.Path)
    p.add_argument('--depth', required=True, type=pathlib.Path)
    p.add_argument('--width', required=True, type=int)
    p.add_argument('--height', required=True, type=int)
    p.add_argument('--frame', required=True, type=int)
    p.add_argument('--pass-name', default='color')
    p.add_argument('--roi', help='x,y,width,height, lower-left pixels')
    p.add_argument('--summary-only', action='store_true', help='vectorized full-image draw/prototype population summary')
    p.add_argument('--proof', type=pathlib.Path, help='existing proof_run proof; verifies contact-index sidecar hashes')
    p.add_argument('--output', required=True, type=pathlib.Path)
    args = p.parse_args()
    proof = read_proof(args.proof, args.archive) if args.proof else None
    if args.output.name == 'proof.txt':
        p.error('proof.txt is exclusively owned by proof_run')
    if min(args.width, args.height) <= 0 or args.width*args.height > 4194304:
        p.error('image dimensions invalid or exceed 4194304 pixels')
    if not args.roi and not args.summary_only:
        p.error('--roi is required except for --summary-only')
    x0, y0, rw, rh = map(int, (args.roi or '0,0,1,1').split(','))
    if min(x0, y0) < 0 or min(rw, rh) <= 0 or rw*rh > 262144 or \
            x0+rw > args.width or y0+rh > args.height:
        p.error('ROI invalid or exceeds 262144 pixels')
    depth_bytes = args.depth.read_bytes()
    if len(depth_bytes) != args.width*args.height*4:
        p.error('depth byte count mismatch')
    depth = np.frombuffer(depth_bytes, dtype='<f4').reshape(args.height, args.width)
    color, allowed_ids, color_meta = None, set(), {}
    if args.pass_name == 'color':
        color, allowed_ids, color_meta = color_capture(args.archive, args.frame, args.width, args.height)
        depth_meta = {k: v for r in records(args.depth.with_suffix('.meta')) for k, v in r.items()}
        if depth_meta.get('status') != 'complete' or int(depth_meta['render_frame']) != args.frame or \
                int(depth_meta['bytes']) != len(depth_bytes) or fnv(depth_bytes) != int(depth_meta['fnv1a64']):
            raise ValueError('scene depth metadata/hash mismatch')
    geos = {}
    for path in args.archive.glob('*geometry*.bin'):
        g = geometry(path)
        key = (g['family'], g['geo'], g['tree'])
        if key in geos:
            raise ValueError(f'duplicate geometry identity {key}')
        if g['family'] == 'tie':
            g['contact_indices'] = load_contact_indices(args.archive, g, proof)
        geos[key] = g
    for offsets_path in args.archive.glob('tie-draw-offsets-*.txt'):
        for r in records(offsets_path):
            g = geos[('tie', int(r['geo']), int(r['tree']))]
            draw = g['draws'][int(r['draw'])]
            if int(r['count']) != len(draw['indices']):
                raise ValueError('offset sidecar count mismatch')
            draw['first'] = int(r['first'])
    mapping, candidates, primitives = {}, collections.defaultdict(set), {}
    counters = collections.Counter()
    payload = (args.archive / 'draws-indices.bin').read_bytes()
    submissions = list(records(args.archive / 'draws.txt'))
    if args.summary_only:
        if color is None:
            p.error('--summary-only requires color captures')
        result = summarize_populations(geos, submissions, payload, color, depth, args.frame, args.pass_name)
        result['proof_run_id'] = proof.get('proof_run_id') if proof else None
        with args.output.open('x') as output:
            json.dump(result, output, allow_nan=False, separators=(',', ':'))
        print(json.dumps(dict(observed_draws=len(result['observed_draws']), color_depth_mismatch_pixels=result['color_depth_mismatch_pixels'])))
        return
    if color_meta.get('format') == 'ao-hut-color-f32-v2':
        if color_meta.get('identity_r') != 'primitive-id-plus-one':
            raise ValueError('unknown v2 identity encoding')
        result = gpu_attribution(geos, submissions, payload, color, allowed_ids, depth, args.frame, (x0, y0, rw, rh))
        result['proof_run_id'] = proof.get('proof_run_id') if proof else None
        result['depth_sha256'] = hashlib.sha256(depth_bytes).hexdigest()
        with args.output.open('x') as output:
            json.dump(result, output, allow_nan=False, separators=(',', ':'))
        print(json.dumps(result['counters'], sort_keys=True))
        return
    for r in submissions:
        if int(r['render_frame']) != args.frame or r['pass'] != args.pass_name:
            continue
        counters['draws_selected'] += 1
        probe_id = int(r.get('probe_id', 0))
        if color is not None and (probe_id not in allowed_ids or r['depth_write'] != '1'):
            counters['draws_missing_or_depthoff_identity'] += 1
            continue
        key = (r['family'], int(r['geo']), int(r['tree']))
        if key not in geos:
            counters['draws_missing_geometry'] += 1
            continue
        g = geos[key]
        if key not in mapping:
            mapping[key] = source_map(g)
        if int(r['payload_ok']) != 1:
            raise ValueError('draw payload marked failed')
        count, offset = int(r['count']), int(r['payload_offset'])
        if count > MAX_INDICES:
            raise ValueError('submission limit exceeded')
        chunk = payload[offset:offset+count*8]
        if len(chunk) != count*8 or fnv(chunk) != int(r['payload_hash']):
            raise ValueError('draw payload checksum mismatch')
        pairs = np.frombuffer(chunk, dtype='<u4').reshape(-1, 2)
        ph = int(r.get('projection_hash', 0))
        projection_path = f"projection-{ph}.bin" if ph else f"frame-ubo-{args.frame}-{r['ubo_hash']}.bin"
        ubo = (args.archive / projection_path).read_bytes()
        if fnv(ubo) != (ph or int(r['ubo_hash'])):
            raise ValueError('UBO checksum mismatch')
        viewport = list(map(int, r['viewport'].split(',')))
        for positions in triangles(pairs, int(r['mode'])):
            counters['triangles_submitted'] += 1
            if counters['triangles_submitted'] > 1000000:
                raise ValueError('triangle budget exceeded')
            entries = [mapping[key].get(int(pairs[i, 1])) for i in positions]
            if any(e is None for e in entries):
                raise ValueError('original index outside archived draws')
            if any(int(e[2][1]) != int(pairs[i, 0]) for e, i in zip(entries, positions)):
                raise ValueError('effective/source index correspondence mismatch')
            if len(set(e[0] for e in entries)) != 1:
                raise ValueError('triangle crosses source draw boundary')
            vi = [int(pairs[i, 0]) for i in positions]
            if max(vi) >= len(g['vertices']):
                raise ValueError('vertex out of range')
            if g['family'] == 'tie':
                weights = [struct.unpack('<h', g['vertices'][i]['sway'][:2].tobytes())[0] for i in vi]
                if any(weights):
                    counters['triangles_sway_unresolved'] += 1
                    continue
                if not contact_inert(r.get('contact_on', 'unknown'), g.get('contact_indices'), vi):
                    counters['triangles_contact_transform_unresolved'] += 1
                    continue
            if r.get('projection_kind', 'unknown') != 'pc_camera':
                counters['triangles_projection_unresolved'] += 1
                continue
            xyz = g['vertices']['pos'][vi]
            original = [int(e[2][0]) for e in entries]
            primitive_id = f"{g['family']}:{g['geo']}:{g['tree']}:{entries[0][0]}:" + ','.join(str(e[1]) for e in entries)
            if g['family'] == 'tie':
                sources = g['vertices'][original]
                matrices = sorted(set(int(v) for v in sources['matrix']))
                groups = sorted(set(int(v) for v in sources['group']))
                instance = dict(matrices=matrices, groups=groups,
                                prototypes=sorted(set(int(e[2][3]) for e in entries)))
            else:
                instance = dict(tree=g['tree'], kind=g['kind'], source_vertices=original)
            primitives[primitive_id] = dict(identity=primitive_id, instance=instance,
                                           xyz=xyz.tolist(), geometry_sha256=g['sha256'])
            for clipped in clip_triangle(project(xyz, ubo)):
                screen = screen_triangle(clipped, viewport)
                xmin = max(x0, int(np.ceil(min(screen[:, 0])-.5)))
                xmax = min(x0+rw-1, int(np.floor(max(screen[:, 0])-.5)))
                ymin = max(y0, int(np.ceil(min(screen[:, 1])-.5)))
                ymax = min(y0+rh-1, int(np.floor(max(screen[:, 1])-.5)))
                for y in range(ymin, ymax+1):
                    for x in range(xmin, xmax+1):
                        d = float(depth[y, x])
                        if not np.isfinite(d) or d <= 1e-9 or d > 1:
                            continue
                        if color is not None:
                            identity = color[0][y, x]
                            if not np.all(np.isfinite(identity)) or identity[3] != probe_id:
                                continue
                            if round(float(identity[2])*D24) != round(d*D24):
                                counters['color_scene_depth_mismatch_tests'] += 1
                                continue
                        hit, boundary = compatible(screen, x+.5, y+.5, d)
                        counters['boundary_tests_unresolved'] += boundary
                        if hit:
                            candidates[(x, y)].add(primitive_id)
    pixels = []
    used = set()
    for y in range(y0, y0+rh):
        for x in range(x0, x0+rw):
            d = float(depth[y, x])
            if not np.isfinite(d) or not 1e-9 < d <= 1:
                counters['pixels_invalid_depth'] += 1
                continue
            status, ids = classify_candidates(candidates[(x, y)])
            counters['pixels_' + status] += 1
            if ids:
                pixel = dict(x=x, y=y, status=status, candidates=ids)
                if color is not None:
                    contribution, normal = color[1][y, x], color[2][y, x]
                    if np.all(np.isfinite(contribution)) and np.all(np.isfinite(normal)):
                        pixel.update(color_delta_rgb=contribution[:3].tolist(),
                                     color_sao=float(contribution[3]),
                                     color_normal=normal[:3].tolist(), color_normal_valid=float(normal[3]))
                    else:
                        counters['color_payload_nonfinite'] += 1
                pixels.append(pixel)
                used.update(ids)
    edges = collections.defaultdict(set)
    for identity in used:
        xyz = primitives[identity]['xyz']
        for a, b in ((0, 1), (1, 2), (2, 0)):
            edge = tuple(sorted((tuple(xyz[a]), tuple(xyz[b]))))
            if edge[0] != edge[1]:
                edges[edge].add(identity)
    contacts = [dict(edge=list(edge), primitives=sorted(ids)) for edge, ids in edges.items() if len(ids)>1]
    result = dict(directives='DIRECTIVES v775512c234', diagnostic_only=True,
                  post_alpha_draw_mask_applied=color is not None, gpu_fill_rule_verified=False,
                  contact_labels='unassigned; external labels require source identities and documented source',
                  frame=args.frame, pass_name=args.pass_name, roi=[x0, y0, rw, rh],
                  proof_run_id=proof.get('proof_run_id') if proof else None,
                  depth_sha256=hashlib.sha256(depth_bytes).hexdigest(), counters=dict(counters),
                  pixels=pixels, primitives=[primitives[i] for i in sorted(used)],
                  exact_shared_edges=contacts,
                  limitations=['D24 interval compatibility only; no GPU arithmetic certificate',
                               'MRT identity covers drawn fragments only; final framebuffer blend contribution unmeasured',
                               'shared edges do not assign wall/roof; T-junctions not inferred',
                               'no global defect value is produced'])
    with args.output.open('x') as output:
        json.dump(result, output, allow_nan=False, separators=(',', ':'))
    print(json.dumps(result['counters'], sort_keys=True))


if __name__ == '__main__':
    main()
