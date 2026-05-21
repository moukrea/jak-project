#!/usr/bin/env bash
# Phase C2 reproducible qemu-aarch64 run wrapper.
#
# What it does:
#   1. Ensure build-arm64-linux is configured (delegates to C1's
#      c1_configure.sh — no duplicate logic).
#   2. cmake --build build-arm64-linux --target gk -j (incremental
#      when CMakeCache already exists).
#   3. Invoke gk under qemu-aarch64-static with a 60 s timeout, no
#      arguments (so the boot driver takes the default path:
#      remap-and-init).
#   4. Capture stdout+stderr to .autoport/reports/C2-boot.log and the
#      wall-clock exit code to .autoport/reports/C2-exit.txt.
#
# Determinism: rerunning on the same source tree produces the same boot
# log modulo wall-clock timestamps (qemu, ASLR, the kernel-heap-init
# duration). The C2 validator only checks for the presence of specific
# upstream markers, not for byte-equality of the log, so this script
# does not need extra normalisation.
#
# Exit codes from this wrapper:
#   0  success (qemu run + log capture completed; doesn't itself assert
#      that the run was successful — that's the validator's job).
#   1  prereq missing (qemu, toolchain, c1_configure.sh).
#   2  configure failed.
#   3  build failed.
#   4  qemu invocation failed in a way that didn't even produce a log
#      (qemu binary missing, fork failure). A SIGSEGV inside gk
#      produces a log with a "qemu: uncaught target signal" line and
#      this script still exits 0 — validator catches the failure.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

REPORTS_DIR=".autoport/reports"
BOOT_LOG="${REPORTS_DIR}/C2-boot.log"
EXIT_TXT="${REPORTS_DIR}/C2-exit.txt"
BUILD_DIR="build-arm64-linux"
CFG_SCRIPT=".autoport/lib/c1_configure.sh"

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

mkdir -p "$REPORTS_DIR"

# Configure if needed. The c1_configure.sh is idempotent (the C1
# validator's check 16 enforces that), so calling it unconditionally
# is fine.
if [ ! -f "$BUILD_DIR/CMakeCache.txt" ]; then
    echo "c2_run.sh: configuring build-arm64-linux..."
    "$CFG_SCRIPT" > /tmp/c2_run-configure.log 2>&1
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "FATAL: configure failed (exit $rc); see /tmp/c2_run-configure.log" >&2
        tail -20 /tmp/c2_run-configure.log >&2
        exit 2
    fi
fi

# Build gk (incremental when objects up-to-date).
echo "c2_run.sh: building gk target..."
cmake --build "$BUILD_DIR" --target gk -j > /tmp/c2_run-build.log 2>&1
rc=$?
if [ $rc -ne 0 ]; then
    echo "FATAL: build failed (exit $rc); see /tmp/c2_run-build.log" >&2
    tail -40 /tmp/c2_run-build.log >&2
    exit 3
fi

# Locate the produced gk binary.
GK=$(find "$BUILD_DIR" -name gk -type f -executable | head -1)
if [ -z "$GK" ] || [ ! -x "$GK" ]; then
    echo "FATAL: no executable gk under $BUILD_DIR/ after build" >&2
    exit 3
fi

# Drop any stale log so a partial run doesn't shadow a clean re-run.
> "$BOOT_LOG"

echo "c2_run.sh: invoking $QEMU on $GK (timeout 60s)..."
echo "# c2_run.sh — qemu=$QEMU sysroot=$SYSROOT" >> "$BOOT_LOG"
echo "# gk=$GK" >> "$BOOT_LOG"
echo "# date=$(date -Iseconds)" >> "$BOOT_LOG"
echo "# ----" >> "$BOOT_LOG"

# `set +e` to capture the exit code below.
set +e
timeout --kill-after=5s 60s "$QEMU" -L "$SYSROOT" "$GK" >> "$BOOT_LOG" 2>&1
qemu_rc=$?
set -e

echo "$qemu_rc" > "$EXIT_TXT"
echo ""
echo "c2_run.sh: qemu exit code $qemu_rc (captured to $EXIT_TXT)"
echo "c2_run.sh: boot log at $BOOT_LOG ($(wc -l < "$BOOT_LOG") lines)"

# Note: a SIGSEGV / SIGILL / abort inside gk shows up in the log as
# "qemu: uncaught target signal 11/4". The validator catches these via
# its check 20 grep — c2_run.sh just captures, doesn't judge.
exit 0
