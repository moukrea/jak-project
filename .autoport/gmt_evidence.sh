#!/usr/bin/env bash
# gmt_evidence.sh — Grecharged-master-toggle device evidence, staged.
# Stages:
#   abset rec|masteroff|alloff   configure settings.ini (app force-stopped first — a live app
#                                rewrites the file on exit and clobbers the edit)
#   cap <tag>                    boot at the pinned vantage (village1-hut, TOD noon, native render
#                                scale), screenrecord, extract a settled frame -> device/<tag>.png
#   compare                      the OFF==stock gate: masteroff vs alloff MUST MATCH (thr24 tol2%);
#                                rec vs alloff MUST MISMATCH (the beat discriminates)
#   prop                         headless-vanilla proof in ONE boot (config rec): capture, flip
#                                debug.opengoal.recharged 0 -> capture (== stock), clear -> capture
#                                (== recharged again); settings.ini untouched; logcat override line
#   menu <stage>                 boot|nav|flipoff|greys|flipon|persistcheck — the user flow: master
#                                row 0 flip OFF -> rows greyed screenshots -> flip ON -> settings diff
#
# Vantage/beat: village1-hut pos '-112.0 42.0 205.0' (owner vantage, lightprobes phase),
# debug.opengoal.tod.hour 1200 (pinned noon — same baked-light keyframe mix every boot),
# debug.opengoal.renderscale.native 1 (kills the adaptive render-scale as a diff source).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-master-toggle/device; mkdir -p "$OUT"
PCS="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
INJECT="/data/data/$PKG/files/cpad_inject"
adb(){ "$ADB" -s "$S" "$@"; }
die(){ echo "[gmt-ev FAIL] $*" >&2; exit 1; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
fg_require(){ local f; f=$(fg); echo "  focus: $f"; case "$f" in *org.opengoal.gk.jak1*) : ;; *) die "jak1 not foreground: $f";; esac }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
tapb(){ inject "$1"; sleep 0.4; inject ""; sleep "${2:-0.9}"; }
shot(){ adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null; echo "  shot $1 ($(stat -c%s "$OUT/$1.png" 2>/dev/null||echo 0)B)"; }
disk_master(){ adb shell cat "$PCS" 2>/dev/null | grep -aE '^recharged-master\?' | tr -d '\r'; }

set_kv(){ # set_kv <file> <key-regex-escaped> <value-line>
  local f="$1" k="$2" v="$3"
  if grep -qE "^$k = " "$f"; then sed -i "s/^$k = .*/$v/" "$f"; else sed -i "/^\[secrets\]/i $v" "$f"; fi
}

