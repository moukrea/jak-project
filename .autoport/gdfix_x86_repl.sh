#!/usr/bin/env bash
# gdfix_x86_repl.sh — Gdynamic-fix DETERMINISTIC controller-logic proof on x86.
# Boots desktop gk, warps to Geyser Rock (training, in-game so the controller runs),
# connects goalc and drives *pc-settings* over the listener to exercise EVERY behavior
# of dynamic-render-scale-update (identical GOAL bytecode to the arm64 device build):
#   1. DESCEND to floor      (dyn-target unreachable -> fps < target -> scale -> floor)
#   2. RE-CLAMP on min raise  (raise Minimum Render Scale 10->40 while at floor -> snap up)  [owner bug #1]
#   3. CLIMB from floor       (drop target below fps -> scale climbs floor->100)             [owner bug #2]
#   4. OFF = manual           (disable -> eff scale == manual render-scale, controller idle)
# Captures [dyn-rs] controller logs + GDFIX-PROBE state reads from the gk stdout log.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export DISPLAY="${DISPLAY:-:0}"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Gdynamic-fix/evidence"; mkdir -p "$OUT"
LOG="$OUT/x86_repl.log"; GCLOG="$OUT/x86_repl_goalc.log"
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
timeout 600 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
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

PROBE='(format 0 "GDFIX-PROBE dyn=~A scale=~f min=~f tgt=~f rs=~f fps=~f~%" (-> *pc-settings* dynamic-render-scale?) *dyn-rs-scale* (-> *pc-settings* min-render-scale) (-> *pc-settings* dyn-target-fps) (-> *pc-settings* render-scale) *dyn-rs-fps-ema*)'
probe_n(){ local n="$1"; for _ in $(seq 1 "$n"); do echo "$PROBE" >&3; sleep 1; done; }

echo "== PHASE 1: enable dynamic, floor 10, target 90 (unreachable) -> DESCEND to floor =="
echo '(set! (-> *pc-settings* render-scale) 100.0)' >&3
echo '(set! (-> *pc-settings* min-render-scale) 10.0)' >&3
echo '(set! (-> *pc-settings* dyn-target-fps) 90.0)' >&3
echo '(set! (-> *pc-settings* dynamic-render-scale?) #t)' >&3
probe_n 14

echo "== PHASE 2: raise Minimum Render Scale 10 -> 40 at runtime -> RE-CLAMP (bug #1) =="
echo '(set! (-> *pc-settings* min-render-scale) 40.0)' >&3
probe_n 6

echo "== PHASE 3: drop target to 25 (below fps) -> CLIMB from floor toward 100 (bug #2) =="
echo '(set! (-> *pc-settings* dyn-target-fps) 25.0)' >&3
probe_n 18

echo "== PHASE 4: disable dynamic, set manual render-scale 55 -> OFF = manual =="
echo '(set! (-> *pc-settings* dynamic-render-scale?) #f)' >&3
echo '(set! (-> *pc-settings* render-scale) 55.0)' >&3
probe_n 6

exec 3>&-
sleep 2
echo "== DONE. summary =="
echo "-- GDFIX-PROBE samples --"; grep -a 'GDFIX-PROBE' "$LOG" | tail -60
echo "-- [dyn-rs] controller events (LOWER/RAISE/RE-CLAMP) --"; grep -aE '\[dyn-rs\] (LOWER|RAISE|RE-CLAMP)' "$LOG"
echo "-- counts --"
echo "   LOWER=$(grep -ac '\[dyn-rs\] LOWER' "$LOG")  RAISE=$(grep -acE '\[dyn-rs\] RAISE' "$LOG")  RE-CLAMP=$(grep -ac '\[dyn-rs\] RE-CLAMP' "$LOG")  PROBES=$(grep -ac 'GDFIX-PROBE' "$LOG")"
echo "   log: $LOG"
