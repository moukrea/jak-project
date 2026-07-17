#!/usr/bin/env bash
# Phase Gtouch-rightstick (autoport): device-side build -> install -> launch ->
# drive ONLY the right CAMERA control -> prove it is now a FLOATING, INVISIBLE
# anchor+deflection virtual stick (sustained RIGHTX/RIGHTY from offset-to-anchor),
# NOT a frame-delta mouse-drag.
#
# Reuses gtouch_run.sh's proven scaffolding (android-env, restore-knowngood
# data, slim APK, device helpers, the anisotropic display<->view coord scale
# that lands synthetic touches dead-on). The actuation here is camera-specific:
#   * DOWN in the right-3/4 camera zone (clear of buttons) -> ANCHOR log.
#   * HELD MOVEs at a fixed offset -> the SAME sustained RIGHTX/RIGHTY value
#     each sample (a delta would decay to 0 once the finger stops).
#   * a LARGER held offset -> a larger sustained value (proportional).
#   * a long `input swipe` -> RIGHTX grows with distance-from-anchor and pins at
#     the clamp for the tail (sustained-at-max), the deflection signature.
#   * UP -> RIGHTX/RIGHTY = 0.
#
# GRSTICK_FAST=1 skips build/restore/install and just relaunches + re-drives
# (e.g. after a coord tweak). Writes .autoport/reports/Gtouch-rightstick/cam.txt
# is assembled by the orchestrator from BOOT_LOG; this script harvests the raw
# camera markers into cam-actuation.txt.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL="${ANDROID_SERIAL:-eae4df44}"
PACKAGE="org.opengoal.gk.jak1"
ACTIVITY=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
SERIAL="${ANDROID_SERIAL:-eae4df44}"
ADB="${ADB:-$(command -v adb || echo /home/emeric/Android/platform-tools/adb)}"

REPORT_DIR=".autoport/reports/Gtouch-rightstick"
BOOT_LOG="$REPORT_DIR/boot.log"
ACT="$REPORT_DIR/cam-actuation.txt"
mkdir -p "$REPORT_DIR"
export LOGCAT_LOG="$BOOT_LOG"

if [ "${GRSTICK_FAST:-0}" = "1" ]; then
    echo "== Grstick FAST: relaunch + drive only =="
    device_require_attached
    device_stayon_on || true
    "$ADB" -s "$SERIAL" shell am force-stop "$PACKAGE" >/dev/null 2>&1 || true
    "$ADB" -s "$SERIAL" logcat -c >/dev/null 2>&1 || true
    : > "$BOOT_LOG"
    "$ADB" -s "$SERIAL" logcat -s opengoal-gk:* Gk:* "*:F" > "$BOOT_LOG" 2>&1 &
    LOGCAT_PID=$!
    "$ADB" -s "$SERIAL" shell am start -n "$PACKAGE/$ACTIVITY" >/dev/null 2>&1 || true
else
    echo "== Grstick 1/5: incremental libgk.so build (no C++ change -> no-op relink) =="
    bash .autoport/lib/d3_build.sh

    echo "== Grstick 2/5: assemble jak1 debug APK (slim; data from restore) =="
    ( cd android && ./gradlew assembleJak1Debug -PslimIso=true 2>&1 ) \
        | tee .autoport/logs/gradle.grstick.log | tail -n 30
    [ -f "$APK" ] || { echo "APK missing at $APK"; exit 2; }

    echo "== Grstick 3/5: restore full gameplay data + sentinel =="
    device_require_attached
    device_require_free_space || true
    device_stayon_on || true
    bash .autoport/restore_knowngood_device.sh || true
    "$ADB" -s "$SERIAL" shell run-as "$PACKAGE" sh -c \
        'cd files/cgo/jak1 2>/dev/null && : > .extracted_v1' >/dev/null 2>&1 || true

    : > "$BOOT_LOG"
    echo "== Grstick 4/5: install + launch =="
    device_install_and_launch "$PACKAGE" "$ACTIVITY" "$APK"
fi

echo "== Grstick 5/5: wait for boot + overlay-map, then drive the camera =="
device_wait_for_marker 'MainActivity onCreate' 200 || true
device_wait_for_marker 'overlay-map: screen=' 30 || true
device_wait_for_marker 'link finish: logo$' 150 || true
# settle into gameplay so the right stick actually moves the camera end-to-end
sleep 8

