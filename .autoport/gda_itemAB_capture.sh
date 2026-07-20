#!/usr/bin/env bash
# gda_itemAB_capture.sh — owner playtest #2 proofs.
#   sweep TAG SMOOTH   : tod.fast (18000x ~24s/cycle) day->night->day sweep at a FIXED, STATIC camera.
#                        SMOOTH = debug.opengoal.rt.todsmooth ('' default 0.10 = fix; '0' = raw stepped =
#                        the before). Records a full cycle so the frame-to-frame luminance step can be
#                        measured (ITEM B). NO stick input during record => camera static => the only
#                        frame-to-frame change is the LIGHTING.
#   still TAG          : tod.hour-pinned still with a slow look-around, for ITEM A (contrast / mood-match).
#                        Env: RTL_HOUR, RTL_LIGHT, RTL_INTENSITY, RTL_AMBIENTMODEL.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-directional-ambient/device; mkdir -p "$OUT"
PROOF="$OUT/device_proof.txt"
POS="${RTL_POS:--112.0 42.0 205.0}"     # owner sage-wall vantage (stone building + hut geometry in frame)
HOUR="${RTL_HOUR:-8}"
LIGHT="${RTL_LIGHT:-1}"
adb(){ "$ADB" -s "$ANDROID_SERIAL" "$@"; }
stick(){ adb shell "setprop debug.opengoal.cpad_inject '$1'" </dev/null; }
focus(){ adb shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

set_common_props(){
  adb shell "setprop debug.opengoal.rt.light '$LIGHT'" </dev/null
  adb shell "setprop debug.opengoal.rt.ambient 1" </dev/null
  # OUT-OF-BOX: clear the ambient model/contrast/strength overrides => shipped GOAL defaults (SH,0.2,1.0).
  adb shell "setprop debug.opengoal.rt.ambientmodel '${RTL_AMBIENTMODEL:-}'" </dev/null
  adb shell "setprop debug.opengoal.rt.ambientcontrast ''" </dev/null
  adb shell "setprop debug.opengoal.rt.ambientstrength ''" </dev/null
  adb shell "setprop debug.opengoal.rt.flatnormal 0" </dev/null
  # ITEM A: sun intensity override ('' => shipped 1.5). ITEM B: todsmooth override + green-moon intensity.
  adb shell "setprop debug.opengoal.rt.intensity '${RTL_INTENSITY:-}'" </dev/null
  adb shell "setprop debug.opengoal.rt.todsmooth '${RTL_TODSMOOTH:-}'" </dev/null
  adb shell "setprop debug.opengoal.rt.moonintensity '${RTL_MOONINTENSITY:-}'" </dev/null
  adb shell "setprop debug.opengoal.pbr.shadowmap ${RTL_SHADOWMAP:-1}" </dev/null
  adb shell "setprop debug.opengoal.ao.force_mode 0" </dev/null
  adb shell "setprop debug.opengoal.pbr.debug ''" </dev/null
  # NB: rt.sunelev is CLEARED for the sweep so the REAL sky-sun elevation drives the day/night fade.
  adb shell "setprop debug.opengoal.rt.sunelev '${RTL_SUNELEV:-}'" </dev/null
}

warp_boot(){ # $1 LOG ; uses $MODE (sweep|still) to pick tod.fast vs tod.hour ; sets ok
  local LOG="$1" TRY t0
  ok=0
  for TRY in 1 2 3; do
    adb shell am force-stop $PKG </dev/null; sleep 2
    stick neutral
    set_common_props
    if [ "$MODE" = sweep ]; then
      adb shell "setprop debug.opengoal.tod.hour ''" </dev/null
      adb shell "setprop debug.opengoal.tod.fast 1" </dev/null       # 18000x continuous sweep
    else
      adb shell "setprop debug.opengoal.tod.fast ''" </dev/null
      adb shell "setprop debug.opengoal.tod.hour '$HOUR'" </dev/null  # pin hour (fractional ok)
    fi
    adb shell setprop debug.opengoal.level.warp village1-hut </dev/null
    adb shell "setprop debug.opengoal.level.warp.pos '$POS'" </dev/null
    adb logcat -b all -c </dev/null || true
    kill "$(cat /tmp/gda_ab_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( adb logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/gda_ab_lc.pid )
    adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 </dev/null
    t0=$(date +%s)
    while [ $(( $(date +%s)-t0 )) -lt 300 ]; do
      grep -qa 'LEVEL-WARP-SPAWN name=village1-hut' "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG' "$LOG" && break
      sleep 3
    done
    echo "  try#$TRY warp_ok=$ok $(focus)"
    [ "$ok" = 1 ] && break
  done
}

record(){ # $1 TAG $2 SECONDS $3 FPS
  local TAG="$1" SECS="$2" FPS="$3"
  adb shell rm -f /sdcard/gda_$TAG.mp4 </dev/null
  adb shell screenrecord --time-limit "$SECS" --bit-rate 16000000 /sdcard/gda_$TAG.mp4 </dev/null
  sleep 1
  adb pull /sdcard/gda_$TAG.mp4 "$OUT/gda_$TAG.mp4" >/dev/null
  adb shell rm -f /sdcard/gda_$TAG.mp4 </dev/null
  mkdir -p "$OUT/frames_$TAG"; rm -f "$OUT/frames_$TAG"/*.png
  ffmpeg -y -loglevel error -i "$OUT/gda_$TAG.mp4" -vf fps=$FPS "$OUT/frames_$TAG/f_%03d.png"
}

case "${1:?stage sweep|still}" in
sweep)
  MODE=sweep; TAG="${2:?tag}"; export RTL_TODSMOOTH="${3:-}"; LOG="$OUT/logcat_$TAG.log"
  warp_boot "$LOG"
  [ "$ok" = 1 ] || { echo "[gda-ab-cap FAIL] warp never spawned ($TAG)"; exit 1; }
  sleep 12                       # let the follow-cam settle; then hold NEUTRAL (static camera)
  FOCUS_LINE="$(focus)"
  stick neutral
  record "$TAG" 36 12            # >1 full 24s cycle; 12 fps => dense frame-to-frame delta
  sleep 2; kill "$(cat /tmp/gda_ab_lc.pid 2>/dev/null)" 2>/dev/null || true
  adb shell am force-stop $PKG </dev/null
  { echo "=== sweep $TAG $(date -Is) ==="; echo "focus-at-record: $FOCUS_LINE";
    echo "tod.fast=1 (18000x) static-cam pos=$POS rt.light=$LIGHT todsmooth='${3:-def(0.10)}' ambmodel='${RTL_AMBIENTMODEL:-def-SH}'";
    grep -aE 'TOD-FAST ratio' "$LOG" | head -1;
    echo "frames=$(ls "$OUT/frames_$TAG" 2>/dev/null | wc -l)"; echo; } >> "$PROOF"
  echo "  sweep $TAG done: frames=$(ls "$OUT/frames_$TAG" | wc -l)"
  ;;
still)
  MODE=still; TAG="${2:?tag}"; LOG="$OUT/logcat_$TAG.log"
  warp_boot "$LOG"
  [ "$ok" = 1 ] || { echo "[gda-ab-cap FAIL] warp never spawned ($TAG)"; exit 1; }
  sleep 12
  FOCUS_LINE="$(focus)"
  ( sleep 3; for _ in $(seq 1 8); do stick "rx=180"; sleep 2; done; stick "rx=127" ) & KICK=$!
  record "$TAG" 20 2
  wait $KICK 2>/dev/null || true; stick "rx=127"
  sleep 2; kill "$(cat /tmp/gda_ab_lc.pid 2>/dev/null)" 2>/dev/null || true
  adb shell am force-stop $PKG </dev/null
  { echo "=== still $TAG $(date -Is) ==="; echo "focus-at-record: $FOCUS_LINE";
    echo "tod.hour=$HOUR rt.light=$LIGHT intensity='${RTL_INTENSITY:-def(1.75)}' ambmodel='${RTL_AMBIENTMODEL:-def-SH}' pos=$POS";
    echo "frames=$(ls "$OUT/frames_$TAG" 2>/dev/null | wc -l)"; echo; } >> "$PROOF"
  echo "  still $TAG done: frames=$(ls "$OUT/frames_$TAG" | wc -l)"
  ;;
*) echo "unknown stage $1"; exit 1;;
esac
