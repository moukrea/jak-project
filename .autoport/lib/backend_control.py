"""Persistent provider selection and revocation of obsolete harness launches."""
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read(root=ROOT):
    try:
        return json.loads((Path(root) / '.autoport/.backend.json').read_text())
    except FileNotFoundError:
        return {}


def default(root=ROOT):
    return read(root).get('backend', 'claude')


def require(backend, root=ROOT):
    state = read(root)
    if state and (state.get('switching') or state.get('backend') != backend):
        raise RuntimeError('Harnais révoqué pour %s ; backend actif : %s. Utilise autoport switch %s.'
                           % (backend, state.get('backend'), backend))


def write(state, root=ROOT):
    path = Path(root) / '.autoport/.backend.json'
    tmp = path.with_name(path.name + f'.{os.getpid()}.tmp')
    tmp.write_text(json.dumps(state, indent=2) + '\n')
    tmp.replace(path)


if __name__ == '__main__':
    import sys
    if len(sys.argv) == 1:
        print(default())
    else:
        require(sys.argv[1])
