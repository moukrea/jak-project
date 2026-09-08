"""Synthetic unit inputs ONLY: no fixture is a game proof or device validation."""
import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('hdr_batches', ROOT / '.autoport/lib/hdr_batches.py')
hdr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hdr)


@pytest.fixture
def plan():
    return hdr.contract(ROOT)


def stats(path):
    value = json.loads(path.read_text())
    if value.get('invalid'):
        raise ValueError('unreadable synthetic pixels')
    return value


def pixels(**changes):
    return dict(pixels=10000, width=100, height=100, white=0, nearwhite=0, clipped=0,
                black=0, luma=120, luma_p99=200, saturation=.3, detail=10, flat=.1,
                hue_bins=[1] * 12, **changes)


def complete_requests(plan):
    views = {}
    for view, level in plan['views'].items():
        views.setdefault(level, view)
    # village1 needs both its sky and Samos' hut.
    views['village1'] = 'village1-out'
    return [(v, h) for v in [*views.values(), 'legacy'] for h in plan['hours']]


def batch(root, plan, requests, name='001', crash=0, replaces=(), bad=None):
    path = root / name
    path.mkdir()
    values = dict(refset_bin_fp='1234567890abcdef', refset_data_fp='abcdef1234567890',
                  hdr_overbright_px='1', hdr_probe_max_x1000='2000', hdr_probe_px='100',
                  hdr_curve_samples='8000', hdr_cfg_frames_recharged='10', hdr_cfg_frames_origine_lumiere='10')
    values.update({key: '0' for key in hdr.CHAIN})
    values.update(hdr_curve_monotone_bad='0', hdr_curve_unbounded_bad='0', hdr_curve_kink_max_x1000='0',
                  hdr_cfg_bad_recharged='0', hdr_cfg_bad_origine_lumiere='0',
                  tonemap_sites_implicit='0', hdr_aux_clamped_reads='0', hdr_aux_clamped_sites='aucun')
    lines = ['REFSET provenance-init version=2 data=abcdef1234567890 input=1111111111111111 input_source=loaded-replay']
    (path / 'captures').mkdir()
    (path / 'captures/refset-format.txt').write_text('version=2\n')
    for view, hour in requests:
        level = plan['views'][view]
        stem = ('' if view == 'legacy' else view + '-') + f'h{hour:02}'
        bg_key = 'refset_bgh_' + view.replace('-', '_')
        bg = 0 if view == 'legacy' or not plan['sky'][level] else 300
        values['refset_bg_max_pm_' + view.replace('-', '_')] = str(bg)
        values[bg_key] = values.get(bg_key, '') + f'h{hour:02}:{bg},'
        for phase, arm in ((2, 'recharged'), (3, 'origine-lumiere')):
            case = arm + '/' + stem
            target = path / 'captures' / (case + '.png')
            target.parent.mkdir(parents=True, exist_ok=True)
            p = pixels()
            if bad and phase == 2:
                p.update(bad)
            hdr.dump(target, p)
            target.with_suffix('.png.provenance.txt').write_text(
                'version=2\ncase=' + case + '\nbin=1234567890abcdef\ndata=abcdef1234567890\ninput=1111111111111111\nconfig=2222222222222222\nflavour=normal\ncapture_lf=100\npng=' + hdr.fnv(target) + '\n')
            options = {'master': True, 'lighting': phase == 2, 'hdr': phase == 2, 'rt_light': phase == 2,
                       'others': {'textures': True, 'grass': True},
                       'output': {'profile': 'sdr', 'curve': 2, 'exposure': 1, 'pbr_exposure': 1, 'knee': .8}}
            lines.append('REFSET effective case=' + case + ' options=' + json.dumps(options))
            key = f'hdr_{view.replace("-", "_")}_h{hour}_p{phase}_'
            values[key + 'cap_lf'] = '100'
            values[key + 'levels'] = level
            values[key + 'pixels'] = '10000'
    values['refset_probe_frames'] = values['refset_captured'] = str(len(requests) * 2)
    lines += [k + '=' + v for k, v in values.items()]
    (path / 'engine.log').write_text('\n'.join(lines) + '\n')
    (path / 'start.json').write_text('{}')
    props = ('[debug.opengoal.hdr]: [1]\n[debug.opengoal.recharged]: [1]\n'
             '[debug.opengoal.rt.light]: [1]\n[debug.opengoal.rt.intensity]: [1]\n'
             '[debug.opengoal.refset.vantages]: [synthetic]\n')
    for suffix in ('start', 'end'):
        (path / ('props-' + suffix + '.txt')).write_text(props)
    manifest = {'schema': hdr.SCHEMA, 'producer': 'proof_run.sh', 'contract': plan,
                'id': name, 'crash': crash, 'errors': [], 'requested': requests,
                'replacements': list(replaces), 'provenance': {
                    'binary_sha256': 'a' * 64, 'installed_sha256': 'a' * 64,
                    'apk_sha256': 'b' * 64, 'binary_fnv': '1234567890abcdef', 'serial': 'eae4df44', 'config_files': {}}, 'files': {}}
    hdr.dump(path / 'manifest.json', manifest)
    rehash(path)
    return path


