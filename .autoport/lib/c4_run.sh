#!/usr/bin/env bash
# Phase C4 reproducible qemu-aarch64 run wrapper.
#
# Same shape as c3_run.sh, but writes C4-boot.log / C4-exit.txt and
# uses a slightly longer timeout (180s) because the EXECUTE-on link
# of all 8 KERNEL.CGO objects under qemu-user runs the top-level
# GOAL functions in addition to relocating, so the wall-clock is
# longer than C3's relocate-only run.
#
# What it does:
#   1. Ensure build-arm64-linux is configured (delegates to C1).
#   2. cmake --build build-arm64-linux --target gk -j (incremental
#      when CMakeCache already exists).
#   3. Sanity-check out/jak1-arm64/iso/KERNEL.CGO exists (B1 output).
#   4. Invoke gk under qemu-aarch64-static with a 180 s timeout.
#   5. Capture stdout+stderr to .autoport/reports/C4-boot.log and the
#      exit code to .autoport/reports/C4-exit.txt.
#
# Determinism: rerunning on the same source tree produces the same
# boot log modulo wall-clock timestamps. The C4 validator only checks
# for the presence of specific upstream markers and the post-execute
# banner, not for byte-equality of the log.
#
# Exit codes from this wrapper:
#   0  success (qemu run + log capture completed). Wrapper does NOT
#      itself assert the run succeeded — that's the validator's job.
#   1  prereq missing (qemu, c1_configure.sh, or arm64 KERNEL.CGO).
#   2  configure failed.
#   3  build failed.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

REPORTS_DIR=".autoport/reports"
BOOT_LOG="${REPORTS_DIR}/C4-boot.log"
EXIT_TXT="${REPORTS_DIR}/C4-exit.txt"
BUILD_DIR="build-arm64-linux"
CFG_SCRIPT=".autoport/lib/c1_configure.sh"
ARM64_KERNEL_CGO="out/jak1-arm64/iso/KERNEL.CGO"

QEMU=$(command -v qemu-aarch64-static || command -v qemu-aarch64)
SYSROOT="/usr/aarch64-linux-gnu"

if [ -z "$QEMU" ]; then
    echo "FATAL: qemu-aarch64-static / qemu-aarch64 not found in PATH" >&2
    exit 1
fi
if [ ! -x "$CFG_SCRIPT" ]; then
    echo "FATAL: $CFG_SCRIPT missing or not executable (C1 deliverable)" >&2
    exit 1
fi
if [ ! -f "$ARM64_KERNEL_CGO" ]; then
    echo "FATAL: $ARM64_KERNEL_CGO missing — run B1 (build_b1_arm64_cgos.sh) first" >&2
    exit 1
fi

mkdir -p "$REPORTS_DIR"

# Configure if needed. c1_configure.sh is idempotent.
if [ ! -f "$BUILD_DIR/CMakeCache.txt" ]; then
    echo "c4_run.sh: configuring build-arm64-linux..."
    "$CFG_SCRIPT" > /tmp/c4_run-configure.log 2>&1
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "FATAL: configure failed (exit $rc); see /tmp/c4_run-configure.log" >&2
        tail -20 /tmp/c4_run-configure.log >&2
        exit 2
    fi
fi

# Build gk (incremental).
echo "c4_run.sh: building gk target..."
cmake --build "$BUILD_DIR" --target gk -j > /tmp/c4_run-build.log 2>&1
rc=$?
if [ $rc -ne 0 ]; then
    echo "FATAL: build failed (exit $rc); see /tmp/c4_run-build.log" >&2
    tail -40 /tmp/c4_run-build.log >&2
    exit 3
fi

# Locate the produced gk binary.
GK=$(find "$BUILD_DIR" -name gk -type f -executable | head -1)
if [ -z "$GK" ] || [ ! -x "$GK" ]; then
    echo "FATAL: no executable gk under $BUILD_DIR/ after build" >&2
    exit 3
fi

# Drop stale log.
> "$BOOT_LOG"

echo "c4_run.sh: invoking $QEMU on $GK (timeout 180s)..."
echo "# c4_run.sh — qemu=$QEMU sysroot=$SYSROOT" >> "$BOOT_LOG"
echo "# gk=$GK" >> "$BOOT_LOG"
echo "# arm64_kernel_cgo=$ARM64_KERNEL_CGO" >> "$BOOT_LOG"
echo "# arm64_kernel_cgo_size=$(stat -c %s "$ARM64_KERNEL_CGO") bytes" >> "$BOOT_LOG"
echo "# arm64_kernel_cgo_sha=$(sha256sum "$ARM64_KERNEL_CGO" | awk '{print $1}')" >> "$BOOT_LOG"
echo "# date=$(date -Iseconds)" >> "$BOOT_LOG"
echo "# ----" >> "$BOOT_LOG"

set +e
timeout --kill-after=5s 180s "$QEMU" -L "$SYSROOT" "$GK" >> "$BOOT_LOG" 2>&1
qemu_rc=$?
set -e

echo "$qemu_rc" > "$EXIT_TXT"
echo ""
echo "c4_run.sh: qemu exit code $qemu_rc (captured to $EXIT_TXT)"
echo "c4_run.sh: boot log at $BOOT_LOG ($(wc -l < "$BOOT_LOG") lines)"
exit 0
