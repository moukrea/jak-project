#!/usr/bin/env bash
set -u
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak2
ACT=org.opengoal.gk.LoaderActivity
DIR=/home/emeric/code/jak-project/.autoport/reports/Gjak2-visuals
PREFIX="$1"      # e.g. jak2-vis-run1
WINDOW="$2"      # total seconds
OUT=$DIR/${PREFIX}.log
FOCUSLOG=$DIR/${PREFIX}-focus.txt
> "$FOCUSLOG"

cap() {  # $1 = suffix ("" for plain)
  local suf="$1"
  local foc pid f
  foc=$("$ADB" shell dumpsys window | grep mCurrentFocus | tr -d '\r')
  pid=$("$ADB" shell pidof "$PKG" | tr -d '\r')
  if echo "$foc" | grep -q "org.opengoal.gk.jak2"; then f=jak2focus; else f=NOTJAK2; fi
  local name
  if [ -z "$suf" ]; then name="$DIR/${PREFIX}-end-${f}.png"; else name="$DIR/${PREFIX}-${suf}-${f}.png"; fi
  "$ADB" exec-out screencap -p > "$name" 2>/dev/null
  echo "[$PREFIX] suf=${suf:-END} pid=[$pid] $foc -> $name" | tee -a "$FOCUSLOG"
}

echo "=== $PREFIX (window=${WINDOW}s) start $(date) ==="
"$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
"$ADB" shell svc power stayon true >/dev/null 2>&1
"$ADB" shell am force-stop "$PKG"
sleep 2
"$ADB" logcat -c >/dev/null 2>&1
"$ADB" logcat -v time GK_STDOUT:V GK_STDERR:V opengoal-gk:V org.opengoal.gk:V AndroidRuntime:E libc:F DEBUG:F '*:S' > "$OUT" 2>&1 &
LOGPID=$!
sleep 1
PIDSTART=""
"$ADB" shell am start -n "${PKG}/${ACT}"

SECS=0
DID60=0; DID120=0
while [ $SECS -lt $WINDOW ]; do
  sleep 5; SECS=$((SECS+5))
  if [ -z "$PIDSTART" ]; then PIDSTART=$("$ADB" shell pidof "$PKG" | tr -d '\r'); [ -n "$PIDSTART" ] && echo "[$PREFIX] PIDSTART=$PIDSTART at ${SECS}s" | tee -a "$FOCUSLOG"; fi
  if [ $SECS -ge 60 ] && [ $DID60 -eq 0 ]; then cap t60; DID60=1; fi
  if [ $SECS -ge 120 ] && [ $DID120 -eq 0 ]; then cap t120; DID120=1; fi
done

cap ""
PID=$("$ADB" shell pidof "$PKG" | tr -d '\r')
FOC=$("$ADB" shell dumpsys window | grep mCurrentFocus | tr -d '\r')
echo "[$PREFIX] END pid=[$PID] PIDSTART=[$PIDSTART] $FOC" | tee -a "$FOCUSLOG"
if [ -n "$PID" ] && echo "$FOC" | grep -q "org.opengoal.gk.jak2"; then
  for suf in b c d; do sleep 10; cap "$suf"; done
fi

kill "$LOGPID" >/dev/null 2>&1
wait "$LOGPID" 2>/dev/null
"$ADB" shell svc power stayon true >/dev/null 2>&1
"$ADB" shell am force-stop "$PKG"
echo "=== $PREFIX done $(date); log lines: $(wc -l < "$OUT"); PIDSTART=$PIDSTART PIDEND=$PID ==="