def rehash(path):
    manifest = json.loads((path / 'manifest.json').read_text())
    manifest['files'] = {str(p.relative_to(path)): hdr.sha(p) for p in path.rglob('*')
                         if p.is_file() and p.name != 'manifest.json'}
    hdr.dump(path / 'manifest.json', manifest)


def edit_manifest(path, **changes):
    m = json.loads((path / 'manifest.json').read_text())
    m.update(changes)
    hdr.dump(path / 'manifest.json', m)


def result(root, plan, current='001'):
    return hdr.aggregate(root, current, plan, stats)


def test_real_contract(plan):
    assert len(plan['sky']) == 21
    assert len(plan['hours']) == 8
    assert len(plan['views']) == 28
    assert plan['sky']['sunkenb'] and plan['sky']['swamp']


def test_complete_synthetic_multiple_processes(tmp_path, plan):
    req = complete_requests(plan)
    batch(tmp_path, plan, req[:80])
    batch(tmp_path, plan, req[80:], '002')
    r = result(tmp_path, plan, '002')
    assert r['hdr_tonemap_defects'] == 0
    assert r['hdr_batch_cells'] == 21 * 8
    assert r['hdr_batch_pairs'] == 22 * 8
    assert not (tmp_path / 'proof.txt').exists()


def test_partial_red(tmp_path, plan):
    batch(tmp_path, plan, [('legacy', 0)])
    assert result(tmp_path, plan)['hdr_tonemap_defects'] > 0


@pytest.mark.parametrize('change', ['missing', 'modified', 'unreadable', 'schema', 'raw_missing',
                                  'duplicate', 'config', 'binary', 'crash', 'missing_chain',
                                  'missing_denominator', 'hdr_missing', 'sky_missing', 'hut_missing',
                                  'interior_missing', 'effective_missing', 'sidecar_missing', 'malformed'])
