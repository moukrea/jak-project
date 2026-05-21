#!/usr/bin/env bash
# Phase D1 (autoport, bucket D): build the android-arm64 gk target.
# Separate from d1_configure.sh so the validator can re-run the build
# without forcing a clean reconfigure.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

BUILD_DIR="build-arm64-android"

if [ ! -f "$BUILD_DIR/CMakeCache.txt" ]; then
    echo "FAIL: $BUILD_DIR not configured yet — run d1_configure.sh first" >&2
    exit 1
fi

exec cmake --build "$BUILD_DIR" --target gk -j
