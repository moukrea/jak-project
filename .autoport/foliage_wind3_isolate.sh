#!/usr/bin/env bash
# foliage_wind3_isolate.sh — isolate what OWNER POINT 1 alone buys, on the device, with no rebuild.
#
# The shipped ON build mixes two things: (a) the restored 60 Hz rate of the game's OWN wind, and
# (b) the ADDED Recharged breeze (tie_amp) + frond flutter. The gated device legs measure the SUM.
# This leg turns (b) off with the live props and leaves the toggle ON, so the only thing left acting
# is (a). The result is the honest answer to "what did restoring ND's rate actually do?".
#
# ⚠ WRITES OUTSIDE device/ ON PURPOSE. The audit's `on` field is
# `rc_frond > 0 || rc_amp > 0` — it labels the ADDED terms, not the toggle. With the added terms at
# zero and the toggle ON, this leg produces rows labelled `on=0` that are NOT the stock path. The
# validator reads device/*.log and requires every on=0 row to be exactly stock, so putting this log
# there would (correctly) fail it. Keeping it here preserves both the measurement and the gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='/storage/emulated/0/OpenGOAL/jak1/settings.ini'
OUT=.autoport/reports/Grecharged-foliage-wind2/isolation; mkdir -p "$OUT"
LOG="$OUT/beach-ON-rate-only.log"
BEACH_POS="-123.3 2.3 -54.6"

$ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
$ADB shell cat "$PCS" > /tmp/fw3i.ini 2>/dev/null || true
sed -i "s/^recharged-foliage-wind? = #[tf]/recharged-foliage-wind? = #t/" /tmp/fw3i.ini
$ADB push /tmp/fw3i.ini "$PCS" >/dev/null 2>&1
echo "toggle: $($ADB shell cat "$PCS" | grep -E 'recharged-(foliage-wind|master)\?' | tr -d '\r' | paste -sd' ')"
# added breeze OFF, flutter OFF, stock multiplier neutral => ONLY the restored rate is acting
$ADB shell setprop debug.opengoal.foliage.tie_mult 1.0 >/dev/null 2>&1
$ADB shell setprop debug.opengoal.foliage.tie_amp 0.0 >/dev/null 2>&1
$ADB shell setprop debug.opengoal.foliage.frond   0.0 >/dev/null 2>&1
echo "knobs: $($ADB shell 'getprop | grep opengoal.foliage' | tr -d '\r' | paste -sd' ')"

ok=0
for TRY in 1 2 3; do
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.level.warp beach-start >/dev/null 2>&1
  $ADB shell "setprop debug.opengoal.level.warp.pos '$BEACH_POS'" >/dev/null 2>&1
  $ADB logcat -b all -c >/dev/null 2>&1
  kill "$(cat /tmp/fw3i_lc.pid 2>/dev/null)" 2>/dev/null || true
  ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/fw3i_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 170 ]; do
    grep -qa "LEVEL-WARP-SPAWN name=beach-start" "$LOG" && { ok=1; break; }
    grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break
    sleep 3
  done
  echo "try#$TRY warp_ok=$ok"
  [ "$ok" = 1 ] && break
done
[ "$ok" = 1 ] || { echo "[fw3-isolate FAIL] boot"; exit 1; }
$ADB shell "setprop debug.opengoal.cpad_inject 'ly=0'" >/dev/null 2>&1; sleep 4
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
for i in $(seq 1 9); do
  sleep 10
  n=$(grep -ac 'shear-audit' "$LOG" 2>/dev/null); n=${n:-0}
  echo "  +$((i*10))s audit_windows=$n"
  [ "$n" -ge 2 ] && break
done
echo "--- RATE-ONLY windows (toggle ON, tie_amp=0, frond=0) ---"
grep -ao "shear-audit.*" "$LOG" | sed 's/.*rate_ticks=/rate_ticks=/' | cut -c1-230
echo "crashlines=$(grep -acE 'signal (4|6|11) \(SIG|Fatal signal' "$LOG")"
$ADB shell am force-stop $PKG >/dev/null 2>&1
# restore compiled defaults and leave NO stale injected input
for k in tie_mult tie_amp frond shrub_amp; do $ADB shell "setprop debug.opengoal.foliage.$k ''" >/dev/null 2>&1; done
$ADB shell "setprop debug.opengoal.cpad_inject ''" >/dev/null 2>&1
kill "$(cat /tmp/fw3i_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "done: $LOG"