def test_negative_inputs(tmp_path, plan, change):
    req = complete_requests(plan)
    path = batch(tmp_path, plan, req)
    capture = next((path / 'captures').rglob('*.png'))
    log = path / 'engine.log'
    if change == 'missing':
        capture.unlink()
    elif change == 'modified':
        capture.write_text('modified')
    elif change == 'unreadable':
        hdr.dump(capture, {'invalid': True})
        rehash(path)
    elif change == 'schema':
        edit_manifest(path, schema=0)
    elif change == 'raw_missing':
        log.unlink()
    elif change == 'duplicate':
        batch(tmp_path, plan, [('legacy', 0)], '002')
    elif change in ('config', 'effective_missing'):
        text = log.read_text()
        log.write_text(text.replace('"grass": true', '"grass": false', 1) if change == 'config'
                       else '\n'.join(x for x in text.splitlines() if not x.startswith('REFSET effective')))
        rehash(path)
    elif change == 'binary':
        m = json.loads((path / 'manifest.json').read_text())
        m['provenance']['installed_sha256'] = 'c' * 64
        hdr.dump(path / 'manifest.json', m)
    elif change == 'crash':
        edit_manifest(path, crash=1)
    elif change in ('missing_chain', 'missing_denominator', 'hdr_missing'):
        key = {'missing_chain': 'hdr_curve_monotone_bad', 'missing_denominator': 'hdr_curve_samples',
               'hdr_missing': 'hdr_overbright_px'}[change]
        log.write_text('\n'.join(x for x in log.read_text().splitlines() if not x.startswith(key + '=')))
        rehash(path)
    elif change in ('sky_missing', 'hut_missing', 'interior_missing'):
        view, before, after = {'sky_missing': ('sunkenb_start', ':300', ':0'),
                              'hut_missing': ('legacy', ':0', ':300'),
                              'interior_missing': ('maincave_start', ':0', ':300')}[change]
        log.write_text('\n'.join(x.replace(before, after) if x.startswith('refset_bgh_' + view + '=') else x
                                 for x in log.read_text().splitlines()))
        rehash(path)
    elif change == 'sidecar_missing':
        capture.with_suffix('.png.provenance.txt').unlink()
        rehash(path)
    elif change == 'malformed':
        (path / 'manifest.json').write_text('{bad')
    assert result(tmp_path, plan)['hdr_tonemap_defects'] > 0


@pytest.mark.parametrize('metric', hdr.QUALITY)
def test_burnt_pixel_defects_recomputed(tmp_path, plan, metric):
    batch(tmp_path, plan, complete_requests(plan), bad={metric: 1000})
    r = result(tmp_path, plan)
    assert r['hdr_defect_1_saturation'] == 1
    assert r['hdr_batch_quality_bad'] > 0


def test_nonidentical_pixels_and_contrast_are_diagnostics(tmp_path, plan):
    batch(tmp_path, plan, complete_requests(plan), bad={'luma': 90, 'detail': 2, 'saturation': .4})
    assert result(tmp_path, plan)['hdr_tonemap_defects'] == 0


def test_explicit_replacement_of_crashed_batch(tmp_path, plan):
    batch(tmp_path, plan, [('swamp-start', 0)], crash=1)
    req = complete_requests(plan)
    # The complete set uses swamp-dock1, a distinct view of the same region/hour.
    assert ('swamp-dock1', 0) in req
    batch(tmp_path, plan, req, '002', replaces=['001:swamp-start:0=swamp-dock1'])
    assert result(tmp_path, plan, '002')['hdr_tonemap_defects'] == 0


def test_replacement_wrong_region_red(tmp_path, plan):
    batch(tmp_path, plan, [('swamp-start', 0)], crash=1)
    batch(tmp_path, plan, complete_requests(plan), '002', replaces=['001:swamp-start:0=beach-start'])
    assert result(tmp_path, plan, '002')['hdr_tonemap_defects'] > 0


def test_imagemagick_actual_decode(tmp_path):
    import shutil
    if not shutil.which('magick'):
        pytest.skip('ImageMagick unavailable')
    ppm = tmp_path / 'fixture.ppm'
    ppm.write_bytes(b'P6\n2 2\n255\n' + bytes([255, 255, 255, 245, 245, 245, 255, 0, 0, 0, 0, 0]))
    r = hdr.measure(ppm)
    assert r['pixels'] == 4 and r['white'] == 1 and r['nearwhite'] == 2 and r['clipped'] == 2


@pytest.mark.parametrize('kind', ['binary', 'apk', 'data', 'config', 'schema'])
def test_incompatible_batches(tmp_path, plan, kind):
    req = complete_requests(plan)
    batch(tmp_path, plan, req[:80])
    path = batch(tmp_path, plan, req[80:], '002')
    m = json.loads((path / 'manifest.json').read_text())
    if kind == 'binary':
        m['provenance']['binary_sha256'] = m['provenance']['installed_sha256'] = 'c' * 64
    elif kind == 'apk':
        m['provenance']['apk_sha256'] = 'c' * 64
    elif kind == 'schema':
        m['schema'] += 1
    else:
        log = path / 'engine.log'
        if kind == 'data':
            log.write_text(log.read_text().replace('abcdef1234567890', 'abcdef1234567891'))
            for p in path.rglob('*.provenance.txt'):
                p.write_text(p.read_text().replace('abcdef1234567890', 'abcdef1234567891'))
        else:
            log.write_text(log.read_text().replace('"exposure": 1', '"exposure": 2'))
        rehash(path)
        m = json.loads((path / 'manifest.json').read_text())
    hdr.dump(path / 'manifest.json', m)
    assert result(tmp_path, plan, '002')['hdr_tonemap_defects'] > 0


