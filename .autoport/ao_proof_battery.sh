#!/usr/bin/env bash
# ao_proof_battery.sh — Grecharged-ambient-occlusion post-gate device proof battery.
# Prereq: title gate PASSED on the deployed AO build. Runs, in order:
#   1. menu-proof2      — REAL menu chain end-to-end (commits push [recharged-ao] lines,
#                         persist to external settings + relaunch re-push)
#   2. vantage A/Bs     — village1 (crease/contact), beach (alpha-cut foliage risk beat),
#                         training (owner's test level) at matched pose via live props
#   3. ao_analyze_ab.py — per-vantage darkening/localization + mode-vs-mode distinctness
#   4. fpsmatrix        — 10-combo AOPERF cost curve
#   5. owner reset      — settings back to AO Off / quality Medium, force-stop
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=.autoport/reports/Grecharged-ambient-occlusion
LOGF="$OUT/proof-battery-log.txt"; : > "$LOGF"
say(){ echo "$*" | tee -a "$LOGF"; }
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak_1/saves/settings/pc-settings.gc"

say "=== 1. menu proof (corrected nav) ==="
bash .autoport/ao_menu_proof2.sh 2>&1 | tee -a "$LOGF"

say "=== 1b. safe-boot fallback proof ==="
bash .autoport/ao_safeboot_proof.sh 2>&1 | tee -a "$LOGF"

say "=== 2+3. vantage A/B captures + analysis ==="
for v in village1 beach training; do
  bash .autoport/ao_capture.sh "$v" 2>&1 | tee -a "$LOGF"
  python3 .autoport/ao_analyze_ab.py "$OUT/device" "$v" 2>&1 | tee -a "$LOGF"
done

say "=== 4. fps matrix (3 algos x 3 qualities + off) ==="
bash .autoport/ao_capture.sh fpsmatrix 2>&1 | tee -a "$LOGF"

say "=== 5. owner reset: AO Off, quality Medium, capture-protocol undo (grass + dynamic RS back ON), props clear, force-stop ==="
$ADB -s $S shell am force-stop $PKG; sleep 1
$ADB -s $S shell "setprop debug.opengoal.ao.force_mode ''" >/dev/null 2>&1
$ADB -s $S shell "setprop debug.opengoal.ao.force_quality ''" >/dev/null 2>&1
$ADB -s $S shell "setprop debug.opengoal.ao.debug 0" >/dev/null 2>&1
$ADB -s $S shell cat "$SETTINGS_DEV" > /tmp/pcs_ao_reset.gc 2>/dev/null
sed -i "s/(ambient-occlusion [0-9]*)/(ambient-occlusion 0)/" /tmp/pcs_ao_reset.gc
sed -i "s/(ao-quality [0-9]*)/(ao-quality 1)/" /tmp/pcs_ao_reset.gc
# capture protocol (owner 2026-07-15 13:50) was: lock full res + grass OFF for the runs,
# RESTORE after the phase's final state -> grass back ON (locked shipped feature),
# dynamic render scale back ON (owner's normal play state).
sed -i "s/(recharged-grass? #f)/(recharged-grass? #t)/" /tmp/pcs_ao_reset.gc
sed -i "s/(dynamic-render-scale? #f)/(dynamic-render-scale? #t)/" /tmp/pcs_ao_reset.gc
$ADB -s $S push /tmp/pcs_ao_reset.gc "$SETTINGS_DEV" >/dev/null 2>&1
say "disk after reset: $($ADB -s $S shell cat "$SETTINGS_DEV" 2>/dev/null | grep -aoE '\((ambient-occlusion [0-9]+|ao-quality [0-9]+|recharged-grass\? #[tf]|dynamic-render-scale\? #[tf])\)' | tr '\n' ' ')"
$ADB -s $S shell am force-stop $PKG >/dev/null 2>&1
say "[ao-proof-battery] DONE"
