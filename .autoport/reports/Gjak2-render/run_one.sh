#!/usr/bin/env bash
# Gjak2-render concurrent-GOAL race experiment: run ONE jak2 boot sample.
# Usage: run_one.sh <run_index> <wait_seconds>
set -u
export PATH="$HOME/Android/platform-tools:$PATH"
export ANDROID_SERIAL=eae4df44
SER=eae4df44
PKG=org.opengoal.gk.jak2
ACT=org.opengoal.gk.jak2/org.opengoal.gk.LoaderActivity
IDX="$1"
WAIT="${2:-150}"
DIR=/home/emeric/code/jak-project/.autoport/reports/Gjak2-render
LOG="$DIR/jak2-race-run${IDX}.log"

echo "=== RUN $IDX start $(date +%T) ==="
# keep awake
adb -s $SER shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
adb -s $SER shell svc power stayon true >/dev/null 2>&1
# force-stop + clear log
adb -s $SER shell am force-stop $PKG >/dev/null 2>&1
sleep 2
adb -s $SER logcat -c >/dev/null 2>&1
# start background logcat to file
adb -s $SER logcat -v time > "$LOG" 2>&1 &
LOGPID=$!
sleep 1
# launch
adb -s $SER shell am start -n "$ACT" >/dev/null 2>&1
# wait using a device-side loop so we don't block the harness foreground sleep
END=$(( $(date +%s) + WAIT ))
while [ "$(date +%s)" -lt "$END" ]; do
  sleep 5
done
# capture end-of-run state BEFORE stopping logcat
FOCUS=$(adb -s $SER shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
PIDOF=$(adb -s $SER shell pidof $PKG 2>/dev/null | tr -d '\r')
# stop logcat capture
kill "$LOGPID" >/dev/null 2>&1
wait "$LOGPID" 2>/dev/null
echo "=== RUN $IDX end $(date +%T) ==="
echo "focus: $FOCUS"
echo "pidof $PKG: ${PIDOF:-<none>}"
echo "logfile: $LOG ($(wc -l < "$LOG") lines)"
