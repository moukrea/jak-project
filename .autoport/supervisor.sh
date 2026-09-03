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

if ! [ -f "$PROMPT_FILE" ]; then
    echo "ERROR: $PROMPT_FILE missing." >&2
    echo "       Run from repo root; the supervisor prompt should be" >&2
    echo "       at $PROMPT_FILE." >&2
    exit 1
fi

# Le JOURNAL de superviseur (buckets A-F, ere de mai) est mort depuis le 2026-06-18 et a ete
# archive le 2026-09-03. L'etat vit desormais dans `.autoport/backlog.yaml`, lisible par
# `./.autoport/autoport status`. On ne fabrique plus de fichier que personne ne lit.

cat <<EOF
================================================================
  Superviseur autoport — session Claude Code separee
================================================================
  Role     : traduire les messages de l'owner en items de backlog,
             poser ses validations, arbitrer, rendre compte.
             Le superviseur n'edite PAS le moteur et ne touche AUCUN appareil.
  Contrat  : $PROMPT_FILE
  Backlog  : .autoport/backlog.yaml   (./.autoport/autoport status)
  Plan     : .autoport/plans/2026-09-03-remise-d-equerre.md

  Pour demarrer :  ./.autoport/autoport status
  L'orchestrateur se lance seul par ./launch.sh et prend le premier item \`open\`.
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
SUP_MODEL="${SUP_MODEL:-claude-opus-4-8[1m]}"
SUP_EFFORT="${SUP_EFFORT:-xhigh}"
SUB_MODEL="${SUB_MODEL:-claude-opus-4-8[1m]}"
export CLAUDE_EFFORT="$SUP_EFFORT"
export CLAUDE_CODE_SUBAGENT_MODEL="$SUB_MODEL"
echo "[supervisor] profile=${_ACTIVE:-fallback} model=$SUP_MODEL effort=$SUP_EFFORT workers=$SUB_MODEL"

exec claude \
    --model "$SUP_MODEL" \
    --effort "$SUP_EFFORT" \
    --append-system-prompt "$(cat "$PROMPT_FILE")" \
    --dangerously-skip-permissions \
    "$@"
