#!/usr/bin/env bash
# lib/run_commits.sh — LES COMMITS SURVENUS PENDANT UNE COURSE, ET CEUX QUI ONT TOUCHE LE JUGE.
#
# POURQUOI CE FICHIER EXISTE (harness-proof-file-has-no-writer-lock, 2026-09-12). Rien
# n'empechait un commit exterieur pendant une course, et rien ne le DISAIT. Mesure du 12/09 : le
# superviseur a commite a 16:12:59 pendant une course ; l'empreinte des sources de verdict a
# bouge entre la mesure et son jugement, et l'essai a ete refuse pour une raison qui ne decrivait
# aucun defaut de son travail. Le meme defaut s'est reproduit dans l'heure.
#
# CE QU'IL FAIT, ET CE QU'IL N'INTERDIT PAS. Il COMPTE, il NOMME ; il ne bloque rien. Le
# superviseur doit pouvoir commiter pendant qu'une course tourne — le contrat de l'item le dit en
# toutes lettres. Ce qui manquait n'est pas une interdiction, c'est un TEMOIN : un refus qui
# nomme la vraie cause au lieu d'accuser le travail de l'essai.
#
# UN SEUL NOMMEUR, ENCORE. La liste des sources du verdict ne se recopie pas ici : elle vient de
# `lib/verdict_sources.sh`, comme pour l'ecrivain (`lib/proof_run.sh`) et pour le juge
# (`validators/generic.sh`). Deux listes ecrites a deux endroits divergent en silence.
#
# Usage : lib/run_commits.sh <item-id> <sha-de-HEAD-au-depart-de-la-course> [kv|count|list]
#   kv (defaut) : proof_commits_* — aucune valeur ne porte d'espace (proof.txt les jette)
#   count       : le nombre de commits depuis le depart, -1 si on ne peut pas le savoir
#   list        : un sha court par ligne, du plus ancien au plus recent
#
# -1 = INCONNU, JAMAIS 0. Un depart non enregistre, un sha qui n'existe plus (rebase), un dossier
# qui n'est pas un depot : tout cela rend -1. Un zero voudrait dire « rien n'a bouge », et c'est
# exactement le mensonge qu'on vient de corriger ailleurs.
set -uo pipefail
export LC_ALL=C

ID="${1:-}"; HEAD_DEPART="${2:-}"; WHAT="${3:-kv}"
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "run_commits: pas dans un depot git" >&2; exit 2; }
cd "$ROOT" || exit 2

N=-1; LISTE="-"; NV=-1; LV="-"

valide=0
case "$HEAD_DEPART" in
  ""|"-") ;;
  *[!0-9a-f]*) ;;
  *) git rev-parse --verify --quiet "$HEAD_DEPART^{commit}" >/dev/null 2>&1 && valide=1 ;;
esac

if [ "$valide" = 1 ]; then
  # Du plus ANCIEN au plus recent : on lit une chronologie, pas une pile.
  COMMITS=$(git rev-list --reverse "$HEAD_DEPART..HEAD" 2>/dev/null)
  N=$(printf '%s\n' "$COMMITS" | grep -c .)
  if [ "$N" -gt 0 ]; then
    LISTE=$(printf '%s\n' "$COMMITS" | cut -c1-10 | paste -sd, -)
    # LES SOURCES DU VERDICT DE CET ITEM, demandees a leur nommeur. Un commit de fusion rend ses
    # chemins par `-m --first-parent` ; sans ca il ne rend RIEN et se lirait « n'a rien touche ».
    SRC=$(mktemp) || SRC=""
    if [ -n "$SRC" ]; then
      bash "$ROOT/.autoport/lib/verdict_sources.sh" "$ID" list 2>/dev/null > "$SRC"
      NV=0; LV=""
      for c in $COMMITS; do
        touches=$(git show --pretty=format: --name-only -m --first-parent "$c" 2>/dev/null \
                  | grep -v '^$' | sort -u | grep -Fx -f "$SRC" 2>/dev/null | head -3 | paste -sd+ -)
        [ -n "$touches" ] || continue
        NV=$((NV+1))
        LV="${LV:+$LV,}$(printf '%s' "$c" | cut -c1-10):$touches"
      done
      [ -n "$LV" ] || LV="-"
      rm -f "$SRC"
    fi
  else
    NV=0
  fi
fi

# AUCUN ESPACE DANS UNE VALEUR : `proof.txt` jette toute ligne `cle=valeur` qui en porte un, et
# la ligne jetee est publiee pour personne.
sans_espace(){ printf '%s' "${1:--}" | tr -s '[:space:]' '_'; }

case "$WHAT" in
  count) printf '%s\n' "$N" ;;
  list)  [ "$LISTE" = "-" ] || printf '%s\n' "$LISTE" | tr ',' '\n' ;;
  kv)
    printf 'proof_commits_head_at_start=%s\n'  "$(sans_espace "${HEAD_DEPART:--}")"
    printf 'proof_commits_start_known=%s\n'    "$valide"
    printf 'proof_commits_during_run=%s\n'     "$N"
    printf 'proof_commits_list=%s\n'           "$(sans_espace "$LISTE")"
    printf 'proof_commits_verdict_sources=%s\n' "$NV"
    printf 'proof_commits_verdict_list=%s\n'   "$(sans_espace "$LV")" ;;
  *) echo "usage: run_commits.sh <item-id> <sha-depart> [kv|count|list]" >&2; exit 2 ;;
esac
