#!/usr/bin/env bash
# grass_nested_menu_diag.sh — POLISH#6. Drive the device build to the NEW nested
# "GRASS SETTINGS" sub-submenu (Recharged Settings > GRASS SETTINGS) and screencap it,
# to PROVE all grass rows (RECHARGED GRASS / NEAR GRASS DISTANCE / GRASS CARD DISTANCE /
# GRASS DENSITY / BACK) actually render on device. Device eae4df44 ONLY.
# Force-stops the app at the end (device-hygiene rule).
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
DOWNS="${1:-8}"   # downs from Graphic Options top to reach RECHARGED SETTINGS

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
shot 20-graphics-menu-top

echo "== down x$DOWNS to RECHARGED SETTINGS row =="
for i in $(seq 1 "$DOWNS"); do inject "down"; sleep 0.35; clr; sleep 0.45; done
shot 21-graphics-recharged-row

echo "== X to enter RECHARGED SETTINGS (now: RECHARGED HUD / GRASS SETTINGS / BACK) =="
inject "x"; sleep 0.5; clr; sleep 1.6
shot 22-recharged-submenu

echo "== down 1 -> GRASS SETTINGS row, X to enter the NESTED grass sub-submenu =="
inject "down"; sleep 0.4; clr; sleep 0.7
shot 23-grass-settings-row-highlighted
inject "x"; sleep 0.5; clr; sleep 1.8
shot 24-grass-settings-nested
sleep 0.6
shot 24b-grass-settings-nested
echo "== step down the nested rows to prove each renders/adjusts =="
inject "down"; sleep 0.4; clr; sleep 0.7; shot 25-grass-row2
inject "down"; sleep 0.4; clr; sleep 0.7; shot 26-grass-row3
inject "down"; sleep 0.4; clr; sleep 0.7; shot 27-grass-row4

echo "== force-stop (device-hygiene) =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
echo "[nested-diag] DONE. Shots in $OUT/  (24*=the nested GRASS SETTINGS page — all grass rows)"
