#!/usr/bin/env bash
# rhud2_device_verify.sh — Grecharged-hud-jak1 on-device verify (eae4df44).
# A: fresh settings -> menu placement (RECHARGED SETTINGS before ADVANCED) + submenu default OFF
# B: in-game OFF baseline shots (stock HUD)
# C: toggle ON via menu -> commit -> pull pc-settings (recharged-hud? #t)
# D: relaunch -> menu shows ON (persistence) -> in-game ON shots (A/B vs B)
# Leaves the toggle ON for the owner. Reuses the Goptions cpad_inject file-token drive.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
INJECT="/data/data/$PKG/files/cpad_inject"
SETF="files/.config/OpenGOAL/jak1/settings/pc-settings.gc"
OUT=.autoport/reports/Grecharged-hud-jak1; SHOTS="$OUT/shots"; mkdir -p "$SHOTS"
adb(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clr(){ inject ""; }
tapb(){ inject "$1"; sleep 0.4; clr; sleep "${2:-0.7}"; }
rd(){ adb shell run-as $PKG cat "$SETF" 2>/dev/null | tr -d '\r'; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$SHOTS/$1.png" 2>/dev/null; echo "    shot $1.png ($(stat -c%s "$SHOTS/$1.png" 2>/dev/null||echo 0) B) fg=$(fg)"; }
boot(){ adb shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true; echo "  launched, settling ${1:-50}s..."; sleep "${1:-50}"; }
nav_to_graphics(){
  tapb start 2.2; tapb down; tapb down; tapb x 2.0; tapb down; tapb x 2.0
}
nav_to_recharged_row(){ # from graphics top: 8 downs (fresh settings -> dynamic ON -> MTF visible -> 12 rows)
  for i in 1 2 3 4 5 6 7 8; do tapb down 0.5; done
}
adb get-state >/dev/null 2>&1 || { echo "device not attached"; exit 1; }
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
if adb shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then echo "DEVICE_LOCKED"; exit 1; fi

echo "== A. fresh settings (defaults: recharged OFF) + menu placement =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb shell run-as $PKG rm -f "$SETF" 2>/dev/null || true
boot 55
nav_to_graphics
shot A1-graphics-top
nav_to_recharged_row
shot A2-recharged-row-before-advanced
tapb x 1.5
shot A3-recharged-submenu-default-OFF

echo "== B. back out (no change) -> in-game OFF baseline =="
tapb circle 1.2; tapb circle 1.2; tapb circle 1.2; tapb circle 2.5
tapb start 2.2
shot B0-title-menu
tapb x 3.0
echo "  waiting 45s for load-in..."; sleep 45
shot B1-ingame-OFF-spawn
sleep 8; shot B2-ingame-OFF-later
inject "ly=0"; sleep 4; clr; sleep 1
shot B3-ingame-OFF-moved

echo "== C. relaunch -> toggle ON -> commit -> pull settings =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
boot 55
nav_to_graphics
nav_to_recharged_row
tapb x 1.5
tapb x 0.8
tapb left 0.9
shot C1-recharged-editmode-ON
tapb x 1.2
shot C2-recharged-ON-committed
tapb circle 1.2; tapb circle 1.2; tapb circle 1.2; tapb circle 1.2; tapb circle 2.5
rd > "$OUT/device-pc-settings-after-ON.gc"
echo "  settings recharged key:"; grep -n "recharged" "$OUT/device-pc-settings-after-ON.gc" || echo "  (MISSING!)"

echo "== D. persistence + in-game ON =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
boot 55
nav_to_graphics
nav_to_recharged_row
tapb x 1.5
shot D1-recharged-persist-ON-after-restart
tapb circle 1.2; tapb circle 1.2; tapb circle 1.2; tapb circle 2.5
tapb start 2.2
tapb x 3.0
echo "  waiting 45s for load-in..."; sleep 45
shot D2-ingame-ON-spawn
sleep 8; shot D3-ingame-ON-later
inject "ly=0"; sleep 4; clr; sleep 1
shot D4-ingame-ON-moved
rd > "$OUT/device-pc-settings-final.gc"
grep -n "recharged" "$OUT/device-pc-settings-final.gc" || echo "  (final settings missing recharged key)"

echo "== E. logcat recharged loader lines (fresh grab) =="
adb logcat -d -v threadtime 2>/dev/null | grep -a "recharged-hud" | tail -15 > "$OUT/device-loader-lines.txt" || true
cat "$OUT/device-loader-lines.txt"
echo "[rhud2-device] DONE. Shots in $SHOTS/"
ls -la "$SHOTS"/*.png
