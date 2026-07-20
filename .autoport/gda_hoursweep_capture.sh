#!/usr/bin/env bash
# gda_hoursweep_capture.sh — OWNER PLAYTEST #4, attempt-10 FAIR per-channel handoff measurement.
#
# WHY: the tod.fast 18000x sweep advances the sun ~12-25 game-min PER RENDERED FRAME, so the moving CAST
# SHADOW sweeps ~a whole structure between frames => a big per-channel step that is DYNAMIC-SHADOW MOTION
# (present for the yellow day-sun too, requested by the owner in item 1), NOT the yellow<->green lighting-
# REGIME COLOUR handoff the owner calls "brutal". To measure the COLOUR/intensity crossfade the owner means,
# we PIN the game hour (tod.hour) and step it in FINE increments across the WHOLE day: at each pinned hour the
# sun/green-sun positions are STATIC (no shadow sweep), so the per-step per-channel change isolates the
# lighting-regime crossfade (warm yellow sun -> green sun + ambient). SHADOWMAP OFF by default so the cast
# shadow (dynamic, item-1) does not confound the colour metric; RTL_SHADOWMAP=1 to include it.
#
# usage: gda_hoursweep_capture.sh <tag> [START END STEP DWELL]     default 0.0 24.0 0.2 0.5
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-directional-ambient/device; mkdir -p "$OUT"
TAG="${1:?tag}"; START="${2:-0.0}"; END="${3:-24.0}"; STEP="${4:-0.2}"; DWELL="${5:-0.5}"
POS="${RTL_POS:--112.0 42.0 205.0}"
LOG="$OUT/logcat_hsweep_$TAG.log"
adb(){ "$ADB" -s "$ANDROID_SERIAL" "$@"; }
stick(){ adb shell "setprop debug.opengoal.cpad_inject '$1'" </dev/null; }
focus(){ adb shell dumpsys window 2>/dev/null </dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

"$ADB" kill-server >/dev/null 2>&1 || true; sleep 1; "$ADB" start-server >/dev/null 2>&1 || true; sleep 2
adb wait-for-device

ok=0
for TRY in 1 2 3; do
  adb shell am force-stop $PKG </dev/null; sleep 2
  stick neutral
  adb shell "setprop debug.opengoal.rt.light 1" </dev/null
  adb shell "setprop debug.opengoal.rt.ambient 1" </dev/null
  adb shell "setprop debug.opengoal.rt.ambientmodel ''" </dev/null   # shipped SH default
  adb shell "setprop debug.opengoal.rt.ambientcontrast ''" </dev/null
  adb shell "setprop debug.opengoal.rt.ambientstrength ''" </dev/null
  adb shell "setprop debug.opengoal.rt.handoffsmooth ''" </dev/null   # shipped default (alpha 0.10)
  adb shell "setprop debug.opengoal.rt.greendbg 1" </dev/null         # state dump green_elev/sun_elev/conf
  adb shell "setprop debug.opengoal.pbr.shadowmap ${RTL_SHADOWMAP:-0}" </dev/null  # OFF => isolate colour
  adb shell "setprop debug.opengoal.ao.force_mode 0" </dev/null
  adb shell "setprop debug.opengoal.pbr.debug ''" </dev/null
  adb shell "setprop debug.opengoal.rt.sunelev ''" </dev/null
  adb shell "setprop debug.opengoal.rt.greenelev ''" </dev/null
  adb shell "setprop debug.opengoal.tod.fast ''" </dev/null
  adb shell "setprop debug.opengoal.tod.hour '$START'" </dev/null     # pin, start of sweep
  adb shell setprop debug.opengoal.level.warp village1-hut </dev/null
  adb shell "setprop debug.opengoal.level.warp.pos '$POS'" </dev/null
  adb logcat -b all -c </dev/null || true
  kill "$(cat /tmp/gda_hs_lc.pid 2>/dev/null)" 2>/dev/null || true
  ( adb logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/gda_hs_lc.pid )
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
[ "$ok" = 1 ] || { echo "[gda-hsweep FAIL] warp never spawned"; exit 1; }
sleep 12
FOCUS_LINE="$(focus)"
stick neutral

# start recording, then step the pinned hour finely; the mp4 spans the whole sweep.
adb shell rm -f /sdcard/gda_hs_$TAG.mp4 </dev/null
adb shell "screenrecord --time-limit 180 --bit-rate 16000000 /sdcard/gda_hs_$TAG.mp4" </dev/null &
REC=$!
sleep 1
# emit an hour->wallclock map so frames can be labelled after extraction
: > "$OUT/hours_$TAG.txt"
for h in $(awk -v s="$START" -v e="$END" -v st="$STEP" 'BEGIN{for(x=s;x<=e+1e-9;x+=st)printf "%.2f\n",x}'); do
  adb shell "setprop debug.opengoal.tod.hour '$h'" </dev/null
  echo "$(date +%s.%N) hour=$h" >> "$OUT/hours_$TAG.txt"
  sleep "$DWELL"
done
sleep 1
kill $REC 2>/dev/null || true; wait $REC 2>/dev/null || true
sleep 2
adb pull /sdcard/gda_hs_$TAG.mp4 "$OUT/gda_hs_$TAG.mp4" >/dev/null
adb shell rm -f /sdcard/gda_hs_$TAG.mp4 </dev/null
kill "$(cat /tmp/gda_hs_lc.pid 2>/dev/null)" 2>/dev/null || true
adb shell am force-stop $PKG </dev/null

# extract at 5fps (dwell 0.5s => ~2-3 frames/hour-step; intra-dwell step ~0, inter-dwell = the hour transition)
d="$OUT/frames_hs_$TAG"; mkdir -p "$d"; find "$d" -name 'f_*.png' -delete 2>/dev/null
ffmpeg -y -loglevel error -i "$OUT/gda_hs_$TAG.mp4" -vf fps=5 "$d/f_%04d.png"
echo "  hoursweep $TAG: frames=$(ls "$d" 2>/dev/null | wc -l) shadowmap=${RTL_SHADOWMAP:-0} focus=$FOCUS_LINE"
echo "  green/sun state samples across the sweep:"
grep -aE 'GDA-GREENSUN' "$LOG" | awk 'NR%40==1' | tail -30
