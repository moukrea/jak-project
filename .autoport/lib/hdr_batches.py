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
import os
import shutil
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
# Views whose capture is the interior of a Sandover Village hut. `legacy` is
# kVantages[0], the village1-hut resume point at (-116, 14, 40) m: the hut hall
# (wooden arch, lamp, barrels), verified by the supervisor on 2026-09-09. It is
# NOT the Green Sage's hut at (-123, 46, 214) m, which stays the separate owner
# "ground" case (HDR-OWNER-GROUND). `aggregate` still requires sky_max_pm <= 10.
HUT_VIEWS = frozenset({'legacy'})


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
    try:                              # lecteur C si disponible (voir lib/backlog.py)
        from yaml import CSafeLoader as _L
    except ImportError:
        from yaml import SafeLoader as _L
    doc = yaml.load((root / '.autoport/backlog.yaml').read_text(), Loader=_L)
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


def crop_command(path, rect=None):
    """ImageMagick source command for the whole capture or a validated crop."""
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
    return command, w, h


def decode(path, rect=None):
    """Decode a capture (or its crop) to an uint8 (h, w, 3) RGB array via ImageMagick."""
    import numpy as np
    command, w, h = crop_command(path, rect)
    return np.frombuffer(subprocess.check_output(
        command + ['-alpha', 'off', '-depth', '8', 'rgb:-']), np.uint8).reshape(h, w, 3)


def dilate(mask, radius):
    """Binary dilation by a disc of `radius` pixels, built from shifted copies (numpy only)."""
    import numpy as np
    out = np.zeros_like(mask)
    h, w = mask.shape
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            if dx * dx + dy * dy > radius * radius:
                continue
            ys, yd = slice(max(0, dy), min(h, h + dy)), slice(max(0, -dy), min(h, h - dy))
            xs, xd = slice(max(0, dx), min(w, w + dx)), slice(max(0, -dx), min(w, w - dx))
            out[yd, xd] |= mask[ys, xs]
    return out


def white_match(on_rgb, off_rgb, radius=3):
    """Spatially tolerant pairing of saturated whites (min channel == 255) between arms.

    `lost` = OFF whites with no ON white within `radius` px; `gained` = the
    reverse. Particle noise moves whites by a few pixels between arms without
    attenuating them (essai61/highlights-loss.md); only unmatched whites count.
    """
    if on_rgb.shape != off_rgb.shape or on_rgb.ndim != 3 or on_rgb.shape[2] != 3:
        raise ValueError('white match requires two RGB regions of identical shape')
    won, woff = on_rgb.min(2) == 255, off_rgb.min(2) == 255
    return {'on_white': int(won.sum()), 'off_white': int(woff.sum()),
            'lost': int((woff & ~dilate(won, radius)).sum()),
            'gained': int((won & ~dilate(woff, radius)).sum())}


def measure(path, rect=None):
    """Decode with ImageMagick; calculate masks and diagnostics from decoded pixels."""
    import numpy as np
    command, w, h = crop_command(path, rect)
    rgb = decode(path, rect)
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
        marker = next((m for m in ('HDR-OWNER-SPRITE ', 'HDR-OWNER-SKY ', 'HDR-OWNER-GROUND ') if m in line), None)
        if marker:
            try:
                witness = json.loads(line.split(marker, 1)[1])
                if not isinstance(witness, dict):
                    raise ValueError('witness is not an object')
                if type(witness.get('lf')) is not int or type(witness.get('actor')) is not int or witness.get('actor') not in (0, 10012, 10013, 1395):
                    raise ValueError('unknown actor or frame')
                if witness['actor'] == 0:
                    layer = witness.get('layer')
                    if witness.get('case') != layer or layer not in ('clouds', 'sunset-sun', 'sage-hut-ground'):
                        raise ValueError('invalid actor zero layer/case')
                    if layer == 'sage-hut-ground':
                        aabb = witness.get('world_aabb')
                        if (marker != 'HDR-OWNER-GROUND ' or not isinstance(aabb, list) or len(aabb) != 6
                                or any(type(v) not in (int, float) or not math.isfinite(v) for v in aabb)
                                or witness.get('supported') is not True or witness.get('passed') is not True):
                            raise ValueError('invalid sage-hut-ground provenance')
                    elif marker == 'HDR-OWNER-GROUND ':
                        raise ValueError('ground witness requires the sage-hut-ground layer')
                    elif layer == 'clouds':
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
                elif marker in ('HDR-OWNER-SKY ', 'HDR-OWNER-GROUND '):
                    raise ValueError('sky/ground witness requires actor zero')
                if marker == 'HDR-OWNER-GROUND ' and (witness.get('in_frame') is False or witness.get('roi') is None):
                    # The box is projected for every capture; out of frame (any other
                    # level, any other vantage) it is simply absent, not an error.
                    continue
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
        # Spatial white pairing: i-th ON sample against i-th OFF sample by frame order.
        # Unreadable images yield no entry (never an invented zero) and a row error.
        row['white_match'], row['errors'] = [], []
        ordered = {arm: sorted([s for s in row['samples'] if s['arm'] == arm], key=lambda s: s['frame'])
                   for arm in ('recharged', 'origine-lumiere')}
        for index in range(min(len(ordered['recharged']), len(ordered['origine-lumiere']))):
            on, off = ordered['recharged'][index], ordered['origine-lumiere'][index]
            try:
                match = white_match(decode(batch / on['image'], rect), decode(batch / off['image'], rect))
            except (ValueError, OSError, subprocess.CalledProcessError) as exc:
                row['errors'].append(f"white match unavailable for sample {index}: {on['image']} / {off['image']}: {exc}")
                row['white_match'] = []
                break
            row['white_match'].append({'sample': index, 'on': on['image'], 'off': off['image'], **match})
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


