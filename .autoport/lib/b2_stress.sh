#!/usr/bin/env bash
# Phase B2 — qemu decode-stress driver (shell entry point).
#
# Thin wrapper around .autoport/lib/b2_stress.py. The validator invokes
# this via B2_OUT_JSON=<tmp> to verify reproducibility, so the python
# driver itself reads B2_OUT_JSON and writes there instead of the
# canonical report path.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

if ! command -v qemu-aarch64-static >/dev/null 2>&1; then
    echo "FAIL: qemu-aarch64-static not on PATH" >&2
    exit 1
fi
if ! command -v aarch64-linux-gnu-objdump >/dev/null 2>&1; then
    echo "FAIL: aarch64-linux-gnu-objdump not on PATH" >&2
    exit 1
fi

for cgo in KERNEL.CGO ENGINE.CGO GAME.CGO; do
    if [ ! -s "out/jak1-arm64/iso/$cgo" ]; then
        echo "FAIL: out/jak1-arm64/iso/$cgo missing (run B1 first)" >&2
        exit 1
    fi
done

exec python3 .autoport/lib/b2_stress.py "$@"
