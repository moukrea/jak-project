#!/usr/bin/env bash
# ghdmodels2_capture.sh — Grecharged-hd-models2 device capture (serial eae4df44).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="/home/emeric/Android/platform-tools/adb -s eae4df44"
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=".autoport/reports/Grecharged-hd-models2/device"; mkdir -p "$OUT"
EXT=/storage/emulated/0/OpenGOAL/jak1/settings.ini
say(){ echo; echo "######## $* ########"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'" </dev/null >/dev/null 2>&1; }
pulse(){ stick "$1"; sleep "${2:-0.4}"; stick neutral; sleep "${3:-0.7}"; }
focus(){ $ADB shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

set_models(){ # $1 = t|f  -> flip recharged-enhanced-models? in EXTERNAL settings (authoritative)
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell "sed -i 's/^recharged-enhanced-models? = #[tf]/recharged-enhanced-models? = #$1/' $EXT" >/dev/null 2>&1
  echo "  models set #$1: ext=$($ADB shell grep -E 'recharged-enhanced-models\?' $EXT 2>/dev/null | tr -d '\r')"
}

boot_warp(){ local LVL="$1" POS="$2" LOG="$3" TRY ok
  for TRY in 1 2 3 4 5; do
    $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 2
    stick neutral
    $ADB shell setprop debug.opengoal.level.warp "$LVL" >/dev/null 2>&1 </dev/null
    $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1 </dev/null
    $ADB logcat -b all -c >/dev/null 2>&1
    kill "$(cat /tmp/hd_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/hd_lc.pid )
    $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
    local t0=$(date +%s); ok=0
    while [ $(( $(date +%s)-t0 )) -lt 150 ]; do
      grep -qa "LEVEL-WARP-SPAWN name=$LVL" "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG' "$LOG" && { echo "  try#$TRY CRASH"; break; }
      sleep 3
    done
    [ "$ok" = 1 ] && { echo "  try#$TRY warp_ok $(focus)"; sleep 12; return 0; }
    echo "  try#$TRY no-spawn"
  done
  return 1; }

rec(){ local NAME="$1" SECS="${2:-10}"; shift 2
  $ADB shell rm -f /sdcard/${NAME}.mp4 >/dev/null 2>&1
  $ADB shell screenrecord --time-limit "$SECS" --bit-rate 12000000 /sdcard/${NAME}.mp4 >/dev/null 2>&1 &
  local RP=$!
  # aim routine passed as remaining args is executed here
  "$@"
  wait $RP 2>/dev/null || true
  sleep 1; $ADB pull /sdcard/${NAME}.mp4 "$OUT/${NAME}.mp4" >/dev/null 2>&1
  $ADB shell rm -f /sdcard/${NAME}.mp4 >/dev/null 2>&1
  mkdir -p "$OUT/${NAME}_frames"; rm -f "$OUT/${NAME}_frames"/*.png
  ffmpeg -y -loglevel error -i "$OUT/${NAME}.mp4" -vf fps=2 "$OUT/${NAME}_frames/f_%03d.png" 2>/dev/null
  echo "  rec $NAME: frames=$(ls "$OUT/${NAME}_frames" 2>/dev/null | wc -l) $(focus)"; }

aim_sage(){ sleep 1; pulse "rx=140" 1.0 0.6; pulse "rx=140" 0.9 0.6; stick neutral; sleep 1; pulse "rx=-120" 0.8 0.5; stick neutral; sleep 1; }
aim_hold(){ sleep 2; pulse "rx=100" 0.6 0.6; stick neutral; sleep 2; pulse "rx=-100" 0.6 0.6; stick neutral; sleep 1; }
