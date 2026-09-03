#!/usr/bin/env bash
# gmouche_device.sh — Gcrash-mouche DEVICE repro/verify (arm64 eae4df44).
#
# Drives the buzzer scout-fly pickup "fly-to-HUD" effect on the device via the
# native mouche hook (kmachine.cpp mouche_maybe_fire): with props
#   debug.opengoal.f1.warp=1   -> warp to Geyser Rock ('training)
#   debug.opengoal.mouche.fx=1 -> arm the manipy fly-to-HUD FX (the buzzer-collect
#                                 crash path) and re-fire it up to 8x via
#                                 *listener-function*, NO cpad navigation needed.
# Watches logcat for MOUCHE-ARM / MOUCHE-FIRE (FX fired), GK-DIAG sig=(4|6|11) /
# Fatal signal (the crash), render progress (A35-RENDER / F1-STATE), and the crash
# forensics (nearest-fn, F1A-MERC-DRAW, A36-SYMBOLIZE, GSPARK-PP, *-STOMP, backtrace).
#
# Usage: gmouche_device.sh <run_tag> [out_dir]
#   SKIP_BUILD=1   reuse the already-built+deployed libgk (skip build+install)
#   WATCH_S        seconds to watch after arming the FX (default 150)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

RUN_TAG="${1:-run1}"
OUT_DIR="${2:-.autoport/reports/Gcrash-mouche}"
WATCH_S="${WATCH_S:-150}"
mkdir -p "$OUT_DIR"

PACKAGE="org.opengoal.gk.jak1"
ACTIVITY=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
SERIAL="${ANDROID_SERIAL:-eae4df44}"
export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
LOG="$OUT_DIR/$RUN_TAG-logcat.log"
RESULT="$OUT_DIR/$RUN_TAG-result.txt"

A() { "$ADB" -s "$SERIAL" "$@"; }

pkill -f 'logcat.*GK_STDOUT' 2>/dev/null || true

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "== build current-HEAD libgk.so =="
  bash .autoport/lib/d3_build.sh || { echo "FAIL: libgk build"; exit 1; }
  echo "== build SLIM jak1 debug APK (libgk-only) =="
  ( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 | tail -n 15 ) \
      || { echo "FAIL: gradle slim build failed"; exit 1; }
  [ -f "$APK" ] || { echo "FAIL: $APK not produced"; exit 1; }
  echo "== install + verify fresh HEAD libgk on device =="
  device_require_attached; device_stayon_on
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  device_require_unlocked
  device_miui_unblock_install
  STAGE="/data/local/tmp/$(basename "$APK")"
  A push "$APK" "$STAGE" >/tmp/gmouche-push.out 2>&1 || { cat /tmp/gmouche-push.out; echo "FAIL: push"; exit 1; }
  A shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/gmouche-pm.out 2>&1 || { cat /tmp/gmouche-pm.out; echo "FAIL: pm install"; exit 1; }
  grep -q "Success" /tmp/gmouche-pm.out || { cat /tmp/gmouche-pm.out; echo "FAIL: pm install no Success"; exit 1; }
  A shell rm -f "$STAGE" >/dev/null 2>&1 || true
  bash .autoport/lib/deploy_verify.sh "$SERIAL" || { echo "FAIL: deploy_verify"; exit 1; }
else
  device_require_attached; device_stayon_on
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  device_require_unlocked
fi

MODE="${MODE:-fx}"   # fx = manipy fly-to-HUD FX only; buzz = full real buzzer collect
echo "== arm warp + mouche (MODE=$MODE); tag=$RUN_TAG =="
A shell setprop debug.opengoal.f1.warp   1 >/dev/null 2>&1 || true
if [ "$MODE" = "buzz" ]; then
  A shell setprop debug.opengoal.mouche.buzz 1 >/dev/null 2>&1 || true
  A shell setprop debug.opengoal.mouche.fx   0 >/dev/null 2>&1 || true
else
  A shell setprop debug.opengoal.mouche.fx   1 >/dev/null 2>&1 || true
  A shell setprop debug.opengoal.mouche.buzz 0 >/dev/null 2>&1 || true
fi

A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c   >/dev/null 2>&1 || true
: > "$LOG"
A logcat -v threadtime \
    opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V opengoal-loader:V \
    libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LOGCAT_PID=$!
cleanup() {
  kill "$LOGCAT_PID" 2>/dev/null || true
  A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
  device_stayon_restore 2>/dev/null || true
}
trap cleanup EXIT

A shell am start -W -n "$PACKAGE/$ACTIVITY" >/tmp/gmouche-am.out 2>&1 || true
grep -q 'Error' /tmp/gmouche-am.out && { cat /tmp/gmouche-am.out; echo "FAIL: am start"; exit 1; }

crash_seen() {
  grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG"
}
focus_is_app() { A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -q "$PACKAGE"; }
max_frame() { grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }
n_fires() { grep -acE 'MOUCHE-FIRE #|MOUCHE-BUZZ #' "$LOG" 2>/dev/null || echo 0; }

