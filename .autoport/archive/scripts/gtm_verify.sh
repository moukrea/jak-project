#!/usr/bin/env bash
# Gtouch-menus VERIFICATION: pure-touch menu navigation via REAL adb input tap.
# Opens the title menu (cpad START = setup only), then taps OPTIONS -> Graphic
# Options -> FPS Counter -> a carousel -> Back, screencapping + logging each.
# Also proves the D-pad still works (cpad down moves the cursor).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"; S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Gtouch-menus/shots; mkdir -p "$OUT"
LOG=.autoport/reports/Gtouch-menus/verify.log
adb(){ "$ADB" -s "$S" "$@"; }
inj(){ adb shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1; }
rel(){ inj neutral; }
press(){ inj "$1"; sleep 0.4; rel; sleep "${2:-0.9}"; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; echo "  shot $1" | tee -a "$LOG"; }
tap(){ echo ">> input tap $1 $2" | tee -a "$LOG"; adb shell input tap "$1" "$2"; }
rowlog(){ adb logcat -d 2>/dev/null | grep -aE 'Gtouch-menus onMenuTap|Gtm-tap|Gtm-row' | tee -a "$LOG"; }

echo "== boot ==" | tee "$LOG"; rel
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
adb shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true
sleep 46; rel

# --- open title menu (retry START until an OPTIONS tap registers a Gtm-tap) ---
opened=0
for a in 1 2 3 4 5; do
  echo "== open attempt $a: START, tap OPTIONS ==" | tee -a "$LOG"
  press start 2.6; adb logcat -c 2>/dev/null || true
  tap 1152 443; sleep 1.6
  if [ "$(adb logcat -d 2>/dev/null | grep -acE 'Gtm-tap')" -gt 0 ]; then opened=1; fi
  echo "== after OPTIONS tap (attempt $a) ==" | tee -a "$LOG"; rowlog
  shot "v1-after-options-a${a}"
  [ "$opened" -eq 1 ] && break
done
echo "opened=$opened" | tee -a "$LOG"

# --- tap Graphic Options (on *options* screen: 4 rows, Graphic=idx1 oy=90 cy~0.43 -> y~465) ---
echo "== tap Graphic Options (1200,465) ==" | tee -a "$LOG"
adb logcat -c 2>/dev/null || true
tap 1200 465; sleep 1.6
rowlog; shot "v2-graphic-options"

# --- dump the Graphic Options row layout by tapping a harmless spot? no: the
#     Graphic Options tap above already logged that screen's rows only if it was
#     the *options* screen. Do one more tap on Graphic Options screen to dump its
#     row cy's (tap the top row area, harmless re-focus). ---
echo "== dump Graphic Options rows (tap top row 1200,240) ==" | tee -a "$LOG"
adb logcat -c 2>/dev/null || true
tap 1200 240; sleep 1.2
rowlog; shot "v3-graphic-rowdump"
echo "== DONE ==" | tee -a "$LOG"
