#!/usr/bin/env bash
# V4-CRASH repro: boot x86 gk to the title, press START to OPEN the menu (the crash
# window), and harvest any GOAL crash/backtrace. The menu-open path spawns the holo
# drone (manipy *voicebox-sg*) — the suspected null-deref (fault=ee_base-4).
# Portable + -boot -debug-mem so GOAL prints route to gk stdout (per x86 listener recipe).
# NEVER pgrep -f gk (would match the claude process) — only kill the PID we launch.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
PY="$HOME/.venv/autoport/bin/python"
LOG="/tmp/gmenu-v4crash-x86.log"
GK="build/game/gk"
: > "$LOG"

echo "== launching gk =="
DISPLAY=:0 XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.RKSTQ3 \
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
      -iso-data out/jak1/iso -- -boot -debug-mem > "$LOG" 2>&1 &
GKPID=$!; echo "  gk pid=$GKPID"
cleanup(){ kill -INT "$GKPID" 2>/dev/null||true; sleep 1; kill -KILL "$GKPID" 2>/dev/null||true; wait "$GKPID" 2>/dev/null||true; }
trap cleanup EXIT

echo "== wait for title (logo-loop) =="
deadline=$(( $(date +%s) + 180 )); got=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  if ! kill -0 "$GKPID" 2>/dev/null; then echo "  gk EXITED before title"; tail -30 "$LOG"; exit 2; fi
  grep -qE "link finish: logo-loop|\\[display\\] game started" "$LOG" 2>/dev/null && { got=1; break; }
  sleep 2
done
[ "$got" = 1 ] || { echo "  never reached title"; tail -30 "$LOG"; exit 3; }
echo "  title reached; settle 6s"; sleep 6

echo "== press START (open menu) — the crash window =="
"$PY" .autoport/xfocus_tap.py 28 >>"$LOG.focus" 2>&1 || echo "  (focus/tap warn)"
# watch 25s for a crash (gk exit) or survival
for s in $(seq 1 25); do
  if ! kill -0 "$GKPID" 2>/dev/null; then
    echo "  !! gk EXITED ${s}s after START — likely the crash"; break
  fi
  sleep 1
done

echo ""
echo "############### CRASH / BACKTRACE SECTION ###############"
grep -niE "segfault|sigsegv|unhandled|backtrace|EE erro|fault|crash|assert|abort|Unmapped|access viol|exception|nullptr|goal stack|Stack Trace" "$LOG" | tail -40
echo "############### LOG TAIL (last 40) ###############"
tail -40 "$LOG"
echo ""
if kill -0 "$GKPID" 2>/dev/null; then echo "RESULT: gk STILL ALIVE after START (no x86 crash — may need device repro)"; else echo "RESULT: gk DIED after START (crash reproduced on x86)"; fi
