#!/usr/bin/env bash
# Validator for phase 01: arm64 emitter scaffold compiles, both backends build.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

echo "== Phase 01 validator =="

# x86 build still works
cmake -B build-x86 -G Ninja > /tmp/cmake-x86.log 2>&1
cmake --build build-x86 --target goalc > /tmp/build-x86.log 2>&1 || {
    echo "FAIL: x86 build broken"; tail -50 /tmp/build-x86.log; exit 1
}
echo "  ok: x86 build"

# arm64 scaffold build
cmake -B build-arm64 -G Ninja -DGOALC_BACKEND=arm64 > /tmp/cmake-arm.log 2>&1 || {
    echo "FAIL: cmake configure arm64 failed"; cat /tmp/cmake-arm.log; exit 1
}
cmake --build build-arm64 --target goalc > /tmp/build-arm.log 2>&1 || {
    echo "FAIL: arm64 build failed"; tail -50 /tmp/build-arm.log; exit 1
}
echo "  ok: arm64 build"

# IGen_arm64 symbols present
# NOTE: must not pipe nm directly into `grep -q`. The goalc binary's nm output
# is larger than the kernel pipe buffer (~64KB), so `grep -q` exits at the
# first match while nm is still writing; nm then dies with SIGPIPE and
# `set -o pipefail` turns that into a spurious failure. Capturing into a
# variable lets grep drain the full pipe.
GOALC_ARM=$(find build-arm64 -name 'goalc' -type f -executable | head -1)
NM_MATCH=$(nm "$GOALC_ARM" 2>/dev/null | grep IGen_arm64 || true)
if [ -z "$NM_MATCH" ]; then
    echo "FAIL: IGen_arm64 symbols not found in goalc"
    exit 1
fi
echo "  ok: IGen_arm64 symbols present"

# --version advertises arm64
"$GOALC_ARM" --version 2>&1 | grep -qi arm64 || {
    echo "FAIL: goalc --version doesn't mention arm64"
    exit 1
}
echo "  ok: version string"

echo "== Phase 01 validator PASSED =="
