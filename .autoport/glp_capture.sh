#!/usr/bin/env bash
# glp_capture.sh — Grecharged-lightprobes device A/B captures (deterministic warp, STATIC camera so the
# ONLY difference between a pair is the probe prop). Usage: glp_capture.sh <tag> <probe> <refl> <qual> <warp> <pos> <hour> [model]
#   probe/refl 0|1 ; qual 0|1 ; warp e.g. village1-hut ; pos "X Y Z" meters ; hour 0..24
#   model (optional, OWNER #3 unification) = 0|1|2 forces the AMBIENT MODEL fidelity tier
#   (Hemisphere/SH/IBL of the PROBE data when probes are on); '' = leave the setting default.
# Records ~12s static, pulls the mp4, extracts a mid frame. Then use glp_measure.py to compare pairs.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-lightprobes/device; mkdir -p "$OUT"
TAG="${1:?tag}"; PROBE="${2:-1}"; REFL="${3:-0}"; QUAL="${4:-1}"
WARP="${5:-village1-hut}"; POS="${6:--112.0 42.0 205.0}"; HOUR="${7:-8}"; MODEL="${8:-}"
adb(){ "$ADB" -s "$ANDROID_SERIAL" "$@"; }
focus(){ adb shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

# SUPERVISOR 2026-07-21 correction: the Redmi's battery-LEVEL reading is BOGUS (plugged 24/7 debug) —
# IGNORE it. Only device-health guard = temperature >= 45.0C -> pause to cool before loading the device.
TEMP=$(adb shell dumpsys battery </dev/null 2>/dev/null | grep -m1 -E '^  temperature' | grep -o '[0-9]*')
while [ -n "${TEMP:-}" ] && [ "$TEMP" -ge 450 ]; do
  echo "[glp-cap] $TAG: device temp ${TEMP} (0.1C) >= 45.0C — cooling pause 180s"
  adb shell am force-stop $PKG </dev/null; sleep 180
  TEMP=$(adb shell dumpsys battery </dev/null 2>/dev/null | grep -m1 -E '^  temperature' | grep -o '[0-9]*')
done

set_props(){
  adb shell "setprop debug.opengoal.rt.light 1" </dev/null
  adb shell "setprop debug.opengoal.rt.ambient 1" </dev/null
  adb shell "setprop debug.opengoal.rt.ambientmodel '$MODEL'" </dev/null
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
  adb logcat -c </dev/null 2>/dev/null   # drop buffer history: stale lines from the PREVIOUS boot
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
# static-vantage sanity: a STATIC capture must be temporally stable (good ~1-2; falling/respawn >>10).
STAB=$(python3 .autoport/glp2_measure.py flicker "$OUT/frames_$TAG" 2>/dev/null | grep -oE 'd_mean= *[0-9.]+' | grep -oE '[0-9.]+' | head -1)
SVERD="OK"; awk -v s="${STAB:-99}" 'BEGIN{exit !(s>5.0)}' && SVERD="UNSTABLE (bad vantage — falling/respawn/FX; do NOT use as A/B evidence)"
echo "[glp-cap] $TAG done: probe=$PROBE refl=$REFL qual=$QUAL model='${MODEL}' warp='$WARP' pos='$POS' hour=$HOUR frames=$NF"
echo "  focus=$FOCUS_LINE"
echo "  spawn=$(grep -aE 'LEVEL-WARP-SPAWN' "$LOG" | tail -1 | tr -d '\r')"
echo "  probe-load=$(grep -aE 'lightprobe' "$LOG" | tail -1 | tr -d '\r')"
echo "  static-stability d_mean=${STAB:-n/a} => $SVERD"
