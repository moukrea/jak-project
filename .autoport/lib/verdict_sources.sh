#!/usr/bin/env bash
# lib/verdict_sources.sh — LES SOURCES QUI PRODUISENT LE VERDICT D'UN ITEM, ET RIEN D'AUTRE.
#
# POURQUOI (harness-verdict-integrity, 2026-09-12). `validators/generic.sh` refusait une preuve
# dont une source de `game/ common/ android/ goal_src/` etait plus RECENTE qu'elle, et ne
# regardait PAS `.autoport/`. Or le verdict d'un item de HARNAIS vit dans `lib/census/<id>.sh`
# et dans les scripts qu'il appelle : ils pouvaient etre edites APRES la course sans que la
# porte s'en apercoive. Le precedent `builder-checkpoint-steals-work` avait mis sa somme dans
# `game/system/checkpoint_census.cpp` exactement pour ca — un detour qu'aucun item de harnais
# n'a le droit de prendre (son perimetre interdit `game/`).
#
# UN SEUL NOMMEUR (NOMMAGE/un-seul-endroit). L'ECRIVAIN (`lib/proof_run.sh`, qui publie
# `verdict_sources_sha=` dans la preuve) et le LECTEUR (`validators/generic.sh`, qui RECALCULE
# l'empreinte a la lecture) appellent ce fichier-ci. Deux listes ecrites a deux endroits
# divergent en silence ; il n'y en a qu'une.
#
# LA LISTE EST DERIVEE DU CONTENU, PAS ECRITE A LA MAIN. On part du socle (le juge, le
# producteur, ce fichier, le recensement de l'item) et on suit les chemins `.autoport/` que ces
# fichiers CITENT, jusqu'au point fixe. Une liste ecrite a la main oublie ; celle-ci ne peut pas
# rater un script que le verdict appelle, puisqu'il faut bien le nommer pour l'appeler.
# Ce fichier est dans sa propre liste : un nommeur qu'on peut editer sans etre vu ne garde rien.
#
# Usage : lib/verdict_sources.sh <item-id> [kv|list|sha|count|newer <fichier>]
#   kv (defaut) : verdict_sources_count= verdict_sources_sha= verdict_sources_list=
#   newer F     : ecrit sur stdout les sources PLUS RECENTES que F (vide = preuve a jour)
set -uo pipefail

ID="${1:-}"; WHAT="${2:-kv}"; REF="${3:-}"
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 1
cd "$ROOT" || exit 1
AP=.autoport

# Le socle. `orchestrator.py` n'y est PAS : il lance la porte, il ne calcule aucun verdict, et il
# bouge tous les jours — l'epingler ferait rougir des preuves que personne n'a touchees.
SOCLE="$AP/validators/generic.sh $AP/lib/proof_run.sh $AP/lib/verdict_sources.sh"
[ -n "$ID" ] && [ -f "$AP/lib/census/$ID.sh" ] && SOCLE="$SOCLE $AP/lib/census/$ID.sh"

# Point fixe : tant qu'un fichier retenu cite un chemin `.autoport/` qui existe, on l'ajoute.
LISTE=""
FRONT="$SOCLE"
while [ -n "$FRONT" ]; do
  SUIV=""
  for f in $FRONT; do
    case " $LISTE " in *" $f "*) continue ;; esac
    [ -f "$f" ] || continue
    LISTE="$LISTE $f"
    for rel in $(grep -oE '(lib|validators)/[A-Za-z0-9_./-]+\.(sh|py)' "$f" 2>/dev/null | sort -u); do
      [ -f "$AP/$rel" ] || continue
      case " $LISTE $SUIV " in *" $AP/$rel "*) continue ;; esac
      SUIV="$SUIV $AP/$rel"
    done
  done
  FRONT="$SUIV"
done
# shellcheck disable=SC2086
LISTE=$(printf '%s\n' $LISTE | sort -u)

case "$WHAT" in
  list)  printf '%s\n' "$LISTE" ;;
  count) printf '%s\n' "$LISTE" | grep -c . ;;
  sha)   printf '%s\n' "$LISTE" | xargs -r sha256sum | sha256sum | cut -c1-16 ;;
  newer)
    [ -n "$REF" ] || { echo "verdict_sources.sh newer <fichier>" >&2; exit 2; }
    for f in $LISTE; do [ "$f" -nt "$REF" ] && printf '%s\n' "$f"; done; : ;;
  kv)
    printf 'verdict_sources_count=%s\n' "$(printf '%s\n' "$LISTE" | grep -c .)"
    printf 'verdict_sources_sha=%s\n'   "$(printf '%s\n' "$LISTE" | xargs -r sha256sum | sha256sum | cut -c1-16)"
    # Une valeur de proof.txt ne peut porter AUCUN espace : elle serait jetee a la publication.
    printf 'verdict_sources_list=%s\n'  "$(printf '%s\n' "$LISTE" | paste -sd, -)" ;;
  *) echo "usage: verdict_sources.sh <item-id> [kv|list|sha|count|newer <fichier>]" >&2; exit 2 ;;
esac
