#!/usr/bin/env python3
"""DIRECTIVES v775512c234. Additional LOCAL diagnostic, never a proof/verdict.

Read fixed contact geometry and full replay images. Historical reader results are
copied from summary.json; this script never reimplements its prefix width.
"""
import argparse
import hashlib
import importlib.util
import json
import pathlib
import sys

import numpy as np

sys.dont_write_bytecode = True
NOTES = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('contact_qualification', NOTES / 'attempt10-profile.py')
qualification = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qualification)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def usable(z):
    return np.isfinite(z) & (z > 1e-9) & (z <= 1)


def full_signal(values):
    """Separate bounded-reference, whole-window and later-descent diagnostics."""
    result = dict(state='missing', interior_minimum=None, interior_minimum_index=None,
                  bright_indices=None, bright_count=None, max_excess=None,
                  whole_window_bright_indices=None, whole_window_bright_count=None,
                  later_drop_indices=None, later_drop_count=None,
                  later_drop_samples=None, secondary_peaks_and_plateaus=None)
    if len(values) < 2:
        return result
    ref = min(range(1, len(values)), key=values.__getitem__)
    result.update(interior_minimum=values[ref], interior_minimum_index=ref)
    if all(v == values[0] for v in values):
        result['state'] = 'censored'
        return result
    indices = [i for i in range(ref) if values[i] > values[ref] + 4]
    result.update(state='measurable', bright_indices=indices, bright_count=len(indices),
                  max_excess=max([values[i] - values[ref] for i in indices], default=0))
    whole = [i for i, value in enumerate(values) if value > values[ref] + 4]
    drops = []
    for i in range(len(values) - 1):
        following = min(range(i + 1, len(values)), key=values.__getitem__)
        if values[i] > values[following] + 4:
            drops.append(dict(index=i, following_minimum_index=following,
                              following_minimum=values[following], drop=values[i] - values[following]))
    # Equal-valued runs are local peaks only when preceded by a lower sample
    # and followed by a lower sample. Report every plateau index, not just its start.
    peaks = []
    start = 0
    while start < len(values):
        end = start
        while end + 1 < len(values) and values[end + 1] == values[start]:
            end += 1
        if (start > 0 and end + 1 < len(values) and values[start - 1] < values[start]
                and values[end + 1] < values[start]):
            following = min(range(end + 1, len(values)), key=values.__getitem__)
            if values[start] > values[following] + 4:
                peaks.append(dict(indices=list(range(start, end + 1)), ao=values[start],
                                  following_minimum_index=following, following_minimum=values[following],
                                  drop=values[start] - values[following]))
        start = end + 1
    result.update(whole_window_bright_indices=whole, whole_window_bright_count=len(whole),
                  later_drop_indices=[sample['index'] for sample in drops], later_drop_count=len(drops),
                  later_drop_samples=drops, secondary_peaks_and_plateaus=peaks)
    return result


def self_test():
    values = [133, 138, 135, 133, 131, 130]
    result = full_signal(values)
    assert result['bright_indices'] == [1, 2], result
    assert full_signal([130])['bright_count'] is None
    assert full_signal([130, 130])['bright_indices'] is None
    assert full_signal([129, 130, 131])['bright_count'] == 0
    plateau_values = [130, 130, 138, 138, 130]
    plateau = full_signal(plateau_values)
    assert plateau['bright_indices'] == []
    assert plateau['whole_window_bright_indices'] == [2, 3]
    assert plateau['later_drop_indices'] == [2, 3]
    assert plateau['secondary_peaks_and_plateaus'][0]['indices'] == [2, 3]
    rising = full_signal([130, 130, 138, 139])
    assert rising['whole_window_bright_indices'] == [2, 3] and rising['later_drop_indices'] == []
    return dict(values=values, result=result, plateau_values=plateau_values,
                plateau_result=plateau, assertions_passed=9)


