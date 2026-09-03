#!/usr/bin/env bash
# glp5_reopen.sh — REOPEN evidence set (owner verdict 2026-07-21 soir: realtime much flatter than
# baked; AO burns + still flickers). Captures on the baked-detail build, all TRUE native res:
#   R. richness: deck + oracle-interior, VANILLA (baked ref) vs detail-OFF (pre-reopen) vs
#      detail-ON (shipped) => DoG band local-contrast, acceptance realtime >= baked
#   A. AO burn: GTAO ON vs AO OFF statics => aodarken (only darkens, hue preserved)
#   F. AO flicker: native walk SSAO ON vs AO OFF => frame-to-frame delta
#   N. night moon-shadow still (probes+detail ON) => shadowcontrast
# Settings variants + restore mirror glp4_native.sh (owner file restored on EXIT).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb; S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-lightprobes/device; mkdir -p "$OUT"
SUM="$OUT/reopen_summary.txt"; : > "$SUM"
say(){ echo "== $*" | tee -a "$SUM"; }
SET=/storage/emulated/0/OpenGOAL/jak1/settings.ini
DECK="-112.0 42.0 205.0"
INT2="86.0 18.5 17.4"      # oracle chamber (oracle-1 NPC floor anchor)

say "0. backup owner settings.ini + variants (A = pbr+custom OFF; B = force-vanilla)"
$ADB -s $S pull "$SET" "$OUT/settings.ini.owner-backup" >/dev/null || { echo "[glp5 FAIL] settings pull"; exit 1; }
sed -e 's/^pbr-materials? = .*/pbr-materials? = #f/' \
    -e 's/^load-custom-assets? = .*/load-custom-assets? = #f/' \
    "$OUT/settings.ini.owner-backup" > /tmp/glp5_settings_A.ini
sed -e 's/^recharged-hud? = .*/recharged-hud? = #f/' \
    -e 's/^extra-hud? = .*/extra-hud? = #f/' \
    -e 's/^recharged-grass? = .*/recharged-grass? = #f/' \
    -e 's/^recharged-grass-overhang? = .*/recharged-grass-overhang? = #f/' \
    -e 's/^recharged-foliage-wind? = .*/recharged-foliage-wind? = #f/' \
    -e 's/^ambient-occlusion = .*/ambient-occlusion = 0/' \
    -e 's/^recharged-enhanced-models? = .*/recharged-enhanced-models? = #f/' \
    /tmp/glp5_settings_A.ini > /tmp/glp5_settings_B.ini
restore(){ $ADB -s $S push "$OUT/settings.ini.owner-backup" "$SET" >/dev/null 2>&1; }
trap restore EXIT

say "1. realtime captures (variant A; native; probes ON)"
$ADB -s $S push /tmp/glp5_settings_A.ini "$SET" >/dev/null
bash .autoport/glp_capture.sh r_deck_d1 1 0 1 village1-hut "$DECK" 8 2>&1 | tail -9 | tee -a "$SUM"
DETAIL=0 bash .autoport/glp_capture.sh r_deck_d0 1 0 1 village1-hut "$DECK" 8 2>&1 | tail -9 | tee -a "$SUM"
bash .autoport/glp_capture.sh r_int2_d1 1 0 1 village1-hut "$INT2" 8 2>&1 | tail -9 | tee -a "$SUM"
bash .autoport/glp_capture.sh r_night_d1 1 0 1 village1-hut "$DECK" 0 2>&1 | tail -9 | tee -a "$SUM"
AOM=3 bash .autoport/glp_capture.sh a_deck_gtao 1 0 1 village1-hut "$DECK" 8 2>&1 | tail -9 | tee -a "$SUM"
AOM=0 bash .autoport/glp_capture.sh a_deck_aooff 1 0 1 village1-hut "$DECK" 8 2>&1 | tail -9 | tee -a "$SUM"
bash .autoport/glp2_walk_capture.sh w_ao1 1 1 village1-hut "$DECK" 8 1 2>&1 | tail -8 | tee -a "$SUM"
bash .autoport/glp2_walk_capture.sh w_ao0 1 0 village1-hut "$DECK" 8 1 2>&1 | tail -8 | tee -a "$SUM"

say "2. VANILLA baked references (variant B + all-off props + logged checklist)"
$ADB -s $S push /tmp/glp5_settings_B.ini "$SET" >/dev/null
VANILLA=1 bash .autoport/glp_capture.sh r_deck_van 0 0 1 village1-hut "$DECK" 8 2>&1 | tail -12 | tee -a "$SUM"
VANILLA=1 bash .autoport/glp_capture.sh r_int2_van 0 0 1 village1-hut "$INT2" 8 2>&1 | tail -12 | tee -a "$SUM"

say "3. restore owner settings + clear eval props"
restore
$ADB -s $S shell "setprop debug.opengoal.renderscale.native ''; setprop debug.opengoal.ao.force_mode ''; setprop debug.opengoal.rt.detail ''" </dev/null

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
say "glp5 reopen battery DONE"
