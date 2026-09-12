#!/usr/bin/env bash
# lib/ablation_anchor.sh — L'ETAT D'AVANT, ANCRE SUR UNE REVISION, JAMAIS SUR UN COMPTE.
#
# POURQUOI CE FICHIER EXISTE (harness-verdict-integrity, 2026-09-12). Trois lecteurs du harnais
# cherchaient le bras d'ablation — le dernier etat du fichier SANS le correctif — dans les
# 60 DERNIERS commits du chemin :
#     lib/pin_props_selftest.sh, lib/census/harness-proof-props-pin.sh,
#     lib/census/harness-test-suite-is-not-a-signal.sh
# `orchestrator.py` porte deja 61 commits et en gagne tous les jours. Le jour ou l'introduction
# du marqueur sort de la fenetre, le temoin d'avant devient introuvable et la porte vire au
# ROUGE sans qu'aucun defaut existe. Une meche lente, deja allumee.
#
# CE QU'ON ANCRE DESORMAIS : la REVISION QUI A INTRODUIT le marqueur (`git log -S`, pioche sur
# le contenu, historique COMPLET du chemin), puis le dernier commit qui a touche ce chemin AVANT
# elle. C'est exactement ce que le balayage rendait, sans plafond : mesure du 2026-09-12, les
# CINQ couples (chemin, marqueur) du harnais rendent le MEME commit qu'avant.
#
# Usage : lib/ablation_anchor.sh <racine> <chemin-relatif> <marqueur> [kv|commit]
#   kv     (defaut) : anchor_commit= anchor_method= anchor_depth= anchor_legacy_window=
#   commit          : le sha seul, vide si aucun etat d'avant n'existe
#
# anchor_method :
#   introduction  la revision qui a introduit le marqueur a servi d'ancre (le cas normal)
#   balayage      la pioche n'a rien rendu : on a remonte le chemin, sans plafond
#   absent        le marqueur n'a jamais eu d'etat d'avant sur ce chemin (fichier ne avec lui)
# anchor_depth : la profondeur de l'introduction dans l'historique DU CHEMIN. C'est la grandeur
#   qui dit ou en est la meche : au-dela de anchor_legacy_window, l'ancien code etait aveugle.
set -uo pipefail

R="${1:-}"; P="${2:-}"; M="${3:-}"; OUT="${4:-kv}"
LEGACY_WINDOW=60

[ -n "$R" ] && [ -n "$P" ] && [ -n "$M" ] || {
  echo "usage: ablation_anchor.sh <racine> <chemin> <marqueur> [kv|commit]" >&2; exit 2; }

# JAMAIS DE TUBE ICI. `git show | grep -q` sous `set -o pipefail` est un piege INTERMITTENT :
# `grep -q` sort des la premiere occurrence, `git show` meurt alors en SIGPIPE (141), et
# `pipefail` fait echouer le tube ALORS QUE LE MARQUEUR EST LA. La course ne se perd que sur
# les gros fichiers (orchestrator.py, 100 Ko) — mesure du 12/09 : une parite sur cinq fausse
# une fois sur deux. Le blob passe donc par une variable, et `grep` lit un here-string.
porte_marqueur(){  # <commit> -> 0 si le blob de $P a ce commit contient le marqueur
  local blob
  blob=$(git -C "$R" show "$1:$P" 2>/dev/null) || return 1
  grep -qF -- "$M" <<<"$blob"
}

COMMIT=""; METHOD=absent; DEPTH=-1

# 1. LA PIOCHE : le plus VIEUX commit ou le nombre d'occurrences du marqueur a change, c'est
#    celui qui l'a introduit. Historique complet du chemin, aucun plafond.
INTRO=$(git -C "$R" log --format=%H -S"$M" -- "$P" 2>/dev/null | tail -1)
if [ -n "$INTRO" ]; then
  DEPTH=$(git -C "$R" log --format=%H -- "$P" 2>/dev/null | grep -n "^$INTRO\$" | head -1 | cut -d: -f1)
  DEPTH=${DEPTH:--1}
  # Le dernier commit qui a touche CE chemin avant l'introduction : le blob d'avant.
  CAND=$(git -C "$R" log --format=%H -n 1 "$INTRO^" -- "$P" 2>/dev/null)
  if [ -n "$CAND" ] && ! porte_marqueur "$CAND"; then COMMIT="$CAND"; METHOD=introduction; fi
fi

# 2. REPLI : la pioche peut etre muette (marqueur present des la creation, reecriture massive).
#    On remonte alors le chemin ENTIER — c'est le balayage d'avant, debarrasse de son plafond.
if [ -z "$COMMIT" ]; then
  for c in $(git -C "$R" log --format=%H -- "$P" 2>/dev/null); do
    if ! porte_marqueur "$c"; then COMMIT="$c"; METHOD=balayage; break; fi
  done
fi

if [ "$OUT" = commit ]; then printf '%s' "$COMMIT"; [ -n "$COMMIT" ] || exit 1; exit 0; fi
printf 'anchor_commit=%s\n' "${COMMIT:--}"
printf 'anchor_method=%s\n' "$METHOD"
printf 'anchor_depth=%s\n' "$DEPTH"
printf 'anchor_legacy_window=%s\n' "$LEGACY_WINDOW"
[ -n "$COMMIT" ]
