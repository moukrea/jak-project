#!/usr/bin/env bash
# BEFORE: overlay DISABLED (== a gamepad present at first launch / user-off persisted state).
# warp+record, drive adb-input touch -> expect ALL-NEUTRAL (overlay absent => real touch never
# reaches on_pad_* => get_cpad_state neutral => recorded all-neutral). Drop point demonstrated.
set -uo pipefail
ADB=/home/emeric/Android/platform-tools/adb
S=eae4df44; PKG=org.opengoal.gk.jak1
OUT=/home/emeric/code/jak-project/.autoport/reports/Ginput-replay-realinput
LOG="$OUT/before_off_logcat.txt"
HOME0=/data/user/0/$PKG

set_pref_off() {
  printf "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n<map>\n    <boolean name=\"touch_overlay_initialised\" value=\"true\" />\n    <boolean name=\"touch_overlay_enabled\" value=\"false\" />\n</map>\n" > /tmp/ovpref.xml
  $ADB -s $S push /tmp/ovpref.xml /data/local/tmp/ovpref.xml >/dev/null 2>&1
  $ADB -s $S shell chmod 644 /data/local/tmp/ovpref.xml
  $ADB -s $S shell "run-as $PKG cp /data/local/tmp/ovpref.xml $HOME0/shared_prefs/opengoal-gk.xml"
}

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
  [ "$outcome" = "anchor" ] && { boot_ok=1; break; }
  kill $LOGPID 2>/dev/null
done
[ "$boot_ok" = 1 ] || { echo "BOOT FAILED"; $ADB -s $S shell am force-stop $PKG; kill $LOGPID 2>/dev/null; exit 2; }

echo "=== overlay setup lines (expect DISABLED, NO overlay-map) ==="
grep -aE "touch overlay (setting|enabled|disabled)|overlay-map:|disabled by settings" "$LOG" | head

echo "=== drive adb touch (same coords that captured ~70% with overlay ON) ==="
SX=356; SY=635
for r in 1 2 3 4 5 6; do
  $ADB -s $S shell input swipe $SX $SY $SX 420 1000
  $ADB -s $S shell input swipe $SX $SY 620 $SY 1000
  $ADB -s $S shell input tap 1976 755
done
sleep 3
echo "  overlay-actuate lines: $(grep -ac 'overlay-actuate' "$LOG")  (expect 0)"
echo "  onPadAxis JNI markers : $(grep -acE 'onPadAxis|axis path' "$LOG")"
$ADB -s $S shell am force-stop $PKG
kill $LOGPID 2>/dev/null
$ADB -s $S exec-out run-as $PKG cat files/pad_demo.inputs > "$OUT/before_off.inputs" 2>/dev/null
ls -la "$OUT/before_off.inputs"
python3 "$OUT/analyze_inputs.py" "$OUT/before_off.inputs"
echo "=== DONE_OFF ==="
