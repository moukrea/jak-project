#!/usr/bin/env bash
# Reproduce the death crash on device by replaying the owner demo.
# Captures full logcat (incl. in-binary GK-DIAG/A38/A34 forensics) and asserts
# crash + foreground state. Crash-capture-window: runs PAST the crash, checks focus.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh 2>/dev/null
ADB="/home/emeric/Android/platform-tools/adb"; S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Gdeath-crash
DEMO=.autoport/demos/death-crash.inputs
LOG="$OUT/device-repro-logcat.log"
STATUS="$OUT/device-repro-status.txt"
DUR="${1:-480}"   # seconds to run

echo "START $(date -Iseconds)" > "$STATUS"

# keep awake
$ADB -s $S shell svc power stayon true >/dev/null 2>&1 || true
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true

# arm replay
$ADB -s $S push "$DEMO" /data/local/tmp/pad_demo.inputs >/dev/null 2>&1
$ADB -s $S shell run-as $PKG cp /data/local/tmp/pad_demo.inputs files/pad_demo.inputs
$ADB -s $S shell setprop debug.opengoal.pad_replay replay
echo "replay-armed prop=$($ADB -s $S shell getprop debug.opengoal.pad_replay)" >> "$STATUS"

# fresh logcat
$ADB -s $S logcat -G 64M >/dev/null 2>&1 || true
$ADB -s $S shell am force-stop $PKG
$ADB -s $S logcat -c 2>/dev/null || true
sleep 1

# start capture (background) + app
( $ADB -s $S logcat -v threadtime opengoal-gk:* GK_STDOUT:* DEBUG:* libc:* AndroidRuntime:* '*:S' > "$LOG" 2>&1 ) &
LCPID=$!
sleep 1
$ADB -s $S shell am start -n $PKG/.LoaderActivity >/dev/null 2>&1
echo "launched $(date -Iseconds)" >> "$STATUS"

CRASH_AT=""
END=$((SECONDS+DUR))
while [ $SECONDS -lt $END ]; do
  sleep 15
  if grep -aqE 'Fatal signal|signal (11|6|4) \(SIG|GK-DIAG sig=(4|6|11)' "$LOG" 2>/dev/null; then
    CRASH_AT="$(date -Iseconds)"
    echo "CRASH-DETECTED $CRASH_AT" >> "$STATUS"
    # let the in-binary forensics (fp-walk/A38/A34) finish flushing
    sleep 8
    break
  fi
done

FOCUS="$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1)"
PID="$($ADB -s $S shell pidof $PKG 2>/dev/null)"
echo "FOCUS_AT_END: $FOCUS" >> "$STATUS"
echo "PID_AT_END: ${PID:-none}" >> "$STATUS"
echo "CRASH_AT: ${CRASH_AT:-none}" >> "$STATUS"

# disarm + stop capture
$ADB -s $S shell setprop debug.opengoal.pad_replay "" >/dev/null 2>&1
kill $LCPID 2>/dev/null || true
echo "DONE $(date -Iseconds)" >> "$STATUS"
echo "logcat lines: $(wc -l < "$LOG")" >> "$STATUS"
