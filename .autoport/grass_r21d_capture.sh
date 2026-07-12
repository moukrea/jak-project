#!/usr/bin/env bash
# grass_r21d_capture.sh — ROUND#21d proof session. Recaptures EVERY validator beat (the report-media
# purge deleted the old frames) on the freshly-deployed build carrying the GOAL->C++ actor-occ channel:
#   A spawn: R21OCC harvest + p13_wide_* + moving screenrecord (mp4 kept) + mv stills
#   B crate: p19_crate_flat_* (crate presses a flat disc) -> spin-kick breaks it -> p19_crate_broken_*
#   C button: p19_btn_closeup_*   D relief: p19_relief_* (+ tilt A/B)
#   E/F rims: p19_edge_* + p11_edge_closeup_* + p15_edge_* + p14_rim_closeup_*
# Device hygiene: force-stop + prop cleanup at the end. Frames >20KB checked; screencap retried if black.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='files/.config/OpenGOAL/jak1/settings/pc-settings.gc'
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
say(){ echo; echo "######## $* ########"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
pulse(){ stick "$1"; sleep "${2:-0.4}"; stick neutral; sleep "${3:-0.8}"; }
focus(){ $ADB shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }
cap(){ $ADB exec-out screencap -p > "$F/$1.png" 2>/dev/null
  local sz=$(stat -c %s "$F/$1.png" 2>/dev/null || echo 0)
  if [ "$sz" -lt 100000 ]; then sleep 2; $ADB exec-out screencap -p > "$F/$1.png" 2>/dev/null; sz=$(stat -c %s "$F/$1.png" 2>/dev/null || echo 0); fi
  echo "  cap $1 = ${sz}B $(focus)"; }
rec(){ local TAG="$1" SECS="$2"   # screenrecord -> /tmp/rec_$TAG/f_NN.png (2 fps)
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  $ADB shell screenrecord --time-limit "$SECS" --bit-rate 12000000 /sdcard/${TAG}.mp4 >/dev/null 2>&1
  sleep 1; $ADB pull /sdcard/${TAG}.mp4 /tmp/${TAG}.mp4 >/dev/null 2>&1
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  mkdir -p /tmp/rec_$TAG; rm -f /tmp/rec_$TAG/*.png
  ffmpeg -y -loglevel error -i /tmp/${TAG}.mp4 -vf fps=2 /tmp/rec_$TAG/f_%02d.png 2>/dev/null
  echo "  rec $TAG: mp4=$(stat -c %s /tmp/${TAG}.mp4 2>/dev/null)B frames=$(ls /tmp/rec_$TAG 2>/dev/null | wc -l) $(focus)"; }
pick(){ local TAG="$1" IDX="$2" NAME="$3"   # copy frame #IDX of rec TAG under NAME (skip tiny/black)
  local src=$(ls /tmp/rec_$TAG/f_*.png 2>/dev/null | sed -n "${IDX}p")
  [ -n "$src" ] && cp "$src" "$F/$NAME.png" && echo "  pick $NAME = $(stat -c %s "$F/$NAME.png")B (from $src)"; }
set_grass(){ $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell run-as $PKG cat "$PCS" > /tmp/pcs21d.gc 2>/dev/null || true
  if grep -q 'recharged-grass?' /tmp/pcs21d.gc 2>/dev/null; then
    sed -i "s/(recharged-grass? #[tf])/(recharged-grass? #$1)/" /tmp/pcs21d.gc
    $ADB push /tmp/pcs21d.gc /data/local/tmp/pcs21d.gc >/dev/null 2>&1
    $ADB shell run-as $PKG cp /data/local/tmp/pcs21d.gc "$PCS" 2>/dev/null || true
    $ADB shell rm -f /data/local/tmp/pcs21d.gc >/dev/null 2>&1
  fi
  echo "  grass: $($ADB shell run-as $PKG cat "$PCS" 2>/dev/null | grep recharged-grass? | tr -d '\r')"; }
boot_warp(){ local POS="$1" LOG="$2"
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
  $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1
  $ADB logcat -b all -c >/dev/null 2>&1
  ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr21d_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  local t0=$(date +%s) ok=0
  while [ $(( $(date +%s)-t0 )) -lt 300 ]; do
    grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }
    grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break
    sleep 3
  done
  sleep 8; echo "  warp_ok=$ok pos=[$POS] $(focus)"; return $((1-ok)); }
stop_lc(){ kill "$(cat /tmp/gr21d_lc.pid 2>/dev/null)" 2>/dev/null || true; }

say "0. grass ON"
set_grass t

say "A. SPAWN — R21OCC harvest + wide + moving mp4"
boot_warp "" /tmp/gr21d_spawn.log || echo "  (warp flaked)"
sleep 8   # give the 30-frame scan + a few publishes time
cap p13_wide_on_a
pulse "rx=205" 1.0 0.6; cap p13_wide_on_b
# moving sweep: walk forward while recording (mp4 itself is a validator artifact)
stick "ly=0"; $ADB shell screenrecord --time-limit 14 --bit-rate 12000000 /sdcard/mv_r21d.mp4 >/dev/null 2>&1
stick neutral; sleep 1
$ADB pull /sdcard/mv_r21d.mp4 "$F/mv_r21d_walk.mp4" >/dev/null 2>&1
$ADB shell rm -f /sdcard/mv_r21d.mp4 >/dev/null 2>&1
echo "  moving mp4 = $(stat -c %s "$F/mv_r21d_walk.mp4" 2>/dev/null)B"
mkdir -p /tmp/rec_mv21d; rm -f /tmp/rec_mv21d/*.png
ffmpeg -y -loglevel error -i "$F/mv_r21d_walk.mp4" -vf fps=1 /tmp/rec_mv21d/f_%02d.png 2>/dev/null
cp /tmp/rec_mv21d/f_05.png "$F/mv_r21d_05.png" 2>/dev/null || true
cp /tmp/rec_mv21d/f_10.png "$F/mv_r21d_10.png" 2>/dev/null || true
grep -aE 'R21OCC|R21CENSUS' /tmp/gr21d_spawn.log | tail -30 > "$OUT/p21d_occ_proof.txt"
grep -aE 'R19OCC frame' /tmp/gr21d_spawn.log | tail -6 >> "$OUT/p21d_occ_proof.txt"
echo "  occ proof lines: $(wc -l < "$OUT/p21d_occ_proof.txt")"
stop_lc

say "B. CRATE — flat disc, then break, then spring-back"
boot_warp "-1362.5 16.2 1094.2" /tmp/gr21d_crate.log || echo "  (warp flaked)"
sleep 4
pulse "ry=238" 0.8 0.6      # pitch down toward the crates
rec r21d_crate_flat 8
pick r21d_crate_flat 6 p19_crate_flat_a
pick r21d_crate_flat 12 p19_crate_flat_b
# break: spin kick (circle) hits all around regardless of facing; two pulses + a step forward
pulse "circle" 0.5 1.0
stick "ly=0"; sleep 0.5; stick neutral; sleep 0.4
pulse "circle" 0.5 1.0
pulse "circle" 0.5 0.6
rec r21d_crate_broken 10
pick r21d_crate_broken 4 p19_crate_broken_a
pick r21d_crate_broken 10 p19_crate_broken_b
pick r21d_crate_broken 18 p19_crate_broken_c
grep -aE 'R21OCC|R19OCC frame' /tmp/gr21d_crate.log | tail -20 >> "$OUT/p21d_occ_proof.txt"
stop_lc

say "C. BUTTON close-up"
boot_warp "-1334.0 16.5 1059.8" /tmp/gr21d_btn.log || echo "  (warp flaked)"
sleep 4
pulse "ry=238" 0.8 0.6
rec r21d_btn 6
pick r21d_btn 5 p19_btn_closeup_a
pick r21d_btn 9 p19_btn_closeup_b
grep -aE 'R21OCC' /tmp/gr21d_btn.log | tail -8 >> "$OUT/p21d_occ_proof.txt"
stop_lc

say "D. RELIEF slope + tilt A/B"
$ADB shell setprop debug.opengoal.grass_tilt 0 >/dev/null 2>&1
boot_warp "-1407.0 8.5 1126.5" /tmp/gr21d_relief.log || echo "  (warp flaked)"
sleep 4
pulse "ry=240" 0.8 0.6
rec r21d_relief 6
pick r21d_relief 5 p19_relief_a
$ADB shell setprop debug.opengoal.grass_tilt 0.30 >/dev/null 2>&1; sleep 5
rec r21d_relief_tilt 6
pick r21d_relief_tilt 5 p19_relief_tiltB
$ADB shell setprop debug.opengoal.grass_tilt 0 >/dev/null 2>&1
stop_lc

say "E. RIM close-up (RIMCAND0, high platform)"
boot_warp "-1296.8 55.0 987.2" /tmp/gr21d_rim0.log || echo "  (warp flaked)"
sleep 4
stick "ry=246"; sleep 1.6; stick neutral; sleep 0.8
rec r21d_rim0 6
pick r21d_rim0 4 p19_edge_rim0_a
pick r21d_rim0 8 p11_edge_closeup_r21d_a
pulse "rx=205" 1.0 0.6; pulse "ry=238" 1.0 0.6
rec r21d_rim0b 5
pick r21d_rim0b 5 p19_edge_rim0_b
stop_lc

say "F. RIM close-up (RIMCAND3)"
boot_warp "-1299.3 53.1 983.9" /tmp/gr21d_rim3.log || echo "  (warp flaked)"
sleep 4
stick "ry=246"; sleep 1.6; stick neutral; sleep 0.8
rec r21d_rim3 6
pick r21d_rim3 4 p15_edge_r21d_on_a
pick r21d_rim3 8 p14_rim_closeup_r21d_a
stop_lc

say "teardown (device hygiene)"
$ADB shell "setprop debug.opengoal.level.warp ''" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
stop_lc
say "sizes"
ls -la "$F"/p19_*.png "$F"/p13_wide*.png "$F"/p11_edge*.png "$F"/p14_rim*.png "$F"/p15_edge*.png "$F"/mv_r21d* 2>/dev/null
echo "[r21d] DONE"
