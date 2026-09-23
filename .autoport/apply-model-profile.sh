#!/usr/bin/env bash
# apply-model-profile.sh — regenerate .claude/agents/*.md effort frontmatter from
# the ACTIVE profile in .autoport/model-profiles.json. DELEGATES to
# `autoport profile sync` (.autoport/lib/profile_cli.py) : one implementation,
# reachable from both the shell and `./.autoport/autoport profile sync`.
set -euo pipefail
exec python3 "$(git rev-parse --show-toplevel)/.autoport/autoport" profile sync
