#!/usr/bin/env bash
# goptions_menu_capture.sh — drive the reordered Graphics Options menu on device,
# screencap it (Dynamic ON default, and Dynamic OFF -> Min Target FPS hidden), and
# prove END-TO-END persistence the owner's way: change a setting in the menu, close
# (commit), force-stop, relaunch, and confirm the change is retained (file + screencap).
# Device eae4df44 ONLY. Real measurements only.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
SETF="files/.config/OpenGOAL/jak1/settings/pc-settings.gc"
OUT=.autoport/reports/Goptions-reorder; SHOTS="$OUT/shots"; mkdir -p "$SHOTS"
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[cap FAIL] $*" >&2; exit 1; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject '$1'"; }
clr(){ inject ""; }
rd(){ adb shell run-as $PKG cat "$SETF" 2>/dev/null | tr -d '\r'; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$SHOTS/$1.png" 2>/dev/null; local sz=$(stat -c%s "$SHOTS/$1.png" 2>/dev/null||echo 0); echo "    shot $1.png ($sz bytes)"; }
bootwait(){
  adb logcat -c >/dev/null 2>&1 || true; local LOG=/tmp/gopt-cap-boot.log; : > "$LOG"
  ( adb logcat -v threadtime | grep --line-buffered -aE 'link finish: logo$|pc settings file (write|read)|Fatal signal' > "$LOG" ) & local LCP=$!
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  local t0=$(date +%s); while [ $(( $(date +%s) - t0 )) -lt 120 ]; do grep -aqE 'link finish: logo$' "$LOG" && break; sleep 3; done
  sleep 8; kill $LCP 2>/dev/null||true
}
nav_to_graphics(){
  # title attract -> START -> title menu; down,down -> Options; x -> *options*; down -> Graphic Options; x
  inject "start"; sleep 0.4; clr; sleep 2.0
  inject "down";  sleep 0.4; clr; sleep 0.8
  inject "down";  sleep 0.4; clr; sleep 0.8
  inject "x";     sleep 0.4; clr; sleep 1.8
  inject "down";  sleep 0.4; clr; sleep 0.8
  inject "x";     sleep 0.4; clr; sleep 1.8
}

adb get-state >/dev/null 2>&1 || die "device not attached"
echo "== ensure app is running (relaunch fresh so Dynamic defaults ON) =="
adb shell run-as $PKG rm -f "$SETF" 2>/dev/null || true    # fresh -> defaults (Dynamic ON)
adb shell am force-stop $PKG >/dev/null 2>&1 || true
bootwait
echo "  fg: $(fg)"

echo "== A. navigate to Graphics Options, screencap (Dynamic ON default -> Min Target FPS VISIBLE) =="
nav_to_graphics
shot 02-graphics-ON

echo "== B. toggle Dynamic Render Scale OFF (cursor 0 Aspect -> down,down = index2 Dynamic; left=off) =="
inject "down"; sleep 0.4; clr; sleep 0.6
inject "down"; sleep 0.4; clr; sleep 0.6
inject "left"; sleep 0.4; clr; sleep 1.0
shot 03-graphics-OFF-mtf-hidden

echo "== C. back out (commit on menu-close), pull settings (expect dynamic-render-scale? #f) =="
adb logcat -c >/dev/null 2>&1 || true; CLOG=/tmp/gopt-cap-commit.log; : > "$CLOG"
( adb logcat -v threadtime | grep --line-buffered -aE 'pc settings file write' > "$CLOG" ) & CLP=$!
inject "circle"; sleep 0.5; clr; sleep 1.2
inject "circle"; sleep 0.5; clr; sleep 1.2
inject "circle"; sleep 0.5; clr; sleep 2.0
sleep 2; kill $CLP 2>/dev/null || true
echo "  commit log: $(grep -c 'pc settings file write' "$CLOG") write(s)"
rd > "$OUT/device-pc-settings-afterchange.gc"
grep -qE '\(dynamic-render-scale\? #f\)' "$OUT/device-pc-settings-afterchange.gc" \
  && echo "  OK  menu change committed to file: dynamic-render-scale? #f" \
  || { echo "  (dynamic key in committed file:)"; grep -nE 'dynamic-render-scale\?' "$OUT/device-pc-settings-afterchange.gc" | sed 's/^/    /'; }

echo "== D. PERSISTENCE: force-stop, relaunch, re-open graphics menu, screencap + pull =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
bootwait
echo "  fg: $(fg)"
nav_to_graphics
shot 04-graphics-persist-after-restart
rd > "$OUT/device-pc-settings-afterrestart.gc"
if grep -qE '\(dynamic-render-scale\? #f\)' "$OUT/device-pc-settings-afterrestart.gc"; then
  echo "  OK  persistence CONFIRMED: dynamic-render-scale? #f retained across app restart"
else
  echo "  BAD dynamic-render-scale? not retained:"; grep -nE 'dynamic-render-scale\?' "$OUT/device-pc-settings-afterrestart.gc" | sed 's/^/    /'
fi
echo "== E. restore defaults on device (leave a clean fresh state) =="
adb shell run-as $PKG rm -f "$SETF" 2>/dev/null || true
echo "[cap] menu capture + persistence DONE. Shots in $SHOTS/"
