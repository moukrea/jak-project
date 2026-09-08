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


def measure(path):
    """Decode with ImageMagick; calculate masks and diagnostics from decoded pixels."""
    import numpy as np
    size = subprocess.check_output(['magick', 'identify', '-format', '%w %h', str(path)], text=True)
    w, h = map(int, size.split())
    if min(w, h) < 2 or w * h > 16000000:
        raise ValueError('invalid capture dimensions')
    rgb = np.frombuffer(subprocess.check_output(
        ['magick', str(path), '-alpha', 'off', '-depth', '8', 'rgb:-']), np.uint8).reshape(h, w, 3)
    hsv = np.frombuffer(subprocess.check_output(
        ['magick', str(path), '-alpha', 'off', '-colorspace', 'HSB', '-set', 'colorspace', 'RGB',
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


def aggregate(campaign, current, expected, measurer=measure):
    errors, batches = [], {}
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
        return {'hdr_tonemap_defects': 1, 'hdr_batch_errors': max(1, len(errors)),
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
                replaced.add((old_batch, key))
            except Exception as exc:
                errors.append('invalid replacement ' + mapping + ': ' + str(exc))
    pairs, seen = [], set()
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
            if view == 'legacy':
                hut.add(hour)
        on, off = p['on'], p['off']
        excess = {k: on[k] - off[k] - max(off['pixels'] // 1000, off[k] // 20) for k in QUALITY}
        if any(x > 0 for x in excess.values()):
            quality_bad.append({'batch': name, 'view': view, 'hour': hour, 'excess': excess})
        diagnostics.append({'batch': name, 'view': view, 'hour': hour, 'level': level,
                            'on': on, 'off': off, 'sky_pm': p['sky_pm']})
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
    result['hdr_tonemap_defects'] = sum(result[k] for k in (*CHAIN, 'hdr_defect_1_saturation',
                  'hdr_defect_2_hl_contrast', 'hdr_defect_4_origine_lumiere_set'))
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
