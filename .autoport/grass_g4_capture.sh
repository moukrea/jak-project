#!/usr/bin/env bash
# grass_g4_capture.sh — Grecharged-grass-overhang4 device capture (owner's failing BEACH overhang
# vantage). recharged-grass stays ON; the OVERHANG sub-toggle is flipped ON vs OFF at the SAME warp
# pose so the objective banding detector (goverhang4_banding.py) can be run on a matched ON/OFF pair
# (the only valid discipline — the game ground textures TILE, so only same-vantage same-crop deltas
# count). OFF is the noise floor (no droop, stock painted fringe); ON must sit at that floor in the
# calibrated 40-62 px period window if the diagonal bands are gone.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
PCS='/storage/emulated/0/OpenGOAL/jak1/settings.ini'
OUT=.autoport/reports/Grecharged-grass-overhang4; F="$OUT/g4frames"; mkdir -p "$F"
say(){ echo; echo "######## $* ########"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
pulse(){ stick "$1"; sleep "${2:-0.4}"; stick neutral; sleep "${3:-0.8}"; }
focus(){ $ADB shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }
rec(){ local TAG="$1" SECS="$2"
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  $ADB shell screenrecord --time-limit "$SECS" --bit-rate 16000000 /sdcard/${TAG}.mp4 >/dev/null 2>&1
  sleep 1; $ADB pull /sdcard/${TAG}.mp4 /tmp/${TAG}.mp4 >/dev/null 2>&1
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  mkdir -p "$F/$TAG"; rm -f "$F/$TAG"/*.png
  ffmpeg -y -loglevel error -i /tmp/${TAG}.mp4 -vf fps=3 "$F/$TAG/f_%03d.png" 2>/dev/null
  echo "  rec $TAG: mp4=$(stat -c %s /tmp/${TAG}.mp4 2>/dev/null)B frames=$(ls "$F/$TAG" 2>/dev/null | wc -l) $(focus)"; }
set_overhang(){ # $1 = t|f ; recharged-grass stays ON
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell cat "$PCS" > /tmp/pcsg4.gc 2>/dev/null || true
  sed -i "s/^recharged-grass? = #[tf]/recharged-grass? = #t/" /tmp/pcsg4.gc
  sed -i "s/^recharged-grass-overhang? = #[tf]/recharged-grass-overhang? = #$1/" /tmp/pcsg4.gc
  $ADB push /tmp/pcsg4.gc /data/local/tmp/pcsg4.gc >/dev/null 2>&1
  $ADB shell cp /data/local/tmp/pcsg4.gc "$PCS" 2>/dev/null || true
  $ADB shell rm -f /data/local/tmp/pcsg4.gc >/dev/null 2>&1
  echo "  grass/overhang: $($ADB shell cat "$PCS" 2>/dev/null | grep -E 'recharged-grass\?|overhang\?' | tr -d '\r' | paste -sd' ')"; }
boot_warp_retry(){ local POS="$1" LOG="$2" TRY ok
  for TRY in 1 2 3; do
    $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 2
    $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
    $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
    $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1
    $ADB logcat -b all -c >/dev/null 2>&1
    kill "$(cat /tmp/g4_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/g4_lc.pid )
    $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
    local t0=$(date +%s); ok=0
    while [ $(( $(date +%s)-t0 )) -lt 160 ]; do
      grep -qa 'LEVEL-WARP-SPAWN name=training-start' "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break
      sleep 3
    done
    echo "  try#$TRY warp_ok=$ok $(focus)"
    [ "$ok" = 1 ] && { sleep 8; return 0; }
  done
  return 1; }

# Aim the follow-cam at the ledge overhang, deterministic + identical for ON and OFF, then hold static.
aim_and_hold(){
  pulse "rx=205" 1.0 0.3     # look toward/along the ledge
  pulse "ry=140" 0.5 0.3     # small yaw to face the drape
  stick neutral; sleep 1.5   # settle static
}

# One vantage: overhang ON capture then OFF capture at the SAME warp+aim pose.
vantage(){ local NAME="$1" POS="$2"
  say "VANTAGE $NAME @ $POS"
  set_overhang t
  boot_warp_retry "$POS" /tmp/g4_${NAME}_on.log || { echo "[g4 FAIL] $NAME ON boot"; return 1; }
  ( sleep 2; aim_and_hold; sleep 3 ) & local A=$!
  rec "g4_${NAME}_ON" 8; wait $A 2>/dev/null || true
  set_overhang f
  boot_warp_retry "$POS" /tmp/g4_${NAME}_off.log || { echo "[g4 FAIL] $NAME OFF boot"; return 1; }
  ( sleep 2; aim_and_hold; sleep 3 ) & local B=$!
  rec "g4_${NAME}_OFF" 8; wait $B 2>/dev/null || true
  # census
  echo "  [$NAME] ON GOVERHANG4 census:"; grep -aE 'GOVERHANG4|recharged-grass\] GBK|expand @' /tmp/g4_${NAME}_on.log | tail -4
}

say "0. beach overhang vantages (owner failing state); recharged-grass ON, overhang ON vs OFF"
vantage beachA "-1296.4 7.8 1033.4"
vantage beachB "-1300.0 7.8 1018.0"
vantage beachC "-1297.5 7.8 1035.0"

say "DONE — frames under $F/*/ ; run goverhang4_banding.py on matched ON/OFF pairs"
