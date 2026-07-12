#!/usr/bin/env bash
# grass_r22_capture.sh — ROUND#22 proof session (owner plateau verdict 2026-07-12 ~16:30).
# Items to prove on device (supervisor eyeballs the frames BEFORE any push):
#   1. SPRING-BACK ON BREAK: publish gate = alive+drawn (crates.gc `die` sets draw-status hidden,
#      process persists). Beat A records CONTINUOUSLY across the crate break: flatten (with the new
#      LYING-DOWN edge ring) -> spin-kick break -> grass visibly back up within ~1 s (2 fps frames
#      = 0.5 s granularity, p22_crate_seq_*).
#   2. GENERIC REAL-BOUNDS COLLIDER: R21OCC publish lines must show per-actor radii that are the
#      draw-bounds footprints (varied real values), NOT the old hand constants (0.90/0.70/2.20/1.20).
#   3. LYING-DOWN RING: p22_crate_flat_* close-ups show edge blades LYING outward at the plateau rim.
#   B BUTTON base margin (real footprint) p22_btn_base_*, C ECOVENT base clean p22_vent_*.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='files/.config/OpenGOAL/jak1/settings/pc-settings.gc'
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
PROOF="$OUT/p22_occ_proof.txt"; : > "$PROOF"
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
  $ADB shell run-as $PKG cat "$PCS" > /tmp/pcs22.gc 2>/dev/null || true
  if grep -q 'recharged-grass?' /tmp/pcs22.gc 2>/dev/null; then
    sed -i "s/(recharged-grass? #[tf])/(recharged-grass? #$1)/" /tmp/pcs22.gc
    $ADB push /tmp/pcs22.gc /data/local/tmp/pcs22.gc >/dev/null 2>&1
    $ADB shell run-as $PKG cp /data/local/tmp/pcs22.gc "$PCS" 2>/dev/null || true
    $ADB shell rm -f /data/local/tmp/pcs22.gc >/dev/null 2>&1
  fi
  echo "  grass: $($ADB shell run-as $PKG cat "$PCS" 2>/dev/null | grep recharged-grass? | tr -d '\r')"; }
boot_warp_retry(){ local POS="$1" LOG="$2" TRY ok
  for TRY in 1 2 3; do
    $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 2
    $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
    $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
    $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1
    $ADB logcat -b all -c >/dev/null 2>&1
    kill "$(cat /tmp/gr22_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr22_lc.pid )
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
    grep -aE 'R21OCC goal-publish' "$LOG" | tail -8
    grep -aE 'R19OCC frame' "$LOG" | tail -4
    grep -aE 'R21E-YBAND' "$LOG" | tail -20
  } >> "$PROOF"
  echo "  harvested $BEAT: $(grep -ac 'R21OCC goal-publish' "$LOG" 2>/dev/null || echo 0) publish lines"; }

say "0. grass ON"
set_grass t

say "A. CRATES cluster — lying-ring flatten + CONTINUOUS break/spring-back sequence"
boot_warp_retry "-1297.5 7.8 1035.0" /tmp/gr22_crate.log || { echo "[r22 FAIL] crate boot"; exit 1; }
sleep 12   # first scans (15f cadence) + publishes settle
orbit_rec r22_crate_flat
for i in 04 08 12 16 20 24; do cp /tmp/rec_r22_crate_flat/f_$i.png "$F/p22_crate_flat_$i.png" 2>/dev/null || true; done
last_ntr(){ grep -a 'R21OCC goal-publish' /tmp/gr22_crate.log | tail -1 | grep -oE 'ntr=[0-9]+' | cut -d= -f2; }
NTR0=$(last_ntr); NTR0=${NTR0:-0}
echo "  baseline ntr=$NTR0"
# Continuous 30 s rec; inside it Jak sweeps 3 directions with spin-kicks (the previous single
# forward pulse never reached a crate — jak pos barely moved and ntr never dropped). Objective
# break signal = ntr drops below baseline in the R21OCC publishes.
( sleep 3; \
  stick "ly=0";   sleep 1.4; stick neutral; sleep 0.2; pulse "circle" 0.5 0.9; pulse "circle" 0.5 0.9; \
  stick "lx=0";   sleep 1.2; stick neutral; sleep 0.2; pulse "circle" 0.5 0.9; pulse "circle" 0.5 0.9; \
  stick "ly=255"; sleep 1.6; stick neutral; sleep 0.2; pulse "circle" 0.5 0.9; pulse "circle" 0.5 0.9; \
  stick "lx=255"; sleep 1.0; stick neutral; sleep 0.2; pulse "circle" 0.5 0.9 ) &
