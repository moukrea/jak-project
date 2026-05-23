#!/usr/bin/env bash
# Phase A7 — emitter unit-test harness entrypoint.
#
# Runs the Level-0 encoding tests (real IGenARM64.cpp compiled into a small
# test binary, asserting per-helper encodings against ARM ISA references)
# then the Level-1 exec tests (handwritten arm64 asm exercised under
# qemu-aarch64-static). Exit 0 iff every assertion + qemu run succeeds.
# Designed to run in under 30 seconds cold-start on the validator host.

set -uo pipefail
cd "$(dirname "$0")"

ROOT="$(cd ../../.. && pwd)"
BUILD_DIR="$(pwd)/build"

mkdir -p "$BUILD_DIR"

echo "=== Phase A7 emitter unit tests ==="
echo "  repo root: $ROOT"
echo "  build dir: $BUILD_DIR"

# --- Level 0: encoding tests ---
echo ""
echo "--- Level 0 (encoding tests) ---"
cmake -B "$BUILD_DIR" -S encoding -DREPO_ROOT="$ROOT" -DCMAKE_BUILD_TYPE=Release \
    > "$BUILD_DIR/cmake.log" 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then
    echo "FAIL: cmake configure failed" >&2
    tail -40 "$BUILD_DIR/cmake.log" >&2
    exit 1
fi

cmake --build "$BUILD_DIR" -j"$(nproc 2>/dev/null || echo 4)" --target encoding_tests \
    > "$BUILD_DIR/build.log" 2>&1
RC=$?
if [ "$RC" -ne 0 ]; then
    echo "FAIL: cmake --build failed" >&2
    tail -60 "$BUILD_DIR/build.log" >&2
    exit 1
fi

"$BUILD_DIR/encoding_tests"
RC=$?
if [ "$RC" -ne 0 ]; then
    echo "FAIL: encoding tests reported failures" >&2
    exit 1
fi

# --- Level 1: exec tests ---
echo ""
echo "--- Level 1 (qemu-aarch64-static exec tests) ---"
bash exec/run_exec_tests.sh
RC=$?
if [ "$RC" -ne 0 ]; then
    echo "FAIL: exec tests reported failures" >&2
    exit 1
fi

echo ""
echo "OK: all emitter unit tests passed"
exit 0
