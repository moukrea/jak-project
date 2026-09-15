"""Exercise the production DMA reader with all artifacts and tools in tmp_path."""
import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import time

import pytest

AP = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('dma_proof_names', AP / 'lib/impossible.py')
names = importlib.util.module_from_spec(spec)
spec.loader.exec_module(names)
ID = 'acquis-perf-dma-chain-copies'
SCRIPT = 'acquis/perf-dma-chain-copies.sh'
BINARY = 'build-android/lib/arm64-v8a/libgk.so'
GOOD = dict(dma_chain_walks_per_frame='2', dma_chain_walks_total='120',
            dma_chain_frames_measured='60', dma_chain_attempts_measured='60',
            dma_chain_diagnostics='0', dma_chain_rejected='0',
            dma_chain_bytes_copied='131072', dma_chain_copy_mode='1')


def journal(values=None, prefix=''):
    values = GOOD if values is None else values
    return ''.join(f'{prefix}{key}={value}\n' for key, value in values.items())


def artifact(root, kind):
    return root / '.autoport/reports' / ID / names.arm_name(kind)


def reseal(root):
    raw = artifact(root, 'proof').read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    artifact(root, 'seal').write_text(
        f'seal_sha={digest}\nexit_sha={digest}\nseal_bytes={len(raw)}\nexit_bytes={len(raw)}\n')


def change(root, key, value):
    path = artifact(root, 'proof')
    lines = path.read_text().splitlines()
    feature = [line for line in lines if line.startswith('FEATURE ')]
    fields = dict(line.split('=', 1) for line in lines if not line.startswith('FEATURE '))
    fields[key] = value
    path.write_text(''.join(f'{k}={v}\n' for k, v in fields.items()) + '\n'.join(feature) + '\n')
    reseal(root)


@pytest.fixture
def fixture_repo(tmp_path):
    subprocess.run(['git', 'init', '-q', str(tmp_path)], check=True)
    for directory in ('.autoport/acquis', '.autoport/lib', f'.autoport/reports/{ID}',
                      'build-android/lib/arm64-v8a', 'game', 'common', 'android', 'goal_src',
                      'template', 'fakebin'):
        (tmp_path / directory).mkdir(parents=True, exist_ok=True)
    for relative in (SCRIPT, 'lib/impossible.py', 'lib/verdict_sources.sh'):
        shutil.copy2(AP / relative, tmp_path / '.autoport' / relative)
    binary = tmp_path / BINARY
    binary.write_bytes(b'isolated Android library fixture\n')
    producer = tmp_path / '.autoport/lib/proof_run.sh'
    producer.write_text('#!/bin/bash\n'
                        'echo "$*" >> producer.calls\n'
                        f'[ "$*" = "{ID} device --timeout 60" ] || exit 98\n'
                        '[ ! -f producer.fail ] || exit 7\n'
                        '[ ! -f producer.noop ] || exit 0\n'
                        f'cp -p template/* .autoport/reports/{ID}/\n')
    producer.chmod(0o755)
    adb = tmp_path / 'fakebin/adb'
    adb.write_text('#!/bin/sh\necho forbidden >> adb.calls\nexit 97\n')
    adb.chmod(0o755)
    old = time.time() - 120
    for path in (binary, producer, *(tmp_path / '.autoport/acquis').glob('*'),
                 *(tmp_path / '.autoport/lib').glob('*')):
        os.utime(path, (old, old))
    verdict = subprocess.check_output(['bash', '.autoport/lib/verdict_sources.sh', ID, 'kv'],
                                     cwd=tmp_path, text=True)
    md5 = hashlib.md5(binary.read_bytes()).hexdigest()
    fields = dict(source='device', binary=BINARY,
                  sha=hashlib.sha256(binary.read_bytes()).hexdigest()[:16],
                  started_at=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time() - 60)),
                  proof_run_id='fixture-run', crash='0', frames='60',
                  dma_acquis_defects='0', proof_census_present='1', proof_census_rc='0',
                  proof_census_keys='9', dma_acquis_cases='100', dma_acquis_passed='100',
                  dma_acquis_failed='0', dma_acquis_bench_rc='0', dma_acquis_live_rc='0',
                  dma_acquis_context_rc='0',
                  serial='USB123', device_serial='USB123', proof_binary_serial='USB123',
                  device_model='HONOR_fixture', local_lib_md5=md5, device_lib_md5=md5,
                  proof_binary_local_md5=md5, proof_binary_device_md5=md5,
                  proof_binary_gate_ran='1', proof_binary_checked_before_measure='1', proof_binary_rc='0', **GOOD)
    artifact(tmp_path, 'engine').write_text(
        f'FEATURE {ID} armed=1 hits=60\n' + journal())
    artifact(tmp_path, 'proof').write_text(
        ''.join(f'{k}={v}\n' for k, v in fields.items()) + verdict +
        f'FEATURE {ID} armed=1 hits=60\n')
    reseal(tmp_path)
    for kind in ('proof', 'engine', 'seal'):
        shutil.copy2(artifact(tmp_path, kind), tmp_path / 'template')
    yield tmp_path
    assert not (tmp_path / 'adb.calls').exists(), 'guard contacted adb directly'


