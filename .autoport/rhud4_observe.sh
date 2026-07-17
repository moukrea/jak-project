#!/usr/bin/env bash
# rhud4_observe.sh — ROUND 4 ground-truth observation of the Recharged HUD on the
# ACTUAL arm64 device (eae4df44), current fresh HEAD build. Goal: SEE whether the
# owner's round-4 bugs still manifest on this fresh build before fixing blind.
#   - green eco (eco.spawn=4): world-space leak? green particle in HUD by heart? heart pop?
#   - blue eco  (eco.spawn=3): eco gauge fill + gauge-center particle?
# Uses screenrecord (video) because the leak is a MOVING/transient effect that sparse
# screencaps miss. Pulls the video, extracts frames as PNGs for manager inspection.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44; PKG=org.opengoal.gk.jak1; ACT=.LoaderActivity
INJECT="/data/data/$PKG/files/cpad_inject"
SETF="/storage/emulated/0/OpenGOAL/jak1/settings.ini"
OUT=.autoport/reports/Grecharged-hud-jak1; SHOTS="$OUT/round4"; mkdir -p "$SHOTS"
adb(){ "$ADB" -s "$S" "$@"; }
inject(){ printf '%s' "$1" | adb shell "run-as $PKG sh -c 'cat > $INJECT'" >/dev/null 2>&1 || true; }
clr(){ inject ""; }
fg(){ adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r'; }
shot(){ adb exec-out screencap -p > "$SHOTS/device-$1.png" 2>/dev/null; echo "    shot device-$1.png ($(stat -c%s "$SHOTS/device-$1.png" 2>/dev/null||echo 0) B) fg=$(fg)"; }
boot(){ adb shell am start -W -n "$PKG/$ACT" >/dev/null 2>&1 || true; echo "  launched, settling ${1:-60}s..."; sleep "${1:-60}"; }

adb get-state >/dev/null 2>&1 || { echo "device not attached"; exit 1; }
adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
adb shell svc power stayon true >/dev/null 2>&1 || true
if adb shell dumpsys trust 2>/dev/null | grep -q 'deviceLocked=1'; then echo "DEVICE_LOCKED"; exit 1; fi

echo "== settings: confirm recharged-hud? ON =="
CUR=$(adb shell run-as $PKG cat "$SETF" 2>/dev/null | grep -a recharged | tr -d '\r')
echo "  device flag: $CUR"
if ! echo "$CUR" | grep -q '^recharged-hud? = #t'; then
  echo "  flag not ON — patching to #t"
  adb shell run-as $PKG cat "$SETF" 2>/dev/null | tr -d '\r' > /tmp/rhud4-set.gc
  if grep -q 'recharged-hud?' /tmp/rhud4-set.gc; then
    sed -i 's/^recharged-hud? = #f/recharged-hud? = #t/' /tmp/rhud4-set.gc
  else
    echo "  WARN: no recharged-hud? line; leaving as-is"
  fi
  adb push /tmp/rhud4-set.gc /data/local/tmp/rhud4-set.gc >/dev/null 2>&1
  adb shell run-as $PKG cp /data/local/tmp/rhud4-set.gc "$SETF" >/dev/null 2>&1
  echo "  now: $(adb shell run-as $PKG cat "$SETF" 2>/dev/null | grep -a recharged | tr -d '\r')"
fi

echo "== warp ON to Geyser Rock =="
adb shell am force-stop $PKG >/dev/null 2>&1 || true
adb logcat -c >/dev/null 2>&1 || true
adb shell setprop debug.opengoal.f1.warp 1 || true
adb shell setprop debug.opengoal.mouche.buzz 0 || true
# spawn green eco continuously near target from the start (type 4=green, period ~45 ticks)
adb shell setprop debug.opengoal.eco.spawn "4 45" || true
boot 90
echo "  focus after boot: $(fg)"
adb logcat -d -v brief 2>/dev/null | grep -aE 'F1-WARP|recharged-hud|Fatal signal|GK-DIAG sig=' | tail -5

echo "== A. GREEN ECO round — record 24s while Jak stands in the green-eco spawn =="
adb shell screenrecord --time-limit 24 --bit-rate 8000000 /sdcard/rhud4-green.mp4 &
REC=$!
sleep 1
# gently rock the stick so Jak drifts through the spawning green eco pills to collect them
for i in 1 2 3 4 5 6; do inject "ly=0.4"; sleep 1.6; clr; inject "ly=-0.4"; sleep 1.6; clr; done
wait $REC 2>/dev/null || sleep 24
shot A-green-still
adb pull /sdcard/rhud4-green.mp4 "$SHOTS/rhud4-green.mp4" >/dev/null 2>&1 && echo "  pulled green video ($(stat -c%s "$SHOTS/rhud4-green.mp4" 2>/dev/null||echo 0) B)"

echo "== B. BLUE ECO round — spawn blue eco, collect, record gauge 18s =="
adb shell setprop debug.opengoal.eco.spawn "3 45" || true
sleep 2
adb shell screenrecord --time-limit 18 --bit-rate 8000000 /sdcard/rhud4-blue.mp4 &
REC=$!
sleep 1
for i in 1 2 3 4; do inject "ly=0.4"; sleep 1.6; clr; inject "ly=-0.4"; sleep 1.6; clr; done
wait $REC 2>/dev/null || sleep 18
shot B-blue-still
adb pull /sdcard/rhud4-blue.mp4 "$SHOTS/rhud4-blue.mp4" >/dev/null 2>&1 && echo "  pulled blue video ($(stat -c%s "$SHOTS/rhud4-blue.mp4" 2>/dev/null||echo 0) B)"

echo "== logcat harvest =="
adb logcat -d -v threadtime 2>/dev/null | grep -aE 'F1-WARP|recharged-hud|eco|SPART|Fatal signal|GK-DIAG sig=|signal 11|signal 6' > "$OUT/round4/device-ON-logcat.txt" || true
echo "  logcat lines: $(wc -l < "$OUT/round4/device-ON-logcat.txt" 2>/dev/null || echo 0)"
echo "  crash sigs: $(grep -acE 'Fatal signal|sig=11|sig=6|signal 11|signal 6' "$OUT/round4/device-ON-logcat.txt" || echo 0)"

echo "== clear eco spawn prop (leave warp/hud as-is for follow-up) =="
adb shell setprop debug.opengoal.eco.spawn "" || true
echo "[rhud4-observe] DONE. Final focus: $(fg)"
ls -la "$SHOTS"/*.mp4 "$SHOTS"/*.png 2>/dev/null