def test_missing_manifest_not_silently_ignored(tmp_path, plan):
    batch(tmp_path, plan, complete_requests(plan))
    (tmp_path / 'broken-lot').mkdir()
    assert result(tmp_path, plan)['hdr_tonemap_defects'] > 0


@pytest.mark.parametrize('field', ['png', 'input', 'config', 'capture_lf', 'flavour'])
def test_sidecar_fields_bound_to_capture(tmp_path, plan, field):
    path = batch(tmp_path, plan, complete_requests(plan))
    side = next(path.rglob('*.provenance.txt'))
    values = hdr.kv(side.read_text())
    values[field] = 'bad'
    side.write_text('\n'.join(k + '=' + v for k, v in values.items()))
    rehash(path)
    assert result(tmp_path, plan)['hdr_tonemap_defects'] > 0


@pytest.mark.parametrize('view', ['legacy', 'training_start'])
def test_sky_min_does_not_hide_other_arm_void(tmp_path, plan, view):
    path = batch(tmp_path, plan, complete_requests(plan))
    log = path / 'engine.log'
    log.write_text('\n'.join('refset_bg_max_pm_' + view + '=1000' if x.startswith('refset_bg_max_pm_' + view + '=') else x
                             for x in log.read_text().splitlines()))
    rehash(path)
    assert result(tmp_path, plan)['hdr_tonemap_defects'] > 0


@pytest.mark.parametrize('kind', ['quality', 'chain'])
def test_replacement_cannot_erase_observed_defect(tmp_path, plan, kind):
    path = batch(tmp_path, plan, [('swamp-start', 0)], bad={'white': 1000} if kind == 'quality' else None)
    if kind == 'chain':
        log = path / 'engine.log'
        log.write_text(log.read_text().replace('hdr_curve_monotone_bad=0', 'hdr_curve_monotone_bad=1'))
        rehash(path)
    batch(tmp_path, plan, complete_requests(plan), '002', replaces=['001:swamp-start:0=swamp-dock1'])
    assert result(tmp_path, plan, '002')['hdr_tonemap_defects'] > 0


def test_supplemental_paths(tmp_path, plan):
    path = batch(tmp_path, plan, complete_requests(plan))
    for arm in ('recharged', 'origine-lumiere'):
        src = path / 'captures' / arm / 'training-start-h00.png'
        dest = path / 'captures/supplement-v1' / arm / src.name
        dest.parent.mkdir(parents=True, exist_ok=True)
        src.rename(dest)
        src.with_suffix('.png.provenance.txt').rename(dest.with_suffix('.png.provenance.txt'))
    rehash(path)
    assert result(tmp_path, plan)['hdr_tonemap_defects'] == 0


def test_unattested_pixel_cache_ignored(tmp_path, plan):
    batch(tmp_path, plan, complete_requests(plan), bad={'white': 1000})
    hdr.dump(tmp_path / 'pixel-cache.json', {'forged': 'green'})
    assert result(tmp_path, plan)['hdr_defect_1_saturation'] == 1


def test_logcat_binary_noise_is_not_a_decode_failure(tmp_path, plan):
    path = batch(tmp_path, plan, complete_requests(plan))
    with (path / 'engine.log').open('ab') as stream:
        stream.write(b'\xff\xfe noisy unrelated log\n')
    rehash(path)
    assert result(tmp_path, plan)['hdr_tonemap_defects'] == 0


