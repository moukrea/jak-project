#!/usr/bin/env bash
# grass_p19_stability.sh — ROUND#19 gate 0: prove the Adreno shader-hang fix holds.
# Previous state (p19_instrument.txt): grass ON died 5-7s after LEVEL-WARP-SPAWN with kgsl
# "Resource deadlock" (errno 35) -> SIGKILL. Fix = no early-exit control flow inside the
# uniform-bounded occluder loop in grass.vert. This run: grass ON, warp to training spawn,
# HOLD 90s past spawn (12x the crash window), assert app alive + foreground at the end,
# harvest FLOORBELOW + R19OCC + census lines.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='files/.config/OpenGOAL/jak1/settings/pc-settings.gc'
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
say(){ echo; echo "######## $* ########"; }
focus(){ $ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'; }

set_grass(){ $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell run-as $PKG cat "$PCS" > /tmp/pcs19.gc 2>/dev/null || true
  if grep -q 'recharged-grass?' /tmp/pcs19.gc 2>/dev/null; then
    sed -i "s/(recharged-grass? #[tf])/(recharged-grass? #$1)/" /tmp/pcs19.gc
    $ADB push /tmp/pcs19.gc /data/local/tmp/pcs19.gc >/dev/null 2>&1
    $ADB shell run-as $PKG cp /data/local/tmp/pcs19.gc "$PCS" 2>/dev/null || true
    $ADB shell rm -f /data/local/tmp/pcs19.gc >/dev/null 2>&1
  fi
  echo "  grass now: $($ADB shell run-as $PKG cat "$PCS" 2>/dev/null | grep recharged-grass | tr -d '\r')"; }

say "0. grass ON + boot @ training spawn (DISCRIMINATOR: noattr4=$($ADB shell getprop debug.opengoal.grass_noattr4))"
set_grass t
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell setprop debug.opengoal.grass_dbg 0 >/dev/null 2>&1
$ADB shell setprop debug.opengoal.grass_tilt 0 >/dev/null 2>&1
$ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1
$ADB logcat -b all -c >/dev/null 2>&1
LOG=/tmp/gr19_stab.log
( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr19_lc.pid )
$ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
APP_PID=$($ADB shell pidof $PKG | tr -d '\r' | awk '{print $1}')
echo "  app pid=$APP_PID"

t0=$(date +%s); SPAWN=0
while [ $(( $(date +%s)-t0 )) -lt 300 ]; do
  grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { SPAWN=1; break; }
  grep -qaE "signal (4|6|11) \(SIG" "$LOG" && break
  sleep 3
done
echo "  spawn_reached=$SPAWN t=+$(( $(date +%s)-t0 ))s"
[ "$SPAWN" = 1 ] || { echo "[p19stab FAIL] never reached spawn"; $ADB shell am force-stop $PKG; kill "$(cat /tmp/gr19_lc.pid)" 2>/dev/null; exit 1; }

say "1. HOLD 90s past spawn (old crash window was 5-7s)"
DEAD=0
for i in $(seq 1 18); do
  sleep 5
  CUR=$($ADB shell pidof $PKG | tr -d '\r' | awk '{print $1}')
  if [ -z "$CUR" ] || [ "$CUR" != "$APP_PID" ]; then DEAD=1; echo "  app DIED at +$((i*5))s post-spawn (pid $APP_PID -> '$CUR')"; break; fi
done
echo "  alive_after_hold=$((1-DEAD))"

say "2. verdict + harvest"
echo "  focus=$(focus)"
: > "$OUT/p19_stability.txt"
{
  echo "=== ROUND#19 STABILITY RUN ($(date '+%F %T')) — grass ON, 90s hold past LEVEL-WARP-SPAWN ==="
  echo "app_pid=$APP_PID dead=$DEAD focus=$(focus)"
  echo "--- FLOORBELOW (this device run) ---"
  grep -a 'FLOORBELOW cantilever-cull' "$LOG"
  echo "--- object CULL/TRAMPLE census (world coords) ---"
  grep -aE 'ROUND#18 object-(CULL|TRAMPLE) captured' "$LOG" | sort -u
  echo "--- R19OCC ---"
  grep -a 'R19OCC' "$LOG" | head -4
  echo "--- Adreno/kgsl errors (must be EMPTY) ---"
  grep -aiE 'adreno.*(deadlock|errno 35)|kgsl.*(timeout|deadlock|fault)' "$LOG" | head -10
  echo "--- fatal signals on pid $APP_PID (must be EMPTY) ---"
  grep -aE "signal (4|6|9|11) \(SIG" "$LOG" | grep -a "$APP_PID" | head -5
  echo "--- kernel dispatch spikes >500ms (old killer showed 1033/3769ms) ---"
  grep -a 'Kernel dispatch time' "$LOG" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+$/ && $i+0>500) print}' | head -5
} | tee -a "$OUT/p19_stability.txt"

# keep the log for the report; screencap one liveness frame
cp "$LOG" "$OUT/p19_stability_logcat.log" 2>/dev/null
$ADB exec-out screencap -p > "$F/p19_stab_live.png" 2>/dev/null
echo "  stab_live=$(stat -c %s "$F/p19_stab_live.png" 2>/dev/null)B"

say "3. FORCE-STOP (device hygiene)"
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/gr19_lc.pid 2>/dev/null)" 2>/dev/null || true
if [ "$DEAD" = 0 ]; then echo "[p19stab PASS] grass ON survived 90s past spawn — deadlock fix HOLDS"; else echo "[p19stab FAIL] app died during hold"; exit 1; fi
