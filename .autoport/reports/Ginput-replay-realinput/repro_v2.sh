#!/usr/bin/env bash
# BEFORE/diagnosis repro v2: boot-retry past the ~1-in-6 SIGILL flake, reach the warp anchor,
# then drive REAL adb-input touch and confirm whether it reaches the overlay + gets recorded.
set -uo pipefail
ADB=/home/emeric/Android/platform-tools/adb
S=eae4df44
PKG=org.opengoal.gk.jak1
OUT=/home/emeric/code/jak-project/.autoport/reports/Ginput-replay-realinput
LOG="$OUT/repro_v2_logcat.txt"
mkdir -p "$OUT"

arm() {
  $ADB -s $S shell am force-stop $PKG
  $ADB -s $S shell run-as $PKG sh -c 'rm -f files/pad_demo.inputs' 2>/dev/null
  $ADB -s $S shell setprop debug.opengoal.cpad_inject none
  $ADB -s $S shell setprop debug.opengoal.f1.warp 1
  $ADB -s $S shell setprop debug.opengoal.pad_replay record
  $ADB -s $S shell "setprop debug.opengoal.pad_trace ''"
  $ADB -s $S shell svc power stayon true
  $ADB -s $S shell input keyevent KEYCODE_WAKEUP
}

boot_ok=0
for attempt in 1 2 3 4 5 6 7 8; do
  echo "=== BOOT ATTEMPT $attempt ==="
  arm
  $ADB -s $S logcat -c
  ( $ADB -s $S logcat -v time > "$LOG" 2>&1 ) &
  LOGPID=$!
  $ADB -s $S shell am start -n $PKG/org.opengoal.gk.LoaderActivity >/dev/null
  # Watch up to ~150s for ANCHOR (success) or a boot SIGILL/exit (flake -> retry)
  outcome=""
  for i in $(seq 1 75); do
    sleep 2
    if grep -qa "ANCHOR reached" "$LOG" 2>/dev/null; then outcome="anchor"; break; fi
    if grep -qaE "exited due to signal 4|exited due to signal 11|exited due to signal 6" "$LOG" 2>/dev/null; then
      # confirm it's OUR pid that died (foreground game), not a background helper
      if grep -qaE "GK-DIAG.*at-crash|F/opengoal-gk|signal 4 \(Illegal" "$LOG" 2>/dev/null; then outcome="crash"; break; fi
    fi
  done
  echo "  outcome=$outcome (after ~$((i*2))s)"
  grep -aE "F1-WARP|ANCHOR reached|exited due to signal" "$LOG" | head -8
  if [ "$outcome" = "anchor" ]; then boot_ok=1; break; fi
  kill $LOGPID 2>/dev/null
done

if [ "$boot_ok" != 1 ]; then echo "BOOT FAILED after retries (flake or deterministic). Aborting."; $ADB -s $S shell am force-stop $PKG; kill $LOGPID 2>/dev/null; exit 2; fi

echo "=== ANCHOR REACHED — calibration touch (landscape coords) ==="
# overlay-map: stick center ~ (356,704) in a 2298x1036 view. Stick radius 170.
$ADB -s $S shell input swipe 356 704 356 480 800   # calibration: stick UP
sleep 2
CAL=$(grep -ac 'overlay-actuate' "$LOG")
echo "  overlay-actuate after landscape calibration swipe: $CAL"
COORDSPACE="landscape"
if [ "$CAL" = 0 ]; then
  echo "  landscape coords MISSED — trying portrait/natural space (1080x2400)"
  # portrait-space guess for a 90deg-rotated landscape: x_p in [0,1080], y_p in [0,2400]
  $ADB -s $S shell input swipe 300 700 300 460 800
  sleep 2
  CAL2=$(grep -ac 'overlay-actuate' "$LOG")
  echo "  overlay-actuate after portrait calibration swipe: $CAL2"
  [ "$CAL2" != 0 ] && COORDSPACE="portrait"
fi
echo "  COORDSPACE=$COORDSPACE"

echo "=== DRIVE REAL adb-input touch (sustained, varied) ==="
if [ "$COORDSPACE" = landscape ]; then
  SX=356; SY=704; FX=1976; FY2=725  # stick center; face cluster center-ish
  for r in 1 2 3 4 5 6 7 8; do
    $ADB -s $S shell input swipe $SX $SY $SX 460 1200
    $ADB -s $S shell input swipe $SX $SY 620 $SY 1200
    $ADB -s $S shell input swipe $SX $SY $SX 940 1200
    $ADB -s $S shell input swipe $SX $SY 120 $SY 1200
    $ADB -s $S shell input tap 1976 837   # SOUTH
    $ADB -s $S shell input tap 2088 725   # EAST
  done
else
  # portrait fallback coords (approx; refine if needed)
  for r in 1 2 3 4 5 6 7 8; do
    $ADB -s $S shell input swipe 300 700 300 460 1200
    $ADB -s $S shell input swipe 300 700 540 700 1200
    $ADB -s $S shell input swipe 300 700 300 940 1200
    $ADB -s $S shell input tap 840 1976
  done
fi
sleep 3

echo "=== input-path markers ==="
echo "  overlay-actuate lines: $(grep -ac 'overlay-actuate' "$LOG")"
echo "  onPadButton(JNI route) : $(grep -ac 'onPadButton: sdl_button' "$LOG")"
echo "  onPadAxis(JNI) markers : $(grep -acE 'onPadAxis|axis path' "$LOG")"
echo "  kernel: pad: lines     : $(grep -ac 'kernel: pad:' "$LOG")"
echo "  LIVE-RECORD WARNING    : $(grep -ac 'LIVE-RECORD WARNING' "$LOG")"
echo "  --- sample overlay-actuate ---"; grep -a 'overlay-actuate' "$LOG" | head -6
echo "  --- sample kernel: pad: ---"; grep -a 'kernel: pad:' "$LOG" | head -6

echo "=== stop + pull + analyze ==="
$ADB -s $S shell am force-stop $PKG
kill $LOGPID 2>/dev/null
$ADB -s $S shell run-as $PKG sh -c 'cat files/pad_demo.inputs' > "$OUT/repro_v2.inputs" 2>/dev/null
ls -la "$OUT/repro_v2.inputs"
python3 "$OUT/analyze_inputs.py" "$OUT/repro_v2.inputs"
echo "=== DONE_V2 ==="
