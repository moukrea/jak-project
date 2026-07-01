#!/usr/bin/env bash
# gci_toggle.sh — Gcamera-interp WITHIN-RUN caminterp toggle (device eae4df44).
# One continuous injected right-stick pan at the device's REAL variable timestep; flip
# debug.opengoal.caminterp 0<->1 every few seconds during the pan (prop polled every 64
# frames), logging GCAM-CI=N markers. OFF and ON segments are interleaved seconds apart
# in ONE run => identical thermal/fps state => a DRIFT-FREE before/after (fixes the
# confound where two separate runs land at different framerates). Scored by
# gci_toggle_analyze.py (pooled OFF vs ON, guard-dropped after each flip).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
export ANDROID_SERIAL=eae4df44
ADB="${ADB:-/home/emeric/Android/platform-tools/adb} -s eae4df44"
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
EV=.autoport/reports/Gcamera-interp/evidence; mkdir -p "$EV"
DEMO="${DEMO:-$EV/demo_sustained_alt_pan.inputs}"
RSCALE="${RSCALE:-100}"; SEG="${SEG:-5}"; NTOG="${NTOG:-8}"   # 8 x 5s = 40s toggle window
GUARD="${GUARD:-64}"   # frames dropped after each toggle (prop polled every 64 frames)
LABEL="${1:-gcitog}"; LOG="$EV/$LABEL.log"
die(){ echo "[gcitog FAIL] $*" >&2; exit 1; }
maxframe(){ grep -aoE 'A35-RENDER frame=[0-9]+' "$1" 2>/dev/null | grep -oE '[0-9]+$' | sort -n | tail -1; }

[ -f "$DEMO" ] || die "missing demo $DEMO"
$ADB shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
$ADB shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1' && die "DEVICE_LOCKED"
$ADB shell svc power stayon true >/dev/null 2>&1 || true
pkill -f "logcat -v threadtime opengoal-gk" 2>/dev/null || true

echo "## push demo + arm real-timestep pan replay, RSCALE=$RSCALE"
$ADB push "$DEMO" /data/local/tmp/pad_demo.inputs 2>&1 | tail -1
$ADB shell run-as $PKG cp /data/local/tmp/pad_demo.inputs files/pad_demo.inputs 2>&1 | tail -1 || die "run-as cp failed"
$ADB shell setprop debug.opengoal.pad_replay replay        >/dev/null 2>&1 || true
$ADB shell setprop debug.opengoal.pad_replay_realtime 1    >/dev/null 2>&1 || true
$ADB shell setprop debug.opengoal.pace.measure 1           >/dev/null 2>&1 || true
$ADB shell setprop debug.opengoal.gspeed.measure 0         >/dev/null 2>&1 || true
$ADB shell setprop debug.opengoal.f1.warp 1                >/dev/null 2>&1 || true
$ADB shell setprop debug.opengoal.render.scale "$RSCALE"   >/dev/null 2>&1 || true
$ADB shell setprop debug.opengoal.caminterp 1              >/dev/null 2>&1 || true

$ADB shell am force-stop "$PKG" >/dev/null 2>&1 || true
$ADB logcat -G 128M >/dev/null 2>&1 || true; $ADB logcat -c >/dev/null 2>&1 || true
: > "$LOG"
( $ADB logcat -v threadtime opengoal-gk:I GK_STDOUT:I GK_STDERR:I libc:F DEBUG:V '*:S' \
    | grep --line-buffered -aE 'PACE-EE|GCAM-CI|pad_replay:|ANCHOR|A35-RENDER frame=|Fatal signal|signal [0-9]+ \(SIG' >> "$LOG" ) &
LCP=$!
trap 'kill ${LCP:-0} 2>/dev/null || true' EXIT
$ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true

echo "## wait for gameplay + active pan"
t0=$(date +%s); fm=0
while [ $(( $(date +%s) - t0 )) -lt 180 ]; do
  sleep 5; fm=$(maxframe "$LOG"); fm=${fm:-0}
  [ "$fm" -ge 600 ] && break
  grep -aqE 'Fatal signal|signal (11|6|4) \(SIG' "$LOG" 2>/dev/null && die "crash before gameplay"
done
[ "$fm" -ge 400 ] || die "no gameplay in 180s (maxframe=$fm)"
echo "## gameplay live (frame $fm); settle 3s then toggle caminterp every ${SEG}s x${NTOG}"
sleep 3
for i in $(seq 1 "$NTOG"); do
  ci=$(( i % 2 ))   # 1,0,1,0,... (starts ON->OFF; both well-covered)
  $ADB shell setprop debug.opengoal.caminterp "$ci" >/dev/null 2>&1 || true
  $ADB shell log -t opengoal-gk "GCAM-CI=$ci" >/dev/null 2>&1 || true
  sleep "$SEG"
done
sleep 1
kill ${LCP:-0} 2>/dev/null || true
pkill -f "logcat -v threadtime opengoal-gk" 2>/dev/null || true
$ADB shell setprop debug.opengoal.pace.measure 0 >/dev/null 2>&1 || true
FOC=$($ADB shell dumpsys window 2>/dev/null | grep -iE mCurrentFocus | head -1 | tr -d '\r')
echo "## captured: maxframe=$(maxframe "$LOG") PACE-EE=$(grep -ac PACE-EE "$LOG") CI-marks=$(grep -ac GCAM-CI "$LOG") focus=$FOC"
grep -a 'pad_replay:' "$LOG" | head -1
case "$FOC" in *org.opengoal.gk.jak1*) : ;; *) echo "  WARN: not foreground ($FOC)";; esac
echo
python3 .autoport/gci_toggle_analyze.py "$LOG" "$GUARD"
