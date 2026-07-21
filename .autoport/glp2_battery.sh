#!/usr/bin/env bash
# glp2_battery.sh — Grecharged-lightprobes playtest#1/#2/#1b OBJECTIVE device battery.
# Runs every capture the reworked gates need, then prints all metrics. ~75 min device time.
# Captures (static = glp_capture.sh, native res; walk = glp2_walk_capture.sh, owner-realistic dyn RS):
#   MULTI-INTERIOR A/B : 4 auto-detected interiors x probe ON/OFF     (gate: interiors non-muted)
#   CONTRAST pair      : deck vantage ON/OFF                          (gate: contrast preserved)
#   REFLECTION no-op   : probes ON, refl ON vs OFF, same vantage      (gate: no grey wash)
#   NIGHT shadow pair  : hour 0 green-sun shadow ON/OFF               (gate: shadow visible)
#   WALK AO flicker    : AO=SSAO probes ON/OFF + AO=off probes ON     (gate: temporally stable)
#   MENU sweep         : screenrecord down-sweep of Recharged page    (gate: rename, no unknown-ID)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-lightprobes/device; mkdir -p "$OUT"
SUM="$OUT/battery_summary.txt"; : > "$SUM"
say(){ echo "== $*" | tee -a "$SUM"; }
adb(){ "$ADB" -s "$ANDROID_SERIAL" "$@"; }

# Interior warp targets from `probe_bake --dump-interiors` (world meters; y = cluster floor + 1).
# int1 = Samos's hut (the previously-proven interior vantage).
declare -A IPOS=(
  [int1]="-133.0 40.0 207.0"
  [int2]="-96.2 -3.0 14.2"
  [int3]="84.4 -7.0 -19.3"
  [int4]="-131.6 -3.0 -31.8"
)
DECK="-112.0 42.0 205.0"

say "A. MULTI-INTERIOR A/B (4 interiors x probe ON/OFF, hour 8, native)"
for k in int1 int2 int3 int4; do
  for p in 1 0; do
    bash .autoport/glp_capture.sh "b_${k}_p${p}" "$p" 0 1 village1-hut "${IPOS[$k]}" 8 2>&1 | tail -4 | tee -a "$SUM"
  done
done

say "B. CONTRAST pair (deck, hour 8, native)"
bash .autoport/glp_capture.sh b_ctr_on  1 0 1 village1-hut "$DECK" 8 2>&1 | tail -4 | tee -a "$SUM"
bash .autoport/glp_capture.sh b_ctr_off 0 0 1 village1-hut "$DECK" 8 2>&1 | tail -4 | tee -a "$SUM"

say "C. REFLECTION no-op pair (probes ON, refl 1 vs 0, deck)"
bash .autoport/glp_capture.sh b_refl_on  1 1 1 village1-hut "$DECK" 8 2>&1 | tail -4 | tee -a "$SUM"
# refl-off reference = b_ctr_on (probe=1 refl=0, same vantage/hour)

say "D. NIGHT green-sun shadow pair (hour 0, deck, native)"
bash .autoport/glp_capture.sh b_night_on  1 0 1 village1-hut "$DECK" 0 2>&1 | tail -4 | tee -a "$SUM"
bash .autoport/glp_capture.sh b_night_off 0 0 1 village1-hut "$DECK" 0 2>&1 | tail -4 | tee -a "$SUM"

say "E. WALK AO-flicker (SSAO, probes ON/OFF; + AO-off probes ON; dyn RS = owner-realistic)"
bash .autoport/glp2_walk_capture.sh b_walk_p1_ao1 1 1 village1-hut "$DECK" 8 0 2>&1 | tail -4 | tee -a "$SUM"
bash .autoport/glp2_walk_capture.sh b_walk_p0_ao1 0 1 village1-hut "$DECK" 8 0 2>&1 | tail -4 | tee -a "$SUM"
bash .autoport/glp2_walk_capture.sh b_walk_p1_ao0 1 0 village1-hut "$DECK" 8 0 2>&1 | tail -4 | tee -a "$SUM"

