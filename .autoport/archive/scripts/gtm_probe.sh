#!/usr/bin/env bash
# Gtouch-menus device probe: open the options menu (cpad_inject SETUP only),
# screencap each step so we can see the menu layout for touch calibration.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"; S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Gtouch-menus/shots; mkdir -p "$OUT"
adb(){ "$ADB" -s "$S" "$@"; }
# cpad inject via system property (CWD-independent, per memory)
inj(){ adb shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1; }
press(){ inj "$1"; sleep 0.35; inj ""; sleep "${2:-0.8}"; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; echo "  shot $1.png $(stat -c%s "$OUT/$1.png" 2>/dev/null||echo 0)B fg=$(adb shell dumpsys window 2>/dev/null|grep -m1 mCurrentFocus|tr -d '\r')"; }

echo "== force-stop + boot to title attract =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
adb shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true
sleep 46
shot 00-attract
echo "== open menu: start =="
press start 2.2; shot 01-after-start
echo "== down, down =="
press down 0.7; press down 0.7; shot 02-after-downdown
echo "== x (enter Options) =="
press x 2.0; shot 03-options-screen
adb logcat -d 2>/dev/null | grep -aE 'isInMenu|progress-process|Gtouch-menus onMenuTap|Gtm-tap' | tail -8
echo "== DONE =="
