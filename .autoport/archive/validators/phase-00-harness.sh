#!/usr/bin/env bash
# Validator for phase 00: differential test harness exists and basic infra works.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

echo "== Phase 00 validator =="

# 1. Structure
test -d test/diff || { echo "FAIL: test/diff directory missing"; exit 1; }
test -d test/diff/inputs || { echo "FAIL: test/diff/inputs missing"; exit 1; }
test -d test/diff/runner || { echo "FAIL: test/diff/runner missing"; exit 1; }

# 2. At least 5 .gc inputs
COUNT=$(ls test/diff/inputs/*.gc 2>/dev/null | wc -l)
if [ "$COUNT" -lt 5 ]; then
    echo "FAIL: only $COUNT .gc inputs (need >= 5)"
    exit 1
fi
echo "  ok: $COUNT .gc inputs"

# 3. Build x86 default
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release > /tmp/cmake.log 2>&1 || {
    echo "FAIL: cmake configure failed"; cat /tmp/cmake.log; exit 1
}
cmake --build build --target goalc-diff-runner > /tmp/build.log 2>&1 || {
    echo "FAIL: build goalc-diff-runner failed"; tail -50 /tmp/build.log; exit 1
}
echo "  ok: build"

# 4. Runner exists
RUNNER=$(find build -name 'goalc-diff-runner' -type f -executable | head -1)
test -n "$RUNNER" || { echo "FAIL: goalc-diff-runner binary not found"; exit 1; }
echo "  ok: runner at $RUNNER"

# 5. ctest runs, at least 1 PASS
cd build
OUT=$(ctest -R goalc-diff --output-on-failure 2>&1) || true
echo "$OUT" | tail -30

if ! echo "$OUT" | grep -qE "[1-9][0-9]* (Passed|tests? passed)"; then
    echo "FAIL: no ctest passes for goalc-diff"
    exit 1
fi
echo "  ok: at least one diff-test passing"

echo "== Phase 00 validator PASSED =="
