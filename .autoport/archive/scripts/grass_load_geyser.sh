#!/usr/bin/env bash
# grass_load_geyser.sh — reach Geyser Rock (training) by LOADING the existing
# "ROCHER DU GEYSER" save (no intro, no overwrite), then confirm grass placed.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
F=.autoport/reports/Grecharged-grass-poc/frames; mkdir -p "$F"
LOG=/tmp/grass_live.log
pulse(){ $ADB shell setprop debug.opengoal.cpad_inject "$1"; sleep "${2:-0.4}"; $ADB shell setprop debug.opengoal.cpad_inject "neutral"; sleep "${3:-1.0}"; }
cap(){ $ADB exec-out screencap -p > "$F/$1.png" 2>/dev/null; echo "  cap $1 = $(stat -c %s "$F/$1.png" 2>/dev/null)B"; }

echo "== clean relaunch =="
$ADB shell am force-stop $PKG >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject "neutral" >/dev/null 2>&1
$ADB logcat -c >/dev/null 2>&1
( $ADB logcat -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/grass_lc.pid )
$ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
echo "  waiting for title (logo-loop)..."
t0=$(date +%s); while [ $(( $(date +%s)-t0 )) -lt 90 ]; do grep -aq 'link finish: logo-loop' "$LOG" && break; sleep 3; done
sleep 4; cap 10_title

echo "== START -> main menu =="
pulse "start" 0.4 2.0; cap 11_mainmenu

echo "== down to CHARGER UNE PARTIE (Load), enter =="
pulse "down" 0.35 0.8      # New Game -> Load Game
pulse "x" 0.4 2.0; cap 12_loadlist

echo "== select top save (ROCHER DU GEYSER), load =="
pulse "x" 0.4 2.0; cap 13_afterselect
# a confirm may appear; press x again to be safe
pulse "x" 0.4 2.0; cap 14_loading

echo "== monitor for training + grass (up to 90s) =="
ok=0
for i in $(seq 1 45); do
  sleep 2
  gl=$(grep -acaE 'recharged-grass' "$LOG")
  if [ "${gl:-0}" -gt 0 ]; then ok=1; echo "  >>> GRASS PLACED (t=$((i*2))s)"; break; fi
  [ $((i % 5)) -eq 0 ] && { mm=$(grep -aoE 'master-mode=[a-z]+' "$LOG" | tail -1); lk=$(grep -aoE 'link finish: (training|geyser|village1|beach)[a-z0-9-]*' "$LOG" | tail -1); echo "  t=$((i*2))s $mm $lk"; }
done
cap 15_afterload
echo "== grass line =="; grep -aE 'recharged-grass' "$LOG" | tail -3
echo "== target/master-mode =="; grep -aE 'GK-DIAG F1D target-pos' "$LOG" | tail -2
echo "== focus =="; $ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'
echo "RESULT ok=$ok"
