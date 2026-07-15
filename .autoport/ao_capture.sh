#!/usr/bin/env bash
# ao_capture.sh — Grecharged-ambient-occlusion device A/B capture + fps matrix.
#
# Uses the LIVE debug.opengoal.ao.force_mode/.force_quality props (re-read every ~120
# effective_mode() calls, ~1 s wall) to flip AO WITHOUT rebooting: one boot+warp per
# vantage, then per-mode captures at the IDENTICAL pose. Owner settings file UNTOUCHED
# (props override the persisted setting only while set; cleared at the end).
#
# Usage:
#   ao_capture.sh village1   -> village1-hut vantage (hut walls/corners: crease/contact beat)
#   ao_capture.sh beach      -> beach-start vantage (palms+shrubs: alpha-TESTED foliage beat)
#   ao_capture.sh training   -> training main-lawn ledge (recharged grass CARDS: alpha beat)
#   ao_capture.sh fpsmatrix  -> village1 vantage, 10-combo AOPERF sweep (3 algos x 3 quality + off)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-ambient-occlusion; DEV="$OUT/device"; mkdir -p "$DEV"
$ADB shell "setprop debug.opengoal.ao.debug 0" >/dev/null 2>&1  # defensive: never leave debug-view armed
say(){ echo; echo "######## $* ########"; }
focus(){ $ADB shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }
fg_ok(){ $ADB shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -q "org.opengoal.gk.jak1" ; }
ao_force(){ $ADB shell "setprop debug.opengoal.ao.force_mode '$1'" >/dev/null 2>&1
            $ADB shell "setprop debug.opengoal.ao.force_quality '$2'" >/dev/null 2>&1; }
ao_clear(){ $ADB shell "setprop debug.opengoal.ao.force_mode ''" >/dev/null 2>&1
            $ADB shell "setprop debug.opengoal.ao.force_quality ''" >/dev/null 2>&1; }

VANT="${1:-village1}"
case "$VANT" in
  village1|fpsmatrix) CONT=village1-hut;  POS="-156.0 34.0 188.0" ;;
  beach)              CONT=beach-start;   POS="-123.3 2.3 -54.6" ;;
  training)           CONT=training-start; POS="-1187.4 16.2 932.3" ;;
  *) echo "unknown vantage $VANT"; exit 2 ;;
esac

boot_warp_retry(){ local LOG="$1" TRY ok
  for TRY in 1 2 3; do
    $ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 2
    $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
    $ADB shell setprop debug.opengoal.level.warp "$CONT" >/dev/null 2>&1
    $ADB shell "setprop debug.opengoal.level.warp.pos '$POS'" >/dev/null 2>&1
    $ADB logcat -b all -c >/dev/null 2>&1
    kill "$(cat /tmp/ao_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( $ADB logcat -b all -v threadtime > "$LOG" 2>/dev/null & echo $! > /tmp/ao_lc.pid )
    $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
    local t0=$(date +%s); ok=0
    while [ $(( $(date +%s)-t0 )) -lt 160 ]; do
      grep -qa "LEVEL-WARP-SPAWN name=$CONT" "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG|LEVEL-WARP-FAIL' "$LOG" && break
      sleep 3
    done
    echo "  try#$TRY warp_ok=$ok $(focus)"
    if [ "$ok" = 1 ]; then
      sleep 8
      # Early-boot MIUI launch bounces steal the foreground for the first ~1-2 min:
      # refront (am start on the LIVE process keeps the warp) until fg holds 30s.
      local st=$(date +%s) held=0
      while [ $(( $(date +%s)-st )) -lt 360 ]; do
        if fg_ok; then held=$((held+1)); [ "$held" -ge 4 ] && break
        else held=0; echo "  (stabilize) FG-LOST — refront"
          $ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1
          $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1; sleep 10
        fi
        sleep 8
      done
      [ "$held" -ge 4 ] && { echo "  foreground STABLE"; return 0; }
      echo "  foreground never stabilized — rebooting app (try $TRY)"
      continue
    fi
  done
  return 1; }

