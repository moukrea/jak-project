#!/usr/bin/env bash
# village-water burst: reuse the installed APK, fly the attract, and at the
# wide-ocean PRESS-START dwell (~t72-86s) grab a tight burst of consecutive
# frames (~0.25s apart) to isolate WAVE animation from camera motion.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh
export ANDROID_SERIAL=eae4df44
TAG="${1:-burst}"
PKG="org.opengoal.gk.jak1"; ACT=".LoaderActivity"
RDIR=".autoport/reports/village-water"
LOG="$RDIR/villwater-routed-logcat-${TAG}.log"
FOCUS="$RDIR/villwater-focus-${TAG}.txt"
mkdir -p "$RDIR"
INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers() { for p in "${INTERLOPERS[@]}"; do adb shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers() { for p in "${INTERLOPERS[@]}"; do adb shell am force-stop "$p" >/dev/null 2>&1 || true; adb shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }
frame_max() { grep -a "A35-RENDER frame=" "$LOG" 2>/dev/null | grep -oE "frame=[0-9]+" | grep -oE "[0-9]+" | sort -n | tail -1; }
sig_count() { grep -acE "GK-DIAG sig=11|exited due to signal 11|Fatal signal 11" "$LOG" 2>/dev/null || true; }
cap() { local name="$1"; local fm; fm=$(frame_max); fm=${fm:-0}; adb shell screencap -p /sdcard/vw.png >/dev/null 2>&1 || true; adb pull /sdcard/vw.png "$RDIR/device-${TAG}-${name}.png" >/dev/null 2>&1 || true; adb shell rm -f /sdcard/vw.png >/dev/null 2>&1 || true; echo "  [$name] frame=$fm -> device-${TAG}-${name}.png"; echo "$name frame=$fm" >> "$FOCUS"; }
device_require_attached
disable_interlopers
trap 'reenable_interlopers; kill ${LOGCAT_PID:-0} 2>/dev/null; adb shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on
: > "$FOCUS"
device_require_unlocked
adb shell am force-stop "$PKG" 2>/dev/null || true
adb logcat -G 16M 2>/dev/null || true; adb logcat -c 2>/dev/null || true
adb logcat -v threadtime > "$LOG" 2>&1 & LOGCAT_PID=$!
START_MS=$(date +%s%3N)
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
# wait until the wide-ocean dwell (~72s), then tight burst
now=$(( $(date +%s%3N) - START_MS )); want=72000
if [ "$want" -gt "$now" ]; then sleep "$(awk "BEGIN{printf \"%.3f\", ($want-$now)/1000}")"; fi
for b in $(seq -w 1 16); do
  cap "f${b}"
  sleep 0.25
done
FM=$(frame_max); FM=${FM:-0}; SC=$(sig_count); SC=${SC:-0}
echo "== final frame_max=$FM sig11=$SC =="
kill ${LOGCAT_PID:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
adb shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true
echo "focus: $FOCUS"
