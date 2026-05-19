#!/usr/bin/env bash
# Phase 26 validator: run real-runtime gk under qemu-aarch64, capture
# GOAL VM observable counters, assert real execution happened.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

echo "== Phase 26 validator (real CGO execution under qemu-aarch64) =="

command -v qemu-aarch64-static >/dev/null 2>&1 \
    || { echo "FAIL: qemu-aarch64-static not on PATH"; exit 1; }
test -f /usr/aarch64-linux-gnu/lib/ld-linux-aarch64.so.1 \
    || { echo "FAIL: aarch64 sysroot missing (install glibc-aarch64-linux-gnu)"; exit 1; }

# 1. Build the arm64-linux stress target.
BUILD_DIR=build-arm64-linux
if [ ! -f "$BUILD_DIR/CMakeCache.txt" ]; then
    echo "FAIL: $BUILD_DIR/ not configured. Phase 26 implementation must"
    echo "      add an arm64-linux cross-build (CMake toolchain file) at"
    echo "      this path with the goal_stress_arm64 target."
    exit 1
fi
echo "== building goal_stress_arm64 =="
cmake --build "$BUILD_DIR" --target goal_stress_arm64 -j > /tmp/p26-build.log 2>&1 \
    || { tail -60 /tmp/p26-build.log; echo "FAIL: cross-build of goal_stress_arm64"; exit 1; }
BIN=$(find "$BUILD_DIR" -name goal_stress_arm64 -type f -executable | head -1)
test -x "$BIN" || { echo "FAIL: goal_stress_arm64 binary not produced"; exit 1; }
echo "  binary: $BIN"

# 2. CGOs must be present from phase 25.
ISO_DIR="$(pwd)/out/jak1/iso"
test -f "$ISO_DIR/KERNEL.CGO" || { echo "FAIL: missing $ISO_DIR/KERNEL.CGO (phase 25 regen needed)"; exit 1; }

# 3. Run under qemu and capture output.
LOG=/tmp/p26-qemu.log
: > "$LOG"
echo "== launching gk under qemu-aarch64 =="
timeout 600 qemu-aarch64-static -L /usr/aarch64-linux-gnu \
    "$BIN" --game jak1 --portable -fakeiso \
    -iso-data "$ISO_DIR" --max-frames 600 \
    > "$LOG" 2>&1
QEMU_RC=$?
echo "  qemu exit: $QEMU_RC"

# 4. Fault check.
if grep -qE 'SIGILL|Illegal instruction|SIGSEGV|Segmentation fault|qemu: uncaught|qemu: fatal' "$LOG"; then
    echo "FAIL: qemu reported a fault during GOAL execution — emitter bug surfaced"
    grep -nE 'SIGILL|SIGSEGV|qemu: uncaught|qemu: fatal|pc=' "$LOG" | head -20
    exit 1
fi

# 5. Counters check.
STATS_LINE=$(grep -E '^goal-stress:' "$LOG" | tail -1)
if [ -z "$STATS_LINE" ]; then
    echo "FAIL: no 'goal-stress:' counter line in qemu output"
    echo "--- last 60 lines of qemu output ---"
    tail -60 "$LOG"
    exit 1
fi
echo "  $STATS_LINE"

kheap_delta=$(echo "$STATS_LINE"     | grep -oE 'kheap-delta=[0-9]+'      | grep -oE '[0-9]+')
symbols_interned=$(echo "$STATS_LINE"| grep -oE 'symbols-interned=[0-9]+' | grep -oE '[0-9]+')
goal_calls=$(echo "$STATS_LINE"      | grep -oE 'goal-calls=[0-9]+'       | grep -oE '[0-9]+')

if [ "${kheap_delta:-0}" -lt 1048576 ]; then
    echo "FAIL: kheap-delta=${kheap_delta:-0} < 1 MB — GOAL kernel did not perform meaningful allocations"
    exit 1
fi
if [ "${symbols_interned:-0}" -lt 50 ]; then
    echo "FAIL: symbols-interned=${symbols_interned:-0} < 50 — symbol table is not alive"
    exit 1
fi
if [ "${goal_calls:-0}" -lt 100 ]; then
    echo "FAIL: goal-calls=${goal_calls:-0} < 100 — dispatcher did not run GOAL code"
    exit 1
fi

# 6. Cross-check: a stub that prints fixed counters would print the same
# numbers run-to-run. Re-launch with --max-frames 300 (half the work);
# at least one counter must change.
echo "== re-running with --max-frames 300 for run-to-run variance check =="
LOG2=/tmp/p26-qemu-2.log
timeout 600 qemu-aarch64-static -L /usr/aarch64-linux-gnu \
    "$BIN" --game jak1 --portable -fakeiso \
    -iso-data "$ISO_DIR" --max-frames 300 \
    > "$LOG2" 2>&1 || true
STATS_LINE2=$(grep -E '^goal-stress:' "$LOG2" | tail -1)
echo "  $STATS_LINE2"
if [ "$STATS_LINE" = "$STATS_LINE2" ]; then
    echo "FAIL: counters identical between 600-frame and 300-frame runs — looks like a constant printf, not real execution"
    exit 1
fi

echo
echo "== Phase 26 validator PASSED =="
echo "   GOAL VM executed real jak1 code under qemu-aarch64:"
echo "     kheap-delta=$kheap_delta bytes, symbols=$symbols_interned, goal-calls=$goal_calls"
echo "   Counters vary run-to-run (stub-detection cross-check OK)."