def test_early_crash_requires_explicit_replacement(tmp_path, plan):
    path = batch(tmp_path, plan, [('swamp-start', 0)], crash=1)
    for p in (path / 'captures').rglob('*'):
        if p.is_file():
            p.unlink()
    (path / 'engine.log').write_text('process aborted before first capture\n')
    rehash(path)
    assert result(tmp_path, plan)['hdr_tonemap_defects'] > 0
    batch(tmp_path, plan, complete_requests(plan), '002', replaces=['001:swamp-start:0=swamp-dock1'])
    assert result(tmp_path, plan, '002')['hdr_tonemap_defects'] == 0


@pytest.mark.parametrize('change', ['luma', 'hue', 'probes'])
def test_existing_image_and_probe_filters(tmp_path, plan, change):
    bad = {'luma_p99': 2} if change == 'luma' else {'hue_bins': [0] * 12} if change == 'hue' else None
    path = batch(tmp_path, plan, complete_requests(plan), bad=bad)
    if change == 'probes':
        log = path / 'engine.log'
        log.write_text('\n'.join('refset_probe_frames=1' if x.startswith('refset_probe_frames=') else x
                                 for x in log.read_text().splitlines()))
        rehash(path)
    assert result(tmp_path, plan)['hdr_tonemap_defects'] > 0


@pytest.mark.parametrize('scope', ['between', 'within'])
def test_rendering_property_intensity_mismatch(tmp_path, plan, scope):
    requests = complete_requests(plan)
    if scope == 'between':
        batch(tmp_path, plan, requests[:80])
        path = batch(tmp_path, plan, requests[80:], '002')
        snapshots = ('start', 'end')
    else:
        path = batch(tmp_path, plan, requests)
        snapshots = ('end',)
    for suffix in snapshots:
        props = path / ('props-' + suffix + '.txt')
        props.write_text(props.read_text().replace('[debug.opengoal.rt.intensity]: [1]',
                                                  '[debug.opengoal.rt.intensity]: [9]'))
    rehash(path)
    assert result(tmp_path, plan, path.name)['hdr_tonemap_defects'] > 0


def test_only_known_plan_properties_can_differ(tmp_path, plan):
    requests = complete_requests(plan)
    batch(tmp_path, plan, requests[:80])
    path = batch(tmp_path, plan, requests[80:], '002')
    for suffix in ('start', 'end'):
        props = path / ('props-' + suffix + '.txt')
        props.write_text(props.read_text().replace('[synthetic]', '[different-view]') +
                         '[debug.opengoal.level.warp]: [swamp-start]\n'
                         '[debug.opengoal.want.levels]: [swamp]\n'
                         '[debug.opengoal.padreplay]: [/different/path]\n')
    rehash(path)
    assert result(tmp_path, plan, '002')['hdr_tonemap_defects'] == 0


@pytest.mark.parametrize('name', ['props-start.txt', 'props-end.txt'])
def test_sealed_property_sources_required(tmp_path, plan, name):
    path = batch(tmp_path, plan, complete_requests(plan))
    (path / name).unlink()
    rehash(path)
    assert result(tmp_path, plan)['hdr_tonemap_defects'] > 0


def test_unknown_rendering_knob_is_not_excluded(tmp_path, plan):
    path = batch(tmp_path, plan, complete_requests(plan))
    props = path / 'props-end.txt'
    props.write_text(props.read_text() + '[debug.opengoal.new.render.knob]: [9]\n')
    rehash(path)
    assert result(tmp_path, plan)['hdr_tonemap_defects'] > 0


