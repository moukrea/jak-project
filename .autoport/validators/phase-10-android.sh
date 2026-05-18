#!/usr/bin/env bash
# Validator for phase 10: Android NDK cross-build produces an arm64 ELF.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

echo "== Phase 10 validator =="

[ -n "${ANDROID_NDK_HOME:-}" ] || {
    echo "FAIL: ANDROID_NDK_HOME not set"
    exit 1
}
[ -d "$ANDROID_NDK_HOME" ] || {
    echo "FAIL: ANDROID_NDK_HOME=$ANDROID_NDK_HOME not a directory"
    exit 1
}

cmake -B build-android -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-29 \
    -DGOALC_BACKEND=arm64 \
    > /tmp/cmake-android.log 2>&1 || {
    echo "FAIL: cmake configure"; cat /tmp/cmake-android.log; exit 1
}

cmake --build build-android --target gk > /tmp/build-android.log 2>&1 || {
    echo "FAIL: build gk for android"; tail -50 /tmp/build-android.log; exit 1
}

GK=$(find build-android \( -name 'libgk.so' -o -name 'gk' \) | head -1)
test -n "$GK" || { echo "FAIL: no gk binary"; exit 1; }

FILE_INFO=$(file "$GK")
echo "  $FILE_INFO"
if ! echo "$FILE_INFO" | grep -qiE "aarch64|arm aarch"; then
    echo "FAIL: gk is not aarch64"; exit 1
fi

echo "== Phase 10 validator PASSED =="
