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
#   ao_capture.sh shoreline  -> Sentinel Beach waterline (defect #7: WATER must be untouched
#                               by AO + grazing wet-sand floor whiteness; beach-start faces
#                               SW = seaward, pos at the sea edge next to the crab cluster)
#   ao_capture.sh fpsmatrix  -> village1 vantage, 10-combo AOPERF sweep (3 algos x 3 quality + off)
#   ao_capture.sh strengthgrid -> training vantage, 3 modes x 3 strengths (weaker/default/
#                               stronger @ quality High) with off brackets — AO STRENGTH proof
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
            $ADB shell "setprop debug.opengoal.ao.force_quality '$2'" >/dev/null 2>&1
            $ADB shell "setprop debug.opengoal.ao.force_strength '$3'" >/dev/null 2>&1; }
ao_clear(){ $ADB shell "setprop debug.opengoal.ao.force_mode ''" >/dev/null 2>&1
            $ADB shell "setprop debug.opengoal.ao.force_quality ''" >/dev/null 2>&1
            $ADB shell "setprop debug.opengoal.ao.force_strength ''" >/dev/null 2>&1; }

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

# Wait for a FRESH AOPERF line proving the renderer actually RUNS mode=M quality=Q.
# (Owner-overlap invalidation root cause: the 01:06-01:15 battery confirmed only the prop
# FLIP; no AOPERF line inside any A/B window ever confirmed a non-zero mode. AOPERF fires
# every 5 s wall time on the current build, so 30 s is 6 cadences of margin.)
wait_aoperf(){ local M="$1" Q="$2" S="$3" MARK="$4" t0=$(date +%s)
  while [ $(( $(date +%s)-t0 )) -lt 30 ]; do
    if tail -n "+$((MARK+1))" "$LOG" 2>/dev/null | grep -aq "AOPERF mode=$M quality=$Q strength=$S"; then
      echo "  aoperf-confirm: mode=$M quality=$Q strength=$S ($(( $(date +%s)-t0 ))s)"; return 0
    fi
    sleep 2
  done
  echo "  aoperf-confirm TIMEOUT: mode=$M quality=$Q strength=$S (30s) — segment evidence SUSPECT"; return 1; }

# Force mode+quality+strength and wait for the renderer's confirmation of every value that
# CHANGED (an unchanged value logs nothing), THEN for an AOPERF line at the forced triple.
# Tracks PREV_M/PREV_Q/PREV_S globals (init -1 = unknown/cleared).
PREV_M=-1; PREV_Q=-1; PREV_S=-1
ao_force_confirmed(){ local M="$1" Q="$2" S="$3"
  local MARK; MARK=$(wc -l < "$LOG" 2>/dev/null || echo 0)
  ao_force "$M" "$Q" "$S"
  [ "$M" != "$PREV_M" ] && wait_override mode "$M" "$MARK"
  [ "$Q" != "$PREV_Q" ] && wait_override quality "$Q" "$MARK"
  [ "$S" != "$PREV_S" ] && wait_override strength "$S" "$MARK"
  PREV_M="$M"; PREV_Q="$Q"; PREV_S="$S"
  wait_aoperf "$M" "$Q" "$S" "$MARK"
  sleep 3; }  # FBO/targets settle after a 0<->N flip (one-frame AO skip + rebuild)

VANT="${1:-village1}"
case "$VANT" in
  village1|fpsmatrix) CONT=village1-hut;  POS="-156.0 34.0 188.0" ;;
  beach)              CONT=beach-start;   POS="-123.3 2.3 -54.6" ;;
  training)           CONT=training-start; POS="-1187.4 16.2 932.3" ;;
  strengthgrid)       CONT=training-start; POS="-1187.4 16.2 932.3" ;;
  shoreline)          CONT=beach-start;   POS="-195.0 3.5 -415.0" ;;
  *) echo "unknown vantage $VANT"; exit 2 ;;
esac

