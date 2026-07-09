#!/usr/bin/env bash
# rhud2_order_shot.sh — one extra device frame: cursor on ADVANCED SETTINGS with the
# RECHARGED SETTINGS row visible directly ABOVE it (proves the before-Advanced ordering
# on device, complementing device-A2/G1 where Recharged is highlighted at the fold edge).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-hud-jak1; SHOTS="$OUT/shots"
adb(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clr(){ inject ""; }
tapb(){ inject "$1"; sleep 0.4; clr; sleep "${2:-0.7}"; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$SHOTS/device-$1.png" 2>/dev/null; echo "    shot device-$1.png ($(stat -c%s "$SHOTS/device-$1.png" 2>/dev/null||echo 0) B) fg=$(fg)"; }
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if adb shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then echo "DEVICE_LOCKED"; exit 1; fi
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.f1.warp 0 || true
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
echo "  launched, settling 55s..."; sleep 55
tapb start 2.2; tapb down; tapb down; tapb x 2.0; tapb down; tapb x 2.0
for i in 1 2 3 4 5 6 7 8 9; do tapb down 0.5; done
shot H1-advanced-after-recharged
adb shell am force-stop $PKG >/dev/null 2>&1 || true
echo "[rhud2-order] DONE"
