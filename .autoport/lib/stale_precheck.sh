#!/usr/bin/env bash
# lib/stale_precheck.sh — LA MEME LECTURE QUE LE JUGE, AU DEMARRAGE DE LA COURSE.
#
# POURQUOI CE FICHIER EXISTE (harness-stale-proof-caught-before-the-run, 2026-09-12).
# `validators/generic.sh` refuse une preuve dont une source — moteur ou verdict — est PLUS
# RECENTE qu'elle. Le constat est juste ; c'est le MOMENT ou il tombe qui coute. Mesure sur les
# 791 verdicts archives de `logs/<id>/validator-*.txt` : 12 lignes de refus pour ce motif, sur
# 9 essais et 5 items, et l'essai 1 de `menu-back-label` a couru 43 minutes avant de mourir
# la-dessus. A chaque fois le travail etait fait : seule la preuve datait d'avant la derniere
# edition, et personne ne l'avait relancee.
#
# CE QU'IL FAIT. Il rejoue, AU DEMARRAGE de la course, les deux comparaisons que le juge fera a
# la fin, contre la preuve qui EXISTE a cet instant — celle que le juge aurait lue si l'essai
# s'etait termine maintenant. Il rend un code distinct, et il NOMME les fichiers.
#
# CE QU'IL NE FAIT PAS, ET C'EST DELIBERE :
#   * il ne DURCIT rien. Les deux predicats sont ceux de `validators/generic.sh`, au mot pres.
#     Une regle recopiee en plus strict fabriquerait un deuxieme juge, plus severe que celui
#     qui ferme les items, et ferait rougir des essais que personne n'a touches.
#   * il n'ARRETE pas la course. La course qui demarre est precisement le remede : la refuser
#     ferait payer a l'essai suivant le defaut de l'essai d'avant.
#   * il n'ecrit RIEN dans proof.txt. `lib/proof_run.sh` publie ses cles, comme pour l'attente.
#
# Usage : lib/stale_precheck.sh <item-id> [--arm <''|-off>] [--ref <fichier>] [--root <dir>]
# Sortie : des `cle=valeur` sur stdout, les explications sur stderr.
# Codes  : 0 = rien de perime ; 5 = PEREMPTION VUE AVANT LA COURSE ; 2 = usage.
#          5 n'est ni 2 (usage), ni 3 (echec de mesure de `lib/proof_run.sh`, `die3`), ni 4
#          (binaire non relie, `lib/build_x86.sh`) : le code dit LEQUEL des deux est arrive.
set -uo pipefail
export LC_ALL=C

CODE_PERIME=5
CODE_MESURE_IMPOSSIBLE=3   # celui de `die3` dans lib/proof_run.sh, dont le notre doit differer

ID=""; ARM=""; REF=""; ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --arm)  ARM="${2:-}"; shift 2 ;;
    --ref)  REF="${2:-}"; shift 2 ;;
    --root) ROOT="${2:-}"; shift 2 ;;
    -*) echo "stale_precheck: option inconnue '$1'" >&2; exit 2 ;;
    *)  [ -z "$ID" ] && { ID="$1"; shift; continue; }
        echo "stale_precheck: argument en trop '$1'" >&2; exit 2 ;;
  esac
done
[ -n "$ID" ] || { echo "usage: lib/stale_precheck.sh <item-id> [--arm ''|-off] [--ref F] [--root D]" >&2; exit 2; }
case "$ARM" in ''|-off) ;; *) echo "stale_precheck: bras inconnu '$ARM'" >&2; exit 2 ;; esac

[ -n "$ROOT" ] || ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "stale_precheck: pas dans un depot git" >&2; exit 2; }
cd "$ROOT" || exit 2
AP=.autoport

pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }

# LE NOM DE LA PREUVE SORT DE L'AUTORITE DE NOMMAGE, jamais d'un litteral pose ici : un nom
# fabrique a deux endroits diverge en silence, et ce script lirait alors un fichier que
# personne n'ecrit — donc « rien de perime », toujours.
if [ -z "$REF" ]; then
  PN=$(python3 "$AP/lib/impossible.py" name proof "$ARM" 2>/dev/null)
  [ -n "$PN" ] || { echo "stale_precheck: lib/impossible.py ne nomme pas la preuve du bras '${ARM:-livre}'" >&2; exit 2; }
  REF="$AP/reports/$ID/$PN"
fi

pub stale_precheck_ran 1
pub stale_precheck_item "$ID"
pub stale_precheck_arm "${ARM:-livre}"
pub stale_precheck_ref "$REF"

# LES SOURCES DU VERDICT. Le comparateur est celui du juge : `lib/verdict_sources.sh <id> newer`,
# c'est-a-dire `[ "$f" -nt "$REF" ]`, nanoseconde et strict (registre de fraicheur).
VS_LISTE=$(bash "$AP/lib/verdict_sources.sh" "$ID" list 2>/dev/null)
VS_N=$(printf '%s\n' "$VS_LISTE" | grep -c .)

