#!/usr/bin/env bash
# grass_p19b_verify.sh — ROUND#19b (stacked-terraces gap cull) device verification.
# 1. install gap-fix APK + deploy_verify
# 2. boot @ spawn: harvest FLOORBELOW + FLOORGAP (p99 must be < thresh; gap_culled > 0)
# 3. hold 60s (fence fix must keep it alive), wide + close-up frames
# Usage: bash .autoport/grass_p19b_verify.sh [skip-install]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
say(){ echo; echo "######## $* ########"; }
focus(){ $ADB shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }
capck(){ # capck <path> — screencap + assert jak1 foreground; prints size + focus
  local fo; fo=$(focus)
  $ADB exec-out screencap -p > "$1" 2>/dev/null
  echo "  cap $(basename "$1") = $(stat -c %s "$1" 2>/dev/null)B focus=$fo"
  echo "$fo" | grep -q "$PKG" || echo "  [WARN] jak1 NOT foreground — frame untrusted"
}
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
pulse(){ stick "$1"; sleep "${2:-0.4}"; stick neutral; sleep "${3:-0.8}"; }

if [ "${1:-}" != "skip-install" ]; then
  say "1. install gap-fix APK"
  $ADB shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
  $ADB install -r -d -t -i com.android.vending android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk 2>&1 | tail -1
  say "2. deploy_verify"
  bash .autoport/lib/deploy_verify.sh $S jak1 2>&1 | tail -1
fi

say "3. boot @ training spawn (grass ON expected from pc-settings), harvest FLOORGAP"
$ADB shell am force-stop $PKG; sleep 1
$ADB shell setprop debug.opengoal.cpad_inject neutral
$ADB shell setprop debug.opengoal.grass_dbg 0
$ADB shell setprop debug.opengoal.grass_tilt 0
$ADB shell "setprop debug.opengoal.grass_floorgap ''"
$ADB shell setprop debug.opengoal.level.warp training-start
$ADB shell "setprop debug.opengoal.level.warp.pos ''"
$ADB logcat -b all -c
LOG=/tmp/gr19b_verify.log
( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr19b_lc.pid )
$ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
APP_PID=$($ADB shell pidof $PKG | tr -d '\r' | awk '{print $1}')
t0=$(date +%s); SPAWN=0
while [ $(( $(date +%s)-t0 )) -lt 300 ]; do
  grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { SPAWN=1; break; }
  grep -qaE 'signal (4|6|11) \(SIG' "$LOG" && break
  sleep 3
done
echo "  spawn=$SPAWN pid=$APP_PID"
grep -a 'FLOORBELOW cantilever-cull' "$LOG" | tail -1
grep -a 'ROUND#19b FLOORGAP' "$LOG" | tail -1

say "4. 60s hold (fence fix + gap fix together)"
DEAD=0
for i in $(seq 1 12); do
  sleep 5
  CUR=$($ADB shell pidof $PKG | tr -d '\r' | awk '{print $1}')
  { [ -z "$CUR" ] || [ "$CUR" != "$APP_PID" ]; } && { DEAD=1; echo "  DIED at +$((i*5))s"; break; }
done
echo "  alive=$((1-DEAD)) adreno_errno35=$(grep -ac 'errno 35 Resource deadlock' "$LOG")"
capck "$F/p19b_spawn_wide.png"

say "5. verdict"
{
  echo "=== ROUND#19b VERIFY ($(date '+%F %T')) gap-fix build ==="
  echo "spawn=$SPAWN dead=$DEAD errno35=$(grep -ac 'errno 35 Resource deadlock' "$LOG")"
  grep -a 'FLOORBELOW cantilever-cull' "$LOG" | tail -1
  grep -a 'ROUND#19b FLOORGAP' "$LOG" | tail -1
} > "$OUT/p19b_verify.txt"
cat "$OUT/p19b_verify.txt"
cp "$LOG" "$OUT/p19b_verify_logcat.log" 2>/dev/null
# NOTE: app left RUNNING on purpose iff caller wants follow-up beats; pass 'stop' to force-stop.
if [ "${2:-}" = "stop" ]; then $ADB shell am force-stop $PKG; kill "$(cat /tmp/gr19b_lc.pid 2>/dev/null)" 2>/dev/null || true; fi
[ "$DEAD" = 0 ] && [ "$SPAWN" = 1 ] && echo "[p19b PASS] gap-fix build boots + survives" || { echo "[p19b FAIL]"; exit 1; }
