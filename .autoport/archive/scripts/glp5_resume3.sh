#!/usr/bin/env bash
# glp5_resume3.sh — finish the glp5 reopen battery (attempt-6 session died while its r_deck_van
# capture process hung post-"done"; frames_r_deck_van is valid/complete). Remaining work:
#   - the ONE missing capture: r_int2_van (VANILLA baked reference, oracle interior)
#   - restore owner settings + clear eval props
#   - compute the full §14 metric set into reopen_summary.txt (append)
# STRICTLY SEQUENTIAL: this is the only device script running.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb; SER=eae4df44
OUT=.autoport/reports/Grecharged-lightprobes/device
SUM="$OUT/reopen_summary.txt"
say(){ echo "== $*" | tee -a "$SUM"; }
SET=/storage/emulated/0/OpenGOAL/jak1/settings.ini
INT2="86.0 18.5 17.4"
restore(){ $ADB -s $SER push "$OUT/settings.ini.owner-backup" "$SET" >/dev/null 2>&1; }
trap restore EXIT

say "2c. RESUME3: missing VANILLA interior reference r_int2_van (variant B + all-off props + checklist)"
rm -rf "$OUT/frames_r_int2_van"
$ADB -s $SER push /tmp/glp5_settings_B.ini "$SET" >/dev/null
VANILLA=1 bash .autoport/glp_capture.sh r_int2_van 0 0 1 village1-hut "$INT2" 8 2>&1 | tail -12 | tee -a "$SUM"

say "3. restore owner settings + clear eval props"
restore
$ADB -s $SER shell "setprop debug.opengoal.renderscale.native ''; setprop debug.opengoal.ao.force_mode ''; setprop debug.opengoal.rt.detail ''; setprop debug.opengoal.rt.probe ''; setprop debug.opengoal.rt.light ''; setprop debug.opengoal.rt.ambient ''; setprop debug.opengoal.rt.probrefl ''" </dev/null 2>&1 | head -2

say "==================== METRICS ===================="
say "-- RICHNESS deck: vanilla(baked) vs detail-OFF(pre-reopen) vs detail-ON(shipped)"
python3 .autoport/glp2_measure.py richness "$OUT"/frames_r_deck_van "$OUT"/frames_r_deck_d0 "$OUT"/frames_r_deck_d1 2>&1 | tee -a "$SUM"
say "-- RICHNESS oracle interior: vanilla vs detail-ON"
python3 .autoport/glp2_measure.py richness "$OUT"/frames_r_int2_van "$OUT"/frames_r_int2_d1 2>&1 | tee -a "$SUM"
say "-- luma (energy / calibration: d1 vs d0 vs vanilla)"
python3 .autoport/glp2_measure.py luma "$OUT"/frames_r_deck_d1 "$OUT"/frames_r_deck_d0 "$OUT"/frames_r_deck_van "$OUT"/frames_r_int2_d1 "$OUT"/frames_r_int2_van 2>&1 | tee -a "$SUM"
say "-- AO BURN: GTAO ON vs OFF signed (must only darken, hue preserved)"
python3 .autoport/glp2_measure.py aodarken "$OUT"/frames_a_deck_gtao "$OUT"/frames_a_deck_aooff 2>&1 | tee -a "$SUM"
say "-- AO FLICKER: walk SSAO ON vs AO OFF (frame-to-frame delta)"
python3 .autoport/glp2_measure.py flicker "$OUT"/frames_w_ao1 "$OUT"/frames_w_ao0 2>&1 | tee -a "$SUM"
say "-- NIGHT moon shadow contrast (probes+detail ON)"
python3 .autoport/glp2_measure.py shadowcontrast "$OUT"/frames_r_night_d1 2>&1 | tee -a "$SUM"
say "-- ground FFT (no damier regression with the detail layer)"
python3 .autoport/glp2_measure.py gridfft "$OUT"/frames_r_deck_d1 "$OUT"/frames_r_deck_van 2>&1 | tee -a "$SUM"
for t in r_deck_d1 r_deck_van r_night_d1 r_int2_d1; do
  FR=$(ls "$OUT"/frames_$t/*.png 2>/dev/null | sed -n '15p'); [ -n "$FR" ] && cp "$FR" "$OUT/glp5_$t.png"
done
say "glp5 reopen battery DONE (resume3)"
