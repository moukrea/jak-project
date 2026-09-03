#!/usr/bin/env bash
# Dense x86 progress-menu pose capture for phase-matching the golden.
# The menu FREEZES the title-attract background at the START-press moment, so to
# sample diverse camera poses we: back fully to title (CIRCLE x2), wait a VARYING
# interval (camera advances along the attract path), then open the menu (START)
# and snapshot the frozen frame. Internal-res screenshot hook => 2400x1080.
# Bindings (game/system/hid/input_bindings.cpp): START=RETURN(28), CIRCLE=E(18).
# NEVER pgrep -f gk (matches the claude -p process). Only kills the PID it spawns.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

PY="$HOME/.venv/autoport/bin/python"
[ -x "$PY" ] || PY="python3"
SHOTDIR="build-x86/game/OpenGOAL/jak1/screenshots"
OUTDIR="/tmp/gmenu-dense"; LOG="/tmp/gmenu-dense.log"
GK="build-x86/game/gk"

rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"
mkdir -p "$SHOTDIR"; rm -f "$SHOTDIR"/autoport_f*.png 2>/dev/null || true
: > "$LOG"; : > "$LOG.focus"

echo "== launching gk =="
DISPLAY=:0 XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.RKSTQ3 \
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
AUTOPORT_SHOT_EVERY=6 AUTOPORT_SHOT_START=1500 AUTOPORT_SHOT_W=2400 AUTOPORT_SHOT_H=1080 AUTOPORT_SHOT_MSAA=4 \
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
      -iso-data out/jak1/iso -- -boot -debug-mem > "$LOG" 2>&1 &
GKPID=$!; echo "  gk pid=$GKPID"
cleanup() {
  echo "== stopping gk pid=$GKPID =="
  kill -INT "$GKPID" 2>/dev/null || true; sleep 2
  kill -KILL "$GKPID" 2>/dev/null || true; wait "$GKPID" 2>/dev/null || true
}
trap cleanup EXIT

echo "== waiting for title (logo-loop) =="
deadline=$(( $(date +%s) + 160 )); got=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  kill -0 "$GKPID" 2>/dev/null || { echo "  gk EXITED early"; tail -15 "$LOG"; exit 1; }
  grep -qE "link finish: logo-loop" "$LOG" 2>/dev/null && { got=1; break; }
  sleep 2
done
[ "$got" = 1 ] || { echo "  never reached logo-loop"; tail -20 "$LOG"; exit 1; }
echo "  title reached; settling 6s"; sleep 6

snap() { # copy newest shot as a unique pose frame
  local pfx="$1"
  local f; f=$(ls -t "$SHOTDIR"/autoport_f*.png 2>/dev/null | head -1)
  [ -n "$f" ] && cp -f "$f" "$OUTDIR/${pfx}_$(basename "$f")" 2>/dev/null || true
}

# Varied waits spanning the FULL attract flythrough loop (close resets phase to
# ~0, so wait W ~= flythrough phase W). Short waits earlier clustered at one
# phase; these span ~4-95s to find the golden's phase.
WAITS=(4 8 13 19 26 34 43 53 64 76 89 6 11 17 24 32 41 51 62 74)
echo "== sampling ${#WAITS[@]} poses =="
i=0
for w in "${WAITS[@]}"; do
  i=$((i+1))
  "$PY" .autoport/xfocus_tap.py 18 18 >>"$LOG.focus" 2>&1   # CIRCLE x2 -> ensure at title
  sleep "$w"                                                 # camera advances
  "$PY" .autoport/xfocus_tap.py 28 >>"$LOG.focus" 2>&1       # START -> open main menu
  sleep 3
  snap "p$(printf '%02d' "$i")"
  echo "  pose $i (wait=${w}s) captured"
done

echo "== harvest =="
echo "  unique frames: $(ls "$OUTDIR"/p*_*.png 2>/dev/null | wc -l)"
ls -la "$OUTDIR" | tail -5
echo "== gk log tail =="; tail -3 "$LOG"
