#!/usr/bin/env bash
# rtl_device_capture.sh — Grecharged-realtime-lighting (SUN-ONLY) device proof captures.
# Reuses the proven pbr_device_capture mechanisms (warp prop, tod.hour pin, screenrecord
# ->ffmpeg, cpad orbit, focus/crash scan) but drives THIS feature via the rt.* debug props
# and writes to the realtime-lighting report dir. Android system properties persist across
# the force-stop/relaunch, so we set them once per stage.
#
# Stages:
#   still TAG   warp sage-wall -> settle -> slow look-around (rx=180) 20s -> fps=2 stills
#   orbit TAG   warp sage-wall -> continuous rx=200 camera ORBIT 45s -> fps=5 stills (pin proof)
#
# Env knobs (all optional):
#   RTL_POS   vantage "x y z"        default -112.0 42.0 205.0 (owner sage-wall)
#   RTL_HOUR  tod pin 0-23           default 8
#   RTL_LIGHT 0|1  rt sun lighting   default 1
#   RTL_BAKED 0|1  keep baked        default 0 (baked OFF = pure sun)
#   RTL_SHADOW 0|1 cast shadow map   default 0 (Stage 1: off; Stage 2: 1)
#   RTL_INTENSITY  sun intensity     default (unset -> shader default 1.5)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-realtime-lighting/device; mkdir -p "$OUT"
PROOF="$OUT/device_proof.txt"
POS="${RTL_POS:--112.0 42.0 205.0}"
HOUR="${RTL_HOUR:-8}"
LIGHT="${RTL_LIGHT:-1}"; BAKED="${RTL_BAKED:-0}"; SHADOW="${RTL_SHADOW:-0}"
adb(){ "$ADB" -s "$ANDROID_SERIAL" "$@"; }
stick(){ adb shell "setprop debug.opengoal.cpad_inject '$1'" </dev/null; }
focus(){ adb shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

set_feature_props(){
  adb shell "setprop debug.opengoal.rt.light '$LIGHT'" </dev/null
  adb shell "setprop debug.opengoal.rt.baked '$BAKED'" </dev/null
  adb shell "setprop debug.opengoal.pbr.shadowmap '$SHADOW'" </dev/null
  [ -n "${RTL_INTENSITY:-}" ] && adb shell "setprop debug.opengoal.rt.intensity '${RTL_INTENSITY}'" </dev/null
  # keep pbr-materials shader path out of the way: rt-light branch takes priority in the
  # shader regardless, but pbr.debug off ensures no viz override.
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
    kill "$(cat /tmp/rtl_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( adb logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/rtl_lc.pid )
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
    echo "tod-hour: $HOUR   rt.light=$LIGHT rt.baked=$BAKED pbr.shadowmap=$SHADOW intensity='${RTL_INTENSITY:-def}'"
    echo "--- rt-lighting boot markers:"
    grep -aiE 'realtime|rt-light|sun-only' "$3" | head -3 || true
    echo "--- crash scan (narrow sig pattern):"
    grep -aE 'signal (4|6|11) \(SIG' "$3" | head -3 || true
    echo "video: $OUT/rtl_$2.mp4 ($(stat -c %s "$OUT/rtl_$2.mp4" 2>/dev/null)B) frames=$(ls "$OUT/frames_$2" 2>/dev/null | wc -l)"
    echo
  } >> "$PROOF"
}

case "${1:?stage still|orbit}" in
still)
  TAG="${2:?tag}"; LOG="$OUT/logcat_$TAG.log"
  warp_boot "$LOG"
  [ "$ok" = 1 ] || { echo "[rtl-cap FAIL] warp never spawned ($TAG)"; exit 1; }
  sleep 12
  FOCUS_LINE="$(focus)"
  ( sleep 3; for _ in $(seq 1 8); do stick "rx=180"; sleep 2; done; stick "rx=127" ) &
  KICK=$!
  adb shell rm -f /sdcard/rtl_$TAG.mp4 </dev/null
  adb shell screenrecord --time-limit 20 --bit-rate 12000000 /sdcard/rtl_$TAG.mp4 </dev/null
  wait $KICK 2>/dev/null || true; stick "rx=127"; sleep 1
  adb pull /sdcard/rtl_$TAG.mp4 "$OUT/rtl_$TAG.mp4" >/dev/null
  adb shell rm -f /sdcard/rtl_$TAG.mp4 </dev/null
  mkdir -p "$OUT/frames_$TAG"; rm -f "$OUT/frames_$TAG"/*.png
  ffmpeg -y -loglevel error -i "$OUT/rtl_$TAG.mp4" -vf fps=2 "$OUT/frames_$TAG/f_%03d.png"
  sleep 2; kill "$(cat /tmp/rtl_lc.pid 2>/dev/null)" 2>/dev/null || true
  adb shell am force-stop $PKG </dev/null
  harvest still "$TAG" "$LOG" "$FOCUS_LINE"
  echo "  still $TAG done: frames=$(ls "$OUT/frames_$TAG" | wc -l)"
  ;;
orbit)
  TAG="${2:?tag}"; LOG="$OUT/logcat_$TAG.log"
  warp_boot "$LOG"
  [ "$ok" = 1 ] || { echo "[rtl-cap FAIL] warp never spawned ($TAG)"; exit 1; }
  sleep 12
  FOCUS_LINE="$(focus)"
  # Camera move: gentle continuous rx look (rx=180 works; rx=200 saturated/no-op) INTERLEAVED
  # with short walk strokes so the follow-cam is dragged through many world angles around
  # Jak — proves the lit/dark sides + cast shadow stay PINNED to geometry (camera-independent).
  ( sleep 4
    for _ in $(seq 1 15); do
      stick "rx=180"; sleep 1.5
      stick "lx=95";  sleep 0.6
      stick "rx=180"; sleep 1.5
      stick "lx=160"; sleep 0.6
    done
    stick "rx=127" ) &
  KICK=$!
  adb shell rm -f /sdcard/rtl_$TAG.mp4 </dev/null
  adb shell screenrecord --time-limit 45 --bit-rate 12000000 /sdcard/rtl_$TAG.mp4 </dev/null
  wait $KICK 2>/dev/null || true; stick "rx=127"; sleep 1
  adb pull /sdcard/rtl_$TAG.mp4 "$OUT/rtl_$TAG.mp4" >/dev/null
  adb shell rm -f /sdcard/rtl_$TAG.mp4 </dev/null
  mkdir -p "$OUT/frames_$TAG"; rm -f "$OUT/frames_$TAG"/*.png
  ffmpeg -y -loglevel error -i "$OUT/rtl_$TAG.mp4" -vf fps=5 "$OUT/frames_$TAG/f_%03d.png"
  sleep 2; kill "$(cat /tmp/rtl_lc.pid 2>/dev/null)" 2>/dev/null || true
  adb shell am force-stop $PKG </dev/null
  harvest orbit "$TAG" "$LOG" "$FOCUS_LINE"
  echo "  orbit $TAG done: frames=$(ls "$OUT/frames_$TAG" | wc -l)"
  ;;
*) echo "unknown stage $1"; exit 1;;
esac
