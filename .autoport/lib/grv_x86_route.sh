#!/usr/bin/env bash
# grv_x86_route.sh — x86 oracle cross-check for Gcrash-rockvillage.
# Runs the IDENTICAL deterministic scenario as the device repro, via the same env
# hooks compiled into our x86 gk (GOAL code byte-identical to original per Gref):
#   warp village2-dock + pos override to the buzzer crate, close task 33 (pontoons),
#   then replay the load-boundary commands: want-levels(village2,swamp) and
#   want-display-level(swamp,display). x86 must survive crash-free.
# Usage: grv_x86_route.sh <tag> [observe_s]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TAG="${1:-x86route1}"
OBS="${2:-120}"
OUT=.autoport/reports/Gcrash-rockvillage
mkdir -p "$OUT"
LOG="$OUT/$TAG-gk.log"
RES="$OUT/$TAG-result.txt"
export DISPLAY="${DISPLAY:-:0}"
: > "$LOG"
env OG_LEVEL_WARP=village2-dock OG_LEVEL_WARP_POS="434.1 3 -1754.8" \
    OG_TASK_CLOSE=33 OG_WANT_LEVELS=village2,swamp OG_WANT_DISPLAY=swamp,display \
  build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data out/jak1/iso -- -boot -debug-mem > "$LOG" 2>&1 &
GKPID=$!
trap 'kill "$GKPID" 2>/dev/null || true' EXIT
echo "== $TAG: x86 gk pid=$GKPID =="
BOOT=0
for i in $(seq 1 120); do
  kill -0 "$GKPID" 2>/dev/null || break
  grep -qa 'link finish: logo' "$LOG" && { BOOT=1; echo "  booted ~${i}s"; break; }
  sleep 1
done
WARP=0; WL=0; WD=0
for i in $(seq 1 90); do
  kill -0 "$GKPID" 2>/dev/null || break
  grep -qa 'LEVEL-WARP-SPAWN name=village2-dock' "$LOG" && { WARP=1; break; }
  sleep 1
done
for i in $(seq 1 60); do
  kill -0 "$GKPID" 2>/dev/null || break
  grep -qa 'WANT-LEVELS lev1=village2' "$LOG" && { WL=1; break; }
  sleep 1
done
for i in $(seq 1 60); do
  kill -0 "$GKPID" 2>/dev/null || break
  grep -qa 'WANT-DISPLAY lev=swamp' "$LOG" && { WD=1; break; }
  sleep 1
done
ALIVE_AT_HOOKS=0; kill -0 "$GKPID" 2>/dev/null && ALIVE_AT_HOOKS=1
echo "  boot=$BOOT warp=$WARP want-levels=$WL want-display=$WD alive=$ALIVE_AT_HOOKS; observing ${OBS}s..."
CRASH=0
for i in $(seq 1 "$OBS"); do
  if ! kill -0 "$GKPID" 2>/dev/null; then CRASH=1; echo "  >>> gk EXITED ~${i}s into observe"; break; fi
  sleep 1
done
ALIVE_END=0; kill -0 "$GKPID" 2>/dev/null && ALIVE_END=1
ADDLEV=$(grep -aoE 'Adding level [a-z0-9-]+' "$LOG" | tail -8 | tr '\n' ';')
LINKS=$(grep -aoE 'link finish: [a-z0-9-]+' "$LOG" | tail -8 | tr '\n' ' ')
ERR=$(grep -aiE 'segfault|fatal|assert|exception' "$LOG" | tail -3 | tr '\n' ';')
STATUS=UNKNOWN
if [ "$WL" = 1 ] && [ "$WD" = 1 ] && [ "$ALIVE_END" = 1 ]; then STATUS="X86-ROUTE-CRASH-FREE"
elif [ "$ALIVE_END" = 0 ]; then STATUS="X86-DIED(boot=$BOOT warp=$WARP wl=$WL wd=$WD)"
else STATUS="X86-INCOMPLETE(warp=$WARP wl=$WL wd=$WD)"; fi
{
  echo "=== grv_x86_route $TAG $(date -Is) ==="
  echo "RESULT tag=$TAG status=$STATUS boot=$BOOT warp=$WARP want_levels=$WL want_display=$WD alive_end=$ALIVE_END"
  echo "  adding-level: ${ADDLEV:-none}"
  echo "  links: ${LINKS:-none}"
  echo "  err-lines: ${ERR:-none}"
} | tee "$RES"
kill "$GKPID" 2>/dev/null || true
trap - EXIT
echo "== $TAG done: $STATUS =="
