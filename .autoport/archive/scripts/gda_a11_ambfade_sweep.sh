#!/usr/bin/env bash
# gda_a11_ambfade_sweep.sh — OWNER PLAYTEST #5 STRUCTURAL orientation-smoothness A/B.
#
# Captures TWO full-day pinned-hour TOD sweeps at the SAME fixed building (hut) vantage:
#   OLD  = debug.opengoal.rt.ambfade 0  -> the pre-fix LOCKED-yellow ambient key (reproduces the ~180deg
#          ambient-orientation SNAP the owner reported at the sun<->green-sun handoff)
#   NEW  = debug.opengoal.rt.ambfade 1  -> the SHIPPED default per-sun elevation-weighted ambient key that
#          eases the orientation OUT into a dark NEUTRAL MIDDLE then IN toward green (the fix)
# The camera is static and the sun is PINNED per hour-step, so between consecutive frames the ONLY change is
# the lighting on the geometry => a per-pixel STRUCTURAL step measures the orientation change directly. The
# orientation SNAP (OLD) shows up as a per-pixel/1-SSIM spike at the handoff even though the frame MEAN is
# continuous; the fix (NEW) removes that spike. shadowmap OFF so the dynamic cast-shadow sweep does not
# confound the ambient-orientation metric (golden rule: shadow gates only the direct term anyway).
#
# usage: gda_a11_ambfade_sweep.sh [START END STEP DWELL]     default 0.0 24.0 0.2 0.5
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-directional-ambient/device; mkdir -p "$OUT"
START="${1:-0.0}"; END="${2:-24.0}"; STEP="${3:-0.2}"; DWELL="${4:-0.5}"
POS="${RTL_POS:--112.0 42.0 205.0}"
LOG="$OUT/logcat_a11_ambfade.log"
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
  adb shell "setprop debug.opengoal.rt.ambientmodel ''" </dev/null    # shipped SH default (model 1)
  adb shell "setprop debug.opengoal.rt.ambientcontrast ''" </dev/null
  adb shell "setprop debug.opengoal.rt.ambientstrength ''" </dev/null
  adb shell "setprop debug.opengoal.rt.handoffsmooth ''" </dev/null    # shipped default (alpha 0.10)
  adb shell "setprop debug.opengoal.rt.greendbg 1" </dev/null
  adb shell "setprop debug.opengoal.pbr.shadowmap 0" </dev/null        # isolate ambient orientation
  adb shell "setprop debug.opengoal.ao.force_mode 0" </dev/null
  adb shell "setprop debug.opengoal.rt.sunelev ''" </dev/null
  adb shell "setprop debug.opengoal.rt.greenelev ''" </dev/null
  adb shell "setprop debug.opengoal.rt.ambfade 1" </dev/null           # start NEW (default)
  adb shell "setprop debug.opengoal.tod.fast ''" </dev/null
  adb shell "setprop debug.opengoal.tod.hour '$START'" </dev/null
  adb shell setprop debug.opengoal.level.warp village1-hut </dev/null
  adb shell "setprop debug.opengoal.level.warp.pos '$POS'" </dev/null
  adb logcat -b all -c </dev/null || true
  kill "$(cat /tmp/gda_a11_lc.pid 2>/dev/null)" 2>/dev/null || true
  ( adb logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/gda_a11_lc.pid )
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
[ "$ok" = 1 ] || { echo "[gda-a11 FAIL] warp never spawned"; exit 1; }
sleep 12
FOCUS_LINE="$(focus)"
case "$FOCUS_LINE" in *org.opengoal.gk.jak1*) : ;; *) echo "[gda-a11 FAIL] not foreground: $FOCUS_LINE"; exit 1 ;; esac
stick neutral

sweep_once() {   # $1 = ambfade (0 OLD / 1 NEW), $2 = tag
  local FADE="$1" TAG="$2"
  adb shell "setprop debug.opengoal.rt.ambfade $FADE" </dev/null
  adb shell "setprop debug.opengoal.tod.hour '$START'" </dev/null
  sleep 2   # let the handoff EMA settle at the start hour before recording
  adb shell rm -f /sdcard/gda_a11_$TAG.mp4 </dev/null
  adb shell "screenrecord --time-limit 180 --bit-rate 16000000 /sdcard/gda_a11_$TAG.mp4" </dev/null &
  local REC=$!
  sleep 1
  : > "$OUT/hours_a11_$TAG.txt"
  for h in $(awk -v s="$START" -v e="$END" -v st="$STEP" 'BEGIN{for(x=s;x<=e+1e-9;x+=st)printf "%.2f\n",x}'); do
    adb shell "setprop debug.opengoal.tod.hour '$h'" </dev/null
    echo "$(date +%s.%N) hour=$h" >> "$OUT/hours_a11_$TAG.txt"
    sleep "$DWELL"
  done
  sleep 1
  kill $REC 2>/dev/null || true; wait $REC 2>/dev/null || true
  sleep 2
  adb pull /sdcard/gda_a11_$TAG.mp4 "$OUT/gda_a11_$TAG.mp4" >/dev/null
  adb shell rm -f /sdcard/gda_a11_$TAG.mp4 </dev/null
  local d="$OUT/frames_a11_$TAG"; mkdir -p "$d"; find "$d" -name 'f_*.png' -delete 2>/dev/null
  ffmpeg -y -loglevel error -i "$OUT/gda_a11_$TAG.mp4" -vf fps=5 "$d/f_%04d.png"
  echo "  sweep $TAG (ambfade=$FADE): frames=$(ls "$d" 2>/dev/null | wc -l)"
}

sweep_once 0 old_snap    # OLD: locked-yellow ambient key (the snap)
sweep_once 1 new_fade    # NEW: per-sun elevation-weighted ambient key (shipped default fix)

kill "$(cat /tmp/gda_a11_lc.pid 2>/dev/null)" 2>/dev/null || true
adb shell am force-stop $PKG </dev/null
echo "  a11 ambfade sweep done. focus=$FOCUS_LINE"
echo "  GDA-GREENSUN samples (locate the handoff hour where sun_elev->0 / green_elev->up):"
grep -aE 'GDA-GREENSUN' "$LOG" | awk 'NR%15==1' | tail -40
