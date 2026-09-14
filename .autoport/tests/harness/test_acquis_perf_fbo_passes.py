"""Production reader with proof bundles and fake producer isolated in tmp_path."""
import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import time

import pytest

AP = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('proof_names', AP / 'lib/impossible.py')
names = importlib.util.module_from_spec(spec)
spec.loader.exec_module(names)
GOOD = dict(fb_extra_passes_per_frame='0', fb_frames_measured='59',
            fb_ui_direct_frames='60', fb_pass_ends_no_invalidate_max='0',
            fb_ui_direct_blocked='-')


def journal(values=None, prefix=''):
    return ''.join(f'{prefix}{key}={value}\n' for key, value in (values or GOOD).items())


def artifact(root, kind):
    return root / '.autoport/reports/acquis-perf-fbo-passes' / names.arm_name(kind)


def reseal(root):
    raw = artifact(root, 'proof').read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    artifact(root, 'seal').write_text(
        f'seal_sha={digest}\nexit_sha={digest}\nseal_bytes={len(raw)}\nexit_bytes={len(raw)}\n')


def change(root, key, value):
    path = artifact(root, 'proof')
    fields = dict(line.split('=', 1) for line in path.read_text().splitlines())
    fields[key] = value
    path.write_text(''.join(f'{k}={v}\n' for k, v in fields.items()))
    reseal(root)


@pytest.fixture
def fixture_repo(tmp_path):
    subprocess.run(['git', 'init', '-q', str(tmp_path)], check=True)
    for directory in ('.autoport/acquis', '.autoport/lib', '.autoport/reports/acquis-perf-fbo-passes',
                      'build/game', 'game', 'common', 'android', 'goal_src', 'template', 'fakebin'):
        (tmp_path / directory).mkdir(parents=True, exist_ok=True)
    for relative in ('acquis/perf-fbo-passes.sh', 'lib/impossible.py', 'lib/verdict_sources.sh'):
        shutil.copy2(AP / relative, tmp_path / '.autoport' / relative)
    binary = tmp_path / 'build/game/gk'
    binary.write_text('#!/bin/sh\nexit 99\n')
    binary.chmod(0o755)
    producer = tmp_path / '.autoport/lib/proof_run.sh'
    producer.write_text('#!/bin/bash\n'
                        'echo "$*" >> producer.calls\n'
                        '[ "$*" = "acquis-perf-fbo-passes x86 --timeout 60" ] || exit 98\n'
                        '[ ! -f producer.fail ] || exit 7\n'
                        '[ ! -f producer.noop ] || exit 0\n'
                        'cp -p template/* .autoport/reports/acquis-perf-fbo-passes/\n')
    pgrep = tmp_path / 'fakebin/pgrep'
    pgrep.write_text('#!/bin/sh\necho 4242\nexit 0\n')
    pgrep.chmod(0o755)
    old = time.time() - 120
    for path in (binary, producer, *(tmp_path / '.autoport/acquis').glob('*'),
                 *(tmp_path / '.autoport/lib').glob('*')):
        os.utime(path, (old, old))
    sha = subprocess.check_output(['bash', '.autoport/lib/verdict_sources.sh',
                                  'acquis-perf-fbo-passes', 'sha'], cwd=tmp_path, text=True).strip()
    fields = dict(source='x86', binary='build/game/gk',
                  sha=hashlib.sha256(binary.read_bytes()).hexdigest()[:16],
                  started_at=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time() - 60)),
                  proof_run_id='fixture-run', crash='0', frames='60', verdict_sources_sha=sha,
                  proof_env_proc_read='1', proof_env_proc_obs_OG_RECHARGED='0',
                  proof_env_proc_obs_OG_HDR='0', proof_env_proc_obs_OG_HDR_OUT='0', **GOOD)
    artifact(tmp_path, 'engine').write_text(journal())
    artifact(tmp_path, 'proof').write_text(''.join(f'{k}={v}\n' for k, v in fields.items()))
    reseal(tmp_path)
    for kind in ('proof', 'engine', 'seal'):
        shutil.copy2(artifact(tmp_path, kind), tmp_path / 'template')
    return tmp_path


