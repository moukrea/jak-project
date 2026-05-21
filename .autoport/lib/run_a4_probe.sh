#!/usr/bin/env bash
# Phase A4 — reproducibility wrapper for the kernel-symbol probe.
#
# The validator (.autoport/validators/phase-A4-linker-fixups.sh) reads
# .autoport/reports/A4-kernel-probe.txt, calls this script, and asserts
# the outputs match. Keep the script's stdout byte-identical to what was
# captured into the report file — no extra log lines.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
exec test/arm64/a4_kernel_probe.sh
