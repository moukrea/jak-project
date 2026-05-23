#!/usr/bin/env bash
# Phase A8 — qemu-aarch64-static reproduction of the display.gc NULL
# fn-ptr BLR. Cross-builds the linux-arm64 gk, runs it under
# qemu-aarch64-static with the KERNEL.CGO + ENGINE.CGO + GAME.CGO load
# pipeline (EXECUTE on for all), captures stdout+stderr to a log.
#
# Wall-clock: ~30-60 s per cycle vs ~3 min per device cycle, so this is
# the primary debug loop for the residual A8 work.
#
# Exit codes:
#   0  qemu run completed (the SCRIPT exits 0 even if qemu crashed —
#      crash detection is the caller's job; the diag dump is in the log).
#   1  prereq missing (qemu, c1_configure.sh, arm64 KERNEL/ENGINE/GAME).
#   2  configure failed.
#   3  build failed.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

REPORTS_DIR=".autoport/reports"
LOG="${1:-$REPORTS_DIR/A8-qemu-repro.log}"
EXIT_TXT="${LOG%.log}-exit.txt"
BUILD_DIR="build-arm64-linux"
CFG_SCRIPT=".autoport/lib/c1_configure.sh"
ARM64_KERNEL_CGO="out/jak1-arm64/iso/KERNEL.CGO"
ARM64_ENGINE_CGO="out/jak1-arm64/iso/ENGINE.CGO"
ARM64_GAME_CGO="out/jak1-arm64/iso/GAME.CGO"

QEMU=$(command -v qemu-aarch64-static || command -v qemu-aarch64)
SYSROOT="/usr/aarch64-linux-gnu"

if [ -z "$QEMU" ]; then
    echo "FATAL: qemu-aarch64-static / qemu-aarch64 not found in PATH" >&2
    exit 1
fi
if [ ! -x "$CFG_SCRIPT" ]; then
    echo "FATAL: $CFG_SCRIPT missing or not executable" >&2
    exit 1
fi
for f in "$ARM64_KERNEL_CGO" "$ARM64_ENGINE_CGO" "$ARM64_GAME_CGO"; do
    if [ ! -f "$f" ]; then
        echo "FATAL: $f missing — run .autoport/lib/build_b1_arm64_cgos.sh" >&2
        exit 1
    fi
done

mkdir -p "$REPORTS_DIR"

if [ ! -f "$BUILD_DIR/CMakeCache.txt" ]; then
    echo "qemu_repro.sh: configuring build-arm64-linux..."
    "$CFG_SCRIPT" > /tmp/qemu_repro-configure.log 2>&1
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "FATAL: configure failed (exit $rc); see /tmp/qemu_repro-configure.log" >&2
        tail -20 /tmp/qemu_repro-configure.log >&2
        exit 2
    fi
fi

echo "qemu_repro.sh: building gk target..."
cmake --build "$BUILD_DIR" --target gk -j > /tmp/qemu_repro-build.log 2>&1
rc=$?
if [ $rc -ne 0 ]; then
    echo "FATAL: build failed (exit $rc); see /tmp/qemu_repro-build.log" >&2
    tail -40 /tmp/qemu_repro-build.log >&2
    exit 3
fi

GK=$(find "$BUILD_DIR" -name gk -type f -executable | head -1)
if [ -z "$GK" ] || [ ! -x "$GK" ]; then
    echo "FATAL: no executable gk under $BUILD_DIR/ after build" >&2
    exit 3
fi

> "$LOG"
echo "# qemu_repro.sh — qemu=$QEMU sysroot=$SYSROOT" >> "$LOG"
echo "# gk=$GK ($(stat -c %s "$GK") bytes)" >> "$LOG"
echo "# kernel.cgo=$ARM64_KERNEL_CGO ($(stat -c %s "$ARM64_KERNEL_CGO") bytes, sha=$(sha256sum "$ARM64_KERNEL_CGO" | awk '{print $1}'))" >> "$LOG"
echo "# engine.cgo=$ARM64_ENGINE_CGO ($(stat -c %s "$ARM64_ENGINE_CGO") bytes, sha=$(sha256sum "$ARM64_ENGINE_CGO" | awk '{print $1}'))" >> "$LOG"
echo "# game.cgo=$ARM64_GAME_CGO ($(stat -c %s "$ARM64_GAME_CGO") bytes, sha=$(sha256sum "$ARM64_GAME_CGO" | awk '{print $1}'))" >> "$LOG"
echo "# date=$(date -Iseconds)" >> "$LOG"
echo "# args=${*:2}" >> "$LOG"
echo "# ----" >> "$LOG"

echo "qemu_repro.sh: invoking $QEMU on $GK (timeout 180s)..."
set +e
timeout --kill-after=5s 180s "$QEMU" -L "$SYSROOT" "$GK" "${@:2}" >> "$LOG" 2>&1
qemu_rc=$?
set -e

echo "$qemu_rc" > "$EXIT_TXT"
echo ""
echo "qemu_repro.sh: qemu exit code $qemu_rc (captured to $EXIT_TXT)"
echo "qemu_repro.sh: log at $LOG ($(wc -l < "$LOG") lines)"
if grep -q "GK-DIAG sig=" "$LOG"; then
    echo "qemu_repro.sh: GK-DIAG signal handler fired; first 6 lines:"
    grep "GK-DIAG" "$LOG" | head -6
fi
exit 0
