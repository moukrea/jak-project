#!/usr/bin/env bash
# lib/proof_impossible.sh — ECRIT L'ETAT NOMME « preuve impossible ».
#
# POURQUOI CE FICHIER EXISTE. `lib/proof_run.sh` sortait en 3 — binaire absent, appareil
# absent, verrou de deploiement tenu au-dela de la borne — en EFFACANT proof.txt et sans rien
# ecrire d'autre. Le 2026-09-12, le constructeur a tenu `.autoport/.deploy-in-progress`
# pendant 6 h 38 : pendant tout ce temps aucune preuve n'etait possible, et AUCUN compteur ne
# le disait. « Pas de preuve » et « preuve impossible » se lisaient pareil, c'est-a-dire pas
# du tout.
#
# CE QU'IL N'EST PAS. Il n'ecrit JAMAIS dans proof.txt : ni `sha`, ni `frames`, ni `crash`,
# ni la moindre cle que le validateur lit. Une preuve impossible ne devient pas une preuve
# parce qu'on l'a nommee. Il ecrit un fichier A COTE, que seul un recensement lit.
#
# Usage :
#   proof_impossible.sh <dir> <id> <suffixe> <raison> <detail> <attendu_s> <borne_s> <pourquoi>
# Ecrit  : <dir>/proof<suffixe>-impossible.txt
set -uo pipefail

D=${1:-}; ID=${2:-}; SUF=${3:-}; REASON=${4:-inconnue}; DETAIL=${5:-}
WAITED=${6:-0}; WAITMAX=${7:-0}; BUSY=${8:-}

[ -n "$D" ] || { echo "proof_impossible: dossier manquant" >&2; exit 2; }
mkdir -p "$D" 2>/dev/null || { echo "proof_impossible: $D non creable" >&2; exit 2; }

# LE VERROU, MESURE ICI et pas raconte : son pid, s'il repond encore, et son age. Un verrou
# dont le pid est mort ne vaut rien — le dire est la moitie du signalement.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo .)
LOCK="$ROOT/.autoport/.deploy-in-progress"
LPID="-"; LALIVE=0; LAGE=-1
if [ -f "$LOCK" ]; then
  LPID=$(sed -n 's/.*pid=\([0-9]\{1,\}\).*/\1/p' "$LOCK" | head -1); LPID=${LPID:--}
  [ "$LPID" != "-" ] && kill -0 "$LPID" 2>/dev/null && LALIVE=1
  LAGE=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || date +%s) ))
fi

one(){ printf '%s' "${1:--}" | tr '\n' ' ' | cut -c1-300; }

OUT="$D/proof$SUF-impossible.txt"
TMP="$OUT.tmp.$$"
{
  echo "proof_impossible=1"
  echo "proof_impossible_id=$(one "$ID")"
  echo "proof_impossible_reason=$(one "$REASON")"
  echo "proof_impossible_detail=$(one "$DETAIL")"
  echo "proof_impossible_wait_s=$((WAITED + 0))"
  echo "proof_impossible_wait_max_s=$((WAITMAX + 0))"
  echo "proof_impossible_busy_why=$(one "$BUSY")"
  echo "proof_impossible_lock_pid=$LPID"
  echo "proof_impossible_lock_alive=$LALIVE"
  echo "proof_impossible_lock_age_s=$LAGE"
  echo "proof_impossible_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "proof_impossible_exit=3"
} > "$TMP" && mv -f "$TMP" "$OUT"
printf '[proof_impossible %s] etat NOMME ecrit : %s (raison=%s attendu=%ss verrou=%s vivant=%s age=%ss)\n' \
  "$ID" "$OUT" "$REASON" "$((WAITED + 0))" "$LPID" "$LALIVE" "$LAGE" >&2
exit 0
