#!/usr/bin/env bash
# Validator for phase 09: gk boots under qemu-aarch64 to "target started".
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

echo "== Phase 09 validator =="

cmake --build build-arm64 --target gk > /tmp/build.log 2>&1 || {
    echo "FAIL: build gk"; tail -50 /tmp/build.log; exit 1
}

GK=$(find build-arm64 -name gk -type f -executable | head -1)
test -n "$GK" || { echo "FAIL: gk binary not found"; exit 1; }

# Boot it under qemu, capture output for up to 120 seconds
timeout 120 qemu-aarch64-static -L /usr/aarch64-linux-gnu "$GK" --boot --headless \
    > /tmp/gk.stdout 2> /tmp/gk.stderr || true

# Look for the success message — accept multiple possible strings
if grep -qE "target started|level zero loaded|kernel: target online" /tmp/gk.stdout /tmp/gk.stderr; then
    echo "  ok: gk reached boot completion"
else
    echo "FAIL: gk did not reach target-started message"
    echo "--- stdout (tail) ---"
    tail -40 /tmp/gk.stdout
    echo "--- stderr (tail) ---"
    tail -40 /tmp/gk.stderr
    exit 1
fi

echo "== Phase 09 validator PASSED =="
