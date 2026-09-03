#!/usr/bin/env bash
# goptions_menu_capture.sh — drive the reordered Graphics Options menu on device,
# screencap it (Dynamic ON default -> Min Target FPS VISIBLE, and Dynamic OFF ->
# Min Target FPS HIDDEN), and prove END-TO-END persistence the owner's way:
# change a setting in the menu, close (commit), force-stop, relaunch, confirm
# the change is retained (file + screencap). Hang-proof: no backgrounded logcat.
# Device eae4df44 ONLY. Real measurements only.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
INJECT="/data/data/$PKG/files/cpad_inject"
SETF="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
OUT=.autoport/reports/Goptions-reorder; SHOTS="$OUT/shots"; mkdir -p "$SHOTS"
adb(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject '$1'"; }
clr(){ inject ""; }
rd(){ adb shell run-as $PKG cat "$SETF" 2>/dev/null | tr -d '\r'; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$SHOTS/$1.png" 2>/dev/null; echo "    shot $1.png ($(stat -c%s "$SHOTS/$1.png" 2>/dev/null||echo 0) bytes) fg=$(fg)"; }
boot(){ adb shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true; echo "  launched, settling ${1:-45}s..."; sleep "${1:-45}"; }
nav_to_graphics(){
  # title attract -> START -> title menu; down,down -> Options; x -> *options*; down -> Graphic Options; x
  inject "start"; sleep 0.5; clr; sleep 2.2
  inject "down";  sleep 0.4; clr; sleep 0.7
  inject "down";  sleep 0.4; clr; sleep 0.7
  inject "x";     sleep 0.4; clr; sleep 2.0
  inject "down";  sleep 0.4; clr; sleep 0.7
  inject "x";     sleep 0.4; clr; sleep 2.0
}
adb get-state >/dev/null 2>&1 || { echo "device not attached"; exit 1; }

echo "== fresh state (wipe settings -> Dynamic defaults ON) + boot =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb shell run-as $PKG rm -f "$SETF" 2>/dev/null || true
boot 50

echo "== A. Graphics Options menu, Dynamic ON default -> screencap (Min Target FPS VISIBLE) =="
nav_to_graphics
shot 02-graphics-ON

echo "== B. toggle Dynamic OFF (down,down -> index2 Dynamic; X=enter-edit, right=OFF fires on-change, X=commit) =="
inject "down"; sleep 0.4; clr; sleep 0.6
inject "down"; sleep 0.4; clr; sleep 0.6
inject "x";     sleep 0.4; clr; sleep 0.8
inject "right"; sleep 0.4; clr; sleep 0.9
shot 03a-graphics-OFF-editmode
inject "x";     sleep 0.4; clr; sleep 1.0
shot 03-graphics-OFF-mtf-hidden

echo "== C. back out to attract (commit on menu-close) then pull settings =="
inject "circle"; sleep 0.5; clr; sleep 1.3
inject "circle"; sleep 0.5; clr; sleep 1.3
inject "circle"; sleep 0.5; clr; sleep 2.5
rd > "$OUT/device-pc-settings-afterchange.gc"
echo "  committed file graphics keys:"; grep -nE 'dynamic-render-scale|min-render|dyn-target|fps-counter|vsync|msaa' "$OUT/device-pc-settings-afterchange.gc" | sed 's/^/    /'

echo "== D. PERSISTENCE: force-stop, relaunch, re-open graphics menu -> screencap + pull =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
boot 50
nav_to_graphics
shot 04-graphics-persist-after-restart
rd > "$OUT/device-pc-settings-afterrestart.gc"
echo "  after-restart file graphics keys:"; grep -nE 'dynamic-render-scale|min-render|dyn-target|fps-counter|vsync|msaa' "$OUT/device-pc-settings-afterrestart.gc" | sed 's/^/    /'
echo "[cap] DONE. Shots: $SHOTS/  (02=ON, 03=OFF-hidden, 04=persist)"
