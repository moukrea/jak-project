#!/usr/bin/env bash
# Gjak2-render VAG null-guard verification. 420s per run, full logcat + gated caps.
set -u
export PATH="$HOME/Android/platform-tools:$PATH"
export ANDROID_SERIAL=eae4df44
SER=eae4df44
PKG=org.opengoal.gk.jak2
ACT="$PKG/org.opengoal.gk.LoaderActivity"
DIR=/home/emeric/code/jak-project/.autoport/reports/Gjak2-render
WAIT=420
IDX="$1"
LOG="$DIR/jak2-vagfix-run${IDX}.log"

echo "===== RUN $IDX start $(date +%T) -> $LOG ====="
# stale runner guard
pgrep -af 'run_vagfix|run_one|run_badptr' | grep -v $$ | grep -v grep || true
adb -s $SER shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
adb -s $SER shell svc power stayon true >/dev/null 2>&1
adb -s $SER shell am force-stop "$PKG" >/dev/null 2>&1
sleep 2
adb -s $SER logcat -c >/dev/null 2>&1
adb -s $SER logcat -v time > "$LOG" 2>&1 &
LCPID=$!
sleep 1
adb -s $SER shell am start -n "$ACT" >/dev/null 2>&1
END=$(( $(date +%s) + WAIT ))
while [ "$(date +%s)" -lt "$END" ]; do sleep 5; done

# end-of-run evidence: focus + pid FIRST
FOCUS=$(adb -s $SER shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
PID=$(adb -s $SER shell pidof "$PKG" 2>/dev/null | tr -d '\r')
echo "----FOCUS-AT-END---- $FOCUS" | tee -a "$LOG"
echo "----PID-AT-END---- ${PID:-<none>}" | tee -a "$LOG"

# main screencap
adb -s $SER exec-out screencap -p > "$DIR/jak2-vagfix-run${IDX}.png" 2>/dev/null
echo "cap A done: $(stat -c%s "$DIR/jak2-vagfix-run${IDX}.png") bytes"

# -b/-c only if pid alive AND focus is jak2
if [ -n "$PID" ] && echo "$FOCUS" | grep -q 'org.opengoal.gk.jak2'; then
  echo "GATE PASS: pid alive + focus=jak2 -> capturing -b/-c 10s apart"
  adb -s $SER exec-out screencap -p > "$DIR/jak2-vagfix-run${IDX}-b.png" 2>/dev/null
  sleep 10
  FOCUS2=$(adb -s $SER shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
  PID2=$(adb -s $SER shell pidof "$PKG" 2>/dev/null | tr -d '\r')
  echo "----FOCUS-AT-C---- $FOCUS2" | tee -a "$LOG"
  echo "----PID-AT-C---- ${PID2:-<none>}" | tee -a "$LOG"
  if [ -n "$PID2" ] && echo "$FOCUS2" | grep -q 'org.opengoal.gk.jak2'; then
    adb -s $SER exec-out screencap -p > "$DIR/jak2-vagfix-run${IDX}-c.png" 2>/dev/null
    echo "cap C done"
  else
    echo "GATE FAIL at C: no -c cap"
  fi
else
  echo "GATE FAIL: pid=${PID:-none} focus=$FOCUS -> no -b/-c caps"
fi

kill $LCPID >/dev/null 2>&1; wait $LCPID 2>/dev/null
adb -s $SER shell am force-stop "$PKG" >/dev/null 2>&1
echo "===== RUN $IDX end $(date +%T) ($(wc -l < "$LOG") lines) ====="
