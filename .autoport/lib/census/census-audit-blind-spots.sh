#!/usr/bin/env bash
# census/census-audit-blind-spots.sh — LE RECENSEMENT DES ANGLES MORTS DE L'AUDIT, pour l'item
# `census-audit-blind-spots`.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course, sa
# sortie `cle=valeur` rejoignant celle du moteur dans le MEME journal. Il n'ecrit aucun champ de
# `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# TOUT LE TRAVAIL VIT DANS `lib/census/blind_spots.py` : quatre detecteurs qui lisent des
# structures (parentheses equilibrees, chaines `if/else if`, directives de preprocesseur) que le
# shell ne sait pas lire sans se tromper — c'est justement la faute que l'un d'eux corrige. Ce
# fichier-ci ne fait que le lancer et garantir la POLARITE : si le python ne rend rien, ou rend
# une sortie sans la cle de la porte, on publie une valeur NON NULLE qui FERME la porte. Jamais un
# zero par silence, jamais une cle fabriquee a la main.
#
# Le chemin `lib/census/blind_spots.py` est CITE ici, dans du CODE : `lib/verdict_sources.sh` le
# suit, l'epingle au verdict de cet item, et `validators/generic.sh` refuse une preuve plus vieille
# que lui. Un detecteur editable sans etre vu ne garde rien.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "blind_audit_ran=0"
  echo "census_blind_spot_defects=9001"
  exit 1
}
cd "$ROOT" || exit 1

AUDIT=".autoport/lib/census/blind_spots.py"
if [ ! -f "$AUDIT" ]; then
  echo "blind_audit_ran=0"
  echo "blind_reason=detecteur-absent:$AUDIT"
  echo "census_blind_spot_defects=9002"
  exit 0
fi

OUT=$(python3 "$AUDIT" 2>&1)
RC=$?
# La sortie du python d'abord : meme quand il accuse, ce qu'il a MESURE doit etre publie. Seules
# les lignes `cle=valeur` sans espace survivent au moissonneur ; on ne filtre rien de plus ici.
printf '%s\n' "$OUT"
if [ "$RC" -ne 0 ] || ! printf '%s\n' "$OUT" | grep -qE '^census_blind_spot_defects=[0-9]+$'; then
  echo "blind_runner_rc=$RC"
  echo "census_blind_spot_defects=9003"
fi
exit 0
