"""Provider handover revokes old launches and stops only the managed repository."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / '.autoport'))
from lib import backend_control


def load_switch():
    spec = importlib.util.spec_from_file_location('backend_switch', ROOT / '.autoport/backend_switch.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_selection_and_revocation_both_directions(tmp_path):
    (tmp_path / '.autoport').mkdir()
    for target, old in [('codex', 'claude'), ('claude', 'codex')]:
        backend_control.write({'backend': target, 'switching': True}, tmp_path)
        for name in ('claude', 'codex'):
            with pytest.raises(RuntimeError):
                backend_control.require(name, tmp_path)
        backend_control.write({'backend': target, 'switching': False}, tmp_path)
        backend_control.require(target, tmp_path)
        assert backend_control.default(tmp_path) == target
        with pytest.raises(RuntimeError):
            backend_control.require(old, tmp_path)


def test_switch_stops_managed_process_and_preserves_other_session(tmp_path, monkeypatch):
    ap = tmp_path / '.autoport'
    ap.mkdir()
    managed = ap / 'watch.py'
    managed.write_text('import time\ntime.sleep(90)\n')
    (tmp_path / 'other').mkdir()
    other = tmp_path / 'other/watch.py'
    other.write_text(managed.read_text())
    procs = [subprocess.Popen([sys.executable, str(p)], cwd=tmp_path)
             for p in (managed, other)]
    switch = load_switch()
    def snapshot(root, previous, target):
        assert not switch.alive(procs[0].pid, live[procs[0].pid])
        assert backend_control.read(root)['switching']
    monkeypatch.setattr(switch, 'snapshot', snapshot)
    try:
        live = switch.processes(tmp_path)
        assert procs[0].pid in live
        assert procs[1].pid not in live
        switch.perform('codex', tmp_path, start=False)
        procs[0].wait(timeout=5)
        assert procs[1].poll() is None
        assert backend_control.read(tmp_path)['backend'] == 'codex'
        assert not backend_control.read(tmp_path)['switching']
    finally:
        for p in procs:
            if p.poll() is None:
                p.terminate()
            p.wait(timeout=5)


def test_controller_is_not_killed_as_a_descendant_of_its_caller(tmp_path):
    # An old supervisor can directly parent the detached handover controller.
    (tmp_path / '.autoport').mkdir()
    script = tmp_path / '.autoport/watch.py'
    script.write_text('''import subprocess,sys
subprocess.run([sys.executable, '-c', "import sys,os; sys.path.insert(0, sys.argv[1]); import backend_switch; p=backend_switch.processes(__import__('pathlib').Path.cwd()); assert os.getppid() in p; assert os.getpid() not in p", sys.argv[1]], check=True)
''')
    subprocess.run([sys.executable, str(script), str(ROOT / '.autoport')],
                   cwd=tmp_path, check=True)