# LE MOTEUR. Le predicat est celui de `validators/generic.sh` : memes dossiers, memes suffixes.
# Les dossiers absents sont retires AVANT l'appel — un `find` qui meurt sur un dossier manquant
# rendrait une population vide, et une population vide se lit « rien de perime ».
DIRS=""
for d in game common android goal_src; do [ -d "$d" ] && DIRS="$DIRS $d"; done
# shellcheck disable=SC2086
MOT_N=0
if [ -n "$DIRS" ]; then
  MOT_N=$(find $DIRS -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.gc' -o -name '*.vert' -o -name '*.frag' \) -print 2>/dev/null | grep -c .)
fi

pub stale_precheck_verdict_compared "$VS_N"
pub stale_precheck_engine_compared "$MOT_N"
pub stale_precheck_files_compared "$((VS_N + MOT_N))"
pub stale_precheck_dirs "$(printf '%s' "$DIRS" | tr ' ' ',' | sed 's/^,//')"

if [ ! -s "$REF" ]; then
  # AUCUNE PREUVE A PERIMER N'EST PAS UNE PREUVE FRAICHE : on le DIT, on ne le confond pas avec
  # un arbre propre. Le premier essai d'un item passe par ici, et il n'y a rien a y voir.
  pub stale_precheck_ref_present 0
  pub stale_precheck_verdict_newer -1
  pub stale_precheck_verdict_newer_list -
  pub stale_precheck_engine_newer -1
  pub stale_precheck_engine_newer_list -
  pub stale_precheck_stale_total -1
  pub stale_precheck_rc 0
  pub stale_precheck_code_stale "$CODE_PERIME"
  pub stale_precheck_code_measure_fail "$CODE_MESURE_IMPOSSIBLE"
  pub stale_precheck_codes_distinct 1
  echo "[stale_precheck $ID] aucune preuve a comparer sous $REF : rien a perimer." >&2
  exit 0
fi
pub stale_precheck_ref_present 1

VS_NEUFS=$(bash "$AP/lib/verdict_sources.sh" "$ID" newer "$REF" 2>/dev/null | grep -c .)
VS_NEUFS_L=$(bash "$AP/lib/verdict_sources.sh" "$ID" newer "$REF" 2>/dev/null | paste -sd, -)
# shellcheck disable=SC2086
MOT_NEUFS_L=""
MOT_NEUFS=0
if [ -n "$DIRS" ]; then
  MOT_NEUFS_L=$(find $DIRS -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.gc' -o -name '*.vert' -o -name '*.frag' \) -newer "$REF" -print 2>/dev/null | sort)
  MOT_NEUFS=$(printf '%s\n' "$MOT_NEUFS_L" | grep -c .)
  MOT_NEUFS_L=$(printf '%s\n' "$MOT_NEUFS_L" | head -10 | paste -sd, -)
fi

TOTAL=$((VS_NEUFS + MOT_NEUFS))
pub stale_precheck_verdict_newer "$VS_NEUFS"
pub stale_precheck_verdict_newer_list "${VS_NEUFS_L:--}"
pub stale_precheck_engine_newer "$MOT_NEUFS"
pub stale_precheck_engine_newer_list "${MOT_NEUFS_L:--}"
pub stale_precheck_stale_total "$TOTAL"
pub stale_precheck_code_stale "$CODE_PERIME"
pub stale_precheck_code_measure_fail "$CODE_MESURE_IMPOSSIBLE"
pub stale_precheck_codes_distinct "$([ "$CODE_PERIME" != "$CODE_MESURE_IMPOSSIBLE" ] && echo 1 || echo 0)"

if [ "$TOTAL" -gt 0 ]; then
  pub stale_precheck_rc "$CODE_PERIME"
  {
    echo "[stale_precheck $ID] PEREMPTION VUE AVANT LA COURSE : $TOTAL fichier(s) plus recent(s) que $REF."
    [ "$VS_NEUFS" -gt 0 ] && echo "  source(s) du VERDICT : ${VS_NEUFS_L:--}"
    [ "$MOT_NEUFS" -gt 0 ] && echo "  source(s) MOTEUR     : ${MOT_NEUFS_L:--}"
    echo "  C'est le constat que validators/generic.sh rendrait a la fin de l'essai. La course"
    echo "  qui demarre le repare ; si elle n'aboutit pas, l'essai mourra la-dessus."
  } >&2
  exit "$CODE_PERIME"
fi
pub stale_precheck_rc 0
echo "[stale_precheck $ID] $((VS_N + MOT_N)) fichier(s) compares contre $REF : aucun plus recent." >&2
exit 0
