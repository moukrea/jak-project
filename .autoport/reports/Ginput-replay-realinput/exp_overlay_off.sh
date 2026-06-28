#!/usr/bin/env bash
# Round A (BEFORE): overlay DISABLED (the gamepad-at-startup / user-off persisted state) ->
# adb-input touch under warp+record -> expect ALL-NEUTRAL (overlay absent => touch not delivered).
# Also run the pad_replay determinism selftest (record==replay).
set -uo pipefail
ADB=/home/emeric/Android/platform-tools/adb
S=eae4df44
PKG=org.opengoal.gk.jak1
OUT=/home/emeric/code/jak-project/.autoport/reports/Ginput-replay-realinput
LOG="$OUT/exp_overlay_off_logcat.txt"

# Force the overlay-disabled persisted state (== a gamepad present at first launch).
PREFXML="<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <boolean name=\"touch_overlay_initialised\" value=\"true\" />
    <boolean name=\"touch_overlay_enabled\" value=\"false\" />
</map>"
$ADB -s $S shell am force-stop $PKG
$ADB -s $S shell run-as $PKG sh -c "mkdir -p shared_prefs; cat > shared_prefs/opengoal-gk.xml" <<EOF
$PREFXML
EOF
echo "=== pref written: ==="; $ADB -s $S shell run-as $PKG cat shared_prefs/opengoal-gk.xml

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
  echo "=== BOOT ATTEMPT $attempt (overlay OFF) ==="
  arm
  $ADB -s $S logcat -c
  ( $ADB -s $S logcat -v time > "$LOG" 2>&1 ) &
  LOGPID=$!
  $ADB -s $S shell am start -n $PKG/org.opengoal.gk.LoaderActivity >/dev/null
  outcome=""
  for i in $(seq 1 75); do
    sleep 2
    if grep -qa "ANCHOR reached" "$LOG" 2>/dev/null; then outcome="anchor"; break; fi
    if grep -qaE "exited due to signal 4" "$LOG" 2>/dev/null && grep -qaE "GK-DIAG.*at-crash|F/opengoal-gk" "$LOG" 2>/dev/null; then outcome="crash"; break; fi
  done
  echo "  outcome=$outcome (~$((i*2))s)"
  if [ "$outcome" = "anchor" ]; then boot_ok=1; break; fi
  kill $LOGPID 2>/dev/null
done
[ "$boot_ok" = 1 ] || { echo "BOOT FAILED"; $ADB -s $S shell am force-stop $PKG; kill $LOGPID 2>/dev/null; exit 2; }

echo "=== overlay setup lines (expect 'disabled by settings', NO overlay-map) ==="
grep -aE "touch overlay (setting|enabled|disabled)|overlay-map:" "$LOG" | head

echo "=== drive adb touch (same landscape coords that captured 75% with overlay ON) ==="
SX=356; SY=704
for r in 1 2 3 4 5 6; do
  $ADB -s $S shell input swipe $SX $SY $SX 460 1000
  $ADB -s $S shell input swipe $SX $SY 620 $SY 1000
  $ADB -s $S shell input tap 1976 837
done
sleep 3
echo "  overlay-actuate lines: $(grep -ac 'overlay-actuate' "$LOG")  (expect 0 — overlay absent)"
$ADB -s $S shell am force-stop $PKG
kill $LOGPID 2>/dev/null
$ADB -s $S exec-out run-as $PKG cat files/pad_demo.inputs > "$OUT/before_overlay_off.inputs" 2>/dev/null
ls -la "$OUT/before_overlay_off.inputs"
python3 "$OUT/analyze_inputs.py" "$OUT/before_overlay_off.inputs"

echo "=== restore default pref (delete the forced file) ==="
$ADB -s $S shell run-as $PKG sh -c 'rm -f shared_prefs/opengoal-gk.xml'
echo "=== DONE_A ==="
