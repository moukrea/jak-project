#!/usr/bin/env bash
set -uo pipefail
ADB=~/Android/platform-tools/adb; SER=eae4df44; PKG=org.opengoal.gk.jak1
OUT=/home/emeric/code/jak-project/.autoport/reports/Grecharged-pbr-realtime-fusion/device
$ADB -s $SER shell am force-stop $PKG; sleep 2
$ADB -s $SER logcat -c
$ADB -s $SER logcat > /tmp/gpbrf2_roughaudit_raw.log 2>/dev/null &
LCPID=$!
$ADB -s $SER shell am start -W -n $PKG/.LoaderActivity >/dev/null 2>&1
sleep 110
kill $LCPID 2>/dev/null
FOCUS=$($ADB -s $SER shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r')
echo "focus: $FOCUS"
grep -a 'pbr roughness data\|pbr binding: vil1-sages-stonewall-01 \|custom pbr material registered: vil1-sages-stonewall-01' /tmp/gpbrf2_roughaudit_raw.log > "$OUT/logcat-roughness-audit.log"
echo "focus: $FOCUS" >> "$OUT/logcat-roughness-audit.log"
echo "=== audit lines captured:"
grep -a -c 'pbr roughness data' /tmp/gpbrf2_roughaudit_raw.log
grep -a 'pbr roughness data' /tmp/gpbrf2_roughaudit_raw.log | head -12
