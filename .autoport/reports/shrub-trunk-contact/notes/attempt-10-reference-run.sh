#!/usr/bin/env bash
set -euo pipefail
LOCK=/home/emeric/code/jak-project/.autoport/.deploy-in-progress
(set -o noclobber; printf '%s pid=%s\n' "$0" "$$" > "$LOCK")
trap 'rm -f "$LOCK"' EXIT
cd /home/emeric/code/jak-shrub-reference-602cd
export AUTOPORT_BACKEND=codex
bash .autoport/lib/proof_run.sh shrub-trunk-contact device --timeout 130
