#!/usr/bin/env bash
# Validator: mem-ops ctest label passes on both backends, no regressions.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

echo "== phase-03-memops.sh validator =="

cmake --build build-arm64 --target goalc-diff-runner > /tmp/build.log 2>&1 || {
    echo "FAIL: build"; tail -30 /tmp/build.log; exit 1
}

COUNT=$(grep -l "tags:.*mem-ops" test/diff/inputs/*.gc 2>/dev/null | wc -l)
if [ "$COUNT" -lt 10 ]; then
    echo "FAIL: only $COUNT mem-ops tests (need >= 10)"
    exit 1
fi
echo "  ok: $COUNT mem-ops tests"

cd build-arm64
OUT=$(ctest -L "mem-ops" --output-on-failure 2>&1)
FAILED=$(echo "$OUT" | grep -cE "Failed" || true)
if [ "$FAILED" -gt 0 ]; then
    echo "FAIL: $FAILED mem-ops tests failed"
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

echo "== phase-03-memops.sh PASSED =="
