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

# Wait for the renderer to CONFIRM an override flip: the build logs
# "[recharged-ao] override <kind> -> <val>" on every change (250ms wall-time re-read).
# Only waits on lines APPENDED to $LOG after the recorded mark; timeout=45s.
# Usage: wait_override <kind> <val> <mark-lineno>
wait_override(){ local KIND="$1" VAL="$2" MARK="$3" t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 45 ]; do
    if tail -n "+$((MARK+1))" "$LOG" 2>/dev/null | grep -aq "override $KIND -> $VAL"; then
      echo "  override-confirm: $KIND -> $VAL ($(( $(date +%s)-t0 ))s)"; return 0
    fi
    sleep 1
  done
  echo "  override-confirm TIMEOUT: $KIND -> $VAL (45s) — segment evidence SUSPECT"; return 1; }

# Force mode+quality and wait for the renderer's confirmation of every value that CHANGED
# (an unchanged value logs nothing). Tracks PREV_M/PREV_Q globals (init -1 = unknown/cleared).
PREV_M=-1; PREV_Q=-1
ao_force_confirmed(){ local M="$1" Q="$2"
  local MARK; MARK=$(wc -l < "$LOG" 2>/dev/null || echo 0)
  ao_force "$M" "$Q"
  [ "$M" != "$PREV_M" ] && wait_override mode "$M" "$MARK"
  [ "$Q" != "$PREV_Q" ] && wait_override quality "$Q" "$MARK"
  PREV_M="$M"; PREV_Q="$Q"
  sleep 3; }  # FBO/targets settle after a 0<->N flip (one-frame AO skip + rebuild)

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
# and frame count in REC_FRAMES. Focus is BRACKETED (before+after, both saved next to the
# frames — supervisor hard rule) and stray screenrecords are killed first (a leftover from
# a killed run starves the encoder -> header-only mp4).
REC_SZ=0; REC_FRAMES=0
rec_core(){ local TAG="$1" SECS="${2:-8}"
  $ADB shell pkill screenrecord >/dev/null 2>&1; sleep 1
  local FB; FB=$(focus)
  echo "  focus-before $TAG: $FB"
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  $ADB shell screenrecord --time-limit "$SECS" --bit-rate 16000000 /sdcard/${TAG}.mp4 2>&1 \
    | tail -2 | sed 's/^/  [screenrecord] /'
  sleep 1; $ADB pull /sdcard/${TAG}.mp4 "$DEV/${TAG}.mp4" >/dev/null 2>&1
  $ADB shell rm -f /sdcard/${TAG}.mp4 >/dev/null 2>&1
  mkdir -p "$DEV/${TAG}_frames"; rm -f "$DEV/${TAG}_frames"/*.png
  ffmpeg -y -loglevel error -i "$DEV/${TAG}.mp4" -vf fps=1 "$DEV/${TAG}_frames/f_%03d.png" 2>/dev/null
  REC_SZ=$(stat -c %s "$DEV/${TAG}.mp4" 2>/dev/null || echo 0); REC_SZ=${REC_SZ:-0}
  REC_FRAMES=$(ls "$DEV/${TAG}_frames"/f_*.png 2>/dev/null | wc -l)
  local FA; FA=$(focus)
  printf 'before: %s\nafter:  %s\n' "$FB" "$FA" > "$DEV/${TAG}_frames/focus-bracket.txt"
  echo "  rec $TAG: mp4=${REC_SZ}B frames=$REC_FRAMES focus-after: $FA"; }

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
  # validity = real frames (a static scene encodes small at any bitrate — the old 500KB
  # size gate false-failed valid still captures; a dead recording yields 0-1 frames).
  if [ "$REC_FRAMES" -lt 4 ] || [ "$REC_SZ" -lt 100000 ]; then
    echo "  SEGMENT INVALID (mp4=${REC_SZ}B frames=$REC_FRAMES): $TAG — deleting frames, retrying once"
    rm -f "$DEV/${TAG}_frames"/*.png
    if ! fg_ok; then
      echo "  re-warp before retry ($TAG)"
      boot_warp_retry "${LOG:-$DEV/ao-recover.log}" || true
      if ! fg_ok; then echo "  SEGMENT FAILED (not foreground for retry): $TAG"; return 1; fi
    fi
    rec_core "$TAG" "$SECS"
    if [ "$REC_FRAMES" -lt 4 ] || [ "$REC_SZ" -lt 100000 ]; then
      echo "  SEGMENT INVALID after retry (mp4=${REC_SZ}B frames=$REC_FRAMES): $TAG"
    fi
  fi
  return 0; }

# capture a mode's debug-view segment: arm ao.debug, WAIT for the renderer to confirm
# (attempt-4 debugview frames were the normal render: the 4s sleep lost the race against
# the old 120-call re-read throttle at 4fps), record, disarm + confirm.
# $1=prefix (e.g. device-ao-village1) $2=mode
rec_debugview(){ local PREFIX="$1" MODE="$2" MARK
  MARK=$(wc -l < "$LOG" 2>/dev/null || echo 0)
  $ADB shell "setprop debug.opengoal.ao.debug 1" >/dev/null 2>&1
  wait_override debug 1 "$MARK"; sleep 2
  rec "${PREFIX}-${MODE}-debugview" 5
  MARK=$(wc -l < "$LOG" 2>/dev/null || echo 0)
  $ADB shell "setprop debug.opengoal.ao.debug 0" >/dev/null 2>&1
  wait_override debug 0 "$MARK"; }

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
    MARK=$(wc -l < "$LOG" 2>/dev/null || echo 0)
    ao_force_confirmed "$M" "$Q"
    # AOPERF fires every 5 s wall time. Count only lines FRESHER than the flip (boot/disk
    # settings can pre-seed identical mode/quality pairs); 3 fresh lines ≈ 15 s, EMA
    # (time-constant ~2.5 s) converged.
    t0=$(date +%s); got=0
    while [ $(( $(date +%s)-t0 )) -lt 120 ]; do
      got=$(tail -n "+$((MARK+1))" "$LOG" 2>/dev/null | grep -ac "AOPERF mode=$M quality=$Q"); got=${got:-0}
      [ "$got" -ge 3 ] && break
      sleep 5
    done
    LINE=$(tail -n "+$((MARK+1))" "$LOG" | grep -a "AOPERF mode=$M quality=$Q" | tail -1 | tr -d '\r')
    echo "$TAG :: ${LINE:-NO-AOPERF-LINE}" | tee -a "$DEV/ao-fpsmatrix-results.txt"
  done
  ao_clear
  $ADB shell am force-stop $PKG >/dev/null 2>&1
  kill "$(cat /tmp/ao_lc.pid 2>/dev/null)" 2>/dev/null || true
  say "DONE fpsmatrix — $DEV/ao-fpsmatrix-results.txt"
  exit 0
fi

say "VANTAGE $VANT ($CONT @ $POS) — AO A/B, INTERLEAVED off brackets (TOD-drift compensated)"
LOG="$DEV/ao-${VANT}.log"
ao_clear
boot_warp_retry "$LOG" || { echo "[ao-capture FAIL] $VANT boot"; exit 1; }

# Walk-settle: a short forward walk parks the follow cam BEHIND Jak deterministically
# (the post-warp camera keeps re-framing for minutes if Jak never moves — attempt-4
# village1 captured three DIFFERENT poses across its segments).
$ADB shell setprop debug.opengoal.cpad_inject up >/dev/null 2>&1; sleep 1.5
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1; sleep 12

# TIGHT interleave: off-a ssao off-b hbao off-c gtao off-d (~2 min total). Each AO mode
# is judged against its BRACKETING offs, so slow time-of-day drift cancels; off-a vs
# off-d measures the residual drift; the analyzer NCC-gates every segment against off-a
# so a moved camera (human touch mid-run) FAILS instead of poisoning the luminance gates.
for combo in "0 1 off-a" "1 2 ssao" "0 1 off-b" "2 2 hbao" "0 1 off-c" "3 2 gtao" "0 1 off-d"; do
  set -- $combo; M=$1; Q=$2; TAG=$3
  ao_force_confirmed "$M" "$Q"
  rec "device-ao-${VANT}-${TAG}" 6
done
# debug-view (raw AO term) segments per mode, AFTER the A/B sequence (not luminance evidence)
for M in 1 2 3; do
  ao_force_confirmed "$M" 2
  rec_debugview "device-ao-${VANT}" "$M"
done
ao_clear
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/ao_lc.pid 2>/dev/null)" 2>/dev/null || true
say "DONE $VANT — frames under $DEV/device-ao-${VANT}-*_frames/"
