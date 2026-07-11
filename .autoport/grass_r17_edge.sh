#!/usr/bin/env bash
# grass_r17_edge.sh — ROUND#17: prove the COLLISION/walkable-floor bound stops grass at the TRUE rim
# (render mesh cantilevers past collision; grass now bounded by PAT ground-mode collision tris). Warp Jak
# to the highest RIMCAND platforms (the ones the owner sees floating), pitch camera DOWN at the rim,
# capture ON vs OFF (A/B), and harvest the ROUND#17 WALKABLE-FLOOR instrumentation. Force-stop at end.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='files/.config/OpenGOAL/jak1/settings/pc-settings.gc'
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
say(){ echo; echo "######## $* ########"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
pulse(){ $ADB shell setprop debug.opengoal.cpad_inject "$1"; sleep "${2:-0.4}"; $ADB shell setprop debug.opengoal.cpad_inject neutral; sleep "${3:-1.0}"; }
cap(){ $ADB exec-out screencap -p > "$F/$1.png" 2>/dev/null; echo "  cap $1 = $(stat -c %s "$F/$1.png" 2>/dev/null)B"; }
focus(){ $ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'; }

set_grass(){ $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell run-as $PKG cat "$PCS" > /tmp/pcs17.gc 2>/dev/null || true
  if grep -q 'recharged-grass?' /tmp/pcs17.gc 2>/dev/null; then
    sed -i "s/(recharged-grass? #[tf])/(recharged-grass? #$1)/" /tmp/pcs17.gc
    $ADB push /tmp/pcs17.gc /data/local/tmp/pcs17.gc >/dev/null 2>&1
    $ADB shell run-as $PKG cp /data/local/tmp/pcs17.gc "$PCS" 2>/dev/null || true; $ADB shell rm -f /data/local/tmp/pcs17.gc >/dev/null 2>&1
  fi
  echo "  grass now: $($ADB shell run-as $PKG cat "$PCS" 2>/dev/null | grep recharged-grass | tr -d '\r')"; }

boot_warp(){ local POS="$1" LOG="$2"
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.grass_dbg 0 >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
  $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1
  $ADB logcat -b all -c >/dev/null 2>&1
  ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr17_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  local t0=$(date +%s); while [ $(( $(date +%s)-t0 )) -lt 170 ]; do grep -qa 'link finish: logo' "$LOG" && break; grep -qaE 'signal (4|6|11) \(SIG' "$LOG" && break; sleep 2; done
  local ok=0; t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 150 ]; do grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }; grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break; sleep 3; done
  sleep 7; echo "  warp_ok=$ok focus=$(focus)"; return $((1-ok)); }

# frame a rim: settle, pitch camera DOWN toward the edge, capture; retry once if black (<100KB)
edge_shots(){ local TAG="$1"
  stick "ry=246"; sleep 1.6; stick "neutral"; sleep 0.6; cap "${TAG}_a"
  [ "$(stat -c %s "$F/${TAG}_a.png" 2>/dev/null || echo 0)" -lt 100000 ] && { sleep 1.5; cap "${TAG}_a"; }
  pulse "rx=205" 1.0 0.5; stick "ry=238"; sleep 1.0; stick "neutral"; sleep 0.5; cap "${TAG}_b"
  stick "ly=0"; sleep 1.1; stick "neutral"; sleep 0.7; stick "ry=243"; sleep 0.9; stick "neutral"; sleep 0.5; cap "${TAG}_c"
  echo "  focus=$(focus)"; }

say "1. grass ON: boot+harvest ROUND#17 line + RIMCAND, wide spawn shot"
set_grass t
boot_warp "" /tmp/gr17_harvest.log
: > "$OUT/p17_round17.txt"
grep -aE 'recharged-grass\] ROUND#17 WALKABLE-FLOOR' /tmp/gr17_harvest.log | tail -2 | tee -a "$OUT/p17_round17.txt"
grep -aE 'recharged-grass\] RIMDIST'  /tmp/gr17_harvest.log | tail -2 | tee -a "$OUT/p17_round17.txt"
grep -aE 'recharged-grass\] RIMCAND'  /tmp/gr17_harvest.log | tail -20 | tee "$OUT/p17_rimcand.txt"
cap p17_spawn_on

mapfile -t COORDS < <(grep -aoE 'pos="[^"]+"' /tmp/gr17_harvest.log | sed 's/pos=//;s/"//g')
P0="${COORDS[0]:-}"; P1="${COORDS[3]:-}"; P2="${COORDS[6]:-}"
echo "  P0=[$P0] P1=[$P1] P2=[$P2]"

say "2. grass ON: warp to the highest platform rims, edge close-ups over the void"
i=0
for P in "$P0" "$P1" "$P2"; do
  [ -n "$P" ] || { i=$((i+1)); continue; }
  say "  ON rim $i pos='$P'"
  boot_warp "$P" "/tmp/gr17_on_$i.log" || echo "  boot flaked rim $i"
  edge_shots "p17_rim_${i}_on"
  i=$((i+1))
done

say "3. grass OFF: same top rim (A/B stock proof) + wide"
set_grass f
boot_warp "$P0" /tmp/gr17_off0.log || echo "  off boot flaked"
edge_shots "p17_rim_0_off"
cap p17_spawn_off

say "4. restore grass ON + FORCE-STOP (device hygiene)"
set_grass t
$ADB shell "setprop debug.opengoal.level.warp '\"\"'" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos '\"\"'" >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/gr17_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "[r17] DONE — p17_rim_*_on/off + p17_spawn_on/off + p17_round17.txt in $OUT"
echo "[r17] frame sizes:"; ls -la "$F"/p17_*.png 2>/dev/null | awk '{print "  "$5"\t"$9}'
