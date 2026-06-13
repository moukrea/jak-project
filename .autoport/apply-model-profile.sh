#!/usr/bin/env bash
# apply-model-profile.sh — regenerate .claude/agents/*.md effort frontmatter from
# the ACTIVE profile in .autoport/model-profiles.json. orchestrator.py and
# supervisor.sh read the JSON live; only the agent frontmatter can't, so this
# script syncs it. Run after flipping "active", then commit + relaunch.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
JSON=.autoport/model-profiles.json
AGENTS_DIR=.claude/agents

ACTIVE=$(jq -r '.active' "$JSON")
echo "active profile: $ACTIVE"

for agent in autoport-researcher autoport-implementer autoport-tester; do
    eff=$(jq -r ".profiles[\"$ACTIVE\"].worker_efforts[\"$agent\"] // empty" "$JSON")
    [ -n "$eff" ] || { echo "  skip $agent (no effort in profile)"; continue; }
    f="$AGENTS_DIR/$agent.md"
    [ -f "$f" ] || { echo "  WARN: $f missing"; continue; }
    # Replace the 'effort:' line inside the YAML frontmatter (first occurrence).
    if grep -qE '^effort:' "$f"; then
        sed -i "0,/^effort:.*/s//effort: $eff/" "$f"
        echo "  $agent -> effort: $eff"
    else
        echo "  WARN: no effort: line in $f (frontmatter manual)"
    fi
done
echo "done. Remember: git add .claude/agents + commit, then relaunch the orchestrator."
