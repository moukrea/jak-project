#!/usr/bin/env bash
# gci_fix_ab.sh — Gcamera-interp FIX verification A/B (device eae4df44).
#
# Same freshly-deployed binary; the ONLY variable is debug.opengoal.caminterp (the
# render-time camera-pose interpolation, OFF vs ON). Both sides run at the device's
# REAL variable timestep (pad_replay_realtime=1 => integer time-ratio k dithers, the
# owner's actual sub-60fps condition) and replay the SAME injected right-stick pan
# (pad_replay cpad injection of demo_sustained_alt_pan.inputs, Jak stationary at the
# open Geyser plateau). Captures per-render-frame *math-camera* yaw (PACE-EE) and
# scores per-frame camera-step smoothness (gci_stepmetric.py). Expect: OFF = k-dither
# judder (high step/vel CoV, high jump>1.5x); ON = smooth (low CoV, ~0 jumps), with the
# game clock (bfc rate) + total swept IDENTICAL (render-only, speed unchanged).
#
# side sequence:
#   off  caminterp=0  RSCALE=100 (fixed sub-60)   -> BEFORE
#   on   caminterp=1  RSCALE=100 (fixed sub-60)   -> AFTER
#   dyn  caminterp=1  scale=neutral/dynamic       -> holds under variable frame timing
# plus a title flythrough capture (caminterp=1) as the TITLE-LOGO hard gate.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb} -s eae4df44"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
EV=.autoport/reports/Gcamera-interp/evidence; mkdir -p "$EV"
DEMO="$EV/demo_sustained_alt_pan.inputs"
CAP="${CAP:-150}"   # seconds to capture after launch (boot+warp+anchor+~27s pan)
say(){ echo; echo "######## $* ########"; }
die(){ echo "[gcifix FAIL] $*" >&2; exit 1; }
maxframe(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$1" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }

[ -f "$DEMO" ] || die "missing demo $DEMO"
$ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED — needs owner unlock"
$ADB shell svc power stayon true >/dev/null 2>&1 || true

say "push the injected-pan demo to files/pad_demo.inputs"
$ADB push "$DEMO" /data/local/tmp/pad_demo.inputs 2>&1 | tail -1
$ADB shell run-as $PKG cp /data/local/tmp/pad_demo.inputs files/pad_demo.inputs 2>&1 | tail -1 || die "run-as cp failed"

# capture one side: $1=label $2=caminterp $3=render.scale('' for neutral/dynamic) $4=warp(1/0)
cap_side(){
  local label="$1" ci="$2" rscale="$3" warp="${4:-1}"
  local LOG="$EV/$label.log"; : > "$LOG"
  say "side $label : caminterp=$ci render.scale='${rscale:-neutral}' warp=$warp realtime-timestep"
  $ADB shell setprop debug.opengoal.caminterp "$ci"          >/dev/null 2>&1 || true
  $ADB shell setprop debug.opengoal.pad_replay replay        >/dev/null 2>&1 || true
  $ADB shell setprop debug.opengoal.pad_replay_realtime 1    >/dev/null 2>&1 || true  # cached; set pre-launch
  $ADB shell setprop debug.opengoal.pace.measure 1           >/dev/null 2>&1 || true
  $ADB shell setprop debug.opengoal.gspeed.measure 0         >/dev/null 2>&1 || true
  $ADB shell setprop debug.opengoal.f1.warp "$warp"          >/dev/null 2>&1 || true
  if [ -n "$rscale" ]; then $ADB shell setprop debug.opengoal.render.scale "$rscale" >/dev/null 2>&1 || true
  else $ADB shell setprop debug.opengoal.render.scale '""' >/dev/null 2>&1 || true; fi
  $ADB shell am force-stop "$PKG" >/dev/null 2>&1 || true
  $ADB logcat -G 128M >/dev/null 2>&1 || true; $ADB logcat -c >/dev/null 2>&1 || true
  ( $ADB logcat -v threadtime opengoal-gk:I GK_STDOUT:I GK_STDERR:I libc:F DEBUG:V '*:S' \
      | grep --line-buffered -aE 'PACE-EE|pad_replay:|ANCHOR|A35-RENDER frame=|link finish: logo|Fatal signal|signal [0-9]+ \(SIG' >> "$LOG" ) &
  local LCP=$!
  $ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
  local t0=$(date +%s) fm=0
  while [ $(( $(date +%s) - t0 )) -lt "$CAP" ]; do
    sleep 5
    fm=$(maxframe "$LOG"); fm=${fm:-0}
    if grep -aqE 'Fatal signal|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null; then echo "  !! crash in $label"; break; fi
  done
  kill ${LCP:-0} 2>/dev/null || true
  pkill -f "logcat -v threadtime opengoal-gk" 2>/dev/null || true
  local pee=$(grep -ac PACE-EE "$LOG"); local foc=$($ADB shell dumpsys window 2>/dev/null | grep -iE mCurrentFocus | head -1 | tr -d '\r')
  echo "  captured $label: maxframe=$(maxframe "$LOG") PACE-EE=$pee focus=$foc"
  grep -a 'pad_replay:' "$LOG" | head -1
  case "$foc" in *org.opengoal.gk.jak1*) : ;; *) echo "  WARN: app not foreground for $label ($foc)";; esac
}

cap_side gcifix_off 0 100 1
python3 .autoport/gci_stepmetric.py "$EV/gcifix_off.log" 2>&1 | tail -14

cap_side gcifix_on 1 100 1
python3 .autoport/gci_stepmetric.py "$EV/gcifix_on.log" 2>&1 | tail -14

cap_side gcifix_dyn 1 "" 1
python3 .autoport/gci_stepmetric.py "$EV/gcifix_dyn.log" 2>&1 | tail -14

say "TITLE-LOGO hard gate: attract flythrough with caminterp=1 (interp EXCLUDES the "
echo "  look-through-other title camera, so it must be byte-identical/smooth)"
$ADB shell setprop debug.opengoal.pad_replay '' >/dev/null 2>&1 || true
$ADB shell setprop debug.opengoal.pad_replay_realtime '' >/dev/null 2>&1 || true
$ADB shell setprop debug.opengoal.caminterp 1 >/dev/null 2>&1 || true
RSCALE="" SETTLE=6 bash .autoport/gcam_pace.sh title gcifix_title 18 2>&1 | tail -18

say "cleanup props"
for p in pad_replay pad_replay_realtime pace.measure f1.warp render.scale; do
  $ADB shell setprop debug.opengoal.$p '' >/dev/null 2>&1 || true
done
$ADB shell setprop debug.opengoal.caminterp 1 >/dev/null 2>&1 || true
echo "[gcifix] DONE — logs in $EV/gcifix_{off,on,dyn,title}.log"