say "F. MENU sweep (screenrecord a full DOWN-sweep of the Recharged Settings page)"
stick(){ adb shell "setprop debug.opengoal.cpad_inject '$1'" </dev/null; }
tapb(){ stick "$1"; sleep 0.8; stick ""; sleep "${2:-1.8}"; }
adb shell am force-stop $PKG </dev/null; sleep 2
stick neutral
adb shell "setprop debug.opengoal.rt.probe ''" </dev/null
adb shell "setprop debug.opengoal.renderscale.native ''" </dev/null
adb shell "setprop debug.opengoal.ao.force_mode ''" </dev/null
adb shell "setprop debug.opengoal.tod.hour ''" </dev/null
adb shell setprop debug.opengoal.level.warp village1-hut </dev/null
adb shell "setprop debug.opengoal.level.warp.pos '$DECK'" </dev/null
adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 </dev/null || true
sleep 60   # boot + ND logo + level load, then in-game
FOCUS_MENU=$(adb shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r')
say "menu-run focus: $FOCUS_MENU"
adb shell rm -f /sdcard/glp2_menu.mp4 </dev/null
( adb shell screenrecord --time-limit 120 --bit-rate 8000000 /sdcard/glp2_menu.mp4 </dev/null ) &
RECP=$!
sleep 2
tapb "start" 3.0                                 # pause menu
tapb "down"; tapb "down"; tapb "x" 3.0           # OPTIONS
tapb "down"; tapb "x" 3.0                        # GRAPHIC OPTIONS
for i in $(seq 1 8); do tapb "down" 1.4; done    # -> RECHARGED SETTINGS row
tapb "x" 2.5                                     # enter recharged page
for i in $(seq 1 22); do tapb "down" 1.6; done   # full sweep past every row (wraps at end)
wait $RECP 2>/dev/null || true
sleep 1
adb pull /sdcard/glp2_menu.mp4 "$OUT/glp2_menu.mp4" >/dev/null 2>&1
adb shell rm -f /sdcard/glp2_menu.mp4 </dev/null
mkdir -p "$OUT/frames_b_menu"; rm -f "$OUT/frames_b_menu"/*.png
ffmpeg -y -loglevel error -i "$OUT/glp2_menu.mp4" -vf fps=1 "$OUT/frames_b_menu/m_%03d.png" 2>/dev/null
stick neutral
adb shell am force-stop $PKG </dev/null
say "menu frames: $(ls "$OUT/frames_b_menu" | wc -l)"

say "==================== METRICS ===================="
say "-- interiors: luma + RGB (ON vs OFF per interior)"
python3 .autoport/glp2_measure.py luma "$OUT"/frames_b_int?_p? 2>&1 | tee -a "$SUM"
say "-- interiors: contrast (detail preservation inside)"
python3 .autoport/glp2_measure.py contrast "$OUT"/frames_b_int?_p? 2>&1 | tee -a "$SUM"
say "-- contrast pair (deck): luma + contrast"
python3 .autoport/glp2_measure.py luma "$OUT"/frames_b_ctr_on "$OUT"/frames_b_ctr_off 2>&1 | tee -a "$SUM"
python3 .autoport/glp2_measure.py contrast "$OUT"/frames_b_ctr_on "$OUT"/frames_b_ctr_off 2>&1 | tee -a "$SUM"
say "-- reflections no-op (b_refl_on vs b_ctr_on must be ~identical)"
python3 .autoport/glp2_measure.py luma "$OUT"/frames_b_refl_on "$OUT"/frames_b_ctr_on 2>&1 | tee -a "$SUM"
python3 .autoport/glp2_measure.py contrast "$OUT"/frames_b_refl_on "$OUT"/frames_b_ctr_on 2>&1 | tee -a "$SUM"
say "-- ground grid-pattern FFT (ON vs OFF: no probe-added periodicity)"
python3 .autoport/glp2_measure.py gridfft "$OUT"/frames_b_ctr_on "$OUT"/frames_b_ctr_off 2>&1 | tee -a "$SUM"
say "-- night green-sun shadow contrast (ON vs OFF: shadow stays visible)"
python3 .autoport/glp2_measure.py shadowcontrast "$OUT"/frames_b_night_on "$OUT"/frames_b_night_off 2>&1 | tee -a "$SUM"
python3 .autoport/glp2_measure.py luma "$OUT"/frames_b_night_on "$OUT"/frames_b_night_off 2>&1 | tee -a "$SUM"
say "-- AO temporal stability on movement (probe ON vs OFF vs AO-off)"
python3 .autoport/glp2_measure.py flicker "$OUT"/frames_b_walk_p1_ao1 "$OUT"/frames_b_walk_p0_ao1 "$OUT"/frames_b_walk_p1_ao0 2>&1 | tee -a "$SUM"
say "battery DONE"
