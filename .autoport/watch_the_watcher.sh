#!/usr/bin/env bash
# The push watcher has died three times (API storm, unbound var, unknown). Keep it alive.
cd "$(dirname "$0")/.." || exit 1
while true; do
  if ! ps -eo args | grep -q '[a]uto_push_builds.sh'; then
    echo "$(date +%H:%M:%S) watcher was dead — respawning" >> .autoport/logs/auto_push_builds.txt
    setsid bash .autoport/auto_push_builds.sh </dev/null >/dev/null 2>&1 &
  fi
  sleep 120
done
