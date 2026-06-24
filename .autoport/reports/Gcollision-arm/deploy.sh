#!/usr/bin/env bash
set -uo pipefail
cd /home/emeric/code/jak-project
ADB=/home/emeric/Android/platform-tools/adb
echo "=== gradle slim APK ==="
( cd android && ./gradlew assembleJak1Debug -PslimIso=true ) 2>&1 | tail -15
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk
echo "=== install ==="
$ADB -s eae4df44 push "$APK" /data/local/tmp/app.apk
$ADB -s eae4df44 shell pm install -r -d -t -i com.android.vending /data/local/tmp/app.apk || {
  bash -c '. .autoport/lib/device-validate.sh; device_miui_unblock_install eae4df44' 2>/dev/null || true
  $ADB -s eae4df44 shell pm install -r -d -t -i com.android.vending /data/local/tmp/app.apk
}
$ADB -s eae4df44 shell rm -f /data/local/tmp/app.apk
echo "=== deploy_verify ==="
bash .autoport/lib/deploy_verify.sh eae4df44
echo "DEPLOY_DONE exit=$?"