def run(root, text=None, mode='log', ttl=None):
    script = root / '.autoport' / SCRIPT
    log = artifact(root, 'engine')
    if text is not None:
        log.write_text(text)
    command = (['bash', str(script), 'USB123'] if mode == 'main' else
               ['bash', '-c', f'source "$1"; dma_check_{mode} "$2"',
                'check', str(script), str(log)])
    env = {key: value for key, value in os.environ.items()
           if key not in {'ACQ_CACHE_TTL', 'GIT_DIR', 'GIT_WORK_TREE', 'ANDROID_SERIAL'}}
    if ttl is not None:
        env['ACQ_CACHE_TTL'] = ttl
    env['PATH'] = str(root / 'fakebin') + os.pathsep + env['PATH']
    return subprocess.run(command, cwd=root, env=env, text=True, capture_output=True, timeout=10)


def calls(root):
    path = root / 'producer.calls'
    return path.read_text().splitlines() if path.exists() else []


@pytest.mark.parametrize('prefix', ['', '    4.423 ', ' 4.423 [24:05:634] [info] ',
                                     '09-14 12:22:33.456 123 456 I GK_STDOUT: '])
def test_good_log(fixture_repo, prefix):
    result = run(fixture_repo, journal(prefix=prefix))
    assert result.returncode == 0, result.stderr


def test_valid_cache_skips_producer(fixture_repo):
    result = run(fixture_repo, mode='proof')
    assert result.returncode == 0, result.stderr
    assert Path(result.stdout.strip()) == artifact(fixture_repo, 'engine').relative_to(fixture_repo)
    result = run(fixture_repo, mode='main')
    assert result.returncode == 0, result.stderr
    assert calls(fixture_repo) == []


@pytest.mark.parametrize('key,value', [
    ('dma_chain_walks_per_frame', '3'), ('dma_chain_walks_total', '119'),
    ('dma_chain_frames_measured', '0'), ('dma_chain_attempts_measured', '59'),
    ('dma_chain_diagnostics', '1'), ('dma_chain_rejected', '1'),
    ('dma_chain_bytes_copied', '0'), ('dma_chain_copy_mode', '0'),
    *[('dma_chain_frames_measured', value) for value in
      ('-1', '+60', '60.0', '6e1', '60garbage', '', '18446744073709551616')]])
def test_bad_measurement(fixture_repo, key, value):
    assert run(fixture_repo, journal(dict(GOOD, **{key: value}))).returncode != 0


@pytest.mark.parametrize('key', list(GOOD))
def test_missing_measurement(fixture_repo, key):
    values = GOOD.copy()
    del values[key]
    assert run(fixture_repo, journal(values)).returncode != 0


def test_empty_log(fixture_repo):
    assert run(fixture_repo, '').returncode != 0


@pytest.mark.parametrize('key', ['dma_chain_walks_per_frame', 'dma_chain_diagnostics',
                                 'dma_chain_rejected', 'dma_chain_copy_mode'])
def test_earlier_failure_cannot_be_hidden(fixture_repo, key):
    assert run(fixture_repo, journal(dict(GOOD, **{key: '3'})) + journal()).returncode != 0


