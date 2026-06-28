#!/usr/bin/env bash
# Build (APK/dex; libgk.so unchanged — Java-only fix) + install + deploy_verify.
set -uo pipefail
cd /home/emeric/code/jak-project
source .autoport/lib/android-env.sh
ADB=/home/emeric/Android/platform-tools/adb
S=eae4df44; PKG=org.opengoal.gk.jak1
APK=android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk

echo "=== libgk pre-build sha + mtime (expect UNCHANGED — no C++ edit) ==="
sha256sum build-android/lib/arm64-v8a/libgk.so 2>/dev/null
echo "=== cmake --build gk (up-to-date no-op expected) ==="
cmake --build build-android --target gk -j"$(nproc)" 2>&1 | tail -6
[ -f build-android/lib/arm64-v8a/libgk.so ] || { echo "FAIL libgk missing"; exit 1; }
echo "=== gradle assembleJak1Debug (recompiles Java/dex) ==="
( cd android && ./gradlew assembleJak1Debug 2>&1 | tail -30 ) || { echo "FAIL gradle"; exit 1; }
[ -f "$APK" ] || { echo "FAIL no APK"; exit 1; }
echo "=== libgk post-build sha (must equal pre) ==="
sha256sum build-android/lib/arm64-v8a/libgk.so
echo "=== install -r (keep app data: iso_data/CGOs persist) ==="
$ADB -s $S shell appops set com.android.shell REQUEST_INSTALL_PACKAGES allow 2>/dev/null || true
$ADB -s $S shell pm trim-caches 999G 2>/dev/null || true
$ADB -s $S install -r -d -t -i com.android.vending "$APK" 2>&1 | tail -3
echo "=== deploy_verify (build==APK==device) ==="
bash .autoport/lib/deploy_verify.sh "$S" 2>&1 | tail -6
echo "=== BUILD_DONE ==="
