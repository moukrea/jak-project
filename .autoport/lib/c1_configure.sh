#!/usr/bin/env bash
# Phase C1 (autoport, bucket C): idempotent CMake configure for the
# aarch64-linux cross-build of gk. The validator re-runs this and
# compares CMakeCache values for drift, so it must be deterministic.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

BUILD_DIR="build-arm64-linux"
TOOLCHAIN="$PWD/cmake/aarch64-linux-toolchain.cmake"

if [ ! -f "$TOOLCHAIN" ]; then
    echo "FAIL: $TOOLCHAIN missing — supervisor must author the toolchain" >&2
    exit 1
fi

# The toolchain file detects OG_LINUX_ARM64 before its OG_ARM64_STRESS
# default kicks in. We pass -DOG_LINUX_ARM64=ON explicitly so the divert
# branch in root CMakeLists.txt fires.
exec cmake -S . -B "$BUILD_DIR" \
    -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DOG_LINUX_ARM64=ON \
    -DOG_ARM64_STRESS=OFF \
    -DCMAKE_BUILD_TYPE=Release
