#!/usr/bin/env bash
# Phase A4 — per-cluster arm64-vs-x86 differential harness with runtime-
# link simulation. Thin shell wrapper around build_a4_diff.py.
#
# Honors OUT_OVERRIDE_JSON env var: if set, writes the coverage JSON there
# instead of REPORTS/A4-coverage.json and skips markdown regeneration.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

if [ ! -x build/goalc/goalc ]; then
    echo "FAIL: build/goalc/goalc missing (x86 backend); rebuild with default cmake" >&2
    exit 1
fi
if [ ! -x build-arm64/goalc/goalc ]; then
    echo "FAIL: build-arm64/goalc/goalc missing (arm64 backend); rebuild with -DGOALC_BACKEND=arm64" >&2
    exit 1
fi

exec python3 .autoport/lib/build_a4_diff.py "$@"
