#!/usr/bin/env python3
"""DIRECTIVES v775512c234 -- qualified primitive patch contact, offline/native reader.
No owner labels or defect values are generated. No CPU profile logic is duplicated.
"""
import argparse
import hashlib
import importlib.util
import json
import pathlib
import struct
import subprocess
import tempfile

import numpy as np

spec = importlib.util.spec_from_file_location('attribution', pathlib.Path(__file__).with_name('attempt10-analyze.py'))
attribution = importlib.util.module_from_spec(spec)
spec.loader.exec_module(attribution)


def segment_triangle(a, b, t):
    e1, e2, direction = t[1]-t[0], t[2]-t[0], b-a
    h = np.cross(direction, e2)
    det = float(np.dot(e1, h))
    if det == 0:
        return None
    s = a-t[0]
    u = float(np.dot(s, h)/det)
    if not 0 <= u <= 1:
        return None
    q = np.cross(s, e1)
    v = float(np.dot(direction, q)/det)
    if v < 0 or u+v > 1:
        return None
    along = float(np.dot(e2, q)/det)
    return a+along*direction if 0 <= along <= 1 else None


def physical_intersection(a, b):
    points = []
    for i, j in ((0, 1), (1, 2), (2, 0)):
        for point in (segment_triangle(a[i], a[j], b), segment_triangle(b[i], b[j], a)):
            if point is not None:
                points.append(point)
    if len(points) < 2:
        raise ValueError('physical triangle intersection not established')
    distances = np.array([[np.linalg.norm(p-q) for p in points] for q in points])
    i, j = np.unravel_index(np.argmax(distances), distances.shape)
    if distances[i, j] == 0:
        raise ValueError('point contact cannot qualify a line profile')
    return np.array([points[i], points[j]])


def crosses_segment(p, q, a, b):
    u, v = q-p, b-a
    den = float(u[0]*v[1]-u[1]*v[0])
    if den == 0:
        return False
    d = a-p
    t = float((d[0]*v[1]-d[1]*v[0])/den)
    s = float((d[0]*u[1]-d[1]*u[0])/den)
    return 0 <= t <= 1 and 0 <= s <= 1


def select_patch(primitives, specification):
    offsets = sorted(specification['full_source_offsets'])
    found = [p for p in primitives if p['family'] == specification['family'] and
             p['geo'] == specification['geo'] and p['tree'] == specification['tree'] and
             sorted(p['full_source_offsets']) == offsets]
    if len(found) != 1 or not found[0]['static_world_positions_qualified']:
        raise ValueError('named patch missing, ambiguous, or world positions unqualified')
    if specification.get('geometry_sha256') and found[0]['geometry_sha256'] != specification['geometry_sha256']:
        raise ValueError('named patch geometry fingerprint changed')
    return found[0]


