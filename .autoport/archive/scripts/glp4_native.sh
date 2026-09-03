#!/usr/bin/env bash
# glp4_native.sh — post-render-scale-fix FULL re-capture of the supervisor-capped evidence set.
# Supervisor/owner mandates covered (2026-07-21 14:49 / 14:57 / 15:00):
#   * stale-TEST-PBR purge => every pre-purge capture untrusted => re-capture the whole capped set
#   * probe-gate captures run with pbr-materials? #f + load-custom-assets? #f (settings.ini variant
#     pushed for the run; the owner's file is restored at the end — trap EXIT)
#   * ALL captures at TRUE native res (debug.opengoal.renderscale.native now == the real window size)
#   * FBO-PROOF: the menu-persisted settings path itself (Dynamic-OFF + scale-100 in the SAME
#     settings.ini the menu writes; game-size left at the stale legacy 640x480 ON PURPOSE) with NO
#     debug prop must yield a native FBO in the heavy vantage — proves the update-to-os fix
#   * one VANILLA reference still with the logged all-off checklist (VANILLA=1)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb; S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-lightprobes/device; mkdir -p "$OUT"
SUM="$OUT/native_summary.txt"; : > "$SUM"
say(){ echo "== $*" | tee -a "$SUM"; }
SET=/storage/emulated/0/OpenGOAL/jak1/settings.ini
DECK="-112.0 42.0 205.0"
INT1="-133.0 40.0 207.0"   # Samos's hut (sage-23 NPC floor anchor)
INT2="86.0 18.5 17.4"      # oracle chamber (oracle-1 NPC floor anchor)

say "0. backup owner settings.ini + build variants"
$ADB -s $S pull "$SET" "$OUT/settings.ini.owner-backup" >/dev/null || { echo "[glp4 FAIL] settings pull"; exit 1; }
# variant A: probe-gate captures — ONLY custom assets + PBR materials forced off
sed -e 's/^pbr-materials? = .*/pbr-materials? = #f/' \
    -e 's/^load-custom-assets? = .*/load-custom-assets? = #f/' \
    "$OUT/settings.ini.owner-backup" > /tmp/glp4_settings_A.ini
# variant B: FORCE-VANILLA — every recharged persisted field off
sed -e 's/^recharged-hud? = .*/recharged-hud? = #f/' \
    -e 's/^extra-hud? = .*/extra-hud? = #f/' \
    -e 's/^recharged-grass? = .*/recharged-grass? = #f/' \
    -e 's/^recharged-grass-overhang? = .*/recharged-grass-overhang? = #f/' \
    -e 's/^recharged-foliage-wind? = .*/recharged-foliage-wind? = #f/' \
    -e 's/^ambient-occlusion = .*/ambient-occlusion = 0/' \
    -e 's/^recharged-enhanced-models? = .*/recharged-enhanced-models? = #f/' \
    /tmp/glp4_settings_A.ini > /tmp/glp4_settings_B.ini
# variant C: the FBO proof — variant A + Dynamic OFF + scale 100 (legacy game-size 640x480 KEPT)
sed -e 's/^dynamic-render-scale? = .*/dynamic-render-scale? = #f/' \
    -e 's/^render-scale = .*/render-scale = 100.0000/' \
    /tmp/glp4_settings_A.ini > /tmp/glp4_settings_C.ini
restore(){ $ADB -s $S push "$OUT/settings.ini.owner-backup" "$SET" >/dev/null 2>&1; }
trap restore EXIT

say "1. FBO-PROOF: menu-persisted Dynamic-OFF/scale-100, NO debug prop => native FBO at the deck"
$ADB -s $S push /tmp/glp4_settings_C.ini "$SET" >/dev/null
$ADB -s $S shell "setprop debug.opengoal.renderscale.native ''; setprop debug.opengoal.render.scale ''; setprop debug.opengoal.tod.hour 8; setprop debug.opengoal.level.warp village1-hut; setprop debug.opengoal.level.warp.pos '$DECK'; am force-stop $PKG" </dev/null
$ADB -s $S logcat -c </dev/null 2>/dev/null
$ADB -s $S shell am start -W -n $PKG/.LoaderActivity </dev/null >/dev/null 2>&1
ok=0
for i in $(seq 1 24); do
  sleep 5
  $ADB -s $S logcat -d 2>/dev/null | grep -aq 'LEVEL-WARP-SPAWN' && { ok=1; break; }
done
sleep 30
$ADB -s $S logcat -d -v threadtime 2>/dev/null | grep -aE 'A35-RENDER FBO setup|LEVEL-WARP-SPAWN' \
  | tail -8 | tee "$OUT/glp4_fbo_proof.log" | tee -a "$SUM"
$ADB -s $S shell am force-stop $PKG </dev/null
[ "$ok" = 1 ] || say "FBO-proof WARN: warp never spawned (check glp4_fbo_proof.log)"