def load_mode(directory):
    meta = dict(line.split('=', 1) for line in (directory / 'manifest.txt').read_text().splitlines()
                if line.count('=') == 1)
    shape = (int(meta['depth_height']), int(meta['depth_width']))
    if meta.get('status') != 'complete':
        raise ValueError('incomplete replay manifest')
    profile = json.loads((directory / 'contact-profiles.json').read_text())
    ao = np.fromfile(directory / 'ridge-3.r8', dtype='u1').reshape(shape)
    depth = np.fromfile(directory / 'scene-depth.f32', dtype='<f4').reshape(shape)
    return profile, ao, depth


def population(profile):
    return {(p['x'], p['y']): p['patch'] for p in profile['pixel_distances']}


def contacts(profile):
    pixels = population(profile)
    if len(pixels) != len(profile['pixel_distances']) or len(pixels) != 425:
        raise ValueError('fixed population must contain exactly 425 unique pixels')
    a, b = np.array(profile['projected_segment_px'])
    edges = []
    for (x, y), patch in sorted(pixels.items(), key=lambda p: (p[0][1], p[0][0])):
        for dx, dy in ((1, 0), (0, 1)):
            other = pixels.get((x + dx, y + dy))
            if other is not None and other != patch and qualification.crosses_segment(
                    np.array([x + .5, y + .5]), np.array([x + dx + .5, y + dy + .5]), a, b):
                edges.append((x, y, dx, dy))
    counts = {i: list(pixels.values()).count(i) for i in (1, 2)}
    if len(edges) != 15 or counts != {1: 250, 2: 175}:
        raise ValueError('fixed population must retain 15 contacts, 250 wall / 175 roof pixels')
    return pixels, edges


def profiles(profile, ao, depth):
    pixels, edges = contacts(profile)
    h, w = ao.shape
    output = []
    for x, y, dx, dy in edges:
        sides = []
        endpoints_usable = bool(usable(depth[y, x]) and usable(depth[y + dy, x + dx]))
        for sx, sy, vx, vy in ((x, y, -dx, -dy), (x + dx, y + dy, dx, dy)):
            samples = []
            stop = 'maximum_9_samples'
            for index in range(9):
                px, py = sx + vx * index, sy + vy * index
                if not (0 <= px < w and 0 <= py < h):
                    stop = 'image_boundary'
                    break
                if pixels.get((px, py)) != pixels[sx, sy]:
                    stop = 'changed_or_unknown_patch_identity'
                    break
                if not usable(depth[py, px]):
                    stop = 'sky_or_unusable_depth'
                    break
                samples.append(dict(index=index, x=px, y=py, ao=int(ao[py, px]),
                                    depth=float(depth[py, px])))
            signal = full_signal([s['ao'] for s in samples]) if endpoints_usable else full_signal([])
            sides.append(dict(start=[sx, sy], direction=[vx, vy], patch=pixels[sx, sy],
                              samples=samples, stop_reason=stop,
                              both_contact_endpoints_usable=endpoints_usable, additional_signal=signal))
        output.append(dict(edge=[[x, y], [x + dx, y + dy]], sides=sides))
    signals = [s['additional_signal'] for e in output for s in e['sides']]
    return dict(contacts=output, summary=dict(
        contacts=len(output), sides=len(signals),
        states={state: sum(s['state'] == state for s in signals)
                for state in ('missing', 'censored', 'measurable')},
        bright_sides=sum(bool(s['bright_count']) for s in signals),
        bright_samples_on_measurable_sides=sum(s['bright_count'] for s in signals if s['bright_count'] is not None),
        whole_window_bright_sides=sum(bool(s['whole_window_bright_count']) for s in signals),
        whole_window_bright_samples_on_measurable_sides=sum(
            s['whole_window_bright_count'] for s in signals if s['whole_window_bright_count'] is not None),
        later_drop_sides=sum(bool(s['later_drop_count']) for s in signals),
        later_drop_samples_on_measurable_sides=sum(
            s['later_drop_count'] for s in signals if s['later_drop_count'] is not None),
        secondary_peak_or_plateau_sides=sum(bool(s['secondary_peaks_and_plateaus']) for s in signals),
        secondary_peak_or_plateau_groups=sum(len(s['secondary_peaks_and_plateaus'])
            for s in signals if s['secondary_peaks_and_plateaus'] is not None),
        unknown_sides=sum(s['bright_count'] is None for s in signals)))


