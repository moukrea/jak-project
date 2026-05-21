#!/usr/bin/env bash
# Phase D3 (autoport): configure (idempotent) + incremental build of
# libgk.so for arm64-v8a Android. Mirrors d1_build.sh's shape, but
# targets the Activity-libgk.so build at android/CMakeLists.txt rather
# than the standalone D1 game/android-arm64/gk executable.
#
# Output: build-android/lib/arm64-v8a/libgk.so

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh

BUILD_DIR="build-android"
TOOLCHAIN="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"

if [ ! -f "$TOOLCHAIN" ]; then
    echo "FATAL: NDK toolchain file missing at $TOOLCHAIN" >&2
    echo "       Did scripts/install-android-toolchain.sh run successfully?" >&2
    exit 1
fi

if [ ! -f "$BUILD_DIR/CMakeCache.txt" ]; then
    echo "  configuring $BUILD_DIR (first time)..."
    cmake -S . -B "$BUILD_DIR" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
        -DANDROID_ABI=arm64-v8a \
        -DANDROID_PLATFORM=android-29 \
        -DGOALC_BACKEND=arm64 \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo
fi

echo "  building gk target (incremental; first build can take 3-5 min)..."
cmake --build "$BUILD_DIR" --target gk -j

OUT_LIB="$BUILD_DIR/lib/arm64-v8a/libgk.so"
if [ ! -f "$OUT_LIB" ]; then
    echo "FATAL: expected $OUT_LIB after build, not found" >&2
    exit 1
fi

echo "  libgk.so produced at $OUT_LIB ($(stat -c %s "$OUT_LIB") bytes)"
