#!/usr/bin/env bash
# grass_r21d_crate_retry.sh — beat B only (crate flat->broken->springback) with boot retries
# (the ~1-in-6 link-time boot-flake left the launcher foregrounded on the first try).
# Target: crate-2950/51/52 cluster ~(-1295,7.3,1024..1032) from training-actors.json.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
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
boot_warp_retry(){ local POS="$1" LOG="$2" TRY ok
  for TRY in 1 2 3; do
    $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 2
    $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
    $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
    $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1
    $ADB logcat -b all -c >/dev/null 2>&1
    kill "$(cat /tmp/gr21c_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr21c_lc.pid )
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

say "B-retry. CRATES (crate-2951 cluster)"
boot_warp_retry "-1297.5 7.8 1035.0" /tmp/gr21c_crate.log || { echo "[r21c FAIL] could not boot-warp in 3 tries"; exit 1; }
sleep 4
orbit_rec r21c_crate_flat
for i in 04 08 12 16 20 24; do cp /tmp/rec_r21c_crate_flat/f_$i.png "$F/p19_crate_flat_$i.png" 2>/dev/null || true; done
stick "ly=0"; sleep 1.2; stick neutral; sleep 0.5
pulse "circle" 0.5 1.0
stick "ly=0"; sleep 0.6; stick neutral; sleep 0.3
pulse "circle" 0.5 1.0
pulse "circle" 0.5 0.6
orbit_rec r21c_crate_broken
for i in 04 08 12 16 20 24; do cp /tmp/rec_r21c_crate_broken/f_$i.png "$F/p19_crate_broken_$i.png" 2>/dev/null || true; done
grep -aE 'R21OCC|R19OCC frame|R21CENSUS.*crate' /tmp/gr21c_crate.log | tail -12 >> "$OUT/p21d_occ_proof.txt"

say "teardown (device hygiene)"
$ADB shell "setprop debug.opengoal.level.warp ''" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/gr21c_lc.pid 2>/dev/null)" 2>/dev/null || true
ls -la "$F"/p19_crate_*.png 2>/dev/null
echo "[r21c] DONE"
