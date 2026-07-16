#!/usr/bin/env bash
# ao_postclamp_chain.sh — device verification of the GTAO broad-saturation build:
#   1. worst-case title spot check (GTAO+High+Stronger = the exact changed path)
#   2. strengthgrid re-run (the gate the clamp exists to satisfy)
#   3. owner reset (AO Off/quality Medium/strength Default, grass + dynamic RS back ON)
# Appends stages 2-3 to proof-battery-log.txt; stage 1 writes its own spotcheck log.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-ambient-occlusion
LOGF="$OUT/proof-battery-log.txt"
say(){ echo "$*" | tee -a "$LOGF"; }
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak_1/saves/settings/pc-settings.gc"

wait_charge(){
  while :; do
    L=$($ADB -s $S shell dumpsys battery 2>/dev/null | grep -m1 'level:' | grep -oE '[0-9]+')
    [ -n "$L" ] && [ "$L" -ge 8 ] && { say "[charge-guard] level=$L%, proceeding"; return 0; }
    say "[charge-guard] level=${L:-?}% < 8%, pausing 5 min to charge (screen stays on)"
    $ADB -s $S shell am force-stop $PKG >/dev/null 2>&1
    sleep 300
  done
}

echo "=== POSTCLAMP stage 1: worst-case title spot check on the saturation build ==="
wait_charge
bash .autoport/ao_title_spotcheck.sh 2>&1 | tee "$OUT/title-gate/spotcheck-log.txt"
grep -q '\[TITLE-SPOTCHECK PASS\]' "$OUT/title-gate/spotcheck-log.txt" || {
  echo "[postclamp] SPOTCHECK FAIL — aborting before the grid"; exit 1; }

say "=== POSTCLAMP stage 2 $(date '+%H:%M:%S'): strengthgrid on the GTAO-broad-saturation build ==="
wait_charge
bash .autoport/ao_capture.sh strengthgrid 2>&1 | tee -a "$LOGF"
python3 .autoport/ao_analyze_ab.py "$OUT/device" strengthgrid 2>&1 | tee -a "$LOGF"

say "=== POSTCLAMP stage 3: owner reset (AO Off, quality Medium, grass + dynamic RS back ON) ==="
$ADB -s $S shell am force-stop $PKG; sleep 1
$ADB -s $S shell "setprop debug.opengoal.ao.force_mode ''" >/dev/null 2>&1
$ADB -s $S shell "setprop debug.opengoal.ao.force_quality ''" >/dev/null 2>&1
$ADB -s $S shell "setprop debug.opengoal.ao.force_strength ''" >/dev/null 2>&1
$ADB -s $S shell "setprop debug.opengoal.ao.debug 0" >/dev/null 2>&1
$ADB -s $S shell cat "$SETTINGS_DEV" > /tmp/pcs_ao_reset.gc 2>/dev/null
sed -i "s/(ambient-occlusion [0-9]*)/(ambient-occlusion 0)/" /tmp/pcs_ao_reset.gc
sed -i "s/(ao-quality [0-9]*)/(ao-quality 1)/" /tmp/pcs_ao_reset.gc
sed -i "s/(ao-strength [0-9]*)/(ao-strength 1)/" /tmp/pcs_ao_reset.gc
grep -qa '(ao-strength' /tmp/pcs_ao_reset.gc || sed -i '/(ao-quality [0-9]*)/a\  (ao-strength 1)' /tmp/pcs_ao_reset.gc
sed -i "s/(recharged-grass? #f)/(recharged-grass? #t)/" /tmp/pcs_ao_reset.gc
sed -i "s/(dynamic-render-scale? #f)/(dynamic-render-scale? #t)/" /tmp/pcs_ao_reset.gc
sed -i "s/(render-scale [0-9.]*)/(render-scale 100.0000)/" /tmp/pcs_ao_reset.gc
$ADB -s $S push /tmp/pcs_ao_reset.gc "$SETTINGS_DEV" >/dev/null 2>&1
say "disk after reset: $($ADB -s $S shell cat "$SETTINGS_DEV" 2>/dev/null | grep -aoE '\((ambient-occlusion [0-9]+|ao-quality [0-9]+|ao-strength [0-9]+|recharged-grass\? #[tf]|dynamic-render-scale\? #[tf])\)' | tr '\n' ' ')"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1
say "[postclamp chain] DONE"
