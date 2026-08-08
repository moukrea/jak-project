#!/usr/bin/env bash
# rhud5_x86_greeneco.sh — ONE question, answered tightly: does the recharged green-eco particle
# (group 720) actually render at the hud-pickups slot (110,55), and how does it compare with ND's
# stock group 75 at the SAME slot?
# The stock eco-pill counter + its green sprite are only on screen for ~2 s after the value
# changes, so every shot here is taken IMMEDIATELY after the change (the first attempt put a
# 2.4 s probe in between and photographed the already-hidden element — an invalid A/B).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk
OUT=.autoport/reports/Grecharged-hud-jak1/round5/x86
mkdir -p "$OUT"
LOG=/tmp/rhud5green; rm -rf "$LOG"; mkdir -p "$LOG"
SHOTDIR=build/game/OpenGOAL/jak1/screenshots
XAUTH="$(ls /run/user/1000/.mutter-Xwaylandauth* 2>/dev/null | head -1)"

pkill -f "[b]uild/game/gk" 2>/dev/null; sleep 2
pkill -f "[g]oalc --game jak1" 2>/dev/null; sleep 1
mkdir -p "$SHOTDIR"; rm -f "$SHOTDIR"/*.png

DISPLAY="${DISPLAY:-:0}" XAUTHORITY="$XAUTH" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
OG_LEVEL_WARP=training-start \
stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
  -- -boot -debug-mem > "$LOG/gk.log" 2>&1 &
GKPID=$!
cleanup(){ kill $GKPID 2>/dev/null; pkill -f "[g]oalc --game jak1" 2>/dev/null; }
trap cleanup EXIT
t=0
until grep -qa "LEVEL-WARP-SPAWN" "$LOG/gk.log"; do
  sleep 3; t=$((t+3)); kill -0 $GKPID 2>/dev/null || { tail -20 "$LOG/gk.log"; exit 1; }
  [ $t -ge 300 ] && { echo "no warp"; exit 1; }
done
sleep 18
rm -f "$LOG/fifo"; mkfifo "$LOG/fifo"
( build/goalc/goalc --game jak1 --proj-path . --disable-ansi < "$LOG/fifo" > "$LOG/goalc.log" 2>&1 ) &
exec 9>"$LOG/fifo"
snd(){ printf '%s\n' "$1" >&9; sleep "${2:-1.2}"; }
snd '(lt)' 8
snd '(mi)' 5
mi=0
until grep -qa "GREENOK" "$LOG/goalc.log" "$LOG/gk.log" 2>/dev/null; do
  sleep 15; mi=$((mi+15)); printf '%s\n' '(format 0 "GREENOK~%")' >&9
  [ $mi -ge 200 ] && { echo "(mi) failed"; tail -20 "$LOG/goalc.log"; exit 1; }
done
echo "env ready after ${mi}s"
shot(){ snd '(pc-screen-shot)' 2.5; local f; f=$(ls -t "$SHOTDIR"/*.png 2>/dev/null|head -1)
        [ -n "$f" ] && mv "$f" "$OUT/x86-$1.png" && echo "  shot $1" || echo "  MISSING $1"; }

snd '(set! (-> *pc-settings* dynamic-render-scale?) #f)' 0.6
snd '(set! (-> *pc-settings* render-scale) 100.0)' 0.6
# face a dark rock wall so a green particle is not judged against green foliage
snd '(set! (-> *target* fact eco-pill) 1.0)' 1.5

# Pin BOTH elements on screen instead of racing the ~2 s auto-hide: force-on-screen makes
# tally-value re-stamp trigger-time every frame (the pin the racer hud uses), so the particle
# cloud has time to build up (a fresh launch is nearly empty for the first ~1 s — that is what
# made the 0.4 s shots of the previous attempt look like "nothing renders").
snd '(set! (-> (-> *hud-parts* pickups 0) force-on-screen) #t)' 1
snd '(set! (-> *hud-parts-pc* recharged-health 0 force-on-screen) #t)' 1
for leg in ON OFF; do
  if [ "$leg" = ON ]; then snd '(set! (-> *pc-settings* recharged-hud?) #t)' 3
  else snd '(set! (-> *pc-settings* recharged-hud?) #f)' 3; fi
  snd '(set! (-> *target* fact eco-pill) 3.0)' 4
  for n in 1 2 3; do shot "greeneco_${leg}_${n}"; sleep 1; done
done
exec 9>&-; sleep 1; cleanup
ls -la "$OUT"/x86-greeneco_*.png
