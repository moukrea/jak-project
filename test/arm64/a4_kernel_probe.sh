#!/usr/bin/env bash
# Phase A4 — kernel-symbol probe driver.
#
# Cross-compiles test/arm64/a4_kernel_probe.c to AArch64 and runs it
# under qemu-aarch64-static, pointed at the freshly-built jak1
# KERNEL.CGO. The probe parses the v3 link table of gcommon (the
# first object in KERNEL.CGO) and prints a stable nonzero integer
# derived from the sorted symbol-reference set — see the .c file
# header for the exact formula.
#
# Output: a single integer line. The validator captures stdout and
# diffs against .autoport/reports/A4-kernel-probe.txt; they MUST
# match byte-for-byte.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

PROBE_C="test/arm64/a4_kernel_probe.c"
PROBE_ELF="test/arm64/build/a4_kernel_probe.elf"
KERNEL_CGO="${KERNEL_CGO:-out/jak1/iso/KERNEL.CGO}"

if [ ! -f "$PROBE_C" ]; then
    echo "FAIL: $PROBE_C missing" >&2
    exit 1
fi
if [ ! -f "$KERNEL_CGO" ]; then
    echo "FAIL: $KERNEL_CGO missing (build jak1 first)" >&2
    exit 1
fi

mkdir -p "$(dirname "$PROBE_ELF")"

# Cross-compile statically so qemu-aarch64-static can run it without a
# dynamic linker. -fno-strict-aliasing keeps the buffer reads safe (the
# file is read as a byte array then reinterpreted via read_u32 helpers).
aarch64-linux-gnu-gcc -O2 -static -fno-strict-aliasing \
    "$PROBE_C" -o "$PROBE_ELF" 2>/dev/null || {
    echo "FAIL: cross-compile of $PROBE_C failed" >&2
    exit 1
}

exec qemu-aarch64-static "$PROBE_ELF" "$KERNEL_CGO"
