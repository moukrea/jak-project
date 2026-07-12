#!/usr/bin/env bash
# grass_p19b_rec.sh — crate + relief beats via SCREENRECORD (screencap is black on this GL surface).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
say(){ echo; echo "######## $* ########"; }
focus(){ $ADB shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
pulse(){ stick "$1"; sleep "${2:-0.4}"; stick neutral; sleep "${3:-0.8}"; }
boot_warp(){ local POS="$1" LOG="$2"
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 2
  $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
  $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
  $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1
  $ADB logcat -b all -c >/dev/null 2>&1
  ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/gr19r_lc.pid )
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
  local t0=$(date +%s) ok=0
  while [ $(( $(date +%s)-t0 )) -lt 300 ]; do
    grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }
    sleep 3
  done
  sleep 6; echo "  warp_ok=$ok pos=[$POS] $(focus)"; return $((1-ok)); }
rec(){ local TAG="$1" SECS="$2"  # record while HOLDING STILL, pull best frames
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  $ADB shell screenrecord --time-limit "$SECS" --bit-rate 12000000 /sdcard/${TAG}.mp4 >/dev/null 2>&1
  sleep 1; $ADB pull /sdcard/${TAG}.mp4 /tmp/${TAG}.mp4 >/dev/null 2>&1
  mkdir -p /tmp/rec_$TAG; rm -f /tmp/rec_$TAG/*.png
  ffmpeg -y -loglevel error -i /tmp/${TAG}.mp4 -vf fps=2 /tmp/rec_$TAG/f_%02d.png 2>/dev/null
  echo "  $TAG: mp4=$(stat -c %s /tmp/${TAG}.mp4 2>/dev/null)B frames=$(ls /tmp/rec_$TAG | wc -l) focus=$(focus)"; }

say "CRATE beat (crates at -1364.1/-1354 y~15.3)"
boot_warp "-1362.5 16.2 1094.2" /tmp/gr19r_crate.log || echo "  (flaked)"
pulse "ry=238" 0.8 0.6   # pitch down toward the ground/crates
rec p19r_crate 8
pulse "rx=185" 1.2 0.6   # pan
rec p19r_crate2 8

say "RELIEF beat + tilt A/B (same pose)"
$ADB shell setprop debug.opengoal.grass_tilt 0 >/dev/null 2>&1
boot_warp "-1407.0 8.5 1126.5" /tmp/gr19r_relief.log || echo "  (flaked)"
pulse "ry=240" 0.8 0.6
rec p19r_reliefA 6
$ADB shell setprop debug.opengoal.grass_tilt 0.30 >/dev/null 2>&1
sleep 6
rec p19r_reliefB 6
$ADB shell setprop debug.opengoal.grass_tilt 0 >/dev/null 2>&1

say "teardown (device hygiene)"
$ADB shell "setprop debug.opengoal.level.warp ''" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/gr19r_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "[p19r] DONE — frames in /tmp/rec_*/"
