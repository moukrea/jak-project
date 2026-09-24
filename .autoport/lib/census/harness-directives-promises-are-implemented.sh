#!/usr/bin/env bash
# census/harness-directives-promises-are-implemented.sh — chaque promesse machine du contrat
# (« la porte de fermeture recalcule ... et refuse ... ») est tenue par du code, sondee.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`). Il n'ecrit aucun champ
# de `proof.txt` lui-meme. Tout le travail vit dans `lib/directives_promises_selftest.py`. Ce fichier
# garantit la POLARITE : sans la cle de la porte, une valeur NON NULLE.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "directives_unkept_promises=9001"
  exit 0
}
cd "$ROOT" || { echo "directives_unkept_promises=9001"; exit 0; }

SELFTEST_PY=".autoport/lib/directives_promises_selftest.py"
OUT=$(timeout 300 python3 "$SELFTEST_PY" 2>/dev/null)
RC=$?
printf '%s\n' "$OUT"
if [ "$(printf '%s\n' "$OUT" | grep -cE '^directives_unkept_promises=[0-9]+$')" -eq 0 ]; then
  echo "directives_selftest_rc=$RC"
  echo "directives_unkept_promises=9001"
fi
exit 0
