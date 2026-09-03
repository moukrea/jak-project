#!/usr/bin/env bash
# r3_rtl_capture.sh — Grecharged-realtime-lighting ROUND 3 device proof captures.
# Reuses the round-2 proven mechanism (warp village1-hut + pos override, tod.hour, cpad_inject,
# screenrecord + ffmpeg still extraction, focus check, narrow crash scan). Disk is tight (~5G),
# so each shot deletes its mp4+frames after extracting the single still; orbit keeps its mp4.
#
# Stages:
#   shot  TAG    warp -> settle 14s -> hold camera still -> record 5s -> extract 1 still -> del mp4/frames
#   orbit TAG    warp -> continuous camera orbit 14s -> record -> KEEP mp4, extract 1 rep still
#
# Env knobs (defaults = owner sage-hut, h8, sun-only, shadow ON):
#   RTL_POS "x y z" (default -112.0 42.0 205.0)   RTL_HOUR 0-23 (default 8)
#   RTL_LIGHT/RTL_BAKED/RTL_SHADOW 0|1            RTL_RES texels   RTL_DIST meters
#   RTL_DEBUG_MODE  pbr.debug viz (0/1/2/12)      RTL_ORBIT_SECS (default 14)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-realtime-lighting/device; mkdir -p "$OUT"
PROOF="$OUT/device_proof_round3.txt"
POS="${RTL_POS:--112.0 42.0 205.0}"
HOUR="${RTL_HOUR:-8}"
LIGHT="${RTL_LIGHT:-1}"; BAKED="${RTL_BAKED:-0}"; SHADOW="${RTL_SHADOW:-1}"
ORBIT_SECS="${RTL_ORBIT_SECS:-14}"
adb(){ "$ADB" -s "$ANDROID_SERIAL" "$@"; }
stick(){ adb shell "setprop debug.opengoal.cpad_inject '$1'" </dev/null; }
focus(){ adb shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

set_feature_props(){
  adb shell "setprop debug.opengoal.rt.light '$LIGHT'" </dev/null
  adb shell "setprop debug.opengoal.rt.baked '$BAKED'" </dev/null
  adb shell "setprop debug.opengoal.pbr.shadowmap '$SHADOW'" </dev/null
  adb shell "setprop debug.opengoal.rt.shadowres '${RTL_RES:-}'" </dev/null
  adb shell "setprop debug.opengoal.rt.shadowdist '${RTL_DIST:-}'" </dev/null
  adb shell "setprop debug.opengoal.pbr.debug '${RTL_DEBUG_MODE:-}'" </dev/null
}

warp_boot(){ # $1 LOG -> sets ok
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
    kill "$(cat /tmp/r3_lc.pid 2>/dev/null)" 2>/dev/null || true
    ( adb logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/r3_lc.pid )
    adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 </dev/null
    t0=$(date +%s)
    while [ $(( $(date +%s)-t0 )) -lt 240 ]; do
      grep -qa 'LEVEL-WARP-SPAWN name=village1-hut' "$LOG" && { ok=1; break; }
      grep -qaE 'signal (4|6|11) \(SIG' "$LOG" && break
      sleep 3
    done
    echo "  try#$TRY warp_ok=$ok $(focus)"
    [ "$ok" = 1 ] && break
  done
}

harvest(){ # $1 stage $2 TAG $3 LOG $4 FOCUS $5 keptmp4(0/1)
  { echo "=== $1 $2 $(date -Is) ==="
    echo "focus-at-record: $4"
    echo "warp: village1-hut pos=$POS"
    echo "tod=$HOUR light=$LIGHT baked=$BAKED shadow=$SHADOW res='${RTL_RES:-def}' dist='${RTL_DIST:-def}' dbg='${RTL_DEBUG_MODE:-}'"
    echo "still: $OUT/r3_$2.png ($(stat -c %s "$OUT/r3_$2.png" 2>/dev/null)B)"
    [ "$5" = 1 ] && echo "clip:  $OUT/r3_$2.mp4 ($(stat -c %s "$OUT/r3_$2.mp4" 2>/dev/null)B)"
    echo "--- crash scan (narrow sig 4/6/11 pattern):"
    grep -aE 'signal (4|6|11) \(SIG' "$3" | head -3 || echo "  (none)"
    echo
  } >> "$PROOF"
  : > "$3"   # truncate the giant logcat (crash-scan already captured)
}

case "${1:?stage shot|orbit}" in
shot)
  TAG="${2:?tag}"; LOG="$OUT/logcat_r3_$TAG.log"
  warp_boot "$LOG"
  [ "$ok" = 1 ] || { echo "[r3-cap FAIL] warp never spawned ($TAG)"; exit 1; }
  sleep 14
  FOCUS_LINE="$(focus)"
  stick "rx=127"   # hold camera still
  adb shell rm -f /sdcard/r3_$TAG.mp4 </dev/null
  adb shell screenrecord --time-limit 5 --bit-rate 16000000 /sdcard/r3_$TAG.mp4 </dev/null
  sleep 1
  adb pull /sdcard/r3_$TAG.mp4 "$OUT/r3_$TAG.mp4" >/dev/null
  adb shell rm -f /sdcard/r3_$TAG.mp4 </dev/null
  mkdir -p "$OUT/frames_r3_$TAG"; rm -f "$OUT/frames_r3_$TAG"/*.png
  ffmpeg -y -loglevel error -i "$OUT/r3_$TAG.mp4" -vf fps=1 "$OUT/frames_r3_$TAG/f_%03d.png"
  cp -f "$OUT/frames_r3_$TAG/f_003.png" "$OUT/r3_$TAG.png" 2>/dev/null \
    || cp -f "$(ls "$OUT/frames_r3_$TAG"/*.png 2>/dev/null | tail -1)" "$OUT/r3_$TAG.png" 2>/dev/null || true
  rm -rf "$OUT/frames_r3_$TAG" "$OUT/r3_$TAG.mp4"   # disk: drop intermediates for stills
  sleep 2; kill "$(cat /tmp/r3_lc.pid 2>/dev/null)" 2>/dev/null || true
  adb shell am force-stop $PKG </dev/null
  harvest shot "$TAG" "$LOG" "$FOCUS_LINE" 0
  echo "  shot $TAG done: $(stat -c %s "$OUT/r3_$TAG.png" 2>/dev/null)B focus=$FOCUS_LINE"
  ;;
orbit)
  TAG="${2:?tag}"; LOG="$OUT/logcat_r3_$TAG.log"
  warp_boot "$LOG"
  [ "$ok" = 1 ] || { echo "[r3-cap FAIL] warp never spawned ($TAG)"; exit 1; }
  sleep 14
  FOCUS_LINE="$(focus)"
  ( sleep 2
    for _ in $(seq 1 6); do
      stick "rx=180"; sleep 1.2
      stick "rx=127"; sleep 0.3
    done
    stick "rx=127" ) &
  KICK=$!
  adb shell rm -f /sdcard/r3_$TAG.mp4 </dev/null
  adb shell screenrecord --time-limit "$ORBIT_SECS" --bit-rate 10000000 /sdcard/r3_$TAG.mp4 </dev/null
  wait $KICK 2>/dev/null || true; stick "rx=127"; sleep 1
  adb pull /sdcard/r3_$TAG.mp4 "$OUT/r3_$TAG.mp4" >/dev/null
  adb shell rm -f /sdcard/r3_$TAG.mp4 </dev/null
  mkdir -p "$OUT/frames_r3_$TAG"; rm -f "$OUT/frames_r3_$TAG"/*.png
  ffmpeg -y -loglevel error -i "$OUT/r3_$TAG.mp4" -vf fps=2 "$OUT/frames_r3_$TAG/f_%03d.png"
  cp -f "$OUT/frames_r3_$TAG/f_012.png" "$OUT/r3_$TAG.png" 2>/dev/null \
    || cp -f "$(ls "$OUT/frames_r3_$TAG"/*.png 2>/dev/null | tail -1)" "$OUT/r3_$TAG.png" 2>/dev/null || true
  rm -rf "$OUT/frames_r3_$TAG"   # keep mp4, drop extracted frames
  sleep 2; kill "$(cat /tmp/r3_lc.pid 2>/dev/null)" 2>/dev/null || true
  adb shell am force-stop $PKG </dev/null
  harvest orbit "$TAG" "$LOG" "$FOCUS_LINE" 1
  echo "  orbit $TAG done: mp4=$(stat -c %s "$OUT/r3_$TAG.mp4" 2>/dev/null)B focus=$FOCUS_LINE"
  ;;
*) echo "unknown stage $1"; exit 1;;
esac
