#!/usr/bin/env bash
# census/harness-tests-never-write-real-registries.sh — les tests n'ecrivent plus dans le vrai registre des
# commentaires Linear, et aucun commentaire ne part sans son chantier.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`). Il n'ecrit aucun champ
# de `proof.txt` lui-meme. Tout le travail vit dans `lib/census/registry_pollution.py`. Ce fichier
# garantit la POLARITE : sans la cle de la porte, une valeur NON NULLE.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "registry_pollution=9001"
  exit 1
}
cd "$ROOT" || exit 1

CENSUS_PY=".autoport/lib/census/registry_pollution.py"
if [ ! -f "$CENSUS_PY" ]; then
  echo "registry_pollution_reason=recensement-absent:$CENSUS_PY"
  echo "registry_pollution=9002"
  exit 0
fi

OUT=$(timeout 700 python3 "$CENSUS_PY" 2>/dev/null)
RC=$?
printf '%s\n' "$OUT"
if [ "$RC" -ne 0 ] || [ "$(printf '%s\n' "$OUT" | grep -cE '^registry_pollution=[0-9]+$')" -eq 0 ]; then
  echo "registry_pollution_runner_rc=$RC"
  echo "registry_pollution=9003"
fi
exit 0
