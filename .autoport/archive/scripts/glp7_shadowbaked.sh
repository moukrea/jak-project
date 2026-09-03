#!/usr/bin/env bash
# glp7_shadowbaked.sh — REOPEN #3 (owner: sun dead + AO invisible): SHADOW-THE-BAKED composite
# (ind_k = mix(ambient_estimate, full_baked, dynamic sun visibility) + modest 0.25 sun boost) and
# the AO soft-knee VISIBLE-MIDDLE mask. Rebuild (shader+LightProbeGrid only => gk + APK; the
# GOAL/CGO/TXT/probes side is byte-unchanged from the verified deploy), redeploy, then STRICTLY
# SEQUENTIAL captures for the reopen gates. Reused as-is (path-identical under this change):
# frames_r_deck_van / frames_r_int2_van (vanilla: whole rt branch off) and frames_r_deck_d0
# (u_rt_detail==0 else-branch == pre-reopen composite exactly).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb; SERIAL=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-lightprobes/device
SUM="$OUT/reopen3_summary.txt"; : > "$SUM"
say(){ echo; echo "######## $* ########" | tee -a "$SUM"; }
die(){ echo "[glp7 FAIL] $*" >&2; exit 1; }

say "0. adb refresh + temp guard + no-overlap check"
pgrep -f 'glp_capture\.sh|glp2_walk_capture\.sh|shell screenrecord' >/dev/null 2>&1 && die "a leftover capture runner is alive — strictly sequential rule (kill it first)"
"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
$ADB -s $SERIAL wait-for-device
T=$($ADB -s $SERIAL shell dumpsys battery | grep temperature | grep -o '[0-9]*')
echo "  battery temp=${T:-?} (guard >=450)" | tee -a "$SUM"; [ "${T:-0}" -lt 450 ] || die "device too hot"

say "1. rebuild libgk (shader blob regen) + freshness proof"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -4
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
LB=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'lit_bake')
SE=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'shade_est = max')
echo "  libgk lit_bake=$LB (expect >=4) stale-attempt8-shade_est=$SE (expect 0)" | tee -a "$SUM"
[ "$LB" -ge 4 ] || die "lit_bake not in libgk — blob not regenerated"
[ "$SE" -eq 0 ] || die "stale attempt-8 shade_est still in libgk"

say "2. assemble + install APK + deploy_verify"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -3 ) || die "gradle assemble failed"
$ADB -s $SERIAL shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB -s $SERIAL shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $SERIAL shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
$ADB -s $SERIAL install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -2 || die "apk install failed"
bash .autoport/lib/deploy_verify.sh "$SERIAL" jak1 2>&1 | tail -4 | tee -a "$SUM" || die "deploy_verify failed"

say "3. boot check (shader compile + render frames + focus)"
$ADB -s $SERIAL shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $SERIAL logcat -c >/dev/null 2>&1 || true
LOG="$OUT/glp7-boot-logcat.log"; : > "$LOG"
( $ADB -s $SERIAL logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aE 'A35-RENDER frame=|shader|Shader|lightprobe|Fatal signal|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true' EXIT
$ADB -s $SERIAL shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); ok=0
while [ $(( $(date +%s) - t0 )) -lt 240 ]; do
  grep -aqE 'GK-DIAG sig=11|Fatal signal (11|6|4)' "$LOG" 2>/dev/null && { echo "  CRASH during boot"; break; }
  rf=$(grep -acE 'A35-RENDER frame=' "$LOG" 2>/dev/null); rf=${rf:-0}
  [ "$rf" -ge 5 ] 2>/dev/null && { ok=1; break; }
  sleep 3
done
grep -aiE 'shader.*(error|fail|missing)' "$LOG" && die "shader compile problem in logcat"
FOCUS=$($ADB -s $SERIAL shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  reached_render=$ok focus=$FOCUS" | tee -a "$SUM"
case "$FOCUS" in *org.opengoal.gk.jak1*) : ;; *) die "app not foreground: $FOCUS" ;; esac
[ "$ok" = 1 ] || die "did not reach render"
kill ${LCP:-0} 2>/dev/null || true
$ADB -s $SERIAL shell am force-stop $PKG >/dev/null 2>&1 || true

say "4. STRICTLY SEQUENTIAL captures (variant A settings; native res)"
SET=/storage/emulated/0/OpenGOAL/jak1/settings.ini
DECK="-112.0 42.0 205.0"
[ -f "$OUT/settings.ini.owner-backup" ] || die "owner settings backup missing"
[ -f /tmp/glp5_settings_A.ini ] || sed -e 's/^pbr-materials? = .*/pbr-materials? = #f/' \
    -e 's/^load-custom-assets? = .*/load-custom-assets? = #f/' \
    "$OUT/settings.ini.owner-backup" > /tmp/glp5_settings_A.ini
restore(){ $ADB -s $SERIAL push "$OUT/settings.ini.owner-backup" "$SET" >/dev/null 2>&1; }
trap 'restore; kill ${LCP:-0} 2>/dev/null || true' EXIT
$ADB -s $SERIAL push /tmp/glp5_settings_A.ini "$SET" >/dev/null
rm -rf "$OUT"/frames_r7_*
bash .autoport/glp_capture.sh r7_deck 1 0 1 village1-hut "$DECK" 8 2>&1 | tail -8 | tee -a "$SUM"
bash .autoport/glp_capture.sh r7_deck_h11 1 0 1 village1-hut "$DECK" 11 2>&1 | tail -8 | tee -a "$SUM"
bash .autoport/glp_capture.sh r7_night 1 0 1 village1-hut "$DECK" 0 2>&1 | tail -8 | tee -a "$SUM"
AOM=3 bash .autoport/glp_capture.sh r7_ao_gtao 1 0 1 village1-hut "$DECK" 8 2>&1 | tail -8 | tee -a "$SUM"
AOM=0 bash .autoport/glp_capture.sh r7_ao_off 1 0 1 village1-hut "$DECK" 8 2>&1 | tail -8 | tee -a "$SUM"
bash .autoport/glp2_walk_capture.sh r7_w_ao1 1 1 village1-hut "$DECK" 8 1 2>&1 | tail -8 | tee -a "$SUM"
bash .autoport/glp2_walk_capture.sh r7_w_ao0 1 0 village1-hut "$DECK" 8 1 2>&1 | tail -8 | tee -a "$SUM"

say "5. restore owner settings + clear eval props"
restore
$ADB -s $SERIAL shell "setprop debug.opengoal.renderscale.native ''; setprop debug.opengoal.ao.force_mode ''; setprop debug.opengoal.rt.detail ''; setprop debug.opengoal.rt.probe ''; setprop debug.opengoal.rt.light ''; setprop debug.opengoal.rt.ambient ''; setprop debug.opengoal.rt.probrefl ''; setprop debug.opengoal.rt.sunboost ''; setprop debug.opengoal.tod.hour ''" </dev/null 2>&1 | head -2

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
say "glp7 shadow-the-baked battery DONE"