# Owner capture protocol (2026-07-15 13:50): every A/B and the fps matrix must be measured
# at LOCKED FULL render resolution with recharged grass OFF and the PERSISTED AO setting at
# 0 (the A/B flips still use the debug props; the persisted setting stays 0, so props do NOT
# arm the safe-boot sentinel). We seed the on-disk pc-settings.gc + read it back + die on a
# failed push (attempt-4 false-negative root cause). Floats print via ~f, e.g. 100.0000, so
# the sed pattern must accept a decimal tail. ao_proof_battery.sh step 5 restores grass +
# dynamic-RS after the whole phase.
SETTINGS_DEV="/storage/emulated/0/OpenGOAL/jak_1/saves/settings/pc-settings.gc"
SENTINEL="/storage/emulated/0/OpenGOAL/jak_1/saves/settings/ao-boot-guard"
seed_capture_protocol(){
  $ADB shell cat "$SETTINGS_DEV" > /tmp/pcs_ao_cap.gc 2>/dev/null
  if ! grep -qa 'ambient-occlusion' /tmp/pcs_ao_cap.gc; then
    echo "  SEED FAIL: no ambient-occlusion key on device settings"; exit 1; fi
  sed -i \
    -e 's/(dynamic-render-scale? #[tf])/(dynamic-render-scale? #f)/' \
    -e 's/(render-scale [0-9.]*)/(render-scale 100.0000)/' \
    -e 's/(recharged-grass? #[tf])/(recharged-grass? #f)/' \
    -e 's/(ambient-occlusion [0-9]*)/(ambient-occlusion 0)/' \
    -e 's/(ao-quality [0-9]*)/(ao-quality 1)/' \
    -e 's/(ao-strength [0-9]*)/(ao-strength 1)/' \
    /tmp/pcs_ao_cap.gc
  # OLD device settings files predate the ao-strength key: insert it after ao-quality.
  grep -qa '(ao-strength' /tmp/pcs_ao_cap.gc || sed -i '/(ao-quality [0-9]*)/a\  (ao-strength 1)' /tmp/pcs_ao_cap.gc
  $ADB push /tmp/pcs_ao_cap.gc "$SETTINGS_DEV" >/dev/null 2>&1
  local BACK; BACK=$($ADB shell cat "$SETTINGS_DEV" 2>/dev/null \
    | grep -aoE "\((dynamic-render-scale\? #[tf]|render-scale [0-9.]+|recharged-grass\? #[tf]|ambient-occlusion [0-9]+|ao-quality [0-9]+|ao-strength [0-9]+)\)" | tr '\n' ' ')
  case "$BACK" in *"(dynamic-render-scale? #f)"*) : ;; *) echo "  SEED READBACK FAIL (dynamic-render-scale? #f): $BACK"; exit 1 ;; esac
  case "$BACK" in *"(recharged-grass? #f)"*) : ;; *) echo "  SEED READBACK FAIL (recharged-grass? #f): $BACK"; exit 1 ;; esac
  case "$BACK" in *"(ambient-occlusion 0)"*) : ;; *) echo "  SEED READBACK FAIL (ambient-occlusion 0): $BACK"; exit 1 ;; esac
  case "$BACK" in *"(ao-quality 1)"*) : ;; *) echo "  SEED READBACK FAIL (ao-quality 1): $BACK"; exit 1 ;; esac
  case "$BACK" in *"(ao-strength 1)"*) : ;; *) echo "  SEED READBACK FAIL (ao-strength 1): $BACK"; exit 1 ;; esac
  case "$BACK" in *"(render-scale 100"*) : ;; *) echo "  SEED READBACK FAIL (render-scale 100.x): $BACK"; exit 1 ;; esac
  $ADB shell rm -f "$SENTINEL" >/dev/null 2>&1
  echo "  capture-protocol seeded+verified: $BACK"; }

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
      if [ "$held" -ge 4 ]; then
        echo "  foreground STABLE"
        # Owner protocol PROOF of locked full res: screenrecord always captures at display
        # res, so the frame-height gate can't see the INTERNAL render scale. The renderer
        # logs "A35-RENDER FBO setup: WxH (game_res WxH scale N% ...)" — the last one must
        # say scale 100% (seed_capture_protocol set render-scale 100, dynamic RS off).
        local SCALE_LINE
        SCALE_LINE=$(grep -a "A35-RENDER FBO setup" "$LOG" | tail -1 | tr -d '\r')
        echo "  fbo-scale check: ${SCALE_LINE:-NO-A35-RENDER-LINE}"
        case "$SCALE_LINE" in
          *"scale 100%"*) : ;;
          *) echo "  RENDER-SCALE NOT LOCKED AT 100% — capture would be low-res evidence; FAIL"
             return 1 ;;
        esac
        return 0
      fi
      echo "  foreground never stabilized — rebooting app (try $TRY)"
      continue
    fi
  done
  return 1; }