def run(root, text=None, main=False, ttl=None):
    script = root / '.autoport/acquis/perf-fbo-passes.sh'
    log = artifact(root, 'engine')
    if text is not None:
        log.write_text(text)
    command = ['bash', str(script), 'ignored-serial'] if main else [
        'bash', '-c', 'source "$1"; fbo_check_log "$2"', 'check', str(script), str(log)]
    env = {key: value for key, value in os.environ.items()
           if key not in {'ACQ_CACHE_TTL', 'GIT_DIR', 'GIT_WORK_TREE'}}
    if ttl is not None:
        env['ACQ_CACHE_TTL'] = ttl
    env['PATH'] = str(root / 'fakebin') + os.pathsep + env['PATH']
    return subprocess.run(command, cwd=root, env=env, text=True, capture_output=True, timeout=10)


def calls(root):
    path = root / 'producer.calls'
    return path.read_text().splitlines() if path.exists() else []


@pytest.mark.parametrize('prefix', ['', '    4.423 ', ' 4.423 [24:05:634] [info] ',
                                     '09-14 12:22:33.456 123 456 I GK_STDOUT: '])
def test_delivered_and_prefixes(fixture_repo, prefix):
    assert run(fixture_repo, journal(prefix=prefix)).returncode == 0


def test_fresh_proof_skips_producer_with_fake_daemon(fixture_repo):
    result = run(fixture_repo, main=True)
    assert result.returncode == 0, result.stderr
    assert 'fixture-run' in result.stderr
    assert calls(fixture_repo) == []


@pytest.mark.parametrize('key,value', [
    ('fb_extra_passes_per_frame', '1'), ('fb_pass_ends_no_invalidate_max', '1'),
    ('fb_frames_measured', '0'), ('fb_ui_direct_frames', '0'),
    ('fb_frames_measured', '-1'), ('fb_frames_measured', '1.0'),
    ('fb_frames_measured', '1garbage'), ('fb_frames_measured', ''),
    ('fb_frames_measured', '18446744073709551616'),
    ('fb_ui_direct_blocked', 'unknown'), ('fb_ui_direct_blocked', 'disarmed')])
def test_reject_bad_measurement(fixture_repo, key, value):
    assert run(fixture_repo, journal(dict(GOOD, **{key: value}))).returncode != 0


@pytest.mark.parametrize('key', list(GOOD))
def test_missing_key(fixture_repo, key):
    values = GOOD.copy()
    del values[key]
    assert run(fixture_repo, journal(values)).returncode != 0


@pytest.mark.parametrize('key', ['fb_extra_passes_per_frame', 'fb_pass_ends_no_invalidate_max'])
def test_previous_nonzero_cannot_be_hidden(fixture_repo, key):
    assert run(fixture_repo, journal(dict(GOOD, **{key: '1'})) + journal()).returncode != 0


@pytest.mark.parametrize('reason', ['no-split', 'hdr-chain', 'hdr-output', 'refset', 'msaa', 'no-window-depth'])
def test_known_fallback_needs_direct_population(fixture_repo, reason):
    values = dict(GOOD, fb_ui_direct_blocked=reason)
    assert run(fixture_repo, journal(values)).returncode == 0
    values['fb_ui_direct_frames'] = '0'
    result = run(fixture_repo, journal(values))
    assert result.returncode != 0
    assert reason in result.stderr


@pytest.mark.parametrize('crash', ['SIGSEGV', 'Fatal signal 6', 'Illegal instruction',
                                   'Assertion failed', 'terminate called'])
def test_crash(fixture_repo, crash):
    assert run(fixture_repo, journal() + crash + '\n').returncode != 0


