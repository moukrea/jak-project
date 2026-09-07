"""Check the mobile launcher with a real pseudo-terminal, never a live model."""
import importlib.util
import io
import json
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import sys
import time

from test_cli_backend import load_watch

ROOT = Path(__file__).resolve().parents[3]


def test_launcher_keeps_keyboard_and_cleans_its_background_watch(tmp_path):
    shutil.copy2(ROOT/'run-codex.sh', tmp_path/'run-codex.sh')
    ap = tmp_path/'.autoport'
    ap.mkdir()
    fake = ap/'fake.py'
    fake.write_text('''import os,sys,time
from pathlib import Path
root=Path(__file__).parent
if '--watch' in sys.argv:
    (root/'watch.pid').write_text(str(os.getpid()))
    assert not os.isatty(0)
    print('BACKGROUND_ONLY', flush=True)
    time.sleep(60)
else:
    assert os.isatty(0) and os.isatty(1)
    Path(os.environ['AUTOPORT_SUPERVISOR_SESSION_FILE']).write_text('fresh-supervisor')
    while not (root/'watch.pid').exists(): time.sleep(.01)
    print('CODEX_READY', flush=True)
    assert input() == 'hello from mobile'
    sys.exit(7)
''')
    (ap/'supervisor.sh').write_text('#!/bin/bash\nexec python3 .autoport/fake.py "$@"\n')
    master, slave = pty.openpty()
    proc = subprocess.Popen(['bash',str(tmp_path/'run-codex.sh')], cwd='/tmp',
                            stdin=slave,stdout=slave,stderr=slave)
    os.close(slave)
    output = b''
    try:
        deadline = time.monotonic()+8
        while b'CODEX_READY' not in output and time.monotonic()<deadline:
            if select.select([master],[],[],.1)[0]:
                output += os.read(master,4096)
        assert b'CODEX_READY' in output, output
        assert b'BACKGROUND_ONLY' not in output
        os.write(master,b'hello from mobile\n')
        assert proc.wait(timeout=8) == 7
        watch_pid = int((ap/'watch.pid').read_text())
        assert not Path(f'/proc/{watch_pid}').exists()
        assert not list((ap/'logs').glob('supervisor-session-*'))
    finally:
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=8)
        os.close(master)


def test_watch_waits_for_this_supervisor_before_touching_backlog(tmp_path, monkeypatch):
    w = load_watch()
    (tmp_path/'.autoport').mkdir()
    session_file = tmp_path/'session'
    session_file.write_text('')
    monkeypatch.setattr(w, 'ROOT', tmp_path)
    def forbidden():
        raise AssertionError('No backlog access before the interactive session starts')
    monkeypatch.setattr(w.backlog, 'load', forbidden)
    assert w.main(['--backend','codex','--session-file',str(session_file),'--once','--maintain']) == 0


def test_supervisor_hook_registers_the_launch_specific_session(tmp_path, monkeypatch):
    spec = importlib.util.spec_from_file_location('codex_hook_test', ROOT/'.autoport/codex/hook.py')
    hook = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(hook)
    (tmp_path/'.autoport').mkdir()
    session_file = tmp_path/'session'
    monkeypatch.setattr(hook,'ROOT',tmp_path)
    monkeypatch.setenv('AUTOPORT_ROLE','supervisor')
    monkeypatch.delenv('AUTOPORT_PHASE_ID',raising=False)
    monkeypatch.setenv('AUTOPORT_SUPERVISOR_SESSION_FILE',str(session_file))
    monkeypatch.setattr(sys,'argv',['hook.py','SessionStart'])
    monkeypatch.setattr(sys,'stdin',io.StringIO(json.dumps({'session_id':'fresh-uuid'})))
    assert hook.main() == 0
    assert session_file.read_text().strip() == 'fresh-uuid'
    assert (tmp_path/'.autoport/.supervisor-codex-session').read_text().strip() == 'fresh-uuid'
