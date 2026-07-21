#!/usr/bin/env bash
# glp2_walk_capture.sh — Grecharged-lightprobes playtest#1b: MOVING capture (AO-flicker gate).
# Same deterministic warp as glp_capture.sh, but during the screenrecord Jak WALKS forward via
# debug.opengoal.cpad_inject, so consecutive frames show the scene under camera MOVEMENT (the
# owner's flicker repro). Fixed inject timing => comparable motion across A/B runs.
# Usage: glp2_walk_capture.sh <tag> <probe> <ao_mode> <warp> <pos> <hour> [native]
#   probe 0|1 ; ao_mode 0..3 (0=Off 1=SSAO 2=HBAO 3=GTAO) ; native 0|1 (default 0 = OWNER-realistic
#   dynamic render scale ON; the quality captures use native=1 instead)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-lightprobes/device; mkdir -p "$OUT"
TAG="${1:?tag}"; PROBE="${2:-1}"; AOM="${3:-1}"
WARP="${4:-village1-hut}"; POS="${5:--112.0 42.0 205.0}"; HOUR="${6:-8}"; NATIVE="${7:-0}"
adb(){ "$ADB" -s "$ANDROID_SERIAL" "$@"; }
focus(){ adb shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }
stick(){ adb shell "setprop debug.opengoal.cpad_inject '$1'" </dev/null; }

# SUPERVISOR 2026-07-21 correction: the Redmi's battery-LEVEL reading is BOGUS (plugged 24/7 debug) —
# IGNORE it. Only device-health guard = temperature >= 45.0C -> pause to cool before loading the device.
TEMP=$(adb shell dumpsys battery </dev/null 2>/dev/null | grep -m1 -E '^  temperature' | grep -o '[0-9]*')
while [ -n "${TEMP:-}" ] && [ "$TEMP" -ge 450 ]; do
  echo "[glp2-walk] $TAG: device temp ${TEMP} (0.1C) >= 45.0C — cooling pause 180s"
  adb shell am force-stop $PKG </dev/null; sleep 180
  TEMP=$(adb shell dumpsys battery </dev/null 2>/dev/null | grep -m1 -E '^  temperature' | grep -o '[0-9]*')
done

set_props(){
  adb shell "setprop debug.opengoal.rt.light 1" </dev/null
  adb shell "setprop debug.opengoal.rt.ambient 1" </dev/null
  adb shell "setprop debug.opengoal.rt.ambientmodel ''" </dev/null
  adb shell "setprop debug.opengoal.ao.force_mode '$AOM'" </dev/null
  adb shell "setprop debug.opengoal.pbr.debug ''" </dev/null
  adb shell "setprop debug.opengoal.renderscale.native '$NATIVE'" </dev/null
  adb shell "setprop debug.opengoal.rt.probe '$PROBE'" </dev/null
  adb shell "setprop debug.opengoal.rt.probrefl 0" </dev/null
  adb shell "setprop debug.opengoal.rt.probqual 1" </dev/null
  adb shell "setprop debug.opengoal.rt.probstr ''" </dev/null
  adb shell "setprop debug.opengoal.tod.fast ''" </dev/null
  adb shell "setprop debug.opengoal.tod.hour '$HOUR'" </dev/null
}

LOG="$OUT/logcat_$TAG.log"; : > "$LOG"
ok=0
for TRY in 1 2 3; do
  adb shell am force-stop $PKG </dev/null; sleep 2
  stick neutral
  set_props
  adb shell setprop debug.opengoal.level.warp "$WARP" </dev/null
  adb shell "setprop debug.opengoal.level.warp.pos '$POS'" </dev/null
  adb logcat -c </dev/null 2>/dev/null   # drop buffer history: stale lines from the PREVIOUS boot
  ( adb logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
      | grep --line-buffered -aE 'LEVEL-WARP-SPAWN|lightprobe|A35-RENDER frame=|Fatal signal|signal [0-9]+ \(SIG' >> "$LOG" ) 2>/dev/null &
  LCP=$!; echo $LCP > /tmp/glp2_lc.pid
  adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 </dev/null || true
  t0=$(date +%s)
  while [ $(( $(date +%s) - t0 )) -lt 90 ]; do
    grep -aqE 'Fatal signal (11|6|4)|signal (11|6|4) \(SIG' "$LOG" && { echo "  CRASH try $TRY"; break; }
    grep -aqE 'LEVEL-WARP-SPAWN' "$LOG" && { ok=1; break; }
    sleep 3
  done
  [ "$ok" = 1 ] && break
  kill "$LCP" 2>/dev/null || true
done
[ "$ok" = 1 ] || { echo "[glp2-walk FAIL] warp never spawned ($TAG)"; tail -5 "$LOG"; exit 1; }

sleep 32   # past ND logo + load; every recorded frame is gameplay
FOCUS_LINE="$(focus)"
adb shell rm -f /sdcard/glp2_$TAG.mp4 </dev/null
# 16s record: 3s static, then walk forward 5s, pause 2s, walk 4s, neutral (deterministic protocol)
( adb shell screenrecord --time-limit 16 --bit-rate 12000000 /sdcard/glp2_$TAG.mp4 </dev/null ) &
RECP=$!
sleep 3;  stick ly=16
sleep 5;  stick neutral
sleep 2;  stick ly=16
sleep 4;  stick neutral
wait $RECP 2>/dev/null || true
sleep 1
adb pull /sdcard/glp2_$TAG.mp4 "$OUT/glp2_$TAG.mp4" >/dev/null 2>&1
adb shell rm -f /sdcard/glp2_$TAG.mp4 </dev/null
mkdir -p "$OUT/frames_$TAG"; rm -f "$OUT/frames_$TAG"/*.png
# 10 fps: dense enough for frame-to-frame flicker deltas, small enough on disk
ffmpeg -y -loglevel error -i "$OUT/glp2_$TAG.mp4" -vf fps=10 "$OUT/frames_$TAG/f_%03d.png" 2>/dev/null
kill "$(cat /tmp/glp2_lc.pid 2>/dev/null)" 2>/dev/null || true
stick neutral
adb shell am force-stop $PKG </dev/null
NF=$(ls "$OUT/frames_$TAG" 2>/dev/null | wc -l)
echo "[glp2-walk] $TAG done: probe=$PROBE ao=$AOM warp='$WARP' pos='$POS' hour=$HOUR native=$NATIVE frames=$NF"
# PROP/SETTINGS CHECKLIST (owner 2026-07-21 force-vanilla mandate): recharged flag state.
echo "  [checklist] settings.ini: $(adb shell grep -E 'recharged|pbr-materials|load-custom|ambient-occlusion|extra-hud|enhanced-models' /storage/emulated/0/OpenGOAL/jak1/settings.ini </dev/null 2>/dev/null | tr -d '\r' | tr '\n' ';' )"
CKP=""
for p in rt.light rt.ambient rt.probe ao.force_mode renderscale.native render.scale; do
  CKP="$CKP $p=$(adb shell getprop debug.opengoal.$p </dev/null 2>/dev/null | tr -d '\r')"
done
echo "  [checklist] props:$CKP"
echo "  focus=$FOCUS_LINE"
echo "  spawn=$(grep -aE 'LEVEL-WARP-SPAWN' "$LOG" | tail -1 | tr -d '\r')"
echo "  probe-load=$(grep -aE 'lightprobe' "$LOG" | tail -1 | tr -d '\r')"
