#!/usr/bin/env bash
# goverhang5_capture.sh — Grecharged-grass-overhang5 device A/B capture (serial eae4df44).
# Captures the OVERHANG LIP zone at two training-start vantages, OFF (stock) vs ON (recharged
# drape), records a short screenrecord while a deterministic camera aim brings the lip into
# frame, and extracts frames. Reusable for BEFORE (baseline) and AFTER (fixed) — pass a TAG.
#
# Usage:
#   TAG=before bash .autoport/goverhang5_capture.sh          # both vantages, OFF+ON
#   TAG=after  VANT=terr bash .autoport/goverhang5_capture.sh # one vantage
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
TAG="${TAG:-cap}"
OUT=".autoport/reports/Grecharged-grass-overhang5/${TAG}"; mkdir -p "$OUT"
EXT=/storage/emulated/0/OpenGOAL/jak1/settings.ini
INT=/storage/emulated/0/OpenGOAL/jak1/settings.ini
say(){ echo; echo "######## $* ########"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'" </dev/null >/dev/null 2>&1; }
pulse(){ stick "$1"; sleep "${2:-0.4}"; stick neutral; sleep "${3:-0.7}"; }
focus(){ $ADB shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

# RIM  = raised grass platform over the OCEAN (clean lip silhouette against ocean/sky)
# TERR = stepped terraces (dirt-faced lips between storeys — the owner's complaint zone)
RIM="-1324.5 52.2 973.9"
TERR="-1310.2 52.8 989.0"

set_overhang(){ # $1 = t|f  -> flip recharged-grass-overhang? in BOTH settings files, keep grass ON
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  # external
  $ADB shell "sed -i 's/^recharged-grass-overhang? = #[tf]/recharged-grass-overhang? = #$1/' $EXT" >/dev/null 2>&1
  $ADB shell "sed -i 's/^recharged-grass? = #[tf]/recharged-grass? = #t/' $EXT" >/dev/null 2>&1
  # internal (run-as bounce)
  $ADB shell run-as $PKG cat $INT > /tmp/g5_int.gc 2>/dev/null || true
  if grep -q 'recharged-grass-overhang?' /tmp/g5_int.gc 2>/dev/null; then
    sed -i "s/^recharged-grass-overhang? = #[tf]/recharged-grass-overhang? = #$1/" /tmp/g5_int.gc
    sed -i "s/^recharged-grass? = #[tf]/recharged-grass? = #t/" /tmp/g5_int.gc
    $ADB push /tmp/g5_int.gc /data/local/tmp/g5_int.gc >/dev/null 2>&1
    $ADB shell run-as $PKG cp /data/local/tmp/g5_int.gc $INT 2>/dev/null || true
    $ADB shell rm -f /data/local/tmp/g5_int.gc >/dev/null 2>&1
  fi
  echo "  overhang set #$1: ext=$($ADB shell grep -E 'recharged-grass-overhang\?' $EXT 2>/dev/null | tr -d '\r')"
}

boot_warp(){ local POS="$1" LOG="$2" TRY ok
  for TRY in 1 2 3 4 5; do
    $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 2
    stick neutral
    $ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1 </dev/null
    $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1 </dev/null
    $ADB logcat -b all -c >/dev/null 2>&1
    kill "$(cat /tmp/g5_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/g5_lc.pid )
    $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
    local t0=$(date +%s); ok=0
    while [ $(( $(date +%s)-t0 )) -lt 130 ]; do
      grep -qa "LEVEL-WARP-SPAWN name=training-start" "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG|GK-DIAG pc\+0 @ 0x7f00000000' "$LOG" && { echo "  try#$TRY CRASH"; break; }
      sleep 3
    done
    [ "$ok" = 1 ] && { echo "  try#$TRY warp_ok $(focus)"; sleep 12; return 0; }
  done
  return 1; }

# deterministic aim: settle, pan the lip into frame, pitch down a touch, hold
do_aim(){
  sleep 1
  pulse "rx=150" 1.0 0.6
  pulse "ry=120" 0.7 0.5     # pitch camera down toward the lip
  stick neutral; sleep 1
  pulse "rx=140" 0.9 0.6
  stick neutral; sleep 1
}

rec(){ local NAME="$1" SECS="${2:-8}"
  $ADB shell rm -f /sdcard/${NAME}.mp4 >/dev/null 2>&1
  $ADB shell screenrecord --time-limit "$SECS" --bit-rate 12000000 /sdcard/${NAME}.mp4 >/dev/null 2>&1 &
  local RP=$!
  do_aim
  wait $RP 2>/dev/null || true
  sleep 1; $ADB pull /sdcard/${NAME}.mp4 "$OUT/${NAME}.mp4" >/dev/null 2>&1
  $ADB shell rm -f /sdcard/${NAME}.mp4 >/dev/null 2>&1
  mkdir -p "$OUT/${NAME}_frames"; rm -f "$OUT/${NAME}_frames"/*.png
  ffmpeg -y -loglevel error -i "$OUT/${NAME}.mp4" -vf fps=2 "$OUT/${NAME}_frames/f_%03d.png" 2>/dev/null
  echo "  rec $NAME: frames=$(ls "$OUT/${NAME}_frames" 2>/dev/null | wc -l) $(focus)"; }

do_vant(){ local NM="$1" POS="$2"
  say "VANTAGE $NM ($POS) — OFF then ON"
  set_overhang f
  boot_warp "$POS" "$OUT/${NM}_off.log" || { echo "[g5cap FAIL] $NM OFF boot"; return 1; }
  rec "${TAG}_${NM}_OFF" 8
  set_overhang t
  boot_warp "$POS" "$OUT/${NM}_on.log" || { echo "[g5cap FAIL] $NM ON boot"; return 1; }
  rec "${TAG}_${NM}_ON" 8; }

case "${VANT:-both}" in
  rim)  do_vant rim  "$RIM" ;;
  terr) do_vant terr "$TERR" ;;
  both) do_vant terr "$TERR"; do_vant rim "$RIM" ;;
esac

# hygiene: clear warp props, restore overhang ON, force-stop
$ADB shell setprop debug.opengoal.level.warp '""' >/dev/null 2>&1
$ADB shell setprop debug.opengoal.level.warp.pos '""' >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
kill "$(cat /tmp/g5_lc.pid 2>/dev/null)" 2>/dev/null || true
$ADB shell am force-stop $PKG >/dev/null 2>&1
say "DONE tag=$TAG — frames under $OUT/*_frames/"
