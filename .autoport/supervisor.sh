#!/usr/bin/env bash
# Launch the autoport supervisor — a fresh Claude Code session whose
# job is to watch the autoport orchestrator and call out its cheats.
#
# Run in its OWN terminal, separate from `./launch.sh`. The supervisor
# spawns the orchestrator itself when ready.
#
# Usage:
#   ./.autoport/supervisor.sh         # interactive
#   ./.autoport/supervisor.sh --quiet # less output from claude itself

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

PROMPT_FILE=".autoport/SUPERVISOR_PROMPT.md"
JOURNAL=".autoport/SUPERVISOR_JOURNAL.md"

if ! [ -f "$PROMPT_FILE" ]; then
    echo "ERROR: $PROMPT_FILE missing." >&2
    echo "       Run from repo root; the supervisor prompt should be" >&2
    echo "       at $PROMPT_FILE." >&2
    exit 1
fi

# Ensure the journal exists with a header — the supervisor appends to it.
if ! [ -f "$JOURNAL" ]; then
    cat > "$JOURNAL" <<EOF
# Autoport supervisor journal

Initialized $(date -u '+%Y-%m-%dT%H:%M:%SZ').

## Bucket status

A (emitter):       not-started
B (CGO regen):     not-started
C (linux-arm64):   not-started
D (android-port):  not-started
E (UX):            not-started
F (gameplay):      not-started

---

EOF
fi

cat <<EOF
================================================================
  Autoport SUPERVISOR — separate Claude Code session
================================================================
  Role:      watch the autoport orchestrator; halt on cheats
  Prompt:    $PROMPT_FILE
  Journal:   $JOURNAL
  Tools:     full Claude Code toolkit (Bash, Read, Edit, ScheduleWakeup, …)

  The supervisor does NOT spawn claude sessions for individual
  phases — that is the autoport orchestrator's job. The supervisor
  runs the orchestrator, watches it, and intervenes on cheats.

  Bootstrap (the supervisor does these on first message):
    1. Verify desktop oracle binary build-x86/game/gk exists.
    2. Capture oracle reference trace if missing.
    3. Audit source tree for cheats (asks user before any deletion).
    4. Reset state.json to last real artifact baseline.
    5. Rewrite milestones.yaml to bucket A-F structure.
    6. Spawn the orchestrator.
    7. Begin operating loop.

  Send 'begin' or similar to kick off.
================================================================
EOF

# Force Opus 4.7 + max effort for the supervisor itself. The 'ultrathink'
# keyword is reinforced inside SUPERVISOR_PROMPT.md so each reasoning step
# allocates maximum thinking budget — see the 'Reasoning depth' section.
# CLAUDE_EFFORT env is set too (belt-and-suspenders for older builds that
# pre-date the --effort CLI flag).
export CLAUDE_EFFORT=max

exec claude \
    --model claude-opus-4-7 \
    --effort max \
    --append-system-prompt "$(cat "$PROMPT_FILE")" \
    --dangerously-skip-permissions \
    "$@"
