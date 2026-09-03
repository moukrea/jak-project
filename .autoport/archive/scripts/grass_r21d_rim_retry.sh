#!/usr/bin/env bash
# grass_r21d_rim_retry.sh — better p11 edge close-up (RIMCAND0 pinned the camera inside a crevice).
# Spots: RIMCAND6 (-1308.5 52.6 1000.1) near plat-eco-62 (-1298.9,52.3,1009.0) -> rim + eco vent;
#        RIMCAND10 (-1324.5 52.2 973.9) second plateau edge.
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

say "E2. RIMCAND6 near plat-eco (rim + eco vent)"
boot_warp_retry "-1308.5 52.6 1000.1" /tmp/gr21e_rim6.log || { echo "[r21e FAIL] boot"; exit 1; }
sleep 4
# step away from any wall, then slow orbit + pitch down while recording
stick "ly=0"; sleep 0.8; stick neutral; sleep 0.5
( sleep 2; pulse "ry=238" 0.8 0.5; pulse "rx=205" 1.4 0.5; pulse "rx=205" 1.4 0.5; \
  pulse "rx=205" 1.4 0.5; pulse "rx=205" 1.4 0.5 ) &
ORB=$!; rec r21e_rim6 14; wait $ORB 2>/dev/null || true
for i in 02 06 10 14 18 22 26; do cp /tmp/rec_r21e_rim6/f_$i.png "$F/p11_edge_closeup_r21e_$i.png" 2>/dev/null || true; done
grep -aE 'R19OCC frame' /tmp/gr21e_rim6.log | tail -3 >> "$OUT/p21d_occ_proof.txt"

say "E3. RIMCAND10 second plateau edge"
boot_warp_retry "-1324.5 52.2 973.9" /tmp/gr21e_rim10.log || { echo "[r21e WARN] rim10 boot failed"; }
sleep 4
stick "ly=0"; sleep 0.8; stick neutral; sleep 0.5
( sleep 2; pulse "ry=238" 0.8 0.5; pulse "rx=205" 1.4 0.5; pulse "rx=205" 1.4 0.5; \
  pulse "rx=205" 1.4 0.5; pulse "rx=205" 1.4 0.5 ) &
ORB=$!; rec r21e_rim10 14; wait $ORB 2>/dev/null || true
for i in 02 06 10 14 18 22 26; do cp /tmp/rec_r21e_rim10/f_$i.png "$F/p19_edge_rim10_$i.png" 2>/dev/null || true; done

say "teardown (device hygiene)"
$ADB shell "setprop debug.opengoal.level.warp ''" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/gr21e_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "[r21e] DONE"
