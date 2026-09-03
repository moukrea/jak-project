#!/usr/bin/env bash
# Validator: simd ctest label passes on both backends, no regressions.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

echo "== phase-07-neon.sh validator =="

cmake --build build-arm64 --target goalc-diff-runner > /tmp/build.log 2>&1 || {
    echo "FAIL: build"; tail -30 /tmp/build.log; exit 1
}

COUNT=$(grep -l "tags:.*simd" test/diff/inputs/*.gc 2>/dev/null | wc -l)
if [ "$COUNT" -lt 8 ]; then
    echo "FAIL: only $COUNT simd tests (need >= 8)"
    exit 1
fi
echo "  ok: $COUNT simd tests"

cd build-arm64
OUT=$(ctest -L "simd" --output-on-failure 2>&1)
FAILED=$(echo "$OUT" | grep -cE "Failed" || true)
if [ "$FAILED" -gt 0 ]; then
    echo "FAIL: $FAILED simd tests failed"
    echo "$OUT" | tail -30
    exit 1
fi

# Regression: re-run full suite
REG=$(ctest --output-on-failure 2>&1)
REGFAIL=$(echo "$REG" | grep -cE "Failed" || true)
if [ "$REGFAIL" -gt 0 ]; then
    echo "FAIL: $REGFAIL regressions in other tags"
    echo "$REG" | tail -30
    exit 1
fi

echo "== phase-07-neon.sh PASSED =="
