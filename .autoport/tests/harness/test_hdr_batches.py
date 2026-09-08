"""Synthetic unit inputs ONLY: no fixture is a game proof or device validation."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess

import pytest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('hdr_batches', ROOT / '.autoport/lib/hdr_batches.py')
hdr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hdr)


@pytest.mark.parametrize('state,pid0,hdr_batch,trace,crash,elapsed,calls', [
    ('stable', '123', 'batch', '', 0, 23, 3),
    ('absent', '123', 'batch', '', 1, 13, 1),
    ('changed', '123', 'batch', '', 1, 13, 1),
    ('transport', '123', 'batch', '', 0, 23, 3),
    ('remote_error', '123', 'batch', '', 0, 23, 3),
    ('absent', '', 'batch', '', 0, 23, 0),
    ('absent', '123', '', '', 0, 23, 0),
    ('stable', '123', 'batch', 'GK-DIAG A36-TREE at-crash frame=1', 1, 13, 0),
    ('stable', '123', 'batch', 'REFSET done steps=4 captured=4 compared=0 missing=0\nhdr_paired=2', 0, 13, 1),
    ('stable', '123', 'batch', 'REFSET done steps=24 captured=24 compared=0 missing=0\nrefset_temporal_samples=6\nhdr_paired=2', 0, 13, 1),
    ('stable', '123', 'batch', 'REFSET done steps=24 captured=23 compared=0 missing=0\nrefset_temporal_samples=6\nhdr_paired=2', 0, 23, 3),
    ('stable', '123', 'batch', 'REFSET done steps=24 captured=24 compared=0 missing=0\nrefset_temporal_samples=6\nhdr_paired=1', 0, 23, 3),
    ('stable', '123', 'batch', 'REFSET done steps=25 captured=25 compared=0 missing=0\nrefset_temporal_samples=6\nhdr_paired=2', 0, 23, 3),
])
def test_hdr_wait_process_liveness(tmp_path, state, pid0, hdr_batch, trace, crash, elapsed, calls):
    """Execute the production wait loop, with local fake adb and no real sleeps."""
    source = (ROOT / '.autoport/lib/proof_run.sh').read_text()
    loop = source.split('  elapsed=8\n', 1)[1].split('\n  PID1=', 1)[0]
    fake_adb = tmp_path / 'adb'
    fake_adb.write_text('''#!/usr/bin/env bash
set -u
[[ "$#" == 4 && "$1" == -s && "$2" == eae4df44 && "$3" == shell ]] || exit 98
echo query >> "$CALLS"
[[ "$STATE" != transport ]] || exit 1
pidof() {
  [[ "$#" == 1 && "$1" == org.opengoal.jak ]] || return 98
  case "$STATE" in
    stable) printf '123 456\\r\\n' ;;
    absent) return 1 ;;
    changed) printf '789\\r\\n' ;;
    remote_error) return 127 ;;
  esac
}
eval "$4"
''')
    fake_adb.chmod(0o755)
    rawlog = tmp_path / 'engine.log'
    rawlog.write_text(trace + '\n')
    call_log = tmp_path / 'calls'
    env = dict(os.environ, ADB=str(fake_adb), SERIAL='eae4df44', PKG='org.opengoal.jak',
               PID0=pid0, HDR_BATCH=hdr_batch, RAWLOG=str(rawlog), STATE=state, CALLS=str(call_log))
    run = subprocess.run(['bash', '-c', '''set -uo pipefail
sleep() { :; }
log() { echo "$*" >&2; }
CRASH=0; TIMEOUT=23; elapsed=8
''' + loop + '\nprintf "%s %s\\n" "$CRASH" "$elapsed"\n'], env=env,
                         capture_output=True, text=True, timeout=10)
    assert run.returncode == 0, run.stderr
    assert run.stdout.strip() == f'{crash} {elapsed}'
    assert (len(call_log.read_text().splitlines()) if call_log.exists() else 0) == calls
    assert rawlog.read_text() == trace + '\n'


@pytest.fixture
def plan(monkeypatch):
    contract = hdr.contract(ROOT)
    # Existing synthetic fixtures measure regional coverage, without owner cases.
    contract['plan'].pop('owner_regression_cases', None)
    # Test-only semantic attribution: this view does not exist in the game and
    # certifies no execution. Legacy remains a separate historical interior.
    contract['views']['synthetic-sage-hut'] = 'village1'
    monkeypatch.setattr(hdr, 'HUT_VIEWS', frozenset({'synthetic-sage-hut'}))
    return contract


def run_hdr_production_block(tmp_path, values, *, item='lighting-hdr', armed='1', batch_path=''):
    source = (ROOT / '.autoport/lib/proof_run.sh').read_text()
    block = source.split('rm -f "$NORM"\n\n', 1)[1].split('\nTMP=', 1)[0]
    env = dict(os.environ, AP=str(ROOT / '.autoport'), D=str(tmp_path), ID=item, ARMED=armed,
               HDR_BATCH=batch_path, HDR_CAMPAIGN='synthetic', EXTRA='', KVLINES=values)
    run = subprocess.run(['bash', '-c', 'set -uo pipefail\nlog() { echo "$*" >&2; }\n' +
                          block + '\nprintf "%s\\n" "$KVLINES"\n'], cwd=ROOT, env=env,
                         capture_output=True, text=True, timeout=20)
    assert run.returncode == 0, run.stderr
    keys = [line.split('=', 1)[0] for line in run.stdout.splitlines() if '=' in line]
    assert len(keys) == len(set(keys)), run.stdout
    return hdr.kv(run.stdout)


@pytest.mark.parametrize('total', ['0', '6', None, 'invalid', '-1'])
def test_normal_proof_adds_owner_guard_preserving_engine_measurements(tmp_path, total):
    previous = {key: str(i) for i, key in enumerate((*hdr.CHAIN, 'hdr_defect_1_saturation',
                'hdr_defect_2_hl_contrast', 'hdr_defect_4_origine_lumiere_set'), 1)}
    previous['hdr_curve_samples'] = '8000'
    values = {**previous, 'owner_case': '0', 'hdr_owner_regressions_required': '0',
              'hdr_owner_regressions_measured': '5', 'hdr_owner_regressions_missing': '0',
              'hdr_defect_7_owner_regressions': '0'}
    if total is not None:
        values['hdr_tonemap_defects'] = total
    r = run_hdr_production_block(tmp_path, '\n'.join(f'{k}={v}' for k, v in values.items()))
    assert all(r[k] == v for k, v in previous.items())
    assert r['hdr_owner_regressions_required'] == r['hdr_owner_regressions_missing'] == '5'
    assert r['hdr_owner_regressions_measured'] == '0'
    assert r['hdr_defect_7_owner_regressions'] == '1'
    if total in ('0', '6'):
        assert r['hdr_tonemap_defects'] == str(int(total) + 1)
    else:
        assert 'hdr_tonemap_defects' not in r
    cases = hdr.contract(ROOT)['plan']['owner_regression_cases']
    diagnostics = json.loads((tmp_path / 'measurements.json').read_text())['owner_regressions']
    assert diagnostics['missing'] == cases
    assert diagnostics['measured'] == []
    assert not (tmp_path / 'proof.txt').exists()


def test_batch_proof_replaces_engine_owner_claims_without_duplicate_keys(tmp_path):
    values = ('hdr_tonemap_defects=0\nhdr_owner_regressions_required=0\n'
              'hdr_owner_regressions_measured=5\nhdr_owner_regressions_missing=0\n'
              'hdr_defect_7_owner_regressions=0\nhdr_batch_errors=0\nhdr_curve_samples=8000')
    r = run_hdr_production_block(tmp_path, values, batch_path=str(tmp_path / 'missing'))
    assert r['hdr_tonemap_defects'] == '2'
    assert r['hdr_defect_7_owner_regressions'] == '1'
    assert r['hdr_owner_regressions_required'] == r['hdr_owner_regressions_missing'] == '5'
    assert r['hdr_owner_regressions_measured'] == '0'
    assert r['hdr_batch_errors'] == '1'
    assert r['hdr_curve_samples'] == '8000'


@pytest.mark.parametrize('item,armed', [('lighting-hdr', '0'), ('other-item', '1')])
def test_normal_owner_guard_leaves_ablation_and_other_items_unchanged(tmp_path, item, armed):
    values = 'hdr_tonemap_defects=0\nother_counter=12'
    assert run_hdr_production_block(tmp_path, values, item=item, armed=armed) == hdr.kv(values)
    assert not (tmp_path / 'measurements.json').exists()


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
    return [(v, h) for v in [*views.values(), 'legacy', 'synthetic-sage-hut'] for h in plan['hours']]


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
        bg = 0 if view in ('legacy', 'synthetic-sage-hut') or not plan['sky'][level] else 300
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
        (path / ('settings-' + suffix + '.ini')).write_text('synthetic-render-setting=1\n')
    manifest = {'schema': hdr.SCHEMA, 'producer': 'proof_run.sh', 'contract': plan,
                'id': name, 'crash': crash, 'errors': [], 'requested': requests,
                'replacements': list(replaces), 'provenance': {
                    'binary_sha256': 'a' * 64, 'installed_sha256': 'a' * 64,
                    'apk_sha256': 'b' * 64, 'binary_fnv': '1234567890abcdef', 'serial': 'eae4df44', 'config_files': {'settings.ini': hdr.sha(path / 'settings-start.ini')}}, 'files': {}}
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


def test_real_contract():
    plan = hdr.contract(ROOT)
    assert len(plan['sky']) == 21
    assert len(plan['hours']) == 8
    assert len(plan['views']) == 29
    assert plan['views']['village1-eco-blue'] == 'village1'
    assert plan['sky']['sunkenb'] and plan['sky']['swamp']
    assert hdr.HUT_VIEWS == frozenset()


def test_owner_regions_use_shared_projected_bounds_and_preserve_absence(tmp_path):
    """Synthetic byte sources and fake regional pixels, never a game verdict."""
    lines, images, measured = [], {}, []
    for frame, arm, rect, passed in ((100, 'recharged', [10, 20, 30, 40], True),
                                     (200, 'origine-lumiere', [12, 22, 32, 42], True),
                                     (212, 'origine-lumiere', None, False)):
        case = arm + '/village1-eco-blue-h12' + ('-t01' if frame == 212 else '')
        rel = 'captures/' + case + '.png'
        target = tmp_path / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(b'synthetic image source ' + str(frame).encode())
        (tmp_path / (rel + '.provenance.txt')).write_text(
            f'case={case}\ncapture_lf={frame}\npng={hdr.fnv(target)}\n')
        images[rel] = {'sha256': hdr.sha(target), 'stats': {'width': 320, 'height': 180}}
        lines.append(f'REFSET sample case={case} layer=historical chain_lf={frame} anchor_lf=88')
        # lg::info has its own prefix, inside logcat's already-normalized line.
        lines.append('[45:00:123] [info] HDR-OWNER-SPRITE ' + json.dumps(
            {'lf': frame, 'actor': 10012, 'roi': rect, 'passed': passed, 'supported': rect is not None}))
    (tmp_path / 'engine.log').write_text('\n'.join(lines))
    def regional(path, rect):
        measured.append((path, rect))
        return dict(white=1, nearwhite=2, clipped=3, luma=120, detail=4, flat=.1, saturation=.2)
    result = hdr.owner_regions(tmp_path, images, regional)
    assert result['errors'] == []
    assert result['status'] == 'diagnostic_only'
    row, = result['regions']
    assert row['status'] == 'not_judged'
    assert all(rect == [10, 20, 32, 42] for _, rect in measured)
    assert len(measured) == 3  # invisible temporal frame is retained, not silently discarded
    assert row['summary']['origine-lumiere']['samples'] == 2
    assert row['summary']['origine-lumiere']['visible_frames'] == 1
    first = next(iter(images))
    (tmp_path / first).write_bytes(b'modified after provenance')
    bad = hdr.owner_regions(tmp_path, images, regional)
    assert any('provenance mismatch' in error for error in bad['errors'])


def test_owner_regions_reject_unmatched_frame_and_unknown_actor(tmp_path):
    (tmp_path / 'engine.log').write_text('\n'.join('HDR-OWNER-SPRITE ' + json.dumps(w) for w in
        ({'lf': 100, 'actor': 10012}, {'lf': 100, 'actor': 99999})))
    result = hdr.owner_regions(tmp_path, {})
    assert len(result['errors']) == 2
    assert result['regions'] == []


def test_regional_measure_rejects_bounds_and_measures_crop(tmp_path):
    image = tmp_path / 'synthetic.ppm'
    image.write_bytes(b'P6\n4 2\n255\n' + bytes([255, 255, 255, 255, 255, 255, 0, 0, 0, 0, 0, 0]) * 2)
    assert hdr.measure(image, [0, 0, 2, 2])['white'] == 4
    assert hdr.measure(image, [2, 0, 4, 2])['white'] == 0
    with pytest.raises(ValueError, match='bounds'):
        hdr.measure(image, [3, 0, 5, 2])


@pytest.mark.parametrize('change', ['missing_count', 'requested_mismatch', 'missing_capture'])
def test_temporal_incomplete_sources_never_pass(tmp_path, plan, change):
    path = batch(tmp_path, plan, [('village1-eco-blue', 12)])
    engine = path / 'engine.log'
    text = engine.read_text() + 'refset_temporal_samples=2\n'
    if change != 'missing_count':
        text += 'refset_temporal_captured=4\nrefset_captured=4\nrefset_probe_frames=4\n'
    if change == 'requested_mismatch':
        props = path / 'props-start.txt'
        props.write_text(props.read_text() + '[debug.opengoal.refset.temporal]: [6]\n')
    engine.write_text(text)
    rehash(path)
    r = result(tmp_path, plan)
    assert r['hdr_batch_errors'] > 0
    assert r['hdr_tonemap_defects'] > 0


@pytest.mark.parametrize('crashed', [False, True])
def test_temporal_complete_cell_survives_later_crash_for_explicit_replacement(tmp_path, plan, crashed):
    path = batch(tmp_path, plan, [('village1-eco-blue', 12)], crash=int(crashed))
    engine = path / 'engine.log'
    lines = []
    for line in engine.read_text().splitlines():
        if not line.startswith('REFSET effective '):
            lines.append(line)
            continue
        prefix, encoded = line.split(' options=', 1)
        case = prefix.split('case=', 1)[1]
        options = json.loads(encoded)
        options['temporal'] = {'samples': 2, 'sample': 0, 'spacing_lf': 12,
                               'particle_step': 'once-per-logic-frame'}
        lines.append(prefix + ' options=' + json.dumps(options))
        extra_case = case + '-t01'
        source = path / 'captures' / (case + '.png')
        extra = path / 'captures' / (extra_case + '.png')
        extra.write_bytes(source.read_bytes())
        sidecar = source.with_suffix('.png.provenance.txt').read_text()
        extra.with_suffix('.png.provenance.txt').write_text(
            sidecar.replace('case=' + case, 'case=' + extra_case).replace('capture_lf=100', 'capture_lf=112'))
        options['temporal']['sample'] = 1
        lines.append('REFSET effective case=' + extra_case + ' options=' + json.dumps(options))
    lines += ['refset_temporal_samples=2', 'refset_temporal_captured=4', 'refset_captured=4', 'refset_probe_frames=4']
    engine.write_text('\n'.join(lines) + '\n')
    if crashed:
        edit_manifest(path, requested=[['village1-eco-blue', 12], ['village1-eco-blue', 18]])
    rehash(path)
    parsed = hdr.read_batch(path / 'manifest.json', plan, stats)
    assert ('village1-eco-blue', 12) in parsed['pairs']
    if crashed:
        assert ('village1-eco-blue', 18) in parsed['unqualified']
        assert result(tmp_path, plan)['hdr_tonemap_defects'] > 0


def test_complete_synthetic_multiple_processes(tmp_path, plan):
    req = complete_requests(plan)
    batch(tmp_path, plan, req[:80])
    batch(tmp_path, plan, req[80:], '002')
    r = result(tmp_path, plan, '002')
    assert r['hdr_tonemap_defects'] == 0
    assert r['hdr_batch_cells'] == 21 * 8
    assert r['hdr_batch_pairs'] == 23 * 8
    assert r['hdr_owner_regressions_required'] == 0
    assert r['hdr_owner_regressions_measured'] == 0
    assert r['hdr_owner_regressions_missing'] == 0
    assert r['hdr_defect_7_owner_regressions'] == 0
    assert not (tmp_path / 'proof.txt').exists()


@pytest.mark.parametrize('forged_engine_verdict', [False, True])
def test_owner_cases_not_measured_by_complete_regional_set(tmp_path, plan, forged_engine_verdict):
    cases = hdr.contract(ROOT)['plan']['owner_regression_cases']
    plan['plan']['owner_regression_cases'] = cases
    assert len(cases) == 5
    path = batch(tmp_path, plan, complete_requests(plan))
    if forged_engine_verdict:
        with (path / 'engine.log').open('a') as stream:
            stream.write('owner_case=0\nhdr_defect_7_owner_regressions=0\n'
                         'hdr_owner_regressions_measured=5\nhdr_owner_regressions_missing=0\n')
        rehash(path)
    r = result(tmp_path, plan)
    assert r['hdr_batch_quality_bad'] == 0
    assert r['hdr_batch_missing'] == 0
    assert r['hdr_batch_errors'] == 0
    assert r['hdr_batch_cells'] == 21 * 8
    assert r['hdr_batch_pairs'] == 23 * 8
    assert r['hdr_owner_regressions_required'] == len(cases)
    assert r['hdr_owner_regressions_measured'] == 0
    assert r['hdr_owner_regressions_missing'] == len(cases)
    assert r['hdr_defect_7_owner_regressions'] == 1
    assert r['hdr_tonemap_defects'] == 1
    diagnostics = json.loads((tmp_path / 'measurements.json').read_text())['owner_regressions']
    assert diagnostics['required'] == diagnostics['missing'] == cases
    assert diagnostics['measured'] == []
    assert diagnostics['findings'] == [
        {'case': case, 'reason': 'no semantic ROI or comparable sequence in regional manifests'}
        for case in cases]
    assert not (tmp_path / 'proof.txt').exists()


@pytest.mark.parametrize('owner_cases', [False, True])
def test_current_missing_reports_owner_cases(tmp_path, plan, owner_cases):
    if owner_cases:
        plan = hdr.contract(ROOT)
    cases = plan['plan'].get('owner_regression_cases', [])
    r = result(tmp_path, plan)
    assert r['hdr_owner_regressions_required'] == len(cases)
    assert r['hdr_owner_regressions_measured'] == 0
    assert r['hdr_owner_regressions_missing'] == len(cases)
    assert r['hdr_defect_7_owner_regressions'] == int(owner_cases)
    assert r['hdr_tonemap_defects'] == 1 + int(owner_cases)
    assert r['hdr_batch_error_detail'] == 'current_batch_missing'
    diagnostics = json.loads((tmp_path / 'measurements.json').read_text())['owner_regressions']
    assert diagnostics['missing'] == cases
    assert [finding['case'] for finding in diagnostics['findings']] == cases


def test_partial_red(tmp_path, plan):
    batch(tmp_path, plan, [('legacy', 0)])
    assert result(tmp_path, plan)['hdr_tonemap_defects'] > 0


def test_legacy_interior_cannot_cover_sage_hut(tmp_path, plan):
    requests = [(view, hour) for view, hour in complete_requests(plan)
                if view != 'synthetic-sage-hut']
    batch(tmp_path, plan, requests)
    r = result(tmp_path, plan)
    measured = json.loads((tmp_path / 'measurements.json').read_text())
    assert measured['errors'] == []
    assert measured['missing'] == measured['sky_missing'] == measured['interior_missing'] == []
    assert measured['hut_missing'] == sorted(plan['hours'])
    legacy = [row for row in measured['pairs'] if row['view'] == 'legacy']
    assert {row['hour'] for row in legacy} == set(plan['hours'])
    assert all(row['sky_pm'] == 0 and row['on'] == row['off'] for row in legacy)
    assert r['hdr_batch_missing'] == len(plan['hours'])
    assert r['hdr_tonemap_defects'] > 0


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
                              'hut_missing': ('synthetic_sage_hut', ':0', ':300'),
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


@pytest.mark.parametrize('view', ['synthetic_sage_hut', 'training_start'])
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


@pytest.mark.parametrize('scope', ['within', 'between'])
def test_raw_settings_change_rejected_with_unchanged_effective_settings(tmp_path, plan, scope):
    requests = complete_requests(plan)
    if scope == 'between':
        batch(tmp_path, plan, requests[:80])
        path = batch(tmp_path, plan, requests[80:], name='002')
        suffixes = ('start', 'end')
    else:
        path = batch(tmp_path, plan, requests)
        suffixes = ('end',)
    for suffix in suffixes:
        (path / ('settings-' + suffix + '.ini')).write_text('synthetic-render-setting=9\n')
    m = json.loads((path / 'manifest.json').read_text())
    m['provenance']['config_files']['settings.ini'] = hdr.sha(path / 'settings-start.ini')
    hdr.dump(path / 'manifest.json', m)
    rehash(path)
    assert result(tmp_path, plan, path.name)['hdr_tonemap_defects'] > 0


@pytest.mark.parametrize('suffix', ['start', 'end'])
def test_raw_settings_snapshot_required_even_with_recorded_hash(tmp_path, plan, suffix):
    path = batch(tmp_path, plan, complete_requests(plan))
    (path / ('settings-' + suffix + '.ini')).unlink()
    rehash(path)
    assert result(tmp_path, plan)['hdr_tonemap_defects'] > 0


def test_raw_settings_hash_must_match_provenance(tmp_path, plan):
    path = batch(tmp_path, plan, complete_requests(plan))
    m = json.loads((path / 'manifest.json').read_text())
    m['provenance']['config_files']['settings.ini'] = 'f' * 64
    hdr.dump(path / 'manifest.json', m)
    assert result(tmp_path, plan)['hdr_tonemap_defects'] > 0


def test_other_raw_config_files_participate_in_compatibility(tmp_path, plan):
    requests = complete_requests(plan)
    batch(tmp_path, plan, requests[:80])
    path = batch(tmp_path, plan, requests[80:], name='002')
    for suffix in ('start', 'end'):
        config = path / ('config-' + suffix) / 'files/display-settings.json'
        config.parent.mkdir(parents=True)
        config.write_text('{"setting":9}')
    m = json.loads((path / 'manifest.json').read_text())
    m['provenance']['config_files']['files/display-settings.json'] = hdr.sha(config)
    hdr.dump(path / 'manifest.json', m)
    rehash(path)
    assert result(tmp_path, plan, '002')['hdr_tonemap_defects'] > 0


def test_replacing_empty_crash_does_not_erase_raw_config_incompatibility(tmp_path, plan):
    path = batch(tmp_path, plan, [('swamp-start', 0)], crash=1)
    for p in (path / 'captures').rglob('*'):
        if p.is_file():
            p.unlink()
    (path / 'engine.log').write_text('early crash\n')
    for suffix in ('start', 'end'):
        (path / ('settings-' + suffix + '.ini')).write_text('different-config=1\n')
    m = json.loads((path / 'manifest.json').read_text())
    m['provenance']['config_files']['settings.ini'] = hdr.sha(path / 'settings-start.ini')
    hdr.dump(path / 'manifest.json', m)
    rehash(path)
    batch(tmp_path, plan, complete_requests(plan), '002', replaces=['001:swamp-start:0=swamp-dock1'])
    assert result(tmp_path, plan, '002')['hdr_tonemap_defects'] > 0


def temporal_owner_row(actor=10012, on_white=(9, 11)):
    row = {'actor': actor, 'view_hour': 'village1-eco-blue-h12',
           'roi_exclusive': [10, 20, 30, 40], 'samples': []}
    for arm, whites in (('recharged', on_white), ('origine-lumiere', (8, 12))):
        for i, white in enumerate(whites):
            row['samples'].append({'arm': arm, 'image': f'{arm}/{i}', 'visible_sprites': 1,
                'stats': {'white': white, 'nearwhite': white + 20, 'clipped': 40,
                          'detail': 8, 'flat': .1, 'hue_bins': [1] * 12}})
    return row


def test_owner_temporal_success_judges_reported_brightness_with_attribution_limit():
    judgment = hdr.owner_sequence_judgment(temporal_owner_row(), 2)
    assert judgment['measured'] and judgment['photometric_passed']
    assert judgment['status'] == 'passed'
    assert 'background' in judgment['limitation']
    assert judgment['bounds']['white']['on_mean'] == 10


@pytest.mark.parametrize('on_white', [(0, 0), (0, 9), (15, 16)])
def test_owner_temporal_mean_detects_loss_and_excess_despite_overlap(on_white):
    judgment = hdr.owner_sequence_judgment(temporal_owner_row(on_white=on_white), 2)
    assert judgment['measured'] and not judgment['photometric_passed']
    assert judgment['status'] == 'failed'
    assert any('white' in failure for failure in judgment['failures'])


@pytest.mark.parametrize('fault', ['absent', 'duplicate', 'invisible', 'nan', 'no_off_white', 'no_roi'])
def test_owner_temporal_unqualified_stays_unjudged(fault):
    row = temporal_owner_row()
    if fault == 'absent':
        row['samples'].pop()
    elif fault == 'duplicate':
        row['samples'][0]['image'] = row['samples'][1]['image']
    elif fault == 'invisible':
        row['samples'][0]['visible_sprites'] = 0
    elif fault == 'nan':
        row['samples'][0]['stats']['detail'] = float('nan')
    elif fault == 'no_off_white':
        for sample in row['samples'][2:]:
            sample['stats']['white'] = 0
    elif fault == 'no_roi':
        row.pop('roi_exclusive')
    judgment = hdr.owner_sequence_judgment(row, 2)
    assert judgment['status'] == 'not_judged' and not judgment.get('measured')


def test_owner_measured_failure_is_distinct_from_missing_and_passed():
    expected = hdr.contract(ROOT)
    observation = {'batch': 'synthetic', 'selected': [('village1-eco-blue', 12)], 'temporal': 2,
                   'diagnostic': {'schema': 1, 'errors': [], 'regions': [
                       temporal_owner_row(actor, (0, 0)) for actor in (10012, 10013)]}}
    metrics, diagnostic = hdr.owner_regressions(expected, [observation])
    assert metrics['hdr_owner_regressions_measured'] == 1
    assert metrics['hdr_owner_regressions_failed'] == 1
    assert metrics['hdr_owner_regressions_missing'] == 4
    assert metrics['hdr_owner_regressions_passed'] == 0
    assert metrics['hdr_defect_7_owner_regressions'] == 1
    assert len(diagnostic['failed']) == 1
    observation['selected'] = [('another-view', 12)]
    metrics, _ = hdr.owner_regressions(expected, [observation])
    assert metrics['hdr_owner_regressions_measured'] == 0
    observation['selected'] = [('village1-eco-blue', 12)]
    observation['diagnostic']['errors'] = ['incompatible provenance']
    metrics, _ = hdr.owner_regressions(expected, [observation])
    assert metrics['hdr_owner_regressions_measured'] == 0


@pytest.mark.parametrize('metric,value', [('clipped', 41), ('detail', 7), ('flat', .2)])
def test_owner_temporal_preserves_detail_and_limits_excess(metric, value):
    row = temporal_owner_row()
    for sample in row['samples'][:2]:
        sample['stats'][metric] = value
    judgment = hdr.owner_sequence_judgment(row, 2)
    assert judgment['measured'] and judgment['status'] == 'failed'
    assert any(metric in failure for failure in judgment['failures'])


def test_owner_temporal_cannot_combine_partial_actor_cells():
    expected = hdr.contract(ROOT)
    rows = [temporal_owner_row(actor) for actor in (10012, 10013)]
    rows[1]['view_hour'] = 'village1-eco-blue-h18'
    observation = {'batch': 'synthetic', 'selected': [('village1-eco-blue', 12), ('village1-eco-blue', 18)],
                   'temporal': 2, 'diagnostic': {'schema': 1, 'errors': [], 'regions': rows}}
    metrics, _ = hdr.owner_regressions(expected, [observation])
    assert metrics['hdr_owner_regressions_measured'] == 0
    assert metrics['hdr_owner_regressions_missing'] == 5


@pytest.mark.parametrize('failed_actor,failed_hour', [(None, None), (10012, 12), (10013, 18)])
def test_owner_eco_success_requires_every_actor_and_hour(failed_actor, failed_hour):
    expected = hdr.contract(ROOT)
    rows = []
    for hour in (12, 18):
        for actor in (10012, 10013):
            fail = (actor, hour) == (failed_actor, failed_hour)
            row = temporal_owner_row(actor, (0, 0) if fail else (9, 11))
            row['view_hour'] = f'village1-eco-blue-h{hour}'
            rows.append(row)
    observation = {'batch': 'synthetic', 'selected': [('village1-eco-blue', 12), ('village1-eco-blue', 18)],
                   'temporal': 2, 'diagnostic': {'schema': 1, 'errors': [], 'regions': rows}}
    metrics, diagnostics = hdr.owner_regressions(expected, [observation])
    assert metrics['hdr_owner_regressions_measured'] == 1
    assert metrics['hdr_owner_regressions_missing'] == 4
    assert metrics['hdr_owner_regressions_failed'] == int(failed_actor is not None)
    assert metrics['hdr_owner_regressions_passed'] == int(failed_actor is None)
    assert len(diagnostics['passed']) == int(failed_actor is None)
    assert metrics['hdr_defect_7_owner_regressions'] == 1  # four unrelated cases absent
    # The eco-only synthetic contract can pass; no unconditional missing guard.
    expected['plan']['owner_regression_cases'] = [expected['plan']['owner_regression_cases'][1]]
    metrics, _ = hdr.owner_regressions(expected, [observation])
    assert metrics['hdr_defect_7_owner_regressions'] == int(failed_actor is not None)


@pytest.mark.parametrize('view', ['village1-eco-blue', 'explicit-eco-replacement'])
def test_owner_absent_entire_selected_hour_blocks_success(view):
    expected = hdr.contract(ROOT)
    rows = [temporal_owner_row(actor) for actor in (10012, 10013)]
    for row in rows:
        row['view_hour'] = view + '-h12'
    observation = {'batch': 'synthetic', 'selected': [(view, 12), (view, 18)], 'temporal': 2,
                   'diagnostic': {'schema': 1, 'errors': [], 'regions': rows}}
    metrics, diagnostic = hdr.owner_regressions(expected, [observation])
    assert metrics['hdr_owner_regressions_passed'] == 0
    assert metrics['hdr_owner_regressions_measured'] == 0
    finding = next(row for row in diagnostic['findings'] if 'observations' in row)
    assert ['synthetic', view + '-h18'] in [list(cell) for cell in finding['expected_cells']]


def inject_synthetic_owner_regions(monkeypatch, regions):
    """Aggregation fixture only: raw-source reconstruction has separate tests."""
    original = hdr.read_batch
    def read(path, expected, measurer):
        record = original(path, expected, measurer)
        record['values']['refset_temporal_samples'] = '2'
        record['owner_regions'] = {'schema': 1, 'errors': [], 'regions': regions.get(record['id'], [])}
        return record
    monkeypatch.setattr(hdr, 'read_batch', read)


@pytest.mark.parametrize('kind', ['absent_target', 'failed_source', 'incompatible'])
def test_eco_replacement_cannot_erase_region_or_failure(tmp_path, monkeypatch, kind):
    plan = hdr.contract(ROOT)
    view = 'village1-eco-blue'
    target = 'village1-out' if kind == 'absent_target' else view
    old = batch(tmp_path, plan, [(view, 12)], name='001')
    new = batch(tmp_path, plan, [(target, 12)], name='002', replaces=[f'001:{view}:12={target}'])
    rows_old = [temporal_owner_row(actor, (0, 0) if kind == 'failed_source' else (9, 11))
                for actor in (10012, 10013)]
    rows_new = [] if kind == 'absent_target' else [temporal_owner_row(actor) for actor in (10012, 10013)]
    if kind == 'incompatible':
        for suffix in ('start', 'end'):
            (new / f'props-{suffix}.txt').write_text((new / f'props-{suffix}.txt').read_text().replace(
                '[debug.opengoal.rt.intensity]: [1]', '[debug.opengoal.rt.intensity]: [2]'))
        rehash(new)
    inject_synthetic_owner_regions(monkeypatch, {'001': rows_old, '002': rows_new})
    metrics = result(tmp_path, plan, '002')
    diagnostic = json.loads((tmp_path / 'measurements.json').read_text())
    reason = {'absent_target': 'loses measurable eco actors', 'failed_source': 'cannot erase measured eco defect',
              'incompatible': 'eco replacement binary/config incompatible'}[kind]
    assert any(reason in error for error in diagnostic['errors'])
    assert metrics['hdr_owner_regressions_passed'] == int(kind == 'absent_target')
    owner = diagnostic['owner_regressions']
    assert any(row['batch'] == '001' for row in owner['regional_observations'] + owner['unselected_regional_observations'])


def test_duplicate_eco_cells_cannot_increment_passed(tmp_path, monkeypatch):
    plan = hdr.contract(ROOT)
    view = 'village1-eco-blue'
    for name in ('001', '002'):
        batch(tmp_path, plan, [(view, 12)], name=name)
    inject_synthetic_owner_regions(monkeypatch, {
        name: [temporal_owner_row(actor) for actor in (10012, 10013)] for name in ('001', '002')})
    metrics = result(tmp_path, plan, '002')
    diagnostic = json.loads((tmp_path / 'measurements.json').read_text())
    assert any('duplicate view/hour' in error for error in diagnostic['errors'])
    assert metrics['hdr_owner_regressions_passed'] == metrics['hdr_owner_regressions_measured'] == 0


def test_eco_early_crash_can_be_explicitly_replaced(tmp_path, monkeypatch):
    plan = hdr.contract(ROOT)
    view = 'village1-eco-blue'
    path = batch(tmp_path, plan, [(view, 12), (view, 18)], crash=1)
    for p in (path / 'captures').rglob('*'):
        if p.is_file():
            p.unlink()
    (path / 'engine.log').write_text('process aborted before first capture\n')
    rehash(path)
    batch(tmp_path, plan, [(view, 12), (view, 18)], name='002',
          replaces=[f'001:{view}:{hour}={view}' for hour in (12, 18)])
    rows = []
    for hour in (12, 18):
        for actor in (10012, 10013):
            row = temporal_owner_row(actor)
            row['view_hour'] = f'{view}-h{hour}'
            rows.append(row)
    inject_synthetic_owner_regions(monkeypatch, {'002': rows})
    metrics = result(tmp_path, plan, '002')
    diagnostic = json.loads((tmp_path / 'measurements.json').read_text())
    assert diagnostic['errors'] == []
    assert metrics['hdr_owner_regressions_passed'] == 1
    assert metrics['hdr_owner_regressions_missing'] == 4


def temporal_particle_batch(root, plan, mutate=lambda case, sample, options: None, *, name='001', hours=(12, 18), modern=True):
    """Synthetic temporal dates, never an execution proof."""
    path = batch(root, plan, [('village1-eco-blue', hour) for hour in hours], name=name)
    lines, count = [], 0
    capture_frames = {}
    for line in (path / 'engine.log').read_text().splitlines():
        if not line.startswith('REFSET effective '):
            lines.append(line)
            continue
        prefix, encoded = line.split(' options=', 1)
        case = prefix.split('case=', 1)[1]
        source = path / 'captures' / (case + '.png')
        sidecar = source.with_suffix('.png.provenance.txt').read_text()
        repin = 200 + count * 100
        for sample in range(2):
            sample_case = case + (f'-t{sample:02}' if sample else '')
            target = path / 'captures' / (sample_case + '.png')
            target.write_bytes(source.read_bytes())
            age = (sample + 1) * 12 - 1
            if sample == 0:
                arm, stem = case.split('/')
                hour = int(stem.rsplit('-h', 1)[1])
                phase = 2 if arm == 'recharged' else 3
                capture_frames[f'hdr_village1_eco_blue_h{hour}_p{phase}_cap_lf'] = repin + age
            target.with_suffix('.png.provenance.txt').write_text(
                sidecar.replace('case=' + case, 'case=' + sample_case)
                .replace('capture_lf=100', 'capture_lf=' + str(repin + age)))
            options = json.loads(encoded)
            options['temporal'] = dict(samples=2, sample=sample, spacing_lf=12,
                                       particle_step='once-per-logic-frame')
            if modern:
                options['temporal'].update(particle_repin_lf=repin, particle_age=age)
            mutate(case, sample, options)
            lines.append('REFSET effective case=' + sample_case + ' options=' + json.dumps(options))
            count += 1
    lines += ['refset_temporal_samples=2', f'refset_temporal_captured={count}',
              f'refset_captured={count}', f'refset_probe_frames={count}']
    lines += [f'{key}={frame}' for key, frame in capture_frames.items()]
    (path / 'engine.log').write_text('\n'.join(lines) + '\n')
    rehash(path)
    return path


def test_temporal_particle_dates_are_not_configuration(tmp_path, plan):
    path = temporal_particle_batch(tmp_path, plan)
    before = hdr.sha(path / 'engine.log')
    parsed = hdr.read_batch(path / 'manifest.json', plan, stats)
    first, second = [parsed['pairs'][('village1-eco-blue', hour)]['options'] for hour in (12, 18)]
    assert first == second
    assert first[0]['temporal'] == dict(samples=2, sample=0, spacing_lf=12,
        particle_step='once-per-logic-frame', particle_age=11)
    assert hdr.sha(path / 'engine.log') == before
    result(tmp_path, plan)
    assert json.loads((tmp_path / 'measurements.json').read_text())['errors'] == []


@pytest.mark.parametrize('fault', ['age', 'repin', 'partial', 'mixed', 'bool', 'float', 'negative', 'unknown_in_sequence'])
def test_temporal_particle_metadata_invalid(tmp_path, plan, fault):
    def mutate(case, sample, options):
        if sample != 1:
            return
        temporal = options['temporal']
        if fault == 'age': temporal['particle_age'] += 1
        elif fault == 'repin': temporal['particle_repin_lf'] += 1
        elif fault == 'partial': temporal.pop('particle_age')
        elif fault == 'mixed':
            temporal.pop('particle_age'); temporal.pop('particle_repin_lf')
        elif fault == 'bool': temporal['particle_age'] = True
        elif fault == 'float': temporal['particle_repin_lf'] = float(temporal['particle_repin_lf'])
        elif fault == 'negative': temporal['particle_repin_lf'] = -1
        elif fault == 'unknown_in_sequence': temporal['unknown_setting'] = 1
    path = temporal_particle_batch(tmp_path, plan, mutate)
    with pytest.raises(ValueError, match='temporal'):
        hdr.read_batch(path / 'manifest.json', plan, stats)


@pytest.mark.parametrize('change', ['render', 'unknown_temporal'])
def test_temporal_real_configuration_difference_kept(tmp_path, plan, change):
    def mutate(case, sample, options):
        if case.endswith('h18'):
            if change == 'render': options['output']['exposure'] = 2
            else: options['temporal']['unknown_setting'] = 2
    temporal_particle_batch(tmp_path, plan, mutate)
    result(tmp_path, plan)
    assert any('effective rendering configuration incompatible' in error
               for error in json.loads((tmp_path / 'measurements.json').read_text())['errors'])


def test_old_temporal_metadata_cannot_match_new(tmp_path, plan):
    old = temporal_particle_batch(tmp_path, plan, name='001', hours=(12,), modern=False)
    new = temporal_particle_batch(tmp_path, plan, name='002', hours=(18,))
    a = hdr.read_batch(old / 'manifest.json', plan, stats)
    b = hdr.read_batch(new / 'manifest.json', plan, stats)
    assert a['pairs'][('village1-eco-blue', 12)]['options'] != b['pairs'][('village1-eco-blue', 18)]['options']
    result(tmp_path, plan, '002')
    assert any('effective rendering configuration incompatible' in error
               for error in json.loads((tmp_path / 'measurements.json').read_text())['errors'])


def portal_region_sources(root, mutate=lambda witness: None):
    """Sealed synthetic bytes, with broad halo and separate projected disc."""
    images, lines = {}, []
    for arm, start in (('recharged', 100), ('origine-lumiere', 200)):
        for sample in range(2):
            frame = start + 12 * sample
            case = f'{arm}/village1-warp-h18' + (f'-t{sample:02}' if sample else '')
            rel = 'captures/' + case + '.png'
            path = root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(f'synthetic portal frame {frame}'.encode())
            (root / (rel + '.provenance.txt')).write_text(
                f'case={case}\ncapture_lf={frame}\npng={hdr.fnv(path)}\n')
            images[rel] = {'sha256': hdr.sha(path), 'stats': {'width': 320, 'height': 180}}
            lines.append(f'REFSET sample case={case} layer=historical chain_lf={frame} anchor_lf=88')
            for disc in (False, True):
                w = {'actor': 1395, 'lf': frame, 'texture': 'effects/harddot' if disc else 'effects/bigpuff',
                     'render_mode': 3 if disc else 1, 'supported': True, 'passed': True,
                     'roi': [20 + sample, 30, 40 + sample, 50] if disc else [1, 2, 300, 170]}
                if disc:
                    w['layer'] = 'portal_disc'
                    mutate(w)
                lines.append('HDR-OWNER-SPRITE ' + json.dumps(w))
    (root / 'engine.log').write_text('\n'.join(lines))
    return images


def portal_fake_measure(path, rect):
    return dict(white=10, nearwhite=30, clipped=40, luma=120, detail=8, flat=.1, saturation=.2)


def test_portal_disc_separate_common_roi_and_global_witnesses_retained(tmp_path):
    images = portal_region_sources(tmp_path)
    diagnostic = hdr.owner_regions(tmp_path, images, portal_fake_measure)
    assert diagnostic['errors'] == []
    global_row, disc = diagnostic['regions']
    assert global_row['roi_exclusive'] == [1, 2, 300, 170]
    assert len(global_row['witnesses']) == 8
    assert disc['layer'] == 'portal_disc'
    assert disc['roi_exclusive'] == [20, 30, 41, 50]
    assert len(disc['witnesses']) == len(disc['samples']) == 4
    assert {s['sha256'] for s in disc['samples']} == {i['sha256'] for i in images.values()}
    assert hdr.owner_sequence_judgment(disc, 2)['status'] == 'passed'


@pytest.mark.parametrize('change', [dict(actor=10012), dict(texture='effects/harddot3D'),
                                    dict(texture='other/harddot'), dict(texture=None),
                                    dict(render_mode=1), dict(render_mode='3')])
def test_portal_disc_wrong_attribution_explicit_error(tmp_path, change):
    images = portal_region_sources(tmp_path, lambda w: w.update(change))
    diagnostic = hdr.owner_regions(tmp_path, images, portal_fake_measure)
    assert any('invalid portal_disc provenance' in e for e in diagnostic['errors'])
    assert not any(r.get('layer') == 'portal_disc' for r in diagnostic['regions'])


@pytest.mark.parametrize('change', ['sidecar_missing', 'sidecar_wrong', 'invisible', 'unsupported', 'layer_absent'])
def test_portal_disc_missing_invalid_or_invisible_not_judged(tmp_path, change):
    def mutate(w):
        if change == 'invisible':
            w['passed'] = False
        if change == 'unsupported':
            w['supported'] = False
        if change == 'layer_absent':
            w.pop('layer')
    images = portal_region_sources(tmp_path, mutate)
    sidecar = tmp_path / (next(iter(images)) + '.provenance.txt')
    if change == 'sidecar_missing':
        sidecar.unlink()
    if change == 'sidecar_wrong':
        sidecar.write_text(sidecar.read_text().replace('capture_lf=100', 'capture_lf=999'))
    diagnostic = hdr.owner_regions(tmp_path, images, portal_fake_measure)
    rows = [r for r in diagnostic['regions'] if r.get('layer') == 'portal_disc']
    assert not rows or hdr.owner_sequence_judgment(rows[0], 2)['status'] == 'not_judged'
    if change.startswith('sidecar'):
        assert diagnostic['errors']


@pytest.mark.parametrize('white', [(9, 11), (0, 0)])
def test_portal_disc_photometry_is_partial_and_eco_judgment_unchanged(white):
    expected = hdr.contract(ROOT)
    eco = [temporal_owner_row(actor) for actor in (10012, 10013)]
    observation = {'batch': 'synthetic', 'temporal': 2, 'selected': [('village1-eco-blue', 12)],
                   'diagnostic': {'schema': 1, 'errors': [], 'regions': eco}}
    before, _ = hdr.owner_regressions(expected, [observation])
    disc = temporal_owner_row(1395, white)
    disc.update(layer='portal_disc', view_hour='village1-warp-h18')
    observation['selected'].append(('village1-warp', 18))
    observation['diagnostic']['regions'].append(disc)
    after, details = hdr.owner_regressions(expected, [observation])
    assert after == {**before, 'hdr_owner_regressions_failed': before['hdr_owner_regressions_failed'] + int(white == (0, 0))}
    finding = next(f for f in details['findings'] if f['case'].startswith('warp gate'))
    assert finding['status'] == ('failed' if white == (0, 0) else 'not_judged')
    assert finding['case'] in details['missing']
    assert finding['case'] not in details['passed']
    assert finding['observations'][0]['status'] == ('passed' if white == (9, 11) else 'failed')


@pytest.mark.parametrize('white', [(9, 11), (0, 0)])
def test_portal_partial_failure_stays_missing_and_preserves_defect(white):
    case = 'warp gate violet ecrase ON'
    expected = {'plan': {'owner_regression_cases': [case]}}
    disc = temporal_owner_row(1395, white)
    disc.update(layer='portal_disc', view_hour='village1-warp-h18')
    observation = {'batch': 'synthetic', 'temporal': 2, 'selected': [('village1-warp', 18)],
                   'diagnostic': {'schema': 1, 'errors': [], 'regions': [disc]}}
    metrics, details = hdr.owner_regressions(expected, [observation])
    assert metrics['hdr_owner_regressions_failed'] == int(white == (0, 0))
    assert metrics['hdr_owner_regressions_missing'] == 1
    assert metrics['hdr_owner_regressions_measured'] == metrics['hdr_owner_regressions_passed'] == 0
    assert metrics['hdr_defect_7_owner_regressions'] == 1
    assert details['failed'] == ([case] if white == (0, 0) else [])


@pytest.mark.parametrize('excess_flat', [False, True])
def test_portal_no_off_whites_preserves_partial_flat_judgment_and_eco_guard(excess_flat):
    case = 'warp gate violet ecrase ON'
    expected = {'plan': {'owner_regression_cases': [case]}}
    disc = temporal_owner_row(1395, (0, 0))
    disc.update(layer='portal_disc', view_hour='village1-warp-h18')
    for sample in disc['samples']:
        sample['stats']['white'] = 0
        sample['stats']['nearwhite'] = 20
        sample['stats']['flat'] = .06 if excess_flat and sample['arm'] == 'recharged' else .05
    assert hdr.owner_sequence_judgment(disc, 2)['status'] == 'not_judged'
    assert hdr.owner_sequence_judgment(disc, 2)['reason'] == 'expected OFF whites not observed'
    observation = {'batch': 'synthetic', 'temporal': 2, 'selected': [('village1-warp', 18)],
                   'diagnostic': {'schema': 1, 'errors': [], 'regions': [disc]}}
    metrics, details = hdr.owner_regressions(expected, [observation])
    assert metrics['hdr_owner_regressions_failed'] == int(excess_flat)
    assert metrics['hdr_owner_regressions_missing'] == 1
    assert metrics['hdr_owner_regressions_measured'] == metrics['hdr_owner_regressions_passed'] == 0
    assert metrics['hdr_defect_7_owner_regressions'] == 1
    partial = details['findings'][0]['observations'][0]
    assert partial['measured'] is True
    assert partial['status'] == ('failed' if excess_flat else 'passed')
    assert partial['failures'] == (['flat: ON excess beyond observed OFF temporal envelope'] if excess_flat else [])
    eco = {**disc, 'actor': 10012, 'view_hour': 'village1-eco-blue-h12'}
    observation['selected'] = [('village1-eco-blue', 12)]
    observation['diagnostic']['regions'] = [eco, {**eco, 'actor': 10013}]
    expected['plan']['owner_regression_cases'] = ['eclairs des orbes eco bleue']
    metrics, details = hdr.owner_regressions(expected, [observation])
    assert metrics['hdr_owner_regressions_measured'] == metrics['hdr_owner_regressions_failed'] == 0
    assert metrics['hdr_owner_regressions_missing'] == 1
    assert all(row['status'] == 'not_judged' for row in details['findings'][0]['observations'])
