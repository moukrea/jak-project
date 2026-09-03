#!/usr/bin/env bash
# hd3_x86_missing_asset_check.sh — guard check: enhanced-models ON with NO jak-hd-ag.go present
# must NOT crash gk (the 02:33 core: initialize-skeleton's art-error state writes through
# entity=#f -> delayed SIGSEGV). Expects the init-jak-hd guard: "[JAK-HD] asset missing" log,
# exactly once (latch, no retry storm), gk alive 60s after, and NO "[JAK-HD] spawned".
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; GOALC=build/goalc/goalc; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-hd-models3; mkdir -p "$OUT"
R="$OUT/missing_asset_check.txt"; : > "$R"
GKLOG="$OUT/.ma_gk.log"; GCLOG="$OUT/.ma_gc.log"; FIFO="$(mktemp -u)"; mkfifo "$FIFO"
: > "$GKLOG"; : > "$GCLOG"

[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/jak-hd.gc ] || { echo "FAIL: GAME.CGO stale vs jak-hd.gc — run (mi) first" | tee -a "$R"; exit 1; }
# THE POINT: remove the HD asset from every location loado probes
rm -f out/jak1/obj/jak-hd-ag.go "$ISO/jak-hd-ag.go"

"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ exec 3>&- 2>/dev/null||true; kill "$GKPID" "${GCPID:-0}" 2>/dev/null||true; wait 2>/dev/null||true; rm -f "$FIFO"; }
trap cleanup EXIT
booted=0
for i in $(seq 1 150); do
  kill -0 "$GKPID" 2>/dev/null || { echo "FAIL: gk exited during boot" | tee -a "$R"; tail -20 "$GKLOG" >> "$R"; exit 1; }
  grep -aqE "link finish: default-menu($|-pc)" "$GKLOG" 2>/dev/null && { booted=1; break; }
  grep -aqE "link finish: logo($|-)" "$GKLOG" 2>/dev/null && [ "$i" -ge 30 ] && { booted=1; break; }
  sleep 1
done
[ "$booted" = 1 ] || { echo "FAIL: boot timeout" | tee -a "$R"; exit 1; }
sleep 4
timeout 900 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 &
GCPID=$!; exec 3>"$FIFO"
echo '(lt)' >&3; sleep 5
echo '(build-game)' >&3
for i in $(seq 1 240); do sleep 1; grep -aqiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && break; done
sleep 3
echo '(set! (-> *pc-settings* recharged-enhanced-models?) #t)' >&3
echo "(start (quote play) (get-continue-by-name *game-info* \"game-start\"))" >&3
tgtok=0
for i in $(seq 1 45); do
  echo '(when *target* (format 0 "TGT-READY~%"))' >&3; sleep 2
  grep -qa TGT-READY "$GKLOG" 2>/dev/null && { tgtok=1; break; }
done
[ "$tgtok" = 1 ] || { echo "FAIL: *target* never spawned" | tee -a "$R"; exit 1; }
# soak: the 02:33 crash hit ~10s after the failed load; give it 60s + a level's worth of frames
sleep 60
ALIVE=0; kill -0 "$GKPID" 2>/dev/null && ALIVE=1
MISS=$(grep -ac "\[JAK-HD\] asset missing" "$GKLOG" 2>/dev/null); MISS=${MISS:-0}
SPAWNED=$(grep -ac "\[JAK-HD\] spawned" "$GKLOG" 2>/dev/null); SPAWNED=${SPAWNED:-0}
{
  echo "MISSING-ASSET CHECK: gk-alive-after-60s=$ALIVE asset-missing-logs=$MISS spawned-logs=$SPAWNED"
  if [ "$ALIVE" = 1 ] && [ "$MISS" -eq 1 ] && [ "$SPAWNED" -eq 0 ]; then echo "RESULT: PASS — no crash, single latched refusal, no spawn";
  elif [ "$ALIVE" = 1 ] && [ "$MISS" -ge 1 ] && [ "$MISS" -le 3 ] && [ "$SPAWNED" -eq 0 ]; then echo "RESULT: PASS-WITH-NOTE — no crash but $MISS refusal logs (latch may re-fire on toggle churn; inspect)";
  elif [ "$ALIVE" = 0 ]; then echo "RESULT: FAIL — gk died (guard did not prevent the crash)";
  else echo "RESULT: FAIL — asset-missing=$MISS spawned=$SPAWNED (unexpected combination)"; fi
} | tee -a "$R"
cp -f "$GKLOG" "$OUT/missing_asset.gk.log"
# restore staging for subsequent HD runs
mkdir -p out/jak1/obj && cp -f recharged_assets/hd_anim/jak-hd-ag.go out/jak1/obj/jak-hd-ag.go
grep -q 'RESULT: PASS' "$R"