say "2. probe-gate captures (variant A settings: pbr+custom OFF; native prop = true window size)"
$ADB -s $S push /tmp/glp4_settings_A.ini "$SET" >/dev/null
bash .autoport/glp_capture.sh n_int1_p1 1 0 1 village1-hut "$INT1" 8 2>&1 | tail -9 | tee -a "$SUM"
bash .autoport/glp_capture.sh n_int1_p0 0 0 1 village1-hut "$INT1" 8 2>&1 | tail -9 | tee -a "$SUM"
bash .autoport/glp_capture.sh n_int2_p1 1 0 1 village1-hut "$INT2" 8 2>&1 | tail -9 | tee -a "$SUM"
bash .autoport/glp_capture.sh n_int2_p0 0 0 1 village1-hut "$INT2" 8 2>&1 | tail -9 | tee -a "$SUM"
bash .autoport/glp_capture.sh n_ctr_on  1 0 1 village1-hut "$DECK" 8 2>&1 | tail -9 | tee -a "$SUM"
bash .autoport/glp_capture.sh n_ctr_off 0 0 1 village1-hut "$DECK" 8 2>&1 | tail -9 | tee -a "$SUM"
bash .autoport/glp_capture.sh n_night_on 1 0 1 village1-hut "$DECK" 0 2>&1 | tail -9 | tee -a "$SUM"
bash .autoport/glp2_walk_capture.sh n_walk_p1_ao1 1 1 village1-hut "$DECK" 8 1 2>&1 | tail -8 | tee -a "$SUM"
bash .autoport/glp2_walk_capture.sh n_walk_p0_ao1 0 1 village1-hut "$DECK" 8 1 2>&1 | tail -8 | tee -a "$SUM"

say "3. VANILLA reference still (variant B settings + all-off props + logged checklist)"
$ADB -s $S push /tmp/glp4_settings_B.ini "$SET" >/dev/null
VANILLA=1 bash .autoport/glp_capture.sh n_vanilla_ref 0 0 1 village1-hut "$DECK" 8 2>&1 | tail -12 | tee -a "$SUM"

say "4. restore owner settings.ini + clear eval props"
restore
$ADB -s $S shell "setprop debug.opengoal.renderscale.native ''" </dev/null

say "==================== METRICS ===================="
say "-- interiors: luma + RGB (matched NPC-anchored pairs)"
python3 .autoport/glp2_measure.py luma "$OUT"/frames_n_int1_p1 "$OUT"/frames_n_int1_p0 "$OUT"/frames_n_int2_p1 "$OUT"/frames_n_int2_p0 2>&1 | tee -a "$SUM"
say "-- interiors: contrast (detail preservation inside)"
python3 .autoport/glp2_measure.py contrast "$OUT"/frames_n_int1_p1 "$OUT"/frames_n_int1_p0 "$OUT"/frames_n_int2_p1 "$OUT"/frames_n_int2_p0 2>&1 | tee -a "$SUM"
say "-- deck pair: luma (energy / no blow-out) + contrast (preserved)"
python3 .autoport/glp2_measure.py luma "$OUT"/frames_n_ctr_on "$OUT"/frames_n_ctr_off 2>&1 | tee -a "$SUM"
python3 .autoport/glp2_measure.py contrast "$OUT"/frames_n_ctr_on "$OUT"/frames_n_ctr_off 2>&1 | tee -a "$SUM"
say "-- ground checkerboard FFT (probes ON still + OFF baseline)"
python3 .autoport/glp2_measure.py gridfft "$OUT"/frames_n_ctr_on "$OUT"/frames_n_ctr_off 2>&1 | tee -a "$SUM"
say "-- night green-sun shadow contrast (probes ON; low ratio = shadow clearly visible)"
python3 .autoport/glp2_measure.py shadowcontrast "$OUT"/frames_n_night_on 2>&1 | tee -a "$SUM"
say "-- AO temporal stability on movement (probes ON vs OFF, native walks)"
python3 .autoport/glp2_measure.py flicker "$OUT"/frames_n_walk_p1_ao1 "$OUT"/frames_n_walk_p0_ao1 2>&1 | tee -a "$SUM"
say "-- vanilla reference luma (stock anchor)"
python3 .autoport/glp2_measure.py luma "$OUT"/frames_n_vanilla_ref 2>&1 | tee -a "$SUM"
CFR=$(ls "$OUT"/frames_n_ctr_on/*.png 2>/dev/null | sed -n '15p'); [ -n "$CFR" ] && cp "$CFR" "$OUT/glp4_deck_on.png"
NFR=$(ls "$OUT"/frames_n_night_on/*.png 2>/dev/null | sed -n '15p'); [ -n "$NFR" ] && cp "$NFR" "$OUT/glp4_night_on.png"
IFR=$(ls "$OUT"/frames_n_int2_p1/*.png 2>/dev/null | sed -n '15p'); [ -n "$IFR" ] && cp "$IFR" "$OUT/glp4_int2_on.png"
VFR=$(ls "$OUT"/frames_n_vanilla_ref/*.png 2>/dev/null | sed -n '15p'); [ -n "$VFR" ] && cp "$VFR" "$OUT/glp4_vanilla_ref.png"
say "glp4 native battery DONE"
