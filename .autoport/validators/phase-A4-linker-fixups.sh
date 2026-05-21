#!/usr/bin/env bash
# Placeholder validator for phase A4-linker-fixups.
#
# The supervisor will author the real validator after A3 passes. Until
# then this exits 1 so the orchestrator's stuck-detection halts cleanly.

set -uo pipefail
echo "FAIL: phase A4-linker-fixups validator is a placeholder."
echo "      The supervisor authors A4 after A3 passes."
exit 1