@pytest.mark.parametrize('fault', ['absent', 'stale'])
def test_acquire_once(fixture_repo, fault):
    if fault == 'absent':
        artifact(fixture_repo, 'proof').unlink()
    else:
        change(fixture_repo, 'started_at', '2000-01-01T00:00:00Z')
    result = run(fixture_repo, main=True)
    assert result.returncode == 0, result.stderr
    assert len(calls(fixture_repo)) == 1


@pytest.mark.parametrize('mode', ['fail', 'noop'])
def test_failed_or_empty_producer(fixture_repo, mode):
    artifact(fixture_repo, 'proof').unlink()
    (fixture_repo / ('producer.' + mode)).touch()
    assert run(fixture_repo, main=True).returncode != 0
    assert len(calls(fixture_repo)) == 1


@pytest.mark.parametrize('fault', ['seal_sha', 'exit_sha', 'seal_bytes', 'exit_bytes',
    'missing-seal', 'sha', 'source', 'binary', 'future', 'log-future', 'empty-log',
    'newer-binary', 'verdict-sha', 'newer-verdict', 'counter-disagreement', 'reason-disagreement'])
def test_metadata_refuses_unchanged_old_files(fixture_repo, fault):
    root = fixture_repo
    (root / 'producer.noop').touch()
    if fault in {'seal_sha', 'exit_sha', 'seal_bytes', 'exit_bytes'}:
        path = artifact(root, 'seal')
        path.write_text(path.read_text().replace(fault + '=', fault + '=bad'))
    elif fault == 'missing-seal':
        artifact(root, 'seal').unlink()
    elif fault in {'sha', 'source', 'binary'}:
        change(root, fault, 'wrong')
    elif fault == 'future':
        change(root, 'started_at', '2099-01-01T00:00:00Z')
    elif fault in {'log-future', 'newer-binary', 'newer-verdict'}:
        path = (artifact(root, 'engine') if fault == 'log-future' else
                root / ('build/game/gk' if fault == 'newer-binary' else '.autoport/lib/verdict_sources.sh'))
        date = time.time() + 2
        os.utime(path, (date, date))
    elif fault == 'empty-log':
        artifact(root, 'engine').write_text('')
    elif fault == 'verdict-sha':
        change(root, 'verdict_sources_sha', 'wrong')
    else:
        change(root, 'fb_ui_direct_blocked' if fault == 'reason-disagreement' else 'fb_frames_measured', '999')
    assert run(root, main=True).returncode != 0
    assert len(calls(root)) == 1


@pytest.mark.parametrize('path', ['game/new.cpp', 'common/new.h', 'goal_src/new.gc',
                                  'android/new.cpp', 'game/new.vert', 'android/new.frag'])
def test_newer_source_fails_closed(fixture_repo, path):
    (fixture_repo / path).write_text('fixture source\n')
    (fixture_repo / 'producer.noop').touch()
    assert run(fixture_repo, main=True).returncode != 0
    assert len(calls(fixture_repo)) == 1


@pytest.mark.parametrize('key,value', [('crash', '1'), ('frames', '0'),
    ('proof_env_proc_read', '0'), ('proof_env_proc_obs_OG_RECHARGED', '1'),
    ('proof_env_proc_obs_OG_HDR', '1'), ('proof_env_proc_obs_OG_HDR_OUT', '1'),
    ('fb_extra_passes_per_frame', '1'), ('fb_ui_direct_blocked', 'disarmed')])
def test_fresh_engine_failure_never_retries(fixture_repo, key, value):
    if key in GOOD:
        artifact(fixture_repo, 'engine').write_text(journal(dict(GOOD, **{key: value})))
    change(fixture_repo, key, value)
    result = run(fixture_repo, main=True)
    assert result.returncode != 0
    assert calls(fixture_repo) == []


@pytest.mark.parametrize('ttl', ['0', '-1', 'invalid'])
def test_ttl_must_be_positive(fixture_repo, ttl):
    assert run(fixture_repo, main=True, ttl=ttl).returncode != 0
    assert len(calls(fixture_repo)) == 1
