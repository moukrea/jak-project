#!/usr/bin/env bash
# gbirds_device_dump.sh — capture the title-screen bird bob anim-advance (GBIRDS2D)
# from the device, with an optional freeze toggle for BEFORE/AFTER calibration.
#
# Usage: gbirds_device_dump.sh <freeze 0|1> <out_label> [capture_secs]
#   freeze=1 -> setprop debug.gbirds.freeze 1  (bird-bob callback skipped -> bob frozen = BEFORE)
#   freeze=0 -> setprop debug.gbirds.freeze 0  (natural bob = AFTER)
# Writes .autoport/reports/Gbirds-anim/<out_label>-gbirds.txt (filtered GBIRDS2D lines)
# and  .autoport/reports/Gbirds-anim/<out_label>-logcat.log (raw filtered logcat).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
FREEZE="${1:-0}"; LABEL="${2:-device}"; SECS="${3:-120}"
OUTDIR=.autoport/reports/Gbirds-anim
RAW="$OUTDIR/${LABEL}-logcat.log"; OUT="$OUTDIR/${LABEL}-gbirds.txt"
adb(){ timeout 25 "$ADB" -s "$S" "$@"; }
die(){ echo "[gbirds-dev FAIL] $*" >&2; exit 1; }
mkdir -p "$OUTDIR"

adb get-state >/dev/null 2>&1 || die "device $S not attached"
# keep the screen awake (device PIN-locks on sleep -> 0 render frames)
adb shell settings put global stay_on_while_plugged_in 7 >/dev/null 2>&1 || true
adb shell svc power stayon true >/dev/null 2>&1 || true
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
LOCKED=$(adb shell dumpsys window 2>/dev/null | grep -m1 -oE 'mDreamingLockscreen=(true|false)')
echo "  lock: ${LOCKED:-unknown}"

echo "== set debug.gbirds.freeze=$FREEZE =="
adb shell setprop debug.gbirds.freeze "$FREEZE" >/dev/null 2>&1 || true
echo "  prop now: $(adb shell getprop debug.gbirds.freeze | tr -d '\r')"

echo "== relaunch app + capture GBIRDS2D for ${SECS}s =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
: > "$RAW"
( "$ADB" -s "$S" logcat -v threadtime | grep --line-buffered -aE 'GBIRDS2D|link finish:|Fatal signal|signal (11|6|4) \(SIG' > "$RAW" ) &
LCP=$!
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt "$SECS" ]; do
  adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  sleep 5
done
kill ${LCP:-0} 2>/dev/null || true

FOCUS=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
echo "  focus: $FOCUS"
grep -a "GBIRDS2D" "$RAW" > "$OUT" 2>/dev/null || true
N=$(wc -l < "$OUT" 2>/dev/null | tr -d ' ')
LF=$(grep -ac "link finish: logo" "$RAW" 2>/dev/null)
CRASH=$(grep -acE "Fatal signal|signal (11|6|4) \(SIG" "$RAW" 2>/dev/null)
echo "[gbirds-dev] label=$LABEL freeze=$FREEZE GBIRDS2D_lines=$N link_finish_logo=$LF crash_lines=$CRASH"
echo "[gbirds-dev] wrote $OUT and $RAW"