GEOMETRY = {0: 'other_or_insufficient_depth', 1: 'sky', 2: 'planar_depth_axes',
            3: 'concave_depth_proxy', 4: 'convex_depth_proxy'}


def geometry(depth):
    """Local reverse-Z depth shape, not semantic or world-space surface identity."""
    labels = np.zeros(depth.shape, dtype='u1')
    labels[np.isfinite(depth) & (depth <= 1e-9)] = 1
    z = depth.astype(np.float64)
    valid = usable(z)
    middle = z[1:-1, 1:-1]
    ddx = z[1:-1, :-2] + z[1:-1, 2:] - 2 * middle
    ddy = z[:-2, 1:-1] + z[2:, 1:-1] - 2 * middle
    support = (valid[1:-1, 1:-1] & valid[1:-1, :-2] & valid[1:-1, 2:]
               & valid[:-2, 1:-1] & valid[2:, 1:-1])
    local = labels[1:-1, 1:-1]
    tolerance = 1e-5
    local[support & (np.abs(ddx) <= tolerance) & (np.abs(ddy) <= tolerance)] = 2
    local[support & (ddx >= -tolerance) & (ddy >= -tolerance)
          & ((ddx > tolerance) | (ddy > tolerance))] = 3
    local[support & (ddx <= tolerance) & (ddy <= tolerance)
          & ((ddx < -tolerance) | (ddy < -tolerance))] = 4
    return labels


def distribution(values):
    if not values.size:
        return dict(count=0, minimum=None, maximum=None, quantiles=None)
    qs = (0, .01, .05, .25, .5, .75, .95, .99, 1)
    return dict(count=int(values.size), minimum=int(values.min()), maximum=int(values.max()),
                quantiles={str(q): float(v) for q, v in zip(qs, np.quantile(values, qs))})


