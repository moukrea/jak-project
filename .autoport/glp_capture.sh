#!/usr/bin/env bash
# glp_capture.sh — Grecharged-lightprobes device A/B captures (deterministic warp, STATIC camera so the
# ONLY difference between a pair is the probe prop). Usage: glp_capture.sh <tag> <probe> <refl> <qual> <warp> <pos> <hour>
#   probe/refl 0|1 ; qual 0|1 ; warp e.g. village1-hut ; pos "X Y Z" meters ; hour 0..24
# Records ~12s static, pulls the mp4, extracts a mid frame. Then use glp_measure.py to compare pairs.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-lightprobes/device; mkdir -p "$OUT"
TAG="${1:?tag}"; PROBE="${2:-1}"; REFL="${3:-0}"; QUAL="${4:-1}"
WARP="${5:-village1-hut}"; POS="${6:--112.0 42.0 205.0}"; HOUR="${7:-8}"
adb(){ "$ADB" -s "$ANDROID_SERIAL" "$@"; }
focus(){ adb shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

set_props(){
  adb shell "setprop debug.opengoal.rt.light 1" </dev/null
  adb shell "setprop debug.opengoal.rt.ambient 1" </dev/null
  adb shell "setprop debug.opengoal.rt.ambientmodel ''" </dev/null
  adb shell "setprop debug.opengoal.ao.force_mode 0" </dev/null
  adb shell "setprop debug.opengoal.pbr.debug ''" </dev/null
  adb shell "setprop debug.opengoal.renderscale.native 1" </dev/null   # FULL-RES eval, render scaling OFF
  adb shell "setprop debug.opengoal.rt.probe '$PROBE'" </dev/null
  adb shell "setprop debug.opengoal.rt.probrefl '$REFL'" </dev/null
  adb shell "setprop debug.opengoal.rt.probqual '$QUAL'" </dev/null
  adb shell "setprop debug.opengoal.rt.probstr ''" </dev/null
  adb shell "setprop debug.opengoal.tod.fast ''" </dev/null
  adb shell "setprop debug.opengoal.tod.hour '$HOUR'" </dev/null
}

LOG="$OUT/logcat_$TAG.log"; : > "$LOG"
ok=0
for TRY in 1 2 3; do
  adb shell am force-stop $PKG </dev/null; sleep 2
  set_props
  adb shell setprop debug.opengoal.level.warp "$WARP" </dev/null
  adb shell "setprop debug.opengoal.level.warp.pos '$POS'" </dev/null
  ( adb logcat -v threadtime GK_STDOUT:I GK_STDERR:I opengoal-gk:I '*:S' \
      | grep --line-buffered -aE 'LEVEL-WARP-SPAWN|lightprobe|A35-RENDER frame=|Fatal signal|signal [0-9]+ \(SIG' >> "$LOG" ) 2>/dev/null &
  LCP=$!; echo $LCP > /tmp/glp_lc.pid
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
[ "$ok" = 1 ] || { echo "[glp-cap FAIL] warp never spawned ($TAG)"; tail -5 "$LOG"; exit 1; }

# the warp SPAWN log fires during load; the actual in-game render only appears ~20-25s later (ND logo
# + level load). Wait well past that so EVERY recorded frame is gameplay (not the ND-logo splash).
sleep 32
FOCUS_LINE="$(focus)"
adb shell rm -f /sdcard/glp_$TAG.mp4 </dev/null
adb shell screenrecord --time-limit 15 --bit-rate 12000000 /sdcard/glp_$TAG.mp4 </dev/null
sleep 1
adb pull /sdcard/glp_$TAG.mp4 "$OUT/glp_$TAG.mp4" >/dev/null 2>&1
adb shell rm -f /sdcard/glp_$TAG.mp4 </dev/null
mkdir -p "$OUT/frames_$TAG"; rm -f "$OUT/frames_$TAG"/*.png
ffmpeg -y -loglevel error -i "$OUT/glp_$TAG.mp4" -vf fps=2 "$OUT/frames_$TAG/f_%03d.png" 2>/dev/null
kill "$(cat /tmp/glp_lc.pid 2>/dev/null)" 2>/dev/null || true
adb shell am force-stop $PKG </dev/null
NF=$(ls "$OUT/frames_$TAG" 2>/dev/null | wc -l)
echo "[glp-cap] $TAG done: probe=$PROBE refl=$REFL qual=$QUAL warp='$WARP' pos='$POS' hour=$HOUR frames=$NF"
echo "  focus=$FOCUS_LINE"
echo "  spawn=$(grep -aE 'LEVEL-WARP-SPAWN' "$LOG" | tail -1 | tr -d '\r')"
echo "  probe-load=$(grep -aE 'lightprobe' "$LOG" | tail -1 | tr -d '\r')"
