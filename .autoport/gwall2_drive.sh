#!/usr/bin/env bash
# Gcollision-wallslide RELIABLE reproduction+measurement driver.
# Warps to Geyser Rock, drives forward-jumps into the walls right of the steps,
# and captures the GWALL2 diagnostic (kmachine.cpp) which logs, per frame, the
# *target* state-name + trans + collision floats + the RELIABLE cpad button word
# (button0 = g_overlay_button0|g_inject_button0, the exact word cpad-hold? reads).
# Decisive value: at a LATCHED st=target-duck-stance, l1r1=1 => phantom L1/R1 hold
# (input divergence); l1r1=0 => can-exit-duck? wrongly #f (collision divergence).
#
# Usage: gwall2_drive.sh <run_tag>   (SKIP_BUILD=1 to reuse the deployed libgk)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

RUN_TAG="${1:-run1}"
OUT_DIR=".autoport/reports/Gcollision-wallslide"
mkdir -p "$OUT_DIR"
PACKAGE="org.opengoal.gk.jak1"
SERIAL="${ANDROID_SERIAL:-eae4df44}"
export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
INJECT="/data/data/$PACKAGE/files/cpad_inject"
LOG="$OUT_DIR/$RUN_TAG-logcat.log"
RESULT="$OUT_DIR/$RUN_TAG-result.txt"
A(){ "$ADB" -s "$SERIAL" "$@"; }
inj(){ printf '%s' "$1" | A shell "run-as $PACKAGE sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
snap(){ A shell screencap -p /sdcard/gw.png >/dev/null 2>&1 || true; A pull /sdcard/gw.png "$OUT_DIR/$RUN_TAG-$1.png" >/dev/null 2>&1 || true; }

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "== build current-HEAD libgk =="; bash .autoport/lib/d3_build.sh || { echo "FAIL build"; exit 1; }
  echo "== assemble slim APK =="; ( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 | tail -n 8 ) || { echo "FAIL gradle"; exit 1; }
  [ -f "$APK" ] || { echo "FAIL no APK"; exit 1; }
  echo "== install + deploy_verify =="
  device_require_attached; device_stayon_on
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  device_require_unlocked; device_miui_unblock_install
  STAGE="/data/local/tmp/$(basename "$APK")"
  A push "$APK" "$STAGE" >/tmp/gw-push.out 2>&1 || { cat /tmp/gw-push.out; echo "FAIL push"; exit 1; }
  A shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/gw-pm.out 2>&1 || { cat /tmp/gw-pm.out; echo "FAIL install"; exit 1; }
  grep -q Success /tmp/gw-pm.out || { cat /tmp/gw-pm.out; echo "FAIL no Success"; exit 1; }
  A shell rm -f "$STAGE" >/dev/null 2>&1 || true
  bash .autoport/lib/deploy_verify.sh "$SERIAL" || { echo "FAIL deploy_verify"; exit 1; }
else
  device_require_attached; device_stayon_on
  A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  device_require_unlocked
fi

echo "== arm warp + collision log, (re)launch =="
A shell setprop debug.opengoal.f1.warp 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.coll.log 1 >/dev/null 2>&1 || true
A shell setprop debug.opengoal.pussret "${PUSSRET:-}" >/dev/null 2>&1 || true
echo "  pussret mode = '${PUSSRET:-unset}'"
inj ""
A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
sleep 2
A logcat -c >/dev/null 2>&1 || true
A shell am start -n "$PACKAGE/.LoaderActivity" >/dev/null 2>&1 || true
( A logcat -v time GK_STDOUT:I '*:S' > "$LOG" 2>&1 ) &
LCPID=$!
trap 'kill $LCPID 2>/dev/null || true; inj ""' EXIT

echo "== wait for link finish + F1-SPAWN (up to 120s) =="
for i in $(seq 1 60); do grep -aq "F1-SPAWN" "$LOG" && break; sleep 2; done
grep -aq "F1-SPAWN" "$LOG" || echo "WARN: no F1-SPAWN yet"
sleep 6
snap 00_spawn

# Baseline: NO input, standing. Confirm l1r1=0 at rest (no phantom while idle).
echo "== baseline: 6s no input =="; inj ""; sleep 6; snap 01_idle

# Drive: forward-jumps into walls right of the steps, with steering sweeps.
# Each micro-step: hold a token ~0.9s, release ~0.3s, so a dropped event has a
# window; repeat across steering angles to hit several walls.
drive_seq() {
  local steer="$1"
  inj "ly=20 ${steer}"; sleep 1.0
  inj "ly=20 ${steer} x"; sleep 0.7
  inj "ly=20 ${steer}"; sleep 1.0
  inj "ly=20 ${steer} x"; sleep 0.7
  inj "ly=20 ${steer}"; sleep 1.2
  inj ""; sleep 1.5     # RELEASE everything, let any stuck-crouch settle + log
}
for pass in 1 2 3 4 5 6; do
  for steer in "" "lx=70" "lx=185" "lx=40" "lx=210" ""; do
    drive_seq "$steer"
  done
  inj ""; sleep 2.0
  snap "pass${pass}"
  # report current latched state
  LAST=$(grep -a "GWALL2" "$LOG" | tail -1)
  echo "  pass${pass} last: $LAST"
done

# Final: ensure released, dwell 8s so any latched duck-stance is densely logged.
inj ""; sleep 8; snap 99_final
kill $LCPID 2>/dev/null || true

echo "== ANALYSIS ==" | tee "$RESULT"
echo "-- distinct states seen --" | tee -a "$RESULT"
grep -ao "st=[a-z0-9-]*" "$LOG" | sort | uniq -c | sort -rn | head -20 | tee -a "$RESULT"
echo "-- duck-stance frames: l1r1 distribution --" | tee -a "$RESULT"
grep -a "st=target-duck-stance" "$LOG" | grep -ao "l1r1=[01]" | sort | uniq -c | tee -a "$RESULT"
echo "-- duck-stance sample lines (first 6, last 6) --" | tee -a "$RESULT"
grep -a "st=target-duck-stance" "$LOG" | head -6 | tee -a "$RESULT"
echo "  ..." | tee -a "$RESULT"
grep -a "st=target-duck-stance" "$LOG" | tail -6 | tee -a "$RESULT"
echo "-- LATCHED runs (>=20 consecutive duck-stance frames at same tx) --" | tee -a "$RESULT"
grep -a "GWALL2" "$LOG" | awk '
  /st=target-duck-stance/ { match($0,/tx=[-0-9.]+/); tx=substr($0,RSTART,RLENGTH); match($0,/l1r1=[01]/); lr=substr($0,RSTART,RLENGTH);
    if (tx==ptx) { n++ } else { if (n>=20) print "  latched "n" frames "ptx" "plr; n=1; ptx=tx } plr=lr; next }
  { if (n>=20) print "  latched "n" frames "ptx" "plr; n=0; ptx="" }
  END { if (n>=20) print "  latched "n" frames "ptx" "plr }' | tee -a "$RESULT"
echo "-- any non-finite floats? --" | tee -a "$RESULT"
grep -a "GWALL2" "$LOG" | grep -ac "nan\|inf" | tee -a "$RESULT"
FOC=$(A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -c "$PACKAGE")
echo "focus_app=$FOC  logcat=$LOG" | tee -a "$RESULT"
echo "DONE $RUN_TAG"
