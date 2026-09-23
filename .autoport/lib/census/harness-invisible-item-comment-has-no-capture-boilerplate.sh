#!/usr/bin/env bash
# census/harness-invisible-item-comment-has-no-capture-boilerplate.sh — un chantier hors champ ne
# parle ni de capture ni de build a tester (INVISIBLE-CAPTURE/, owner 23/09 sur JAK-240).
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`). Il n'ecrit aucun champ
# de `proof.txt` lui-meme. Tout le travail vit dans `lib/census/invisible_capture.py` (registre des
# commentaires avant/apres le correctif, contrat rendu aux items vivants, controles semes sur le VRAI
# `linear_sync.main`). Ce fichier garantit la POLARITE : sans la cle de la porte, une valeur NON NULLE.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "invisible_item_capture_mentions=9001"
  exit 1
}
cd "$ROOT" || exit 1

CENSUS_PY=".autoport/lib/census/invisible_capture.py"
if [ ! -f "$CENSUS_PY" ]; then
  echo "invisible_capture_reason=recensement-absent:$CENSUS_PY"
  echo "invisible_item_capture_mentions=9002"
  exit 0
fi

OUT=$(timeout 300 python3 "$CENSUS_PY" 2>/dev/null)
RC=$?
printf '%s\n' "$OUT"
if [ "$RC" -ne 0 ] || [ "$(printf '%s\n' "$OUT" | grep -cE '^invisible_item_capture_mentions=[0-9]+$')" -eq 0 ]; then
  echo "invisible_capture_runner_rc=$RC"
  echo "invisible_item_capture_mentions=9003"
fi
exit 0
