#!/usr/bin/env bash
# gci_dynsweep.sh — Gcamera-interp holds under VARIABLE FRAME TIMING (device eae4df44).
# caminterp stays ON; during ONE injected alternating pan we SWEEP debug.opengoal.render.
# scale between two values every few seconds, deliberately jolting the per-frame render
# time (== the worst case the dynamic render-scale controller can produce). If the fix
# tracks real display time correctly, the per-render-frame camera step stays smooth
# (low vel CoV / jump>1.5x) DESPITE the scale/fps changes. Scored whole-log by
# gci_stepmetric.py (caminterp constant, so no segmentation needed).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb} -s eae4df44"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
EV=.autoport/reports/Gcamera-interp/evidence; mkdir -p "$EV"
DEMO="$EV/demo_sustained_alt_pan.inputs"
LABEL="${1:-gcidyn}"; LOG="$EV/$LABEL.log"
SEG="${SEG:-4}"; NSW="${NSW:-10}"
die(){ echo "[gcidyn FAIL] $*" >&2; exit 1; }
maxframe(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$1" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }

$ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED"
$ADB shell svc power stayon true >/dev/null 2>&1 || true
pkill -f "logcat -v threadtime opengoal-gk" 2>/dev/null || true

$ADB push "$DEMO" /data/local/tmp/pad_demo.inputs 2>&1 | tail -1
$ADB shell run-as $PKG cp /data/local/tmp/pad_demo.inputs files/pad_demo.inputs 2>&1 | tail -1 || die "cp failed"
$ADB shell setprop debug.opengoal.pad_replay replay        >/dev/null 2>&1 || true
$ADB shell setprop debug.opengoal.pad_replay_realtime 1    >/dev/null 2>&1 || true
$ADB shell setprop debug.opengoal.pace.measure 1           >/dev/null 2>&1 || true
$ADB shell setprop debug.opengoal.f1.warp 1                >/dev/null 2>&1 || true
$ADB shell setprop debug.opengoal.caminterp 1              >/dev/null 2>&1 || true
$ADB shell setprop debug.opengoal.render.scale 100         >/dev/null 2>&1 || true

$ADB shell am force-stop "$PKG" >/dev/null 2>&1 || true
$ADB logcat -G 128M >/dev/null 2>&1 || true; $ADB logcat -c >/dev/null 2>&1 || true
: > "$LOG"
( $ADB logcat -v threadtime opengoal-gk:I GK_STDOUT:I GK_STDERR:I libc:F DEBUG:V '*:S' \
    | grep --line-buffered -aE 'PACE-EE|GCAM-|pad_replay:|A35-RENDER frame=|Fatal signal|signal [0-9]+ \(SIG' >> "$LOG" ) &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true' EXIT
$ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true
t0=$(date +%s); fm=0
while [ $(( $(date +%s) - t0 )) -lt 180 ]; do
  sleep 5; fm=$(maxframe "$LOG"); fm=${fm:-0}
  [ "$fm" -ge 600 ] && break
  grep -aqE 'Fatal signal|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null && die "crash before gameplay"
done
[ "$fm" -ge 400 ] || die "no gameplay (maxframe=$fm)"
echo "## gameplay live (frame $fm); caminterp=1, sweeping render.scale every ${SEG}s x${NSW}"
sleep 2
for i in $(seq 1 "$NSW"); do
  sc=$([ $(( i % 2 )) -eq 0 ] && echo 100 || echo 60)   # jolt frame-time: 100 <-> 60
  $ADB shell setprop debug.opengoal.render.scale "$sc" >/dev/null 2>&1 || true
  $ADB shell log -t opengoal-gk "GCAM-SCALE=$sc" >/dev/null 2>&1 || true
  sleep "$SEG"
done
sleep 1
kill ${LCP:-0} 2>/dev/null || true
pkill -f "logcat -v threadtime opengoal-gk" 2>/dev/null || true
$ADB shell setprop debug.opengoal.pace.measure 0 >/dev/null 2>&1 || true
FOC=$($ADB shell dumpsys window 2>/dev/null | grep -iE mCurrentFocus | head -1 | tr -d '\r')
echo "## captured: maxframe=$(maxframe "$LOG") PACE-EE=$(grep -ac PACE-EE "$LOG") scale-marks=$(grep -ac GCAM-SCALE "$LOG") focus=$FOC"
case "$FOC" in *org.opengoal.gk.jak1*) : ;; *) echo "  WARN: not foreground ($FOC)";; esac
echo "## whole-log smoothness under the render-scale sweep (caminterp ON):"
python3 .autoport/gci_stepmetric.py "$LOG"
