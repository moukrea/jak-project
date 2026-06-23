#!/usr/bin/env bash
# f1_diag_capture.sh — DIAGNOSTIC ONLY (not the validator).
# Reuses the already-deployed probe libgk (F1-STATE in Merc2.cpp). Drives the
# canonical NEW-GAME sequence, then keeps the capture running LONG past the
# training-level link (NO false-settle early-stop), periodically advancing the
# sage-intro dialogue with X, so we can see whether the device's *target* ever
# leaves the village1-hub cinematic cluster (~-543k) and lands in the Geyser
# Rock gameplay region (~-5.39M = the desktop game-start spawn).
#
# Output: .autoport/reports/F1-diag-boot.log  (+ trajectory printed at the end)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh 2>/dev/null || true
. .autoport/lib/device-validate.sh 2>/dev/null || true

PKG="org.opengoal.gk.jak1"
ACT=".LoaderActivity"
SERIAL="${ANDROID_SERIAL:-eae4df44}"; export ANDROID_SERIAL="$SERIAL"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
INJECT="/data/data/$PKG/files/cpad_inject"
LOG=".autoport/reports/F1-diag-boot.log"
A(){ "$ADB" -s "$SERIAL" "$@"; }
inject(){ printf '%s' "$1" | A shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject '$1'"; }
clear_inject(){ inject ""; }

pkill -f 'logcat.*GK_STDOUT' 2>/dev/null || true
device_require_attached 2>/dev/null || true
device_stayon_on 2>/dev/null || true
A shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
device_require_unlocked 2>/dev/null || true

A shell setprop debug.opengoal.f1.census 1 >/dev/null 2>&1 || true
echo "  census prop = $(A shell getprop debug.opengoal.f1.census | tr -d '\r')"
A shell am force-stop "$PKG" >/dev/null 2>&1 || true
clear_inject
A logcat -G 64M >/dev/null 2>&1 || true
A logcat -c >/dev/null 2>&1 || true
: > "$LOG"
A logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-gk-full:V \
    opengoal-loader:V libc:F DEBUG:V '*:S' > "$LOG" 2>&1 &
LCP=$!
cleanup(){ kill "$LCP" 2>/dev/null||true; A shell am force-stop "$PKG" >/dev/null 2>&1||true; device_stayon_restore 2>/dev/null||true; }
trap cleanup EXIT

A shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
echo "  warm to title (link finish: logo, up to 90s)..."
for i in $(seq 1 90); do grep -qa "link finish: logo" "$LOG" && { echo "  title ~${i}s"; break; }; sleep 1; done
sleep 40

echo "  drive: START -> NEW GAME -> CONTINUE WITHOUT SAVING"
inject "start"; sleep 1.2; clear_inject; sleep 4
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "down"; sleep 0.4; clear_inject; sleep 1.5
inject "up";   sleep 0.4; clear_inject; sleep 1
inject "up";   sleep 0.4; clear_inject; sleep 1.5
inject "x";    sleep 0.6; clear_inject; sleep 3
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "down"; sleep 0.4; clear_inject; sleep 1
inject "x";    sleep 0.6; clear_inject; sleep 4

echo "  LONG capture: 7 min past inject, advancing sage-intro with periodic X (no false-settle)"
END=$(( $(date +%s) + 7*60 ))
tick=0
while [ "$(date +%s)" -lt "$END" ]; do
  sleep 10; tick=$((tick+1))
  # advance any dialogue / cutscene boxes
  inject "x"; sleep 0.3; clear_inject
  if grep -qaE 'Fatal signal|signal (11|6|4) \(SIG' "$LOG" && grep -qa '>>> org.opengoal.gk.jak1' "$LOG"; then
    echo "   >>> native crash at tick $tick"; break; fi
  # live trajectory: last F1-STATE tx + training marker presence
  LAST=$(grep -aE 'F1-STATE tx=' "$LOG" | tail -1 | sed -E 's/.* (tx=[-0-9.]+ ty=[-0-9.]+ tz=[-0-9.]+).*/\1/')
  TR=$(grep -qaE "link finish: training-vis" "$LOG" && echo "TRAIN-LINKED" || echo "-")
  echo "   [t=$((tick*10))s] $TR last=$LAST"
done

echo "== trajectory summary =="
echo "-- distinct F1-STATE plateaus (rounded), top 15 by count --"
grep -aE 'F1-STATE tx=' "$LOG" | sed -E 's/.*tx=([-0-9.]+) ty=([-0-9.]+) tz=([-0-9.]+).*/\1 \2 \3/' \
  | awk '{printf "%d|%d|%d\n",$1,$2,$3}' | sort | uniq -c | sort -rn | head -15
echo "-- closest sample to desktop game-start tx=-5393129 --"
grep -aE 'F1-STATE tx=' "$LOG" | sed -E 's/.*tx=([-0-9.]+) ty=([-0-9.]+) tz=([-0-9.]+).*/\1 \2 \3/' \
  | awk 'BEGIN{b=1e18}{d=$1-(-5393129);if(d<0)d=-d;if(d<b){b=d;x=$1;y=$2;z=$3}}END{printf "closest tx=%s ty=%s tz=%s |dx|=%.0f\n",x,y,z,b}'
echo "-- level/control markers (post training) --"
grep -aoE "Adding level [a-z0-9-]+|link finish: (training[a-z-]*|sage-intro[a-z0-9-]*)|set-master-mode|state=in-game" "$LOG" | sort | uniq -c
echo "-- total F1-STATE samples --"; grep -ac 'F1-STATE tx=' "$LOG"
echo "DONE -> $LOG"
