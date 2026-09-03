#!/usr/bin/env bash
# grass_r23_capture.sh — ROUND#23 proof session (owner R22b verdict 2026-07-12 ~18:30).
# Items to prove on device (supervisor eyeballs the frames BEFORE any push):
#   1. SMALL ROCKS no longer leak grass: the R23 face-densified footprint sampling closes the
#      vertex-gap leak. Boot log gives "R23 rock-face warp spots" -> close-up orbit at 2 spots
#      (p23_rock_*): NO blades poking through the rock.
#   2. DUMMY trample = FEET: scarecrow kind-1 radius now = collide root-prim clamp 1.2m (was
#      bsphere*0.8 = 2.4m). p23_dummy_flat_* shows a feet-sized pressed patch. R21OCC tr[] radii
#      must read r1.20 for scarecrows (was r2.40).
#   3. BREAK = ONE smooth spring-back (joint-exploder/touch-tracker no longer published): the
#      continuous p23_dummy_seq_* frames must show flatten -> break -> gradual recovery, with NO
#      disappear-then-lying-then-upright triple (no kind-0 bald disc stomp during debris).
#   4. CRATE A/B regression check (owner: crates PERFECT — forbidden to regress): p23_crate_flat_*
#      vs the p22_crate_flat_* frames; radii 1.28 -> 1.20 must be visually identical.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='/storage/emulated/0/OpenGOAL/jak1/settings.ini'
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
PROOF="$OUT/p23_occ_proof.txt"; : > "$PROOF"
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
  $ADB shell cat "$PCS" > /tmp/pcs23.gc 2>/dev/null || true
  if grep -q 'recharged-grass?' /tmp/pcs23.gc 2>/dev/null; then
    sed -i "s/^recharged-grass? = #[tf]/recharged-grass? = #$1/" /tmp/pcs23.gc
    $ADB push /tmp/pcs23.gc /data/local/tmp/pcs23.gc >/dev/null 2>&1
    $ADB shell cp /data/local/tmp/pcs23.gc "$PCS" 2>/dev/null || true
    $ADB shell rm -f /data/local/tmp/pcs23.gc >/dev/null 2>&1
  fi
  echo "  grass: $($ADB shell cat "$PCS" 2>/dev/null | grep recharged-grass? | tr -d '\r')"; }
boot_warp_retry(){ local POS="$1" LOG="$2" TRY ok
  for TRY in 1 2 3; do
    $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 2
    $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
    $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
    $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1
    $ADB logcat -b all -c >/dev/null 2>&1
    kill "$(cat /tmp/gr23_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr23_lc.pid )
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
    grep -aE 'R23 footprint densify|R23 rock-face warp spots' "$LOG" | tail -4
    grep -aE 'R21OCC goal-publish' "$LOG" | tail -8
    grep -aE 'R19OCC frame' "$LOG" | tail -4
  } >> "$PROOF"
  echo "  harvested $BEAT: $(grep -ac 'R21OCC goal-publish' "$LOG" 2>/dev/null || echo 0) publish lines"; }
last_ntr(){ grep -a 'R21OCC goal-publish' "$1" | tail -1 | grep -oE 'ntr=[0-9]+' | cut -d= -f2; }

say "0. grass ON"
set_grass t

say "A. DUMMY (scarecrow-a-3 @ -1230.4 15.0 1005.1) — FEET-sized flatten + ONE-smooth-spring-back break"
boot_warp_retry "-1227.5 15.3 1002.5" /tmp/gr23_dummy.log || { echo "[r23 FAIL] dummy boot"; exit 1; }
sleep 12   # scans settle (15f cadence)
# walk INTO the dummy first so the flatten patch is at frame center, then orbit
stick "ly=0"; sleep 1.2; stick neutral; sleep 1.0
orbit_rec r23_dummy_flat
for i in 04 08 12 16 20 24; do cp /tmp/rec_r23_dummy_flat/f_$i.png "$F/p23_dummy_flat_$i.png" 2>/dev/null || true; done
NTR0=$(last_ntr /tmp/gr23_dummy.log); NTR0=${NTR0:-0}
echo "  baseline ntr=$NTR0"
# continuous 30 s rec; Jak sweeps toward the dummy with spin-kicks. Objective break signal =
# ntr drops below baseline (scarecrow turns hidden -> leaves the publish set).
( sleep 3; \
  stick "ly=0";   sleep 1.2; stick neutral; sleep 0.2; pulse "circle" 0.5 0.9; pulse "circle" 0.5 0.9; \
  stick "lx=0";   sleep 1.0; stick neutral; sleep 0.2; pulse "circle" 0.5 0.9; pulse "circle" 0.5 0.9; \
  stick "ly=255"; sleep 1.2; stick neutral; sleep 0.2; pulse "circle" 0.5 0.9; pulse "circle" 0.5 0.9; \
  stick "lx=255"; sleep 1.0; stick neutral; sleep 0.2; pulse "circle" 0.5 0.9 ) &
