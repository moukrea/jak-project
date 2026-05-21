#!/usr/bin/env bash
# Placeholder validator for phase D4-android-apk-title.
#
# The supervisor (see .autoport/SUPERVISOR_PROMPT.md) is expected to
# replace this with a real validator that runs the reality check
# toolkit for this phase's bucket. Until that's done, this script
# halts the orchestrator with a clear "supervisor must author"
# message so the stuck-detection fires immediately rather than
# passing a fictitious validator.

set -uo pipefail
echo "FAIL: phase D4-android-apk-title validator is a placeholder."
echo "      The supervisor (.autoport/SUPERVISOR_PROMPT.md) must"
echo "      author the real .autoport/validators/phase-D4-android-apk-title.sh"
echo "      and .autoport/prompts/phase-D4-android-apk-title.md before this phase"
echo "      can run. Halting."
exit 1
