#!/usr/bin/env python3
"""HDR batch measurements. Invoked by proof_run; never writes proof.txt.

No historical proof imports: compatibility requires the same complete binary/APK,
render sources, data fingerprint and effective non-lighting settings. Synthetic
unit fixtures exercise aggregation, never certify a game execution.
"""
import argparse
import hashlib
import io
import json
import math
import re
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path

SCHEMA = 1
CHAIN = ('hdr_defect_3_curve', 'hdr_defect_5_sites_three_configs',
         'hdr_defect_6_intermediate_narrowing')
QUALITY = ('clipped', 'white', 'nearwhite')
# Only semantically established interior views of the Green Sage's hut belong
# here. None is established in kVantages: legacy is at (-116, 14, 40) m,
# not the hut at (-123, 46, 214) m. Keep its measurements as diagnostics.
HUT_VIEWS = frozenset()


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def fnv(path):
    h = 1469598103934665603
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            for value in block:
                h = ((h ^ value) * 1099511628211) & 0xffffffffffffffff
    return f'{h:016x}'


def dump(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def kv(text):
    return dict(re.findall(r'^([A-Za-z_][A-Za-z0-9_]*)=([^\s]+)$', text, re.M))


def normalized(text):
    text = re.sub(r'\r', '', text)
    text = re.sub(r'^[0-9]{2}-[0-9]{2} [0-9:.]+ +[A-Z]/[^\(]*\( *[0-9]+\): *', '', text, flags=re.M)
    return re.sub(r'^\s*[0-9]+\.[0-9]+\s+', '', text, flags=re.M)


def contract(root):
    import yaml
    doc = yaml.safe_load((root / '.autoport/backlog.yaml').read_text())
    items = doc['items'] if isinstance(doc, dict) else doc
    plan = next(x['proof_plan'] for x in items if x['id'] == 'lighting-hdr')
    if plan['mode'] != 'multi_process_batches' or plan['owner_authorized'] is not True:
        raise ValueError('unauthorized batch plan')
    source = (root / 'game/graphics/refset.cpp').read_text()
    table = source.split('constexpr Vantage kVantages[] = {', 1)[1].split('\n};', 1)[0]
    views = {v or 'legacy': level for v, level in re.findall(
        r'\{"([^"]*)",\s*"[^"]*",\s*"[^"]*",\s*"([^"]+)"', table)}
    level_source = (root / 'goal_src/jak1/engine/level/level-info.gc').read_text()
    sky = {}
    for name, block in re.findall(r'\(define ([\w-]+)\s+(.*?)(?=\n\(define |\Z)', level_source, re.S):
        if name in views.values():
            match = re.search(r':sky #(t|f)', block)
            if match:
                sky[name] = match[1] == 't'
    if len(set(views.values())) != plan['required_levels'] or set(sky) != set(views.values()):
        raise ValueError('refset/level tables do not cover proof_plan')
    return {'views': views, 'sky': sky, 'hours': plan['hours'], 'plan': plan}


def measure(path, rect=None):
    """Decode with ImageMagick; calculate masks and diagnostics from decoded pixels."""
    import numpy as np
    size = subprocess.check_output(['magick', 'identify', '-format', '%w %h', str(path)], text=True)
    w, h = map(int, size.split())
    if min(w, h) < 2 or w * h > 16000000:
        raise ValueError('invalid capture dimensions')
    command = ['magick', str(path)]
    if rect is not None:
        if (len(rect) != 4 or any(type(x) is not int for x in rect)
                or not 0 <= rect[0] < rect[2] <= w or not 0 <= rect[1] < rect[3] <= h):
            raise ValueError('invalid regional bounds')
        x, y, right, bottom = rect
        w, h = right - x, bottom - y
        if min(w, h) < 2:
            raise ValueError('regional bounds too small for detail measurement')
        command += ['-crop', f'{w}x{h}+{x}+{y}', '+repage']
    rgb = np.frombuffer(subprocess.check_output(
        command + ['-alpha', 'off', '-depth', '8', 'rgb:-']), np.uint8).reshape(h, w, 3)
    hsv = np.frombuffer(subprocess.check_output(
        command + ['-alpha', 'off', '-colorspace', 'HSB', '-set', 'colorspace', 'RGB',
         '-depth', '16', '-endian', 'LSB', 'rgb:-']), np.dtype('<u2')).reshape(h, w, 3) / 65535
    lo, hi = rgb.min(2), rgb.max(2)
    lum = (rgb.astype(np.int64) * [77, 150, 29]).sum(2) // 256
    grad = abs(lum[:-1, 1:] - lum[:-1, :-1]) + abs(lum[1:, :-1] - lum[:-1, :-1])
    return {'pixels': w * h, 'width': w, 'height': h, 'white': int((lo == 255).sum()),
            'nearwhite': int((lo >= 245).sum()), 'clipped': int((hi == 255).sum()),
            'black': int((hi <= 2).sum()), 'luma': float(lum.mean()),
            'luma_p99': float(np.quantile(lum, .99)), 'detail': float(grad.mean()),
            'flat': float((grad == 0).mean()), 'saturation': float(hsv[:, :, 1].mean()),
            'hue_bins': np.histogram(hsv[:, :, 0][hi > lo], bins=np.linspace(0, 1, 13))[0].tolist()}


def archive_extract(data, target):
    """Only regular files/directories below the fresh lot; never tar links/devices."""
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for member in archive.getmembers():
            rel = Path(member.name)
            if rel.is_absolute() or '..' in rel.parts or not (member.isfile() or member.isdir()):
                raise ValueError('unsafe capture archive')
            dest = target / rel
            if member.isdir():
                dest.mkdir(parents=True, exist_ok=True)
            else:
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(archive.extractfile(member).read())


def sun_components_complete(witnesses):
    """One native disc and the two differently sized rays, not duplicate witnesses."""
    discs = [w for w in witnesses if w.get('texture') == 'effects/middot']
    rays = [w for w in witnesses if w.get('texture') == 'effects/starflash2']
    expected = ((2800 * 4096, 2200 * 4096), (2200 * 4096, 2800 * 4096))
    return len(discs) == 1 and len(rays) == 2 and all(
        sum(abs(w.get('scale_x_goal', 0) - x) <= 1 and abs(w.get('scale_y_goal', 0) - y) <= 1
            for w in rays) == 1 for x, y in expected)


def sky_sequence_judgment(row, temporal):
    judgment = owner_sequence_judgment(row, temporal)
    partial = (owner_sequence_judgment(row, temporal, require_expected_white=False)
               if judgment.get('reason') == 'expected OFF whites not observed' else judgment)
    if row.get('layer') == 'sunset-sun' and any(
            s.get('sun_components_complete') is not True for s in row.get('samples', [])):
        return {'status': 'not_judged', 'reason': 'incomplete visible sun disc and two distinct rays',
                'partial_photometry': partial}
    if partial is not judgment:
        judgment['partial_photometry'] = partial
    judgment['limitation'] = ('textured sky bounds mix cloud and background; cloud visibility not qualified'
                             if row.get('layer') == 'clouds' else
                             'sun bounds include background; photometric preservation only')
    return judgment


def owner_regions(batch, images, region_measurer=measure):
    """Bounded diagnostic of the two actor effects, never an artistic verdict.

    Bounds come from submitted sprite corners and a GPU visibility query. Their
    union is shared across both arms and all temporal samples. Background pixels
    inside that rectangle remain mixed with the effect; keep this limitation.
    """
    raw = normalized((batch / 'engine.log').read_text(errors='replace'))
    samples, witnesses, errors = {}, [], []
    for line in raw.splitlines():
        match = re.match(r'REFSET sample case=(\S+) layer=(\S+) chain_lf=(\d+) ', line)
        if match:
            case, layer, frame = match.groups()
            rel = 'captures/' + ('supplement-v1/' if layer == 'supplement-v1' else '') + case + '.png'
            if frame in samples:
                errors.append('duplicate capture frame: ' + frame)
            samples[frame] = (case, rel)
        marker = next((m for m in ('HDR-OWNER-SPRITE ', 'HDR-OWNER-SKY ') if m in line), None)
        if marker:
            try:
                witness = json.loads(line.split(marker, 1)[1])
                if not isinstance(witness, dict):
                    raise ValueError('witness is not an object')
                if type(witness.get('lf')) is not int or type(witness.get('actor')) is not int or witness.get('actor') not in (0, 10012, 10013, 1395):
                    raise ValueError('unknown actor or frame')
                if witness['actor'] == 0:
                    layer = witness.get('layer')
                    if witness.get('case') != layer or layer not in ('clouds', 'sunset-sun'):
                        raise ValueError('invalid actor zero layer/case')
                    if layer == 'clouds':
                        if (marker != 'HDR-OWNER-SKY ' or witness.get('association') != 'sky_draw_textured_triangles'
                                or type(witness.get('bucket')) is not int or witness['bucket'] != 3
                                or witness.get('prim_tme') is not True
                                or witness.get('prim_abe') is not True
                                or any(type(witness.get(k)) is not int or witness[k] != value
                                       for k, value in (('alpha_a', 0), ('alpha_b', 2),
                                                        ('alpha_c', 0), ('alpha_d', 1), ('alpha_fix', 0)))
                                or type(witness.get('vertices')) is not int or witness['vertices'] <= 0
                                or not isinstance(witness.get('tbps'), list) or not witness['tbps']
                                or any(type(v) is not int or v < 0 for v in witness['tbps'])):
                            raise ValueError('invalid clouds provenance')
                    else:
                        error, tolerance = witness.get('association_error_m'), witness.get('association_tolerance_m')
                        if (marker != 'HDR-OWNER-SPRITE ' or witness.get('association') != 'texture_and_sun_position'
                                or witness.get('texture') not in ('effects/middot', 'effects/starflash2')
                                or type(error) not in (int, float) or not math.isfinite(error) or not 0 <= error <= .05
                                or type(tolerance) not in (int, float) or tolerance != .05
                                or any(type(witness.get(k)) not in (int, float) or not math.isfinite(witness[k])
                                       for k in ('scale_x_goal', 'scale_y_goal', 'rotation_z'))):
                            raise ValueError('invalid sunset-sun provenance')
                elif marker == 'HDR-OWNER-SKY ':
                    raise ValueError('sky witness requires actor zero')
                witnesses.append(witness)
            except (ValueError, TypeError) as exc:
                errors.append('invalid sprite witness: ' + str(exc))
    groups = {}
    for witness in witnesses:
        entry = samples.get(str(witness['lf']))
        if entry is None:
            errors.append('sprite has no matching capture frame: ' + str(witness['lf']))
            continue
        case, rel = entry
        if rel not in images:
            errors.append('sprite capture missing: ' + rel)
            continue
        arm, stem = case.split('/', 1)
        stem = re.sub(r'-t\d+$', '', stem)
        group_keys = [(witness['actor'], stem, witness.get('layer', '') if witness['actor'] == 0 else '')]
        if witness.get('layer') == 'portal_disc':
            if (witness['actor'] != 1395 or witness.get('texture') != 'effects/harddot'
                    or type(witness.get('render_mode')) is not int or witness['render_mode'] != 3):
                errors.append('invalid portal_disc provenance: ' + rel)
            else:
                group_keys.append((1395, stem, 'portal_disc'))
        witness_groups = [groups.setdefault(key, {'witnesses': [], 'bounds': []})
                          for key in group_keys]
        for group in witness_groups:
            group['witnesses'].append({'image': rel, **witness})
        rect = witness.get('roi')
        if witness.get('supported') is not True or witness.get('passed') is not True:
            continue
        if (not isinstance(rect, list) or len(rect) != 4 or any(type(x) is not int for x in rect)
                or not 0 <= rect[0] < rect[2] <= 320 or not 0 <= rect[1] < rect[3] <= 180):
            errors.append('invalid sprite bounds: ' + rel)
            continue
        for group in witness_groups:
            group['bounds'].append(rect)
    records = []
    for (actor, stem, layer), group in sorted(groups.items()):
        bounds = group.pop('bounds')
        row = {'actor': actor, 'view_hour': stem, **group, 'status': 'not_judged', 'samples': []}
        if layer:
            row['layer'] = layer
        if not bounds:
            row['reason'] = 'no supported sprite with fragments passing depth/alpha'
            records.append(row)
            continue
        rect = [min(r[0] for r in bounds), min(r[1] for r in bounds),
                max(r[2] for r in bounds), max(r[3] for r in bounds)]
        row['roi_exclusive'] = rect
        for frame, (case, rel) in samples.items():
            arm, sample_stem = case.split('/', 1)
            if re.sub(r'-t\d+$', '', sample_stem) != stem or rel not in images:
                continue
            try:
                sidecar = kv((batch / (rel + '.provenance.txt')).read_text())
                if sidecar.get('case') != case or sidecar.get('capture_lf') != frame or sidecar.get('png') != fnv(batch / rel):
                    raise ValueError('regional capture provenance mismatch')
                if images[rel]['stats']['width'] != 320 or images[rel]['stats']['height'] != 180:
                    raise ValueError('regional projection/capture resolution mismatch')
                stats = region_measurer(batch / rel, rect)
                matched = [w for w in group['witnesses'] if str(w['lf']) == frame]
                visible = [w for w in matched if w.get('passed') is True and w.get('supported') is True]
                row['samples'].append({'arm': arm, 'case': case, 'frame': int(frame),
                    'image': rel, 'sha256': images[rel]['sha256'], 'stats': stats,
                    'visible_sprites': len(visible),
                    **({'sun_components_complete': sun_components_complete(visible)} if layer == 'sunset-sun' else {})})
            except (ValueError, OSError, subprocess.CalledProcessError) as exc:
                errors.append(rel + ': ' + str(exc))
        row['summary'] = {}
        for arm in ('recharged', 'origine-lumiere'):
            arm_samples = [s for s in row['samples'] if s['arm'] == arm]
            summary = {'samples': len(arm_samples),
                       'visible_frames': sum(s['visible_sprites'] > 0 for s in arm_samples)}
            for key in ('white', 'nearwhite', 'clipped', 'luma', 'detail', 'flat', 'saturation'):
                values = [s['stats'][key] for s in arm_samples]
                if values:
                    summary[key] = {'min': min(values), 'max': max(values), 'mean': sum(values) / len(values)}
            row['summary'][arm] = summary
        row['reason'] = 'projected sprite bounds include background; expected white/detail and local colour preservation not yet qualified'
        records.append(row)
    return {'schema': 1, 'status': 'diagnostic_only', 'engine_sha256': sha(batch / 'engine.log'),
            'errors': errors, 'regions': records, 'unattributed_cases': [case for case in ('clouds', 'sunset-sun', 'sage-hut-ground')
                                                    if not any(r.get('layer') == case for r in records)],
            'witness_count': len(witnesses)}


def adb(args, *command):
    return subprocess.check_output([args.adb, '-s', args.serial, *command], timeout=180)


def snapshot(args, suffix):
    batch = Path(args.batch)
    apk_path = adb(args, 'shell', 'pm', 'path', args.pkg).decode().strip().splitlines()
    if len(apk_path) != 1 or not apk_path[0].startswith('package:'):
        raise ValueError('APK provenance ambiguous or absent')
    apk_file = apk_path[0][8:].strip()
    if not re.fullmatch(r'/[A-Za-z0-9_./=+~\-]+', apk_file):
        raise ValueError('invalid APK path')
    apk_digest = adb(args, 'shell', 'sha256sum', apk_file).decode().split()[0]
    native_file = str(Path(apk_file).parent / 'lib/arm64/libgk.so')
    try:
        installed = adb(args, 'shell', 'sha256sum', native_file).decode().split()[0]
        if not re.fullmatch('[0-9a-f]{64}', installed):
            raise ValueError('native library not extracted')
    except (subprocess.CalledProcessError, ValueError, IndexError):
        apk = adb(args, 'exec-out', 'cat', apk_file)
        with zipfile.ZipFile(io.BytesIO(apk)) as archive:
            installed = hashlib.sha256(archive.read('lib/arm64-v8a/libgk.so')).hexdigest()
    local = sha(args.binary)
    if installed != local:
        raise ValueError('installed libgk differs from local binary')
    props = adb(args, 'shell', 'getprop').decode()
    (batch / ('props-' + suffix + '.txt')).write_text(props)
    # Preserve raw app configuration files when present. Effective capture settings
    # are independently read from REFSET effective, not inferred from these files.
    configs = adb(args, 'exec-out', 'run-as', args.pkg, 'sh', '-c',
                  'find files -type f -name "*settings*.json"')
    (batch / ('config-paths-' + suffix + '.txt')).write_bytes(configs)
    hashes = {}
    for entry in configs.decode().splitlines():
        if not re.fullmatch(r'files/[A-Za-z0-9_./ -]+\.(json|ini)', entry) or '..' in Path(entry).parts:
            raise ValueError('invalid config path')
        data = adb(args, 'exec-out', 'run-as', args.pkg, 'cat', entry)
        dest = batch / ('config-' + suffix) / entry
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        hashes[entry] = sha(dest)
    asset_root = adb(args, 'exec-out', 'run-as', args.pkg, 'cat', 'files/asset_root.txt').decode().strip()
    if not re.fullmatch(r'/[A-Za-z0-9_./ -]+', asset_root) or '..' in Path(asset_root).parts:
        raise ValueError('invalid asset root')
    settings = adb(args, 'exec-out', 'cat', asset_root.rstrip('/') + '/settings.ini')
    (batch / ('settings-' + suffix + '.ini')).write_bytes(settings)
    hashes['settings.ini'] = hashlib.sha256(settings).hexdigest()
    return {'binary_sha256': local, 'apk_sha256': apk_digest,
            'installed_sha256': installed, 'serial': args.serial, 'config_files': hashes}


def prepare(args):
    if args.serial != 'eae4df44':
        raise ValueError('HDR campaign requires authorized Redmi eae4df44')
    batch = Path(args.batch)
    batch.mkdir(parents=True, exist_ok=False)
    c = contract(Path(args.root))
    views = args.vantages.split(',')
    hours = [int(x) for x in args.hours.split(',')]
    if len(set(views)) != len(views) or not set(views) <= c['views'].keys():
        raise ValueError('unknown or duplicate vantage')
    if len(set(hours)) != len(hours) or not set(hours) <= set(c['hours']):
        raise ValueError('unknown or duplicate hour')
    provenance = snapshot(args, 'start')
    # FNV is the runtime sidecar identifier; SHA256 remains authoritative for
    # installed/local identity. Reuse only a prior producer snapshot of identical bytes.
    fingerprint = None
    for previous in batch.parent.glob('*/start.json'):
        old = json.loads(previous.read_text()).get('provenance', {})
        if old.get('binary_sha256') == provenance['binary_sha256']:
            fingerprint = old.get('binary_fnv')
            if fingerprint:
                break
    provenance['binary_fnv'] = fingerprint or fnv(args.binary)
    dump(batch / 'start.json', {'schema': SCHEMA, 'contract': c, 'provenance': provenance,
                               'requested': [[v, h] for v in views for h in hours],
                               'replacements': args.replace})


def finish(args):
    batch = Path(args.batch)
    start = json.loads((batch / 'start.json').read_text())
    errors = []
    try:
        end = snapshot(args, 'end')
        if {k: v for k, v in end.items() if k != 'binary_fnv'} != {k: v for k, v in start['provenance'].items() if k != 'binary_fnv'}:
            errors.append('binary/APK/config changed during batch')
    except Exception as exc:
        errors.append('end provenance: ' + str(exc))
    try:
        data = adb(args, 'exec-out', 'run-as', args.pkg, 'tar', '-C', args.remote, '-cf', '-', '.')
        archive_extract(data, batch / 'captures')
    except Exception as exc:
        errors.append('capture collection: ' + str(exc))
    if 'binary_fnv' not in start['provenance'] and sha(args.binary) == start['provenance']['binary_sha256']:
        start['provenance']['binary_fnv'] = fnv(args.binary)
    pixel_records = {}
    for image in (batch / 'captures').rglob('*.png'):
        try:
            pixel_records[str(image.relative_to(batch))] = {'sha256': sha(image), 'stats': measure(image)}
        except Exception as exc:
            errors.append('image measurement: ' + str(exc))
    dump(batch / 'pixels.json', {'helper_sha256': sha(__file__), 'images': pixel_records})
    dump(batch / 'owner-regions.json', owner_regions(batch, pixel_records))
    manifest = {**start, 'id': batch.name, 'producer': 'proof_run.sh', 'crash': args.crash,
                'errors': errors, 'files': {},
                'run': {'started_at': args.started_at, 'duration_s': args.duration_s}}
    for path in sorted(batch.rglob('*')):
        if path.is_file() and path.name != 'manifest.json':
            manifest['files'][str(path.relative_to(batch))] = sha(path)
    dump(batch / 'manifest.json', manifest)


def rendering_properties(path):
    """Parse sealed Android getprop output; exclude only campaign plan controls.

    Empty and absent properties both select the renderer's default. All nonempty
    unknown debug.opengoal properties participate, so a new rendering knob cannot
    silently escape compatibility checks.
    """
    properties = {}
    for line in path.read_text(errors='strict').splitlines():
        match = re.fullmatch(r'\[([^\]]+)\]: \[(.*)\]', line)
        if not match:
            if 'debug.opengoal.' in line:
                raise ValueError('unreadable rendering property snapshot')
            continue
        key, value = match.groups()
        if not key.startswith('debug.opengoal.'):
            continue
        if key in properties:
            raise ValueError('duplicate rendering property: ' + key)
        properties[key] = value
    if not properties:
        raise ValueError('absent rendering properties in snapshot')
    def plan_control(key):
        return (key == 'debug.opengoal.refset' or key.startswith('debug.opengoal.refset.')
                or key.startswith('debug.opengoal.level.warp')
                or key in ('debug.opengoal.want.levels', 'debug.opengoal.want.display',
                           'debug.opengoal.padreplay')
                or key.startswith('debug.opengoal.feature'))
    return {key: value for key, value in properties.items() if value and not plan_control(key)}


def raw_configuration(files, suffix):
    """Reconstruct configuration identity from sealed raw snapshot files."""
    settings = 'settings-' + suffix + '.ini'
    if settings not in files:
        raise ValueError('missing sealed raw settings snapshot: ' + settings)
    prefix = 'config-' + suffix + '/'
    config = {name[len(prefix):]: digest for name, digest in files.items() if name.startswith(prefix)}
    config['settings.ini'] = files[settings]
    return config


def read_batch(path, expected, measurer):
    m = json.loads(path.read_text())
    if m['schema'] != SCHEMA or m['producer'] != 'proof_run.sh' or m['contract'] != expected:
        raise ValueError('schema/producer/render contract incompatible')
    blocking = [e for e in m['errors'] if not (m.get('crash') == 1 and e.startswith('capture collection:'))]
    if blocking:
        raise ValueError('; '.join(blocking))
    base = path.parent
    files = m['files']
    if 'engine.log' not in files or 'start.json' not in files:
        raise ValueError('missing raw sources')
    actual = {str(p.relative_to(base)) for p in base.rglob('*') if p.is_file() and p != path}
    if actual != set(files):
        raise ValueError('unregistered or missing files')
    for name, digest in files.items():
        p = base / name
        if Path(name).is_absolute() or '..' in Path(name).parts or p.is_symlink() or sha(p) != digest:
            raise ValueError('missing/modified/unsafe file: ' + name)
    for snapshot_name in ('props-start.txt', 'props-end.txt'):
        if snapshot_name not in files:
            raise ValueError('missing sealed rendering property snapshot')
    props_start = rendering_properties(base / 'props-start.txt')
    props_end = rendering_properties(base / 'props-end.txt')
    if props_start != props_end:
        raise ValueError('rendering properties changed during batch')
    raw = normalized((base / 'engine.log').read_text(errors='replace'))
    values = kv(raw)
    provenance = dict(m['provenance'])
    provenance['rendering_properties'] = props_start
    config_start = raw_configuration(files, 'start')
    config_end = raw_configuration(files, 'end')
    if config_start != config_end:
        raise ValueError('raw configuration changed during batch')
    if provenance.get('config_files') != config_start:
        raise ValueError('raw configuration hashes disagree with provenance')
    if provenance['binary_sha256'] != provenance['installed_sha256'] or any(
            not re.fullmatch('[0-9a-f]{64}', provenance[k]) for k in
            ('binary_sha256', 'installed_sha256', 'apk_sha256')):
        raise ValueError('incomplete binary provenance')
    if m.get('crash') == 1 and not any(n.endswith('.png') for n in files):
        requested = [tuple(x) for x in m['requested']]
        if not requested or len(requested) != len(set(requested)) or any(v not in expected['views'] or h not in expected['hours'] for v, h in requested):
            raise ValueError('invalid crashed batch requests')
        m.update(pairs={}, values=values, identity=(provenance, None))
        return m
    probes_complete = int(values.get('refset_probe_frames', '0')) > 0 and values.get('refset_probe_frames') == values.get('refset_captured')
    init = re.findall(r'REFSET provenance-init version=2 data=([0-9a-f]{16}) input=([0-9a-f]{16}) ', raw)
    if len(set(init)) != 1:
        raise ValueError('missing or conflicting runtime data/input identity')
    data_fp, input_fp = init[0]
    fingerprints = (provenance.get('binary_fnv', ''), data_fp)
    if (base / 'captures/refset-format.txt').read_text().strip() != 'version=2':
        raise ValueError('capture schema absent or incompatible')
    if any(not re.fullmatch('[0-9a-f]{16}', x) or int(x, 16) == 0 for x in fingerprints):
        raise ValueError('missing runtime render/data identity')
    effective = {}
    for line in raw.splitlines():
        if not line.startswith('REFSET effective '):
            continue
        match = re.fullmatch(r'REFSET effective case=(\S+) options=(.*)', line)
        if not match:
            raise ValueError('malformed effective settings record')
        case, options = match.groups()
        if case in effective:
            raise ValueError('duplicate capture effective settings')
        effective[case] = json.loads(options)
        if not isinstance(effective[case], dict):
            raise ValueError('malformed effective settings object')
    requested = [tuple(x) for x in m['requested']]
    if len(set(requested)) != len(requested) or not requested:
        raise ValueError('duplicate/empty requested views')
    temporal = int(values.get('refset_temporal_samples', '1'))
    if temporal < 1 or temporal > 16:
        raise ValueError('invalid temporal sample count')
    requested_temporal = re.findall(r'^\[debug\.opengoal\.refset\.temporal\]: \[([^\]]*)\]$',
                                   (base / 'props-start.txt').read_text(), re.M)
    if requested_temporal and requested_temporal != [''] and requested_temporal != [str(temporal)]:
        raise ValueError('requested/effective temporal count differs')
    temporal_failures = {}
    if temporal > 1:
        expected_count = 2 * temporal * len(requested)
        actual_count = sum(name.startswith('captures/') and name.endswith('.png') for name in files)
        if (actual_count > expected_count or any(values.get(k) != str(actual_count) for k in
                ('refset_temporal_captured', 'refset_captured'))
                or int(values.get('refset_probe_frames', '0')) < actual_count):
            raise ValueError('temporal capture accounting inconsistent')
        temporal_configs = set()
        particle_metadata_modes = set()
        for view, hour in requested:
            stem = ('' if view == 'legacy' else view + '-') + f'h{hour:02}'
            for arm in ('recharged', 'origine-lumiere'):
                frames = []
                spacing = None
                base_options = None
                sequence_repin = None
                sequence_temporal = None
                for sample in range(temporal):
                    case = arm + '/' + stem + (f'-t{sample:02}' if sample else '')
                    candidates = [prefix + case + '.png' for prefix in
                                  ('captures/', 'captures/supplement-v1/')]
                    present = [p for p in candidates if p in files]
                    if not present:
                        temporal_failures.setdefault((view, hour), []).append('temporal capture absent: ' + case)
                        continue
                    if len(present) != 1:
                        raise ValueError('temporal capture duplicate: ' + case)
                    rel = present[0]
                    sidecar = kv((base / (rel + '.provenance.txt')).read_text())
                    if (sidecar.get('case') != case or sidecar.get('png') != fnv(base / rel)
                            or sidecar.get('bin') != fingerprints[0] or sidecar.get('data') != fingerprints[1]
                            or sidecar.get('input') != input_fp or sidecar.get('version') != '2'):
                        raise ValueError('temporal provenance mismatch: ' + case)
                    temporal_configs.add(sidecar.get('config'))
                    if len(temporal_configs) != 1 or not re.fullmatch('[0-9a-f]{16}', sidecar.get('config', '')):
                        raise ValueError('temporal configuration changed or absent')
                    invariant = {k: v for k, v in effective.get(case, {}).items() if k != 'temporal'}
                    if base_options is not None and invariant != base_options:
                        raise ValueError('rendering settings changed within temporal arm')
                    base_options = invariant
                    options = effective.get(case, {}).get('temporal', {})
                    if (type(options.get('samples')) is not int or type(options.get('sample')) is not int
                            or options.get('samples') != temporal or options.get('sample') != sample
                            or options.get('particle_step') != 'once-per-logic-frame'
                            or type(options.get('spacing_lf')) is not int or options['spacing_lf'] <= 0):
                        raise ValueError('temporal effective settings absent/incompatible: ' + case)
                    if spacing is not None and spacing != options['spacing_lf']:
                        raise ValueError('temporal spacing changed')
                    spacing = options['spacing_lf']
                    frame = int(sidecar['capture_lf'])
                    fields = {'particle_repin_lf', 'particle_age'} & options.keys()
                    if fields and len(fields) != 2:
                        raise ValueError('partial temporal particle metadata: ' + case)
                    particle_metadata_modes.add(bool(fields))
                    if len(particle_metadata_modes) != 1:
                        raise ValueError('mixed temporal particle metadata')
                    if fields:
                        repin, age = options['particle_repin_lf'], options['particle_age']
                        if (type(repin) is not int or type(age) is not int or repin <= 0
                                or not re.fullmatch('[0-9]+', sidecar['capture_lf'])
                                or frame <= 0 or age != (sample + 1) * spacing - 1
                                or frame - repin != age):
                            raise ValueError('invalid temporal particle age/date: ' + case)
                        if sequence_repin is not None and sequence_repin != repin:
                            raise ValueError('temporal particle repin changed within sequence')
                        sequence_repin = repin
                    # Sample and age vary by the validated cadence within a sequence;
                    # preserve every unknown temporal setting in its invariant.
                    temporal_invariant = {k: v for k, v in options.items()
                                          if k not in ('sample', 'particle_age', 'particle_repin_lf')}
                    if sequence_temporal is not None and sequence_temporal != temporal_invariant:
                        raise ValueError('temporal settings changed within sequence')
                    sequence_temporal = temporal_invariant
                    frames.append(frame)
                if any(b - a != spacing for a, b in zip(frames, frames[1:])):
                    temporal_failures.setdefault((view, hour), []).append('temporal cadence incomplete')
    cached_pixels = json.loads((base / 'pixels.json').read_text()) if 'pixels.json' in files else {}
    pairs = {}
    unqualified = {}
    all_options = []
    configs = set()
    for view, hour in requested:
        if view not in expected['views'] or hour not in expected['hours']:
            raise ValueError('requested view/hour outside contract')
        level = expected['views'][view]
        stem = ('' if view == 'legacy' else view + '-') + f'h{hour:02}'
        pair = []
        reasons = [] if probes_complete else ['sky probes do not account for captures']
        reasons += temporal_failures.get((view, hour), [])
        for phase, arm in ((2, 'recharged'), (3, 'origine-lumiere')):
            case = arm + '/' + stem
            rel = 'captures/' + case + '.png'
            supplemental = 'captures/supplement-v1/' + case + '.png'
            if rel in files and supplemental in files:
                raise ValueError('duplicate primary/supplemental capture')
            if supplemental in files:
                rel = supplemental
            # Missing pairs remain explicitly incomplete, never silently supplied by
            # another lot unless the replacement mapping identifies the old request.
            if rel not in files:
                reasons.append('capture absent: ' + case)
                break
            sidecar = kv((base / (rel + '.provenance.txt')).read_text())
            if sidecar.get('version') != '2' or sidecar.get('case') != case or sidecar.get('bin') != fingerprints[0] or sidecar.get('data') != fingerprints[1]:
                raise ValueError('capture provenance incompatible')
            if sidecar.get('input') != input_fp or sidecar.get('png') != fnv(base / rel) or not re.fullmatch('[0-9a-f]{16}', sidecar.get('config', '')) or int(sidecar['config'], 16) == 0:
                raise ValueError('capture input/config/pixel provenance mismatch')
            configs.add(sidecar['config'])
            if len(configs) > 1:
                raise ValueError('capture config changed within batch')
            options = effective.get(case)
            if options is None:
                reasons.append('effective settings absent: ' + case)
            else:
                if not isinstance(options.get('output'), dict) or not {'profile', 'curve', 'exposure', 'pbr_exposure', 'knee'} <= options['output'].keys():
                    raise ValueError('missing effective output profile')
                if options.get('master') is not True or options.get('lighting') is not (phase == 2):
                    raise ValueError('wrong effective ON/OFF settings')
                if options.get('hdr') is not (phase == 2):
                    raise ValueError('ON capture did not use HDR')
                if not isinstance(options.get('others'), dict) or not options['others']:
                    raise ValueError('missing effective non-lighting settings')
            key = f'hdr_{view.replace("-", "_")}_h{hour}_p{phase}_'
            if sidecar.get('flavour') != 'normal' or not re.fullmatch(r'[0-9]+', sidecar.get('capture_lf', '')):
                raise ValueError('capture frame/flavour provenance mismatch')
            published_frame = values.get(key + 'cap_lf')
            if published_frame is None:
                reasons.append('final capture frame measurement absent: ' + case)
            elif not re.fullmatch(r'[0-9]+', published_frame) or sidecar['capture_lf'] != published_frame:
                raise ValueError('capture frame/flavour provenance mismatch')
            published_levels = values.get(key + 'levels')
            if published_levels is None:
                reasons.append('final level measurement absent: ' + case)
            elif level not in published_levels.split(','):
                reasons.append('expected region not drawn: ' + case)
            cache = cached_pixels.get('images', {}).get(rel)
            if measurer is measure and cached_pixels.get('helper_sha256') == sha(__file__) and cache and cache.get('sha256') == files[rel]:
                stats = cache['stats']
            else:
                stats = measurer(base / rel)
            published_pixels = values.get(key + 'pixels')
            if published_pixels is None:
                reasons.append('final pixel count measurement absent: ' + case)
            elif not re.fullmatch(r'[0-9]+', published_pixels) or stats['pixels'] != int(published_pixels):
                raise ValueError('capture dimensions disagree with engine')
            if stats['black'] >= .99 * stats['pixels'] or stats['luma_p99'] <= 2 or sum(stats['hue_bins']) == 0:
                reasons.append('black or achromatic capture: ' + case)
            # The purge timestamp is execution evidence, not a rendering option.
            # Its source remains sealed; normalize only this copied comparison value
            # after the full temporal sequence metadata has been checked above.
            if temporal > 1 and options is not None and 'particle_repin_lf' in options.get('temporal', {}):
                options = {**options, 'temporal': {k: v for k, v in options['temporal'].items()
                                                 if k != 'particle_repin_lf'}}
            pair.append((stats, options))
        if len(pair) != 2:
            unqualified[(view, hour)] = {'reasons': reasons, 'measured_arms': [{'stats': st, 'options': opt} for st, opt in pair]}
            continue
        comparable = pair[0][1] is not None and pair[1][1] is not None
        if comparable and pair[0][1]['others'] != pair[1][1]['others']:
            raise ValueError('non-lighting settings differ ON/OFF')
        if pair[0][0]['width'] != pair[1][0]['width'] or pair[0][0]['height'] != pair[1][0]['height']:
            raise ValueError('dimensions differ ON/OFF')
        bgh = dict(re.findall(r'h(\d+):(\d+)', values.get('refset_bgh_' + view.replace('-', '_'), '')))
        if f'{hour:02}' not in bgh or 'refset_bg_max_pm_' + view.replace('-', '_') not in values:
            reasons.append('sky pixel measurement absent')
            unqualified[(view, hour)] = {'reasons': reasons, 'on': pair[0][0], 'off': pair[1][0], 'comparable': comparable, 'options': [x[1] for x in pair]}
            continue
        bg = int(bgh[f'{hour:02}'])
        if not 0 <= bg <= 1000:
            raise ValueError('invalid sky pixels')
        bg_max = int(values['refset_bg_max_pm_' + view.replace('-', '_')])
        if not bg <= bg_max <= 1000:
            raise ValueError('inconsistent sky min/max')
        record = {'on': pair[0][0], 'off': pair[1][0], 'comparable': comparable, 'sky_pm': bg, 'sky_max_pm': bg_max, 'level': level,
                               'options': [x[1] for x in pair]}
        if reasons:
            unqualified[(view, hour)] = {**record, 'reasons': reasons}
        else:
            pairs[(view, hour)] = record
    m['unqualified'] = unqualified
    m['pairs'] = pairs
    m['values'] = values
    m['identity'] = (provenance, fingerprints)
    m['owner_regions'] = None
    if 'owner-regions.json' in files:
        # Reconstruct regional observations from sealed raw captures and queries.
        # Historical summaries never become a verdict by being present in JSON.
        images = {}
        for rel, digest in files.items():
            if rel.startswith('captures/') and rel.endswith('.png'):
                cache = cached_pixels.get('images', {}).get(rel)
                stats = (cache['stats'] if measurer is measure
                         and cached_pixels.get('helper_sha256') == sha(__file__)
                         and cache and cache.get('sha256') == digest else measurer(base / rel))
                images[rel] = {'sha256': digest, 'stats': stats}
        m['owner_regions'] = owner_regions(base, images, measurer)
    return m


def chain_measurements(values, required):
    """Reproduce hdr.cpp's chain verdicts from their measured operands.

    Missing evidence blocks selected runs. A replaced incomplete run contributes
    positive observations only, never a historical flag caused by an unvisited arm.
    """
    defects = dict.fromkeys(CHAIN, 0)
    findings = []
    curve, sites, narrowing = CHAIN
    def fail(group, detail):
        defects[group] = 1
        findings.append(detail)
    def number(key, group):
        value = values.get(key)
        if value is None:
            if required:
                fail(group, key + '=absent')
            return None
        if not re.fullmatch(r'[0-9]+', value):
            fail(group, key + '=malformed')
            return None
        return int(value)
    samples = number('hdr_curve_samples', curve)
    if required and samples == 0:
        fail(curve, 'hdr_curve_samples=0')
    for key in ('hdr_curve_monotone_bad', 'hdr_curve_unbounded_bad'):
        count = number(key, curve)
        if count is not None and count > 0:
            fail(curve, key + '=' + str(count))
    kink = number('hdr_curve_kink_max_x1000', curve)
    if kink is not None and kink > 50:
        fail(curve, 'hdr_curve_kink_max_x1000=' + str(kink))
    elif kink == 50:
        # Published rounding maps both sides of the exact <=0.05 boundary to
        # 50. Only the engine's exact-float comparison can resolve this bin.
        flag = values.get(curve)
        if flag == '1' or (required and flag != '0'):
            fail(curve, 'hdr_curve_kink_max_x1000=50,exact_curve_flag=' + str(flag))
    for arm in ('recharged', 'origine_lumiere'):
        frames = number('hdr_cfg_frames_' + arm, sites)
        bad = number('hdr_cfg_bad_' + arm, sites)
        if required and frames == 0:
            fail(sites, 'hdr_cfg_frames_' + arm + '=0')
        if bad is not None and bad > 0:
            fail(sites, 'hdr_cfg_bad_' + arm + '=' + str(bad))
    implicit = number('tonemap_sites_implicit', narrowing)
    if implicit is not None and implicit > 0:
        fail(narrowing, 'tonemap_sites_implicit=' + str(implicit))
    aux_count = number('hdr_aux_clamped_reads', narrowing)
    aux_text = values.get('hdr_aux_clamped_sites')
    if aux_text is None:
        if required:
            fail(narrowing, 'hdr_aux_clamped_sites=absent')
    else:
        names = [] if aux_text == 'aucun' else aux_text.split(',')
        if aux_count is not None and (len(names) != aux_count or len(set(names)) != len(names)):
            fail(narrowing, 'hdr_aux_clamped_reads/sites=inconsistent')
        if 'Sprite3_Distort:scene-copy' in names:
            fail(narrowing, 'hdr_aux_clamped_sites=Sprite3_Distort:scene-copy')
    return defects, findings


def owner_sequence_judgment(row, temporal, require_expected_white=True):
    """Compare temporal populations, never demand matching lightning frames.

    OFF's observed envelope supplies the bounds: no invented artistic tolerance.
    These constraints judge the reported eco brightness loss. The projected
    rectangle also contains background; no local colour attribution is claimed.
    """
    samples = row.get('samples', [])
    arms = {arm: [s for s in samples if s.get('arm') == arm]
            for arm in ('recharged', 'origine-lumiere')}
    rect = row.get('roi_exclusive', [])
    if (temporal < 2 or len(rect) != 4
            or any(type(x) is not int for x in rect)
            or not 0 <= rect[0] < rect[2] <= 320
            or not 0 <= rect[1] < rect[3] <= 180):
        return {'status': 'not_judged', 'reason': 'no comparable temporal projected ROI'}
    if (len(samples) != 2 * temporal or any(len(v) != temporal for v in arms.values())
            or len({s.get('image') for s in samples}) != len(samples)
            or any(s.get('visible_sprites', 0) <= 0 for s in samples)):
        return {'status': 'not_judged', 'reason': 'incomplete, duplicate or invisible temporal samples'}
    bounds, failures = {}, []
    for key in ('white', 'nearwhite', 'clipped', 'detail', 'flat'):
        values = {arm: [s.get('stats', {}).get(key) for s in seq] for arm, seq in arms.items()}
        if any(not isinstance(v, (int, float)) or not math.isfinite(v) or v < 0
               for seq in values.values() for v in seq):
            return {'status': 'not_judged', 'reason': 'invalid regional measurement: ' + key}
        off = values['origine-lumiere']
        on = values['recharged']
        mean = sum(on) / len(on)
        bounds[key] = {'off_min': min(off), 'off_max': max(off),
                       'off_mean': sum(off) / len(off), 'on_mean': mean}
        if key in ('white', 'nearwhite') and not min(off) <= mean <= max(off):
            failures.append(key + ': ON mean outside observed OFF temporal envelope')
        if key in ('clipped', 'flat') and mean > max(off):
            failures.append(key + ': ON excess beyond observed OFF temporal envelope')
        if key == 'detail' and mean < min(off):
            failures.append('detail: ON loss beyond observed OFF temporal envelope')
    if require_expected_white and bounds['white']['off_mean'] <= 0:
        return {'status': 'not_judged', 'reason': 'expected OFF whites not observed', 'bounds': bounds}
    if bounds['white']['off_mean'] > 0 and bounds['white']['on_mean'] <= 0:
        failures.append('white: expected whites suppressed entirely ON')
    return {'status': 'failed' if failures else 'passed', 'measured': True,
            'photometric_passed': not failures, 'bounds': bounds, 'failures': failures,
            'limitation': 'projected bounds include background; local colour and non-lightning3 sprites not attributed'}


def owner_regressions(expected, observations=()):
    owner_required = list(expected['plan'].get('owner_regression_cases', []))
    measured, failed, passed, findings = [], [], [], []
    for case in owner_required:
        layer = 'clouds' if case.startswith('nuages ') else 'sunset-sun' if case.startswith('soleil couchant ') else None
        if layer:
            rows = []
            for observation in observations:
                diagnostic = observation.get('diagnostic') or {}
                if diagnostic.get('schema') != 1 or diagnostic.get('errors'):
                    continue
                for row in diagnostic.get('regions', []):
                    if row.get('actor') != 0 or row.get('layer') != layer:
                        continue
                    match = re.fullmatch(r'(.+)-h(\d+)', row.get('view_hour', ''))
                    if not match or (match[1], int(match[2])) not in observation.get('eligible', observation['selected']):
                        continue
                    rows.append({'batch': observation['batch'], 'actor': 0, 'layer': layer,
                                 'view_hour': row['view_hour'],
                                 **sky_sequence_judgment(row, observation['temporal'])})
            if not rows:
                findings.append({'case': case, 'reason': 'no semantic ROI or comparable sequence in regional manifests'})
                continue
            views = {re.fullmatch(r'(.+)-h(\d+)', row['view_hour'])[1] for row in rows}
            cells = {(observation['batch'], f'{view}-h{hour:02}') for observation in observations
                     for view, hour in observation['selected'] if view in views}
            qualified = [row for row in rows if row.get('measured')
                         and (layer != 'sunset-sun' or row['view_hour'].endswith('-h18'))]
            if layer == 'sunset-sun':
                cells = {cell for cell in cells if cell[1].endswith('-h18')}
            judged_rows = [row for row in rows if layer != 'sunset-sun' or row['view_hour'].endswith('-h18')]
            complete = len(qualified) == len(judged_rows) and all(
                sum((row['batch'], row['view_hour']) == cell for row in qualified) == 1 for cell in cells)
            if any(row.get('status') == 'failed' or row.get('partial_photometry', {}).get('status') == 'failed'
                   for row in judged_rows):
                failed.append(case)
            # Textured sky bounds cannot establish that the expected clouds remain visible.
            if layer == 'sunset-sun' and any(row['view_hour'].endswith('-h18') for row in qualified) and complete:
                measured.append(case)
                if all(row['status'] == 'passed' for row in qualified):
                    passed.append(case)
            findings.append({'case': case, 'status': 'failed' if case in failed else 'passed' if case in passed else 'not_judged',
                             'observations': rows,
                             'reason': 'textured sky attribution remains partial' if layer == 'clouds' else
                                       'sun requires visible disc and both distinct rays in every sample'})
            continue
        if case.startswith('warp gate'):
            rows = []
            for observation in observations:
                diagnostic = observation.get('diagnostic') or {}
                if diagnostic.get('schema') != 1 or diagnostic.get('errors'):
                    continue
                for row in diagnostic.get('regions', []):
                    if row.get('actor') != 1395 or row.get('layer') != 'portal_disc':
                        continue
                    match = re.fullmatch(r'(.+)-h(\d+)', row.get('view_hour', ''))
                    if not match or (match[1], int(match[2])) not in observation.get('eligible', observation['selected']):
                        continue
                    judgment = owner_sequence_judgment(row, observation['temporal'], require_expected_white=False)
                    judgment['limitation'] = 'portal disc bounds include background; halos and local colour not qualified'
                    rows.append({'batch': observation['batch'], 'actor': 1395,
                                 'layer': 'portal_disc', 'view_hour': row['view_hour'], **judgment})
            if rows:
                if any(row.get('measured') and row['status'] == 'failed' for row in rows):
                    failed.append(case)
                findings.append({'case': case, 'status': 'failed' if case in failed else 'not_judged',
                                 'observations': rows,
                                 'reason': 'partial portal disc observation only; halos and local colour not qualified'})
            else:
                findings.append({'case': case, 'reason': 'no semantic ROI or comparable sequence in regional manifests'})
            continue
        if not case.startswith('eclairs des orbes eco bleue'):
            findings.append({'case': case, 'reason': 'no semantic ROI or comparable sequence in regional manifests'})
            continue
        rows, cells = [], set()
        eco_views = {'village1-eco-blue'}
        for observation in observations:
            for row in (observation.get('diagnostic') or {}).get('regions', []):
                match = re.fullmatch(r'(.+)-h(\d+)', row.get('view_hour', ''))
                if row.get('actor') in (10012, 10013) and match:
                    eco_views.add(match[1])
        for observation in observations:
            cells.update((observation['batch'], f'{view}-h{hour:02}')
                         for view, hour in observation['selected'] if view in eco_views)
            diagnostic = observation.get('diagnostic') or {}
            if diagnostic.get('schema') != 1 or diagnostic.get('errors'):
                continue
            for row in diagnostic.get('regions', []):
                if row.get('actor') not in (10012, 10013):
                    continue
                match = re.fullmatch(r'(.+)-h(\d+)', row.get('view_hour', ''))
                if not match or (match[1], int(match[2])) not in observation.get('eligible', observation['selected']):
                    continue
                rows.append({'batch': observation['batch'], 'actor': row['actor'],
                             'view_hour': row['view_hour'],
                             **owner_sequence_judgment(row, observation['temporal'])})
        qualified = [row for row in rows if row.get('measured')]
        complete = bool(cells) and len(qualified) == len(rows) and all(
            {row['actor'] for row in qualified
             if (row['batch'], row['view_hour']) == cell} == {10012, 10013}
            and sum((row['batch'], row['view_hour']) == cell for row in qualified) == 2
            for cell in cells)
        if complete:
            measured.append(case)
        if any(row['status'] == 'failed' for row in qualified):
            failed.append(case)
        if complete and all(row['status'] == 'passed' for row in qualified):
            passed.append(case)
        if rows:
            findings.append({'case': case, 'status': ('failed' if case in failed else 'passed' if case in passed else 'not_judged'),
                             'observations': rows, 'expected_cells': sorted(cells)})
        else:
            findings.append({'case': case, 'reason': 'no semantic ROI or comparable sequence in regional manifests'})
    missing = [case for case in owner_required if case not in measured]
    metrics = {'hdr_owner_regressions_required': len(owner_required),
               'hdr_owner_regressions_measured': len(measured),
               'hdr_owner_regressions_missing': len(missing),
               'hdr_owner_regressions_failed': len(failed),
               'hdr_owner_regressions_passed': len(passed),
               'hdr_defect_7_owner_regressions': int(len(passed) != len(owner_required))}
    return metrics, {'required': owner_required, 'measured': measured, 'missing': missing,
                     'failed': failed, 'passed': passed, 'findings': findings}


def check_owner_replacement(previous, key, current, new_key):
    """A replacement may repair collection, never erase a measured eco loss."""
    def sky_regions(batch, cell):
        return [r for r in (batch.get('owner_regions') or {}).get('regions', [])
                if r.get('actor') == 0 and r.get('layer') in ('clouds', 'sunset-sun')
                and r.get('view_hour') == f'{cell[0]}-h{cell[1]:02}']
    old_sky = sky_regions(previous, key)
    if old_sky:
        if previous['identity'] != current['identity']:
            raise ValueError('sky replacement binary/config incompatible')
        old_pair = previous['pairs'].get(key) or previous.get('unqualified', {}).get(key)
        if old_pair and old_pair.get('options') is not None and old_pair['options'] != current['pairs'][new_key]['options']:
            raise ValueError('sky replacement effective settings incompatible')
        diagnostic = current.get('owner_regions') or {}
        new_sky = sky_regions(current, new_key)
        for row in old_sky:
            judgment = sky_sequence_judgment(row, int(previous['values'].get('refset_temporal_samples', '1')))
            if (judgment.get('measured') and judgment['status'] == 'failed'
                    or judgment.get('partial_photometry', {}).get('status') == 'failed'):
                raise ValueError('replacement cannot erase measured sky defect')
            replacements = [r for r in new_sky if r['layer'] == row['layer']]
            if (diagnostic.get('schema') != 1 or diagnostic.get('errors') or len(replacements) != 1
                    or not sky_sequence_judgment(replacements[0], int(current['values'].get('refset_temporal_samples', '1'))).get('measured')):
                raise ValueError('replacement loses measurable sky layer')
    def regions(batch, cell):
        stem = f'{cell[0]}-h{cell[1]:02}'
        return [row for row in (batch.get('owner_regions') or {}).get('regions', [])
                if row.get('actor') in (10012, 10013) and row.get('view_hour') == stem]
    old_rows = regions(previous, key)
    if key[0] != 'village1-eco-blue' and not old_rows:
        return
    if (previous['identity'][0] != current['identity'][0]
            or (previous['identity'][1] is not None and previous['identity'][1] != current['identity'][1])):
        raise ValueError('eco replacement binary/config incompatible')
    old_pair = previous['pairs'].get(key) or previous.get('unqualified', {}).get(key)
    if old_pair and old_pair.get('options') is not None and old_pair['options'] != current['pairs'][new_key]['options']:
        raise ValueError('eco replacement effective settings incompatible')
    old_judgments = [owner_sequence_judgment(row, int(previous['values'].get('refset_temporal_samples', '1')))
                     for row in old_rows]
    if any(row.get('measured') and row['status'] == 'failed' for row in old_judgments):
        raise ValueError('replacement cannot erase measured eco defect')
    diagnostic = current.get('owner_regions') or {}
    new_rows = regions(current, new_key)
    if (diagnostic.get('schema') != 1 or diagnostic.get('errors')
            or len(new_rows) != 2 or {row['actor'] for row in new_rows} != {10012, 10013}
            or not all(owner_sequence_judgment(row, int(current['values'].get('refset_temporal_samples', '1'))).get('measured')
                       for row in new_rows)):
        raise ValueError('replacement loses measurable eco actors')


def aggregate(campaign, current, expected, measurer=measure):
    errors, batches = [], {}
    owner_metrics, owner_diagnostics = owner_regressions(expected)
    for directory in sorted(p for p in Path(campaign).iterdir() if p.is_dir()):
        path = directory / 'manifest.json'
        try:
            m = read_batch(path, expected, measurer)
            if m['id'] in batches or m['id'] != path.parent.name:
                raise ValueError('duplicate batch identity')
            batches[m['id']] = m
        except Exception as exc:
            errors.append(path.parent.name + ': ' + str(exc))
    if current not in batches:
        dump(Path(campaign) / 'measurements.json', {
            'errors': errors or ['current_batch_missing'], 'owner_regressions': owner_diagnostics})
        return {**owner_metrics, 'hdr_tonemap_defects': 1 + owner_metrics['hdr_defect_7_owner_regressions'],
                'hdr_batch_errors': max(1, len(errors)),
                'hdr_batch_error_detail': '|'.join(errors).replace(' ', '_') or 'current_batch_missing'}
    active = batches[current]
    for name, m in batches.items():
        if m['identity'][0] != active['identity'][0] or (m['identity'][1] is not None and m['identity'][1] != active['identity'][1]):
            errors.append(name + ': incompatible binary/APK/data/config')
    replaced = set()
    superseded_mappings = []
    # Newest valid replacements are resolved first. Superseding B's target
    # retires its A->B attempt, but deliberately does not mark A replaced.
    for name in sorted(batches, reverse=True):
        m = batches[name]
        for mapping in m['replacements']:
            try:
                old, target = mapping.split('=')
                old_batch, view, hour = old.split(':')
                key = (view, int(hour))
                new_key = (target, int(hour))
                if old_batch >= name or old_batch not in batches or key not in map(tuple, batches[old_batch]['requested']) or new_key not in map(tuple, m['requested']):
                    raise ValueError('replacement source/target absent')
                if expected['views'][view] != expected['views'][target]:
                    raise ValueError('replacement changes region')
                if (name, new_key) in replaced:
                    superseded_mappings.append({'batch': name, 'mapping': mapping})
                    continue
                if new_key not in m['pairs']:
                    raise ValueError('replacement target unqualified')
                if (old_batch, key) in replaced:
                    raise ValueError('replacement duplicates source')
                previous = batches[old_batch]
                old_pair = previous['pairs'].get(key)
                new_pair = m['pairs'][new_key]
                if view == 'legacy' and (target != 'legacy' or new_pair['sky_max_pm'] > 10):
                    raise ValueError('replacement loses hut interior')
                if old_pair and 150 <= old_pair['sky_pm'] <= old_pair['sky_max_pm'] <= 900 and not 150 <= new_pair['sky_pm'] <= new_pair['sky_max_pm'] <= 900:
                    raise ValueError('replacement loses covered sky region')
                if old_pair and not expected['sky'][expected['views'][view]] and new_pair['sky_max_pm'] > 10:
                    raise ValueError('replacement loses interior region')
                image_record = old_pair or previous.get('unqualified', {}).get(key, {})
                trustworthy_image = ('on' in image_record and 'off' in image_record
                                     and image_record.get('comparable', True)
                                     and not any('black or achromatic' in r or 'region not drawn' in r
                                                 for r in image_record.get('reasons', [])))
                if trustworthy_image:
                    for metric in QUALITY:
                        on, off = image_record['on'], image_record['off']
                        if on[metric] > off[metric] + max(off['pixels'] // 1000, off[metric] // 20):
                            raise ValueError('replacement cannot erase measured image defect')
                check_owner_replacement(previous, key, m, new_key)
                replaced.add((old_batch, key))
            except Exception as exc:
                errors.append('invalid replacement ' + mapping + ': ' + str(exc))
    pairs, seen, duplicates = [], set(), set()
    hdr_above_one = False
    chain_defects = dict.fromkeys(CHAIN, 0)
    chain_evidence = []
    for name, m in batches.items():
        remaining = set(map(tuple, m['requested'])) - {key for b, key in replaced if b == name}
        if m['crash'] not in (0, 1) or (m['crash'] and remaining):
            errors.append(name + ': unreplaced crash')
        observed, findings = chain_measurements(m['values'], required=bool(remaining))
        for key, defect in observed.items():
            chain_defects[key] |= defect
        chain_evidence.append({'batch': name, 'selected': bool(remaining), 'defects': observed,
                               'findings': findings})
        errors.extend(name + ': chain ' + detail for detail in findings)
        if remaining:
            hdr_above_one |= int(m['values'].get('hdr_overbright_px', '0')) > 0 and int(m['values'].get('hdr_probe_max_x1000', '0')) > 1000 and int(m['values'].get('hdr_probe_px', '0')) > 0
        for key in remaining:
            if key in seen:
                errors.append('duplicate view/hour: ' + str(key))
                duplicates.add(key)
            seen.add(key)
            if key not in m['pairs']:
                errors.append(name + ': unqualified/absent pair ' + str(key) + ': ' + '; '.join(m.get('unqualified', {}).get(key, {}).get('reasons', [])))
                continue
            pairs.append((name, key, m['pairs'][key]))
    if not hdr_above_one:
        errors.append('no compatible measured HDR > 1')
    coverage, sky, interior, hut = set(), set(), set(), set()
    quality_bad, diagnostics = [], []
    baseline_options = None
    for name, (view, hour), p in pairs:
        opts = p['options']
        # Different output profiles between arms are allowed; each arm must keep
        # its own effective rendering configuration across the campaign.
        if baseline_options is None:
            baseline_options = opts
        if opts != baseline_options:
            errors.append(name + ': effective rendering configuration incompatible')
        level = p['level']
        coverage.add((level, hour))
        if 150 <= p['sky_pm'] <= p['sky_max_pm'] <= 900:
            sky.add((level, hour))
        if p['sky_max_pm'] <= 10:
            interior.add((level, hour))
            if view in HUT_VIEWS:
                hut.add(hour)
        on, off = p['on'], p['off']
        excess = {k: on[k] - off[k] - max(off['pixels'] // 1000, off[k] // 20) for k in QUALITY}
        if any(x > 0 for x in excess.values()):
            quality_bad.append({'batch': name, 'view': view, 'hour': hour, 'excess': excess})
        diagnostics.append({'batch': name, 'view': view, 'hour': hour, 'level': level,
                            'on': on, 'off': off, 'sky_pm': p['sky_pm']})
    observations = []
    for name, m in batches.items():
        selected = set(map(tuple, m['requested'])) - {key for batch_name, key in replaced if batch_name == name}
        eligible = {key for batch_name, key, pair in pairs if batch_name == name
                    and pair['options'] == baseline_options and key not in duplicates}
        if m['identity'] == active['identity'] and selected:
            observations.append({'batch': name, 'diagnostic': m.get('owner_regions'),
                                 'selected': sorted(selected), 'eligible': sorted(eligible),
                                 'temporal': int(m['values'].get('refset_temporal_samples', '1'))})
    owner_metrics, owner_diagnostics = owner_regressions(expected, observations)
    owner_diagnostics['regional_observations'] = observations
    owner_diagnostics['unselected_regional_observations'] = [
        {'batch': name, 'diagnostic': m.get('owner_regions')} for name, m in batches.items()
        if name not in {row['batch'] for row in observations}]
    required = {(level, hour) for level in expected['sky'] for hour in expected['hours']}
    sky_required = {x for x in required if expected['sky'][x[0]]}
    interior_required = required - sky_required
    missing = sorted(required - coverage)
    sky_missing = sorted(sky_required - sky)
    interior_missing = sorted(interior_required - interior)
    hut_missing = sorted(set(expected['hours']) - hut)
    incomplete = bool(missing or sky_missing or interior_missing or hut_missing or errors)
    # Equal weight per (level, hour), with multiple views averaged within a cell.
    cells = {}
    for row in diagnostics:
        cell = cells.setdefault((row['level'], row['hour']), [])
        cell.append({k: row['on'][k] - row['off'][k] for k in ('luma', 'saturation', 'detail', 'flat')})
    means = {k: sum(sum(v[k] for v in rows) / len(rows) for rows in cells.values()) / len(cells)
             for k in ('luma', 'saturation', 'detail', 'flat')} if cells else {}
    dump(Path(campaign) / 'measurements.json', {'errors': errors, 'missing': missing, 'sky_missing': sky_missing,
         'owner_regressions': owner_diagnostics,
         'interior_missing': interior_missing, 'hut_missing': hut_missing, 'quality_bad': quality_bad,
         'balanced_deltas': means, 'pairs': diagnostics, 'chain_evidence': chain_evidence, 'superseded_mappings': superseded_mappings,
         'unqualified': [{'batch': name, 'view': view, 'hour': hour, **record}
                         for name, m in batches.items() for (view, hour), record in m.get('unqualified', {}).items()]})
    result = {'hdr_batch_errors': len(errors), 'hdr_batch_pairs': len(pairs), 'hdr_batch_cells': len(coverage),
              'hdr_batch_missing': len(missing) + len(sky_missing) + len(interior_missing) + len(hut_missing),
              'hdr_batch_quality_bad': len(quality_bad), 'hdr_batch_count': len(batches),
              'hdr_defect_1_saturation': int(bool(quality_bad) or incomplete),
              'hdr_defect_2_hl_contrast': int(incomplete),
              'hdr_defect_4_origine_lumiere_set': int(incomplete)}
    result.update(chain_defects)
    result.update(owner_metrics)
    result['hdr_tonemap_defects'] = sum(result[k] for k in (*CHAIN, 'hdr_defect_1_saturation',
                  'hdr_defect_2_hl_contrast', 'hdr_defect_4_origine_lumiere_set', 'hdr_defect_7_owner_regressions'))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'finish', 'aggregate'])
    parser.add_argument('--root', default='.')
    parser.add_argument('--batch', required=True)
    parser.add_argument('--adb')
    parser.add_argument('--serial')
    parser.add_argument('--pkg')
    parser.add_argument('--binary')
    parser.add_argument('--remote')
    parser.add_argument('--vantages', default='legacy')
    parser.add_argument('--hours', default='0,3,6,9,12,15,18,21')
    parser.add_argument('--replace', action='append', default=[])
    parser.add_argument('--crash', type=int, default=1)
    parser.add_argument('--started-at')
    parser.add_argument('--duration-s', type=int)
    args = parser.parse_args()
    try:
        if args.action == 'prepare':
            prepare(args)
        elif args.action == 'finish':
            finish(args)
        else:
            batch = Path(args.batch)
            for key, value in aggregate(batch.parent, batch.name, contract(Path(args.root))).items():
                print(f'{key}={value}')
    except Exception as exc:
        print('hdr_batches: ' + str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
