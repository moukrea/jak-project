#!/usr/bin/env bash
# Phase Gdeath-crash — device death/respawn repro+verify driver.
# Warps to Geyser Rock, then arms the deterministic death hook (prop
# debug.opengoal.die) which forces Jak to die COUNT times via *listener-function*.
# Detects a hard crash AND counts crash-free deaths (GDEATH-FIRE + render advancing).
#
# Usage: gdeath_run.sh <mode> <count> <run_tag> [out_dir]
#   mode  = respawn | endlessfall | drown-death | movie | <attack-mode-sym>
#   SKIP_BUILD=1  reuse already-built+deployed libgk (skip build+install)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

MODE="${1:-endlessfall}"
COUNT="${2:-6}"
RUN_TAG="${3:-run1}"
OUT_DIR="${4:-.autoport/reports/Gdeath-crash}"
mkdir -p "$OUT_DIR"

PKG="org.opengoal.gk.jak1"; ACT=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
SERIAL="${ANDROID_SERIAL:-eae4df44}"; export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT_DIR/$RUN_TAG-logcat.log"; RESULT="$OUT_DIR/$RUN_TAG-result.txt"
A(){ "$ADB" -s "$SERIAL" "$@"; }

pkill -f 'logcat.*GK_STDOUT' 2>/dev/null || true

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "== build current-HEAD libgk.so =="
  bash .autoport/lib/d3_build.sh || { echo "FAIL: libgk build"; exit 1; }
  echo "== build SLIM jak1 debug APK =="
  ( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 | tail -n 20 ) || { echo "FAIL: gradle"; exit 1; }
  [ -f "$APK" ] || { echo "FAIL: no APK"; exit 1; }
  device_require_attached; device_stayon_on
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  device_require_unlocked; device_miui_unblock_install
  STAGE="/data/local/tmp/$(basename "$APK")"
  A push "$APK" "$STAGE" >/tmp/gdeath-push.out 2>&1 || { cat /tmp/gdeath-push.out; echo "FAIL: push"; exit 1; }
  A shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/gdeath-pm.out 2>&1 || { cat /tmp/gdeath-pm.out; echo "FAIL: install"; exit 1; }
  grep -q Success /tmp/gdeath-pm.out || { cat /tmp/gdeath-pm.out; echo "FAIL: no Success"; exit 1; }
  A shell rm -f "$STAGE" >/dev/null 2>&1 || true
  bash .autoport/lib/deploy_verify.sh "$SERIAL" || { echo "FAIL: deploy_verify"; exit 1; }
else
  device_require_attached; device_stayon_on
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  device_require_unlocked
fi

echo "== arm warp + death hook: mode=$MODE count=$COUNT tag=$RUN_TAG =="
A shell setprop debug.opengoal.pad_replay "" >/dev/null 2>&1 || true
A shell setprop debug.opengoal.f1.warp 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.f1.census 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.die 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.die.mode "$MODE" >/dev/null 2>&1 || true
A shell setprop debug.opengoal.die.count "$COUNT" >/dev/null 2>&1 || true

A shell am force-stop "$PKG" >/dev/null 2>&1 || true
A logcat -G 64M >/dev/null 2>&1 || true; A logcat -c >/dev/null 2>&1 || true
: > "$LOG"
A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LCPID=$!
cleanup(){ kill "$LCPID" 2>/dev/null||true; A shell setprop debug.opengoal.die 0 >/dev/null 2>&1||true;
  A shell setprop debug.opengoal.f1.warp 0 >/dev/null 2>&1||true; device_stayon_restore 2>/dev/null||true; }
trap cleanup EXIT

A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true

crash_seen(){ grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG"; }
focus_app(){ A shell dumpsys window 2>/dev/null | grep -iE mCurrentFocus | grep -q "$PKG"; }
fire_count(){ grep -acE 'GDEATH-FIRE' "$LOG" 2>/dev/null || echo 0; }
frame_now(){ grep -aoE 'frame=[0-9]+' "$LOG" | tail -1 | grep -oE '[0-9]+' || echo 0; }

echo "  warming to title (up to 120s)..."
for i in $(seq 1 120); do grep -qa "link finish: logo" "$LOG" && break; sleep 1; done
echo "  waiting for training (Geyser Rock) load (up to 8min)..."
TR=0
for ((i=1;i<=96;i++)); do sleep 5
  grep -qaE "Adding level training|link finish: training-vis" "$LOG" && { echo "   training ~$((i*5))s"; TR=1; break; }
  crash_seen && { echo "   crash before training"; break; }
done
[ "$TR" = 1 ] || { echo "RESULT mode=$MODE tag=$RUN_TAG status=NO-TRAINING-LOAD fires=$(fire_count)" | tee "$RESULT"; exit 0; }

echo "  observe death hook firing $COUNT deaths (up to 6min)..."
F0=$(frame_now)
LAST=0
for ((i=1;i<=72;i++)); do
  sleep 5
  FC=$(fire_count)
  [ "$FC" != "$LAST" ] && { echo "   GDEATH-FIRE count=$FC (t=$((i*5))s) frame=$(frame_now)"; LAST=$FC; }
  crash_seen && { echo "   >>> CRASH after $FC fires"; break; }
  [ "$FC" -ge "$COUNT" ] && { echo "   all $COUNT deaths fired"; sleep 10; break; }
done

# settle/observe a bit more for any delayed crash
for ((i=1;i<=10;i++)); do sleep 2; crash_seen && break; done

FC=$(fire_count); F1=$(frame_now); DF=$(( ${F1:-0} - ${F0:-0} ))
FOC=no; focus_app && FOC=yes
SIG=$(grep -aoE 'GK-DIAG sig=[0-9]+' "$LOG" | tail -1)
NEARFN=$(grep -aE 'A38-TRIPWIRE (pc|lr|fault) nearest-fn' "$LOG" | tail -3 | tr '\n' ';')
FPWALK=$(grep -acE 'A34-DIAG fp-walk' "$LOG")
CURPROC=$(grep -aE 'A34-DIAG (pp=|state-name)' "$LOG" | tail -2 | tr '\n' ';')
STOMP=$(grep -aoE '(GCINE3-DEACT-STOMP|GMATCH-RFTD-STOMP|GND-OOB-WRITE|ENTER-STATE-CODE-REPAIR)' "$LOG" | sort | uniq -c | tr '\n' ';')

STATUS=UNKNOWN
if crash_seen; then STATUS="HARD-CRASH-after-${FC}-fires"
elif [ "$FC" -ge "$COUNT" ] && [ "$FOC" = yes ] && [ "$DF" -ge 5 ]; then STATUS="DEATH-CRASH-FREE-${FC}/${COUNT}-render+${DF}"
elif [ "$FOC" = yes ] && [ "$DF" -ge 5 ]; then STATUS="PARTIAL-${FC}/${COUNT}-render-advancing"
elif [ "$DF" -lt 5 ] && [ "$FOC" = yes ]; then STATUS="RENDER-LOCK-${FC}-fires-frozen"
fi
{
  echo "RESULT mode=$MODE tag=$RUN_TAG status=$STATUS"
  echo "  fires=$FC/$COUNT crash=$(crash_seen && echo YES || echo no) focus_app=$FOC frame +$DF (F0=$F0 F1=$F1)"
  echo "  sig=${SIG:-none} fp-walk-lines=$FPWALK"
  echo "  near-fn: ${NEARFN:-none}"
  echo "  cur-proc: ${CURPROC:-none}"
  echo "  stomps: ${STOMP:-none}"
} | tee "$RESULT"
kill "$LCPID" 2>/dev/null||true; trap - EXIT; cleanup