@pytest.mark.parametrize('reason', ['black', 'achromatic', 'missing_level', 'missing_probe'])
def test_unqualified_views_require_explicit_replacement(tmp_path, plan, reason):
    bad = {'black': 10000, 'luma_p99': 0} if reason == 'black' else {'hue_bins': [0] * 12} if reason == 'achromatic' else None
    path = batch(tmp_path, plan, [('swamp-start', 0)], bad=bad)
    if reason in ('missing_level', 'missing_probe'):
        log = path / 'engine.log'
        lines = log.read_text().splitlines()
        log.write_text('\n'.join(x.split('=')[0] + '=aucun' if reason == 'missing_level' and '_levels=' in x
                                 else 'refset_probe_frames=0' if reason == 'missing_probe' and x.startswith('refset_probe_frames=')
                                 else x for x in lines))
        rehash(path)
    old = hdr.read_batch(path / 'manifest.json', plan, stats)
    assert not old['pairs']
    assert ('swamp-start', 0) in old['unqualified']
    assert result(tmp_path, plan)['hdr_tonemap_defects'] > 0
    batch(tmp_path, plan, complete_requests(plan), '002', replaces=['001:swamp-start:0=swamp-dock1'])
    assert result(tmp_path, plan, '002')['hdr_tonemap_defects'] == 0
    diagnostics = json.loads((tmp_path / 'measurements.json').read_text())
    assert diagnostics['unqualified'][0]['reasons']


def test_missing_sky_probe_does_not_erase_measured_burns(tmp_path, plan):
    path = batch(tmp_path, plan, [('swamp-start', 0)], bad={'white': 1000})
    log = path / 'engine.log'
    log.write_text(log.read_text().replace('refset_probe_frames=2', 'refset_probe_frames=0'))
    rehash(path)
    batch(tmp_path, plan, complete_requests(plan), '002', replaces=['001:swamp-start:0=swamp-dock1'])
    assert result(tmp_path, plan, '002')['hdr_tonemap_defects'] > 0


@pytest.mark.parametrize('replace_a', [True, False])
def test_failed_replacement_target_can_be_superseded(tmp_path, plan, replace_a):
    a = batch(tmp_path, plan, [('swamp-start', 0)], name='001')
    # A's requested capture never arrived; the raw request and manifest remain.
    for image in (a / 'captures').rglob('*.png'):
        image.with_suffix('.png.provenance.txt').unlink()
        image.unlink()
    rehash(a)
    batch(tmp_path, plan, [('swamp-start', 0)], name='002',
          bad={'black': 10000, 'luma_p99': 0}, replaces=['001:swamp-start:0=swamp-start'])
    assert result(tmp_path, plan, '002')['hdr_tonemap_defects'] > 0
    replacements = ['002:swamp-start:0=swamp-dock1']
    if replace_a:
        replacements.append('001:swamp-start:0=swamp-dock1')
    batch(tmp_path, plan, complete_requests(plan), name='003', replaces=replacements)
    r = result(tmp_path, plan, '003')
    assert (r['hdr_tonemap_defects'] == 0) is replace_a
    diagnostics = json.loads((tmp_path / 'measurements.json').read_text())
    assert diagnostics['superseded_mappings'] == [{'batch': '002', 'mapping': '001:swamp-start:0=swamp-start'}]
    if not replace_a:
        assert any('001: unqualified/absent pair' in e for e in diagnostics['errors'])


@pytest.mark.parametrize('defect', ['burns', 'chain', 'integrity'])
def test_superseded_attempt_preserves_previous_defects(tmp_path, plan, defect):
    a = batch(tmp_path, plan, [('swamp-start', 0)], name='001',
              bad={'white': 1000} if defect == 'burns' else None)
    if defect == 'chain':
        log = a / 'engine.log'
        log.write_text(log.read_text().replace('hdr_curve_monotone_bad=0', 'hdr_curve_monotone_bad=1'))
        rehash(a)
    elif defect == 'integrity':
        (a / 'engine.log').write_text('changed after collection')
    batch(tmp_path, plan, [('swamp-start', 0)], name='002', bad={'black': 10000, 'luma_p99': 0},
          replaces=['001:swamp-start:0=swamp-start'])
    batch(tmp_path, plan, complete_requests(plan), name='003',
          replaces=['001:swamp-start:0=swamp-dock1', '002:swamp-start:0=swamp-dock1'])
    assert result(tmp_path, plan, '003')['hdr_tonemap_defects'] > 0


