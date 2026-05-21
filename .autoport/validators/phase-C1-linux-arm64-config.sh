#!/usr/bin/env bash
# Placeholder validator for phase C1-linux-arm64-config.
#
# The supervisor (see .autoport/SUPERVISOR_PROMPT.md) is expected to
# replace this with a real validator that runs the reality check
# toolkit for this phase's bucket. Until that's done, this script
# halts the orchestrator with a clear "supervisor must author"
# message so the stuck-detection fires immediately rather than
# passing a fictitious validator.

set -uo pipefail
echo "FAIL: phase C1-linux-arm64-config validator is a placeholder."
echo "      The supervisor (.autoport/SUPERVISOR_PROMPT.md) must"
echo "      author the real .autoport/validators/phase-C1-linux-arm64-config.sh"
echo "      and .autoport/prompts/phase-C1-linux-arm64-config.md before this phase"
echo "      can run. Halting."
exit 1
