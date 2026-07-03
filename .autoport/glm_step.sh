#!/usr/bin/env bash
# glm_step.sh — inject a cpad token sequence, screencapping after each step.
# Usage: glm_step.sh <tag> <token1> [token2 ...]   ("." = no input, just wait+cap)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TAG="$1"; shift
OUT=.autoport/reports/Glang-mixed
PACKAGE=org.opengoal.gk.jak1
SERIAL="${ANDROID_SERIAL:-eae4df44}"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
A(){ "$ADB" -s "$SERIAL" "$@"; }
inj(){ printf '%s' "$1" | A shell "run-as $PACKAGE sh -c 'cat > /data/data/$PACKAGE/files/cpad_inject'" >/dev/null 2>&1 || true; }
i=0
for tok in "$@"; do
  i=$((i+1))
  case "$tok" in
    .) ;;                       # wait+cap only
    -) inj "" ;;                # release
    *) inj "$tok"; sleep 0.4; inj "" ;;   # press then release
  esac
  sleep 1.4
  A exec-out screencap -p > "$OUT/$TAG-s$(printf '%02d' $i)-$tok.png" 2>/dev/null || true
done
A shell dumpsys window 2>/dev/null | grep -i mCurrentFocus
echo "done: $i steps -> $OUT/$TAG-sNN-*.png"
