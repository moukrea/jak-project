"""Switch providers on a real PTY, keeping the keyboard and no tmux dependency."""
import json
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]


def test_provider_switch_keeps_same_terminal_and_keyboard(tmp_path):
    ap = tmp_path / '.autoport'
    (ap / 'lib').mkdir(parents=True)
    for name in ('supervisor_terminal.py', 'lib/backend_control.py'):
        shutil.copy2(ROOT / '.autoport' / name, ap / name)
    (ap / 'fake.py').write_text('''import os,sys
assert os.isatty(0) and os.isatty(1)
print('READY-' + sys.argv[1], flush=True)
assert input() == ('switch' if sys.argv[1] == 'codex' else 'bye')
''')
    for path, backend in [(tmp_path / 'run-codex.sh', 'codex'), (ap / 'supervisor.sh', 'claude')]:
        path.write_text(f'#!/bin/bash\nexec {sys.executable} .autoport/fake.py {backend}\n')
    state = ap / '.backend.json'
    state.write_text(json.dumps({'backend': 'codex', 'generation': 1}))
    master, slave = pty.openpty()
    proc = subprocess.Popen([sys.executable, str(ap / 'supervisor_terminal.py')],
                            cwd=tmp_path, stdin=slave, stdout=slave, stderr=slave)
    os.close(slave)
    output = b''
    def wait_for(marker):
        nonlocal output
        deadline = time.monotonic() + 8
        while marker not in output and time.monotonic() < deadline:
            if select.select([master], [], [], .1)[0]:
                output += os.read(master, 4096)
        assert marker in output, output
    try:
        wait_for(b'READY-codex')
        original = json.loads((ap / '.supervisor-terminal.json').read_text())
        state.write_text(json.dumps({'backend': 'claude', 'generation': 2}))
        os.write(master, b'switch\n')
        wait_for(b'READY-claude')
        assert json.loads((ap / '.supervisor-terminal.json').read_text()) == original
        os.write(master, b'bye\n')
        assert proc.wait(timeout=8) == 0
        assert not (ap / '.supervisor-terminal.json').exists()
    finally:
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=5)
        os.close(master)