# low-level record+pull+extract for ONE segment (no gating); returns mp4 size in REC_SZ
REC_SZ=0
rec_core(){ local TAG="$1" SECS="${2:-8}"
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  $ADB shell screenrecord --time-limit "$SECS" --bit-rate 16000000 /sdcard/${TAG}.mp4 >/dev/null 2>&1
  sleep 1; $ADB pull /sdcard/${TAG}.mp4 "$DEV/${TAG}.mp4" >/dev/null 2>&1
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  mkdir -p "$DEV/${TAG}_frames"; rm -f "$DEV/${TAG}_frames"/*.png
  ffmpeg -y -loglevel error -i "$DEV/${TAG}.mp4" -vf fps=1 "$DEV/${TAG}_frames/f_%03d.png" 2>/dev/null
  REC_SZ=$(stat -c %s "$DEV/${TAG}.mp4" 2>/dev/null || echo 0); REC_SZ=${REC_SZ:-0}
  echo "  rec $TAG: mp4=${REC_SZ}B frames=$(ls "$DEV/${TAG}_frames" 2>/dev/null | wc -l) $(focus)"; }

# foreground-gated, size-gated, settled capture of ONE segment.
# $1=TAG $2=SECS.  Uses global $LOG for warp-recovery.
rec(){ local TAG="$1" SECS="${2:-8}"
  if ! fg_ok; then
    echo "  FG-LOST before $TAG — attempting ONE recovery re-warp"
    boot_warp_retry "${LOG:-$DEV/ao-recover.log}" || true
    if ! fg_ok; then
      echo "  SEGMENT FAILED (not foreground after recovery): $TAG — skipped, not recording launcher"
      return 1
    fi
  fi
  rec_core "$TAG" "$SECS"
  if ! fg_ok; then echo "  SEGMENT SUSPECT (foreground lost after record): $TAG"; fi
  if [ "$REC_SZ" -lt 500000 ]; then
    echo "  SEGMENT INVALID (mp4=${REC_SZ}B < 500000): $TAG — deleting frames, retrying once"
    rm -f "$DEV/${TAG}_frames"/*.png
    if ! fg_ok; then
      echo "  re-warp before retry ($TAG)"
      boot_warp_retry "${LOG:-$DEV/ao-recover.log}" || true
      if ! fg_ok; then echo "  SEGMENT FAILED (not foreground for retry): $TAG"; return 1; fi
    fi
    rec_core "$TAG" "$SECS"
    if [ "$REC_SZ" -lt 500000 ]; then echo "  SEGMENT INVALID after retry (mp4=${REC_SZ}B): $TAG"; fi
  fi
  return 0; }

# capture a mode's debug-view segment: arm ao.debug, settle, record, disarm.
# $1=prefix (e.g. device-ao-village1) $2=mode
rec_debugview(){ local PREFIX="$1" MODE="$2"
  $ADB shell "setprop debug.opengoal.ao.debug 1" >/dev/null 2>&1; sleep 4
  rec "${PREFIX}-${MODE}-debugview" 5
  $ADB shell "setprop debug.opengoal.ao.debug 0" >/dev/null 2>&1; sleep 2; }

if [ "$VANT" = fpsmatrix ]; then
  say "FPS MATRIX @ $CONT $POS — 10 combos, AOPERF harvest"
  LOG="$DEV/ao-fpsmatrix.log"
  ao_clear
  boot_warp_retry "$LOG" || { echo "[ao-capture FAIL] fpsmatrix boot"; exit 1; }
  : > "$DEV/ao-fpsmatrix-results.txt"
  for combo in "0 1 off" "1 0 ssao-low" "1 1 ssao-med" "1 2 ssao-high" \
               "2 0 hbao-low" "2 1 hbao-med" "2 2 hbao-high" \
               "3 0 gtao-low" "3 1 gtao-med" "3 2 gtao-high"; do
    set -- $combo; M=$1; Q=$2; TAG=$3
    ao_force "$M" "$Q"; sleep 4    # prop pickup + FBO/targets settle
    # AOPERF fires every 300 presented frames (~10-30 s at 10-30 fps). Wait for TWO fresh
    # lines with the right mode/quality so the EMA has converged.
    t0=$(date +%s); got=0
    while [ $(( $(date +%s)-t0 )) -lt 120 ]; do
      got=$(grep -ac "AOPERF mode=$M quality=$Q" "$LOG" 2>/dev/null); got=${got:-0}
      [ "$got" -ge 2 ] && break
      sleep 5
    done
    LINE=$(grep -a "AOPERF mode=$M quality=$Q" "$LOG" | tail -1 | tr -d '\r')
    echo "$TAG :: ${LINE:-NO-AOPERF-LINE}" | tee -a "$DEV/ao-fpsmatrix-results.txt"
  done
  ao_clear
  $ADB shell am force-stop $PKG >/dev/null 2>&1
  kill "$(cat /tmp/ao_lc.pid 2>/dev/null)" 2>/dev/null || true
  say "DONE fpsmatrix — $DEV/ao-fpsmatrix-results.txt"
  exit 0
fi

say "VANTAGE $VANT ($CONT @ $POS) — AO off/ssao/hbao/gtao at matched pose (live prop flip)"
LOG="$DEV/ao-${VANT}.log"
ao_clear
boot_warp_retry "$LOG" || { echo "[ao-capture FAIL] $VANT boot"; exit 1; }

for combo in "0 1 off" "1 2 ssao" "2 2 hbao" "3 2 gtao"; do
  set -- $combo; M=$1; Q=$2; TAG=$3
  ao_force "$M" "$Q"; sleep 4    # prop pickup + FBO/targets settle (renderer re-reads ~2s)
  rec "device-ao-${VANT}-${TAG}" 8
  # debug-view (raw AO) segment for AO-on modes only (1 ssao, 2 hbao, 3 gtao) — not off(0)
  if [ "$M" != 0 ]; then rec_debugview "device-ao-${VANT}" "$M"; fi
done
ao_clear
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/ao_lc.pid 2>/dev/null)" 2>/dev/null || true
say "DONE $VANT — frames under $DEV/device-ao-${VANT}-*_frames/"
