#!/usr/bin/env bash
set -u
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak2
ACT=org.opengoal.gk.LoaderActivity
DIR=/home/emeric/code/jak-project/.autoport/reports/Gjak2-render
N="$1"
WINDOW="$2"   # total seconds
OUT=$DIR/jak2-3dg-run${N}.log
FOCUSLOG=$DIR/focus-3dg-run${N}.txt
> "$FOCUSLOG"

cap() {  # $1 = suffix ("" for plain)
  local suf="$1"
  local foc pid f
  foc=$("$ADB" shell dumpsys window | grep mCurrentFocus | tr -d '\r')
  pid=$("$ADB" shell pidof "$PKG" | tr -d '\r')
  if echo "$foc" | grep -q "org.opengoal.gk.jak2"; then f=jak2focus; else f=NOTJAK2; fi
  local name
  if [ -z "$suf" ]; then name="$DIR/jak2-3dg-run${N}-${f}.png"; else name="$DIR/jak2-3dg-run${N}-${suf}-${f}.png"; fi
  "$ADB" exec-out screencap -p > "$name" 2>/dev/null
  echo "[run${N}] suf=${suf:-END} pid=[$pid] $foc -> $name" | tee -a "$FOCUSLOG"
}

echo "=== RUN ${N} (window=${WINDOW}s) start $(date) ==="
"$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
"$ADB" shell svc power stayon true >/dev/null 2>&1
"$ADB" shell am force-stop "$PKG"
sleep 2
"$ADB" logcat -c >/dev/null 2>&1
"$ADB" logcat -v time GK_STDOUT:V GK_STDERR:V opengoal-gk:V org.opengoal.gk:V AndroidRuntime:E libc:F DEBUG:F '*:S' > "$OUT" 2>&1 &
LOGPID=$!
sleep 1
"$ADB" shell am start -n "${PKG}/${ACT}"

SECS=0
DID60=0; DID120=0
while [ $SECS -lt $WINDOW ]; do
  sleep 5; SECS=$((SECS+5))
  if [ $SECS -ge 60 ] && [ $DID60 -eq 0 ]; then cap t60; DID60=1; fi
  if [ $SECS -ge 120 ] && [ $DID120 -eq 0 ]; then cap t120; DID120=1; fi
done

# end-of-window capture (no suffix)
cap ""
PID=$("$ADB" shell pidof "$PKG" | tr -d '\r')
FOC=$("$ADB" shell dumpsys window | grep mCurrentFocus | tr -d '\r')
echo "[run${N}] END pid=[$PID] $FOC" | tee -a "$FOCUSLOG"
if [ -n "$PID" ] && echo "$FOC" | grep -q "org.opengoal.gk.jak2"; then
  for suf in b c d; do sleep 10; cap "$suf"; done
fi

kill "$LOGPID" >/dev/null 2>&1
wait "$LOGPID" 2>/dev/null
"$ADB" shell svc power stayon true >/dev/null 2>&1
"$ADB" shell am force-stop "$PKG"
echo "=== RUN ${N} done $(date); log lines: $(wc -l < "$OUT") ==="
