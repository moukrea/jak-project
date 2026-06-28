#!/usr/bin/env bash
# AFTER (with the fix): pref OFF (overlay would be disabled) + record armed + warp ->
# the fix FORCES the overlay touch-capable -> adb-input touch is CAPTURED.
# Also: pad_replay determinism SELFTEST (record==replay bit-identical) + replay the real demo.
set -uo pipefail
ADB=/home/emeric/Android/platform-tools/adb
S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=/home/emeric/code/jak-project/.autoport/reports/Ginput-replay-realinput
HOME0=/data/user/0/$PKG

set_pref_off() {
  printf "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n    <boolean name=\"touch_overlay_initialised\" value=\"true\" />\n    <boolean name=\"touch_overlay_enabled\" value=\"false\" />\n</map>\n" > /tmp/ovpref.xml
  $ADB -s $S push /tmp/ovpref.xml /data/local/tmp/ovpref.xml >/dev/null 2>&1
  $ADB -s $S shell chmod 644 /data/local/tmp/ovpref.xml
  $ADB -s $S shell "run-as $PKG cp /data/local/tmp/ovpref.xml $HOME0/shared_prefs/opengoal-gk.xml"
}

#####################################################################
# PART 1 — adb-input touch CAPTURE with overlay pref OFF (fix forces it on)
#####################################################################
LOG="$OUT/after_capture_logcat.txt"
arm() {
  $ADB -s $S shell am force-stop $PKG
  set_pref_off
  $ADB -s $S shell "run-as $PKG rm -f $HOME0/files/pad_demo.inputs" 2>/dev/null
  $ADB -s $S shell setprop debug.opengoal.cpad_inject none
  $ADB -s $S shell setprop debug.opengoal.f1.warp 1
  $ADB -s $S shell setprop debug.opengoal.pad_replay record
  $ADB -s $S shell "setprop debug.opengoal.pad_trace ''"
  $ADB -s $S shell svc power stayon true
  $ADB -s $S shell input keyevent KEYCODE_WAKEUP
}
boot_ok=0
for attempt in 1 2 3 4 5 6 7 8; do
  echo "=== CAPTURE BOOT ATTEMPT $attempt (pref OFF + fix) ==="
  arm
  $ADB -s $S logcat -c
  ( $ADB -s $S logcat -v time > "$LOG" 2>&1 ) & LOGPID=$!
  $ADB -s $S shell am start -n $PKG/org.opengoal.gk.LoaderActivity >/dev/null
  outcome=""
  for i in $(seq 1 75); do
    sleep 2
    grep -qa "ANCHOR reached" "$LOG" 2>/dev/null && { outcome="anchor"; break; }
    grep -qaE "exited due to signal 4" "$LOG" 2>/dev/null && grep -qaE "GK-DIAG.*at-crash|F/opengoal-gk" "$LOG" && { outcome="crash"; break; }
  done
  echo "  outcome=$outcome (~$((i*2))s)"
  [ "$outcome" = "anchor" ] && { boot_ok=1; break; }
  kill $LOGPID 2>/dev/null
done
[ "$boot_ok" = 1 ] || { echo "CAPTURE BOOT FAILED"; $ADB -s $S shell am force-stop $PKG; kill $LOGPID 2>/dev/null; exit 2; }

echo "=== FIX markers (expect FORCING overlay ON + PERSISTENT + overlay-map present) ==="
grep -aE "FORCING the overlay ON|record_armed=true|PERSISTENT|overlay-map:" "$LOG" | head
echo "=== drive REAL adb-input touch (varied: stick 4-dir swipes + face taps) ==="
SX=356; SY=635
for r in 1 2 3 4 5 6 7 8; do
  $ADB -s $S shell input swipe $SX $SY $SX 420 1100
  $ADB -s $S shell input swipe $SX $SY 640 $SY 1100
  $ADB -s $S shell input swipe $SX $SY $SX 900 1100
  $ADB -s $S shell input swipe $SX $SY 120 $SY 1100
  $ADB -s $S shell input tap 1976 755
  $ADB -s $S shell input tap 2077 653
