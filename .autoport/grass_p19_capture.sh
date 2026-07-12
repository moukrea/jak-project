#!/usr/bin/env bash
# grass_p19_capture.sh — ROUND#19 device proof beats (validator: p19_edge/btn/crate/relief >20KB).
#   BTN   : warp-gate button close-up — footprint grass-free (object-CULL working visually).
#   CRATE : crate close-up — visibly PRESSING a flat disc of grass (object-TRAMPLE working visually).
#   EDGE  : platform-rim-over-void close-up — no blades in the void (FLOORBELOW cull working).
#   RELIEF: bumpy-slope macro, normal-tilt A/B (grass_tilt 0 vs 0.30, same view).
# Frames land in /tmp/p19cand/<beat>/ for supervisor eyeballing; the good ones get promoted by hand.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; CAND=/tmp/p19cand
mkdir -p "$F" "$CAND"
say(){ echo; echo "######## $* ########"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
pulse(){ stick "$1"; sleep "${2:-0.4}"; stick neutral; sleep "${3:-0.8}"; }
focus(){ $ADB shell dumpsys window 2>/dev/null | grep -iE 'mCurrentFocus' | head -1 | tr -d '\r'; }
cap(){ $ADB exec-out screencap -p > "$1" 2>/dev/null; echo "  cap $(basename "$1") = $(stat -c %s "$1" 2>/dev/null)B"; }

boot_warp(){ local POS="$1" LOG="$2"
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.grass_dbg 0 >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
  $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1
  $ADB logcat -b all -c >/dev/null 2>&1
  ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr19cap_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  local t0=$(date +%s) ok=0
  while [ $(( $(date +%s)-t0 )) -lt 300 ]; do
    grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }
    grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break
    sleep 3
  done
  sleep 5; echo "  warp_ok=$ok pos=[$POS] focus=$(focus)"; return $((1-ok)); }

# record TAG SECONDS <camera-move-fn>
record(){ local TAG="$1" SECS="$2" MOVE="$3"
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  ( $ADB shell screenrecord --time-limit "$SECS" --bit-rate 16000000 /sdcard/${TAG}.mp4 >/dev/null 2>&1 ) & local REC=$!
  sleep 1; $MOVE; stick neutral
  wait $REC 2>/dev/null || true; sleep 1
  $ADB pull /sdcard/${TAG}.mp4 "/tmp/${TAG}.mp4" >/dev/null 2>&1
  mkdir -p "$CAND/$TAG"
  ffmpeg -y -loglevel error -i "/tmp/${TAG}.mp4" -vf fps=3 "$CAND/$TAG/f_%03d.png" 2>/dev/null
  echo "  $TAG: mp4=$(stat -c %s "/tmp/${TAG}.mp4" 2>/dev/null)B frames=$(ls "$CAND/$TAG" 2>/dev/null | wc -l)"; }

pan360_down(){  # slow full pan with camera pitched down at the ground objects
  pulse "ry=238" 1.0 0.5
  for i in 1 2 3 4 5 6 7 8; do pulse "rx=180" 1.0 0.6; done; }
pan_walk(){     # pan + small forward walks (unpins the follow-cam)
  pulse "ry=236" 0.9 0.4
  for i in 1 2 3 4; do pulse "rx=182" 1.0 0.5; pulse "ly=40" 0.5 0.5; done; }
hold_still(){ sleep "$1"; }

# ===================== BEAT 1: WARP BUTTON (object-CULL visual) =====================
say "BEAT 1 — warp button close-up (button at -1337.4 15.8 1062.2)"
boot_warp "-1334.0 16.5 1059.8" /tmp/gr19cap_btn.log || echo "  (btn warp flaked)"
record p19cap_btn 16 pan360_down
cap "$CAND/p19cap_btn_still1.png"; pulse "rx=185" 0.8 0.5; cap "$CAND/p19cap_btn_still2.png"

# ===================== BEAT 2: CRATE (object-TRAMPLE visual) =====================
say "BEAT 2 — crate close-up (crates at -1364.1 15.4 1095.8 / -1354 15.2 1093.6)"
boot_warp "-1361.5 16.2 1093.5" /tmp/gr19cap_crate.log || echo "  (crate warp flaked)"
record p19cap_crate 16 pan360_down
cap "$CAND/p19cap_crate_still1.png"; pulse "rx=185" 0.8 0.5; cap "$CAND/p19cap_crate_still2.png"

# ===================== BEAT 3: PLATFORM EDGE over void (FLOORBELOW) =====================
say "BEAT 3 — rim-over-void close-up (top RIMCAND from this boot's log)"
boot_warp "" /tmp/gr19cap_edge.log || echo "  (edge boot flaked)"
grep -ao 'RIMCAND [0-9]* pos="[^"]*"[^(]*' /tmp/gr19cap_edge.log | head -14 | tee /tmp/gr19_rimcand.txt
RIM=$(grep -ao 'pos="[^"]*"' /tmp/gr19_rimcand.txt | head -1 | sed 's/pos=//;s/"//g')
echo "  RIM=[$RIM]"
if [ -n "$RIM" ]; then
  boot_warp "$RIM" /tmp/gr19cap_edge2.log || echo "  (rim warp flaked)"
  record p19cap_edge 18 pan_walk
  cap "$CAND/p19cap_edge_still1.png"
fi

# ===================== BEAT 4: RELIEF macro + normal-tilt A/B =====================
say "BEAT 4 — bumpy slope macro, tilt A/B (scarecrow slope -1405 7.6 1129)"
$ADB shell setprop debug.opengoal.grass_tilt 0 >/dev/null 2>&1
boot_warp "-1407.0 8.5 1126.5" /tmp/gr19cap_relief.log || echo "  (relief warp flaked)"
pulse "ry=240" 1.0 0.5
record p19cap_relief_tiltA 8 "hold_still 6"
$ADB shell setprop debug.opengoal.grass_tilt 0.30 >/dev/null 2>&1
sleep 4   # tilt read is throttled (~64 frames); give it time to take
record p19cap_relief_tiltB 8 "hold_still 6"
$ADB shell setprop debug.opengoal.grass_tilt 0 >/dev/null 2>&1
cap "$CAND/p19cap_relief_still1.png"

# ===================== teardown =====================
say "teardown — restore props + FORCE-STOP (device hygiene)"
$ADB shell "setprop debug.opengoal.level.warp ''" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/gr19cap_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "[p19cap] DONE — candidates in $CAND/<beat>/ ; supervisor eyeballs + promotes to $F"
