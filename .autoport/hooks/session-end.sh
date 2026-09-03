#!/usr/bin/env bash
# session-end.sh — one line per worker session, and the phase claim given back.
#
# Il ecrivait TOUT state.json (38 Ko) a chaque fin de session : logs/session-end.log
# faisait 52 Mo et personne ne l'a jamais lu en entier. Un post-mortem se fait sur
# logs/<id>/attempt-NNN.jsonl, qui est complet et date. Ici, une ligne suffit.

set -euo pipefail
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LOG="$CLAUDE_PROJECT_DIR/.autoport/logs/session-end.log"

# Rend le jeton de phase pris au demarrage (cf. .autoport/phase_claim.sh). Le `release`
# ne retire QUE notre propre jeton : un worker qui meurt sans passer ici laisse un jeton
# perime, que le prochain `claim` detecte mort par (pid, heure de demarrage, nom du
# programme) et remplace. Aucun verrou ne peut donc rester coince sur un disparu.
if [ -n "${AUTOPORT_PHASE_ID:-}" ]; then
    bash "$CLAUDE_PROJECT_DIR/.autoport/phase_claim.sh" release "$AUTOPORT_PHASE_ID" || true
fi

HEAD=$(git -C "$CLAUDE_PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')
DIRTY=$(git -C "$CLAUDE_PROJECT_DIR" status --porcelain -uall 2>/dev/null | wc -l)

printf '%s item=%s head=%s dirty=%s\n' \
    "$TS" "${AUTOPORT_PHASE_ID:-none}" "$HEAD" "$DIRTY" >> "$LOG"

exit 0
