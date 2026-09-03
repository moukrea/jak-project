#!/usr/bin/env bash
# Gfinal-apk stage C+D: after apk_selfcontained_verify.sh left the freshly
# installed self-contained APK at the title screen (first run, unpack done):
#   C) prove TOUCH menus + reordered Graphic Options ship in the APK:
#      START -> tap OPTIONS -> tap Graphic Options -> screencaps.
#   D) second launch boots DIRECT (no re-unpack), then drive NEW GAME ->
#      intro cinematic -> Jak spawn (gameplay frame) -> screencaps.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"; S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Gfinal-apk; mkdir -p "$OUT"
LOG="$OUT/stageCD.log"
adb(){ "$ADB" -s "$S" "$@"; }
inj(){ adb shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1; }
rel(){ inj neutral; }
press(){ inj "$1"; sleep 0.4; rel; sleep "${2:-0.9}"; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; echo "  shot $1 fg=$(adb shell dumpsys window 2>/dev/null|grep -m1 mCurrentFocus|tr -d '\r')" | tee -a "$LOG"; }
tap(){ echo ">> input tap $1 $2" | tee -a "$LOG"; adb shell input tap "$1" "$2"; }

echo "== STAGE C: touch menus ($(date -Is)) ==" | tee "$LOG"
adb shell svc power stayon true >/dev/null 2>&1 || true
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
rel
shot "c0-title"
opened=0
for a in 1 2 3 4 5; do
  echo "== open attempt $a: START, tap OPTIONS (1152,443) ==" | tee -a "$LOG"
  press start 2.6
  shot "c1-menu-a${a}"
  adb logcat -c 2>/dev/null || true
  tap 1152 443; sleep 1.8
  HITS=$(adb logcat -d 2>/dev/null | grep -acE 'Gtm-tap')
  echo "  Gtm-tap hits: $HITS" | tee -a "$LOG"
  if [ "${HITS:-0}" -gt 0 ]; then opened=1; shot "c2-options-a${a}"; break; fi
done
echo "options_opened=$opened" | tee -a "$LOG"
echo "== tap Graphic Options (1200,465) ==" | tee -a "$LOG"
adb logcat -c 2>/dev/null || true
tap 1200 465; sleep 2.0
adb logcat -d 2>/dev/null | grep -aE 'Gtm-tap|Gtm-row' | head -20 | tee -a "$LOG"
shot "c3-graphic-options"

echo "== STAGE D: second launch = direct boot, then NEW GAME ==" | tee -a "$LOG"
rel
adb shell am force-stop $PKG; sleep 3
adb logcat -c 2>/dev/null || true
DLOG="$OUT/stageD-logcat.log"
adb logcat -v threadtime opengoal-gk:V GK_STDOUT:V GK_STDERR:V opengoal-loader:V libc:F DEBUG:V '*:S' > "$DLOG" 2>&1 &
LCPID=$!
trap 'kill $LCPID 2>/dev/null||true; rel' EXIT
T0=$(date +%s)
adb shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true
BOOTED=0
for i in $(seq 1 180); do
  grep -qa "link finish: logo" "$DLOG" && { BOOTED=1; echo "  direct boot -> title in $(( $(date +%s) - T0 ))s" | tee -a "$LOG"; break; }
  grep -qaE "unpack|decompress" "$DLOG" | grep -qav "already" && true
  sleep 1
done
REUNPACK=$(grep -acE "unpacking|decompress(ing)? asset|Bundle unpack start" "$DLOG")
echo "  booted=$BOOTED re-unpack-markers=$REUNPACK" | tee -a "$LOG"
sleep 25   # let the title flythrough settle
shot "d0-title-secondlaunch"

echo "== NEW GAME drive ==" | tee -a "$LOG"
rel
press start 2.6
shot "d1-menu"
# cursor to top (New Game)
press up 1.2; press up 1.2; press up 1.2
shot "d2-menu-top"
press x 3.0
shot "d3-savefile"
# select "create/continue without saving" (bottom row)
press down 1.0; press down 1.0; press down 1.0; press down 1.0
shot "d4-savefile-sel"
press x 3.0
shot "d5-newgame-start"
echo "== waiting for intro cinematic -> spawn (up to 480s) ==" | tee -a "$LOG"
for t in 60 120 180 240 300 360 420; do
  sleep 60
  shot "d6-cine-t${t}"
  SIG=$(grep -aoE 'GK-DIAG sig=[0-9]+|Fatal signal [0-9]+' "$DLOG" | tail -1)
  [ -n "$SIG" ] && { echo "  CRASH: $SIG" | tee -a "$LOG"; break; }
done
shot "d7-gameplay"
# nudge the stick to prove control (and get a distinct second frame)
inj "ly=15"; sleep 3; rel; sleep 1
shot "d8-gameplay-moved"
SIG=$(grep -aoE 'GK-DIAG sig=[0-9]+|Fatal signal [0-9]+' "$DLOG" | tail -1)
FRAME=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$DLOG"|grep -oE '[0-9]+$'|sort -n|tail -1)
FOC=$(adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -q "$PKG" && echo yes || echo no)
echo "RESULT stageD booted=$BOOTED reunpack=$REUNPACK frame=${FRAME:-0} focus=$FOC sig=${SIG:-none}" | tee -a "$LOG"
kill $LCPID 2>/dev/null || true
rel
echo "== DONE ==" | tee -a "$LOG"
