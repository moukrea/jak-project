#!/usr/bin/env bash
# session-end.sh — snapshot of state when a Claude Code session ends.
# Useful for post-mortem on stuck phases.

set -euo pipefail
TS=$(date -u +%Y%m%dT%H%M%SZ)
LOG="$CLAUDE_PROJECT_DIR/.autoport/logs/session-end.log"

# Rend le jeton de phase pris au demarrage (cf. .autoport/phase_claim.sh). Le `release` ne
# retire QUE notre propre jeton : un worker qui meurt sans passer ici laisse un jeton perime,
# que le prochain `claim` detecte mort par (pid, heure de demarrage, nom du programme) et
# remplace. Aucun verrou ne peut donc rester coince sur un processus disparu.
if [ -n "${AUTOPORT_PHASE_ID:-}" ]; then
    bash "$CLAUDE_PROJECT_DIR/.autoport/phase_claim.sh" release "$AUTOPORT_PHASE_ID" || true
fi

{
    echo "=== Session end $TS ==="
    echo "--- Recent commits ---"
    git -C "$CLAUDE_PROJECT_DIR" log --oneline -10 2>/dev/null || true
    echo "--- Working tree status ---"
    git -C "$CLAUDE_PROJECT_DIR" status -s 2>/dev/null || true
    echo "--- State ---"
    cat "$CLAUDE_PROJECT_DIR/.autoport/state.json" 2>/dev/null || true
    echo ""
} >> "$LOG"

exit 0
