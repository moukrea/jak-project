#!/usr/bin/env bash
# Phase 19 validator: delegate to .autoport/lib/emitter_stress.sh.
#
# This validator is intentionally thin. The actual checks — toolchain
# availability, qemu smoke on gk, CGO format integrity, CGO architecture
# detection, and AArch64 emitter coverage inventory — live in the lib
# script so they can be invoked standalone, and so the validator's role
# is reduced to "wire up the right entry point and surface the exit
# code".
#
# Pass conditions (enforced by the lib script):
#   - cross-toolchain (qemu-aarch64-static + binutils-aarch64-linux-gnu
#     + glibc-aarch64-linux-gnu sysroot) present
#   - build-arm64/gk builds and runs cleanly under qemu 10x without
#     SIGILL / SIGSEGV / "qemu: uncaught" / "qemu: fatal"
#   - out/jak1/iso/*.CGO files parse as valid V3 OpenGOAL OBJs with
#     hundreds of objects + code segments accounted for
#   - if CGO architecture is AArch64 (upstream emitter is real), apply
#     strict decode-stress gates; otherwise document the gap and
#     defer runtime stress until upstream is fixed
#
# The lib script prints "emitter-stress: PASS …" on success and exits 0.
# Anything else fails the validator.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

echo "== Phase 19 validator (emitter stress on real jak1 CGOs, qemu-aarch64) =="

LIB="$(pwd)/.autoport/lib/emitter_stress.sh"
if [ ! -x "$LIB" ]; then
    echo "FAIL: $LIB missing or not executable"
    exit 1
fi

bash "$LIB"
RC=$?

if [ "$RC" -ne 0 ]; then
    echo "== Phase 19 validator FAILED (rc=$RC) =="
    exit "$RC"
fi

echo
echo "== Phase 19 validator PASSED =="
exit 0