echo "  warming to title (link finish: logo, up to 120s)..."
for i in $(seq 1 120); do grep -qa "link finish: logo" "$LOG" && { echo "  title ~${i}s"; break; }; sleep 1; done
echo "  waiting for warp (up to 90s)..."
for i in $(seq 1 90); do grep -qa "\[F1-WARP\] (start 'play game-start)" "$LOG" && { echo "  warp fired ~${i}s"; break; }; sleep 1; done
echo "  waiting for training (Geyser Rock) load (up to 8min)..."
TRAIN_OK=0
for ((i=1;i<=96;i++)); do
  sleep 5
  if grep -qaE "Adding level training|link finish: training-vis|MOUCHE-ARM|MOUCHE-FIRE" "$LOG"; then echo "   >>> training/mouche active ~$((i*5))s"; TRAIN_OK=1; break; fi
  if crash_seen; then echo "   >>> crash before training load"; break; fi
  (( i % 6 == 0 )) && echo "   [load ${i}/96] waiting..."
done

echo "  watching ${WATCH_S}s for MOUCHE-FIRE x N / crash (FX auto-fires, no cpad)..."
FB=$(max_frame); FB=${FB:-0}
CRASHED=0
for ((s=0; s<WATCH_S; s+=3)); do
  sleep 3
  NF=$(n_fires); FM=$(max_frame); FM=${FM:-0}
  if (( s % 15 == 0 )); then echo "   [${s}/${WATCH_S}s] mouche_fires=$NF frame=$FM"; fi
  if crash_seen; then echo "   >>> CRASH after $NF mouche fires"; CRASHED=1; break; fi
done

# Forensics harvest.
FA=$(max_frame); FA=${FA:-0}; DF=$(( FA - FB ))
NFIRE=$(n_fires)
FOC="no"; focus_is_app && FOC="yes"
SIG=$(grep -aoE 'GK-DIAG sig=[0-9]+|signal (11|6|4) \(SIG[A-Z]+' "$LOG" | tail -1)
NEARFN=$(grep -aE 'A38-TRIPWIRE (pc|lr|fault) nearest-fn|nearest-fn' "$LOG" | tail -4 | tr '\n' ';')
MERC=$(grep -aE 'F1A-MERC-DRAW|F1A-BUCKET|F1E-MERC-TEX|GD3-MERC' "$LOG" | tail -3 | tr '\n' ';')
SYMB=$(grep -aE 'A36-SYMBOLIZE' "$LOG" | tail -3 | tr '\n' ';')
GSPARK=$(grep -aE 'GSPARK-PP|GSPARK-OBJ|GSPARK-STATE' "$LOG" | tail -3 | tr '\n' ';')
STOMP=$(grep -aoE '(GCINE3-DEACT-STOMP|GMATCH-RFTD-STOMP|RFTD-STOMP-REPAIR|RFTD-NULLRET-REDIRECT|GND-OOB-WRITE|DBLEE-REPAIR)' "$LOG" | sort | uniq -c | tr '\n' ';')
BT=$(grep -aE '#[0-9]{2} pc [0-9a-f]+' "$LOG" | head -12 | tr '\n' ';')
MFIRE=$(grep -aE 'MOUCHE-FIRE #|MOUCHE-BUZZ|MOUCHE-SKIP|MOUCHE-HUD|MOUCHE-ARM' "$LOG" | tail -16 | tr '\n' ';')

STATUS="UNKNOWN"
if [ "$CRASHED" = 1 ]; then
  STATUS="BUZZER-FX-CRASH(sig=${SIG:-?})"
elif [ "$NFIRE" -ge 1 ] && [ "$DF" -ge 5 ] && [ "$FOC" = "yes" ]; then
  STATUS="BUZZER-FX-CRASH-FREE(fires=$NFIRE,frames+$DF)"
elif [ "$NFIRE" -lt 1 ]; then
  STATUS="NO-FIRE(mouche never armed/fired — investigate readiness)"
else
  STATUS="INCONCLUSIVE(fires=$NFIRE,frames+$DF,focus=$FOC)"
fi

{
  echo "RESULT tag=$RUN_TAG status=$STATUS"
  echo "  mouche_fires=$NFIRE  render_frames +$DF (from $FB to $FA)  focus_app=$FOC"
  echo "  sig=${SIG:-none}"
  echo "  mouche-markers: ${MFIRE:-none}"
  echo "  near-fn: ${NEARFN:-none}"
  echo "  merc-draw: ${MERC:-none}"
  echo "  symbolize: ${SYMB:-none}"
  echo "  gspark: ${GSPARK:-none}"
  echo "  stomps: ${STOMP:-none}"
  echo "  backtrace: ${BT:-none}"
} | tee "$RESULT"

kill "$LOGCAT_PID" 2>/dev/null || true
trap - EXIT
A shell setprop debug.opengoal.mouche.fx 0 >/dev/null 2>&1 || true
A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
device_stayon_restore 2>/dev/null || true
echo "== gmouche_device.sh $RUN_TAG done: $STATUS =="
exit 0
