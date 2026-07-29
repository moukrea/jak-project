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

# Model + effort for the supervisor come from the ACTIVE profile in
# .autoport/model-profiles.json (single source of truth — same one the
# orchestrator reads). Flip "active" there to switch the whole setup.
# 'ultrathink' in SUPERVISOR_PROMPT.md keeps reasoning deep regardless.
# NOTE: model names contain brackets — pass them quoted (glob chars).
PROFILE_JSON="$REPO_ROOT/.autoport/model-profiles.json"
if command -v jq >/dev/null 2>&1 && [ -f "$PROFILE_JSON" ]; then
    _ACTIVE=$(jq -r '.active' "$PROFILE_JSON")
    SUP_MODEL=$(jq -r ".profiles[\"$_ACTIVE\"].manager_model" "$PROFILE_JSON")
    SUP_EFFORT=$(jq -r ".profiles[\"$_ACTIVE\"].manager_effort" "$PROFILE_JSON")
    SUB_MODEL=$(jq -r ".profiles[\"$_ACTIVE\"].worker_model" "$PROFILE_JSON")
fi
# Fallback if the JSON/jq is unavailable.
SUP_MODEL="${SUP_MODEL:-claude-fable-5[1m]}"
SUP_EFFORT="${SUP_EFFORT:-xhigh}"
SUB_MODEL="${SUB_MODEL:-claude-fable-5[1m]}"
export CLAUDE_EFFORT="$SUP_EFFORT"
export CLAUDE_CODE_SUBAGENT_MODEL="$SUB_MODEL"
echo "[supervisor] profile=${_ACTIVE:-fallback} model=$SUP_MODEL effort=$SUP_EFFORT workers=$SUB_MODEL"

exec claude \
    --model "$SUP_MODEL" \
    --effort "$SUP_EFFORT" \
    --append-system-prompt "$(cat "$PROMPT_FILE")" \
    --dangerously-skip-permissions \
    "$@"
