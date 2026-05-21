#!/usr/bin/env bash
# Phase A3 — per-cluster arm64-vs-x86 differential harness driver.
#
# This is a thin shell wrapper around build_a3_diff.py. The script must
# be executable and reproduce the same JSON when re-run (the validator
# spot-checks this with `OUT_OVERRIDE_JSON=<tmp>` and diffs against the
# canonical .autoport/reports/A3-coverage.json).
#
# Honors OUT_OVERRIDE_JSON env var: if set, writes the coverage JSON
# there instead of REPORTS/A3-coverage.json and skips the markdown
# regeneration (the validator does not re-check the markdown on spot
# runs).

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

exec python3 .autoport/lib/build_a3_diff.py "$@"