@pytest.mark.parametrize('key', ['dma_chain_walks_total', 'dma_chain_frames_measured',
                                 'dma_chain_attempts_measured'])
def test_cumulative_decrease(fixture_repo, key):
    previous = dict(GOOD, **{key: str(int(GOOD[key]) + 1)})
    assert run(fixture_repo, journal(previous) + journal()).returncode != 0


@pytest.mark.parametrize('marker', ['A42-CHAIN-PRECOPY skip', 'A37-CHAIN-LOOP', 'A37-BUCKET-MALFORMED', 'SIGSEGV',
                                   'Fatal signal 4 (SIGILL)', 'segmentation fault',
                                   'Fatal signal 6', 'Illegal instruction', 'Assertion failed',
                                   'terminate called'])
def test_error_markers(fixture_repo, marker):
    assert run(fixture_repo, journal() + marker + '\n').returncode != 0


@pytest.mark.parametrize('fault', ['absent', 'stale'])
def test_acquire_once(fixture_repo, fault):
    if fault == 'absent':
        artifact(fixture_repo, 'proof').unlink()
    else:
        change(fixture_repo, 'started_at', '2000-01-01T00:00:00Z')
    assert run(fixture_repo, mode='proof').returncode == 2
    result = run(fixture_repo, mode='main')
    assert result.returncode == 0, result.stderr
    assert calls(fixture_repo) == [f'{ID} device --timeout 60']


@pytest.mark.parametrize('mode', ['fail', 'noop', 'malformed'])
def test_producer_failure_or_no_publication(fixture_repo, mode):
    artifact(fixture_repo, 'proof').unlink()
    if mode == 'malformed':
        (fixture_repo / 'template' / names.arm_name('proof')).write_text('not a proof\n')
    else:
        (fixture_repo / ('producer.' + mode)).touch()
    assert run(fixture_repo, mode='main').returncode != 0
    assert len(calls(fixture_repo)) == 1


@pytest.mark.parametrize('key,value', [
    ('sha', 'wrong'), ('source', 'x86'), ('binary', 'build/game/gk'),
    ('local_lib_md5', '0' * 32), ('device_lib_md5', '0' * 32),
    ('proof_binary_local_md5', '0' * 32), ('proof_binary_device_md5', '0' * 32),
    ('device_serial', 'OTHER'), ('proof_binary_serial', 'OTHER'),
    ('serial', '192.0.2.1:5555'), ('device_model', 'SHIELD'),
    ('proof_binary_gate_ran', '0'), ('proof_binary_checked_before_measure', '0'), ('proof_binary_rc', '1'),
    ('proof_run_id', ''), ('started_at', '2099-01-01T00:00:00Z'),
    ('verdict_sources_sha', 'wrong'), ('verdict_sources_count', '999'),
    ('verdict_criterion_sha', 'wrong'), ('verdict_acquis_sha', 'wrong'),
    ('verdict_acquis_count', '999'), ('dma_chain_walks_total', '122')])
def test_invalid_metadata_reacquires_and_rejects_noop(fixture_repo, key, value):
    change(fixture_repo, key, value)
    (fixture_repo / 'producer.noop').touch()
    assert run(fixture_repo, mode='proof').returncode == 2
    assert run(fixture_repo, mode='main').returncode != 0
    assert len(calls(fixture_repo)) == 1


@pytest.mark.parametrize('fault', ['seal_sha', 'exit_sha', 'seal_bytes', 'exit_bytes',
                                 'missing-seal', 'empty-log', 'log-future', 'newer-binary',
                                 'newer-verdict', 'newer-source', 'duplicate-proof-field'])
