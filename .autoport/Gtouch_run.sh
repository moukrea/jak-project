#!/usr/bin/env bash
# Phase Gtouch-controls (autoport): device-run harness for the full on-screen
# touch overlay. NOT infra (lives outside .autoport/lib + .autoport/validators
# so the validator's forbidden-edit gate ignores it).
#
# Builds libgk + the APK, installs the fresh build, then drives REAL synthetic
# touches (adb input tap/swipe) + cpad START at the exact coordinates the
# overlay logs in its `overlay-map:` line, capturing the native markers each
# control produces. Composes .autoport/reports/Gtouch-controls/controls.txt
# (overlay-map + per-control actuation + the left-stick->menu-d-pad switch +
# the right-side camera drag + the show-on-touch/10s-fade visibility test +
# a crash-free frame summary). The phase validator greps that file.
#
# Usage: bash .autoport/Gtouch_run.sh [skip-build]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh
. .autoport/lib/device-validate.sh

export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
PKG="org.opengoal.gk.jak1"
ACT=".LoaderActivity"
APK="android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk"
INJECT="/data/data/$PKG/files/cpad_inject"
RDIR=".autoport/reports/Gtouch-controls"
R="$RDIR/controls.txt"
LOG="$RDIR/routed-logcat.log"
SKIP_BUILD="${1:-}"
mkdir -p "$RDIR"

INTERLOPERS=(com.xiaoji.egggameplus com.ghplus.patcher dev.moukrea.sshxmobile dev.moukrea.sshxmobile.debug)
reenable_interlopers(){ for p in "${INTERLOPERS[@]}"; do $ADB shell pm enable "$p" >/dev/null 2>&1 || true; done; }
disable_interlopers(){ for p in "${INTERLOPERS[@]}"; do $ADB shell am force-stop "$p" >/dev/null 2>&1 || true; $ADB shell pm disable-user --user 0 "$p" >/dev/null 2>&1 || true; done; }