done
sleep 3
echo "  overlay-actuate lines: $(grep -ac 'overlay-actuate' "$LOG")"
$ADB -s $S shell am force-stop $PKG
kill $LOGPID 2>/dev/null
$ADB -s $S exec-out run-as $PKG cat files/pad_demo.inputs > "$OUT/after_capture.inputs" 2>/dev/null
echo "=== CAPTURED DEMO ANALYSIS ==="
python3 "$OUT/analyze_inputs.py" "$OUT/after_capture.inputs"

#####################################################################
# PART 2 — pad_replay determinism SELFTEST (record==replay bit-identical)
#####################################################################
SLOG="$OUT/after_selftest_logcat.txt"
echo "=== SELFTEST (record==replay round-trip) ==="
$ADB -s $S shell am force-stop $PKG
$ADB -s $S shell "setprop debug.opengoal.f1.warp ''"
$ADB -s $S shell setprop debug.opengoal.pad_replay selftest
$ADB -s $S logcat -c
( $ADB -s $S logcat -v time > "$SLOG" 2>&1 ) & SLOGPID=$!
$ADB -s $S shell am start -n $PKG/org.opengoal.gk.LoaderActivity >/dev/null
for i in $(seq 1 40); do sleep 2; grep -qa "pad_replay: SELFTEST PASS\|pad_replay: SELFTEST FAIL\|PAD DIFF:" "$SLOG" && break; done
sleep 1
echo "--- selftest results ---"
grep -aE "PAD DIFF:|DETERMINISM:|FIRST DIVERGENCE:|SELFTEST (PASS|FAIL)|demo size" "$SLOG" | head
$ADB -s $S shell am force-stop $PKG
kill $SLOGPID 2>/dev/null

#####################################################################
# PART 3 — REPLAY the real adb-touch demo (proves it loads + reproduces)
#####################################################################
RLOG="$OUT/after_replay_logcat.txt"
echo "=== REPLAY the captured real demo (push it back, warp+replay) ==="
$ADB -s $S push "$OUT/after_capture.inputs" /data/local/tmp/after_capture.inputs >/dev/null 2>&1
$ADB -s $S shell chmod 644 /data/local/tmp/after_capture.inputs
$ADB -s $S shell "run-as $PKG cp /data/local/tmp/after_capture.inputs $HOME0/files/pad_demo.inputs"
$ADB -s $S shell am force-stop $PKG
set_pref_off
$ADB -s $S shell setprop debug.opengoal.cpad_inject none
$ADB -s $S shell setprop debug.opengoal.f1.warp 1
$ADB -s $S shell setprop debug.opengoal.pad_replay replay
$ADB -s $S shell svc power stayon true
boot_ok=0
for attempt in 1 2 3 4 5 6; do
  $ADB -s $S shell am force-stop $PKG
  $ADB -s $S shell input keyevent KEYCODE_WAKEUP
  $ADB -s $S logcat -c
  ( $ADB -s $S logcat -v time > "$RLOG" 2>&1 ) & RLOGPID=$!
  $ADB -s $S shell am start -n $PKG/org.opengoal.gk.LoaderActivity >/dev/null
  outcome=""
  for i in $(seq 1 75); do
    sleep 2
    grep -qa "ANCHOR reached" "$RLOG" 2>/dev/null && { outcome="anchor"; break; }
    grep -qaE "exited due to signal 4" "$RLOG" 2>/dev/null && grep -qaE "GK-DIAG.*at-crash" "$RLOG" && { outcome="crash"; break; }
  done
  echo "  replay boot attempt $attempt outcome=$outcome"
  [ "$outcome" = "anchor" ] && { boot_ok=1; break; }
  kill $RLOGPID 2>/dev/null
done
echo "--- replay load line (expect 'REPLAY <- ... N logic frames') ---"
grep -aE "pad_replay: REPLAY <-|ANCHOR reached" "$RLOG" | head
$ADB -s $S shell am force-stop $PKG
kill $RLOGPID 2>/dev/null

# restore default pref
$ADB -s $S shell "run-as $PKG rm -f $HOME0/shared_prefs/opengoal-gk.xml" 2>/dev/null
echo "=== AFTER_DONE ==="
