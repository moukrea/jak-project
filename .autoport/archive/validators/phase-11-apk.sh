#!/usr/bin/env bash
# Validator for phase 11: APK builds, optionally installs and boots on emulator.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

echo "== Phase 11 validator =="

test -d android || { echo "FAIL: android/ directory missing"; exit 1; }
{ test -f android/gradlew || test -f android/app/build.gradle.kts; } || {
    echo "FAIL: no gradle project in android/"; exit 1
}

cd android
if [ -x ./gradlew ]; then
    ./gradlew assembleDebug > /tmp/gradle.log 2>&1 || {
        echo "FAIL: gradle assembleDebug"; tail -50 /tmp/gradle.log; exit 1
    }
else
    echo "FAIL: ./gradlew not executable"; exit 1
fi

APK=$(find app/build/outputs/apk/debug -name '*.apk' 2>/dev/null | head -1)
test -n "$APK" || { echo "FAIL: no APK produced"; exit 1; }
echo "  ok: $APK"

# Optional emulator test if adb is available and an emulator is running
if command -v adb >/dev/null && adb devices | grep -qE "emulator-|device$"; then
    adb install -r "$APK" > /tmp/adb-install.log 2>&1 || {
        echo "FAIL: adb install"; cat /tmp/adb-install.log; exit 1
    }
    echo "  ok: installed on emulator"
else
    echo "  (no emulator running; APK build check only)"
fi

echo "== Phase 11 validator PASSED =="
