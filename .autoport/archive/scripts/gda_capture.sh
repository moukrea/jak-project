#!/usr/bin/env bash
# gda_capture.sh — Grecharged-directional-ambient device proof captures.
# Adapted from rtl_device_capture.sh: drives the hemisphere directional-ambient feature via the
# rt.* debug props and writes to THIS phase's report dir. Android props persist across the
# force-stop/relaunch, so we set them once per stage.
#
# Stages:
#   still TAG   warp -> settle -> slow look-around (rx=180) 20s -> fps=2 stills
#   orbit TAG   warp -> continuous rx look ORBIT 45s -> fps=5 stills (geometry-pin proof)
#
# Env knobs (all optional):
#   RTL_POS          vantage "x y z"          default -112.0 42.0 205.0 (owner sage-wall)
#   RTL_HOUR         tod pin 0-23             default 8
#   RTL_LIGHT        0|1  rt sun lighting     default 1
#   RTL_AMBIENT      0|1  hemisphere ambient  default 1  (0 => legacy flat floor, for A/B)
#   RTL_AMBIENTSTR   float 0..0.5 strength    default (unset -> setting/default 0.2)
#   AO_MODE          -1/0/1/2/3 standalone AO default 0 (AO OFF -> proves form WITHOUT AO)
#   RTL_SHADOW       0|1  cast shadow map     default 1
#   RTL_DEBUG_MODE   pbr.debug viz mode       default '' (0=normal; 2=world normal; 12=light frac)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-directional-ambient/device; mkdir -p "$OUT"
PROOF="$OUT/device_proof.txt"
POS="${RTL_POS:--112.0 42.0 205.0}"
HOUR="${RTL_HOUR:-8}"
LIGHT="${RTL_LIGHT:-1}"; AMBIENT="${RTL_AMBIENT:-1}"; SHADOW="${RTL_SHADOW:-1}"
adb(){ "$ADB" -s "$ANDROID_SERIAL" "$@"; }
stick(){ adb shell "setprop debug.opengoal.cpad_inject '$1'" </dev/null; }
focus(){ adb shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

set_feature_props(){
  adb shell "setprop debug.opengoal.rt.light '$LIGHT'" </dev/null
  adb shell "setprop debug.opengoal.rt.ambient '$AMBIENT'" </dev/null
  [ -n "${RTL_AMBIENTSTR:-}" ] && adb shell "setprop debug.opengoal.rt.ambientstrength '${RTL_AMBIENTSTR}'" </dev/null
  # ROUND 2: ambient MODEL selector (0 HEMISPHERE, 1 SH, 2 IBL) for on-device A/B of the three tiers.
  [ -n "${RTL_AMBIENTMODEL:-}" ] && adb shell "setprop debug.opengoal.rt.ambientmodel '${RTL_AMBIENTMODEL}'" </dev/null
  # ROOT-CAUSE FIX A/B: 0 = SMOOTH per-vertex normal (the fix), 1 = force OLD flat per-face normal.
  adb shell "setprop debug.opengoal.rt.flatnormal '${RTL_FLATNORMAL:-0}'" </dev/null
  # SUN-OFF proof: force the real sun-elevation night-fade. 0 => sun fully OFF (ambient-only, the owner's
  # core gate: relief must come from the ambient alone); 1 => full day sun (deterministic golden-rule A/B).
  [ -n "${RTL_SUNELEV:-}" ] && adb shell "setprop debug.opengoal.rt.sunelev '${RTL_SUNELEV}'" </dev/null
  # AZIMUTHAL AMBIENT CONTRAST A/B: the directional spread that sculpts VERTICAL faces sun-off. 0 =>
  # flat (pre-fix look, no azimuthal form); 0.9 => default (form on rock/curved-wall faces).
  [ -n "${RTL_AMBIENTCONTRAST:-}" ] && adb shell "setprop debug.opengoal.rt.ambientcontrast '${RTL_AMBIENTCONTRAST}'" </dev/null
  # ROUND-2 CREASE A/B: crease angle (deg) for the smooth-normal weld, read at LEVEL LOAD (set before the
  # relaunch below). Default 45 (fix). 179 => reproduce round-1's unconditional weld (the masonry artifact).
  [ -n "${RTL_CREASE:-}" ] && adb shell "setprop debug.opengoal.tfrag.crease '${RTL_CREASE}'" </dev/null
  adb shell "setprop debug.opengoal.pbr.shadowmap '$SHADOW'" </dev/null
  # Standalone AO forced OFF by default => the form we show comes from the hemisphere ambient, NOT AO.
  adb shell "setprop debug.opengoal.ao.force_mode '${AO_MODE:-0}'" </dev/null
  adb shell "setprop debug.opengoal.pbr.debug '${RTL_DEBUG_MODE:-}'" </dev/null
}

warp_boot(){ # $1 LOG  -> sets ok
  local LOG="$1" TRY t0
  ok=0
  for TRY in 1 2 3; do
    adb shell am force-stop $PKG </dev/null; sleep 2
    stick neutral
    set_feature_props
    adb shell "setprop debug.opengoal.tod.hour '$HOUR'" </dev/null
    adb shell "setprop debug.opengoal.tod.fast ''" </dev/null
    adb shell setprop debug.opengoal.level.warp village1-hut </dev/null
    adb shell "setprop debug.opengoal.level.warp.pos '$POS'" </dev/null
    adb logcat -b all -c </dev/null || true
    kill "$(cat /tmp/gda_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( adb logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/gda_lc.pid )
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

harvest(){ # $1 stage $2 TAG $3 LOG $4 FOCUS
  { echo "=== $1 $2 $(date -Is) ==="
    echo "focus-at-record: $4"
    echo "warp: village1-hut pos=$POS"
    echo "tod-hour: $HOUR rt.light=$LIGHT rt.ambient=$AMBIENT ao.force_mode='${AO_MODE:-0}' pbr.shadowmap=$SHADOW debug='${RTL_DEBUG_MODE:-}' ambstr='${RTL_AMBIENTSTR:-def}' flatnormal='${RTL_FLATNORMAL:-0}' ambmodel='${RTL_AMBIENTMODEL:-def}'"
    echo "--- crash scan (narrow sig pattern):"
    grep -aE 'signal (4|6|11) \(SIG' "$3" | head -3 || true
    echo "video: $OUT/gda_$2.mp4 ($(stat -c %s "$OUT/gda_$2.mp4" 2>/dev/null)B) frames=$(ls "$OUT/frames_$2" 2>/dev/null | wc -l)"
    echo
  } >> "$PROOF"
}

case "${1:?stage still|orbit}" in
still)
  TAG="${2:?tag}"; LOG="$OUT/logcat_$TAG.log"
  warp_boot "$LOG"
  [ "$ok" = 1 ] || { echo "[gda-cap FAIL] warp never spawned ($TAG)"; exit 1; }
  sleep 12
  FOCUS_LINE="$(focus)"
  ( sleep 3; for _ in $(seq 1 8); do stick "rx=180"; sleep 2; done; stick "rx=127" ) &
  KICK=$!
  adb shell rm -f /sdcard/gda_$TAG.mp4 </dev/null
  adb shell screenrecord --time-limit 20 --bit-rate 12000000 /sdcard/gda_$TAG.mp4 </dev/null
  wait $KICK 2>/dev/null || true; stick "rx=127"; sleep 1
  adb pull /sdcard/gda_$TAG.mp4 "$OUT/gda_$TAG.mp4" >/dev/null
  adb shell rm -f /sdcard/gda_$TAG.mp4 </dev/null
  mkdir -p "$OUT/frames_$TAG"; rm -f "$OUT/frames_$TAG"/*.png
  ffmpeg -y -loglevel error -i "$OUT/gda_$TAG.mp4" -vf fps=2 "$OUT/frames_$TAG/f_%03d.png"
  sleep 2; kill "$(cat /tmp/gda_lc.pid 2>/dev/null)" 2>/dev/null || true
  adb shell am force-stop $PKG </dev/null
  harvest still "$TAG" "$LOG" "$FOCUS_LINE"
  echo "  still $TAG done: frames=$(ls "$OUT/frames_$TAG" | wc -l)"
  ;;
orbit)
  TAG="${2:?tag}"; LOG="$OUT/logcat_$TAG.log"
  warp_boot "$LOG"
  [ "$ok" = 1 ] || { echo "[gda-cap FAIL] warp never spawned ($TAG)"; exit 1; }
  sleep 12
  FOCUS_LINE="$(focus)"
  ( sleep 4
    for _ in $(seq 1 15); do
      stick "rx=180"; sleep 1.5
      stick "lx=95";  sleep 0.6
      stick "rx=180"; sleep 1.5
      stick "lx=160"; sleep 0.6
    done
    stick "rx=127" ) &
  KICK=$!
  adb shell rm -f /sdcard/gda_$TAG.mp4 </dev/null
  adb shell screenrecord --time-limit 45 --bit-rate 12000000 /sdcard/gda_$TAG.mp4 </dev/null
  wait $KICK 2>/dev/null || true; stick "rx=127"; sleep 1
  adb pull /sdcard/gda_$TAG.mp4 "$OUT/gda_$TAG.mp4" >/dev/null
  adb shell rm -f /sdcard/gda_$TAG.mp4 </dev/null
  mkdir -p "$OUT/frames_$TAG"; rm -f "$OUT/frames_$TAG"/*.png
  ffmpeg -y -loglevel error -i "$OUT/gda_$TAG.mp4" -vf fps=5 "$OUT/frames_$TAG/f_%03d.png"
  sleep 2; kill "$(cat /tmp/gda_lc.pid 2>/dev/null)" 2>/dev/null || true
  adb shell am force-stop $PKG </dev/null
  harvest orbit "$TAG" "$LOG" "$FOCUS_LINE"
  echo "  orbit $TAG done: frames=$(ls "$OUT/frames_$TAG" | wc -l)"
  ;;
*) echo "unknown stage $1"; exit 1;;
esac