# low-level record+pull+extract for ONE segment (no gating); returns mp4 size in REC_SZ
# and frame count in REC_FRAMES. Focus is BRACKETED (before+after, both saved next to the
# frames — supervisor hard rule) and stray screenrecords are killed first (a leftover from
# a killed run starves the encoder -> header-only mp4).
REC_SZ=0; REC_FRAMES=0; REC_H=0
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
  # Owner protocol: assert LOCKED FULL RES. The Redmi is 2400x1080 landscape; a
  # dynamic-renderscale'd low-res capture is not acceptance evidence. Probe the first
  # frame's dimensions and expose the height in REC_H (0 if no frames).
  local FIRST W H
  FIRST=$(ls "$DEV/${TAG}_frames"/f_*.png 2>/dev/null | head -1)
  REC_H=0; W=0; H=0
  if [ -n "$FIRST" ]; then
    read -r W H < <(python3 -c "from PIL import Image;import sys;i=Image.open(sys.argv[1]);print(i.width,i.height)" "$FIRST" 2>/dev/null \
      || ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=' ' "$FIRST" 2>/dev/null)
    W=${W:-0}; H=${H:-0}; REC_H=$H
  fi
  echo "  res $TAG: ${W}x${H}"
  local FA; FA=$(focus)
  printf 'before: %s\nafter:  %s\n' "$FB" "$FA" > "$DEV/${TAG}_frames/focus-bracket.txt"
  echo "  rec $TAG: mp4=${REC_SZ}B frames=$REC_FRAMES res=${W}x${H} focus-after: $FA"; }

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
  # validity = real frames AND locked full res (owner protocol: HEIGHT < 1000px = a
  # dynamic-renderscale'd low-res capture, NOT acceptance evidence).
  if [ "$REC_FRAMES" -lt 4 ] || [ "$REC_SZ" -lt 100000 ] || [ "${REC_H:-0}" -lt 1000 ]; then
    echo "  SEGMENT INVALID (mp4=${REC_SZ}B frames=$REC_FRAMES h=${REC_H}px<1000): $TAG — deleting frames, retrying once"
    rm -f "$DEV/${TAG}_frames"/*.png
    if ! fg_ok; then
      echo "  re-warp before retry ($TAG)"
      boot_warp_retry "${LOG:-$DEV/ao-recover.log}" || true
      if ! fg_ok; then echo "  SEGMENT FAILED (not foreground for retry): $TAG"; return 1; fi
    fi
    rec_core "$TAG" "$SECS"
    if [ "$REC_FRAMES" -lt 4 ] || [ "$REC_SZ" -lt 100000 ] || [ "${REC_H:-0}" -lt 1000 ]; then
      echo "  SEGMENT INVALID after retry (mp4=${REC_SZ}B frames=$REC_FRAMES h=${REC_H}px): $TAG"
    fi
  fi
  return 0; }

# capture a mode's debug-view segment: arm ao.debug, WAIT for the renderer to confirm
# (attempt-4 debugview frames were the normal render: the 4s sleep lost the race against
# the old 120-call re-read throttle at 4fps), record, disarm + confirm.
# $1=prefix (e.g. device-ao-village1) $2=mode
rec_debugview(){ local PREFIX="$1" MODE="$2" MARK TRY
  MARK=$(wc -l < "$LOG" 2>/dev/null || echo 0)
  $ADB shell "setprop debug.opengoal.ao.debug 1" >/dev/null 2>&1
  wait_override debug 1 "$MARK"; sleep 2
  for TRY in 1 2; do
    rec "${PREFIX}-${MODE}-debugview" 5
    # Verify the segment really shows the TERM VIEW, not a raced normal render
    # (training attempt: SSAO debugview read white=1% sky=149 — a normal-render frame).
    # Discriminator: the term view's sky is grey/white (saturation ~0); the normal
    # render's sky is saturated blue.
    local SKY_SAT
    SKY_SAT=$(python3 - "$DEV/${PREFIX}-${MODE}-debugview_frames" <<'PYEOF'
import glob, sys
import numpy as np
from PIL import Image
fs = sorted(glob.glob(sys.argv[1] + "/f_*.png"))
if not fs:
    print("999"); raise SystemExit
a = np.asarray(Image.open(fs[len(fs)//2]).convert("RGB"), dtype=float)
sky = a[: a.shape[0] // 5, :, :]
sat = (sky.max(axis=2) - sky.min(axis=2)).mean()
print(f"{sat:.1f}")
PYEOF
)
    echo "  debugview sky-saturation ${PREFIX}-${MODE}: ${SKY_SAT} (term view expects <20)"
    case "$SKY_SAT" in
      99*|"") echo "  DEBUGVIEW INVALID (no frames) — retry $TRY";;
      *) if python3 -c "import sys;sys.exit(0 if float('$SKY_SAT')<20.0 else 1)"; then break
         else echo "  DEBUGVIEW SUSPECT (saturated sky = normal render raced in) — retry $TRY"; sleep 3; fi;;
    esac
  done
  MARK=$(wc -l < "$LOG" 2>/dev/null || echo 0)
  $ADB shell "setprop debug.opengoal.ao.debug 0" >/dev/null 2>&1
  wait_override debug 0 "$MARK"; }

if [ "$VANT" = fpsmatrix ]; then
  say "FPS MATRIX @ $CONT $POS — 10 combos, AOPERF harvest"
  LOG="$DEV/ao-fpsmatrix.log"
  ao_clear
  # cost curve must be measured at locked full res, grass off (same protocol as the A/Bs).
  seed_capture_protocol
  boot_warp_retry "$LOG" || { echo "[ao-capture FAIL] fpsmatrix boot"; exit 1; }
  : > "$DEV/ao-fpsmatrix-results.txt"
  for combo in "0 1 1 off" "1 0 1 ssao-low" "1 1 1 ssao-med" "1 2 1 ssao-high" \
               "2 0 1 hbao-low" "2 1 1 hbao-med" "2 2 1 hbao-high" \
               "3 0 1 gtao-low" "3 1 1 gtao-med" "3 2 1 gtao-high"; do
    set -- $combo; M=$1; Q=$2; S=$3; TAG=$4
    MARK=$(wc -l < "$LOG" 2>/dev/null || echo 0)
    ao_force_confirmed "$M" "$Q" "$S"
    # AOPERF fires every 5 s wall time. Count only lines FRESHER than the flip (boot/disk
    # settings can pre-seed identical mode/quality pairs); 3 fresh lines ≈ 15 s, EMA
    # (time-constant ~2.5 s) converged.
    t0=$(date +%s); got=0
    while [ $(( $(date +%s)-t0 )) -lt 120 ]; do
      got=$(tail -n "+$((MARK+1))" "$LOG" 2>/dev/null | grep -ac "AOPERF mode=$M quality=$Q strength=$S"); got=${got:-0}
      [ "$got" -ge 3 ] && break
      sleep 5
    done
    LINE=$(tail -n "+$((MARK+1))" "$LOG" | grep -a "AOPERF mode=$M quality=$Q strength=$S" | tail -1 | tr -d '\r')
    echo "$TAG :: ${LINE:-NO-AOPERF-LINE}" | tee -a "$DEV/ao-fpsmatrix-results.txt"
  done
  ao_clear
  $ADB shell am force-stop $PKG >/dev/null 2>&1
  kill "$(cat /tmp/ao_lc.pid 2>/dev/null)" 2>/dev/null || true
  say "DONE fpsmatrix — $DEV/ao-fpsmatrix-results.txt"
  exit 0
fi

if [ "$VANT" = strengthgrid ]; then
  # 3 modes x 3 strengths @ training (quality High=2 throughout). closing round v2:
  # PER-TRIO BOOTS (TOD measurement control). The single-boot 13-segment run drifted
  # ~40 min into the in-game sunset (off-bracket luma 98.7 -> 52.8); the golden-rule
  # composite's (1-dst) ambient weight grows as the scene dims, so the late trios (gtao)
  # were measured in an amplified regime the daylight caps were never calibrated for.
  # Each trio now boots FRESH — the warp lands at the same deterministic early-boot TOD —
  # and brackets itself with its own off-pre/off-post from the SAME boot (an off model
  # must never span a boot boundary: game TOD resets there). NO debugview loop (strength
  # changes the composite weight, not the raw AO term).
  say "STRENGTH GRID @ $CONT $POS — 3 modes x 3 strengths (weaker/default/stronger), PER-TRIO BOOTS + off brackets"
  rm -f "$DEV"/device-ao-strengthgrid-*.mp4
  rm -rf "$DEV"/device-ao-strengthgrid-*_frames
  seed_capture_protocol
  for TRIO in "1 ssao" "2 hbao" "3 gtao"; do
    set -- $TRIO; TM=$1; MNAME=$2
    LOG="$DEV/ao-strengthgrid-$MNAME.log"
    ao_clear
    boot_warp_retry "$LOG" || { echo "[ao-capture FAIL] strengthgrid boot ($MNAME)"; exit 1; }

    # Walk-settle: park the follow cam BEHIND Jak deterministically (see vantage branch).
    $ADB shell setprop debug.opengoal.cpad_inject up >/dev/null 2>&1; sleep 1.5
    $ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1; sleep 12

    for combo in "0 2 1 ${MNAME}-off-pre" "$TM 2 0 ${MNAME}-weak" "$TM 2 1 ${MNAME}-def" \
                 "$TM 2 2 ${MNAME}-strong" "0 2 1 ${MNAME}-off-post"; do
      set -- $combo; M=$1; Q=$2; S=$3; TAG=$4
      ao_force_confirmed "$M" "$Q" "$S"
      RECMARK=$(wc -l < "$LOG" 2>/dev/null || echo 0)
      rec "device-ao-strengthgrid-${TAG}" 10
      FRDIR="$DEV/device-ao-strengthgrid-${TAG}_frames"
      GOODC=0; BADC=0; BR0=$(date +%s)
      while [ $(( $(date +%s)-BR0 )) -lt 45 ]; do
        tail -n "+$((RECMARK+1))" "$LOG" | grep -a "AOPERF" | tr -d '\r' > "$FRDIR/aoperf-bracket.txt" || true
        GOODC=$(grep -ac "AOPERF mode=$M quality=$Q strength=$S" "$FRDIR/aoperf-bracket.txt" 2>/dev/null); GOODC=${GOODC:-0}
        BADC=$(grep -a "AOPERF" "$FRDIR/aoperf-bracket.txt" 2>/dev/null | grep -acv "mode=$M quality=$Q strength=$S"); BADC=${BADC:-0}
        { [ "$GOODC" -ge 1 ] || [ "$BADC" -ge 1 ]; } && break
        sleep 5
      done
      if [ "${GOODC:-0}" -ge 1 ] && [ "${BADC:-0}" -eq 0 ]; then
        echo "  aoperf-bracket OK ${TAG}: $GOODC matching line(s)"
      else
        echo "  AOPERF-BRACKET FAIL ${TAG}: good=$GOODC bad=$BADC — SEGMENT INVALID, deleting frames"
        rm -f "$FRDIR"/f_*.png
      fi
    done
    $ADB shell am force-stop $PKG >/dev/null 2>&1
    kill "$(cat /tmp/ao_lc.pid 2>/dev/null)" 2>/dev/null || true
  done
  ao_clear
  say "DONE strengthgrid — frames under $DEV/device-ao-strengthgrid-*_frames/"
  exit 0
fi

say "VANTAGE $VANT ($CONT @ $POS) — AO A/B, INTERLEAVED off brackets (TOD-drift compensated)"
LOG="$DEV/ao-${VANT}.log"
ao_clear
seed_capture_protocol
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
for combo in "0 1 1 off-a" "1 2 1 ssao" "0 1 1 off-b" "2 2 1 hbao" "0 1 1 off-c" "3 2 1 gtao" "0 1 1 off-d"; do
  set -- $combo; M=$1; Q=$2; S=$3; TAG=$4
  ao_force_confirmed "$M" "$Q" "$S"
  RECMARK=$(wc -l < "$LOG" 2>/dev/null || echo 0)
  rec "device-ao-${VANT}-${TAG}" 10
  # AOPERF bracket (supervisor invalidation fix): every AOPERF line logged DURING the
  # recording window must match the forced pair, and there must be at least one (10 s
  # window vs 5 s cadence). Saved next to the frames like the focus bracket; a mismatch
  # (owner touching settings mid-run) deletes the segment — honest absence over fiction.
  FRDIR="$DEV/device-ao-${VANT}-${TAG}_frames"
  # The bracket must WAIT for its evidence: AOPERF is 5 s wall-time, but logcat delivery
  # lags and heavy AO frames (GTAO ~10 fps) stall the frame loop, so an instant sample
  # can see ZERO lines for a healthy segment (beach/gtao run-2 flake). The forced pair is
  # already aoperf-confirmed BEFORE rec; here we poll up to 45 s for at least one fresh
  # line since RECMARK — any NON-matching line in the same span is still contamination.
  # NB: grep -c prints "0" AND exits 1 on zero matches — `|| echo 0` would emit a second
  # line ("0\n0") and break the integer tests (feedback_validator_pipefail_grep_q).
  GOODC=0; BADC=0; BR0=$(date +%s)
  while [ $(( $(date +%s)-BR0 )) -lt 45 ]; do
    tail -n "+$((RECMARK+1))" "$LOG" | grep -a "AOPERF" | tr -d '\r' > "$FRDIR/aoperf-bracket.txt" || true
    GOODC=$(grep -ac "AOPERF mode=$M quality=$Q strength=$S" "$FRDIR/aoperf-bracket.txt" 2>/dev/null); GOODC=${GOODC:-0}
    BADC=$(grep -a "AOPERF" "$FRDIR/aoperf-bracket.txt" 2>/dev/null | grep -acv "mode=$M quality=$Q strength=$S"); BADC=${BADC:-0}
    { [ "$GOODC" -ge 1 ] || [ "$BADC" -ge 1 ]; } && break
    sleep 5
  done
  if [ "${GOODC:-0}" -ge 1 ] && [ "${BADC:-0}" -eq 0 ]; then
    echo "  aoperf-bracket OK ${TAG}: $GOODC matching line(s)"
  else
    echo "  AOPERF-BRACKET FAIL ${TAG}: good=$GOODC bad=$BADC — SEGMENT INVALID, deleting frames"
    rm -f "$FRDIR"/f_*.png
  fi
done
# debug-view (raw AO term) segments per mode, AFTER the A/B sequence (not luminance evidence)
for M in 1 2 3; do
  ao_force_confirmed "$M" 2 1
  rec_debugview "device-ao-${VANT}" "$M"
done
ao_clear
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/ao_lc.pid 2>/dev/null)" 2>/dev/null || true
say "DONE $VANT — frames under $DEV/device-ao-${VANT}-*_frames/"
