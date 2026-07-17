#!/usr/bin/env bash
# ao_battery_resume_roundf.sh — resume the 2026-07-16 17:49 proof battery that was cut
# mid-village1 when the session ended (device found at 1% battery, game foregrounded).
# Stages 1 (menu-proof2) + 1b (safeboot) already PASSed ON THIS round-F build/deploy
# (standalone logs 17:59/18:01, build-deploy-roundf 17:41, spot-check 17:53) and their
# output is preserved in proof-battery-log.txt (the full battery truncates only at
# start) — so this APPENDS the remaining stages instead of re-running ~15 min of
# already-proven device work on a weak 500 mA charger.
# Stage order is fail-fast: the two ROUND-F gates (bandcheck, training depth A/B)
# run before the regression re-checks.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-ambient-occlusion
LOGF="$OUT/proof-battery-log.txt"   # APPEND — do not truncate (stages 1/1b live here)
say(){ echo "$*" | tee -a "$LOGF"; }
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak1/settings.ini"

# Weak-charger guard: never start a stage under 8% — force-stop the game and wait.
# NEVER sleep the screen here: the Redmi PIN-locks on sleep (deviceLocked=1) and there
# is deliberately no headless unlock — a screen-off = a stalled phase until the owner
# unlocks. stay_on_while_plugged_in=7 keeps the lit screen awake on AC.
wait_charge(){
  while :; do
    L=$($ADB -s $S shell dumpsys battery 2>/dev/null | grep -m1 'level:' | grep -oE '[0-9]+')
    [ -n "$L" ] && [ "$L" -ge 8 ] && { say "[charge-guard] level=$L%, proceeding"; return 0; }
    say "[charge-guard] level=${L:-?}% < 8%, pausing 5 min to charge (screen stays on)"
    $ADB -s $S shell am force-stop $PKG >/dev/null 2>&1
    sleep 300
  done
}

say "=== RESUME $(date '+%H:%M:%S') — stages 1/1b stand from the 17:49 run (menu-proof2 17:59 PASS, safeboot 18:01 PASS, this build); resuming cut stages, round-F gates first ==="

say "=== 3c. round F: SSAO Low/Med banding gate (debug-view band metric) ==="
wait_charge
bash .autoport/ao_capture.sh bandcheck 2>&1 | tee -a "$LOGF"

say "=== 2+3. vantage A/B captures + analysis (training first: round-F depth A/B) ==="
for v in training village1 beach shoreline; do
  wait_charge
  bash .autoport/ao_capture.sh "$v" 2>&1 | tee -a "$LOGF"
  python3 .autoport/ao_analyze_ab.py "$OUT/device" "$v" 2>&1 | tee -a "$LOGF"
done

say "=== 3b. strength grid (3 modes x 3 strengths @ training) ==="
wait_charge
bash .autoport/ao_capture.sh strengthgrid 2>&1 | tee -a "$LOGF"
python3 .autoport/ao_analyze_ab.py "$OUT/device" strengthgrid 2>&1 | tee -a "$LOGF"

say "=== 4. fps matrix (3 algos x 3 qualities + off) ==="
wait_charge
bash .autoport/ao_capture.sh fpsmatrix 2>&1 | tee -a "$LOGF"

say "=== 5. owner reset: AO Off, quality Medium, capture-protocol undo (grass + dynamic RS back ON), props clear, force-stop ==="
$ADB -s $S shell am force-stop $PKG; sleep 1
$ADB -s $S shell "setprop debug.opengoal.ao.force_mode ''" >/dev/null 2>&1
$ADB -s $S shell "setprop debug.opengoal.ao.force_quality ''" >/dev/null 2>&1
$ADB -s $S shell "setprop debug.opengoal.ao.force_strength ''" >/dev/null 2>&1
$ADB -s $S shell "setprop debug.opengoal.ao.debug 0" >/dev/null 2>&1
$ADB -s $S shell cat "$SETTINGS_DEV" > /tmp/pcs_ao_reset.gc 2>/dev/null
sed -i "s/^ambient-occlusion = [0-9]*/ambient-occlusion = 0/" /tmp/pcs_ao_reset.gc
sed -i "s/^ao-quality = [0-9]*/ao-quality = 1/" /tmp/pcs_ao_reset.gc
sed -i "s/^ao-strength = [0-9]*/ao-strength = 1/" /tmp/pcs_ao_reset.gc
grep -qa '^ao-strength = ' /tmp/pcs_ao_reset.gc || sed -i '/^ao-quality = [0-9]*/a\ao-strength = 1' /tmp/pcs_ao_reset.gc
sed -i "s/^recharged-grass? = #f/recharged-grass? = #t/" /tmp/pcs_ao_reset.gc
sed -i "s/^dynamic-render-scale? = #f/dynamic-render-scale? = #t/" /tmp/pcs_ao_reset.gc
$ADB -s $S push /tmp/pcs_ao_reset.gc "$SETTINGS_DEV" >/dev/null 2>&1
say "disk after reset: $($ADB -s $S shell cat "$SETTINGS_DEV" 2>/dev/null | grep -aoE '^(ambient-occlusion = [0-9]+|ao-quality = [0-9]+|ao-strength = [0-9]+|recharged-grass\? = #[tf]|dynamic-render-scale\? = #[tf])' | tr '\n' ' ')"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1
# Leave the screen state alone: stay-on-while-plugged is the owner's own setting and
# sleeping the screen would PIN-lock the device (no headless unlock).
say "[ao-proof-battery] DONE"
