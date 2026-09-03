#!/usr/bin/env bash
# grass_p19_bisect.sh <tag> [prop=val ...] — one GPU-wedge bisect run.
# Boots grass-ON at the training spawn with the given debug props, holds 45s past
# LEVEL-WARP-SPAWN (crash window is 5-7s), reports ALIVE/DEAD + Adreno errno-35 count.
# Always clears the props + force-stops at the end (device hygiene).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
TAG="$1"; shift
PROPS=("$@")

$ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell setprop debug.opengoal.grass_dbg 0 >/dev/null 2>&1
$ADB shell setprop debug.opengoal.grass_tilt 0 >/dev/null 2>&1
$ADB shell setprop debug.opengoal.grass_noattr4 0 >/dev/null 2>&1
$ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1
for p in "${PROPS[@]}"; do
  $ADB shell "setprop debug.opengoal.${p%%=*} '${p#*=}'" >/dev/null 2>&1
done
echo "[$TAG] props: ${PROPS[*]:-<none>}"

$ADB logcat -b all -c >/dev/null 2>&1
LOG=/tmp/gr19_bisect_$TAG.log
( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr19_bis_lc.pid )
$ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
APP_PID=$($ADB shell pidof $PKG | tr -d '\r' | awk '{print $1}')
echo "[$TAG] pid=$APP_PID"

t0=$(date +%s); SPAWN=0
while [ $(( $(date +%s)-t0 )) -lt 300 ]; do
  grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { SPAWN=1; break; }
  grep -qaE 'signal (4|6|11) \(SIG' "$LOG" && break
  CUR=$($ADB shell pidof $PKG | tr -d '\r' | awk '{print $1}')
  [ -z "$CUR" ] && break
  sleep 3
done
echo "[$TAG] spawn_reached=$SPAWN t=+$(( $(date +%s)-t0 ))s"

DEAD=0; DIED_AT=-
if [ "$SPAWN" = 1 ]; then
  for i in $(seq 1 9); do
    sleep 5
    CUR=$($ADB shell pidof $PKG | tr -d '\r' | awk '{print $1}')
    if [ -z "$CUR" ] || [ "$CUR" != "$APP_PID" ]; then DEAD=1; DIED_AT=$((i*5)); break; fi
  done
else
  DEAD=1; DIED_AT=pre-spawn
fi
ADRENO=$(grep -ac 'errno 35 Resource deadlock' "$LOG" 2>/dev/null || echo 0)
FB=$(grep -a 'FLOORBELOW cantilever-cull' "$LOG" | head -1 | sed 's/.*FLOORBELOW/FLOORBELOW/')
echo "[$TAG] VERDICT: dead=$DEAD died_at=+${DIED_AT}s adreno_errno35=$ADRENO"
echo "[$TAG] $FB"

# teardown
$ADB shell am force-stop $PKG >/dev/null 2>&1
$ADB shell setprop debug.opengoal.grass_dbg 0 >/dev/null 2>&1
$ADB shell setprop debug.opengoal.grass_tilt 0 >/dev/null 2>&1
$ADB shell setprop debug.opengoal.grass_noattr4 0 >/dev/null 2>&1
kill "$(cat /tmp/gr19_bis_lc.pid 2>/dev/null)" 2>/dev/null || true
[ "$DEAD" = 0 ] && echo "[$TAG] SURVIVED" || echo "[$TAG] DIED"
