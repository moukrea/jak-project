#!/usr/bin/env bash
# ghint_device.sh — Gaudio-hint-voices: capture the IN-GAME tutorial/hint VOICE path
# on the real device (arm64 eae4df44). Warps to Geyser Rock ('training), enables the
# per-source RMS meter (debug.opengoal.audio.rms) + the HINT-PROBE (srpc.cpp, gated by
# debug.opengoal.hint.probe), idles to let training-intro auto-hints fire, then teleports
# to crates and spin-attacks them (crate hints + crate-break SFX). Greps:
#   [HINT-PROBE] PLAY ...           every sound-play-by-name (spool? + 128-bit name bytes)
#   [HINT-PROBE] SPOOL resolve ...  FindVAGFile result for a streamed hint/voice
#   A42-STRCLK PlayVag id= fd=      did the VAG stream actually open + key on
#   AUDIODIAG rms ... stream=.. sfx=.. music=..   per-source levels over time
#
# Usage: ghint_device.sh <run_tag> [out_dir]
#   SKIP_BUILD=1   reuse already-built+deployed libgk (skip build/install)
#   IDLE_S=N       seconds to idle after training load before crate phase (default 30)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

RUN_TAG="${1:-run1}"
OUT_DIR="${2:-.autoport/reports/Gaudio-hint-voices}"
IDLE_S="${IDLE_S:-30}"
mkdir -p "$OUT_DIR"

PACKAGE="org.opengoal.gk.jak1"
ACTIVITY=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
SERIAL="${ANDROID_SERIAL:-eae4df44}"
export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
INJECT="/data/data/$PACKAGE/files/cpad_inject"
LOG="$OUT_DIR/$RUN_TAG-logcat.log"
SUM="$OUT_DIR/$RUN_TAG-summary.txt"

