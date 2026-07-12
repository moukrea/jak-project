#!/usr/bin/env bash
# grass_r21d_redo_bcd.sh — redo the r21d B/C/D beats (crate/button/relief) whose warp targets in
# grass_r21d_capture.sh were derived from the JUNK merc-census coords (off-level -> black screens).
# Corrected targets come from decompiler_out/jak1/entities/training-actors.json, which matches the
# GOAL pc-grass-occ channel EXACTLY (button == occ[0], plat-eco-62 == occ[1], scarecrow-b-2 == tr[1]):
#   crates  crate-2950/51/52  ~(-1295, 7.3, 1024..1032)
#   button  warp-gate-switch-8 (-1312.0, 6.7, 1063.8)
#   relief  scarecrow field slope near scarecrow-a-1 (-1244.6, 15.0, 997.0)
# Each beat: warp to ground-level coords ~3m from target, orbit the camera while screenrecording,
# extract 2fps frames; the supervisor picks the good ones. Device hygiene: force-stop at the end.
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
orbit_rec(){ local TAG="$1"   # 14s record while orbiting camera + slight pitch down
  ( sleep 2; pulse "rx=205" 1.2 0.4; pulse "ry=225" 0.7 0.4; pulse "rx=205" 1.2 0.4; \
    pulse "rx=205" 1.2 0.4; pulse "ry=225" 0.5 0.4; pulse "rx=205" 1.2 0.4 ) &
  local ORB=$!
  rec "$TAG" 14
  wait $ORB 2>/dev/null || true; }
boot_warp(){ local POS="$1" LOG="$2"
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
  $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1
  $ADB logcat -b all -c >/dev/null 2>&1
  ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr21r_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  local t0=$(date +%s) ok=0
  while [ $(( $(date +%s)-t0 )) -lt 300 ]; do
    grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }
    grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break
    sleep 3
  done
  sleep 10; echo "  warp_ok=$ok pos=[$POS] $(focus)"; return $((1-ok)); }
stop_lc(){ kill "$(cat /tmp/gr21r_lc.pid 2>/dev/null)" 2>/dev/null || true; }

say "B. CRATES (crate-2951 cluster) — flat disc under crate, then break -> spring back"
boot_warp "-1297.5 7.8 1035.0" /tmp/gr21r_crate.log || echo "  (warp flaked)"
sleep 4
orbit_rec r21r_crate_flat
for i in 04 08 12 16 20 24; do cp /tmp/rec_r21r_crate_flat/f_$i.png "$F/p19_crate_flat_$i.png" 2>/dev/null || true; done
# walk into the cluster + spin-kick to break
stick "ly=0"; sleep 1.2; stick neutral; sleep 0.5
pulse "circle" 0.5 1.0
stick "ly=0"; sleep 0.6; stick neutral; sleep 0.3
pulse "circle" 0.5 1.0
pulse "circle" 0.5 0.6
orbit_rec r21r_crate_broken
for i in 04 08 12 16 20 24; do cp /tmp/rec_r21r_crate_broken/f_$i.png "$F/p19_crate_broken_$i.png" 2>/dev/null || true; done
grep -aE 'R21OCC|R19OCC frame|R21CENSUS.*crate' /tmp/gr21r_crate.log | tail -12 >> "$OUT/p21d_occ_proof.txt"
stop_lc

say "C. BUTTON (warp-gate-switch-8) close-up"
boot_warp "-1309.0 7.2 1060.5" /tmp/gr21r_btn.log || echo "  (warp flaked)"
sleep 4
orbit_rec r21r_btn
for i in 04 08 12 16 20 24; do cp /tmp/rec_r21r_btn/f_$i.png "$F/p19_btn_closeup_$i.png" 2>/dev/null || true; done
grep -aE 'R21OCC|R19OCC frame' /tmp/gr21r_btn.log | tail -8 >> "$OUT/p21d_occ_proof.txt"
stop_lc

say "D. RELIEF (scarecrow-field slope) + tilt A/B"
$ADB shell setprop debug.opengoal.grass_tilt 0 >/dev/null 2>&1
boot_warp "-1247.0 15.6 999.0" /tmp/gr21r_relief.log || echo "  (warp flaked)"
sleep 4
orbit_rec r21r_relief
for i in 04 08 12 16 20; do cp /tmp/rec_r21r_relief/f_$i.png "$F/p19_relief_$i.png" 2>/dev/null || true; done
$ADB shell setprop debug.opengoal.grass_tilt 0.30 >/dev/null 2>&1; sleep 5
rec r21r_relief_tilt 8
cp /tmp/rec_r21r_relief_tilt/f_08.png "$F/p19_relief_tiltB.png" 2>/dev/null || true
$ADB shell setprop debug.opengoal.grass_tilt 0 >/dev/null 2>&1
stop_lc

say "teardown (device hygiene)"
$ADB shell "setprop debug.opengoal.level.warp ''" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
stop_lc
say "sizes"
ls -la "$F"/p19_crate_*.png "$F"/p19_btn_*.png "$F"/p19_relief_*.png 2>/dev/null
echo "[r21r] DONE"
