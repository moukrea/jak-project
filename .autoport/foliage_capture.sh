#!/usr/bin/env bash
# foliage_capture.sh — Grecharged-foliage-wind device A/B capture.
# Flips ONLY recharged-foliage-wind? OFF vs ON at the SAME warp pose + SAME deterministic camera aim,
# records a screenrecord mp4 each side (motion is the whole point — a still can't show sway), and
# extracts frames. Palms = jak1 TIE instances (bch-palmtree*); shrubs = the shrub renderer
# (bch-bush.mb/bch-kelp.mb/...). Sentinel Beach (beach-start) has BOTH in frame.
#
# Usage:
#   foliage_capture.sh beach     -> beach-start vantage (palms + shrubs)
#   foliage_capture.sh village1  -> village1-hut vantage (shrub-heavy Sandover)
#   AIM="rx=205 ry=140" foliage_capture.sh beach   -> override the aim pulse sequence
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
# External-asset mode game root (Grecharged-external-assets): the game READS AND WRITES its
# pc-settings on EXTERNAL storage. The old internal files/.config path still exists but is DEAD —
# editing it is a silent no-op (cost this phase a full false-OFF A/B cycle).
PCS='/storage/emulated/0/OpenGOAL/jak_1/saves/settings/pc-settings.gc'
OUT=.autoport/reports/Grecharged-foliage-wind; DEV="$OUT/device"; mkdir -p "$DEV"
say(){ echo; echo "######## $* ########"; }
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
pulse(){ stick "$1"; sleep "${2:-0.4}"; stick neutral; sleep "${3:-0.8}"; }
focus(){ $ADB shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

VANT="${1:-beach}"
case "$VANT" in
  beach)    CONT=beach-start;  POS="-123.3 2.3 -54.6"; SECS=14 ;;
  village1) CONT=village1-hut; POS="-156.0 34.0 188.0"; SECS=14 ;;
  *) echo "unknown vantage $VANT"; exit 2 ;;
esac

