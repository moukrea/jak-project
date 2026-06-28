#!/usr/bin/env bash
# BEFORE reproduction: warp + record, drive REAL adb-input touch, expect ALL-NEUTRAL.
# Captures the diagnostic logcat to find WHERE real touch is dropped under the warp.
set -uo pipefail
ADB=/home/emeric/Android/platform-tools/adb
S=eae4df44
PKG=org.opengoal.gk.jak1
OUT=/home/emeric/code/jak-project/.autoport/reports/Ginput-replay-realinput
LOG="$OUT/before_repro_logcat.txt"
mkdir -p "$OUT"

echo "[repro] force-stop + clean state"
$ADB -s $S shell am force-stop $PKG
$ADB -s $S shell run-as $PKG sh -c 'rm -f files/pad_demo.inputs files/cpad_inject' 2>/dev/null
$ADB -s $S shell setprop debug.opengoal.cpad_inject none    # neutral token -> NO headless injection (overrides any stale value)
$ADB -s $S shell setprop debug.opengoal.f1.warp 1
$ADB -s $S shell setprop debug.opengoal.pad_replay record
$ADB -s $S shell "setprop debug.opengoal.pad_trace ''"      # OFF (clear any stale trace prop)
$ADB -s $S shell svc power stayon true
$ADB -s $S shell input keyevent KEYCODE_WAKEUP

echo "[repro] gamepad count BEFORE launch (host atomic not up yet — informational):"
$ADB -s $S logcat -c

echo "[repro] launch"
$ADB -s $S shell am start -n $PKG/org.opengoal.gk.LoaderActivity
( $ADB -s $S logcat -v time > "$LOG" 2>&1 ) &
LOGPID=$!

echo "[repro] waiting for ANCHOR reached (max ~180s)"
ANCHORED=0
for i in $(seq 1 90); do
  sleep 2
  if grep -qa "ANCHOR reached" "$LOG" 2>/dev/null; then ANCHORED=1; echo "[repro] anchor reached at iter $i (~$((i*2))s)"; break; fi
done
[ "$ANCHORED" = 1 ] || echo "[repro] WARNING: anchor not detected; proceeding anyway"
sleep 2

echo "[repro] overlay-map line:"
grep -a -m1 "overlay-map:" "$LOG" || echo "  (no overlay-map — overlay may not be added)"
echo "[repro] touch-overlay setup lines:"
grep -aE "touch overlay (setting|enabled|disabled)|hiding touch overlay|open_gamepad_count|touch overlay disabled" "$LOG" | head

echo "[repro] driving REAL adb-input touch (landscape 2400x1080): left-stick swipes + face/start taps"
# Left stick center ~ (0.155*2400, 0.68*1080) = (372, 734); zone radius ~178.
# Face buttons cluster ~ (0.86*2400, 0.70*1080) = (2064, 756); START ~ (0.5*2400+10, 0.045*1080)=(1210,49)
for round in 1 2 3 4 5 6; do
  $ADB -s $S shell input swipe 372 734 372 480 700      # stick UP (forward)
  $ADB -s $S shell input swipe 372 734 600 734 700      # stick RIGHT
  $ADB -s $S shell input swipe 372 734 372 980 700      # stick DOWN
  $ADB -s $S shell input swipe 372 734 150 734 700      # stick LEFT
  $ADB -s $S shell input tap 2064 900                   # SOUTH (X)
  $ADB -s $S shell input tap 2256 756                   # EAST (circle)
done

echo "[repro] post-input settle"
sleep 3
echo "[repro] input-path logcat markers (did touch reach overlay/native?):"
grep -aE "overlay-actuate|onPadButton|onPadAxis|kernel: pad:|F1D-CPAD-START|LIVE-RECORD WARNING|F1D-INJECT" "$LOG" | head -40
echo "[repro] counts:"
echo "  overlay-actuate lines: $(grep -ac 'overlay-actuate' "$LOG")"
echo "  onPadButton lines:     $(grep -ac 'onPadButton' "$LOG")"
echo "  onPadAxis lines:       $(grep -ac 'onPadAxis' "$LOG")"
echo "  kernel: pad: lines:    $(grep -ac 'kernel: pad:' "$LOG")"
echo "  LIVE-RECORD WARNING:   $(grep -ac 'LIVE-RECORD WARNING' "$LOG")"

echo "[repro] stop + pull demo"
$ADB -s $S shell am force-stop $PKG
kill $LOGPID 2>/dev/null
$ADB -s $S shell run-as $PKG sh -c 'cat files/pad_demo.inputs' > "$OUT/before.inputs" 2>/dev/null
ls -la "$OUT/before.inputs"
python3 "$OUT/analyze_inputs.py" "$OUT/before.inputs"
echo "[repro] DONE"
