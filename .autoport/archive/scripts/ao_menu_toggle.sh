#!/usr/bin/env bash
# ao_menu_toggle.sh — Grecharged-ambient-occlusion LIVE menu proof (staged).
# Proves the REAL user flow: pause menu -> graphics -> Recharged Settings -> the two new
# carousell rows (AMBIENT OCCLUSION Off/SSAO/HBAO/GTAO + AO QUALITY Low/Medium/High) ->
# values change on screen -> GOAL pushes to C++ ([recharged-ao] logcat line) -> persisted
# to the EXTERNAL pc-settings file -> survives a relaunch.
# Staged like goverhang7_menu_toggle3.sh so the manager can eyeball the highlighted row
# BEFORE each flip. Stages: boot | nav | flipao | flipquality | resume | persist | reset
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-ambient-occlusion/menu-toggle; mkdir -p "$OUT"
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
adb(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
tapb(){ inject "$1"; sleep 0.4; inject ""; sleep "${2:-0.9}"; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; echo "  shot $1 ($(stat -c%s "$OUT/$1.png" 2>/dev/null||echo 0)B)"; }
disk(){ adb shell cat "$SETTINGS_DEV" 2>/dev/null | grep -oE "^(ambient-occlusion|ao-quality) = [0-9]+" | tr '\n' ' '; echo; }
lastao(){ adb logcat -d -v brief opengoal-gk:I GK_STDOUT:I '*:S' 2>/dev/null | grep -a "recharged-ao" | tail -2; }

case "${1:?stage boot|nav|flipao|flipquality|resume|persist|reset}" in
boot)
  adb shell cat "$SETTINGS_DEV" > "$OUT/settings-prerun.gc" 2>/dev/null || true
  echo "  disk pre-run: $(disk)"
  adb shell am force-stop $PKG; sleep 2
  adb shell setprop debug.opengoal.level.warp '""'; adb shell setprop debug.opengoal.level.warp.pos '""'
  adb logcat -c 2>/dev/null || true
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  echo "  waiting 75s for title/attract..."; sleep 75
  fg; shot boot-title
  ;;
nav)  # from title: START into game menu? No — pause menu needs in-game. From TITLE the
      # options menu is reachable directly: X on title -> main menu -> OPTIONS row.
      # Simpler + proven: START from in-game. But the title main menu ALSO exposes
      # OPTIONS (progress-screen). Use title path: press start/X to leave attract, then
      # navigate: NOUVELLE PARTIE / CHARGER / OPTIONS ... -> OPTIONS is row 2.
  tapb "start" 2.5; shot nav-01-main-menu
  tapb "down" 0.7; tapb "down" 0.7; shot nav-02-options-row
  tapb "x" 2.0; shot nav-03-options
  tapb "down" 0.8; tapb "x" 2.0; shot nav-04-graphics
  for i in $(seq 1 7); do tapb "down" 0.55; done   # 7 downs = RECHARGED SETTINGS (proven by goverhang7_menu_toggle3)
  shot nav-05-recharged-row
  tapb "x" 1.8; shot nav-06-recharged-page
  for i in $(seq 1 5); do tapb "down" 0.55; done
  shot nav-07-ao-row
  echo "  VERIFY nav-07: highlighted row MUST read AMBIENT OCCLUSION (value Off) before flipao"
  ;;
flipao)
  echo "  disk BEFORE: $(disk)" | tee "$OUT/disk-reads.txt"
  tapb "x" 0.9; shot flip-01-edit-open
  tapb "right" 0.9; shot flip-02-ssao-selected
  tapb "x" 1.6; shot flip-03-committed-ssao
  sleep 1.5
  echo "  disk AFTER AO=SSAO: $(disk)" | tee -a "$OUT/disk-reads.txt"
  echo "  logcat: $(lastao)" | tee -a "$OUT/disk-reads.txt"
  ;;
flipquality)
  tapb "down" 0.8; shot flip-04-quality-row
  tapb "x" 0.9; tapb "right" 0.9; shot flip-05-high-selected
  tapb "x" 1.6; shot flip-06-committed-high
  sleep 1.5
  echo "  disk AFTER Q=HIGH: $(disk)" | tee -a "$OUT/disk-reads.txt"
  echo "  logcat: $(lastao)" | tee -a "$OUT/disk-reads.txt"
  ;;
resume) # unwind: down to Back (row 7) -> X -> graphics -> triangle x2 -> title menu
  tapb "down" 0.8; tapb "x" 1.6
  tapb "triangle" 1.2; tapb "triangle" 1.5
  shot resume-01-back-out
  ;;
persist)
  adb shell am force-stop $PKG; sleep 2
  adb logcat -c 2>/dev/null || true
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  echo "  waiting 70s for boot + settings load + first update-to-os push..."; sleep 70
  echo "  disk after relaunch: $(disk)" | tee -a "$OUT/disk-reads.txt"
  echo "  logcat after relaunch: $(lastao)" | tee -a "$OUT/disk-reads.txt"
  fg
  ;;
reset)  # restore owner default: AO off, quality medium — via the settings file (established
        # foliage precedent), then force-stop so next boot reads it.
  adb shell am force-stop $PKG; sleep 1
  adb shell cat "$SETTINGS_DEV" > /tmp/pcs_ao.gc 2>/dev/null
  sed -i "s/^ambient-occlusion = [0-9]*/ambient-occlusion = 0/" /tmp/pcs_ao.gc
  sed -i "s/^ao-quality = [0-9]*/ao-quality = 1/" /tmp/pcs_ao.gc
  adb push /tmp/pcs_ao.gc "$SETTINGS_DEV" >/dev/null 2>&1
  echo "  disk after reset: $(disk)" | tee -a "$OUT/disk-reads.txt"
  adb shell cat "$SETTINGS_DEV" > "$OUT/settings-postrun.gc" 2>/dev/null || true
  ;;
*) echo "unknown stage"; exit 1;;
esac
echo "[ao menu-toggle $1] DONE"
