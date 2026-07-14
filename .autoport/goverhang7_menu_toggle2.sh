#!/usr/bin/env bash
# goverhang7_menu_toggle2.sh — CORRECTED in-game menu drive (attempt-1 script navigated the pause
# stat pages, not the menu: in-game pause needs CIRCLE to open settings [progress.gc:1130], and with
# the owner's dynamic-render-scale?=#f the hidden MTF row puts RECHARGED SETTINGS at 7 downs, not 8).
# Stages:
#   boot  — warp boot to the owner training vantage (app force-stopped first)
#   nav   — pause -> CIRCLE -> down x1 X (Graphic Options) -> down x7 (RECHARGED) X -> down x1 X
#           (GRASS SETTINGS) -> down x5 (GRASS OVERHANG row). Screenshots each hop. NO flip. Menu left open.
#   flipA — X-right-X on the current row (expect ON->OFF), disk read, circle x4 + start resume,
#           shot + 10s stateA video (OFF at the vantage)
#   flipB — re-nav from game, flip back (OFF->ON), disk read, resume, shot + 10s stateB video (ON)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-grass-overhang7/menu-toggle2; mkdir -p "$OUT"
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak_1/saves/settings/pc-settings.gc"
adb(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clr(){ inject ""; }
tapb(){ inject "$1"; sleep 0.4; clr; sleep "${2:-0.8}"; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; echo "  shot $1 ($(stat -c%s "$OUT/$1.png" 2>/dev/null||echo 0)B)"; }
disk(){ adb shell cat "$SETTINGS_DEV" | grep -o "(recharged-grass-overhang? #[tf])" || echo "(key missing)"; }
rec(){ local N="$1" SEC="${2:-10}"
  fg > "$OUT/$N.focus"
  adb shell "screenrecord --time-limit $SEC /sdcard/gov7mt2_$N.mp4" & local P=$!
  sleep $((SEC+2)); wait $P 2>/dev/null || true
  adb pull "/sdcard/gov7mt2_$N.mp4" "$OUT/$N.mp4" >/dev/null 2>&1; adb shell rm -f "/sdcard/gov7mt2_$N.mp4" || true
  mkdir -p "$OUT/${N}_frames"; ffmpeg -y -loglevel error -i "$OUT/$N.mp4" -vf fps=2,scale=600:-1 "$OUT/${N}_frames/f_%03d.png"
  echo "  rec $N ($(stat -c%s "$OUT/$N.mp4" 2>/dev/null||echo 0)B) focus=$(cat "$OUT/$N.focus")"
}
nav_to_overhang(){ # from IN-GAME (unpaused) to the GRASS OVERHANG row; $1 = shot prefix
  tapb "start" 2.2;  shot "$1-01-pause"
  tapb "circle" 2.0; shot "$1-02-settings"
  tapb "down" 0.8;   tapb "x" 2.0; shot "$1-03-graphics"
  for i in $(seq 1 7); do tapb "down" 0.55; done
  shot "$1-04-recharged-row"
  tapb "x" 1.6;      shot "$1-05-recharged-submenu"
  tapb "down" 0.8;   tapb "x" 1.8; shot "$1-06-grass-page"
  for i in $(seq 1 5); do tapb "down" 0.55; done
  shot "$1-07-overhang-row"
}
resume_game(){ # unwind grass->recharged->graphics->settings->fuel-cell, then start to resume
  tapb "circle" 1.2; tapb "circle" 1.2; tapb "circle" 1.2; tapb "circle" 1.5
  tapb "start" 2.5
}

case "${1:?stage boot|nav|flipA|flipB}" in
boot)
  adb shell am force-stop $PKG >/dev/null 2>&1 || true; sleep 2
  adb logcat -c 2>/dev/null || true
  adb shell setprop debug.opengoal.level.warp training-start
  adb shell "setprop debug.opengoal.level.warp.pos '-1310.2 52.8 989.0'"
  adb shell am start -W -n "$PKG/.LoaderActivity" >/dev/null 2>&1 || true
  echo "  warp boot, settling 75s..."; sleep 75
  fg; echo "  disk: $(disk)"
  ;;
nav)
  fg | grep -q "$PKG" || { echo "app not foreground"; exit 1; }
  nav_to_overhang N
  echo "  menu left OPEN on the (claimed) GRASS OVERHANG row — verify N-07 before flipping"
  ;;
flipA)
  echo "  disk BEFORE: $(disk)"
  tapb "x" 0.9; shot F-08-edit
  tapb "right" 0.9; shot F-09-edited
  tapb "x" 1.5; shot F-10-committed
  sleep 1.5; echo "  disk after flipA: $(disk)"
  resume_game; shot F-11-ingame-off
  rec stateA-off 10
  ;;
flipB)
  nav_to_overhang R
  tapb "x" 0.9; tapb "right" 0.9; tapb "x" 1.5; shot R-08-committed
  sleep 1.5; echo "  disk after flipB: $(disk)"
  resume_game; shot R-09-ingame-on
  rec stateB-on 10
  echo "  disk FINAL: $(disk)"
  ;;
*) echo "unknown stage"; exit 1;;
esac
echo "[gov7 toggle2 $1] DONE"