def test_invalid_artifacts(fixture_repo, fault):
    root = fixture_repo
    (root / 'producer.noop').touch()
    if fault in {'seal_sha', 'exit_sha', 'seal_bytes', 'exit_bytes'}:
        path = artifact(root, 'seal')
        path.write_text(path.read_text().replace(fault + '=', fault + '=bad'))
    elif fault == 'missing-seal':
        artifact(root, 'seal').unlink()
    elif fault == 'empty-log':
        artifact(root, 'engine').write_text('')
    elif fault == 'duplicate-proof-field':
        path = artifact(root, 'proof')
        path.write_text(path.read_text() + 'source=device\n')
        reseal(root)
    else:
        path = {'log-future': artifact(root, 'engine'), 'newer-binary': root / BINARY,
                'newer-verdict': root / '.autoport/lib/verdict_sources.sh',
                'newer-source': root / 'game/new.cpp'}[fault]
        if not path.exists():
            path.write_text('fixture source\n')
        future = time.time() + 2
        os.utime(path, (future, future))
    assert run(root, mode='main').returncode != 0
    assert len(calls(root)) == 1


@pytest.mark.parametrize('key,value', [('crash', '1'), ('frames', '0'),
    ('dma_chain_walks_per_frame', '3'), ('dma_chain_diagnostics', '1'),
    ('dma_chain_rejected', '1'), ('dma_chain_copy_mode', '0'),
    ('dma_chain_bytes_copied', '0')])
def test_measured_failure_never_retries(fixture_repo, key, value):
    if key in GOOD:
        artifact(fixture_repo, 'engine').write_text(
            f'FEATURE {ID} armed=1 hits=60\n' + journal(dict(GOOD, **{key: value})))
    change(fixture_repo, key, value)
    assert run(fixture_repo, mode='proof').returncode == 1
    assert run(fixture_repo, mode='main').returncode != 0
    assert calls(fixture_repo) == []


@pytest.mark.parametrize('ttl', ['0', '-1', 'invalid'])
def test_invalid_ttl(fixture_repo, ttl):
    (fixture_repo / 'producer.noop').touch()
    assert run(fixture_repo, mode='main', ttl=ttl).returncode != 0
    assert len(calls(fixture_repo)) == 1


def test_informative_sigill_is_not_a_crash(fixture_repo):
    assert run(fixture_repo, journal() + "CPU doesn't SIGILL on this instruction\n").returncode == 0


def test_window_bytes_can_decrease(fixture_repo):
    earlier = dict(GOOD, dma_chain_bytes_copied='262144')
    assert run(fixture_repo, journal(earlier) + journal()).returncode == 0


@pytest.mark.parametrize('feature', ['', f'FEATURE {ID} armed=0 hits=60',
    f'FEATURE {ID} armed=1 hits=-1', f'FEATURE {ID} armed=1 hits=18446744073709551616',
    'FEATURE another-item armed=1 hits=60'])
def test_invalid_feature_publication(fixture_repo, feature):
    path = artifact(fixture_repo, 'proof')
    path.write_text(path.read_text().replace(f'FEATURE {ID} armed=1 hits=60', feature))
    reseal(fixture_repo)
    assert run(fixture_repo, mode='proof').returncode == 2


@pytest.mark.parametrize('serial', ['192.0.2.1:5555', '192.0.2.1', 'usb_adb-tls-connect._tcp'])
def test_consistent_network_identity_still_rejected(fixture_repo, serial):
    for key in ('serial', 'device_serial', 'proof_binary_serial'):
        change(fixture_repo, key, serial)
    assert run(fixture_repo, mode='proof').returncode == 2


def test_different_usb_cache_does_not_acquire(fixture_repo):
    for key in ('serial', 'device_serial', 'proof_binary_serial'):
        change(fixture_repo, key, 'OTHERUSB')
    result = run(fixture_repo, mode='main')
    assert result.returncode == 0, result.stderr
    assert calls(fixture_repo) == []


@pytest.mark.parametrize('key,value', [('dma_acquis_defects', '1'),
    ('proof_census_present', '0'), ('proof_census_rc', '1'), ('proof_census_keys', '0'),
    ('dma_acquis_cases', '0'), ('dma_acquis_passed', '99'), ('dma_acquis_failed', '1'),
    ('dma_acquis_bench_rc', '1'), ('dma_acquis_live_rc', '1'), ('dma_acquis_context_rc', '1')])
def test_census_failure_never_retries(fixture_repo, key, value):
    change(fixture_repo, key, value)
    assert run(fixture_repo, mode='proof').returncode == 1
    assert run(fixture_repo, mode='main').returncode != 0
    assert calls(fixture_repo) == []
