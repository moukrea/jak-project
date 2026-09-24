"""harness-device-acquis-hardening : une garde commune, l'ordre par type, le terme ecarte, le delai."""
import ast
import importlib.util
from pathlib import Path
import re
import subprocess

import pytest

AP = Path(__file__).resolve().parents[2]
ROOT = AP.parent
ECO = AP / 'acquis/hud-eco-gauge.sh'
DEVICE_ACQUIS = ('hud-eco-gauge', 'perf-dma-chain-copies')
TYPES = ('blue', 'red', 'yellow')

spec = importlib.util.spec_from_file_location('acquis_budget', AP / 'lib/acquis_budget.py')
acquis_budget = importlib.util.module_from_spec(spec)
spec.loader.exec_module(acquis_budget)


# ------------------------------------------------------------------ 1. une seule garde scellee
def test_device_acquis_carry_no_copy_of_the_sealed_guard():
    # Les litteraux PROPRES a la garde appareil ; le sceau seul est aussi dans l'acquis x86
    # perf-fbo-passes (signale), qui n'est pas un acquis appareil.
    guard_literals = ('proof_binary_checked_before_measure', 'device_lib_md5', 'proof_binary_device_md5')
    for script in sorted((AP / 'acquis').glob('*.sh')):
        text = script.read_text()
        for literal in guard_literals:
            assert literal not in text, f'{script.name} recopie la garde ({literal})'
    guard = (AP / 'lib/acquis_device_guard.py').read_text()
    assert all(literal in guard for literal in guard_literals)
    for name in DEVICE_ACQUIS:
        text = (AP / 'acquis' / f'{name}.sh').read_text()
        assert 'lib/acquis_device.sh' in text and 'acq_device_guard ' in text
        assert f'--site {name}' in text


# ------------------------------------------------------------------ 4. l'ordre par type
def eco_log(windows, extra=None):
    """Journal synthetique : chaque fenetre = (types vus, images d'ordre, fautes d'ordre)."""
    cum = {f't12_n_{k}': 0 for k in TYPES}
    cum.update(t10_n=0, t10_order_bad=0, t10_park_ko=0, t10_cover=0)
    fixed = dict(code_rev=18, nuee_target_r_16th=755, t1_angle=0, t1_n=900, t7_quart=0, t7_n=900,
                 t7_base_ctrl=900, t2_tip=0, t2_n=900, t3_color=0, t3_n=900, t13_opaque=1,
                 **{f't12_box_16th_{k}': 755 for k in TYPES})
    fixed.update(extra or {})
    lines = []
    for seen, n, bad in windows:
        for k in seen:
            cum[f't12_n_{k}'] += n
        cum['t10_n'] += n
        cum['t10_cover'] += n
        cum['t10_order_bad'] += bad
        lines += [f'hud_gauge_{k}={v}' for k, v in {**cum, **fixed}.items()]
        lines.append('AUTOPORT-FRAMES n=60')
    return '\n'.join('09-24 15:54:18.424 I/GK_STDOUT(1): ' + line for line in lines) + '\n'


def judge(tmp_path, text):
    log = tmp_path / 'eco.log'
    log.write_text(text)
    run = subprocess.run(['bash', '-c', '. "$1"; eco_check_log "$2" x_', '_', str(ECO), str(log)],
                         cwd=ROOT, capture_output=True, text=True, timeout=60)
    out = dict(line.split('=', 1) for line in run.stdout.splitlines() if '=' in line)
    return run.returncode, out


GOOD = [(('blue',), 100, 0)] * 4 + [(('red',), 100, 0)] * 4 + [(('yellow',), 100, 0)] * 4


def test_order_per_type_negative_control(tmp_path):
    rc, out = judge(tmp_path, eco_log(GOOD))
    assert rc == 0 and out['x_faulty'] == 'none'
    assert out['x_terms_measured'] == out['x_terms_expected'] == '11'
    assert [out[f'x_order_n_{k}'] for k in TYPES] == ['400'] * 3


