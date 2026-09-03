#!/usr/bin/env bash
# gjak2polish_menu_capture.sh — Gjak2-polish item 3 (menu order + ADVANCED SETTINGS)
# and a probe toward item 4 (FPS Counter row). Boots <game>, opens the pause/options
# menu, walks toward Graphic Options capturing EVERY step so the screencaps reveal the
# actual nav path + the reordered graphics page. Non-destructive (no toggles here).
# Usage: gjak2polish_menu_capture.sh <jak1|jak2>
set -u
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; GAME="${1:?game jak1|jak2}"; PKG=org.opengoal.gk.$GAME; ACT=org.opengoal.gk.LoaderActivity
DIR=/home/emeric/code/jak-project/.autoport/reports/Gjak2-polish/evidence
FOC="$DIR/menu-${GAME}-focus.txt"; mkdir -p "$DIR"; : > "$FOC"
inj(){ $ADB shell setprop debug.opengoal.cpad_inject "$1" >/dev/null 2>&1; }
clr(){ $ADB shell setprop debug.opengoal.cpad_inject '""' >/dev/null 2>&1; }
trap 'clr' EXIT INT TERM
tap(){ inj "$1"; sleep "${2:-0.5}"; clr; sleep 0.6; }
cap(){ local n="$1" foc; foc=$($ADB shell dumpsys window 2>/dev/null|grep -iE mCurrentFocus|head -1|tr -d '\r'); local o="$DIR/menu-${GAME}-${n}.png"; $ADB exec-out screencap -p > "$o" 2>/dev/null; echo "  [$n] $foc -> ${o##*/} ($(stat -c %s "$o" 2>/dev/null||echo 0)B)"|tee -a "$FOC"; }

LEFT=$(pgrep -af 'gjak2|f1d_run|gtf_|capture_device' | grep -v $$ | grep -v grep || true)
[ -n "$LEFT" ] && { echo "LEFTOVER RUNNERS — aborting:"; echo "$LEFT"; exit 3; }
$ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
$ADB shell svc power stayon true >/dev/null 2>&1
$ADB shell am force-stop $PKG; clr; sleep 2
$ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
echo "== warmup to title (65s) ==" | tee -a "$FOC"; sleep 65; cap 01-title
$ADB shell pidof $PKG >/dev/null 2>&1 || { echo "APP DEAD AT TITLE"|tee -a "$FOC"; exit 4; }
# open menu from title attract
tap start 1.2; cap 02-after-start
# jak1-style: down,down highlights Options; capture the menu items as we go
tap down 0.4; cap 03-down1
tap down 0.4; cap 04-down2
tap x 1.0; cap 05-after-x-options       # expect Options submenu (Game/Graphic/Sound/Back)
tap down 0.4; cap 06-down-in-options
tap x 1.0; cap 07-graphic-options       # expect the Graphic Options page
# scroll the graphics page to reveal all rows + the ADVANCED SETTINGS row + order
tap down 0.4; cap 08-gfx-row1
tap down 0.4; cap 09-gfx-row2
tap down 0.4; cap 10-gfx-row3
tap down 0.4; cap 11-gfx-row4
tap down 0.4; cap 12-gfx-row5
tap down 0.4; cap 13-gfx-row6
tap down 0.4; cap 14-gfx-row7
tap down 0.4; cap 15-gfx-row8
tap up 0.3; tap up 0.3; tap up 0.3; tap up 0.3; tap up 0.3; tap up 0.3; tap up 0.3; tap up 0.3; cap 16-gfx-top
foc=$($ADB shell dumpsys window|grep -iE mCurrentFocus|head -1|tr -d '\r'); echo "final focus=$foc"|tee -a "$FOC"
echo "DONE $GAME menu capture -> $DIR/menu-${GAME}-*.png"