BRK=$!
rec r23_dummy_seq 30
wait $BRK 2>/dev/null || true
sleep 6
NTR1=$(last_ntr /tmp/gr23_dummy.log); NTR1=${NTR1:-$NTR0}
echo "  post-sweep ntr=$NTR1 (baseline $NTR0)"
if [ "$NTR1" -ge "$NTR0" ] 2>/dev/null; then
  echo "  no break detected — second sweep"
  ( sleep 2; \
    stick "ly=0";  sleep 1.8; stick neutral; sleep 0.2; pulse "circle" 0.5 0.9; pulse "circle" 0.5 0.9; \
    stick "lx=0";  sleep 1.4; stick neutral; sleep 0.2; pulse "circle" 0.5 0.9; pulse "circle" 0.5 0.9 ) &
  BRK2=$!
  rec r23_dummy_seq2 22
  wait $BRK2 2>/dev/null || true
  sleep 6
  NTR1=$(last_ntr /tmp/gr23_dummy.log); NTR1=${NTR1:-$NTR0}
  echo "  post-sweep2 ntr=$NTR1 (baseline $NTR0)"
  for i in 02 06 10 14 18 22 26 30 34 38 42; do
    cp /tmp/rec_r23_dummy_seq2/f_$i.png "$F/p23_dummy_seq2_$i.png" 2>/dev/null || true; done
fi
[ "$NTR1" -lt "$NTR0" ] 2>/dev/null && echo "  BREAK CONFIRMED: ntr $NTR0 -> $NTR1 (hidden dummy left the publish set)"
for i in 02 04 06 08 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 44 48 52 56 60; do
  cp /tmp/rec_r23_dummy_seq/f_$i.png "$F/p23_dummy_seq_$i.png" 2>/dev/null || true; done
harvest "A-DUMMY (tr[] scarecrow radii must be r1.20 [collide feet], not r2.40 [bsphere]; break: ntr $NTR0 -> $NTR1; NO kind-0 debris spike)" /tmp/gr23_dummy.log

say "B. CRATES A/B regression (owner: crates PERFECT) — same beat as r22"
boot_warp_retry "-1297.5 7.8 1035.0" /tmp/gr23_crate.log || { echo "[r23 FAIL] crate boot"; exit 1; }
sleep 12
orbit_rec r23_crate_flat
for i in 04 08 12 16 20 24; do cp /tmp/rec_r23_crate_flat/f_$i.png "$F/p23_crate_flat_$i.png" 2>/dev/null || true; done
harvest "B-CRATES A/B (tr[] crate radii 1.28 -> 1.20, must be visually identical to p22_crate_flat)" /tmp/gr23_crate.log

say "C. SMALL ROCKS — close-up at R23 rock-face warp spots (no blades through rock)"
# spots come from the boot log of beat A (the densify census logs once at grass place)
SPOTS=$(grep -a 'R23 rock-face warp spots' /tmp/gr23_dummy.log | tail -1 | grep -oE '\(-?[0-9.]+ -?[0-9.]+ -?[0-9.]+\)' | tr -d '()')
echo "  rock spots from log:"; echo "$SPOTS" | sed 's/^/    /'
n=0
while read -r RX RY RZ; do
  [ -z "${RX:-}" ] && continue
  n=$((n+1)); [ "$n" -gt 2 ] && break
  # land Jak ~2.5m beside the rock face, slightly above
  JX=$(python3 -c "print(f'{$RX+2.5:.1f}')"); JY=$(python3 -c "print(f'{$RY+0.7:.1f}')"); JZ=$(python3 -c "print(f'{$RZ+2.5:.1f}')")
  echo "  rock#$n face=($RX $RY $RZ) jak=($JX $JY $JZ)"
  if boot_warp_retry "$JX $JY $JZ" /tmp/gr23_rock$n.log; then
    sleep 12
    pulse "rx=205" 1.0 0.5
    orbit_rec r23_rock$n
    for i in 04 08 12 16 20 24; do cp /tmp/rec_r23_rock$n/f_$i.png "$F/p23_rock${n}_$i.png" 2>/dev/null || true; done
    harvest "C-ROCK#$n @($RX $RY $RZ) (face-densified footprint: no blades through the rock)" /tmp/gr23_rock$n.log
  else
    echo "[r23 WARN] rock#$n warp failed"
  fi
done <<< "$SPOTS"

say "teardown (device hygiene)"
$ADB shell "setprop debug.opengoal.level.warp ''" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/gr23_lc.pid 2>/dev/null)" 2>/dev/null || true
echo; echo "=== proof file ==="; cat "$PROOF"
ls -la "$F"/p23_*.png 2>/dev/null
echo "[r23] DONE"
