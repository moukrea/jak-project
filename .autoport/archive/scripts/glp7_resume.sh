#!/usr/bin/env bash
# glp7_resume.sh — resume the glp7 shadow-the-baked battery after the attempt-7 session died
# mid-stage-4. The build is already DEPLOY-VERIFY PASSED (reopen3_summary.txt) and the orphaned
# r7_deck capture completed its artifacts; this runs the REMAINING captures strictly sequentially
# (variant A settings are already on the device — the dead parent's restore trap never fired),
# then the metrics, then restores the owner settings.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb; SERIAL=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-lightprobes/device
SUM="$OUT/reopen3_summary.txt"
say(){ echo; echo "######## $* ########" | tee -a "$SUM"; }
die(){ echo "[glp7r FAIL] $*" >&2; exit 1; }

say "4r. resume guard (no overlapping runner) + temp"
pgrep -f 'glp_capture\.sh|glp2_walk_capture\.sh' | grep -v $$ >/dev/null 2>&1 && die "another capture runner is alive — strictly sequential rule"
$ADB -s $SERIAL wait-for-device
T=$($ADB -s $SERIAL shell dumpsys battery | grep temperature | grep -o '[0-9]*')
echo "  battery temp=${T:-?} (guard >=450)" | tee -a "$SUM"; [ "${T:-0}" -lt 450 ] || die "device too hot"
NF=$(ls "$OUT/frames_r7_deck"/*.png 2>/dev/null | wc -l)
echo "  orphan r7_deck frames=$NF (need >=10)" | tee -a "$SUM"; [ "$NF" -ge 10 ] || die "r7_deck capture incomplete — rerun it first"

SET=/storage/emulated/0/OpenGOAL/jak1/settings.ini
DECK="-112.0 42.0 205.0"
[ -f "$OUT/settings.ini.owner-backup" ] || die "owner settings backup missing"
restore(){ $ADB -s $SERIAL push "$OUT/settings.ini.owner-backup" "$SET" >/dev/null 2>&1; }
trap 'restore' EXIT
# variant A settings (pbr/custom-assets OFF) were pushed by the dead parent; re-push to be sure
[ -f /tmp/glp5_settings_A.ini ] || sed -e 's/^pbr-materials? = .*/pbr-materials? = #f/' \
    -e 's/^load-custom-assets? = .*/load-custom-assets? = #f/' \
    "$OUT/settings.ini.owner-backup" > /tmp/glp5_settings_A.ini
$ADB -s $SERIAL push /tmp/glp5_settings_A.ini "$SET" >/dev/null

say "4r. remaining STRICTLY SEQUENTIAL captures (variant A settings; native res)"
bash .autoport/glp_capture.sh r7_deck_h11 1 0 1 village1-hut "$DECK" 11 2>&1 | tail -8 | tee -a "$SUM"
bash .autoport/glp_capture.sh r7_night 1 0 1 village1-hut "$DECK" 0 2>&1 | tail -8 | tee -a "$SUM"
AOM=3 bash .autoport/glp_capture.sh r7_ao_gtao 1 0 1 village1-hut "$DECK" 8 2>&1 | tail -8 | tee -a "$SUM"
AOM=0 bash .autoport/glp_capture.sh r7_ao_off 1 0 1 village1-hut "$DECK" 8 2>&1 | tail -8 | tee -a "$SUM"
bash .autoport/glp2_walk_capture.sh r7_w_ao1 1 1 village1-hut "$DECK" 8 1 2>&1 | tail -8 | tee -a "$SUM"
bash .autoport/glp2_walk_capture.sh r7_w_ao0 1 0 village1-hut "$DECK" 8 1 2>&1 | tail -8 | tee -a "$SUM"

say "5. restore owner settings + clear eval props"
restore
$ADB -s $SERIAL shell "setprop debug.opengoal.renderscale.native ''; setprop debug.opengoal.ao.force_mode ''; setprop debug.opengoal.rt.detail ''; setprop debug.opengoal.rt.probe ''; setprop debug.opengoal.rt.light ''; setprop debug.opengoal.rt.ambient ''; setprop debug.opengoal.rt.probrefl ''; setprop debug.opengoal.rt.sunboost ''; setprop debug.opengoal.tod.hour ''" </dev/null 2>&1 | head -2
$ADB -s $SERIAL shell am force-stop $PKG </dev/null 2>&1 || true

say "==================== METRICS (shadow-the-baked build) ===================="
say "-- SHADOW OBVIOUS: ground shadow/lit ratio — r7 (dyn shadows) vs vanilla (none) vs d0"
python3 .autoport/glp2_measure.py shadowcontrast "$OUT"/frames_r7_deck "$OUT"/frames_r7_deck_h11 "$OUT"/frames_r_deck_van "$OUT"/frames_r_deck_d0 2>&1 | tee -a "$SUM"
say "-- SHADOW MOVES with TOD: per-pixel diff hour 8 vs hour 11 (same vantage, static)"
python3 .autoport/glp2_measure.py pairdiff "$OUT"/frames_r7_deck "$OUT"/frames_r7_deck_h11 2>&1 | tee -a "$SUM"
say "-- NIGHT green-sun/moon shadow contrast (probes+detail ON)"
python3 .autoport/glp2_measure.py shadowcontrast "$OUT"/frames_r7_night 2>&1 | tee -a "$SUM"
say "-- RICHNESS deck: vanilla(baked) vs d0(pre-reopen) vs r7(shadow-the-baked)"
python3 .autoport/glp2_measure.py richness "$OUT"/frames_r_deck_van "$OUT"/frames_r_deck_d0 "$OUT"/frames_r7_deck 2>&1 | tee -a "$SUM"
say "-- LUMA / energy (no blow-out: r7 vs d0 vs vanilla)"
python3 .autoport/glp2_measure.py luma "$OUT"/frames_r7_deck "$OUT"/frames_r_deck_d0 "$OUT"/frames_r_deck_van 2>&1 | tee -a "$SUM"
say "-- ground FFT (no damier regression)"
python3 .autoport/glp2_measure.py gridfft "$OUT"/frames_r7_deck "$OUT"/frames_r_deck_van 2>&1 | tee -a "$SUM"
say "-- AO VISIBLE MIDDLE: GTAO ON vs OFF (signed darkening, hue-preserving, no burn)"
python3 .autoport/glp2_measure.py aodarken "$OUT"/frames_r7_ao_gtao "$OUT"/frames_r7_ao_off 2>&1 | tee -a "$SUM"
say "-- AO FLICKER on movement: frame-to-frame delta, SSAO ON vs AO OFF walks"
python3 .autoport/glp2_measure.py flicker "$OUT"/frames_r7_w_ao1 "$OUT"/frames_r7_w_ao0 2>&1 | tee -a "$SUM"
for t in r7_deck r7_deck_h11 r7_night r7_ao_gtao; do
  FR=$(ls "$OUT"/frames_$t/*.png 2>/dev/null | sed -n '15p'); [ -n "$FR" ] && cp "$FR" "$OUT/glp7_$t.png"
done
say "glp7 resume battery DONE"