settings_config(){ # rec | masteroff | alloff
  adb shell am force-stop $PKG; sleep 2
  adb shell cat "$PCS" > /tmp/gmt_pcs.ini 2>/dev/null || die "cannot read $PCS"
  tr -d '\r' < /tmp/gmt_pcs.ini > /tmp/gmt_pcs2.ini && mv /tmp/gmt_pcs2.ini /tmp/gmt_pcs.ini
  case "$1" in
    rec) # master ON + a visibly-recharged config (grass/pbr/realtime/wind ON). AO stays 0:
         # enabling AO arms the safe-boot sentinel, and our short capture boots end in a
         # force-stop within its 60s healthy window -> next boot would pin AO off and
         # desync the A/B configs. The master gating of AO is source-level (effective_mode
         # wrap) + menu-greying evidence; the pixel A/B doesn't need it.
      set_kv /tmp/gmt_pcs.ini 'recharged-master\?' 'recharged-master? = #t'
      set_kv /tmp/gmt_pcs.ini 'recharged-grass\?' 'recharged-grass? = #t'
      set_kv /tmp/gmt_pcs.ini 'pbr-materials\?' 'pbr-materials? = #t'
      set_kv /tmp/gmt_pcs.ini 'realtime-lighting\?' 'realtime-lighting? = #t'
      set_kv /tmp/gmt_pcs.ini 'recharged-foliage-wind\?' 'recharged-foliage-wind? = #t'
      set_kv /tmp/gmt_pcs.ini 'ambient-occlusion' 'ambient-occlusion = 0'
      ;;
    masteroff) # SAME individual config as rec, ONLY the master flipped
      set_kv /tmp/gmt_pcs.ini 'recharged-master\?' 'recharged-master? = #f'
      set_kv /tmp/gmt_pcs.ini 'recharged-grass\?' 'recharged-grass? = #t'
      set_kv /tmp/gmt_pcs.ini 'pbr-materials\?' 'pbr-materials? = #t'
      set_kv /tmp/gmt_pcs.ini 'realtime-lighting\?' 'realtime-lighting? = #t'
      set_kv /tmp/gmt_pcs.ini 'recharged-foliage-wind\?' 'recharged-foliage-wind? = #t'
      set_kv /tmp/gmt_pcs.ini 'ambient-occlusion' 'ambient-occlusion = 0'
      ;;
    alloff) # master ON, EVERY per-feature toggle at its stock value (the accepted per-feature
            # OFF==stock composition this phase must reproduce with one switch)
      set_kv /tmp/gmt_pcs.ini 'recharged-master\?' 'recharged-master? = #t'
      set_kv /tmp/gmt_pcs.ini 'recharged-grass\?' 'recharged-grass? = #f'
      set_kv /tmp/gmt_pcs.ini 'pbr-materials\?' 'pbr-materials? = #f'
      set_kv /tmp/gmt_pcs.ini 'realtime-lighting\?' 'realtime-lighting? = #f'
      set_kv /tmp/gmt_pcs.ini 'recharged-foliage-wind\?' 'recharged-foliage-wind? = #f'
      set_kv /tmp/gmt_pcs.ini 'ambient-occlusion' 'ambient-occlusion = 0'
      set_kv /tmp/gmt_pcs.ini 'load-custom-assets\?' 'load-custom-assets? = #f'
      set_kv /tmp/gmt_pcs.ini 'recharged-enhanced-models\?' 'recharged-enhanced-models? = #f'
      ;;
    *) die "unknown config $1";;
  esac
  adb push /tmp/gmt_pcs.ini /data/local/tmp/gmt_pcs.ini >/dev/null 2>&1 || die "push failed"
  adb shell cp /data/local/tmp/gmt_pcs.ini "$PCS" || die "cp to settings failed"
  echo "  config '$1' applied:"; adb shell cat "$PCS" | grep -aE '^(recharged-master|recharged-grass|pbr-materials|realtime-lighting|recharged-foliage-wind|ambient-occlusion|load-custom-assets|recharged-enhanced-models)' | sed 's/^/    /'
}

warp_props(){
  adb shell setprop debug.opengoal.level.warp village1-hut
  adb shell "setprop debug.opengoal.level.warp.pos '-112.0 42.0 205.0'"
  adb shell setprop debug.opengoal.tod.hour 1200
  adb shell setprop debug.opengoal.renderscale.native 1
}
clear_props(){
  adb shell setprop debug.opengoal.level.warp '""'
  adb shell setprop debug.opengoal.level.warp.pos '""'
  adb shell setprop debug.opengoal.tod.hour '""'
  adb shell setprop debug.opengoal.renderscale.native '""'
  adb shell setprop debug.opengoal.recharged '""'
}

boot_to_vantage(){ # -> waits for LEVEL-WARP-SPAWN + settle
  adb shell am force-stop $PKG; sleep 2
  adb logcat -c 2>/dev/null || true
  warp_props
  LOG="$OUT/logcat-$1.log"; : > "$LOG"
  ( adb logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
     | grep --line-buffered -aE 'LEVEL-WARP-SPAWN|recharged-master|recharged-ao|foliage-wind|HD-MODELS|Fatal signal|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
  LCP=$!
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 300 ]; do
    grep -aq 'LEVEL-WARP-SPAWN name=village1-hut' "$LOG" && break; sleep 5
  done
  grep -aq 'LEVEL-WARP-SPAWN name=village1-hut' "$LOG" || die "no LEVEL-WARP-SPAWN in 300s (log $LOG)"
  echo "  spawned; settling 20s (static camera, pinned TOD)"; sleep 20
  fg_require
}