# --- View size (overlay-local) and display size (synthetic-input space) ----
MAP_LINE=$(grep -a -m1 -E 'overlay-map: screen=' "$BOOT_LOG" | sed -E 's/^.*overlay-map: //')
VIEW_W=$(echo "$MAP_LINE" | grep -oE 'screen=[0-9]+x[0-9]+' | grep -oE '[0-9]+' | head -1)
VIEW_H=$(echo "$MAP_LINE" | grep -oE 'screen=[0-9]+x[0-9]+' | grep -oE '[0-9]+' | tail -1)
WM=$("$ADB" -s "$SERIAL" shell wm size 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | tail -1)
RA=${WM%x*}; RB=${WM#*x}
if [ "${RA:-0}" -ge "${RB:-0}" ]; then DISPLAY_W=$RA; DISPLAY_H=$RB; else DISPLAY_W=$RB; DISPLAY_H=$RA; fi
[ "${VIEW_W:-0}" -gt 0 ] || VIEW_W=$DISPLAY_W
[ "${VIEW_H:-0}" -gt 0 ] || VIEW_H=$DISPLAY_H
echo "  view=${VIEW_W}x${VIEW_H}  display=${DISPLAY_W}x${DISPLAY_H}"
sx(){ echo $(( $1 * DISPLAY_W / VIEW_W )); }   # view-x -> display-x (inject space)
sy(){ echo $(( $1 * DISPLAY_H / VIEW_H )); }   # view-y -> display-y

# --- Pick a clean camera-zone point (right of 0.45*W, clear of all buttons) -
# face cluster ~0.86*W, top buttons y<0.16*H, left stick ~0.155*W. (0.58*W,0.52*H)
# is empty -> a right-3/4 touch that misses every button => the camera anchor.
AVX=$(( VIEW_W * 58 / 100 )); AVY=$(( VIEW_H * 52 / 100 ))   # anchor (view)
O1=$(( VIEW_W * 5 / 100 ))                                    # small offset px (~0.7*maxR)
O2=$(( VIEW_W * 12 / 100 ))                                   # large offset px (> maxR -> clamp)
B1VX=$(( AVX + O1 )); B1VY=$AVY
B2VX=$(( AVX + O2 )); B2VY=$AVY
echo "  anchor(view)=($AVX,$AVY)  held1=($B1VX,$B1VY)  held2=($B2VX,$B2VY)  [camRegionLeft=$(( VIEW_W*45/100 ))]"

ADx=$(sx $AVX);  ADy=$(sy $AVY)
B1Dx=$(sx $B1VX); B1Dy=$(sy $B1VY)
B2Dx=$(sx $B2VX); B2Dy=$(sy $B2VY)

# Mark the actuation window in the log so we can isolate it.
"$ADB" -s "$SERIAL" shell log -t opengoal-gk "GRSTICK-ACT-BEGIN" >/dev/null 2>&1 || true
sleep 0.4

# --- (A) anchor + HELD-offset sequence: sustained, not delta -----------------
# >150ms between MOVEs so each clears the per-pointer log throttle. Same point
# repeated => same value (sustained). Larger point => larger value (proportional).
"$ADB" -s "$SERIAL" shell "input motionevent DOWN $ADx $ADy; sleep 0.25; \
input motionevent MOVE $B1Dx $B1Dy; sleep 0.25; \
input motionevent MOVE $B1Dx $B1Dy; sleep 0.25; \
input motionevent MOVE $B2Dx $B2Dy; sleep 0.25; \
input motionevent MOVE $B2Dx $B2Dy; sleep 0.25; \
input motionevent UP $B2Dx $B2Dy" >/dev/null 2>&1 || true
sleep 1.5

# --- (B) long single-process swipe: deflection grows with distance, pins at max
"$ADB" -s "$SERIAL" shell log -t opengoal-gk "GRSTICK-SWIPE-BEGIN" >/dev/null 2>&1 || true
"$ADB" -s "$SERIAL" shell input swipe "$ADx" "$ADy" "$B2Dx" "$B2Dy" 1600 >/dev/null 2>&1 || true
sleep 1.5
"$ADB" -s "$SERIAL" shell log -t opengoal-gk "GRSTICK-ACT-END" >/dev/null 2>&1 || true
sleep 1

# --- Harvest the camera markers ---------------------------------------------
{
  echo "== camera actuation harvest =="
  echo "view=${VIEW_W}x${VIEW_H} display=${DISPLAY_W}x${DISPLAY_H}"
  echo "anchor(view)=($AVX,$AVY) held1=($B1VX,$B1VY) held2=($B2VX,$B2VY) camRegionLeft=$(( VIEW_W*45/100 ))"
  echo
  echo "-- overlay-actuate: camera (Java side: anchor / deflect[sustained held] / release) --"
  grep -a -E 'overlay-actuate: camera' "$BOOT_LOG" || echo "(none)"
  echo
  echo "-- onPadAxis: sdl_axis=2|3 (native JNI route reaching on_pad_axis -> cpad rx/ry) --"
  grep -a -E 'onPadAxis: sdl_axis=[23] ' "$BOOT_LOG" || echo "(none)"
  echo
  echo "-- crash/liveness --"
  SIGS=$(grep -a -cE 'Fatal signal|signal (11|6|4)\b|SIGSEGV|SIGABRT|SIGILL' "$BOOT_LOG" 2>/dev/null || echo 0)
  echo "fatal-signal lines: $SIGS"
  grep -a -E 'link finish: logo' "$BOOT_LOG" | head -1 || true
} | tee "$ACT"

[ -n "${LOGCAT_PID:-}" ] && kill "$LOGCAT_PID" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true
echo "== Grstick done: harvest at $ACT ; full log $BOOT_LOG =="
