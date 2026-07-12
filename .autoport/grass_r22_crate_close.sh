#!/usr/bin/env bash
# grass_r22_crate_close.sh — ROUND#22 addendum: STATIONARY close-up of one crate across its break.
# Warp Jak within spin-kick range of the spawn-cluster crate at (-1295.3,7.4,1032.5); camera stays
# put. One continuous 18 s rec: pressed plateau + LYING-DOWN ring with the crate present -> spin
# kick (circle, 360°, no aiming needed) -> crate breaks IN FRAME -> the disc springs back within
# ~1 s at the same spot. Frames p22_crate_close_XX (2 fps = 0.5 s steps).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb
export ANDROID_SERIAL=eae4df44
PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
OUT=.autoport/reports/Grecharged-grass-poc; F="$OUT/frames"; mkdir -p "$F"
stick(){ $ADB shell "setprop debug.opengoal.cpad_inject '$1'"; }
pulse(){ stick "$1"; sleep "${2:-0.4}"; stick neutral; sleep "${3:-0.8}"; }
focus(){ $ADB shell dumpsys window 2>/dev/null | grep -m1 -iE 'mCurrentFocus' | tr -d '\r'; }

$ADB shell am force-stop $PKG >/dev/null 2>&1; sleep 2
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell setprop debug.opengoal.level.warp training-start >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos '-1296.4 7.8 1033.4'" >/dev/null 2>&1
$ADB logcat -b all -c >/dev/null 2>&1
( $ADB logcat -b all -v threadtime > /tmp/gr22_close.log 2>/dev/null & echo $! > /tmp/gr22c_lc.pid )
$ADB shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1
t0=$(date +%s); ok=0
while [ $(( $(date +%s)-t0 )) -lt 180 ]; do
  grep -qa 'LEVEL-WARP-SPAWN name=training-start' /tmp/gr22_close.log && { ok=1; break; }
  grep -qaE 'signal (4|6|11) \(SIG' /tmp/gr22_close.log && break
  sleep 3
done
echo "warp_ok=$ok $(focus)"
[ "$ok" = 1 ] || { echo "[r22close FAIL] warp"; $ADB shell am force-stop $PKG; exit 1; }
sleep 14   # flatten + publishes settle, crate presses its plateau

NTR0=$(grep -a 'R21OCC goal-publish' /tmp/gr22_close.log | tail -1 | grep -oE 'ntr=[0-9]+' | cut -d= -f2)
echo "baseline ntr=${NTR0:-?}"
$ADB shell rm -f /sdcard/r22close.mp4 >/dev/null 2>&1
( sleep 5; pulse "circle" 0.5 0.5; sleep 4; pulse "circle" 0.5 0.5 ) &
KICK=$!
$ADB shell screenrecord --time-limit 18 --bit-rate 12000000 /sdcard/r22close.mp4 >/dev/null 2>&1
wait $KICK 2>/dev/null || true
sleep 1; $ADB pull /sdcard/r22close.mp4 /tmp/r22close.mp4 >/dev/null 2>&1
$ADB shell rm -f /sdcard/r22close.mp4 >/dev/null 2>&1
sleep 5
NTR1=$(grep -a 'R21OCC goal-publish' /tmp/gr22_close.log | tail -1 | grep -oE 'ntr=[0-9]+' | cut -d= -f2)
echo "post ntr=${NTR1:-?} (baseline ${NTR0:-?})"

mkdir -p /tmp/rec_r22close; rm -f /tmp/rec_r22close/*.png
ffmpeg -y -loglevel error -i /tmp/r22close.mp4 -vf fps=2 /tmp/rec_r22close/f_%02d.png 2>/dev/null
echo "frames: $(ls /tmp/rec_r22close | wc -l) $(focus)"
for i in $(seq -w 1 36); do
  cp /tmp/rec_r22close/f_$i.png "$F/p22_crate_close_$i.png" 2>/dev/null || true; done

$ADB shell "setprop debug.opengoal.level.warp ''" >/dev/null 2>&1
$ADB shell "setprop debug.opengoal.level.warp.pos ''" >/dev/null 2>&1
$ADB shell setprop debug.opengoal.cpad_inject neutral >/dev/null 2>&1
$ADB shell am force-stop $PKG >/dev/null 2>&1
kill "$(cat /tmp/gr22c_lc.pid 2>/dev/null)" 2>/dev/null || true
echo "[r22close] DONE ntr ${NTR0:-?}->${NTR1:-?}"
