#!/usr/bin/env bash
# rtl2_device_capture.sh — Grecharged-realtime-lighting ROUND 2 device proof captures.
# Extends rtl_device_capture.sh with the new Shadow Quality (rt.shadowres) + Shadow Distance
# (rt.shadowdist) props, and adds a STATIC "shot" stage (camera held still -> clean, matched
# stills for A/B pairs). Writes a representative PNG directly into device/ (validator wants a
# .png there) plus the frames_<TAG>/ set + the mp4. Drives everything via debug props (headless,
# no menu). Android props persist across force-stop, re-set each boot.
#
# Stages:
#   shot  TAG   warp -> settle 12s -> hold camera still -> record 6s -> fps=1 stills (A/B use)
#   orbit TAG   warp -> continuous camera move + walk strokes 45s -> fps=5 (pinned + no-pop)
#
# Env knobs (all optional; defaults = owner sage-wall, h8, sun-only, shadow ON):
#   RTL_POS   "x y z"   default -112.0 42.0 205.0     RTL_HOUR  0-23  default 8
#   RTL_LIGHT 0|1 default 1   RTL_BAKED 0|1 default 0   RTL_SHADOW 0|1 default 1
#   RTL_RES   texels    default (unset -> setting default 1024)
#   RTL_DIST  meters    default (unset -> setting default 40)
#   RTL_INTENSITY       default (unset -> shader default 1.5)
#   RTL_DEBUG_MODE      pbr.debug viz (e.g. 12 = shadow factor); default '' (real render)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-realtime-lighting/device; mkdir -p "$OUT"
PROOF="$OUT/device_proof_round2.txt"
POS="${RTL_POS:--112.0 42.0 205.0}"
HOUR="${RTL_HOUR:-8}"
LIGHT="${RTL_LIGHT:-1}"; BAKED="${RTL_BAKED:-0}"; SHADOW="${RTL_SHADOW:-1}"
adb(){ "$ADB" -s "$ANDROID_SERIAL" "$@"; }
stick(){ adb shell "setprop debug.opengoal.cpad_inject '$1'" </dev/null; }
focus(){ adb shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

set_feature_props(){
  adb shell "setprop debug.opengoal.rt.light '$LIGHT'" </dev/null
  adb shell "setprop debug.opengoal.rt.baked '$BAKED'" </dev/null
  adb shell "setprop debug.opengoal.pbr.shadowmap '$SHADOW'" </dev/null
  # Round-2 settings props. Empty string clears -> the C++ setting default is used.
  adb shell "setprop debug.opengoal.rt.shadowres '${RTL_RES:-}'" </dev/null
  adb shell "setprop debug.opengoal.rt.shadowdist '${RTL_DIST:-}'" </dev/null
  [ -n "${RTL_INTENSITY:-}" ] && adb shell "setprop debug.opengoal.rt.intensity '${RTL_INTENSITY}'" </dev/null
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
    kill "$(cat /tmp/rtl2_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( adb logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/rtl2_lc.pid )
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
    echo "tod=$HOUR light=$LIGHT baked=$BAKED shadow=$SHADOW res='${RTL_RES:-def}' dist='${RTL_DIST:-def}' dbg='${RTL_DEBUG_MODE:-}'"
    echo "--- crash scan (narrow sig pattern):"
    grep -aE 'signal (4|6|11) \(SIG' "$3" | head -3 || echo "  (none)"
    echo "video: $OUT/rtl2_$2.mp4 ($(stat -c %s "$OUT/rtl2_$2.mp4" 2>/dev/null)B) frames=$(ls "$OUT/frames_$2" 2>/dev/null | wc -l)"
    echo
  } >> "$PROOF"
  # Truncate the giant logcat once harvested (keeps disk sane); crash-scan already captured.
  : > "$3"
}

case "${1:?stage shot|orbit}" in
shot)
  TAG="${2:?tag}"; LOG="$OUT/logcat_$TAG.log"
  warp_boot "$LOG"
  [ "$ok" = 1 ] || { echo "[rtl2-cap FAIL] warp never spawned ($TAG)"; exit 1; }
  sleep 12
  FOCUS_LINE="$(focus)"
  # Hold the camera STILL (neutral) so A/B pairs are matched-pose.
  stick "rx=127"
  adb shell rm -f /sdcard/rtl2_$TAG.mp4 </dev/null
  adb shell screenrecord --time-limit 6 --bit-rate 16000000 /sdcard/rtl2_$TAG.mp4 </dev/null
  sleep 1
  adb pull /sdcard/rtl2_$TAG.mp4 "$OUT/rtl2_$TAG.mp4" >/dev/null
  adb shell rm -f /sdcard/rtl2_$TAG.mp4 </dev/null
  mkdir -p "$OUT/frames_$TAG"; rm -f "$OUT/frames_$TAG"/*.png
  ffmpeg -y -loglevel error -i "$OUT/rtl2_$TAG.mp4" -vf fps=1 "$OUT/frames_$TAG/f_%03d.png"
  # Representative still directly in device/ (validator wants a .png there).
  cp -f "$OUT/frames_$TAG/f_003.png" "$OUT/rtl2_$TAG.png" 2>/dev/null \
    || cp -f "$(ls "$OUT/frames_$TAG"/*.png 2>/dev/null | tail -1)" "$OUT/rtl2_$TAG.png" 2>/dev/null || true
  sleep 2; kill "$(cat /tmp/rtl2_lc.pid 2>/dev/null)" 2>/dev/null || true
  adb shell am force-stop $PKG </dev/null
  harvest shot "$TAG" "$LOG" "$FOCUS_LINE"
  echo "  shot $TAG done: frames=$(ls "$OUT/frames_$TAG" 2>/dev/null | wc -l) focus=$FOCUS_LINE"
  ;;
orbit)
  TAG="${2:?tag}"; LOG="$OUT/logcat_$TAG.log"
  warp_boot "$LOG"
  [ "$ok" = 1 ] || { echo "[rtl2-cap FAIL] warp never spawned ($TAG)"; exit 1; }
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
  adb shell rm -f /sdcard/rtl2_$TAG.mp4 </dev/null
  adb shell screenrecord --time-limit 45 --bit-rate 12000000 /sdcard/rtl2_$TAG.mp4 </dev/null
  wait $KICK 2>/dev/null || true; stick "rx=127"; sleep 1
  adb pull /sdcard/rtl2_$TAG.mp4 "$OUT/rtl2_$TAG.mp4" >/dev/null
  adb shell rm -f /sdcard/rtl2_$TAG.mp4 </dev/null
  mkdir -p "$OUT/frames_$TAG"; rm -f "$OUT/frames_$TAG"/*.png
  ffmpeg -y -loglevel error -i "$OUT/rtl2_$TAG.mp4" -vf fps=5 "$OUT/frames_$TAG/f_%03d.png"
  cp -f "$OUT/frames_$TAG/f_060.png" "$OUT/rtl2_$TAG.png" 2>/dev/null \
    || cp -f "$(ls "$OUT/frames_$TAG"/*.png 2>/dev/null | tail -1)" "$OUT/rtl2_$TAG.png" 2>/dev/null || true
  sleep 2; kill "$(cat /tmp/rtl2_lc.pid 2>/dev/null)" 2>/dev/null || true
  adb shell am force-stop $PKG </dev/null
  harvest orbit "$TAG" "$LOG" "$FOCUS_LINE"
  echo "  orbit $TAG done: frames=$(ls "$OUT/frames_$TAG" 2>/dev/null | wc -l) focus=$FOCUS_LINE"
  ;;
*) echo "unknown stage $1"; exit 1;;
esac