@pytest.mark.parametrize('missing', ['frame', 'all_final_fields'])
def test_final_counter_absence_keeps_other_pairs_and_allows_repair(tmp_path, plan, missing):
    path = batch(tmp_path, plan, [('swamp-start', 0), ('swamp-start', 3)])
    log = path / 'engine.log'
    endings = ('cap_lf=',) if missing == 'frame' else ('cap_lf=', 'pixels=', 'levels=')
    log.write_text('\n'.join(x for x in log.read_text().splitlines()
                             if not ('hdr_swamp_start_h3_p' in x and any(e in x for e in endings))))
    rehash(path)
    old = hdr.read_batch(path / 'manifest.json', plan, stats)
    assert set(old['pairs']) == {('swamp-start', 0)}
    assert set(old['unqualified']) == {('swamp-start', 3)}
    assert old['unqualified'][('swamp-start', 3)]['on']['pixels'] == 10000
    batch(tmp_path, plan, complete_requests(plan), name='002',
          replaces=['001:swamp-start:3=swamp-dock1'])
    assert result(tmp_path, plan, '002')['hdr_tonemap_defects'] == 0


@pytest.mark.parametrize('field,value', [('cap_lf', '101'), ('cap_lf', 'bad'), ('cap_lf', '-1'),
                                        ('pixels', '10001'), ('pixels', 'bad')])
def test_present_final_counter_contradictions_remain_fatal(tmp_path, plan, field, value):
    path = batch(tmp_path, plan, [('swamp-start', 0)])
    log = path / 'engine.log'
    key = 'hdr_swamp_start_h0_p2_' + field + '='
    log.write_text('\n'.join(key + value if x.startswith(key) else x for x in log.read_text().splitlines()))
    rehash(path)
    with pytest.raises(ValueError):
        hdr.read_batch(path / 'manifest.json', plan, stats)
    batch(tmp_path, plan, complete_requests(plan), name='002',
          replaces=['001:swamp-start:0=swamp-dock1'])
    assert result(tmp_path, plan, '002')['hdr_tonemap_defects'] > 0


def test_missing_final_counters_cannot_erase_measured_burns(tmp_path, plan):
    path = batch(tmp_path, plan, [('swamp-start', 0)], bad={'white': 1000})
    log = path / 'engine.log'
    log.write_text('\n'.join(x for x in log.read_text().splitlines() if not
                             ('hdr_swamp_start_h0_p' in x and any(e in x for e in ('cap_lf=', 'pixels=', 'levels=')))))
    rehash(path)
    batch(tmp_path, plan, complete_requests(plan), name='002',
          replaces=['001:swamp-start:0=swamp-dock1'])
    assert result(tmp_path, plan, '002')['hdr_tonemap_defects'] > 0


def test_replaced_unvisited_arm_flag_is_not_a_permanent_chain_defect(tmp_path, plan):
    path = batch(tmp_path, plan, [('swamp-start', 0)])
    log = path / 'engine.log'
    log.write_text(log.read_text().replace('hdr_cfg_frames_origine_lumiere=10', 'hdr_cfg_frames_origine_lumiere=0')
                   .replace('hdr_defect_5_sites_three_configs=0', 'hdr_defect_5_sites_three_configs=1'))
    rehash(path)
    batch(tmp_path, plan, complete_requests(plan), '002', replaces=['001:swamp-start:0=swamp-dock1'])
    assert result(tmp_path, plan, '002')['hdr_tonemap_defects'] == 0


@pytest.mark.parametrize('key,value,group', [
    ('hdr_cfg_bad_recharged', '1', 1), ('hdr_curve_monotone_bad', '1', 0),
    ('tonemap_sites_implicit', '1', 2), ('hdr_aux_clamped_sites', 'Sprite3_Distort:scene-copy', 2)])
