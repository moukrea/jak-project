#!/usr/bin/env bash
# glp6_shadefix.sh — attempt-7 SHADE-ADAPTIVE ind_k fix: rebuild (shader-only => gk + APK; the
# GOAL/CGO/TXT/probes side is byte-unchanged from the verified 4812b51b1 deploy), redeploy, then
# SEQUENTIALLY re-capture only the stages the composite change affects (r_deck_d1, r_int2_d1,
# r_night_d1) and re-run the §14 metrics. d0 (rt.detail=0) and the vanilla/AO pairs are
# path-identical under this change and stay valid.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb; S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
OUT=.autoport/reports/Grecharged-lightprobes/device
SUM="$OUT/reopen_summary.txt"
say(){ echo; echo "######## $* ########" | tee -a "$SUM"; }
die(){ echo "[glp6 FAIL] $*" >&2; exit 1; }

say "0. adb refresh + temp guard"
"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
$ADB -s $S wait-for-device
T=$($ADB -s $S shell dumpsys battery | grep temperature | grep -o '[0-9]*')
echo "  battery temp=${T:-?} (guard >=450)"; [ "${T:-0}" -lt 450 ] || die "device too hot"

say "1. rebuild libgk (shader blob regen) + freshness proof"
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -8
[ -f build-android/lib/arm64-v8a/libgk.so ] || die "libgk.so not built"
SE=$(strings -a build-android/lib/arm64-v8a/libgk.so | grep -c 'shade_est')
echo "  libgk shade_est occurrences=$SE (expect >=4, one per world shader)"
[ "$SE" -ge 4 ] || die "shade_est not in libgk — blob not regenerated"

say "2. assemble + install APK + deploy_verify"
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -5 ) || die "gradle assemble failed"
$ADB -s $S shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell settings put global verifier_verify_adb_installs 0 >/dev/null 2>&1 || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -2 || die "apk install failed"
bash .autoport/lib/deploy_verify.sh "$S" jak1 2>&1 | tail -4 || die "deploy_verify failed"

say "3. boot check (shader compile + render frames + focus)"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true
$ADB -s $S logcat -c >/dev/null 2>&1 || true
LOG="$OUT/glp6-boot-logcat.log"; : > "$LOG"
( $ADB -s $S logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
   | grep --line-buffered -aE 'A35-RENDER frame=|shader|Shader|lightprobe|Fatal signal|GK-DIAG sig=' >> "$LOG" ) 2>/dev/null &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true' EXIT
$ADB -s $S shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); ok=0
while [ $(( $(date +%s) - t0 )) -lt 240 ]; do
  grep -aqE 'GK-DIAG sig=11|Fatal signal (11|6|4)' "$LOG" 2>/dev/null && { echo "  CRASH during boot"; break; }
  rf=$(grep -acE 'A35-RENDER frame=' "$LOG" 2>/dev/null); rf=${rf:-0}
  [ "$rf" -ge 5 ] 2>/dev/null && { ok=1; break; }
  sleep 3
done
grep -aiE 'shader.*(error|fail|missing)' "$LOG" && die "shader compile problem in logcat"
FOCUS=$($ADB -s $S shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r')
echo "  reached_render=$ok focus=$FOCUS" | tee -a "$SUM"
case "$FOCUS" in *org.opengoal.gk.jak1*) : ;; *) die "app not foreground: $FOCUS" ;; esac
[ "$ok" = 1 ] || die "did not reach render"
kill ${LCP:-0} 2>/dev/null || true
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1 || true

say "4. SEQUENTIAL re-captures on the shade-fix build (variant A settings; native res)"
SET=/storage/emulated/0/OpenGOAL/jak1/settings.ini
DECK="-112.0 42.0 205.0"; INT2="86.0 18.5 17.4"
[ -f "$OUT/settings.ini.owner-backup" ] || die "owner settings backup missing"
[ -f /tmp/glp5_settings_A.ini ] || die "/tmp/glp5_settings_A.ini missing (regen from backup first)"
restore(){ $ADB -s $S push "$OUT/settings.ini.owner-backup" "$SET" >/dev/null 2>&1; }
trap 'restore; kill ${LCP:-0} 2>/dev/null || true' EXIT
$ADB -s $S push /tmp/glp5_settings_A.ini "$SET" >/dev/null
rm -rf "$OUT/frames_r_deck_d1" "$OUT/frames_r_int2_d1" "$OUT/frames_r_night_d1"
bash .autoport/glp_capture.sh r_deck_d1 1 0 1 village1-hut "$DECK" 8 2>&1 | tail -9 | tee -a "$SUM"
bash .autoport/glp_capture.sh r_int2_d1 1 0 1 village1-hut "$INT2" 8 2>&1 | tail -9 | tee -a "$SUM"
bash .autoport/glp_capture.sh r_night_d1 1 0 1 village1-hut "$DECK" 0 2>&1 | tail -9 | tee -a "$SUM"

say "5. restore owner settings + clear eval props"
restore
$ADB -s $S shell "setprop debug.opengoal.renderscale.native ''; setprop debug.opengoal.ao.force_mode ''; setprop debug.opengoal.rt.detail ''; setprop debug.opengoal.rt.probe ''; setprop debug.opengoal.rt.light ''; setprop debug.opengoal.rt.ambient ''; setprop debug.opengoal.rt.probrefl ''" </dev/null 2>&1 | head -2

say "==================== METRICS (shade-fix build) ===================="
say "-- RICHNESS deck: vanilla(baked) vs detail-OFF(pre-reopen) vs detail-ON(shade-fix)"
python3 .autoport/glp2_measure.py richness "$OUT"/frames_r_deck_van "$OUT"/frames_r_deck_d0 "$OUT"/frames_r_deck_d1 2>&1 | tee -a "$SUM"
say "-- RICHNESS oracle interior: vanilla vs detail-ON"
python3 .autoport/glp2_measure.py richness "$OUT"/frames_r_int2_van "$OUT"/frames_r_int2_d1 2>&1 | tee -a "$SUM"
say "-- luma (energy / calibration: d1 vs d0 vs vanilla)"
python3 .autoport/glp2_measure.py luma "$OUT"/frames_r_deck_d1 "$OUT"/frames_r_deck_d0 "$OUT"/frames_r_deck_van "$OUT"/frames_r_int2_d1 "$OUT"/frames_r_int2_van 2>&1 | tee -a "$SUM"
say "-- NIGHT moon shadow contrast (probes+detail ON)"
python3 .autoport/glp2_measure.py shadowcontrast "$OUT"/frames_r_night_d1 2>&1 | tee -a "$SUM"
say "-- ground FFT (no damier regression with the shade-adaptive detail layer)"
python3 .autoport/glp2_measure.py gridfft "$OUT"/frames_r_deck_d1 "$OUT"/frames_r_deck_van 2>&1 | tee -a "$SUM"
for t in r_deck_d1 r_night_d1 r_int2_d1; do
  FR=$(ls "$OUT"/frames_$t/*.png 2>/dev/null | sed -n '15p'); [ -n "$FR" ] && cp "$FR" "$OUT/glp5_$t.png"
done
say "glp6 shade-fix battery DONE"
