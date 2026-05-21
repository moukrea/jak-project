#!/usr/bin/env bash
# Placeholder validator for phase F1-gameplay-geyser-rock.
#
# The supervisor (see .autoport/SUPERVISOR_PROMPT.md) is expected to
# replace this with a real validator that runs the reality check
# toolkit for this phase's bucket. Until that's done, this script
# halts the orchestrator with a clear "supervisor must author"
# message so the stuck-detection fires immediately rather than
# passing a fictitious validator.

set -uo pipefail
echo "FAIL: phase F1-gameplay-geyser-rock validator is a placeholder."
echo "      The supervisor (.autoport/SUPERVISOR_PROMPT.md) must"
echo "      author the real .autoport/validators/phase-F1-gameplay-geyser-rock.sh"
echo "      and .autoport/prompts/phase-F1-gameplay-geyser-rock.md before this phase"
echo "      can run. Halting."
exit 1
