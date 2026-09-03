#!/usr/bin/env bash
# foliage_wind3_off_leg.sh — re-run ONLY the toggle-OFF beach leg, with a dwell long enough for a
# shear-audit window to CLOSE.
#
# Why this exists: the audit prints one line per 300 render_tree_wind frames. The shared device
# script's OFF leg dwells ~27 s, and this device renders at ~15 fps (the shipped build reports
# rate_ticks=4, i.e. 60/15), so the OFF leg reached only ~270 wind frames after boot and NO window
# closed — the run produced ON windows and no OFF reference. That is a dwell-time shortfall in the
# harness, not a defect in the build: the same binary closes windows fine on the ON leg, which runs
# longer. Nothing here changes what is measured; it only waits long enough to measure it.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='/storage/emulated/0/OpenGOAL/jak1/settings.ini'
DEV=.autoport/reports/Grecharged-foliage-wind2/device; mkdir -p "$DEV"
LOG="$DEV/beach-OFF.log"
BEACH_POS="-123.3 2.3 -54.6"
focus(){ $ADB shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

echo "######## toggle OFF ########"
$ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
$ADB shell cat "$PCS" > /tmp/fw3_pcs.ini 2>/dev/null || true
grep -q 'recharged-foliage-wind?' /tmp/fw3_pcs.ini || { echo "FATAL: no toggle key"; exit 1; }
sed -i "s/^recharged-foliage-wind? = #[tf]/recharged-foliage-wind? = #f/" /tmp/fw3_pcs.ini
$ADB push /tmp/fw3_pcs.ini "$PCS" >/dev/null 2>&1
echo "  toggle: $($ADB shell cat "$PCS" | grep -E 'recharged-(foliage-wind|master)\?' | tr -d '\r' | paste -sd' ')"
# clear the amplitude props so the compiled defaults are what runs (and so a stale prop cannot
# leave the breeze half-on during the STOCK reference leg).
for k in tie_mult tie_amp frond shrub_amp; do $ADB shell "setprop debug.opengoal.foliage.$k ''" >/dev/null 2>&1; done

echo "######## boot + warp ########"
ok=0
for TRY in 1 2 3; do
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.level.warp beach-start >/dev/null 2>&1
  $ADB shell "setprop debug.opengoal.level.warp.pos '$BEACH_POS'" >/dev/null 2>&1
  $ADB logcat -b all -c >/dev/null 2>&1
  kill "$(cat /tmp/fw3_lc.pid 2>/dev/null)" 2>/dev/null || true
  ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/fw3_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 170 ]; do
    grep -qa "LEVEL-WARP-SPAWN name=beach-start" "$LOG" && { ok=1; break; }
    grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break
    sleep 3
  done
  echo "  try#$TRY warp_ok=$ok $(focus)"
  [ "$ok" = 1 ] && break
done
[ "$ok" = 1 ] || { echo "[fw3 FAIL] beach OFF boot"; exit 1; }

echo "######## dwell for audit windows (need >=300 wind frames at ~15 fps) ########"
$ADB shell "setprop debug.opengoal.cpad_inject 'ly=0'" >/dev/null 2>&1; sleep 4
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
for i in 1 2 3 4 5 6 7 8 9; do
  sleep 10
  n=$(grep -ac 'shear-audit' "$LOG" 2>/dev/null || echo 0)
  echo "  +$((i*10))s  audit_windows=$n  $(focus)"
  [ "${n:-0}" -ge 2 ] && break
done

echo "######## harvest ########"
grep -ao "shear-audit.*" "$LOG" | sed 's/.*on=/on=/' | cut -c1-200
echo "  crashlines=$(grep -acE 'signal (4|6|11) \(SIG|Fatal signal' "$LOG")"
$ADB shell am force-stop $PKG >/dev/null 2>&1
# leave NO stale injected input behind (memory: a leftover cpad_inject holds a button down)
$ADB shell "setprop debug.opengoal.cpad_inject ''" >/dev/null 2>&1
kill "$(cat /tmp/fw3_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "done: $LOG ($(stat -c %s "$LOG") bytes)"
