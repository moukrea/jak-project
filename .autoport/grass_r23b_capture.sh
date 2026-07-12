#!/usr/bin/env bash
# grass_r23b_capture.sh — ROUND#23 retake: (A2) dummy CLOSE-UP flatten + ON-CAMERA break ->
# one smooth spring-back; (C2) small-rock close-ups with proper camera standoff (the r23 first
# pass buried the camera in blades and the while-read loop lost spots to adb eating stdin).
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
    kill "$(cat /tmp/gr23b_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/gr23b_lc.pid )
    $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 </dev/null
    local t0=$(date +%s); ok=0
    while [ $(( $(date +%s)-t0 )) -lt 180 ]; do
      grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break
      sleep 3
    done
    echo "  try#$TRY warp_ok=$ok $(focus)"
    [ "$ok" = 1 ] && { sleep 12; return 0; }
  done
  return 1; }
last_ntr(){ grep -a 'R21OCC goal-publish' "$1" | tail -1 | grep -oE 'ntr=[0-9]+' | cut -d= -f2; }

say "A2. DUMMY close-up — scarecrow-a-1 @ -1244.6 15.0 997.0 (warp 3.5m south, walk in, kick ON CAMERA)"
# Jak lands south of the dummy; walking forward (ly=0) moves him INTO it with the follow-cam
# behind, so the dummy + its feet patch stay centered through flatten, break, and spring-back.
boot_warp_retry "-1244.6 15.3 993.5" /tmp/gr23b_dummy.log || { echo "[r23b FAIL] dummy boot"; exit 1; }
sleep 4  # let the warp-in glow finish before recording
NTR0=$(last_ntr /tmp/gr23b_dummy.log); NTR0=${NTR0:-0}
( sleep 2; \
  stick "ly=0"; sleep 1.6; stick neutral; sleep 3.0; \
  pulse "circle" 0.5 1.0; sleep 1.0; \
  pulse "circle" 0.5 1.0; sleep 1.0; \
  pulse "circle" 0.5 1.0 ) &
KICK=$!
rec r23b_dummy 32
wait $KICK 2>/dev/null || true
sleep 6
NTR1=$(last_ntr /tmp/gr23b_dummy.log); NTR1=${NTR1:-$NTR0}
echo "  ntr $NTR0 -> $NTR1"
for i in 04 08 10 12 14 16 18 20 22 24 26 28 30 32 34 36 40 44 48 52 56 60 64; do
  cp /tmp/rec_r23b_dummy/f_$i.png "$F/p23b_dummy_$i.png" 2>/dev/null || true; done
{ echo "=== A2-DUMMY-CLOSEUP (scarecrow-a-1; flatten feet-sized r1.20, break on camera, ntr $NTR0 -> $NTR1) ==="
  grep -aE 'R21OCC goal-publish' /tmp/gr23b_dummy.log | tail -6
  grep -aE 'R19OCC frame' /tmp/gr23b_dummy.log | tail -4
} >> "$PROOF"

say "C2. SMALL ROCKS — standoff close-ups (camera above blades)"
n=0
for SPOT in "-1179.9 14.9 951.1" "-1192.9 11.3 949.1"; do
  n=$((n+1))
  RX=$(echo $SPOT | cut -d' ' -f1); RY=$(echo $SPOT | cut -d' ' -f2); RZ=$(echo $SPOT | cut -d' ' -f3)
  JX=$(python3 -c "print(f'{$RX+4.5:.1f}')"); JY=$(python3 -c "print(f'{$RY+0.8:.1f}')"); JZ=$(python3 -c "print(f'{$RZ+4.5:.1f}')")
  echo "  rock#$n face=($RX $RY $RZ) jak=($JX $JY $JZ)"
  if boot_warp_retry "$JX $JY $JZ" /tmp/gr23b_rock$n.log; then
    sleep 4
    # slow half-orbit at default pitch: the rock enters frame without burying the camera
    ( sleep 2; pulse "rx=215" 1.6 0.6; pulse "rx=215" 1.6 0.6; pulse "rx=215" 1.6 0.6; \
      pulse "ry=205" 0.5 0.5; pulse "rx=215" 1.6 0.6 ) &
    ORB=$!
    rec r23b_rock$n 18
    wait $ORB 2>/dev/null || true
    for i in 04 08 12 16 20 24 28 32; do
      cp /tmp/rec_r23b_rock$n/f_$i.png "$F/p23b_rock${n}_$i.png" 2>/dev/null || true; done
    { echo "=== C2-ROCK#$n @($RX $RY $RZ) footprint-densified: no blades through the rock ==="
      grep -aE 'R23 footprint densify|R23 rock-face warp spots' /tmp/gr23b_rock$n.log | tail -2
    } >> "$PROOF"
  else
    echo "[r23b WARN] rock#$n warp failed"
  fi
done

say "teardown (device hygiene)"
$ADB shell "setprop debug.opengoal.level.warp ''" >/dev/null 2>&1 </dev/null
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1 </dev/null
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1 </dev/null
$ADB shell am force-stop $PKG >/dev/null 2>&1 </dev/null
kill "$(cat /tmp/gr23b_lc.pid 2>/dev/null)" 2>/dev/null || true
ls -la "$F"/p23b_*.png 2>/dev/null | head -8
echo "[r23b] DONE"
