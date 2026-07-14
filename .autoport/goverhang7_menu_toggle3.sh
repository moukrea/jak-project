#!/usr/bin/env bash
# goverhang7_menu_toggle3.sh — round-7 LIVE menu-toggle proof, CORRECTED resume path.
# toggle2's resume (circle x4 + start) never closed the custom grass page; proven path is:
#   down -> X on RETOUR (grass page) -> TRIANGLE (recharged) -> TRIANGLE (graphics)
#   -> TRIANGLE (options) -> START at pause root (main.gc start only resumes from root).
# Staged so the manager can eyeball the highlighted row BEFORE each flip (toggle2's flipB
# hit GRASS DENSITY because it re-navigated from a menu-open state).
# Stages: on | navoff | flipoff | navon | flipon | final
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1
INJECT="/data/data/$PKG/files/cpad_inject"
OUT=.autoport/reports/Grecharged-grass-overhang7/menu-toggle3; mkdir -p "$OUT"
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak_1/saves/settings/pc-settings.gc"
adb(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
tapb(){ inject "$1"; sleep 0.4; inject ""; sleep "${2:-0.9}"; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; echo "  shot $1 ($(stat -c%s "$OUT/$1.png" 2>/dev/null||echo 0)B)"; }
disk(){ adb shell cat "$SETTINGS_DEV" | grep -o "(recharged-grass-overhang? #[tf])" || echo "(key missing)"; }
rec(){ local N="$1" SEC="${2:-10}"
  fg > "$OUT/$N.focus"
  adb shell "screenrecord --time-limit $SEC /sdcard/gov7mt3_$N.mp4" & local P=$!
  sleep $((SEC+2)); wait $P 2>/dev/null || true
  adb pull "/sdcard/gov7mt3_$N.mp4" "$OUT/$N.mp4" >/dev/null 2>&1; adb shell rm -f "/sdcard/gov7mt3_$N.mp4" >/dev/null 2>&1 || true
  fg >> "$OUT/$N.focus"
  mkdir -p "$OUT/${N}_frames"; ffmpeg -y -loglevel error -i "$OUT/$N.mp4" -vf fps=1,scale=800:-1 "$OUT/${N}_frames/f_%03d.png"
  echo "  rec $N ($(stat -c%s "$OUT/$N.mp4" 2>/dev/null||echo 0)B) focus: $(cat "$OUT/$N.focus" | tr '\n' '|')"
}
nav_to_overhang(){ # from IN-GAME to the GRASS OVERHANG row; $1 = shot prefix. NO flip.
  tapb "start" 2.2;  shot "$1-01-pause"
  tapb "circle" 2.0; shot "$1-02-options"
  tapb "down" 0.8;   tapb "x" 2.0; shot "$1-03-graphics"
  for i in $(seq 1 7); do tapb "down" 0.55; done
  tapb "x" 1.6;      shot "$1-04-recharged"
  tapb "down" 0.8;   tapb "x" 1.8; shot "$1-05-grass-page"
  for i in $(seq 1 5); do tapb "down" 0.55; done
  shot "$1-06-overhang-row"
  echo "  VERIFY $1-06: highlighted row MUST be GRASS OVERHANG before flipping"
}
resume_game(){ # PROVEN unwind from the overhang row (cursor on row 5 of grass page)
  tapb "down" 0.8; tapb "x" 1.6     # RETOUR -> recharged page
  tapb "triangle" 1.2               # -> graphics
  tapb "triangle" 1.2               # -> options
  tapb "triangle" 1.5               # -> pause root
  tapb "start" 2.5                  # resume gameplay
}

case "${1:?stage on|navoff|flipoff|navon|flipon|final}" in
on)
  adb shell cat "$SETTINGS_DEV" > "$OUT/settings-prerun.gc"
  echo "  disk pre-run: $(disk)"
  fg; shot live-on-still
  rec live-on 10
  ;;
navoff) nav_to_overhang N ;;
flipoff)
  echo "  disk BEFORE flip: $(disk)" | tee "$OUT/disk-reads.txt"
  tapb "x" 0.9; tapb "right" 0.9; tapb "x" 1.5; shot N-07-committed-off
  sleep 1.5; echo "  disk AFTER OFF flip: $(disk)" | tee -a "$OUT/disk-reads.txt"
  resume_game; shot off-ingame
  rec live-off 10
  ;;
navon) nav_to_overhang R ;;
flipon)
  tapb "x" 0.9; tapb "right" 0.9; tapb "x" 1.5; shot R-07-committed-on
  sleep 1.5; echo "  disk AFTER ON flip: $(disk)" | tee -a "$OUT/disk-reads.txt"
  resume_game; shot on-ingame
  rec live-on2 10
  ;;
final)
  adb shell cat "$SETTINGS_DEV" > "$OUT/settings-postrun.gc"
  echo "  disk FINAL: $(disk)" | tee -a "$OUT/disk-reads.txt"
  if cmp -s "$OUT/settings-prerun.gc" "$OUT/settings-postrun.gc"; then
    echo "  settings pre==post byte-identical" | tee -a "$OUT/disk-reads.txt"
  else diff "$OUT/settings-prerun.gc" "$OUT/settings-postrun.gc" | head -8; fi
  fg
  ;;
*) echo "unknown stage"; exit 1;;
esac
echo "[gov7 toggle3 $1] DONE"