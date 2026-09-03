#!/usr/bin/env bash
# grass_r21e_capture.sh — ROUND#21e proof session (owner verdict 21d: channel works, tuning wrong).
# Beats + the objective log proof for each 21e fix:
#   A CRATES (crate-2950/51/52 cluster): R19OCC must show tr[0..3] = r0.90 CRATES at the cluster
#     coords (nearest-16 sort fix — 21d had scarecrows 100-170m away in the slots) + flat-disc frames
#     p21e_crate_flat_* -> spin-kick break -> p21e_crate_broken_* (spring-back).
#   B BUTTON (warp-gate-switch-8): base-ring close-up p21e_btn_base_* with r2.20 in occ[] (was r1.50
#     -> grass clipped around the base).
#   C ECOVENT (ecovent-245 at -1308.0 29.5 854.2): occ[] must now CONTAIN the ground vent (the 21d
#     scan only matched plat-eco -> only the terrace platform was published) + p21e_vent_* close-up.
#   Every beat also harvests the one-shot R21E-YBAND lines (dy obj-vs-blade, IN-BAND check).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='/storage/emulated/0/OpenGOAL/jak1/settings.ini'
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
PROOF="$OUT/p21e_occ_proof.txt"; : > "$PROOF"
say(){ echo; echo "######## $* ########"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
pulse(){ stick "$1"; sleep "${2:-0.4}"; stick neutral; sleep "${3:-0.8}"; }
focus(){ $ADB shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }
rec(){ local TAG="$1" SECS="$2"
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  $ADB shell screenrecord --time-limit "$SECS" --bit-rate 12000000 /sdcard/${TAG}.mp4 >/dev/null 2>&1
  sleep 1; $ADB pull /sdcard/${TAG}.mp4 /tmp/${TAG}.mp4 >/dev/null 2>&1
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  mkdir -p /tmp/rec_$TAG; rm -f /tmp/rec_$TAG/*.png
  ffmpeg -y -loglevel error -i /tmp/${TAG}.mp4 -vf fps=2 /tmp/rec_$TAG/f_%02d.png 2>/dev/null
  echo "  rec $TAG: mp4=$(stat -c %s /tmp/${TAG}.mp4 2>/dev/null)B frames=$(ls /tmp/rec_$TAG 2>/dev/null | wc -l) $(focus)"; }
orbit_rec(){ local TAG="$1"
  ( sleep 2; pulse "rx=205" 1.2 0.4; pulse "ry=225" 0.7 0.4; pulse "rx=205" 1.2 0.4; \
    pulse "rx=205" 1.2 0.4; pulse "ry=225" 0.5 0.4; pulse "rx=205" 1.2 0.4 ) &
  local ORB=$!
  rec "$TAG" 14
  wait $ORB 2>/dev/null || true; }
set_grass(){ $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell cat "$PCS" > /tmp/pcs21e.gc 2>/dev/null || true
  if grep -q 'recharged-grass?' /tmp/pcs21e.gc 2>/dev/null; then
    sed -i "s/^recharged-grass? = #[tf]/recharged-grass? = #$1/" /tmp/pcs21e.gc
    $ADB push /tmp/pcs21e.gc /data/local/tmp/pcs21e.gc >/dev/null 2>&1
    $ADB shell cp /data/local/tmp/pcs21e.gc "$PCS" 2>/dev/null || true
    $ADB shell rm -f /data/local/tmp/pcs21e.gc >/dev/null 2>&1
  fi
  echo "  grass: $($ADB shell cat "$PCS" 2>/dev/null | grep recharged-grass? | tr -d '\r')"; }
boot_warp_retry(){ local POS="$1" LOG="$2" TRY ok
  for TRY in 1 2 3; do
    $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 2
    $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
    $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
    $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1
    $ADB logcat -b all -c >/dev/null 2>&1
    kill "$(cat /tmp/gr21e_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr21e_lc.pid )
    $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
    local t0=$(date +%s); ok=0
    while [ $(( $(date +%s)-t0 )) -lt 180 ]; do
      grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break
      sleep 3
    done
    echo "  try#$TRY warp_ok=$ok $(focus)"
    [ "$ok" = 1 ] && { sleep 10; return 0; }
  done
  return 1; }
harvest(){ local BEAT="$1" LOG="$2"
  { echo "=== $BEAT ==="
    grep -aE 'R21E-YBAND' "$LOG" | tail -40
    grep -aE 'R21OCC goal-publish' "$LOG" | tail -6
    grep -aE 'R19OCC frame' "$LOG" | tail -6
  } >> "$PROOF"
  echo "  harvested $BEAT: $(grep -ac 'R21E-YBAND' "$LOG" 2>/dev/null || echo 0) yband lines"; }

say "0. grass ON"
set_grass t

say "A. CRATES (crate-2950/51/52 cluster) — nearest-16 proof + flat->broken->springback"
boot_warp_retry "-1297.5 7.8 1035.0" /tmp/gr21e_crate.log || { echo "[r21e FAIL] crate boot"; exit 1; }
sleep 20   # scan (30f) + a few publishes + the R19OCC 150-frame dump cadence
orbit_rec r21e_crate_flat
for i in 04 08 12 16 20 24; do cp /tmp/rec_r21e_crate_flat/f_$i.png "$F/p21e_crate_flat_$i.png" 2>/dev/null || true; done
stick "ly=0"; sleep 1.2; stick neutral; sleep 0.5
pulse "circle" 0.5 1.0
stick "ly=0"; sleep 0.6; stick neutral; sleep 0.3
pulse "circle" 0.5 1.0
pulse "circle" 0.5 0.6
orbit_rec r21e_crate_broken
for i in 04 08 12 16 20 24; do cp /tmp/rec_r21e_crate_broken/f_$i.png "$F/p21e_crate_broken_$i.png" 2>/dev/null || true; done
harvest "A-CRATES (expect tr[0..3]=r0.90 crates ~(-1285..-1296,7,1024..1035))" /tmp/gr21e_crate.log

say "B. BUTTON (warp-gate-switch-8) — base-ring close-up with r2.20"
boot_warp_retry "-1309.0 7.2 1060.5" /tmp/gr21e_btn.log || { echo "[r21e FAIL] button boot"; exit 1; }
sleep 20
pulse "ry=238" 0.8 0.6      # pitch down at the base ring
orbit_rec r21e_btn
for i in 04 08 12 16 20 24; do cp /tmp/rec_r21e_btn/f_$i.png "$F/p21e_btn_base_$i.png" 2>/dev/null || true; done
harvest "B-BUTTON (expect occ[] entry (-1312.0,6.7,1063.8 r2.20))" /tmp/gr21e_btn.log

say "C. ECOVENT (ecovent-245, the owner's blue-eco ground vent) — now published via the vent family"
VOK=0
for POS in "-1304.5 29.8 851.5" "-1310.5 29.8 850.0" "-1305.0 30.2 858.5"; do
  if boot_warp_retry "$POS" /tmp/gr21e_vent.log; then VOK=1; break; fi
done
if [ "$VOK" = 1 ]; then
  sleep 20
  pulse "rx=205" 1.0 0.5    # swing camera to face the vent
  orbit_rec r21e_vent
  for i in 04 08 12 16 20 24; do cp /tmp/rec_r21e_vent/f_$i.png "$F/p21e_vent_$i.png" 2>/dev/null || true; done
  harvest "C-ECOVENT (expect occ[] entry (-1308.0,29.5,854.2 r1.20))" /tmp/gr21e_vent.log
else
  echo "[r21e WARN] vent warp failed at all 3 candidates — occ[] log proof may still come from beat A/B"
fi

say "teardown (device hygiene)"
$ADB shell "setprop debug.opengoal.level.warp ''" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/gr21e_lc.pid 2>/dev/null)" 2>/dev/null || true
echo; echo "=== proof file ==="; cat "$PROOF"
ls -la "$F"/p21e_*.png 2>/dev/null
echo "[r21e] DONE"