BRK=$!
rec r22_crate_seq 30
wait $BRK 2>/dev/null || true
sleep 6   # let a %20 publish land in the log
NTR1=$(last_ntr); NTR1=${NTR1:-$NTR0}
echo "  post-sweep ntr=$NTR1 (baseline $NTR0)"
if [ "$NTR1" -ge "$NTR0" ] 2>/dev/null; then
  echo "  no break detected — second sweep"
  ( sleep 2; \
    stick "ly=0";  sleep 2.0; stick neutral; sleep 0.2; pulse "circle" 0.5 0.9; pulse "circle" 0.5 0.9; \
    stick "lx=0";  sleep 1.8; stick neutral; sleep 0.2; pulse "circle" 0.5 0.9; pulse "circle" 0.5 0.9 ) &
  BRK2=$!
  rec r22_crate_seq2 22
  wait $BRK2 2>/dev/null || true
  sleep 6
  NTR1=$(last_ntr); NTR1=${NTR1:-$NTR0}
  echo "  post-sweep2 ntr=$NTR1 (baseline $NTR0)"
  for i in 02 06 10 14 18 22 26 30 34 38 42; do
    cp /tmp/rec_r22_crate_seq2/f_$i.png "$F/p22_crate_seq2_$i.png" 2>/dev/null || true; done
fi
[ "$NTR1" -lt "$NTR0" ] 2>/dev/null && echo "  BREAK CONFIRMED: ntr $NTR0 -> $NTR1 (hidden crate left the publish set)"
for i in 02 04 06 08 10 12 14 16 18 20 22 24 26 28 30 32 34 36 38 40 44 48 52 56 60; do
  cp /tmp/rec_r22_crate_seq/f_$i.png "$F/p22_crate_seq_$i.png" 2>/dev/null || true; done
harvest "A-CRATES (radii must be REAL bounds, not 0.90 constants; hidden crate must VANISH from tr[] after break: ntr $NTR0 -> $NTR1)" /tmp/gr22_crate.log

say "B. BUTTON (warp-gate-switch) — base margin with the real footprint"
boot_warp_retry "-1309.0 7.2 1060.5" /tmp/gr22_btn.log || { echo "[r22 FAIL] button boot"; exit 1; }
sleep 12
pulse "ry=238" 0.8 0.6
orbit_rec r22_btn
for i in 04 08 12 16 20 24; do cp /tmp/rec_r22_btn/f_$i.png "$F/p22_btn_base_$i.png" 2>/dev/null || true; done
harvest "B-BUTTON (occ[] radius = real draw-bounds footprint, base margin exact)" /tmp/gr22_btn.log

say "C. ECOVENT — base clean with the real footprint"
VOK=0
for POS in "-1304.5 29.8 851.5" "-1310.5 29.8 850.0" "-1305.0 30.2 858.5"; do
  if boot_warp_retry "$POS" /tmp/gr22_vent.log; then VOK=1; break; fi
done
if [ "$VOK" = 1 ]; then
  sleep 12
  pulse "rx=205" 1.0 0.5
  orbit_rec r22_vent
  for i in 04 08 12 16 20 24; do cp /tmp/rec_r22_vent/f_$i.png "$F/p22_vent_$i.png" 2>/dev/null || true; done
  harvest "C-ECOVENT (occ[] radius = real bounds; base clean)" /tmp/gr22_vent.log
else
  echo "[r22 WARN] vent warp failed at all 3 candidates"
fi

say "teardown (device hygiene)"
$ADB shell "setprop debug.opengoal.level.warp ''" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/gr22_lc.pid 2>/dev/null)" 2>/dev/null || true
echo; echo "=== proof file ==="; cat "$PROOF"
ls -la "$F"/p22_*.png 2>/dev/null
echo "[r22] DONE"
