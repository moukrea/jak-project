#!/usr/bin/env bash
# grass_r23c_capture.sh — ROUND#23 final take: warp ADJACENT (no camera-relative walking).
# A3: Jak 1.4m from scarecrow-a-1 -> flatten ring close-up; kicks connect point-blank; 10s
#     post-break idle on camera = the ONE smooth spring-back proof.
# C3: Jak 2.5m from a rock face on the dummy plateau, 10s settle (no warp glow), gentle orbit.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
PROOF="$OUT/p23_occ_proof.txt"
say(){ echo; echo "######## $* ########"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'" </dev/null; }
pulse(){ stick "$1"; sleep "${2:-0.4}"; stick neutral; sleep "${3:-0.8}"; }
focus(){ $ADB shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }
rec(){ local TAG="$1" SECS="$2"
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1 </dev/null
  $ADB shell screenrecord --time-limit "$SECS" --bit-rate 12000000 /sdcard/${TAG}.mp4 >/dev/null 2>&1 </dev/null
  sleep 1; $ADB pull /sdcard/${TAG}.mp4 /tmp/${TAG}.mp4 >/dev/null 2>&1 </dev/null
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1 </dev/null
  mkdir -p /tmp/rec_$TAG; rm -f /tmp/rec_$TAG/*.png
  ffmpeg -y -loglevel error -i /tmp/${TAG}.mp4 -vf fps=2 /tmp/rec_$TAG/f_%02d.png 2>/dev/null
  echo "  rec $TAG: mp4=$(stat -c %s /tmp/${TAG}.mp4 2>/dev/null)B frames=$(ls /tmp/rec_$TAG 2>/dev/null | wc -l) $(focus)"; }
boot_warp_retry(){ local POS="$1" LOG="$2" TRY ok
  for TRY in 1 2 3; do
    $ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null; sleep 2
    $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1 </dev/null
    $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1 </dev/null
    $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1 </dev/null
    $ADB logcat -b all -c >/dev/null 2>&1 </dev/null
    kill "$(cat /tmp/gr23c_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/gr23c_lc.pid )
    $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 </dev/null
    local t0=$(date +%s); ok=0
    while [ $(( $(date +%s)-t0 )) -lt 180 ]; do
      grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break
      sleep 3
    done
    echo "  try#$TRY warp_ok=$ok $(focus)"
    [ "$ok" = 1 ] && { sleep 14; return 0; }   # long settle: warp glow fully faded
  done
  return 1; }

say "A3. DUMMY point-blank — scarecrow-a-1 @ -1244.6 15.0 997.0, Jak at 1.4m east"
boot_warp_retry "-1243.2 15.3 997.0" /tmp/gr23c_dummy.log || { echo "[r23c FAIL] dummy boot"; exit 1; }
( sleep 6; \
  pulse "circle" 0.5 1.2; \
  pulse "circle" 0.5 1.2; \
  pulse "circle" 0.5 1.2; \
  pulse "circle" 0.5 1.2 ) &
KICK=$!
rec r23c_dummy 34
wait $KICK 2>/dev/null || true
for i in 02 04 06 08 10 12 14 16 18 20 22 24 26 28 30 32 36 40 44 48 52 56 60 64 68; do
  cp /tmp/rec_r23c_dummy/f_$i.png "$F/p23c_dummy_$i.png" 2>/dev/null || true; done
{ echo "=== A3-DUMMY-POINTBLANK (idle flatten ring 0-6s, kicks 6-14s, spring-back 14-34s) ==="
  grep -aE 'R21OCC goal-publish' /tmp/gr23c_dummy.log | tail -6
} >> "$PROOF"

say "C3. ROCK standoff — plateau rock face @ -1179.9 14.9 951.1, Jak at 2.5m"
boot_warp_retry "-1177.4 15.7 953.6" /tmp/gr23c_rock.log || { echo "[r23c FAIL] rock boot"; exit 1; }
( sleep 3; pulse "rx=220" 1.4 0.8; pulse "rx=220" 1.4 0.8; pulse "rx=220" 1.4 0.8; \
  pulse "rx=220" 1.4 0.8; pulse "rx=220" 1.4 0.8 ) &
ORB=$!
rec r23c_rock 20
wait $ORB 2>/dev/null || true
for i in 02 06 10 14 18 22 26 30 34 38; do
  cp /tmp/rec_r23c_rock/f_$i.png "$F/p23c_rock_$i.png" 2>/dev/null || true; done

say "teardown (device hygiene)"
$ADB shell "setprop debug.opengoal.level.warp ''" >/dev/null 2>&1 </dev/null
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1 </dev/null
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1 </dev/null
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null
kill "$(cat /tmp/gr23c_lc.pid 2>/dev/null)" 2>/dev/null || true
ls "$F"/p23c_*.png 2>/dev/null | head -4
echo "[r23c] DONE"