def test_order_fault_in_a_red_window_is_named_red(tmp_path):
    windows = list(GOOD)
    windows[5] = (('red',), 100, 1)
    rc, out = judge(tmp_path, eco_log(windows))
    assert rc == 1 and set(out['x_faulty'].split(',')) == {'order', 'order_red'}
    assert out['x_order_bad_red'] == '1' and out['x_order_bad_blue'] == '0'


def test_red_seen_only_in_mixed_windows_is_blind(tmp_path):
    windows = [w for w in GOOD if w[0] != ('red',)] + [(('blue', 'red'), 100, 0)] * 4
    rc, out = judge(tmp_path, eco_log(windows))
    assert rc == 1 and out['x_faulty'] == 'order_red'
    assert out['x_order_n_red'] == '0' and out['x_order_mixed_n'] == '400'


def test_fault_in_a_mixed_window_names_its_types(tmp_path):
    rc, out = judge(tmp_path, eco_log(GOOD + [(('red', 'yellow'), 100, 1)]))
    assert rc == 1 and out['x_faulty'] == 'order'
    assert out['x_order_mixed_types'] == 'red,yellow'


def test_probe_reset_is_counted_not_attributed(tmp_path):
    text = eco_log(GOOD).replace('hud_gauge_t10_n=800\n', 'hud_gauge_t10_n=5\n', 1)
    rc, out = judge(tmp_path, text)
    assert out['x_order_windows_reset'] != '0'


# ------------------------------------------------------------------ 5. le terme 13 ecarte
@pytest.mark.parametrize('value', [0, 1, 9])
def test_t13_is_excluded_and_published(tmp_path, value):
    rc, out = judge(tmp_path, eco_log(GOOD, {'t13_opaque': value}))
    assert rc == 0 and out['x_faulty'] == 'none'
    assert out['x_excluded'] == 't13_opaque' and out['x_excluded_t13_opaque'] == str(value)


# ------------------------------------------------------------------ 3. delai derive de la course
def item_proof(tmp_path, name, duration):
    d = tmp_path / 'reports' / f'acquis-{name}'
    d.mkdir(parents=True)
    (d / 'proof.txt').write_text(f'source=device\nduration_s={duration}\n')


@pytest.mark.parametrize('duration,declared,want', [
    (None, None, 600), ('96', 420, 660), ('700', None, 940), ('268', 240, 600),
    ('abc', None, 600), ('-5', 30, 600), ('900', 1200, 1440)])
def test_budget_is_derived_from_the_course(tmp_path, duration, declared, want):
    if duration is not None:
        item_proof(tmp_path, 'x', duration)
    items = {'acquis-x': {'proof_timeout': declared}} if declared is not None else {}
    got = acquis_budget.budget(tmp_path / 'acquis/x.sh', tmp_path, items.get)
    assert got['budget_s'] == want
    assert ('plancher %d s' % acquis_budget.FLOOR_S) in got['why']


def test_orchestrator_uses_the_derived_budget():
    tree = ast.parse((AP / 'orchestrator.py').read_text())
    hits = []
    for node in ast.walk(tree):
        if (isinstance(node, ast.Call) and getattr(node.func, 'attr', '') == 'run'
                and node.args and isinstance(node.args[0], ast.List)
                and any(isinstance(e, ast.Call) and getattr(e.func, 'id', '') == 'str'
                        and e.args and getattr(e.args[0], 'id', '') == 'script'
                        for e in node.args[0].elts)):
            timeout = [k.value for k in node.keywords if k.arg == 'timeout']
            hits.append(timeout)
    assert len(hits) == 1, 'porte des acquis introuvable ou dupliquee'
    assert hits[0] and not isinstance(hits[0][0], ast.Constant), 'delai des acquis code en dur'
    assert re.search(r'acquis_budget\.budget\(script,', (AP / 'orchestrator.py').read_text())
