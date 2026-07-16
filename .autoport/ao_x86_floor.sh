#!/bin/bash
# ao_x86_floor.sh — Grecharged-ambient-occlusion x86 grazing-floor iteration rig.
# One desktop gk boot at the TRAINING spawn vantage with AO forced via env, 3 shots,
# region metrics. Shaders are runtime-loaded on desktop: edit game/graphics/
# opengl_renderer/shaders/ao_*.frag between runs, NO rebuild needed.
# Usage: ao_x86_floor.sh <tag> <mode 0-3> [debug 0|1]
# Output: .autoport/reports/Grecharged-ambient-occlusion/x86-floor/<tag>/ + AOFLOOR lines.
set -u
cd "$(git rev-parse --show-toplevel)"
TAG="${1:?tag}"
MODE="${2:?mode}"
DBG="${3:-1}"
OUT=/tmp/ao_x86_floor
DEST=".autoport/reports/Grecharged-ambient-occlusion/x86-floor/$TAG"
SHOTDIR="build/game/OpenGOAL/jak1/screenshots"
SETTINGS="build/game/OpenGOAL/jak1/settings/pc-settings.gc"
POS="${POS_OVERRIDE:--1187.4 16.2 932.3}"   # ao_capture.sh training vantage
CONT="${CONT_OVERRIDE:-training-start}"     # warp container (e.g. village1-hut for crease A/B)
mkdir -p "$OUT" "$DEST" "$SHOTDIR"

pkill -f 'build/game/gk' 2>/dev/null; sleep 1
pkill -f 'goalc --user-auto' 2>/dev/null; sleep 1

set_key(){ # key value
  local k="$1" v="$2"
  if grep -q "($k " "$SETTINGS"; then
    sed -i "s/($k [^)]*)/($k $v)/" "$SETTINGS"
  else
    sed -i "s/^  (skip-movies?/  ($k $v)\n  (skip-movies?/" "$SETTINGS"
  fi
  grep -q "($k $v)" "$SETTINGS" || { echo "KEY INJECT FAILED: $k"; exit 9; }
}
set_key "recharged-grass?" "#f"          # capture protocol: grass off
set_key "ambient-occlusion" "0"          # env force is authoritative; keep disk clean
set_key "ao-quality" "2"

rm -f "$OUT/fifo"; mkfifo "$OUT/fifo"
./build/goalc/goalc --user-auto < "$OUT/fifo" > "$OUT/goalc.log" 2>&1 &
GOALC_PID=$!
exec 3>"$OUT/fifo"
snd(){ echo "$1" >&3; sleep "${2:-1.5}"; }
GK_PID=""
finish(){ [ -n "$GK_PID" ] && { kill -INT "$GK_PID" 2>/dev/null; sleep 2; kill "$GK_PID" 2>/dev/null; }; kill "$GOALC_PID" 2>/dev/null; exec 3>&- 2>/dev/null; }
trap finish EXIT
sleep 3

shot(){
  local f="$SHOTDIR/screenshot.png" t=0
  rm -f "$f"
  snd '(pc-screen-shot)' 1
  while [ $t -lt 12 ]; do
    if [ -f "$f" ]; then sleep 0.6; cp "$f" "$DEST/$1.png"; echo "  shot $1 ($(stat -c%s "$DEST/$1.png") B)"; return 0; fi
    sleep 1; t=$((t+1))
  done
  echo "  shot $1 MISSING"; return 1
}

LOG="$DEST/gk.log"
echo "== AO-X86-FLOOR tag=$TAG mode=$MODE debug=$DBG cont=$CONT pos=$POS =="
DISPLAY=:0 XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.RKSTQ3 \
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
AO_FORCE_MODE="$MODE" AO_FORCE_QUALITY=2 AO_DEBUG="$DBG" \
OG_LEVEL_WARP="$CONT" OG_LEVEL_WARP_POS="$POS" \
stdbuf -oL -eL ./build/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi \
  -iso-data out/jak1/iso -- -boot -debug-mem > "$LOG" 2>&1 &
GK_PID=$!
deadline=$(( $(date +%s) + 240 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  kill -0 "$GK_PID" 2>/dev/null || { echo "  GK EXITED EARLY"; tail -20 "$LOG"; exit 1; }
  grep -qa "LEVEL-WARP-SPAWN" "$LOG" && break
  sleep 3
done
grep -qa "LEVEL-WARP-SPAWN" "$LOG" || { echo "  NEVER SPAWNED"; exit 1; }
c=0
for i in 1 2 3 4 5 6; do
  snd '(lt)' 4
  grep -qa "Socket connected established" "$OUT/goalc.log" && { c=1; break; }
done
[ "$c" = 1 ] || echo "  listener connect FAILED (shots will be missing)"
sleep 12
# AOPERF confirmation: the forced mode must be live before shots count.
grep -a "AOPERF" "$LOG" | tail -2
grep -qa "AOPERF mode=$MODE " "$LOG" || { echo "  AOPERF MODE MISMATCH (wanted $MODE)"; }
shot "shot1"; sleep 3; shot "shot2"; sleep 3; shot "shot3"
grep -a "AOERR" "$LOG" | tail -5
python3 .autoport/ao_floor_metrics.py "$DEST"/shot*.png
echo "== DONE tag=$TAG =="
