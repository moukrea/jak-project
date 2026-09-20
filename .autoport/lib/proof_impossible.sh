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
# NOMMAGE/ecrivain-derive — L'ECRIVAIN NE FABRIQUE PLUS SON NOM (harness-impossible-single-namer,
# 12/09). Il le concatenait tout seul a partir du suffixe de bras pendant que
# `lib/impossible.py` le derivait de son cote : deux endroits qui fabriquent un nom finissent
# toujours par en fabriquer deux differents, et c'est exactement la divergence qui avait rendu
# l'attente du bras d'ablation illisible sous une porte verte. Le nom vient desormais de
# l'AUTORITE, et d'elle seule. Si elle ne repond pas, on N'ECRIT RIEN et on sort en 2 : un etat
# pose sous un nom que personne ne lira serait un silence de plus, deguise en fichier.
#
# Usage :
#   proof_impossible.sh <dir> <id> <suffixe> <raison> <detail> <attendu_s> <borne_s> <pourquoi>
# Ecrit  : <dir>/<nom que `lib/impossible.py name impossible <suffixe>` derive>
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
  # PID *ET* INSTANT DE DEMARRAGE (harness-judge-binary-race-with-builder, 20/09) : `kill -0`
  # seul rend VRAI sur le numero d'un processus mort et RECYCLE par le systeme. Le 20/09 un
  # marqueur d'AOUT a fait attendre le constructeur 25 min, puis construire sous une course.
  bash "$ROOT/.autoport/lib/pidguard.sh" holder "$LOCK" >/dev/null 2>&1 && LALIVE=1
  LAGE=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || date +%s) ))
fi

one(){ printf '%s' "${1:--}" | tr '\n' ' ' | cut -c1-300; }

# L'AUTORITE EST A COTE DE CE SCRIPT, pas dans le depot courant : ce script est appele avec un
# `cwd` quelconque — un banc jetable, un `tmp_path` de test — et un `git rev-parse` y designerait
# un arbre qui ne porte pas le harnais.
AP=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)
NAME=$(python3 "$AP/lib/impossible.py" name impossible "$SUF" 2>/dev/null)
case "$NAME" in
  ""|*/*|*[!A-Za-z0-9._-]*)
    echo "proof_impossible: nom non derivable par $AP/lib/impossible.py pour le bras '${SUF:-livre}' (rendu : '${NAME:--}') : rien ecrit" >&2
    exit 2 ;;
esac

OUT="$D/$NAME"
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
