#!/usr/bin/env bash
# Phase Ginput-replay: build APK with the harness, install on the device,
# deploy_verify, then run the on-device pad-replay SELF-TEST (prop-gated) and
# pull the demo + per-logic-tick state dump for the cross-backend comparison.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

OUT_DIR=".autoport/reports/Ginput-replay"
mkdir -p "$OUT_DIR"
PACKAGE="org.opengoal.gk.jak1"
SERIAL="${ANDROID_SERIAL:-eae4df44}"
export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
FILES="/data/data/$PACKAGE/files"
LOG="$OUT_DIR/device-selftest-logcat.log"
A(){ "$ADB" -s "$SERIAL" "$@"; }

echo "== assemble slim APK (libgk already built fresh) =="
( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 | tail -n 6 ) || { echo "FAIL gradle"; exit 1; }
[ -f "$APK" ] || { echo "FAIL no APK"; exit 1; }

echo "== install + deploy_verify =="
device_require_attached; device_stayon_on
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
device_require_unlocked; device_miui_unblock_install
STAGE="/data/local/tmp/$(basename "$APK")"
A push "$APK" "$STAGE" >/tmp/gi-push.out 2>&1 || { cat /tmp/gi-push.out; echo "FAIL push"; exit 1; }
A shell pm install -r -d -t -i com.android.vending "$STAGE" >/tmp/gi-pm.out 2>&1 || { cat /tmp/gi-pm.out; echo "FAIL install"; exit 1; }
grep -q Success /tmp/gi-pm.out || { cat /tmp/gi-pm.out; echo "FAIL no Success"; exit 1; }
A shell rm -f "$STAGE" >/dev/null 2>&1 || true
bash .autoport/lib/deploy_verify.sh "$SERIAL" || { echo "FAIL deploy_verify"; exit 1; }
echo "DEPLOY_VERIFY: PASS"

echo "== arm on-device pad-replay SELF-TEST + (re)launch =="
A shell run-as "$PACKAGE" rm -f "$FILES/selftest.inputs" "$FILES/selftest.inputs.statedump.txt" >/dev/null 2>&1 || true
A shell setprop debug.opengoal.pad_replay selftest >/dev/null 2>&1 || true
A shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
sleep 2
A logcat -c >/dev/null 2>&1 || true
A shell am start -n "$PACKAGE/.LoaderActivity" >/dev/null 2>&1 || true
( A logcat -v time GK_STDOUT:I '*:S' > "$LOG" 2>&1 ) &
LCPID=$!
trap 'kill $LCPID 2>/dev/null || true' EXIT

echo "== wait for PAD DIFF marker (up to 60s) =="
for i in $(seq 1 30); do grep -aq "PAD DIFF" "$LOG" && break; sleep 2; done
kill $LCPID 2>/dev/null || true

echo "-- device self-test logcat lines --" | tee "$OUT_DIR/device-selftest.txt"
grep -aE "pad_replay|PAD DIFF|DETERMIN|DIVERG|SELFTEST" "$LOG" | sed 's/.*GK_STDOUT[^:]*: //' | tee -a "$OUT_DIR/device-selftest.txt"

echo "== pull demo + state dump from device =="
A shell run-as "$PACKAGE" cat "$FILES/selftest.inputs" > "$OUT_DIR/selftest-arm64.inputs" 2>/dev/null || true
A shell run-as "$PACKAGE" cat "$FILES/selftest.inputs.statedump.txt" > "$OUT_DIR/statedump-arm64.txt" 2>/dev/null || true
echo "  arm64 demo bytes: $(wc -c < "$OUT_DIR/selftest-arm64.inputs" 2>/dev/null || echo 0)"
echo "  arm64 statedump lines: $(wc -l < "$OUT_DIR/statedump-arm64.txt" 2>/dev/null || echo 0)"

echo "== CROSS-BACKEND state-anchored compare (x86 vs arm64, keyed by logic tick) =="
if cmp -s "$OUT_DIR/statedump-x86.txt" "$OUT_DIR/statedump-arm64.txt"; then
  echo "CROSS-BACKEND: statedump BIT-IDENTICAL at all matching logic ticks (x86 == arm64)" | tee "$OUT_DIR/crossbackend.txt"
else
  echo "CROSS-BACKEND: statedump DIFFERS — first divergence:" | tee "$OUT_DIR/crossbackend.txt"
  diff "$OUT_DIR/statedump-x86.txt" "$OUT_DIR/statedump-arm64.txt" | head -8 | tee -a "$OUT_DIR/crossbackend.txt"
fi
if cmp -s .autoport/demos/selftest.inputs "$OUT_DIR/selftest-arm64.inputs"; then
  echo "CROSS-BACKEND: recorded demo bytes BIT-IDENTICAL (x86 == arm64)" | tee -a "$OUT_DIR/crossbackend.txt"
fi

echo "== disarm self-test prop (normal boot restored) =="
A shell setprop debug.opengoal.pad_replay "" >/dev/null 2>&1 || true
FOC=$(A shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | grep -c "$PACKAGE")
echo "focus_app=$FOC"
echo "DONE"