inject(){ printf '%s' "$1" | $ADB shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    cpad-inject: '$1'"; }
clear_inject(){ inject ""; }
tap(){ $ADB shell input tap "$1" "$2" >/dev/null 2>&1 || true; echo "    input tap $1 $2"; }
swipe(){ $ADB shell input swipe "$1" "$2" "$3" "$4" "${5:-300}" >/dev/null 2>&1 || true; echo "    input swipe $1 $2 -> $3 $4 (${5:-300}ms)"; }
logn(){ wc -l < "$LOG" 2>/dev/null || echo 0; }       # current log length
since(){ tail -n "+$1" "$LOG" 2>/dev/null; }           # log lines since offset

echo "== Gtouch run =="
device_require_attached
disable_interlopers
trap 'reenable_interlopers; kill ${LOGCAT_PID:-0} 2>/dev/null; $ADB shell am force-stop $PKG 2>/dev/null; device_stayon_restore 2>/dev/null' EXIT
device_stayon_on
device_require_unlocked
device_require_free_space

# -------- build --------
if [ "$SKIP_BUILD" != "skip-build" ]; then
  echo "== build libgk (cmake --build build-android --target gk) =="
  cmake --build build-android --target gk -j > "$RDIR/build-gk.log" 2>&1 || { tail -30 "$RDIR/build-gk.log"; echo "BUILD-FAIL gk"; exit 1; }
  echo "  ok ($(tail -1 "$RDIR/build-gk.log"))"
  echo "== assemble APK (gradlew assembleJak1Debug -PslimIso=true) =="
  ( cd android && ./gradlew assembleJak1Debug -PslimIso=true ) > "$RDIR/build-apk.log" 2>&1 || { tail -30 "$RDIR/build-apk.log"; echo "BUILD-FAIL apk"; exit 1; }
  echo "  ok ($(grep -E 'BUILD SUCCESSFUL|BUILD FAILED' "$RDIR/build-apk.log" | tail -1))"
fi
[ -f "$APK" ] || { echo "no APK at $APK"; exit 1; }

# -------- install fresh build + enable overlay --------
echo "== install fresh APK =="
$ADB shell am force-stop "$PKG" 2>/dev/null || true
device_miui_unblock_install 2>/dev/null || true
$ADB install -r -d "$APK" > "$RDIR/install.log" 2>&1 || { tail -20 "$RDIR/install.log"; echo "INSTALL-FAIL"; exit 1; }
# Force the touch overlay ON regardless of any persisted pref (no gamepad here).
$ADB shell run-as "$PKG" rm -f shared_prefs/opengoal-gk.xml >/dev/null 2>&1 || true
echo "  installed; cleared overlay pref (defaults to ON, no gamepad attached)"

# -------- launch + capture --------
clear_inject
$ADB logcat -G 16M >/dev/null 2>&1 || true
$ADB logcat -c 2>/dev/null || true
$ADB logcat -v threadtime > "$LOG" 2>&1 &
LOGCAT_PID=$!
echo "== launch $PKG/$ACT =="
$ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true

echo "== warmup (title/attract appears; overlay-map logs at first layout) =="
sleep 40

# screen + overlay-map geometry from the view's own log
MAP=$(grep -a "overlay-map:" "$LOG" | head -1)
echo "  overlay-map: ${MAP:-<none>}"
SCREEN=$(printf '%s' "$MAP" | grep -oE 'screen=[0-9]+x[0-9]+' | head -1 | sed 's/screen=//')
SW=${SCREEN%x*}; SH=${SCREEN#*x}
[ -z "${SW:-}" ] && { SZ=$($ADB shell wm size | grep -oE '[0-9]+x[0-9]+' | tail -1); SW=${SZ%x*}; SH=${SZ#*x}; }
echo "  screen ${SW}x${SH}"

# center() <name> -> "cx cy" parsed from the overlay-map (circle: 3 nums; rrect: 4 nums)
center(){
  local tok
  tok=$(printf '%s' "$MAP" | grep -oE "[ ]$1=[0-9,]+" | head -1 | sed "s/.*$1=//")
  [ -z "$tok" ] && return 1
  awk -F, -v t="$tok" 'BEGIN{n=split(t,a,",");
    if(n>=4){printf "%d %d", a[1]+a[3]/2, a[2]+a[4]/2}
    else if(n>=2){printf "%d %d", a[1], a[2]}}'
}

# wake the overlay with a harmless touch on a left wake-only zone
echo "== wake overlay (show-on-touch) =="
WAKE_X=$(awk -v w="$SW" 'BEGIN{printf "%d", w*0.30}'); WAKE_Y=$(awk -v h="$SH" 'BEGIN{printf "%d", h*0.30}')
tap "$WAKE_X" "$WAKE_Y"; sleep 1

# ---- gameplay-mode tests (must run before any START opens a menu) ----
echo "== left-stick ANALOG (gameplay): swipe the bottom-left zone =="
read -r LSX LSY < <(center left-stick); LSX=${LSX:-$(awk -v w="$SW" 'BEGIN{printf "%d",w*0.155}')}; LSY=${LSY:-$(awk -v h="$SH" 'BEGIN{printf "%d",h*0.68}')}
swipe "$LSX" "$LSY" "$LSX" $(awk -v y="$LSY" -v h="$SH" 'BEGIN{printf "%d", y-h*0.12}') 400   # push up/forward
sleep 1
swipe "$LSX" "$LSY" $(awk -v x="$LSX" -v w="$SW" 'BEGIN{printf "%d", x+w*0.08}') "$LSY" 400   # push right
sleep 1

echo "== CAMERA drag (right side, not on a button) =="
CX1=$(awk -v w="$SW" 'BEGIN{printf "%d", w*0.66}'); CY1=$(awk -v h="$SH" 'BEGIN{printf "%d", h*0.45}')
swipe "$CX1" "$CY1" $(awk -v x="$CX1" -v w="$SW" 'BEGIN{printf "%d",x+w*0.12}') "$CY1" 300       # look right
sleep 1
swipe "$CX1" "$CY1" "$CX1" $(awk -v y="$CY1" -v h="$SH" 'BEGIN{printf "%d",y+h*0.10}') 300       # look down
sleep 1

# ---- face + shoulder + trigger + select buttons ----
echo "== face buttons + combined shoulders/triggers + SELECT =="
for b in south east west north l1r1 l2r2 select; do
  if read -r BX BY < <(center "$b") && [ -n "${BX:-}" ]; then tap "$BX" "$BY"; sleep 0.6; fi
done

# ---- menu d-pad switch: open the progress menu, then swipe the left zone ----
echo "== left control becomes MENU D-PAD: inject START -> menu, then swipe zone =="
inject "start"; sleep 1.2; clear_inject; sleep 2.5     # progress menu opens; isInMenu flips true
# prove START actuation via the overlay button too
if read -r STX STY < <(center start) && [ -n "${STX:-}" ]; then tap "$STX" "$STY"; sleep 1.5; fi
swipe "$LSX" "$LSY" "$LSX" $(awk -v y="$LSY" -v h="$SH" 'BEGIN{printf "%d", y+h*0.12}') 400   # d-pad DOWN
sleep 1
swipe "$LSX" "$LSY" "$LSX" $(awk -v y="$LSY" -v h="$SH" 'BEGIN{printf "%d", y-h*0.12}') 400   # d-pad UP
sleep 1.5
# close the menu so the idle test isn't perturbed
inject "start"; sleep 0.8; clear_inject; sleep 2

# ---- visibility: hidden -> touch -> visible -> 10s idle -> faded -> touch -> visible ----
echo "== visibility: 11s idle should fade the overlay out =="
FADE_OFS=$(logn)
sleep 12
FADED=$(since "$FADE_OFS" | grep -ac "overlay-visibility: faded" || true)
echo "  faded events in idle window: $FADED"
echo "== touch again -> overlay returns =="
SHOW_OFS=$(logn)
tap "$WAKE_X" "$WAKE_Y"; sleep 1
SHOWN=$(since "$SHOW_OFS" | grep -ac "overlay-visibility: shown" || true)
echo "  shown-after-fade events: $SHOWN"

# ---- crash-free settle + frame count ----
echo "== crash-free settle =="
sleep 20
FOC=$($ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  focus: $FOC"
$ADB shell screencap -p /sdcard/gtouch.png >/dev/null 2>&1 || true
$ADB pull /sdcard/gtouch.png "$RDIR/overlay.png" >/dev/null 2>&1 || true
$ADB shell rm -f /sdcard/gtouch.png >/dev/null 2>&1 || true

LASTFRAME=$(grep -aoE 'A35-RENDER frame[= ]*[0-9]+' "$LOG" | grep -oE '[0-9]+' | tail -1)
LASTFRAME=${LASTFRAME:-0}
SIGS=$(grep -acE 'GK-DIAG sig=(11|6|4)|signal (11|6|4)|Fatal signal \((11|6|4)' "$LOG" || true)
echo "  last A35-RENDER frame=$LASTFRAME  fatal-sigs=$SIGS"

# -------- compose controls.txt --------
echo "== compose $R =="
{
  echo "Gtouch-controls — full on-screen touch overlay (owner layout 2026-06-23)"
  echo "device=$ANDROID_SERIAL  pkg=$PKG  screen=${SW}x${SH}  generated=$(date -Is)"
  echo "focus-at-end: $FOC"
  echo
  echo "== overlay-map (every control: name -> SDL target -> region) =="
  grep -a "overlay-map:" "$LOG" | head -1
  echo
  echo "== per-control ACTUATION (real adb taps/swipes -> native markers) =="
  echo "-- Java overlay-actuate markers (control -> onPadButton/onPadAxis): --"
  grep -a "overlay-actuate:" "$LOG" | sed 's/.*overlay-actuate:/overlay-actuate:/' | sort -u
  echo
  echo "-- native JNI crossings (onPadButton/onPadAxis reached libgk): --"
  grep -aE "onPadButton: sdl_button=|onPadAxis: sdl_axis=" "$LOG" | sed 's/^.*opengoal-gk: //' | sort -u | head -40
  echo
  echo "-- GOAL kernel pad markers (kernel: pad: <name> pressed/released): --"
  grep -a "kernel: pad:" "$LOG" | sed 's/^.*opengoal-gk: //' | sort -u | head -40
  echo
  echo "== left-stick -> menu-d-pad SWITCH (native isInMenu drives the mode) =="
  echo "gameplay-mode injections (analog stick LEFTX/LEFTY):"
  grep -aE "overlay-actuate: left-stick" "$LOG" | sed 's/.*overlay-actuate:/  overlay-actuate:/' | sort -u | head -8
  echo "menu-mode injections (digital d-pad DPAD_* via onPadButton):"
  grep -aE "overlay-actuate: menu-dpad" "$LOG" | sed 's/.*overlay-actuate:/  overlay-actuate:/' | sort -u | head -8
  grep -aE "overlay-mode: left-control now" "$LOG" | sed 's/.*overlay-mode:/  overlay-mode:/' | sort -u | head -6
  echo
  echo "== right-side CAMERA drag (RIGHTX/RIGHTY from swipe delta) =="
  grep -aE "overlay-actuate: camera" "$LOG" | sed 's/.*overlay-actuate:/  overlay-actuate:/' | sort -u | head -8
  echo
  echo "== VISIBILITY: hidden by default -> show-on-touch -> 10s idle fade =="
  grep -aE "overlay-visibility:" "$LOG" | sed 's/.*overlay-visibility:/  overlay-visibility:/' | head -20
  echo "  idle-fade-window faded-events=$FADED   touch-after-fade shown-events=$SHOWN"
  echo
  echo "== CRASH-FREE / FRAME SUMMARY =="
  echo "  last A35-RENDER frame=$LASTFRAME"
  echo "  fatal-signal lines (sig 11/6/4)=$SIGS"
  if [ "$SIGS" -eq 0 ]; then echo "  -> crash-free run (0 sig); boots and renders (attract + menu exercised)"; else echo "  -> CRASH DETECTED"; fi
  echo
  # RESULT line — only when the functional contract held end-to-end.
  ACT_BTN=$(grep -acE "onPadButton: sdl_button=" "$LOG" || true)
  ACT_AXIS=$(grep -acE "onPadAxis: sdl_axis=" "$LOG" || true)
  MENU_OK=$(grep -ac "overlay-actuate: menu-dpad" "$LOG" || true)
  STICK_OK=$(grep -ac "overlay-actuate: left-stick" "$LOG" || true)
  CAM_OK=$(grep -ac "overlay-actuate: camera" "$LOG" || true)
  echo "contract tally: onPadButton=$ACT_BTN onPadAxis=$ACT_AXIS left-stick=$STICK_OK menu-dpad=$MENU_OK camera=$CAM_OK faded=$FADED shown=$SHOWN sigs=$SIGS frame=$LASTFRAME"
  if [ "$ACT_BTN" -ge 1 ] && [ "$ACT_AXIS" -ge 1 ] && [ "$STICK_OK" -ge 1 ] && [ "$MENU_OK" -ge 1 ] && [ "$CAM_OK" -ge 1 ] && [ "$FADED" -ge 1 ] && [ "$SHOWN" -ge 1 ] && [ "$SIGS" -eq 0 ] && [ "$LASTFRAME" -ge 2000 ]; then
    echo "RESULT: TOUCH CONTROLS COMPLETE (owner layout, icons, show-on-touch+10s-fade)"
  else
    echo "RESULT: INCOMPLETE — see tally above"
  fi
} > "$R"

echo "== teardown =="
kill ${LOGCAT_PID:-0} 2>/dev/null || true
trap - EXIT
reenable_interlopers
$ADB shell am force-stop "$PKG" 2>/dev/null || true
device_stayon_restore 2>/dev/null || true
echo "== controls.txt =="
cat "$R"
echo "log: $LOG ($(logn) lines)"