grab_frame(){ # grab_frame <tag> — screenrecord (GL surface; screencap is black on it), last frame
  adb shell screenrecord --time-limit 6 --bit-rate 8000000 /sdcard/gmt_$1.mp4
  adb pull /sdcard/gmt_$1.mp4 /tmp/gmt_$1.mp4 >/dev/null 2>&1 || die "pull rec failed"
  adb shell rm -f /sdcard/gmt_$1.mp4
  rm -rf /tmp/gmt_frames_$1; mkdir -p /tmp/gmt_frames_$1
  ffmpeg -y -loglevel error -i /tmp/gmt_$1.mp4 -vf fps=2 /tmp/gmt_frames_$1/f_%03d.png
  local last; last=$(ls /tmp/gmt_frames_$1/f_*.png | tail -1)
  [ -n "$last" ] || die "no frames extracted for $1"
  cp "$last" "$OUT/$1.png"; echo "  frame -> $OUT/$1.png"
  rm -rf /tmp/gmt_frames_$1 /tmp/gmt_$1.mp4   # don't hoard capture intermediates (owner rule)
}

case "${1:?stage}" in
abset) settings_config "${2:?rec|masteroff|alloff}";;
cap)
  TAG=${2:?tag}
  boot_to_vantage "$TAG"
  grab_frame "$TAG"
  adb shell am force-stop $PKG
  ;;
compare)
  echo "== OFF==stock gate: masteroff vs alloff (same build+vantage+TOD, same renderer) =="
  python3 .autoport/lib/frame_compare.py "$OUT/alloff.png" "$OUT/masteroff.png" --threshold 24 --tolerance 0.02 \
    --diff "$OUT/diff_masteroff_vs_alloff.png" | tee "$OUT/compare_off_stock.txt"
  echo "== discrimination sanity: rec vs alloff MUST MISMATCH =="
  python3 .autoport/lib/frame_compare.py "$OUT/alloff.png" "$OUT/rec.png" --threshold 24 --tolerance 0.02 \
    | tee "$OUT/compare_rec_vs_stock.txt" || true
  grep -q '^MATCH ' "$OUT/compare_off_stock.txt" || die "masteroff vs alloff did not MATCH"
  grep -q '^MISMATCH ' "$OUT/compare_rec_vs_stock.txt" || die "rec vs alloff did not MISMATCH (beat cannot discriminate)"
  echo "[gmt-ev compare] PASS"
  ;;
prop)
  # config must be 'rec' (master ON + features ON). One boot, three captures.
  settings_config rec
  boot_to_vantage prop_run
  grab_frame prop_before
  echo "  -> setprop debug.opengoal.recharged 0 (force vanilla, settings untouched)"
  adb shell setprop debug.opengoal.recharged 0; sleep 4
  grab_frame prop_forced0
  echo "  -> clear prop (back to the persisted master=ON config)"
  adb shell setprop debug.opengoal.recharged '""'; sleep 4
  grab_frame prop_cleared
  fg_require
  adb shell am force-stop $PKG
  echo "  settings after prop flips (must still be master #t): $(disk_master)"
  [ "$(disk_master)" = "recharged-master? = #t" ] || die "prop flip touched the saved settings!"
  echo "== prop_forced0 vs alloff (stock) MUST MATCH =="
  python3 .autoport/lib/frame_compare.py "$OUT/alloff.png" "$OUT/prop_forced0.png" --threshold 24 --tolerance 0.02 \
    --diff "$OUT/diff_prop0_vs_alloff.png" | tee "$OUT/compare_prop0_stock.txt"
  echo "== prop_before vs prop_forced0 MUST MISMATCH (the flip did something) =="
  python3 .autoport/lib/frame_compare.py "$OUT/prop_before.png" "$OUT/prop_forced0.png" --threshold 24 --tolerance 0.02 \
    | tee "$OUT/compare_prop_flip.txt" || true
  echo "== prop_cleared vs prop_before MUST MATCH (clean revert) =="
  python3 .autoport/lib/frame_compare.py "$OUT/prop_before.png" "$OUT/prop_cleared.png" --threshold 24 --tolerance 0.02 \
    | tee "$OUT/compare_prop_revert.txt"
  grep -q '^MATCH ' "$OUT/compare_prop0_stock.txt" || die "prop=0 frame != stock"
  grep -q '^MISMATCH ' "$OUT/compare_prop_flip.txt" || die "prop flip changed nothing"
  grep -q '^MATCH ' "$OUT/compare_prop_revert.txt" || die "prop clear did not revert"
  echo "  logcat override evidence:"; grep -a 'recharged-master' "$OUT/logcat-prop_run.log" | tail -4
  echo "[gmt-ev prop] PASS"
  ;;
