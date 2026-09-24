#!/usr/bin/env bash
# Synchronise le miroir Linear toutes les $LINEAR_WATCH_PERIOD_S s : etats vers Linear, commentaires de l'owner vers le backlog.
# LINEAR_WATCH_PERIOD_S est la SEULE source de la periode : le `sleep` la lit, ce texte et la ligne de
# demarrage du journal la citent. Ne jamais ecrire la periode en chiffres ailleurs (le 23/09, ce
# commentaire disait « 5 min » pendant que le code dormait 30 s). Porte : lib/census/
# harness-linear-watch-comment-matches-its-period.sh -> linear_watch_period_mismatch == 0.
LINEAR_WATCH_PERIOD_S=30
cd "$(dirname "$0")/.." || exit 1
exec 9>.autoport/.linear_watch.lock; flock -n 9 || exit 0
echo $$ > .autoport/.linear_watch.pid; trap 'rm -f .autoport/.linear_watch.pid' EXIT
echo "$(date +%H:%M:%S) veille Linear demarree : synchro toutes les $LINEAR_WATCH_PERIOD_S s" >> .autoport/logs/linear_sync.txt
while true; do
  python3 .autoport/linear_sync.py >> .autoport/logs/linear_sync.txt 2>&1 || echo "$(date +%H:%M:%S) synchro en erreur" >> .autoport/logs/linear_sync.txt
  sleep "$LINEAR_WATCH_PERIOD_S"
done