def native_measure(executable, directory, ao, depth, surface, right, down, identity):
    h, w = ao.shape
    with tempfile.NamedTemporaryFile(prefix='native-profile-', suffix='.bin', dir=directory) as f:
        f.write(b'AOHPRO01'+struct.pack('<IIf', w, h, 0.0))
        for data, dtype in ((ao, 'u1'), (depth, '<f4'), (surface, 'u1'), (right, 'u1'), (down, 'u1'), (identity, '<u8')):
            f.write(np.asarray(data, dtype=dtype).tobytes())
        f.flush()
        run = subprocess.run([str(executable.resolve()), f.name], check=False, capture_output=True, text=True)
    if run.returncode not in (0, 3):
        raise ValueError(f'native profile failed: exit {run.returncode}: {run.stderr}')
    result = json.loads(run.stdout)
    result['native_exit'] = run.returncode
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('archive', type=pathlib.Path)
    p.add_argument('--attribution', required=True, type=pathlib.Path)
    p.add_argument('--qualification', required=True, type=pathlib.Path)
    p.add_argument('--native', required=True, type=pathlib.Path)
    p.add_argument('--reference-profile', type=pathlib.Path, help='require exactly the same qualified pixel population as an earlier native profile')
    p.add_argument('--output', required=True, type=pathlib.Path)
    args = p.parse_args()
    if args.output.name == 'proof.txt':
        p.error('proof.txt belongs exclusively to proof_run')
    attributed = json.loads(args.attribution.read_text())
    qualification = json.loads(args.qualification.read_text())
    if attributed.get('identity_format') != 'gpu-primitive-v2' or attributed.get('cpu_depth_used_for_identity') is not False:
        raise ValueError('qualified profiles require actual GPU primitive v2 identities')
    if not qualification.get('source_evidence') or not qualification.get('label_rationale'):
        raise ValueError('external patch labels lack source evidence/rationale')
    wall = select_patch(attributed['primitives'], qualification['wall'])
    roof = select_patch(attributed['primitives'], qualification['roof'])
    if wall['identity'] == roof['identity']:
        raise ValueError('wall and roof patch identities must differ')
    physical = physical_intersection(np.array(wall['xyz']), np.array(roof['xyz']))
    projections = {(s.get('projection_hash', '0'), s.get('ubo_hash'))
                   for patch in (wall, roof) for s in patch['submissions']}
    if len(projections) != 1:
        raise ValueError('patch projection state differs or is missing')
    ph, uh = next(iter(projections))
    viewports = {s.get('viewport') for patch in (wall, roof) for s in patch['submissions']}
    if len(viewports) != 1 or None in viewports:
        raise ValueError('patch viewport state differs or is missing')
    vx, vy, vw, vh = map(int, next(iter(viewports)).split(','))
    if min(vw, vh) <= 0:
        raise ValueError('invalid patch viewport')
    file = f'projection-{ph}.bin' if int(ph or 0) else f"frame-ubo-{attributed['frame']}-{uh}.bin"
    projection_bytes = (args.archive/file).read_bytes()
    if attribution.fnv(projection_bytes) != int(ph or 0) + (0 if int(ph or 0) else int(uh)):
        raise ValueError('projection hash mismatch')
    color_rows = list(attribution.records(args.archive/'color.meta'))
    meta = {k:v for r in color_rows if len(r) == 1 for k,v in r.items()}
    if meta.get('status') != 'complete' or int(meta['render_frame']) != attributed['frame']:
        raise ValueError('color archive and attribution frame differ')
    width, height = int(meta['width']), int(meta['height'])
    clip = attribution.project(physical, projection_bytes)
    if np.any(clip[:, 3] <= 0):
        raise ValueError('physical contact behind camera')
    ndc = clip[:, :3]/clip[:, 3:4]
    segment = np.column_stack((vx+(ndc[:, 0]+1)*vw/2, vy+(ndc[:, 1]+1)*vh/2))
    x0, y0, w, h = attributed['roi']
    if min(w, h) <= 0 or w*h > 262144:
        raise ValueError('profile ROI out of bounds')
    surface = np.zeros((h, w), dtype='u1')
    identity = np.zeros((h, w), dtype='<u8')
    patches = {wall['identity']: (1, 1), roof['identity']: (2, 2)}
    distances = []
    direction = segment[1]-segment[0]
    length = np.linalg.norm(direction)
    if length == 0:
        raise ValueError('physical contact projects to a point')
    for pixel in attributed['pixels']:
        if pixel['status'] != 'gpu-unique' or len(pixel['candidates']) != 1 or not pixel['depth_scene_matches_mrt']:
            continue
        label = patches.get(pixel['candidates'][0])
        if label is None:
            continue
        x, y = pixel['x'], pixel['y']
        surface[y-y0, x-x0], identity[y-y0, x-x0] = label
        rel = np.array([x+.5, y+.5])-segment[0]
        along = float(np.dot(rel, direction)/(length*length))
        signed = float((direction[0]*rel[1]-direction[1]*rel[0])/length)
        closest = segment[0]+np.clip(along, 0, 1)*direction
        distances.append(dict(x=x, y=y, patch=label[0], signed_distance_to_projected_line_px=signed,
                              distance_to_projected_segment_px=float(np.linalg.norm(np.array([x+.5,y+.5])-closest))))
    counts = {name: int(np.count_nonzero(surface == value)) for name, value in (('wall_pixels', 1), ('roof_pixels', 2))}
    right, down = np.zeros_like(surface), np.zeros_like(surface)
    for y in range(h):
        for x in range(w):
            if surface[y, x] == 0:
                continue
            for dx, dy, target in ((1, 0, right), (0, 1, down)):
                if x+dx >= w or y+dy >= h or surface[y+dy, x+dx] == 0 or surface[y+dy, x+dx] == surface[y, x]:
                    continue
                a = np.array([x+x0+.5, y+y0+.5]); b = a+[dx, dy]
                if crosses_segment(a, b, segment[0], segment[1]):
                    target[y, x] = 1
    counts['physically_qualified_edges'] = int(right.sum()+down.sum())
    reference_comparison = None
    if args.reference_profile:
        reference = json.loads(args.reference_profile.read_text())
        old_pixels = {(p['x'], p['y'], p['patch']) for p in reference['pixel_distances']}
        new_pixels = {(p['x'], p['y'], p['patch']) for p in distances}
        reference_comparison = dict(pixel_population_identical=old_pixels == new_pixels,
            contact_populations_identical=reference['populations'] == counts,
            physical_segment_identical=sorted(map(tuple, reference['physical_segment_world'])) == sorted(map(tuple, physical.tolist())),
            projected_segment_identical=sorted(map(tuple, reference['projected_segment_px'])) == sorted(map(tuple, segment.tolist())))
        if not all(reference_comparison.values()):
            raise ValueError('fixed reference contact population/projection changed: '+json.dumps(reference_comparison))
    # The original native reader decides measured/censored/missing. Empty geometry
    # populations are reported and can never become a successful profile.
    depth_bytes = (args.archive/'scene-depth.f32').read_bytes()
    if hashlib.sha256(depth_bytes).hexdigest() != attributed.get('depth_sha256'):
        raise ValueError('attribution lacks matching source depth fingerprint')
    depth = np.frombuffer(depth_bytes, dtype='<f4').reshape(height,width)[y0:y0+h,x0:x0+w]
    rows = list(attribution.records(args.archive/'manifest.txt'))
    manifest = {k:v for r in rows if len(r) == 1 for k,v in r.items()}
    if manifest.get('status') != 'complete' or int(manifest['render_frame']) != attributed['frame']:
        raise ValueError('AO stages frame/status mismatch')
    stages = []
    estimator_reports = []
    for row in rows:
        if 'stage' not in row:
            continue
        name = row['stage']
        if name.startswith('estimator-report-') and name.endswith('.rgba8'):
            estimator_reports.append(name)
            continue  # Exclusion/normal diagnostics are RGBA reports, not AO scalar stages.
        data = (args.archive/name).read_bytes()
        if int(row['width']) != width or int(row['height']) != height or len(data) != width*height or \
                attribution.fnv(data) != int(row['fnv1a64']):
            raise ValueError('AO stage dimensions/hash mismatch; no resampling permitted')
        ao = np.frombuffer(data, dtype='u1').reshape(height,width)[y0:y0+h,x0:x0+w]
        result = native_measure(args.native, args.output.parent, ao, depth, surface, right, down, identity)
        result['stage'] = name
        stages.append(result)
    nonempty = all(counts.values())
    output = dict(directives='DIRECTIVES v775512c234', diagnostic_only=True,
        source_attribution_sha256=hashlib.sha256(args.attribution.read_bytes()).hexdigest(),
        native_binary_sha256=hashlib.sha256(args.native.read_bytes()).hexdigest(),
        native_profile_header_sha256=hashlib.sha256((pathlib.Path(__file__).resolve().parents[4]/'game/graphics/opengl_renderer/ao_contact_profile.h').read_bytes()).hexdigest(),
        frame=attributed['frame'], logic_frame=int(meta['logic_frame']), mode=manifest.get('mode'),
        physical_segment_world=physical.tolist(), projected_segment_px=segment.tolist(),
        wall=wall, roof=roof, populations=counts, population_nonempty=nonempty,
        profile_input_qualified=nonempty, stages=stages, pixel_distances=distances,
        estimator_reports_not_scalar_profiles=estimator_reports,
        reference_population_comparison=reference_comparison,
        comparison_to_ssao_frame1400='not established: capture logic frame differs' if int(meta['logic_frame']) != 1400 else 'same tick only; other exogenous state equality not established',
        limitations=['labels name these source patches only, not all hut geometry',
                     'screen distances use projection of the physical source intersection, not GPU world-position readback',
                     'no owner verdict or global defect value is produced'])
    with args.output.open('x') as f:
        json.dump(output,f,allow_nan=False,separators=(',',':'))
    print(json.dumps(dict(populations=counts, stages=len(stages), profile_input_qualified=nonempty)))


if __name__ == '__main__':
    main()
