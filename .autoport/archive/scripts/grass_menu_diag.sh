#!/usr/bin/env bash
# grass_menu_diag.sh — DIAGNOSTIC ONLY. Drive the current device build to the
# "RECHARGED SETTINGS" submenu and screencap it, to see whether the two grass
# DISTANCE SLIDERS (NEAR GRASS DISTANCE / GRASS CARD DISTANCE) actually render.
# Device eae4df44 ONLY. Force-stops the app at the end (device-hygiene rule).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-grass-poc/menu-diag; mkdir -p "$OUT"
adb(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; echo "    inject '$1'"; }
clr(){ inject ""; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; echo "    shot $1.png ($(stat -c%s "$OUT/$1.png" 2>/dev/null||echo 0) bytes) fg=$(fg)"; }
boot(){ adb shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true; echo "  launched, settling ${1:-50}s..."; sleep "${1:-50}"; }

adb get-state >/dev/null 2>&1 || { echo "device not attached"; exit 1; }
DOWNS="${1:-8}"   # number of downs from Graphic Options top to reach RECHARGED SETTINGS

echo "== force-stop + boot =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
boot 50

echo "== nav: title attract -> START -> Options -> Graphic Options =="
inject "start"; sleep 0.5; clr; sleep 2.4
inject "down";  sleep 0.4; clr; sleep 0.7
inject "down";  sleep 0.4; clr; sleep 0.7
inject "x";     sleep 0.4; clr; sleep 2.0
inject "down";  sleep 0.4; clr; sleep 0.7
inject "x";     sleep 0.4; clr; sleep 2.0
shot 10-graphics-menu-top

echo "== down x$DOWNS to RECHARGED SETTINGS row, screencap the highlighted row =="
for i in $(seq 1 "$DOWNS"); do inject "down"; sleep 0.35; clr; sleep 0.45; done
shot 11-graphics-recharged-row-highlighted

echo "== X to enter the RECHARGED SETTINGS submenu, screencap it =="
inject "x"; sleep 0.5; clr; sleep 1.6
shot 12-recharged-submenu
sleep 0.5
shot 12b-recharged-submenu

echo "== force-stop (device-hygiene) =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
echo "[diag] DONE. Shots in $OUT/  (12*=the submenu — look for NEAR/GRASS CARD DISTANCE rows)"
