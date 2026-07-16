#!/usr/bin/env bash
# ao_roundg_chain.sh — ROUND G (owner 2026-07-16 22:20, final tweak): HBAO/GTAO strength
# ladder shifted one notch DOWN (new Default == old Weaker, new Stronger == old Default,
# new Weaker = one proportional step below); SSAO strictly untouched.
# Chain: build+deploy -> strengthgrid on the NEW ladder -> caps/ordering analysis ->
# cross-build equivalence vs device/roundg-baseline (the archived round-F old-ladder
# grid) -> 90s worst-case spot-check -> owner reset.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
SDEV=eae4df44; PKG=org.opengoal.gk.jak1
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak_1/saves/settings/pc-settings.gc"
OUT=.autoport/reports/Grecharged-ambient-occlusion
say(){ echo; echo "######## $* ########"; }
die(){ echo "[roundg FAIL] $*"; exit 1; }
wait_charge(){
  while :; do
    L=$($ADB -s $SDEV shell dumpsys battery 2>/dev/null | grep -m1 'level:' | grep -oE '[0-9]+')
    [ -n "$L" ] && [ "$L" -ge 8 ] && { say "[charge-guard] level=$L%, proceeding"; return 0; }
    say "[charge-guard] level=${L:-?}% < 8%, pausing 5 min to charge"
    $ADB -s $SDEV shell am force-stop $PKG >/dev/null 2>&1
    sleep 300
  done
}

say "=== 0. baseline presence gate (round-F old-ladder grid archived?) ==="
ls "$OUT/device/roundg-baseline/device-ao-strengthgrid-hbao-weak_frames"/f_*.png >/dev/null 2>&1 \
  || die "no roundg-baseline archive"
ls "$OUT/device/roundg-baseline"/device-ao-strengthgrid-*.mp4 >/dev/null 2>&1 \
  || die "no baseline mp4 mtimes (off interpolation needs them)"

say "=== 1. full consistent build + deploy (fresh HEAD libgk on device) ==="
bash .autoport/ao_build_deploy.sh > "$OUT/build-deploy-roundg.log" 2>&1 \
  || { tail -30 "$OUT/build-deploy-roundg.log"; die "build/deploy failed"; }
grep -q "DONE — AO build on device" "$OUT/build-deploy-roundg.log" || die "build log lacks DONE marker"
tail -3 "$OUT/build-deploy-roundg.log"

say "=== 2. strengthgrid capture on the NEW ladder (3 modes x 3 strengths, per-trio boots) ==="
wait_charge
bash .autoport/ao_capture.sh strengthgrid 2>&1 | tee "$OUT/chain-roundg-grid.log"
grep -q "DONE strengthgrid" "$OUT/chain-roundg-grid.log" || die "strengthgrid capture did not finish"

say "=== 3. caps + ordering gates on the NEW ladder (defect-5 caps, weaker<default<stronger) ==="
python3 .autoport/ao_analyze_ab.py "$OUT/device" strengthgrid 2>&1 | tee "$OUT/chain-roundg-analyze.log" \
  || die "new-ladder caps/ordering FAIL"

say "=== 4. cross-build equivalence (new Default==old Weaker, new Stronger==old Default; SSAO rung-identical) ==="
python3 .autoport/ao_roundg_equiv.py "$OUT/device" 2>&1 | tee "$OUT/chain-roundg-equiv.log" \
  || die "ladder-shift equivalence FAIL"

say "=== 5. 90s worst-case spot-check (GTAO+High+Stronger persisted boot) ==="
wait_charge
bash .autoport/ao_title_spotcheck.sh 2>&1 | tee "$OUT/chain-roundg-spot.log" \
  || die "title spot-check FAIL"

say "=== 6. owner reset: AO Off, quality Medium, strength Default, grass + dynamic RS back ON, props clear, force-stop ==="
$ADB -s $SDEV shell am force-stop $PKG; sleep 1
for p in force_mode force_quality force_strength; do
  $ADB -s $SDEV shell "setprop debug.opengoal.ao.$p ''" >/dev/null 2>&1
done
$ADB -s $SDEV shell "setprop debug.opengoal.ao.debug 0" >/dev/null 2>&1
$ADB -s $SDEV shell cat "$SETTINGS_DEV" > /tmp/pcs_ao_roundg_reset.gc 2>/dev/null
sed -i "s/(ambient-occlusion [0-9]*)/(ambient-occlusion 0)/" /tmp/pcs_ao_roundg_reset.gc
sed -i "s/(ao-quality [0-9]*)/(ao-quality 1)/" /tmp/pcs_ao_roundg_reset.gc
sed -i "s/(ao-strength [0-9]*)/(ao-strength 1)/" /tmp/pcs_ao_roundg_reset.gc
grep -qa '(ao-strength' /tmp/pcs_ao_roundg_reset.gc || sed -i '/(ao-quality [0-9]*)/a\  (ao-strength 1)' /tmp/pcs_ao_roundg_reset.gc
sed -i "s/(recharged-grass? #f)/(recharged-grass? #t)/" /tmp/pcs_ao_roundg_reset.gc
sed -i "s/(dynamic-render-scale? #f)/(dynamic-render-scale? #t)/" /tmp/pcs_ao_roundg_reset.gc
$ADB -s $SDEV push /tmp/pcs_ao_roundg_reset.gc "$SETTINGS_DEV" >/dev/null 2>&1
echo "disk after reset: $($ADB -s $SDEV shell cat "$SETTINGS_DEV" 2>/dev/null | grep -aoE '\((ambient-occlusion [0-9]+|ao-quality [0-9]+|ao-strength [0-9]+|recharged-grass\? #[tf]|dynamic-render-scale\? #[tf])\)' | tr '\n' ' ')"
$ADB -s $SDEV shell am force-stop $PKG >/dev/null 2>&1

say "[roundg] DONE ALL — build+deploy, new-ladder grid caps/ordering, cross-build equivalence, spot-check, owner reset"
