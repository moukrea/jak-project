#!/usr/bin/env bash
# Synchronise le miroir Linear toutes les 5 min : etats vers Linear, commentaires de l'owner vers le backlog.
cd "$(dirname "$0")/.." || exit 1
exec 9>.autoport/.linear_watch.lock; flock -n 9 || exit 0
echo $$ > .autoport/.linear_watch.pid; trap 'rm -f .autoport/.linear_watch.pid' EXIT
while true; do
  python3 .autoport/linear_sync.py >> .autoport/logs/linear_sync.txt 2>&1 || echo "$(date +%H:%M:%S) synchro en erreur" >> .autoport/logs/linear_sync.txt
  sleep 30
done
