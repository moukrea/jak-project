#!/usr/bin/env bash
# gda_a11_ambientonly_sweep.sh — OWNER PLAYTEST #5 ISOLATED ambient-orientation A/B.
#
# WHY a second, ambient-ONLY sweep: the full-lighting sweep (gda_a11_ambfade_sweep.sh) is dominated by the
# sun rise/set BRIGHTNESS envelope + the direct-sun lit-side sweep, which are IDENTICAL in the ambfade A/B
# (the fix only touches the ambient ORIENTATION) => a whole-crop metric can't discriminate the fix. Here we
# force the DIRECT sun term to ZERO (debug.opengoal.rt.sunelev 0 + greenelev 0 => sun_scalar=0, moon term=0,
# AND the SH sun-glow=0 since it also scales by rt_sun_elev) so ONLY the ambient's amb_key directional term
# remains. Sweeping the pinned hour then sweeps the NATURAL sun/green elevations (sun_up_raw/green_up_raw,
# which the debug elev props do NOT override) => it sweeps amb_key exactly. With a BRIGHTNESS-NORMALIZED
# structural metric (gda_structural_smoothness.py [ORIENT]) this isolates the shading ORIENTATION change:
#   OLD (ambfade 0) = locked-yellow full-strength key -> snaps when the yellow azimuth degenerates at the
#                     sun's nadir (deep night) / at the antiphase handoff;
#   NEW (ambfade 1) = per-sun elevation-weighted key -> fades through a dark neutral middle, no snap.
#
# usage: gda_a11_ambientonly_sweep.sh [START END STEP DWELL]   default 0.0 24.0 0.2 0.6
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-directional-ambient/device; mkdir -p "$OUT"
START="${1:-0.0}"; END="${2:-24.0}"; STEP="${3:-0.2}"; DWELL="${4:-0.6}"
POS="${RTL_POS:--112.0 42.0 205.0}"
LOG="$OUT/logcat_a11_ambonly.log"
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
  adb shell "setprop debug.opengoal.rt.ambientmodel ''" </dev/null    # shipped SH default
  adb shell "setprop debug.opengoal.rt.ambientcontrast ''" </dev/null
  adb shell "setprop debug.opengoal.rt.ambientstrength ''" </dev/null
  adb shell "setprop debug.opengoal.rt.handoffsmooth ''" </dev/null
  adb shell "setprop debug.opengoal.rt.greendbg 1" </dev/null
  adb shell "setprop debug.opengoal.pbr.shadowmap 0" </dev/null
  adb shell "setprop debug.opengoal.ao.force_mode 0" </dev/null
  adb shell "setprop debug.opengoal.rt.sunelev 0" </dev/null          # DIRECT yellow OFF (ambient-only)
  adb shell "setprop debug.opengoal.rt.greenelev 0" </dev/null        # DIRECT green OFF (ambient-only)
  adb shell "setprop debug.opengoal.rt.ambfade 1" </dev/null
  adb shell "setprop debug.opengoal.tod.fast ''" </dev/null
  adb shell "setprop debug.opengoal.tod.hour '$START'" </dev/null
  adb shell setprop debug.opengoal.level.warp village1-hut </dev/null
  adb shell "setprop debug.opengoal.level.warp.pos '$POS'" </dev/null
  adb logcat -b all -c </dev/null || true
  kill "$(cat /tmp/gda_ao_lc.pid 2>/dev/null)" 2>/dev/null || true
  ( adb logcat -b all -v threadtime </dev/null > "$LOG" 2>/dev/null & echo $! > /tmp/gda_ao_lc.pid )
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
[ "$ok" = 1 ] || { echo "[gda-ao FAIL] warp never spawned"; exit 1; }
sleep 12
FOCUS_LINE="$(focus)"
case "$FOCUS_LINE" in *org.opengoal.gk.jak1*) : ;; *) echo "[gda-ao FAIL] not foreground: $FOCUS_LINE"; exit 1 ;; esac
stick neutral

# stop the ON-DEVICE screenrecord daemon with SIGINT so the mp4 moov atom is finalized (the host-side
# adb-shell wrapper kill does NOT propagate; leaving the daemon => 'moov atom not found' / frames=0).
stop_rec() {
  adb shell "pkill -INT screenrecord" </dev/null 2>/dev/null || true
  sleep 3   # let the encoder flush + write the moov atom
}

sweep_once() {   # $1 = ambfade (0 OLD / 1 NEW), $2 = tag
  local FADE="$1" TAG="$2"
  adb shell "pkill -INT screenrecord" </dev/null 2>/dev/null || true; sleep 1
  adb shell "setprop debug.opengoal.rt.ambfade $FADE" </dev/null
  adb shell "setprop debug.opengoal.tod.hour '$START'" </dev/null
  sleep 2
  adb shell rm -f /sdcard/gda_ao_$TAG.mp4 </dev/null
  adb shell "screenrecord --time-limit 180 --bit-rate 16000000 /sdcard/gda_ao_$TAG.mp4" </dev/null &
  sleep 1
  : > "$OUT/hours_ao_$TAG.txt"
  for h in $(awk -v s="$START" -v e="$END" -v st="$STEP" 'BEGIN{for(x=s;x<=e+1e-9;x+=st)printf "%.2f\n",x}'); do
    adb shell "setprop debug.opengoal.tod.hour '$h'" </dev/null
    echo "$(date +%s.%N) hour=$h" >> "$OUT/hours_ao_$TAG.txt"
    sleep "$DWELL"
  done
  sleep 1
  stop_rec
  adb pull /sdcard/gda_ao_$TAG.mp4 "$OUT/gda_ao_$TAG.mp4" >/dev/null
  adb shell rm -f /sdcard/gda_ao_$TAG.mp4 </dev/null
  local d="$OUT/frames_ao_$TAG"; mkdir -p "$d"; find "$d" -name 'f_*.png' -delete 2>/dev/null
  ffmpeg -y -loglevel error -i "$OUT/gda_ao_$TAG.mp4" -vf fps=5 "$d/f_%04d.png" 2>/dev/null
  echo "  ambient-only sweep $TAG (ambfade=$FADE): frames=$(ls "$d" 2>/dev/null | wc -l)"
}

sweep_once 0 old_snap
sweep_once 1 new_fade

kill "$(cat /tmp/gda_ao_lc.pid 2>/dev/null)" 2>/dev/null || true
adb shell am force-stop $PKG </dev/null
echo "  a11 AMBIENT-ONLY sweep done. focus=$FOCUS_LINE"
