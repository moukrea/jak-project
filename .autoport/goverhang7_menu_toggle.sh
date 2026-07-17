#!/usr/bin/env bash
# goverhang7_menu_toggle.sh — Grecharged-grass-overhang7 STEP-3: prove the LIVE menu chain on device.
# Assumes the game is ALREADY in-game at beach (run after goverhang7_capture.sh D boot, app foreground).
# Drives: pause -> Options -> Graphic Options -> RECHARGED SETTINGS (row 8) -> GRASS SETTINGS (row 1)
#         -> GRASS OVERHANG (row 5): X-right-X toggle. Screenshot at every step; reads the on-disk
#         settings file after each commit; captures a 10s video after each flip (live effect proof).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-grass-overhang7/menu-toggle; mkdir -p "$OUT"
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
adb(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clr(){ inject ""; }
tapb(){ inject "$1"; sleep 0.4; clr; sleep "${2:-0.7}"; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; echo "  shot $1 ($(stat -c%s "$OUT/$1.png" 2>/dev/null||echo 0)B)"; }
disk(){ adb shell cat "$SETTINGS_DEV" | grep -o "^recharged-grass-overhang? = #[tf]" || echo "(key missing)"; }
rec(){ local N="$1" SEC="${2:-10}"
  fg > "$OUT/$N.focus"
  adb shell "screenrecord --time-limit $SEC /sdcard/gov7mt_$N.mp4" & local P=$!
  sleep $((SEC+2)); wait $P 2>/dev/null || true
  adb pull "/sdcard/gov7mt_$N.mp4" "$OUT/$N.mp4" >/dev/null 2>&1; adb shell rm -f "/sdcard/gov7mt_$N.mp4" || true
  mkdir -p "$OUT/${N}_frames"; ffmpeg -y -loglevel error -i "$OUT/$N.mp4" -vf fps=2,scale=600:-1 "$OUT/${N}_frames/f_%03d.png"
  echo "  rec $N ($(stat -c%s "$OUT/$N.mp4" 2>/dev/null||echo 0)B) focus=$(cat "$OUT/$N.focus")"
}

fg | grep -q "$PKG" || { echo "app not foreground — boot to beach first"; exit 1; }
echo "== disk BEFORE: $(disk) =="

echo "== pause -> Options -> Graphic Options =="
tapb "start" 2.2; shot 01-pause
tapb "down"; tapb "down"; shot 02-options-row
tapb "x" 2.0; shot 03-options-menu
tapb "down"; tapb "x" 2.0; shot 04-graphics-menu

echo "== down x8 -> RECHARGED SETTINGS -> enter =="
for i in $(seq 1 8); do tapb "down" 0.5; done
shot 05-recharged-row
tapb "x" 1.6; shot 06-recharged-submenu

echo "== down x1 -> GRASS SETTINGS -> enter =="
tapb "down"; tapb "x" 1.8; shot 07-grass-page

echo "== down x5 -> GRASS OVERHANG row =="
for i in $(seq 1 5); do tapb "down" 0.5; done
shot 08-overhang-row

echo "== FLIP #1 (X-right-X): expect ON->OFF =="
tapb "x" 0.8; tapb "right" 0.9; shot 09-edit; tapb "x" 1.2; shot 10-flipped
sleep 1.5
echo "  disk after flip1: $(disk)"

echo "== unwind menu (circle x4) + film the lips (toggle state A) =="
tapb "circle" 1.3; tapb "circle" 1.3; tapb "circle" 1.3; tapb "circle" 2.5
shot 11-ingame-stateA
rec stateA 10

echo "== back in: same walk, FLIP #2 back =="
tapb "start" 2.2
tapb "down"; tapb "down"; tapb "x" 2.0
tapb "down"; tapb "x" 2.0
for i in $(seq 1 8); do tapb "down" 0.5; done
tapb "x" 1.6
tapb "down"; tapb "x" 1.8
for i in $(seq 1 5); do tapb "down" 0.5; done
shot 12-overhang-row-2
tapb "x" 0.8; tapb "right" 0.9; tapb "x" 1.2; shot 13-flipped-back
sleep 1.5
echo "  disk after flip2: $(disk)"
tapb "circle" 1.3; tapb "circle" 1.3; tapb "circle" 1.3; tapb "circle" 2.5
shot 14-ingame-stateB
rec stateB 10

echo "== logcat toggle lines =="
adb logcat -d 2>/dev/null | grep -a "GOVERHANG\|PLACE-TIME\|toggle" | tail -6 | cut -c1-200
echo "== disk FINAL: $(disk) =="
echo "[gov7 menu-toggle] DONE — verify shots 10/13 show the row value flip and stateA/stateB videos differ at the lips"
