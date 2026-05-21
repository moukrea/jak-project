#!/usr/bin/env bash
# Phase D1 (autoport, bucket D): idempotent CMake configure for the
# android-arm64 NDK cross-build of gk. The validator re-runs this and
# checks key CMakeCache values, so it must be deterministic.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

# Source the install-script-generated env so ANDROID_NDK_HOME +
# ANDROID_HOME are set without depending on the user's interactive
# shell startup. See .autoport/lib/android-env.sh for the canonical
# version validators use; we keep this self-contained so the
# configure script also works when invoked directly.
if [ -f "$HOME/.opengoal-android-env.sh" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.opengoal-android-env.sh"
fi
: "${ANDROID_NDK_HOME:=$HOME/Android/android-ndk-r27c}"
export ANDROID_NDK_HOME

if [ ! -d "$ANDROID_NDK_HOME" ]; then
    echo "FAIL: ANDROID_NDK_HOME=$ANDROID_NDK_HOME does not exist." >&2
    echo "      Run scripts/install-android-toolchain.sh first." >&2
    exit 1
fi

BUILD_DIR="build-arm64-android"
TOOLCHAIN="$PWD/cmake/android-arm64-toolchain.cmake"

if [ ! -f "$TOOLCHAIN" ]; then
    echo "FAIL: $TOOLCHAIN missing — D1 deliverable" >&2
    exit 1
fi

# Pass OG_ANDROID_ARM64=ON explicitly so the bucket-D divert branch in
# root CMakeLists.txt fires (rather than the phase-10 android/
# libgk.so Activity divert).
exec cmake -S . -B "$BUILD_DIR" \
    -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DOG_ANDROID_ARM64=ON \
    -DCMAKE_BUILD_TYPE=Release
