#!/usr/bin/env bash
# Recensement de harness-directives-gate-reads-any-report-name : la porte DIRECTIVES lit le
# dossier du rapport, un refus de forme n'est pas compte, les refus passes sont recenses.
# Toute la logique est dans lib/directives_form.py ; ici, jamais un passage silencieux.
set -u
cd "$(dirname "$0")/../../.." || exit 2
OUT=$(timeout 300 python3 .autoport/lib/directives_form.py census 2>&1)
RC=$?
printf '%s\n' "$OUT" | grep -E '^[a-z0-9_]+=' | tr -d ' '
if ! printf '%s\n' "$OUT" | grep -qE '^directives_gate_misnamed_refusals=[0-9]+$'; then
  echo "directives_gate_census_rc=$RC"
  echo "directives_gate_misnamed_refusals=9001"
  printf '%s\n' "$OUT" | tail -5 >&2
fi
exit 0
