#!/usr/bin/env bash
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
LOCK="$ROOT/.autoport/.deploy-in-progress"
if [ -e "$LOCK" ]; then
  python3 - "$LOCK" <<'PY'
import os,re,sys
p=sys.argv[1]
s=open(p).read();m=re.search(r'pid=(\d+)',s)
if not m: raise SystemExit('verrou sans PID: refus de le remplacer')
try: os.kill(int(m.group(1)),0)
except ProcessLookupError: os.unlink(p)
else: raise SystemExit('constructeur vivant: repack refusé')
PY
fi
(set -o noclobber; printf '%s pid=%s\n' "$0" "$$" > "$LOCK")
trap 'rm -f "$LOCK"' EXIT
cd "$ROOT/android"
./gradlew assembleJak1Debug -PslimIso=true -x :app:buildNativeLibs -x :app:configureNativeLibs </dev/null