A() { "$ADB" -s "$SERIAL" "$@"; }
inject() { printf '%s' "$1" | A shell "run-as $PACKAGE sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clear_inject() { inject ""; }

pkill -f 'logcat.*GK_STDOUT' 2>/dev/null || true

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "== build current-HEAD libgk.so (with HINT-PROBE) =="
  bash .autoport/lib/d3_build.sh || { echo "FAIL: libgk build"; exit 1; }
  echo "== build SLIM jak1 debug APK (libgk-only) =="
  ( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 | tail -n 12 ) \
      || { echo "FAIL: gradle slim build"; exit 1; }
  [ -f "$APK" ] || { echo "FAIL: $APK not produced"; exit 1; }
  echo "== install + deploy_verify fresh HEAD libgk =="
  device_require_attached; device_stayon_on
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  device_require_unlocked; device_miui_unblock_install
  STAGE="/data/local/tmp/$(basename "$APK")"
  A push "$APK" "$STAGE" >/tmp/gh-push.out 2>&1 || { cat /tmp/gh-push.out; echo "FAIL: push"; exit 1; }
  A shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/gh-pm.out 2>&1 || { cat /tmp/gh-pm.out; echo "FAIL: pm install"; exit 1; }
  grep -q "Success" /tmp/gh-pm.out || { cat /tmp/gh-pm.out; echo "FAIL: pm install no Success"; exit 1; }
  A shell rm -f "$STAGE" >/dev/null 2>&1 || true
  bash .autoport/lib/deploy_verify.sh "$SERIAL" || { echo "FAIL: deploy_verify"; exit 1; }
else
  device_require_attached; device_stayon_on
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  device_require_unlocked
fi

echo "== arm warp + teleport + audio probes =="
A shell setprop debug.opengoal.audio.rms  1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.hint.probe 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.f1.warp    1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.tele       1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.tele.idx  -1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.tele.gen   0 >/dev/null 2>&1 || true

A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c   >/dev/null 2>&1 || true
: > "$LOG"
A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V '*:S' > "$LOG" 2>&1 &
LOGCAT_PID=$!
cleanup() {
  kill "$LOGCAT_PID" 2>/dev/null || true
  clear_inject
  A shell setprop debug.opengoal.tele 0 >/dev/null 2>&1 || true
  A shell setprop debug.opengoal.hint.probe 0 >/dev/null 2>&1 || true
  A shell setprop debug.opengoal.audio.rms 0 >/dev/null 2>&1 || true
  A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
  device_stayon_restore 2>/dev/null || true
}
trap cleanup EXIT

A shell am start -W -n "$PACKAGE/$ACTIVITY" >/tmp/gh-am.out 2>&1 || true

crash_seen() { grep -qaE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG"; }

echo "  warming to title (link finish: logo, up to 120s)..."
for i in $(seq 1 120); do grep -qa "link finish: logo" "$LOG" && { echo "  title ~${i}s"; break; }; sleep 1; done
echo "  waiting for warp/spawn (F1-SPAWN, up to 90s)..."
for i in $(seq 1 90); do grep -qa "F1-SPAWN" "$LOG" && { echo "  spawn ~${i}s"; break; }; sleep 1; done
echo "  waiting for training (Geyser Rock) load (up to 8min)..."
for ((i=1;i<=96;i++)); do
  sleep 5
  grep -qaE "Adding level training|link finish: training" "$LOG" && { echo "   >>> training active ~$((i*5))s"; break; }
  crash_seen && { echo "   >>> crash before training load"; break; }
done
sleep 8  # settle

echo "== PHASE 1: idle ${IDLE_S}s (training-intro auto-hints + RMS baseline) =="
sleep "$IDLE_S"

echo "== PHASE 2: wander + break crates (crate hints + crate-break SFX) =="
GEN=0
# small wander to provoke proximity hints
for dir in "ly=15" "ly=240" "lx=15" "lx=240"; do
  inject "$dir"; sleep 1.2; clear_inject; sleep 0.4
done
for ((i=0;i<=6;i++)); do
  GEN=$((GEN+1))
  A shell setprop debug.opengoal.tele.idx "$i"  >/dev/null 2>&1 || true
  A shell setprop debug.opengoal.tele.gen "$GEN" >/dev/null 2>&1 || true
  for w in $(seq 1 16); do grep -qaE "TELE-JAK idx=$i" "$LOG" && break; sleep 0.25; done
  sleep 0.4
  inject "circle"; sleep 1.4; clear_inject   # spin attack -> break crate
  sleep 1.6
  crash_seen && { echo "   crash at crate $i"; break; }
done

echo "== PHASE 3: idle 15s (let any late hint stream finish) =="
sleep 15

clear_inject
kill "$LOGCAT_PID" 2>/dev/null || true

echo "============== SUMMARY ==============" | tee "$SUM"
FOC=$(A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -c "$PACKAGE")
echo "focus_app=$FOC  crash=$(crash_seen && echo YES || echo no)" | tee -a "$SUM"
echo "--- [HINT-PROBE] PLAY lines (all sound-play-by-name; spool=1 -> streamed voice) ---" | tee -a "$SUM"
grep -a "\[HINT-PROBE\] PLAY" "$LOG" | sed 's/.*\[HINT-PROBE\]/[HINT-PROBE]/' | sort | uniq -c | sort -rn | head -50 | tee -a "$SUM"
echo "--- spool=1 PLAY (the in-game hint/cutscene VOICES) ---" | tee -a "$SUM"
grep -a "\[HINT-PROBE\] PLAY" "$LOG" | grep -a "spool=1" | sed 's/.*\[HINT-PROBE\]/[HINT-PROBE]/' | sort -u | tee -a "$SUM"
echo "--- [HINT-PROBE] SPOOL resolve (FindVAGFile=0x0 -> SILENT hint) ---" | tee -a "$SUM"
grep -a "\[HINT-PROBE\] SPOOL" "$LOG" | sed 's/.*\[HINT-PROBE\]/[HINT-PROBE]/' | sort | uniq -c | sort -rn | head -40 | tee -a "$SUM"
echo "--- A42-STRCLK PlayVag (stream open: fd=1 ok / fd=0 no file) ---" | tee -a "$SUM"
grep -a "A42-STRCLK PlayVag" "$LOG" | sed 's/.*A42-STRCLK/A42-STRCLK/' | sort | uniq -c | sort -rn | head -20 | tee -a "$SUM"
echo "--- AUDIODIAG rms timeline (stream=voice tag1, sfx=tag2, music=tag3); nonzero stream = a voice reached output ---" | tee -a "$SUM"
grep -a "AUDIODIAG rms" "$LOG" | sed 's/.*AUDIODIAG/AUDIODIAG/' | tee -a "$OUT_DIR/$RUN_TAG-rms.txt" | awk 'NR%4==1' | tail -40 | tee -a "$SUM"
echo "--- AUDIODIAG max stream/sfx/music seen ---" | tee -a "$SUM"
grep -a "AUDIODIAG rms" "$LOG" | grep -aoE 'stream=[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1 | sed 's/^/  max stream RMS avg = /' | tee -a "$SUM"
grep -a "AUDIODIAG rms" "$LOG" | grep -aoE 'sfx=[0-9]+'    | grep -oE '[0-9]+' | sort -n | tail -1 | sed 's/^/  max sfx    RMS avg = /' | tee -a "$SUM"
grep -a "AUDIODIAG rms" "$LOG" | grep -aoE 'music=[0-9]+'  | grep -oE '[0-9]+' | sort -n | tail -1 | sed 's/^/  max music  RMS avg = /' | tee -a "$SUM"
echo "DONE — log=$LOG summary=$SUM"
