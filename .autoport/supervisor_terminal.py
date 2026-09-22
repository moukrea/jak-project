#!/usr/bin/env python3
"""Keep the supervisor on the user's actual terminal across provider switches."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / '.autoport'))
from lib import backend_control


def main():
    if not os.isatty(0) or not os.isatty(1):
        raise SystemExit('Ouvre ./run-supervisor.sh dans un terminal interactif.')
    record = ROOT / '.autoport/.supervisor-terminal.json'
    identity = {'pid': os.getpid(),
                'start': Path(f'/proc/{os.getpid()}/stat').read_text().rsplit(')', 1)[1].split()[19],
                'tty': os.ttyname(0)}
    if record.exists():
        # UNE SEULE REGLE DE VIVACITE POUR TOUT LE DEPOT (lib/supervisor_alive.py). La copie
        # qui vivait ici lisait bien le starttime, mais elle prenait un ZOMBIE pour un
        # superviseur ouvert : `run-supervisor.sh` refusait alors de demarrer en accusant un
        # mort, et la file « retour owner » restait servie a personne.
        from lib import supervisor_alive
        vivant, releve = supervisor_alive.process_alive(str(record))
        if vivant:
            raise SystemExit('Un superviseur est déjà ouvert dans ' + releve['tty'])
        if releve['declared']:
            print('[superviseur] fichier de terminal perime (%s, pid %s) : ignore.'
                  % (releve['why'], releve['pid']))
    record.write_text(json.dumps(identity) + '\n')
    args = sys.argv[1:]
    try:
        while True:
            while backend_control.read().get('switching'):
                time.sleep(.2)
            state = backend_control.read()
            backend = state.get('backend', 'claude')
            command = (['bash', str(ROOT / 'run-codex.sh')] if backend == 'codex' else
                       ['bash', str(ROOT / '.autoport/supervisor.sh'), '--backend', backend])
            result = subprocess.run(command + args, cwd=ROOT)
            args = ['Reprends le rôle superviseur. Lis .autoport/SWITCH_HANDOFF.md et poursuis la reprise autorisée.']
            while backend_control.read().get('switching'):
                time.sleep(.2)
            current = backend_control.read()
            if (current.get('backend'), current.get('generation')) == (state.get('backend'), state.get('generation')):
                return result.returncode
    finally:
        if record.exists() and json.loads(record.read_text()).get('pid') == os.getpid():
            record.unlink()


if __name__ == '__main__':
    sys.exit(main())
