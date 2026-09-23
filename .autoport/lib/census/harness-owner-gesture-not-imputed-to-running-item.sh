#!/usr/bin/env bash
# census/harness-owner-gesture-not-imputed-to-running-item.sh — un geste de l'owner pendant un essai
# (ticket Linear adopte dans le backlog, JAK-265 le 23/09) n'est plus impute au chantier qui tourne,
# et un ticket adopte arrive `code_scope: a-cadrer`, hors de la file tant qu'il n'est pas cadre.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`). Il n'ecrit aucun champ
# de `proof.txt` lui-meme. Tout le travail vit dans `lib/census/owner_gesture.py` (banc a semis sur
# le VRAI `lib/suite_gate.py`, bras d'avant ancre par marqueur, cas reel du 23/09 rejoue sur ses
# commits, adoption et auteur par les VRAIS points d'entree). Ce fichier garantit la POLARITE : sans
# la cle de la porte, une valeur NON NULLE.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "owner_gesture_misimputed=9001"
  exit 1
}
cd "$ROOT" || exit 1

CENSUS_PY=".autoport/lib/census/owner_gesture.py"
if [ ! -f "$CENSUS_PY" ]; then
  echo "owner_gesture_reason=recensement-absent:$CENSUS_PY"
  echo "owner_gesture_misimputed=9002"
  exit 0
fi

OUT=$(timeout 900 python3 "$CENSUS_PY" 2>/dev/null)
RC=$?
printf '%s\n' "$OUT"
if [ "$RC" -ne 0 ] || [ "$(printf '%s\n' "$OUT" | grep -cE '^owner_gesture_misimputed=[0-9]+$')" -eq 0 ]; then
  echo "owner_gesture_runner_rc=$RC"
  echo "owner_gesture_misimputed=9003"
fi
exit 0