def source_snapshot(root):
    names = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z',
                                     'game', 'common', 'goal_src', 'data/shaders'], text=True)
    return {name: sha(root / name) for name in names.split('\0') if name
            and Path(name).suffix in ('.cpp', '.h', '.gc', '.gd', '.glsl', '.vert', '.frag', '.tesc', '.tese', '.geom', '.comp')}


def local_snapshot(args, suffix):
    batch = Path(args.batch)
    binary = Path(args.binary).resolve()
    pointer = Path(os.environ.get('XDG_CONFIG_HOME') or str(Path.home() / '.config')) / 'OpenGOAL/asset-root.txt'
    if pointer.exists():
        raise ValueError('external asset-root pointer unsupported for portable HDR snapshot: ' + str(pointer))
    config_root = binary.parent / 'OpenGOAL/jak1'
    required = ('misc/debug-settings.json', 'settings/display-settings.json',
                'settings/input-settings.json', 'settings/settings.ini')
    for name in required:
        if not (config_root / name).is_file():
            raise ValueError('missing portable configuration: ' + name)
    hashes = {}
    for path in sorted(config_root.rglob('*')):
        if path.is_file() and path.suffix in ('.json', '.ini'):
            name = str(path.relative_to(config_root))
            dest = batch / ('config-' + suffix) / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, dest)
            hashes[name] = sha(dest)
    settings = batch / ('settings-' + suffix + '.ini')
    shutil.copyfile(config_root / 'settings/settings.ini', settings)
    hashes['settings.ini'] = sha(settings)
    environment = {k: v for k, v in os.environ.items()
                   if k.startswith(('OG_', 'AUTOPORT_FEATURE', 'SDL_', 'MESA_', 'LIBGL_', '__GL_'))}
    dump(batch / ('env-' + suffix + '.json'), environment)
    sources = source_snapshot(Path(args.root))
    if not sources:
        raise ValueError('missing rendering sources')
    dump(batch / ('sources-' + suffix + '.json'), sources)
    return {'source': 'x86', 'binary_sha256': sha(binary),
            'config_files': hashes, 'sources': sources}