rec(){ local TAG="$1" SECS="$2"
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  $ADB shell screenrecord --time-limit "$SECS" --bit-rate 16000000 /sdcard/${TAG}.mp4 >/dev/null 2>&1 &
  local RPID=$!
  # run the deterministic aim WHILE recording so both OFF/ON get the identical camera path
  do_aim
  wait $RPID 2>/dev/null || true
  sleep 1; $ADB pull /sdcard/${TAG}.mp4 "$DEV/${TAG}.mp4" >/dev/null 2>&1
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  mkdir -p "$DEV/${TAG}_frames"; rm -f "$DEV/${TAG}_frames"/*.png
  ffmpeg -y -loglevel error -i "$DEV/${TAG}.mp4" -vf fps=2 "$DEV/${TAG}_frames/f_%03d.png" 2>/dev/null
  echo "  rec $TAG: mp4=$(stat -c %s "$DEV/${TAG}.mp4" 2>/dev/null)B frames=$(ls "$DEV/${TAG}_frames" 2>/dev/null | wc -l) $(focus)"; }

# Deterministic camera path. Default: settle, then a slow yaw sweep so palms + shrubs pass through
# frame, then hold. Override the whole sequence with $AIM (space-separated cpad tokens, pulsed).
do_aim(){
  if [ -n "${AIM:-}" ]; then
    for tok in $AIM; do pulse "$tok" 0.6 0.6; done
    stick neutral; return
  fi
  # beach: walk forward ~4s toward the arch palms first (the beach-start spawn has all palms far;
  # at range the light sway is sub-pixel). Same deterministic input on OFF and ON runs.
  if [ "$VANT" = beach ]; then stick "ly=0"; sleep 4; stick neutral; sleep 1.5; fi
  sleep 2
  pulse "rx=160" 1.2 0.5      # slow pan right to sweep the beach line (palms)
  pulse "rx=160" 1.2 0.5
  stick neutral; sleep 2      # hold on foliage (sway visible ON, frozen OFF)
  pulse "rx=90"  1.0 0.5      # nudge to a shrub cluster
  stick neutral; sleep 2
}

set_foliage(){ # $1 = t|f (ONLY flips recharged-foliage-wind?, leaves everything else stock incl. grass)
  $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 1
  $ADB shell cat "$PCS" > /tmp/pcs_fol.gc 2>/dev/null || true
  if grep -q 'recharged-foliage-wind?' /tmp/pcs_fol.gc 2>/dev/null; then
    sed -i "s/(recharged-foliage-wind? #[tf])/(recharged-foliage-wind? #$1)/" /tmp/pcs_fol.gc
  elif grep -q 'recharged-grass-overhang?' /tmp/pcs_fol.gc 2>/dev/null; then
    # field not persisted yet (settings predate this build): inject it right after grass-overhang.
    # The settings reader is key-based, so position among the block doesn't matter; it will read on boot.
    sed -i "s/\(  (recharged-grass-overhang? #[tf])\)/\1\n  (recharged-foliage-wind? #$1)/" /tmp/pcs_fol.gc
  else
    echo "  WARN: no grass-overhang anchor to inject after — settings schema unexpected"; return 1
  fi
  $ADB push /tmp/pcs_fol.gc "$PCS" >/dev/null 2>&1
  echo "  foliage-wind now: $($ADB shell cat "$PCS" 2>/dev/null | grep -E 'recharged-foliage-wind\?' | tr -d '\r' | paste -sd' ')"; }

boot_warp_retry(){ local LOG="$1" TRY ok
  for TRY in 1 2 3; do
    $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 2
    $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
    $ADB shell setprop debug.opengoal.level.warp "$CONT" >/dev/null 2>&1
    $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1
    $ADB logcat -b all -c >/dev/null 2>&1
    kill "$(cat /tmp/fol_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/fol_lc.pid )
    $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
    local t0=$(date +%s); ok=0
    while [ $(( $(date +%s)-t0 )) -lt 160 ]; do
      grep -qa "LEVEL-WARP-SPAWN name=$CONT" "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break
      sleep 3
    done
    echo "  try#$TRY warp_ok=$ok $(focus)"
    [ "$ok" = 1 ] && { sleep 8; return 0; }
  done
  return 1; }

# fps over a 10s static window (counts A35-RENDER frame= advance / wall-clock)
measure_fps(){ local LOG="$1" tag="$2"
  local f0 f1 t0 t1
  f0=$(grep -aoE 'A35-RENDER frame=[0-9]+' "$LOG" | tail -1 | grep -oE '[0-9]+$'); f0=${f0:-0}
  t0=$(date +%s); sleep 10; t1=$(date +%s)
  # pull the freshest counter from a short live logcat sample
  $ADB logcat -d -v threadtime GK_STDOUT:I '*:S' 2>/dev/null | grep -aoE 'A35-RENDER frame=[0-9]+' | tail -1 > /tmp/fol_f1 || true
  f1=$(grep -oE '[0-9]+$' /tmp/fol_f1 2>/dev/null); f1=${f1:-$f0}
  local df=$(( f1 - f0 )); local dt=$(( t1 - t0 )); [ "$dt" -le 0 ] && dt=1
  echo "  PERF[$tag]: frames=$df over ${dt}s => ~$(awk "BEGIN{printf \"%.1f\", $df/$dt}") fps"
}

say "VANTAGE $VANT ($CONT @ $POS) — foliage-wind OFF vs ON, matched pose"

set_foliage f
boot_warp_retry "$DEV/foliage-${VANT}-OFF.log" || { echo "[foliage FAIL] $VANT OFF boot"; exit 1; }
measure_fps "$DEV/foliage-${VANT}-OFF.log" "OFF-${VANT}"
rec "device-foliage-${VANT}-OFF" "$SECS"

set_foliage t
boot_warp_retry "$DEV/foliage-${VANT}-ON.log" || { echo "[foliage FAIL] $VANT ON boot"; exit 1; }
measure_fps "$DEV/foliage-${VANT}-ON.log" "ON-${VANT}"
rec "device-foliage-${VANT}-ON" "$SECS"

say "DONE $VANT — mp4s + frames under $DEV/ (device-foliage-${VANT}-{OFF,ON}.mp4)"