def delta_stats(delta, selection):
    values = delta[selection]
    darker, lighter = values[values < 0], values[values > 0]
    return dict(population=int(values.size), changed=int(np.count_nonzero(values)),
                darker=int(darker.size), lighter=int(lighter.size),
                max_darkening=int(-darker.min()) if darker.size else 0,
                max_brightening=int(lighter.max()) if lighter.size else 0,
                signed_delta=distribution(values), changed_signed_delta=distribution(values[values != 0]),
                darkening_magnitude=distribution(-darker), brightening_magnitude=distribution(lighter))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--replay', required=True, type=pathlib.Path)
    parser.add_argument('--output', required=True, type=pathlib.Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.parent != NOTES or not output.name.startswith('attempt12') or output.suffix != '.json':
        parser.error('output must be an attempt12*.json file directly in notes')
    if output.exists():
        parser.error('refusing to overwrite existing diagnostic')
    replay = args.replay.resolve()
    historical = replay / 'summary.json'
    result = dict(directives='DIRECTIVES v775512c234', diagnostic_only=True,
                  source_replay=str(replay), self_test=self_test(),
                  historical_summary=json.loads(historical.read_text()),
                  historical_summary_sha256=digest(historical), modes={},
                  geometry_classes=GEOMETRY, geometry_tolerance=1e-5,
                  geometry_definition='Finite reverse-Z z<=1e-9: sky. Valid five-point cross: '
                  'ddx=zLeft+zRight-2*zCenter, ddy=zDown+zUp-2*zCenter. '
                  'Planar: abs(ddx),abs(ddy)<=1e-5. Concave proxy: both >=-1e-5 and one >1e-5. '
                  'Convex proxy: both <=1e-5 and one <-1e-5. Remaining: other.',
                  limitations=['Local diagnostic only, never device proof or owner validation.',
                    'Historical summary is copied verbatim as data; its prefix verdict is not recalculated.',
                    'Bright indices cover every sample before the first darkest interior sample, including secondary peaks.',
                    'Whole-window bright indices use that same minimum+4 over ALL samples; natural interior brightening may be included.',
                    'Later-drop indices compare each sample with its strictly following minimum across the entire window; descending shoulders may be included.',
                    'Secondary peak/plateau groups require lower immediate neighbors on both sides and a strictly following minimum more than 4 below the peak.',
                    'No full disappearance or global verdict follows from the first-minimum diagnostic or any additional statistic.',
                    'Profiles stop at nine samples, identity/surface changes or unusable depth, exactly as the bounded reader.',
                    'Missing and censored sides have null counts; totals cover measurable sides only.',
                    'Qualified primitive identities exist only in the ROI; 425 pixels are two named patches, not all contacts.',
                    'Depth curvature classes are local proxies: no semantic classes or physical concavity established outside ROI.',
                    'Depth discontinuities and silhouettes may enter curvature proxies; no safety outside contact is proved.'])
    for mode in ('ssao', 'hbao', 'gtao'):
        directory = replay / mode
        profile, ao, depth = load_mode(directory)
        pixels, _ = contacts(profile)
        mask = np.zeros(ao.shape, dtype=bool)
        for x, y in pixels:
            mask[y, x] = True
        labels = geometry(depth)
        full = profiles(profile, ao, depth)
        record = dict(shape=list(ao.shape), origin='lower-left', population=profile['populations'],
                      profile=full, comparisons={},
                      source_sha256={name: digest(directory / name) for name in
                                     ('contact-profiles.json', 'ridge-3.r8', 'scene-depth.f32')})
        arrays = dict(qualified_425=mask, geometry_class=labels)
        for name in ('attempt11-reference', 'attempt11-delivered'):
            base_dir = NOTES / name / mode
            base_profile, base_ao, base_depth = load_mode(base_dir)
            if (population(base_profile) != pixels or
                base_profile['projected_segment_px'] != profile['projected_segment_px'] or
                base_ao.shape != ao.shape or not np.array_equal(base_depth, depth, equal_nan=True)):
                raise ValueError('comparison population/projection/depth mismatch')
            delta = ao.astype(np.int16) - base_ao.astype(np.int16)
            changed = delta != 0
            arrays[name + '_signed_delta'] = delta
            arrays[name + '_changed'] = changed
            arrays[name + '_changed_outside_425'] = changed & ~mask
            yy, xx = np.indices(ao.shape)
            record['comparisons'][name] = dict(
                reference_ridge_sha256=digest(base_dir / 'ridge-3.r8'),
                global_image=delta_stats(delta, np.ones_like(mask)),
                inside_425=delta_stats(delta, mask), outside_425=delta_stats(delta, ~mask),
                by_geometry={label: delta_stats(delta, labels == code) for code, label in GEOMETRY.items()},
                outside_425_by_geometry={label: delta_stats(delta, (labels == code) & ~mask)
                                         for code, label in GEOMETRY.items()},
                phases_2x2={f'{x},{y}': delta_stats(delta, (xx % 2 == x) & (yy % 2 == y))
                            for y in (0, 1) for x in (0, 1)},
                reference_full_profile=profiles(base_profile, base_ao, base_depth))
        mask_path = output.with_name(output.stem + '-' + mode + '-masks.npz')
        if mask_path.exists():
            raise ValueError('refusing to overwrite masks')
        np.savez_compressed(mask_path, **arrays)
        record['masks'] = dict(path=str(mask_path), sha256=digest(mask_path), arrays=list(arrays),
                             layout='full-image row-major [y,x], lower-left origin; booleans true mark membership')
        result['modes'][mode] = record
    with output.open('x') as stream:
        json.dump(result, stream, indent=2, allow_nan=False)
        stream.write('\n')
    print(json.dumps({mode: record['profile']['summary'] for mode, record in result['modes'].items()}))


if __name__ == '__main__':
    main()
