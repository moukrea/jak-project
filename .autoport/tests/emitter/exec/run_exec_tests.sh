#!/usr/bin/env bash
# Phase A7 — Level 1 exec tests.
#
# Each test_*.s is a static AArch64 ELF that uses direct syscalls (no libc)
# to exit with 42 if its emitter-shape semantic invariant holds, or with a
# non-42 status if not. We assemble + link with aarch64-linux-gnu-*, then
# execute under qemu-aarch64-static and assert exit code 42.

set -uo pipefail
cd "$(dirname "$0")"

AS=${AARCH64_AS:-aarch64-linux-gnu-as}
LD=${AARCH64_LD:-aarch64-linux-gnu-ld}
QEMU=${QEMU_AARCH64:-qemu-aarch64-static}

# Verify toolchain — fail with a clear message if cross binutils or qemu
# aren't installed. The CI/host image is expected to provide these.
for tool in "$AS" "$LD" "$QEMU"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FAIL: required tool not found: $tool" >&2
        exit 1
    fi
done

WORK=$(mktemp -d -t a7-exec.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
FAILURES=()

run_one() {
    local src="$1"
    local name
    name=$(basename "$src" .s)
    local obj="$WORK/$name.o"
    local elf="$WORK/$name"

    "$AS" -I "$(pwd)" -o "$obj" "$src" 2>"$WORK/$name.as.log" || {
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILURES+=("$name (assemble failed)")
        cat "$WORK/$name.as.log" >&2
        return
    }

    # Static link, no entry symbol resolution needed since we define _start.
    "$LD" -static -o "$elf" "$obj" 2>"$WORK/$name.ld.log" || {
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILURES+=("$name (link failed)")
        cat "$WORK/$name.ld.log" >&2
        return
    }

    # Run under qemu-aarch64-static. Expect exit code 42 = pass; anything
    # else = failure (1 = explicit fail from EXPECT_EQ_OR_FAIL; other = crash).
    "$QEMU" "$elf" >"$WORK/$name.stdout" 2>"$WORK/$name.stderr"
    local rc=$?
    if [ "$rc" -eq 42 ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  ok: $name (exit 42)"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILURES+=("$name (rc=$rc)")
        echo "  FAIL: $name exit=$rc" >&2
        [ -s "$WORK/$name.stderr" ] && cat "$WORK/$name.stderr" >&2
    fi
}

echo "Phase A7 exec tests (qemu-aarch64-static):"
for src in test_*.s; do
    [ -f "$src" ] || continue
    run_one "$src"
done

echo "exec tests: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -gt 0 ]; then
    for f in "${FAILURES[@]}"; do
        echo "  - $f" >&2
    done
    exit 1
fi
exit 0
