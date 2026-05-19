#!/usr/bin/env bash
# session-start.sh — inject context about the current phase into Claude.
# Stdout from this hook is added directly to Claude's context window.

set -euo pipefail

STATE="$CLAUDE_PROJECT_DIR/.autoport/state.json"
PLAN="$CLAUDE_PROJECT_DIR/.autoport/milestones.yaml"

# Scope guard: only inject the phase-context preamble into orchestrator-
# spawned sessions (orchestrator.py sets AUTOPORT_PHASE_ID). Interactive
# user sessions shouldn't be told "you are running headless with no human
# in the loop" — that's misleading and confuses both Claude and the user.
if [ -z "${AUTOPORT_PHASE_ID:-}" ]; then
    exit 0
fi

if [ ! -f "$STATE" ] || [ ! -f "$PLAN" ]; then
    exit 0
fi

IDX=$(jq -r '.current_phase_idx // 0' "$STATE")
PHASE_ID=$(yq -r ".phases[$IDX].id" "$PLAN")
PHASE_NAME=$(yq -r ".phases[$IDX].name" "$PLAN")
VALIDATOR=$(yq -r ".phases[$IDX].validator" "$PLAN")

cat <<EOF
## Autoport: current phase

You are working on phase **$PHASE_ID — $PHASE_NAME** of the OpenGOAL → Android port.

**Validator (the ground truth):**
\`\`\`
bash .autoport/$VALIDATOR
\`\`\`

Rules:
1. Work ONLY on what this phase requires. Do not touch files outside its scope.
2. Run the validator yourself when you think you're done. The Stop hook will
   also run it and refuse to let you stop if it fails.
3. Use 'ultrathink' planning for design decisions — you are Opus 4.7 at max effort.
4. The existing x86 backend lives under \`goalc/emitter/\`. Mirror its
   structure for AArch64, do not rewrite the language.
5. Useful reference paths:
   - x86 emitter: goalc/emitter/IGen.h, goalc/emitter/IGen.cpp
   - Reg allocator: goalc/regalloc/
   - GOAL kernel asm trampoline: game/kernel/asm_funcs.asm
   - GOAL kernel source: goal_src/jak1/kernel/gkernel.gc, gstate.gc
   - Build system: CMakeLists.txt at repo root + per-dir CMakeLists
6. Commit messages must start with \`[autoport/$PHASE_ID]\`.

You are running in headless mode with no human in the loop. Be thorough, but
do not declare success until the validator exits 0.
EOF
