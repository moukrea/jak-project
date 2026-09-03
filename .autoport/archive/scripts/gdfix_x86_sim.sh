#!/usr/bin/env bash
# gdfix_x86_sim.sh — Gdynamic-fix DETERMINISTIC hill-climb+lock proof on x86.
#
# A beefy desktop GPU is never the bottleneck, so real measured fps pins at the vsync cap at
# every render scale -- x86 alone can't exhibit the GPU-bound fps-vs-scale relationship the
# controller needs. So we arm the controller's TEST SEAM (*dyn-rs-sim-a*/*dyn-rs-sim-b*, inert
# in production): with it armed the controller SYNTHESIZES the measured fps from its own live
# scale as  fps = clamp(sim-a - sim-b*scale, [8,58])  every frame -- exactly a GPU-bound device
# (higher scale => lower fps), closed-loop. Its real GOAL bytecode (identical to the arm64
# build) then hill-climbs against this curve, so the [dyn-rs] trace PROVES the climb, the
# boundary LOCK, the STAY-locked, the UNLOCK on a lighter scene, the runtime Min-Render-Scale
# RE-CLAMP (bug#1), the floor, and OFF=manual. We capture the controller's OWN [dyn-rs] logs
# (which reach gk stdout) plus the renderer's "FBO Setup: requested WxH" lines, which are an
# INDEPENDENT confirmation of the effective scale actually applied to the render target.
#
# Main curve: fps = 56 - 0.4*scale (dyn-target 30). fps by 10%-grid scale:
#   40->40  50->36  60->32  70->28  80->24  90->20  100->16
# => HIGHEST scale holding fps>=30 is 60% (70% drops to 28<30). Owner's exact repro (target 30,
# "~32fps @ 60%"): the controller MUST settle at 60%, NOT the floor.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gdynamic-fix/evidence"; mkdir -p "$OUT"
LOG="$OUT/x86_sim.log"; GCLOG="$OUT/x86_sim_goalc.log"
[ -x "$GK" ] || { echo "FAIL: $GK missing"; exit 1; }
: > "$LOG"; : > "$GCLOG"

echo "== launch x86 gk =="
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$LOG" 2>&1 &
GKPID=$!
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT

echo "== wait for title (link finish: logo) =="
for i in $(seq 1 120); do
  kill -0 "$GKPID" 2>/dev/null || { echo "FAIL: gk exited during boot"; tail -20 "$LOG"; exit 1; }
  grep -qE "link finish: logo" "$LOG" && { echo "  booted ~${i}s"; break; }
  sleep 1
done
sleep 3
echo "== goalc (lt)+(build-game), then warp to Geyser Rock (training) =="
timeout 1200 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!
exec 3>"$FIFO"
echo '(lt)' >&3
echo '(build-game)' >&3
for i in $(seq 1 180); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && { echo "  build-game done ~${i}s"; break; }; done
sleep 3
echo "  warp -> game-start (Geyser Rock)"
echo '(start (quote play) (get-continue-by-name *game-info* "game-start"))' >&3
echo "  waiting 12s for level load + settle..."
sleep 12

mark(){ echo "(format 0 \"GDFIX-MARK $*~%\")" >&3; echo "---- $* ----"; sleep 0.3; }
sim(){ echo "(set! *dyn-rs-sim-a* $1)" >&3; echo "(set! *dyn-rs-sim-b* $2)" >&3; }   # arm the fps=a-b*scale curve
setf(){ echo "(set! (-> *pc-settings* $1) $2)" >&3; }

echo "== SETUP: dynamic ON, floor 40, target 30 (real render fps irrelevant -- controller uses the sim seam) =="
setf render-scale 100.0
setf min-render-scale 40.0
setf dyn-target-fps 30.0
setf dynamic-render-scale? '#t'
sleep 1

mark "P0 recreate STUCK-AT-FLOOR: heavy flat 15fps (sim-a 15, sim-b 0) -> descend to floor 40 (load-following, stays UNLOCKED)"
sim 15.0 0.0
sleep 9

mark "P1 CLIMB+LOCK (bug#2): curve 56-0.4*scale -> at 40 fps=40 headroom -> climb 40->60, probe 70 fails (28<30), back to 60, LOCK"
sim 56.0 0.4
sleep 16

mark "P2 STAY-LOCKED: same curve -> HOLD at 60 (one step below the first scale <target); no oscillation"
sleep 9

mark "P3 UNLOCK on lighter scene: curve 68-0.4*scale -> 60 now gives 44 (>= lock+5) -> unlock -> re-climb to 90, LOCK"
sim 68.0 0.4
sleep 20

mark "P4 RE-CLAMP (bug#1): floor->10, heavy flat 15 -> descend to 10, then raise Min-Render-Scale 10->60 -> snap up to 60"
setf min-render-scale 10.0
sim 15.0 0.0
sleep 9
setf min-render-scale 60.0    # runtime raise of the floor -> RE-CLAMP must snap the running scale 10 -> 60
sleep 4

mark "P5 OFF=manual: disarm sim, disable dynamic, manual render-scale 55 -> effective scale == 55 (FBO becomes 55% of base)"
sim -1.0 0.0
setf dynamic-render-scale? '#f'
setf render-scale 55.0
sleep 4

exec 3>&-
sleep 2
echo "== DONE. Trace summary =="
echo "-- controller events ([dyn-rs] LOWER/RAISE/LOCK/UNLOCK/RE-CLAMP), in order --"
grep -aE '\[dyn-rs\] (LOWER|RAISE|LOCK|UNLOCK|RE-CLAMP)' "$LOG"
echo
echo "-- interleaved MARK phases + [dyn-rs] state heartbeats + FBO Setup (applied scale), in order --"
grep -aE 'GDFIX-MARK|\[dyn-rs\] state|FBO Setup: requested' "$LOG"
echo
echo "-- counts --"
echo "   RAISE=$(grep -ac '\[dyn-rs\] RAISE' "$LOG")  LOWER=$(grep -ac '\[dyn-rs\] LOWER' "$LOG")  LOCK=$(grep -acE '\[dyn-rs\] LOCK ' "$LOG")  UNLOCK=$(grep -ac '\[dyn-rs\] UNLOCK' "$LOG")  RE-CLAMP=$(grep -ac '\[dyn-rs\] RE-CLAMP' "$LOG")"
echo "   log: $LOG"
