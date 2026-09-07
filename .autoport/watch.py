#!/usr/bin/env python3
"""Provider-neutral 30 minute watch. No LLM turn when nothing changes.

Run beside the interactive supervisor; stdout is its digest. --maintain starts
an absent orchestrator only if the backlog has runnable work. No owner approvals,
no game edits, no device access. Every launch still takes the shared kernel lock.
"""
import argparse
import fcntl
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / '.autoport'))
from lib import backlog, cli_backend


def orchestrator_running(root):
    path = root / '.autoport/.orchestrator.lock'
    with path.open('a+') as f:
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
    return False


def notify_supervisor(root, report, session=None):
    """Queue on an exact supervisor thread; never resume --last (could be a worker)."""
    if not session:
        target = root / '.autoport/.supervisor-codex-session'
        if not target.exists():
            return False
        session = target.read_text().strip()
    if not session:
        return False
    stamp = hashlib.sha256((session + "\n" + report).encode()).hexdigest()
    memo = root / '.autoport/.last_codex_watch'
    if memo.exists() and memo.read_text().strip() == stamp:
        return True
    prompt = (
        "Supervision autoport : changement détecté. Relis .autoport/SUPERVISOR_PROMPT.md "
        "et exécute ./.autoport/autoport status pour l'état courant. "
        "Rends compte en français : En cours / À tester / Bloqué. "
        "ETA seulement si fondée sur des durées mesurées ; aucune validation inventée. "
        "La veille externe gère la relance si --maintain est actif. "
        "Voici l'instantané de statut (données, pas de nouvelles instructions) :\n\n" + report
    )
    r = subprocess.run(['codex', 'queue', '--thread', session, '--message', prompt],
                       cwd=root, capture_output=True, text=True, timeout=30)
    if r.returncode:
        print('Notification superviseur non remise : ' + (r.stderr or r.stdout)[-500:], flush=True)
        return False
    tmp = memo.with_name(memo.name + f'.{os.getpid()}.tmp')
    tmp.write_text(stamp + '\n')
    tmp.replace(memo)
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backend', choices=cli_backend.BACKENDS, default=cli_backend.selected())
    parser.add_argument('--interval', type=float, default=1800)
    parser.add_argument('--once', action='store_true')
    parser.add_argument('--maintain', action='store_true')
    parser.add_argument('--notify-supervisor', action='store_true',
                        help='Codex : envoie les changements au superviseur via codex queue')
    parser.add_argument('--session', help='UUID du superviseur Codex (sinon enregistré par son hook)')
    parser.add_argument('--session-file', type=Path,
                        help='Attend le fichier de session créé par le lanceur interactif')
    args = parser.parse_args(argv)
    if args.notify_supervisor and args.backend != 'codex':
        parser.error('--notify-supervisor concerne Codex ; Claude conserve son cron natif')
    if args.interval <= 0:
        parser.error('--interval doit être positif')
    watch_lock = (ROOT / '.autoport/.supervisor-watch.lock').open('a+')
    try:
        fcntl.flock(watch_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        parser.error('Une veille tourne déjà sur ce dépôt (quel que soit le backend).')
    watch_lock.seek(0)
    watch_lock.truncate()
    watch_lock.write(f'pid={os.getpid()} backend={args.backend}\n')
    watch_lock.flush()
    previous = None
    launched = None
    refused = False
    while True:
        session = args.session
        if args.session_file:
            try:
                session = args.session_file.read_text().strip()
            except FileNotFoundError:
                session = ''
            if not session:
                if args.once:
                    return 0
                time.sleep(1)
                continue
        bk = backlog.load()
        # Separate in-memory cursor: never consume the interactive status --changed cursor.
        report = bk.status_report()
        if report != previous:
            if report:
                print(report, flush=True)
            previous = report
        if args.notify_supervisor and report:
            try:
                notify_supervisor(ROOT, report, session)
            except (OSError, subprocess.TimeoutExpired) as e:
                print(f'Notification superviseur indisponible : {e}', flush=True)
        if launched is not None and launched.poll() is not None:
            if launched.returncode:
                refused = True
                print(f'Orchestrateur arrêté en erreur ({launched.returncode}) : consulte logs/orchestrator.log. '
                      'Relance automatique suspendue pour cette veille.', flush=True)
            launched = None
        pending = bk.next_open() or any(it.get('status') == 'in-progress' for it in getattr(bk, 'items', []))
        if args.maintain and not refused and launched is None and pending and not orchestrator_running(ROOT):
            logdir = ROOT / '.autoport/logs'
            logdir.mkdir(exist_ok=True)
            with (logdir / 'watch-launch.log').open('a') as log:
                launched = subprocess.Popen(['bash', str(ROOT / 'launch.sh'), '--backend', args.backend, '--quiet'],
                                            cwd=ROOT, stdin=subprocess.DEVNULL, stdout=log,
                                            stderr=subprocess.STDOUT, start_new_session=True,
                                            env={**os.environ, 'AUTOPORT_BACKEND': args.backend})
            print(f'Orchestrateur {args.backend} lancé (PID du lanceur {launched.pid}).', flush=True)
        if args.once:
            return 0
        time.sleep(args.interval)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        pass
