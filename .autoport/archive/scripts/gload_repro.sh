#!/usr/bin/env bash
# Grecharged-loader-packfix: faithful reproduction of the owner's failure.
# Installs the 29/07 build (the one whose libgk BuildID matches the tombstones)
# and launches it through the REAL entry point (LoaderActivity), capturing
# everything: logcat (which IS readable on this Honor), process liveness,
# per-second filesystem progress, and RSS.
set -uo pipefail
export PATH=$PATH:$HOME/Android/platform-tools
S=AREE026206000788
PKG=org.opengoal.gk.jak1
OUT=${1:-/tmp/gload/repro1}
APK=${2:-android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk}
mkdir -p "$OUT"

echo "### APK: $APK ($(stat -c%s "$APK") bytes)"
adb -s $S shell "am force-stop $PKG"

echo "### installing (this takes a while for a 1GB apk)..."
/usr/bin/time -f "install wall=%e s" adb -s $S install -r -d "$APK" 2>&1 | tail -5

echo "### clearing logcat"
adb -s $S logcat -c 2>/dev/null
adb -s $S logcat -G 64M 2>/dev/null

# background full logcat capture
adb -s $S logcat -v time > "$OUT/logcat.txt" 2>&1 &
LOGPID=$!

echo "### pre-launch files state"
adb -s $S shell "run-as $PKG sh -c 'ls -la files/; ls files/cgo/$( echo jak1 ) 2>/dev/null | wc -l'" > "$OUT/pre_files.txt" 2>&1
cat "$OUT/pre_files.txt"

echo "### launching via LoaderActivity (the REAL entry point)"
adb -s $S shell "am start -W -n $PKG/org.opengoal.gk.LoaderActivity" 2>&1 | tee "$OUT/am_start.txt"

echo "### polling for 180s"
{
  for i in $(seq 1 180); do
    TS=$(date +%H:%M:%S)
    PID=$(adb -s $S shell "pidof $PKG" 2>/dev/null | tr -d '\r')
    if [ -z "$PID" ]; then
      echo "$TS t=${i}s PID=NONE"
    else
      RSS=$(adb -s $S shell "grep -E '^VmRSS' /proc/$PID/status 2>/dev/null" | tr -d '\r')
      STATE=$(adb -s $S shell "run-as $PKG sh -c 'echo cgo=\$(ls files/cgo/jak1 2>/dev/null | wc -l) custom_fr3=\$(ls files/custom/jak1/fr3 2>/dev/null | wc -l) custom_bytes=\$(du -sk files/custom/jak1 2>/dev/null | cut -f1) stampC=\$(cat files/.cgo_pack_stamp_jak1 2>/dev/null) stampU=\$(cat files/.custom_pack_stamp_jak1 2>/dev/null)'" 2>/dev/null | tr -d '\r')
      FOCUS=$(adb -s $S shell "dumpsys window 2>/dev/null | grep -m1 mCurrentFocus" | tr -d '\r')
      echo "$TS t=${i}s PID=$PID $RSS | $STATE | $FOCUS"
    fi
  done
} 2>&1 | tee "$OUT/poll.txt"

kill $LOGPID 2>/dev/null
echo "### done. logcat lines: $(wc -l < "$OUT/logcat.txt")"