menu)
  ST=${2:?boot|nav|flipoff|greys|flipon|persistcheck}
  case "$ST" in
  boot)
    settings_config rec
    adb shell cat "$PCS" > "$OUT/settings-pre-menu.ini" 2>/dev/null
    clear_props
    adb logcat -c 2>/dev/null || true
    adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
    echo "  waiting 75s for title/attract..."; sleep 75
    fg_require; shot menu-00-title
    ;;
  nav) # title -> main menu -> options -> graphics -> recharged settings (ao_menu_toggle path)
    tapb "start" 2.5; shot menu-01-main
    tapb "down" 0.7; tapb "down" 0.7
    tapb "x" 2.0; shot menu-02-options
    tapb "down" 0.8; tapb "x" 2.0; shot menu-03-graphics
    for i in $(seq 1 7); do tapb "down" 0.55; done
    shot menu-04-recharged-row
    tapb "x" 1.8; shot menu-05-recharged-page-master-row0
    echo "  VERIFY menu-05: highlighted row 0 MUST read RECHARGED MASTER (On)"
    ;;
  flipoff) # master row 0 is the entry highlight: X, RIGHT=OFF, X (directional edit)
    tapb "x" 0.9; shot menu-06-edit-open
    tapb "right" 0.9; shot menu-07-off-selected
    tapb "x" 1.6; shot menu-08-master-off-rows-greyed
    sleep 1.5
    echo "  disk: $(disk_master) (menu flip commits immediately)"
    ;;
  greys) # scroll down the page so every greyed row is captured; X on a greyed row must no-op
    for i in 1 2 3; do tapb "down" 0.55; done; shot menu-09-greyed-rows-a
    tapb "x" 0.9; shot menu-10-greyed-row-x-noop
    for i in 1 2 3 4; do tapb "down" 0.55; done; shot menu-11-greyed-rows-b
    for i in $(seq 1 7); do tapb "up" 0.5; done   # back to row 0
    ;;
  flipon)
    tapb "x" 0.9; tapb "left" 0.9; shot menu-12-on-selected
    tapb "x" 1.6; shot menu-13-master-on-rows-back
    sleep 1.5
    echo "  disk: $(disk_master)"
    ;;
  persistcheck)
    adb shell am force-stop $PKG; sleep 2
    adb shell cat "$PCS" > "$OUT/settings-post-menu.ini" 2>/dev/null
    echo "== individual settings preserved across master OFF->ON menu flips =="
    if diff <(tr -d '\r' < "$OUT/settings-pre-menu.ini") <(tr -d '\r' < "$OUT/settings-post-menu.ini") > "$OUT/settings-diff.txt"; then
      echo "  IDENTICAL settings.ini (master ended #t as it started; zero other-key churn)"
    else
      echo "  diff (must touch NOTHING but recharged-master? transitions):"; cat "$OUT/settings-diff.txt"
      # acceptable: no diff at all. Any other-key change is a FAIL.
      grep -vE '^[0-9<>,-]|recharged-master' "$OUT/settings-diff.txt" | grep -q . && die "non-master settings churned"
    fi
    echo "[gmt-ev menu] settings-preservation check done"
    ;;
  esac
  ;;
cleanup)
  clear_props
  adb shell am force-stop $PKG
  ;;
*) die "unknown stage $1";;
esac
echo "[gmt-ev ${1}${2:+ }${2:-}] DONE"
