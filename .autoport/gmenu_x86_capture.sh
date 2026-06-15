#!/usr/bin/env bash
# Capture OUR build-x86 progress menu at 2400x1080 (English) via the internal-res
# screenshot hook (MSAA>=2). Menu opened by activating the gk window (EWMH) and
# injecting START (uinput ENTER). Cycles BACK(E)->wait->START to collect multiple
# frozen-flythrough backgrounds for phase-matching the golden.
# Portable build => screenshots land in build-x86/game/OpenGOAL/jak1/screenshots.
# NEVER pgrep -f gk (matches the claude -p process) — only kills the PID it launches.
# Usage: bash .autoport/gmenu_x86_capture.sh <tag> [cycles]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

TAG="${1:-16x9}"; CYCLES="${2:-6}"
PY="$HOME/.venv/autoport/bin/python"
SHOTDIR="build-x86/game/OpenGOAL/jak1/screenshots"
OUTDIR="/tmp/gmenu-cap-$TAG"; LOG="/tmp/gmenu-x86-$TAG.log"
GK="build-x86/game/gk"

rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"
mkdir -p "$SHOTDIR"; rm -f "$SHOTDIR"/autoport_f*.png 2>/dev/null || true
: > "$LOG"

echo "== launching gk ($TAG) =="
DISPLAY=:0 XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.RKSTQ3 \
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
AUTOPORT_SHOT_EVERY=10 AUTOPORT_SHOT_START=2300 AUTOPORT_SHOT_W=2400 AUTOPORT_SHOT_H=1080 AUTOPORT_SHOT_MSAA=4 \
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
      -iso-data out/jak1/iso -- -boot -debug-mem > "$LOG" 2>&1 &
GKPID=$!; echo "  gk pid=$GKPID"
cleanup() {
  echo "== stopping gk pid=$GKPID =="
  kill -INT "$GKPID" 2>/dev/null || true; sleep 2
  kill -TERM "$GKPID" 2>/dev/null || true; sleep 1
  kill -KILL "$GKPID" 2>/dev/null || true; wait "$GKPID" 2>/dev/null || true
}
trap cleanup EXIT

echo "== waiting for title (logo-loop) =="
deadline=$(( $(date +%s) + 150 )); got=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  if ! kill -0 "$GKPID" 2>/dev/null; then echo "  gk EXITED early"; tail -15 "$LOG"; exit 1; fi
  grep -qE "link finish: logo-loop" "$LOG" 2>/dev/null && { got=1; break; }
  sleep 2
done
[ "$got" = 1 ] || { echo "  never reached logo-loop"; tail -20 "$LOG"; exit 1; }
echo "  title reached; waiting 5s then opening menu"
sleep 5

snap() {
  local pfx="$1"
  ls -t "$SHOTDIR"/autoport_f*.png 2>/dev/null | head -4 | while read -r f; do
    cp -f "$f" "$OUTDIR/${pfx}_$(basename "$f")" 2>/dev/null || true
  done
}

echo "== open menu (focus+START) + collect $CYCLES poses =="
for i in $(seq 1 "$CYCLES"); do
  "$PY" .autoport/xfocus_tap.py 28 >>"$LOG.focus" 2>&1   # START -> open menu
  sleep 4; snap "c${i}"
  echo "  cycle $i done"
  "$PY" .autoport/xfocus_tap.py 18 >>"$LOG.focus" 2>&1   # E=CIRCLE -> back to title
  sleep 3
done

echo "== harvest =="
echo "  shot total: $(ls "$SHOTDIR"/autoport_f*.png 2>/dev/null | wc -l)"
ls -la "$OUTDIR" | tail -10
echo "== focus log tail =="; tail -8 "$LOG.focus" 2>/dev/null
echo "== gk log tail =="; tail -4 "$LOG"