def snapshot(args, suffix):
    if getattr(args, 'source', 'device') == 'x86':
        return local_snapshot(args, suffix)
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
    if getattr(args, 'source', 'device') == 'device' and (not args.serial or ':' in args.serial):
        raise ValueError('HDR campaign requires the USB serial selected by proof_run')
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
        if getattr(args, 'source', 'device') == 'x86':
            remote = Path(args.remote)
            if not remote.is_dir() or remote.is_symlink() or any(p.is_symlink() for p in remote.rglob('*')):
                raise ValueError('missing or unsafe local captures')
            shutil.copytree(remote, batch / 'captures')
        else:
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
    source = m['provenance'].get('source', 'device')
    if source not in ('device', 'x86'):
        raise ValueError('unknown execution source')
    snapshot_names = (('env-start.json', 'env-end.json', 'sources-start.json', 'sources-end.json')
                      if source == 'x86' else ('props-start.txt', 'props-end.txt'))
    for snapshot_name in snapshot_names:
        if snapshot_name not in files:
            raise ValueError('missing sealed rendering property snapshot')
    if source == 'x86':
        envs = [json.loads((base / ('env-' + suffix + '.json')).read_text()) for suffix in ('start', 'end')]
        if any(not isinstance(e, dict) or e.get('OG_REFSET') != 'capture' for e in envs):
            raise ValueError('missing x86 capture environment')
        if envs[0] != envs[1]:
            raise ValueError('x86 environment changed during batch')
        def rendering_env(e):
            return {k: v for k, v in e.items() if not k.startswith(('OG_REFSET', 'OG_LEVEL_WARP', 'AUTOPORT_FEATURE'))
                    and k not in ('OG_WANT_LEVELS', 'OG_WANT_DISPLAY', 'OG_PADREPLAY')}
        props_start, props_end = map(rendering_env, envs)
        sources = [json.loads((base / ('sources-' + suffix + '.json')).read_text()) for suffix in ('start', 'end')]
        if (not isinstance(sources[0], dict) or not sources[0]
                or any(not isinstance(v, str) or not re.fullmatch('[0-9a-f]{64}', v) for v in sources[0].values())
                or sources[0] != sources[1] or sources[0] != m['provenance'].get('sources')):
            raise ValueError('rendering sources changed or absent')
    else:
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
    if source == 'x86':
        if any(k in provenance for k in ('installed_sha256', 'apk_sha256', 'serial')) or not re.fullmatch('[0-9a-f]{64}', provenance.get('binary_sha256', '')):
            raise ValueError('incomplete or false x86 binary provenance')
    elif provenance['binary_sha256'] != provenance['installed_sha256'] or any(
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
    requested_temporal = ([envs[0]['OG_REFSET_TEMPORAL_SAMPLES']]
                          if source == 'x86' and 'OG_REFSET_TEMPORAL_SAMPLES' in envs[0] else []
                          if source == 'x86' else re.findall(
                              r'^\[debug\.opengoal\.refset\.temporal\]: \[([^\]]*)\]$',
                              (base / 'props-start.txt').read_text(), re.M))
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
        particle_step_modes = set()
        for view, hour in requested:
            stem = ('' if view == 'legacy' else view + '-') + f'h{hour:02}'
            for arm in ('recharged', 'origine-lumiere'):
                frames = []
                spacing = None
                base_options = None
                sequence_repin = None
                sequence_steps = None
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
                    # dead-literals-round-3 (2026-09-13) : LA CADENCE DE LA PARTICULE, MESUREE.
                    # Ce bloc comparait `particle_step_const` a la chaine 'once-per-logic-frame'
                    # que `refset.cpp` y ecrit lui-meme : la condition ne pouvait pas etre vraie,
                    # et le protocole qu'elle pretendait garantir — un pas et un seul par frame de
                    # logique — n'etait verifie par personne. `particle_steps` est le compteur de
                    # pas du moteur, brut. Entre deux photos separees de `spacing_lf` frames de
                    # logique il doit avancer d'EXACTEMENT `spacing_lf` : un feu qui gele (delta
                    # nul) ou qui avance au rythme des images DESSINEES (delta > spacing) rougit
                    # ici. La difference annule tout decalage d'un pas a l'ancre.
                    # POURQUOI L'ABSENCE EST TOLEREE, ET CE QUI L'EMPECHE DE L'ETRE EN SILENCE :
                    # 4455 captures temporelles deja scellees par `refset_qualification.h` ont ete
                    # prises par un binaire qui ne publiait pas ce compteur ; les rejeter serait
                    # detruire la donnee de `lighting-hdr`. La tolerance est donc sur le LOT, pas
                    # sur la capture : un lot melangeant les deux niveaux est FATAL, si bien qu'un
                    # lot neuf ne peut pas retomber capture par capture au niveau d'avant.
                    steps = options.get('particle_steps')
                    particle_step_modes.add(steps is not None)
                    if len(particle_step_modes) != 1:
                        raise ValueError('mixed temporal particle step metadata')
                    if steps is not None:
                        if type(steps) is not int or steps < 0:
                            raise ValueError('invalid temporal particle step count: ' + case)
                        if sequence_steps is not None and steps - sequence_steps != spacing:
                            raise ValueError('temporal particle step cadence: ' + case)
                        sequence_steps = steps
                    # Sample, age and step count vary by the validated cadence within a sequence;
                    # preserve every unknown temporal setting in its invariant.
                    temporal_invariant = {k: v for k, v in options.items()
                                          if k not in ('sample', 'particle_age', 'particle_repin_lf',
                                                       'particle_steps')}
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
                if not isinstance(options.get('output'), dict) or not {'profile_const', 'curve', 'exposure', 'pbr_exposure', 'knee'} <= options['output'].keys():
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
            # A global flash (Rock Village lightning: +33/255 on every pixel of one
            # sample, x1.3 on the next) is not a rendering configuration: an arm whose
            # temporal samples disagree on the whole-frame luma is not stationary and
            # its pair is unqualified, to be re-captured, never judged.
            if temporal > 1:
                last = [prefix + case + f'-t{temporal - 1:02}.png' for prefix in ('captures/', 'captures/supplement-v1/')]
                last = [x for x in last if x in files]
                if len(last) == 1:
                    cache_last = cached_pixels.get('images', {}).get(last[0])
                    if measurer is measure and cached_pixels.get('helper_sha256') == sha(__file__) and cache_last and cache_last.get('sha256') == files[last[0]]:
                        stats_last = cache_last['stats']
                    else:
                        stats_last = measurer(base / last[0])
                    if abs(stats_last['luma'] - stats['luma']) > max(10.0, .15 * max(stats['luma'], stats_last['luma'])):
                        reasons.append('non-stationary arm (whole-frame luma changed between temporal samples): ' + case)
            # The purge timestamp and the raw step counter are execution evidence, not
            # rendering options: both are anchored on how many logic frames ran BEFORE the
            # capture plan, which differs from one process to the next. Their source remains
            # sealed; normalize only these copied comparison values after the full temporal
            # sequence metadata — cadence included — has been checked above.
            dates = {'particle_repin_lf', 'particle_steps'}
            if temporal > 1 and options is not None and dates & options.get('temporal', {}).keys():
                options = {**options, 'temporal': {k: v for k, v in options['temporal'].items()
                                                 if k not in dates}}
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


# Owner cases: (case name prefix, judged layer, actors per cell, restricted hour).
OWNER_CASES = (('nuages ', 'clouds', (0,), None),
               ('eclairs des orbes eco bleue', 'eco', (10012, 10013), None),
               ('soleil couchant ', 'sunset-sun', (0,), 18),
               ('petites zones au sol', 'sage-hut-ground', (0,), None),
               ('warp gate', 'portal_disc', (1395,), None))
SETTLED = ('passed', 'failed', 'not_applicable')
LAYER_LIMITATIONS = {
    'clouds': 'textured sky bounds mix cloud and background; cloud visibility not qualified',
    'sunset-sun': 'sun bounds include background; photometric preservation only',
    'portal_disc': 'portal disc bounds include background; halos and local colour not qualified',
    'sage-hut-ground': 'ground bounds include background; local colour attribution not qualified',
    'eco': 'projected bounds include background; local colour and non-lightning3 sprites not attributed'}
# Quantisation floors added to the OFF envelope: 1 % of 255 for luma, 1 % of
# the ROI for pixel counts, half a percent for fractions (essai61 spec, section 3).
LUMA_FLOOR, FRACTION_FLOOR = 2.55, .005


def envelope(off_values, floor):
    """OFF dispersion widened by itself and a quantisation floor: (lo, hi)."""
    spread = max(off_values) - min(off_values)
    return min(off_values) - spread - floor, max(off_values) + spread + floor


def owner_case_judgment(row, temporal, layer):
    """Single judge of one regional row against its OFF temporal envelope.

    Rules derive from the observed OFF dispersion (essai61/highlights-loss.md):
    whites are paired spatially (particle noise moves them without attenuating
    them), photometric keys are bounded by the OFF envelope plus a quantisation
    floor, and `detail` is published as a diagnostic bound only. Rows without a
    `white_match` record (older lots, unreadable images) are never judged.
    """
    if layer not in LAYER_LIMITATIONS:
        raise ValueError('unknown owner layer: ' + str(layer))
    limitation = LAYER_LIMITATIONS[layer]

    def unjudged(reason, bounds=None, totals=None, failures=(), status='not_judged'):
        return {'status': status, 'measured': False, 'reason': reason, 'bounds': bounds or {},
                'failures': list(failures), 'white_match_totals': totals or {}, 'limitation': limitation}
    samples = row.get('samples', [])
    arms = {arm: [s for s in samples if s.get('arm') == arm] for arm in ('recharged', 'origine-lumiere')}
    rect = row.get('roi_exclusive', [])
    if (temporal < 2 or len(rect) != 4 or any(type(x) is not int for x in rect)
            or not 0 <= rect[0] < rect[2] <= 320 or not 0 <= rect[1] < rect[3] <= 180):
        return unjudged('no comparable temporal projected ROI')
    if (len(samples) != 2 * temporal or any(len(v) != temporal for v in arms.values())
            or len({s.get('image') for s in samples}) != len(samples)
            or any(s.get('visible_sprites', 0) <= 0 for s in samples)):
        return unjudged('incomplete, duplicate or invisible temporal samples')
    if layer == 'sunset-sun' and any(s.get('sun_components_complete') is not True for s in samples):
        return unjudged('incomplete visible sun disc and two distinct rays')
    pixels = (rect[2] - rect[0]) * (rect[3] - rect[1])
    keys = ('white', 'nearwhite', 'clipped', 'luma', 'luma_p99', 'detail', 'flat', 'saturation', 'violet_fraction')
    values = {arm: {key: [] for key in keys} for arm in arms}
    for arm, sequence in arms.items():
        for sample in sequence:
            stats = sample.get('stats')
            if not isinstance(stats, dict):
                return unjudged('invalid regional measurement: stats')
            hues = stats.get('hue_bins')
            if (type(stats.get('pixels')) is not int or stats['pixels'] != pixels
                    or not isinstance(hues, list) or len(hues) != 12
                    or any(type(v) is not int or v < 0 for v in hues) or sum(hues) > pixels):
                return unjudged('invalid regional measurement: hue_bins')
            for key, ceiling in (('white', pixels), ('nearwhite', pixels), ('clipped', pixels), ('luma', 255),
                                 ('luma_p99', 255), ('detail', None), ('flat', 1), ('saturation', 1)):
                v = stats.get(key)
                if (type(v) not in (int, float) or not math.isfinite(v) or v < 0
                        or (ceiling is not None and v > ceiling)):
                    return unjudged('invalid regional measurement: ' + key)
                values[arm][key].append(v)
            # HSB bins span 30 degrees: 270..330 covers violet/magenta, not blue.
            values[arm]['violet_fraction'].append((hues[9] + hues[10]) / pixels)
    if layer == 'sunset-sun' and min(values['origine-lumiere']['luma_p99']) <= 2:
        return unjudged('expected OFF sun brightness not observed')
    count_floor = max(2, pixels // 100)
    floors = {'white': count_floor, 'nearwhite': count_floor, 'clipped': count_floor,
              'luma': LUMA_FLOOR, 'luma_p99': LUMA_FLOOR, 'detail': 0,
              'flat': FRACTION_FLOOR, 'saturation': FRACTION_FLOOR, 'violet_fraction': FRACTION_FLOOR}
    bounds, failures = {}, []
    for key in keys:
        on, off = values['recharged'][key], values['origine-lumiere'][key]
        lo, hi = envelope(off, floors[key])
        mean = sum(on) / len(on)
        bounds[key] = {'off_min': min(off), 'off_max': max(off), 'off_mean': sum(off) / len(off),
                       'on_mean': mean, 'floor': floors[key], 'lo': lo, 'hi': hi}
        if key in ('clipped', 'nearwhite', 'flat', 'violet_fraction', 'saturation') and mean > hi:
            failures.append(key + ': ON excess beyond OFF envelope')
        if (key == 'luma' or (key == 'luma_p99' and layer == 'sunset-sun')) and mean < lo:
            failures.append(key + ': ON loss beyond OFF envelope')
    matches = row.get('white_match')
    if not isinstance(matches, list) or not matches:
        return unjudged('white match not available', bounds)
    images = {arm: {s.get('image') for s in sequence} for arm, sequence in arms.items()}
    totals = {'pairs': len(matches), 'on_white': 0, 'off_white': 0, 'lost': 0, 'gained': 0}
    for index, match in enumerate(matches):
        if (not isinstance(match, dict) or match.get('sample') != index
                or match.get('on') not in images['recharged'] or match.get('off') not in images['origine-lumiere']
                or any(type(match.get(k)) is not int or match[k] < 0 for k in ('on_white', 'off_white', 'lost', 'gained'))):
            return unjudged('invalid white match record', bounds)
        for k in ('on_white', 'off_white', 'lost', 'gained'):
            totals[k] += match[k]
    if (len(matches) != temporal or len({m['on'] for m in matches}) != temporal
            or len({m['off'] for m in matches}) != temporal):
        return unjudged('white match does not cover every temporal pair', bounds, totals)
    if totals['off_white'] > 0 and totals['lost'] > totals['gained'] + 2 * math.sqrt(totals['lost'] + totals['gained'] + 1):
        failures.append('white: expected whites suppressed')
    white = bounds['white']
    if white['off_mean'] > 0 and white['on_mean'] <= 0:
        failures.append('white: expected whites suppressed entirely ON')
    if white['off_mean'] <= 0 and layer == 'eco':
        return unjudged('expected OFF whites not observed', bounds, totals, failures)
    if failures:
        status = 'failed'
    elif white['off_mean'] <= 0 and layer == 'clouds':
        return unjudged('expected OFF whites not observed', bounds, totals, status='not_applicable')
    else:
        status = 'passed'
    return {'status': status, 'measured': True, 'bounds': bounds, 'failures': failures,
            'white_match_totals': totals, 'limitation': limitation}


def owner_regressions(expected, observations=()):
    """Completeness per owner case: every selected cell of a case's views carries
    exactly one settled row per actor (passed/failed/not_applicable) and at
    least one row is passed or failed. `missing` = not measured."""
    owner_required = list(expected['plan'].get('owner_regression_cases', []))
    measured, failed, passed, findings = [], [], [], []
    absent = 'no semantic ROI or comparable sequence in regional manifests'
    for case in owner_required:
        spec = next((s for s in OWNER_CASES if case.startswith(s[0])), None)
        if spec is None:
            findings.append({'case': case, 'reason': absent})
            continue
        _, layer, actors, hour_only = spec
        rows, views = [], {'village1-eco-blue'} if layer == 'eco' else set()
        for observation in observations:
            diagnostic = observation.get('diagnostic') or {}
            valid = diagnostic.get('schema') == 1 and not diagnostic.get('errors')
            for row in diagnostic.get('regions', []):
                if row.get('actor') not in actors or (layer != 'eco' and row.get('layer') != layer):
                    continue
                match = re.fullmatch(r'(.+)-h(\d+)', row.get('view_hour', ''))
                if not match:
                    continue
                views.add(match[1])
                if not valid or (match[1], int(match[2])) not in observation.get('eligible', observation['selected']):
                    continue
                rows.append({'batch': observation['batch'], 'actor': row['actor'], 'layer': layer,
                             'view_hour': row['view_hour'],
                             **owner_case_judgment(row, observation['temporal'], layer)})
        if not rows:
            findings.append({'case': case, 'reason': absent})
            continue
        cells = {(observation['batch'], f'{view}-h{hour:02}') for observation in observations
                 for view, hour in observation['selected']
                 if view in views and (hour_only is None or hour == hour_only)}
        judged = [row for row in rows if hour_only is None or row['view_hour'].endswith(f'-h{hour_only:02}')]
        settled = [row for row in judged if row['status'] in SETTLED]
        complete = bool(cells) and len(settled) == len(judged) and all(
            sorted(row['actor'] for row in settled if (row['batch'], row['view_hour']) == cell) == sorted(actors)
            for cell in cells) and any(row['status'] in ('passed', 'failed') for row in settled)
        if any(row['status'] == 'failed' for row in judged):
            failed.append(case)
        if complete:
            measured.append(case)
            if case not in failed:
                passed.append(case)
        status = 'failed' if case in failed else 'passed' if case in passed else 'not_judged'
        finding = {'case': case, 'status': status, 'observations': rows, 'expected_cells': sorted(cells)}
        if status == 'not_judged':
            finding['reason'] = ('no selected cell for the case views' if not cells else
                                 'every selected cell needs one settled row per actor and one passed/failed row')
        findings.append(finding)
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
    """A replacement may repair collection, never erase a measured owner defect."""
    def sky_regions(batch, cell):
        return [r for r in (batch.get('owner_regions') or {}).get('regions', [])
                if r.get('actor') == 0 and r.get('layer') in ('clouds', 'sunset-sun', 'sage-hut-ground')
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
            judgment = owner_case_judgment(row, int(previous['values'].get('refset_temporal_samples', '1')), row['layer'])
            if judgment['measured'] and judgment['status'] == 'failed':
                raise ValueError('replacement cannot erase measured sky defect')
            replacements = [r for r in new_sky if r['layer'] == row['layer']]
            if (diagnostic.get('schema') != 1 or diagnostic.get('errors') or len(replacements) != 1
                    or owner_case_judgment(replacements[0], int(current['values'].get('refset_temporal_samples', '1')),
                                           row['layer'])['status'] not in SETTLED):
                raise ValueError('replacement loses measurable sky layer')
    def portal_regions(batch, cell):
        return [r for r in (batch.get('owner_regions') or {}).get('regions', [])
                if r.get('actor') == 1395 and r.get('layer') == 'portal_disc'
                and r.get('view_hour') == f'{cell[0]}-h{cell[1]:02}']
    old_portal = portal_regions(previous, key)
    if old_portal:
        if previous['identity'] != current['identity']:
            raise ValueError('portal replacement binary/config incompatible')
        old_pair = previous['pairs'].get(key) or previous.get('unqualified', {}).get(key)
        if old_pair and old_pair.get('options') is not None and old_pair['options'] != current['pairs'][new_key]['options']:
            raise ValueError('portal replacement effective settings incompatible')
        for row in old_portal:
            judgment = owner_case_judgment(row, int(previous['values'].get('refset_temporal_samples', '1')), 'portal_disc')
            if judgment['measured'] and judgment['status'] == 'failed':
                raise ValueError('replacement cannot erase measured portal defect')
        diagnostic = current.get('owner_regions') or {}
        new_portal = portal_regions(current, new_key)
        if (diagnostic.get('schema') != 1 or diagnostic.get('errors') or len(new_portal) != 1
                or owner_case_judgment(new_portal[0], int(current['values'].get('refset_temporal_samples', '1')),
                                       'portal_disc')['status'] not in SETTLED):
            raise ValueError('replacement loses measurable portal region')
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
    old_judgments = [owner_case_judgment(row, int(previous['values'].get('refset_temporal_samples', '1')), 'eco')
                     for row in old_rows]
    if any(row['measured'] and row['status'] == 'failed' for row in old_judgments):
        raise ValueError('replacement cannot erase measured eco defect')
    diagnostic = current.get('owner_regions') or {}
    new_rows = regions(current, new_key)
    if (diagnostic.get('schema') != 1 or diagnostic.get('errors')
            or len(new_rows) != 2 or {row['actor'] for row in new_rows} != {10012, 10013}
            or not all(owner_case_judgment(row, int(current['values'].get('refset_temporal_samples', '1')), 'eco')['status'] in SETTLED
                       for row in new_rows)):
        raise ValueError('replacement loses measurable eco actors')


def rendering_options(options):
    """Effective rendering configuration of a pair, without its capture protocol.

    The `temporal` block (samples, spacing, particle age) is the lot's capture
    protocol: proof_plan prescribes different protocols per owner case (portal
    animated >= 10 s after each reset, eco short sequence) and each batch is
    checked against its own protocol in read_batch and judged with its own
    `temporal` in owner_regressions. It is not a rendering setting, so it does
    not decide compatibility between lots of one campaign.
    """
    def one(o):
        if not isinstance(o, dict):
            return o
        out = {k: v for k, v in o.items() if k != 'temporal'}
        if 'temporal' in o:
            # The protocol's SCHEMA still has to agree: an old lot without the
            # particle metadata, or an unknown temporal field, is not comparable.
            block = o['temporal']
            out['temporal_schema'] = sorted(block) if isinstance(block, dict) else block
        return out
    if isinstance(options, list):
        return [one(o) for o in options]
    return one(options)


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
    # A platform mismatch is an error above, and never contributes coverage.
    source = active['provenance'].get('source', 'device')
    batches = {name: m for name, m in batches.items()
               if m['provenance'].get('source', 'device') == source}
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
        opts = rendering_options(p['options'])
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
                    and rendering_options(pair['options']) == baseline_options and key not in duplicates}
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
    parser.add_argument('--source', choices=['x86', 'device'], default='device')
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
