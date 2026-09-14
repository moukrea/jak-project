"""Exercise the production guard; every write and fake gk stays in tmp_path."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import time

import pytest

ACQUIS = Path(__file__).resolve().parents[2] / 'acquis'
GOOD = dict(fb_extra_passes_per_frame='0', fb_frames_measured='59',
            fb_ui_direct_frames='60', fb_pass_ends_no_invalidate_max='0',
            fb_ui_direct_blocked='-')


def journal(values=None, prefix=''):
    return ''.join(f'{prefix}{key}={value}\n' for key, value in (values or GOOD).items())


@pytest.fixture
def fixture_repo(tmp_path):
    subprocess.run(['git', 'init', '-q', str(tmp_path)], check=True)
    for directory in ('.autoport/acquis', '.autoport/reports/_acquis',
                      'build/game', 'game', 'common', 'android', 'goal_src'):
        (tmp_path / directory).mkdir(parents=True, exist_ok=True)
    for name in ('perf-fbo-passes.sh', '_lib.sh'):
        shutil.copy2(ACQUIS / name, tmp_path / '.autoport/acquis' / name)
    binary = tmp_path / 'build/game/gk'
    binary.write_text('#!/bin/sh\nprintf "fake gk unavailable\\n"\nexit 1\n')
    binary.chmod(0o755)
    # Isolate the common library's host build detection from unrelated real processes.
    fakebin = tmp_path / 'fakebin'
    fakebin.mkdir()
    pgrep = fakebin / 'pgrep'
    pgrep.write_text('#!/bin/sh\nexit 1\n')
    pgrep.chmod(0o755)
    old = time.time() - 60
    os.utime(binary, (old, old))
    log = tmp_path / '.autoport/reports/_acquis/perf-fbo-passes.log'
    log.write_text(journal())
    sha = hashlib.sha256(binary.read_bytes()).hexdigest()[:16]
    log.with_suffix('.stamp').write_text(sha + '|--portable|OG_RECHARGED=0 OG_HDR=0 OG_HDR_OUT=0\n')
    return tmp_path


def run(root, text=None, main=False):
    script = root / '.autoport/acquis/perf-fbo-passes.sh'
    log = root / '.autoport/reports/_acquis/perf-fbo-passes.log'
    if text is not None:
        log.write_text(text)
    command = ['bash', str(script), 'ignored-serial'] if main else [
        'bash', '-c', 'source "$1"; fbo_check_log "$2"', 'check', str(script), str(log)]
    env = {key: value for key, value in os.environ.items()
           if key not in {'ACQ_CACHE_TTL', 'ACQ_GK_ARGS', 'GIT_DIR', 'GIT_WORK_TREE'}}
    env['PATH'] = str(root / 'fakebin') + os.pathsep + env['PATH']
    return subprocess.run(command, cwd=root, env=env, text=True, capture_output=True, timeout=10)


@pytest.mark.parametrize('prefix', ['', '    4.423 ', ' 4.423 [24:05:634] [info] ',
                                     '09-14 12:22:33.456 123 456 I GK_STDOUT: '])
def test_delivered_and_prefixes(fixture_repo, prefix):
    assert run(fixture_repo, journal(prefix=prefix), main=True).returncode == 0


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


@pytest.mark.parametrize('fault', ['missing-log', 'missing-binary', 'missing-stamp',
                                  'sha-mismatch', 'stale', 'future', 'newer-binary'])
def test_cache_fails_closed(fixture_repo, fault):
    log = fixture_repo / '.autoport/reports/_acquis/perf-fbo-passes.log'
    binary = fixture_repo / 'build/game/gk'
    if fault == 'missing-log':
        log.unlink()
    elif fault == 'missing-binary':
        binary.unlink()
    elif fault == 'missing-stamp':
        log.with_suffix('.stamp').unlink()
    elif fault == 'sha-mismatch':
        log.with_suffix('.stamp').write_text('wrong|--portable|\n')
    elif fault in {'stale', 'future'}:
        date = time.time() + (3600 if fault == 'future' else -3600)
        os.utime(log, (date, date))
    else:
        date = time.time() + 1
        os.utime(binary, (date, date))
    assert run(fixture_repo, main=True).returncode != 0


@pytest.mark.parametrize('path', ['game/new.cpp', 'common/new.h', 'goal_src/new.gc',
                                  'android/new.cpp', 'game/new.vert', 'android/new.frag'])
def test_newer_source_fails_closed(fixture_repo, path):
    source = fixture_repo / path
    source.write_text('fixture source\n')
    date = time.time() + 1
    os.utime(source, (date, date))
    assert run(fixture_repo, main=True).returncode != 0


def test_real_cache_renewal_with_fake_binary(fixture_repo):
    binary = fixture_repo / 'build/game/gk'
    binary.write_text("#!/bin/sh\n[ \"$OG_RECHARGED:$OG_HDR:$OG_HDR_OUT\" = 0:0:0 ] || exit 1\ncat <<'LOG'\n" + journal() + 'LOG\n')
    assert run(fixture_repo, main=True).returncode == 0
