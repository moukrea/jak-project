#!/usr/bin/env python3
"""Interactive Codex supervisor. The role stays in the shared contract."""
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / '.autoport'))
from lib import cli_backend, backend_control


def main():
    profile = cli_backend.codex_profile(ROOT)
    args = sys.argv[1:]
    check = '--check' in args
    if check:
        args.remove('--check')
    cmd = ['codex', *cli_backend.codex_options(ROOT, profile, supervisor=True)]
    # resume accepts an exact Codex UUID; never guess using --last across workers.
    if args[:1] == ['--resume']:
        if len(args) < 2 or args[1].startswith('-'):
            raise SystemExit('--resume exige un identifiant de session Codex explicite')
        cmd += ['resume', args[1], *args[2:]]
    else:
        cmd += args or ['Reprends le rôle superviseur. Lis le handoff et donne autoport status.']
    if check:
        print(json.dumps({'backend': 'codex', 'command': cmd}, ensure_ascii=False, indent=2))
        return
    backend_control.require('codex', ROOT)
    os.environ['AUTOPORT_BACKEND'] = 'codex'
    os.environ['AUTOPORT_ROLE'] = 'supervisor'
    for key in ('AUTOPORT_PHASE_ID', 'AUTOPORT_PHASE_VALIDATOR', 'CLAUDECODE',
                'CLAUDE_EFFORT', 'CLAUDE_CODE_SUBAGENT_MODEL'):
        os.environ.pop(key, None)
    os.chdir(ROOT)
    os.execvp(cmd[0], cmd)


if __name__ == '__main__':
    main()
