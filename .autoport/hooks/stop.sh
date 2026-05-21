#!/usr/bin/env bash
# stop.sh — runs after every Claude turn. Refuses to let Claude stop
# until the current phase's validator passes.
# Exit 0 = allow stop. Exit 2 = block stop, feed message back to Claude.

set -euo pipefail

STATE="$CLAUDE_PROJECT_DIR/.autoport/state.json"
PLAN="$CLAUDE_PROJECT_DIR/.autoport/milestones.yaml"

# Scope guard: this hook is meant for orchestrator-spawned Claude sessions
# only (orchestrator.py sets AUTOPORT_PHASE_ID before exec'ing claude). For
# regular interactive sessions in the same repo (user conversations, ad-hoc
# debugging, etc.) we exit cleanly so the user isn't held hostage by a
# phase validator they aren't trying to make pass.
if [ -z "${AUTOPORT_PHASE_ID:-}" ]; then
    exit 0
fi

# Read hook stdin (JSON from Claude Code) — we don't actually need it, but
# consume it so the pipe doesn't break.
INPUT=$(cat || true)

# stop_hook_active prevents infinite loops where the hook itself triggers
# another stop. If the same hook is already running, allow the stop.
ALREADY=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
if [ "$ALREADY" = "true" ]; then
    exit 0
fi

# Stale-session guard: each orchestrator-spawned session is supposed to make
# ITS OWN phase pass (orchestrator.py sets AUTOPORT_PHASE_ID before exec'ing
# claude). If state.json's `completed` list already contains this session's
# AUTOPORT_PHASE_ID, the orchestrator has already accepted this phase as
# done and possibly advanced state.json past it (spawning a new session for
# the next phase). Holding the now-stale session hostage on the NEW phase's
# validator is wrong: that's a different session's responsibility. Allow
# stop so the stale session can exit cleanly.
ALREADY_DONE=$(jq -r --arg id "$AUTOPORT_PHASE_ID" \
    '(.completed // []) | index($id) != null' "$STATE" 2>/dev/null || echo "false")
if [ "$ALREADY_DONE" = "true" ]; then
    exit 0
fi

IDX=$(jq -r '.current_phase_idx // 0' "$STATE" 2>/dev/null || echo 0)
PHASE_ID=$(yq -r ".phases[$IDX].id" "$PLAN" 2>/dev/null || echo "")
VALIDATOR=$(yq -r ".phases[$IDX].validator" "$PLAN" 2>/dev/null || echo "")

if [ -z "$PHASE_ID" ] || [ -z "$VALIDATOR" ]; then
    exit 0
fi

VPATH="$CLAUDE_PROJECT_DIR/.autoport/$VALIDATOR"
if [ ! -x "$VPATH" ]; then
    exit 0
fi

# Run validator
OUT=$(bash "$VPATH" 2>&1) && {
    echo "Phase $PHASE_ID validator PASSED. Stop allowed."
    exit 0
}

# Validator failed — block stop with feedback
cat <<EOF >&2
The phase $PHASE_ID validator is still failing. You must keep working.

Validator command:
  bash .autoport/$VALIDATOR

Last 80 lines of validator output:
$(echo "$OUT" | tail -n 80)

Diagnose the failure precisely (don't guess) and fix it. Do not stop again
until \`bash .autoport/$VALIDATOR\` exits with status 0.
EOF
exit 2
