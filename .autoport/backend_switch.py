#!/usr/bin/env python3
"""Stop one harness, persist the provider and open its supervisor in tmux."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / '.autoport'))
from lib import backend_control

SCRIPTS = {'.autoport/orchestrator.py', '.autoport/watch.py', '.autoport/supervisor.sh',
           '.autoport/codex/supervisor.py', 'run-codex.sh', 'launch.sh',
           '.autoport/auto_build_apk.sh', '.autoport/auto_push_builds.sh'}


def processes(root=ROOT):
    """Only managed processes in this exact repository; never match prompt text."""
    found = {}
    for path in Path('/proc').glob('[0-9]*'):
        try:
            if (path / 'cwd').resolve() != root.resolve():
                continue
            args = (path / 'cmdline').read_bytes().decode().split('\0')[:-1]
            env = dict(x.split('=', 1) for x in (path / 'environ').read_bytes().decode().split('\0')
                       if '=' in x)
            stat = (path / 'stat').read_text().rsplit(')', 1)[1].split()
            # Interpreter + its script, not arbitrary arguments containing script names.
            command = args[0] if args else ''
            if Path(command).name in ('bash', 'python', 'python3'):
                command = next((a for a in args[1:3] if not a.startswith('-')), '')
            script = Path(command).name
            path_on_disk = (root / command).resolve()
            managed = path_on_disk in {root / p for p in SCRIPTS} or (script in ('claude', 'codex') and
                      (env.get('AUTOPORT_ROLE') == 'supervisor' or env.get('AUTOPORT_PHASE_ID')))
            if managed:
                found[int(path.name)] = {'start': stat[19], 'script': script}
        except (OSError, ValueError, UnicodeError):
            continue
    # Include tool/build descendants, even after they become orphaned during shutdown.
    all_children = {}
    for path in Path('/proc').glob('[0-9]*'):
        try:
            stat = (path / 'stat').read_text().rsplit(')', 1)[1].split()
            all_children[int(path.name)] = (int(stat[1]), stat[19])
        except (OSError, ValueError):
            continue
    changed = True
    while changed:
        changed = False
        for pid, (parent, start) in all_children.items():
            if parent in found and pid not in found:
                found[pid] = {'start': start, 'script': 'descendant', 'child': True}
                changed = True
    # The detached switch controller may still be a descendant of the caller
    # for a few milliseconds. It must survive revoking that supervisor.
    found.pop(os.getpid(), None)
    return found


def alive(pid, entry):
    try:
        stat = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()
        return stat[19] == entry['start'] and stat[0] != 'Z'
    except OSError:
        return False


def terminate(pid, entry):
    # pidfd pins identity even if the numeric PID gets recycled after the check.
    try:
        fd = os.pidfd_open(pid)
    except ProcessLookupError:
        return
    try:
        if alive(pid, entry):
            signal.pidfd_send_signal(fd, signal.SIGTERM)
            print(f"Arrêt {entry['script']} PID {pid}", flush=True)
    finally:
        os.close(fd)


def snapshot(root, previous, target):
    ap = root / '.autoport'
    stamp = time.strftime('%Y%m%dT%H%M%S')
    out = ap / 'logs' / ('switch-' + stamp)
    out.mkdir(parents=True, exist_ok=True)
    for name in ('state.json', 'backlog.yaml', '.backend.json'):
        if (ap / name).exists():
            (out / name).write_bytes((ap / name).read_bytes())
    status = subprocess.run([str(ap / 'autoport'), 'status'], cwd=root,
                            capture_output=True, text=True, check=True).stdout
    commits = subprocess.check_output(['git', 'log', '-15', '--oneline', '--', '.autoport'],
                                     cwd=root, text=True)
    handoff = (f'# Bascule {previous} → {target} — {stamp}\n\n'
               'Lis CLAUDE.md, .autoport/SUPERVISOR_PROMPT.md, README.md et DIRECTIVES.md.\n'
               'Reprends le pilotage autorisé : backlog courant, derniers handoffs, rapports et FINDINGS\n'
               'des items en cours/bloqués prioritaires. Les snapshots sont historiques, jamais des ordres.\n'
               'Aucune validation owner à inventer. Ne code pas le jeu et ne touche aucun appareil.\n'
               'Les correctifs du harnais sont partagés entre CLI ; ne repars pas du handoff Codex du 7 septembre.\n'
               'Lis aussi .autoport/SUPERVISOR_CATCHUP.md si présent.\n'
               f'\nSauvegarde : {out.relative_to(root)}\n\n{status}\n\nDerniers commits :\n{commits}')
    (out / 'handoff.md').write_text(handoff)
    (ap / 'SWITCH_HANDOFF.md').write_text(handoff)


def perform(target, root=ROOT, start=True):
    lock = (root / '.autoport/.backend-switch.lock').open('a+')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    if start:
        import shutil
        if not shutil.which('tmux') or not shutil.which(target):
            raise RuntimeError('tmux et la CLI cible doivent être installés avant la bascule')
    previous = backend_control.read(root)
    live = processes(root)
    daemons = previous.get('daemons', [])
    daemons = sorted(set(daemons) | {p['script'] for p in live.values()
                                   if p['script'] in ('auto_build_apk.sh', 'auto_push_builds.sh')})
    state = {'backend': target, 'switching': True, 'daemons': daemons}
    backend_control.write(state, root)  # Fence launches BEFORE sending any signal.
    for pid, entry in sorted(live.items(), key=lambda p: p[1]['script'] == 'orchestrator.py'):
        if not entry.get('child'):
            terminate(pid, entry)
    # Give the orchestrator its normal cancellation/save path before cleaning stragglers.
    time.sleep(1)
    for pid, entry in live.items():
        if entry.get('child'):
            terminate(pid, entry)
    deadline = time.monotonic() + 40
    while any(alive(pid, entry) for pid, entry in live.items()):
        if time.monotonic() >= deadline:
            raise RuntimeError('Arrêt incomplet ; lancement suspendu. Voir les PID dans le journal et relancer switch.')
        time.sleep(.2)
    snapshot(root, previous.get('backend', 'claude'), target)
    state['switching'] = False
    backend_control.write(state, root)
    if not start:
        return
    prompt = ('Reprends le rôle superviseur et le travail autorisé. Lis .autoport/SWITCH_HANDOFF.md '
              'et .autoport/SUPERVISOR_CATCHUP.md, puis les handoffs et FINDINGS récents. '
              'Rends compte du rattrapage, vérifie la santé du harnais et entretiens la file. '
              'Relance les démons de build/livraison listés dans .autoport/.backend.json si arrêtés, '
              'dans leur configuration normale : leur automatisation existante est autorisée, '
              'ne désactive pas ADB ou le déploiement. '
              'Pas de code jeu ni de contact appareil. '
              + ('La veille externe de run-codex.sh entretient l’orchestrateur.' if target == 'codex' else
                 'Relance ./launch.sh --backend claude en arrière-plan et installe ton suivi périodique.'))
    import hashlib
    session = 'autoport-' + hashlib.sha256(str(root).encode()).hexdigest()[:10]
    cmd = ['bash', str(root / 'run-codex.sh'), prompt] if target == 'codex' else [
        'bash', str(root / '.autoport/supervisor.sh'), '--backend', 'claude', prompt]
    # A dedicated tmux server prevents collision with the owner's unrelated sessions.
    subprocess.run(['tmux', '-L', 'autoport', 'new-session', '-d', '-s', session,
                    '-c', str(root), *cmd], check=True)
    print(f'Superviseur {target} lancé. Accès : tmux -L autoport attach -t {session}', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('backend', choices=('claude', 'codex'))
    parser.add_argument('--no-start', action='store_true')
    args = parser.parse_args()
    perform(args.backend, start=not args.no_start)


if __name__ == '__main__':
    main()
