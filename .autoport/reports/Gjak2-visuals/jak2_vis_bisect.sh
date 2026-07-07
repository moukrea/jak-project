#!/usr/bin/env bash
# Gjak2-visuals wash bisection: boots jak2 on the device, then walks the
# debug.opengoal.vis.skip bucket-family mute through each suspect family,
# screencapping after each toggle. One run localizes which family paints
# the white wash.
set -u
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak2
ACT=org.opengoal.gk.LoaderActivity
DIR=/home/emeric/code/jak-project/.autoport/reports/Gjak2-visuals
PREFIX="${1:-jak2-vis-bisect}"
OUT=$DIR/${PREFIX}.log

cap() {  # $1 = label
  local lab="$1" foc f
  foc=$("$ADB" shell dumpsys window | grep mCurrentFocus | tr -d '\r')
  if echo "$foc" | grep -q "org.opengoal.gk.jak2"; then f=jak2focus; else f=NOTJAK2; fi
  "$ADB" exec-out screencap -p > "$DIR/${PREFIX}-${lab}-${f}.png" 2>/dev/null
  echo "[$PREFIX] cap=$lab $foc" | tee -a "$DIR/${PREFIX}-focus.txt"
}

> "$DIR/${PREFIX}-focus.txt"
echo "=== $PREFIX start $(date) ==="
"$ADB" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
"$ADB" shell svc power stayon true >/dev/null 2>&1
"$ADB" shell setprop debug.opengoal.vis.skip none >/dev/null 2>&1
"$ADB" shell am force-stop "$PKG"
sleep 2
"$ADB" logcat -c >/dev/null 2>&1
"$ADB" logcat -v time GK_STDOUT:V GK_STDERR:V opengoal-gk:V org.opengoal.gk:V AndroidRuntime:E libc:F DEBUG:F '*:S' > "$OUT" 2>&1 &
LOGPID=$!
"$ADB" shell am start -n "${PKG}/${ACT}"

# boot to the attract flythrough
sleep 75
cap baseline

# one family at a time, then everything at once
for fam in etie emerc gmerc merc effects screen-filter sky-draw particles; do
  "$ADB" shell setprop debug.opengoal.vis.skip "$fam"
  sleep 12
  cap "$fam"
done
"$ADB" shell setprop debug.opengoal.vis.skip "etie,emerc,gmerc,effects,screen-filter,sky-draw"
sleep 12
cap allmute
# setprop rejects an empty value on this device — use a no-op token instead.
"$ADB" shell setprop debug.opengoal.vis.skip none
sleep 8
cap restored

PID=$("$ADB" shell pidof "$PKG" | tr -d '\r')
echo "[$PREFIX] END pid=[$PID]" | tee -a "$DIR/${PREFIX}-focus.txt"
kill "$LOGPID" >/dev/null 2>&1
wait "$LOGPID" 2>/dev/null
"$ADB" shell am force-stop "$PKG"
echo "=== $PREFIX done $(date) ==="
