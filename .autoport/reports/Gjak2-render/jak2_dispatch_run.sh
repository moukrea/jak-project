#!/usr/bin/env bash
set -u
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak2
ACT=org.opengoal.gk.LoaderActivity
DIR=/home/emeric/code/jak-project/.autoport/reports/Gjak2-render
N="$1"
OUT=$DIR/jak2-dispatch-run${N}.log
CAP=$DIR/jak2-dispatch-run${N}.png

echo "=== RUN ${N} start $(date) ==="
# ensure no leftover runner
"$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
"$ADB" shell svc power stayon true >/dev/null 2>&1
"$ADB" shell am force-stop "$PKG"
sleep 2
"$ADB" logcat -c >/dev/null 2>&1
"$ADB" logcat -v time GK_STDOUT:V GK_STDERR:V opengoal-gk:V org.opengoal.gk:V AndroidRuntime:E libc:F DEBUG:F '*:S' > "$OUT" 2>&1 &
LOGPID=$!
sleep 1
"$ADB" shell am start -n "${PKG}/${ACT}"
# wait 420s
SECS=0
while [ $SECS -lt 420 ]; do sleep 10; SECS=$((SECS+10)); done
# primary cap
"$ADB" shell dumpsys window | grep mCurrentFocus > $DIR/focus-run${N}.txt 2>&1
"$ADB" exec-out screencap -p > "$CAP" 2>/dev/null
PID=$("$ADB" shell pidof "$PKG" | tr -d '\r')
FOCUS=$(cat $DIR/focus-run${N}.txt)
echo "=== RUN ${N} @420: pid=[$PID] focus=[$FOCUS] ==="
if [ -n "$PID" ] && echo "$FOCUS" | grep -q "org.opengoal.gk.jak2"; then
  for suf in b c d; do
    sleep 10
    "$ADB" shell dumpsys window | grep mCurrentFocus >> $DIR/focus-run${N}.txt 2>&1
    "$ADB" exec-out screencap -p > "$DIR/jak2-dispatch-run${N}-${suf}.png" 2>/dev/null
    echo "  extra cap ${suf} taken"
  done
fi
kill "$LOGPID" >/dev/null 2>&1
wait "$LOGPID" 2>/dev/null
"$ADB" shell am force-stop "$PKG"
echo "=== RUN ${N} done $(date); log lines: $(wc -l < "$OUT") ==="
