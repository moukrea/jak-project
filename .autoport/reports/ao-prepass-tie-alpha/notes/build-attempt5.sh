#!/usr/bin/env bash
set -euo pipefail
cd /home/emeric/code/jak-project
LOCK=/home/emeric/code/jak-project/.autoport/.deploy-in-progress
if [ -e "$LOCK" ]; then
  holder=$(sed -nE 's/.*pid=([0-9]+).*/\1/p' "$LOCK" | head -1)
  if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
    echo "Déploiement déjà tenu par PID $holder" >&2
    exit 3
  fi
  rm -f "$LOCK"
fi
(set -o noclobber; printf '%s pid=%s\n' "$0" "$$" > "$LOCK")
trap 'rm -f "$LOCK"' EXIT
export TMPDIR=/home/emeric/code/jak-project/.autoport/reports/ao-prepass-tie-alpha/notes/tmp-build
mkdir -p "$TMPDIR"
cmake --build build-android --target gk -j 3
cd android
./gradlew assembleJak1Debug