def test_raw_chain_defect_survives_replacement_and_clean_latest_run(tmp_path, plan, key, value, group):
    path = batch(tmp_path, plan, [('swamp-start', 0)])
    log = path / 'engine.log'
    log.write_text('\n'.join(key + '=' + value if x.startswith(key + '=') else x
                             for x in log.read_text().splitlines()))
    if key == 'hdr_aux_clamped_sites':
        log.write_text(log.read_text().replace('hdr_aux_clamped_reads=0', 'hdr_aux_clamped_reads=1'))
    rehash(path)
    batch(tmp_path, plan, complete_requests(plan), '002', replaces=['001:swamp-start:0=swamp-dock1'])
    r = result(tmp_path, plan, '002')
    assert r[hdr.CHAIN[group]] == 1
    assert r['hdr_tonemap_defects'] > 0
    diagnostics = json.loads((tmp_path / 'measurements.json').read_text())
    assert any('001: chain ' + key in e for e in diagnostics['errors'])


@pytest.mark.parametrize('key', ['hdr_curve_monotone_bad', 'hdr_cfg_bad_origine_lumiere',
                                 'tonemap_sites_implicit', 'hdr_aux_clamped_reads', 'hdr_aux_clamped_sites'])
def test_selected_batch_requires_raw_chain_operands(tmp_path, plan, key):
    path = batch(tmp_path, plan, complete_requests(plan))
    log = path / 'engine.log'
    log.write_text('\n'.join(x for x in log.read_text().splitlines() if not x.startswith(key + '=')))
    rehash(path)
    assert result(tmp_path, plan)['hdr_tonemap_defects'] > 0


@pytest.mark.parametrize('kink,flag,expected', [('49', '1', 0), ('50', '0', 0), ('50', '1', 1),
                                             ('50', None, 1), ('51', '0', 1)])
def test_curve_rounding_bin_requires_exact_float_corroboration(kink, flag, expected):
    values = {'hdr_curve_kink_max_x1000': kink, 'hdr_curve_samples': '8000',
              'hdr_curve_monotone_bad': '0', 'hdr_curve_unbounded_bad': '0'}
    if flag is not None:
        values[hdr.CHAIN[0]] = flag
    defects, _ = hdr.chain_measurements(values, required=True)
    assert defects[hdr.CHAIN[0]] == expected


def test_missing_last_effective_record_keeps_pixels_and_allows_repair(tmp_path, plan):
    path = batch(tmp_path, plan, [('swamp-start', 0), ('swamp-start', 3)])
    log = path / 'engine.log'
    log.write_text('\n'.join(x for x in log.read_text().splitlines() if not
                             x.startswith('REFSET effective case=origine-lumiere/swamp-start-h03 ')))
    rehash(path)
    old = hdr.read_batch(path / 'manifest.json', plan, stats)
    assert set(old['pairs']) == {('swamp-start', 0)}
    row = old['unqualified'][('swamp-start', 3)]
    assert row['on']['pixels'] == row['off']['pixels'] == 10000
    assert row['comparable'] is False
    assert row['options'][1] is None
    assert any('effective settings absent:' in r for r in row['reasons'])
    assert result(tmp_path, plan)['hdr_tonemap_defects'] > 0
    batch(tmp_path, plan, complete_requests(plan), name='002',
          replaces=['001:swamp-start:3=swamp-dock1'])
    assert result(tmp_path, plan, '002')['hdr_tonemap_defects'] == 0


@pytest.mark.parametrize('invalid', ['malformed_json', 'wrong_config', 'non_object'])
def test_present_invalid_effective_record_is_fatal_even_after_replacement(tmp_path, plan, invalid):
    path = batch(tmp_path, plan, [('swamp-start', 0)])
    log = path / 'engine.log'
    text = log.read_text()
    if invalid == 'wrong_config':
        text = text.replace('"grass": true', '"grass": false', 1)
    else:
        prefix = 'REFSET effective case=origine-lumiere/swamp-start-h00 options='
        text = '\n'.join(prefix + ('{broken' if invalid == 'malformed_json' else 'null')
                         if x.startswith(prefix) else x for x in text.splitlines())
    log.write_text(text)
    rehash(path)
    with pytest.raises(ValueError):
        hdr.read_batch(path / 'manifest.json', plan, stats)
    batch(tmp_path, plan, complete_requests(plan), name='002',
          replaces=['001:swamp-start:0=swamp-dock1'])
    assert result(tmp_path, plan, '002')['hdr_tonemap_defects'] > 0
