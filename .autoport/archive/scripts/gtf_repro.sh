#!/usr/bin/env bash
# Gtouch-fix REPRO: current tap behavior on toggles / sliders / save rows.
# Boot -> title menu -> Options -> Graphic Options; tap Render Scale (slider)
# left+right halves, tap FPS Counter dead-center; then Load Game screen save-row taps.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"; S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Gtouch-fix/shots; mkdir -p "$OUT"
LOG=.autoport/reports/Gtouch-fix/repro.log
adb(){ "$ADB" -s "$S" "$@"; }
inj(){ adb shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1; }
rel(){ inj neutral; }
press(){ inj "$1"; sleep 0.4; rel; sleep "${2:-0.9}"; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; echo "  shot $1 fg=$(adb shell dumpsys window 2>/dev/null|grep -m1 mCurrentFocus|tr -d '\r')" | tee -a "$LOG"; }
tap(){ echo ">> input tap $1 $2" | tee -a "$LOG"; adb logcat -c 2>/dev/null||true; adb shell input tap "$1" "$2"; sleep 1.6; adb logcat -d 2>/dev/null | grep -aE 'onMenuTap|Gtm-tap' | tee -a "$LOG"; }

echo "== boot ==" | tee "$LOG"; rel
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
adb shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true
sleep 46; rel

opened=0
for a in 1 2 3 4 5; do
  echo "== open attempt $a: START, tap OPTIONS (1200,464) ==" | tee -a "$LOG"
  press start 2.6
  tap 1200 464
  if adb logcat -d 2>/dev/null | grep -aqE 'Gtm-tap'; then opened=1; fi
  [ "$opened" -eq 1 ] && break
done
echo "opened=$opened" | tee -a "$LOG"; shot r01-options
[ "$opened" -eq 1 ] || { echo "FAILED to open menu" | tee -a "$LOG"; exit 1; }

echo "== tap Graphic Options (1200,464) ==" | tee -a "$LOG"
tap 1200 464; shot r02-graphic

echo "== SLIDER repro: Render Scale row (expect best=3). probe y=592 left half ==" | tee -a "$LOG"
tap 850 592; shot r03-rs-left1
echo "== again left ==" | tee -a "$LOG"
tap 850 592; shot r04-rs-left2
echo "== right half x2 ==" | tee -a "$LOG"
tap 1560 592; shot r05-rs-right1
tap 1560 592; shot r06-rs-right2

echo "== TOGGLE center repro: FPS Counter dead center (1200,850) x2 ==" | tee -a "$LOG"
tap 1200 850; shot r07-fps-center1
tap 1200 850; shot r08-fps-center2

echo "== back out to title menu (tap outside x2) ==" | tee -a "$LOG"
tap 1200 1065; shot r09-back1
tap 1200 1065; shot r10-back2

echo "== LOAD GAME screen: tap Load Game row (1200,335) ==" | tee -a "$LOG"
tap 1200 335; shot r11-loadgame
echo "== tap a save slot row (center-ish 1200,400) twice ==" | tee -a "$LOG"
tap 1200 400; shot r12-slot-tap1
tap 1200 400; shot r13-slot-tap2
rel
echo "== DONE ==" | tee -a "$LOG"
