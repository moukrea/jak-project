#!/bin/bash
# AO defect5 x86 smoke: boot to title flythrough, screenshot via in-game (pc-screen-shot).
# One config per invocation:  ao_run.sh <tag> <MODE> <QUALITY> <DEBUG>
set -u
cd "$(git rev-parse --show-toplevel)"
TAG="$1"; MODE="$2"; QUAL="$3"; DBG="$4"
REPORT=.autoport/reports/Grecharged-ambient-occlusion/x86-defect5
OUT="$REPORT"
SHOTDIR="build/game/OpenGOAL/jak1/screenshots"
mkdir -p "$OUT" "$SHOTDIR"
LOG="$OUT/gk-$TAG.log"

# never touch other projects; kill only stray gk from THIS path
pgrep -f 'build/game/gk' >/dev/null && { pkill -f 'build/game/gk'; sleep 2; }
pgrep -f 'goalc --user-auto' >/dev/null && { pkill -f 'goalc --user-auto'; sleep 2; }

export DISPLAY=:0 XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.RKSTQ3
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
export AO_FORCE_MODE="$MODE" AO_FORCE_QUALITY="$QUAL" AO_DEBUG="$DBG"

stdbuf -oL -eL ./build/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi \
  -iso-data out/jak1/iso -- -boot -debug-mem > "$LOG" 2>&1 &
GK_PID=$!
echo "GK_PID=$GK_PID tag=$TAG MODE=$MODE QUAL=$QUAL DBG=$DBG"

deadline=$(( $(date +%s) + 90 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  kill -0 "$GK_PID" 2>/dev/null || { echo "GK EXITED EARLY"; tail -25 "$LOG"; exit 1; }
  grep -qa "machine started" "$LOG" && break
  sleep 2
done
grep -qa "machine started" "$LOG" || { echo "NEVER BOOTED"; kill "$GK_PID" 2>/dev/null; exit 1; }
# let title flythrough run over village geometry
sleep 18

# goalc listener just to trigger screenshots (no build-game; screenshot fn already linked)
rm -f "$OUT/fifo_$TAG"; mkfifo "$OUT/fifo_$TAG"
./build/goalc/goalc --user-auto < "$OUT/fifo_$TAG" > "$OUT/goalc-$TAG.log" 2>&1 &
GOALC_PID=$!
exec 3>"$OUT/fifo_$TAG"
snd(){ echo "$1" >&3; sleep "${2:-1.5}"; }
cleanup(){ kill -INT "$GK_PID" 2>/dev/null; sleep 2; kill "$GK_PID" "$GOALC_PID" 2>/dev/null; exec 3>&- 2>/dev/null; rm -f "$OUT/fifo_$TAG"; }
trap cleanup EXIT

sleep 3
CONNECTED=0
for i in 1 2 3 4 5 6 7 8; do
  snd '(lt)' 3
  grep -qa "Socket connected established\|Connected to OpenGOAL" "$OUT/goalc-$TAG.log" && { CONNECTED=1; break; }
done
[ "$CONNECTED" = 1 ] || { echo "LISTENER NEVER CONNECTED"; tail -15 "$OUT/goalc-$TAG.log"; exit 1; }

shot(){
  local f="$SHOTDIR/screenshot.png" t=0
  rm -f "$f"
  snd '(pc-screen-shot)' 1
  while [ $t -lt 12 ]; do
    if [ -f "$f" ]; then sleep 0.5; cp "$f" "$OUT/$TAG-$1.png"; echo "shot $TAG-$1 ($(stat -c%s "$OUT/$TAG-$1.png") B)"; return 0; fi
    sleep 1; t=$((t+1))
  done
  echo "shot $TAG-$1 MISSING"; return 1
}

shot shot0
sleep 3
shot shot1
sleep 3
shot shot2

echo "AOLINES:"
grep -a "AOERR\|AOPERF\|AO:" "$LOG" | tail -20
echo "DONE_$TAG"
