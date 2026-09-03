#!/usr/bin/env bash
# Grecharged-loader-packfix — put the MESH BROWSER row ON SCREEN and photograph it.
# GRAPHIC OPTIONS -> RECHARGED SETTINGS is Android row index 8 (menu-tree.md §2: the
# desktop-only Display mode / Display / Frame rate rows do not exist here, so the
# ambient-occlusion-era "7 downs" is one short). Inside RECHARGED SETTINGS, MESH BROWSER
# is row 23 and Back is row 24, with several rows above conditionally hidden — so we
# reach it by cursor WRAP (two UPs from row 0) instead of counting downs.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
SER=AREE026206000788; PKG=org.opengoal.gk.jak1
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-loader-packfix/device; mkdir -p "$OUT"
a(){ "$ADB" -s "$SER" "$@"; }
inject(){ printf '%s' "$1" | a shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
tapb(){ inject "$1"; sleep 0.4; inject ""; sleep "${2:-0.9}"; }
shot(){ a exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; echo "   $1.png md5=$(md5sum "$OUT/$1.png" | cut -c1-10)"; }

echo "-- back out to a known state (triangle x4) --"
for i in 1 2 3 4; do tapb "triangle" 1.0; done
shot n00-backed-out

echo "-- start -> OPTIONS --"
tapb "start" 2.5
tapb "down" 0.7; tapb "down" 0.7; tapb "x" 2.0
shot n01-options

echo "-- down -> GRAPHIC OPTIONS --"
tapb "down" 0.8; tapb "x" 2.0
shot n02-graphic-options

echo "-- 8 downs -> RECHARGED SETTINGS row (android index 8) --"
for i in $(seq 1 8); do tapb "down" 0.55; done
shot n03-recharged-settings-row
echo "-- X -> enter RECHARGED SETTINGS --"
tapb "x" 2.0
shot n04-recharged-settings-page

echo "-- wrap: up -> Back (row 24) --"
tapb "up" 1.0; shot n05-row-back
echo "-- wrap: up -> MESH BROWSER (row 23) --"
tapb "up" 1.0; shot n06-MESH-BROWSER
echo "alive pid=$(a shell "pidof $PKG" | tr -d '\r')"
