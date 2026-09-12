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
# CE QUI MANQUAIT ENCORE (harness-verdict-sources-are-incomplete, 2026-09-12) :
#
#   1. LE CRITERE. `gate.key/op/value`, `frames_min` et `device` vivent dans `backlog.yaml`, que
#      l'orchestrateur reecrit toutes les secondes : epingler le FICHIER ferait rougir des
#      preuves que personne n'a touchees. On epingle donc le SOUS-ARBRE de l'item — la valeur
#      du critere, canonisee ici et nulle part ailleurs (mode `criterion`). Un seuil desserre
#      APRES la course change cette empreinte, et la porte le voit.
#   2. LES ACQUIS. `.autoport/acquis/*.sh` prononcent un verdict a CHAQUE fermeture (GATE 3 de
#      l'orchestrateur) et n'etaient epingles par rien. Ils entrent dans le socle, et leur
#      nombre + leur empreinte collective sont publies A PART : huit qui tombe a sept est un
#      defaut, pas un detail.
#   3. LES COMMENTAIRES NE SONT PLUS DES CITATIONS. L'en-tete de `lib/ablation_anchor.sh` NOMME
#      ses trois anciens lecteurs : deux d'entre eux se retrouvaient epingles au verdict d'items
#      qui ne les appellent jamais, et une coquille corrigee dans cette prose rendait la preuve
#      rouge. Une prose ne cree pas une dependance. `AUTOPORT_VS_COMMENTS=1` reproduit l'ancienne
#      derivation — le recensement s'en sert pour PUBLIER l'ecart, jamais la porte.
#      Ce reglage ne peut qu'AJOUTER des fichiers : il n'y a pas de chemin par lequel il
#      affaiblisse l'epinglage.
#
# UN SEUL NOMMEUR (NOMMAGE/un-seul-endroit). L'ECRIVAIN (`lib/proof_run.sh`, qui publie
# `verdict_sources_sha=` dans la preuve), le LECTEUR (`validators/generic.sh`, qui RECALCULE
# l'empreinte a la lecture) et les BACS A SABLE (qui copient ce qu'ils declarent) appellent ce
# fichier-ci. Deux listes ecrites a deux endroits divergent en silence ; il n'y en a qu'une.
#
# LA LISTE EST DERIVEE DU CONTENU, PAS ECRITE A LA MAIN. On part du socle (le juge, le
# producteur, ce fichier, le chargeur du backlog, les acquis, le recensement de l'item) et on
# suit les chemins `.autoport/` que le CODE de ces fichiers CITE, jusqu'au point fixe. Une liste
# ecrite a la main oublie ; celle-ci ne peut pas rater un script que le verdict appelle, puisqu'il
# faut bien le nommer pour l'appeler.
# Ce fichier est dans sa propre liste : un nommeur qu'on peut editer sans etre vu ne garde rien.
#
# Usage : lib/verdict_sources.sh <item-id> [kv|list|sha|count|newer <fichier>|criterion|
#                                           criterion_sha|acquis_list|acquis_count|acquis_sha]
#   kv (defaut) : verdict_sources_count= verdict_sources_sha= verdict_sources_list=
#                 verdict_criterion= verdict_criterion_sha=
#                 verdict_acquis_count= verdict_acquis_sha=
#   newer F     : ecrit sur stdout les sources PLUS RECENTES que F (vide = preuve a jour)
set -uo pipefail
# LE TRI EST DANS L EMPREINTE : une locale differente entre le producteur et le juge rendrait
# deux ordres, donc deux sha, sur des fichiers identiques.
export LC_ALL=C

ID="${1:-}"; WHAT="${2:-kv}"; REF="${3:-}"
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 1
cd "$ROOT" || exit 1
AP=.autoport

# Le socle. `orchestrator.py` n'y est PAS : il lance la porte, il ne calcule aucun verdict, et il
# bouge tous les jours — l'epingler ferait rougir des preuves que personne n'a touchees.
# `lib/backlog.py` y est NOMME : `validators/generic.sh` l'importe (`__import__('backlog')`) pour
# lire le critere, et aucune derivation de chemin ne peut voir un import python. Il y entrait
# jusqu'ici par ACCIDENT, cite dans un commentaire de `proof_run.sh` ; depuis que les commentaires
# ne comptent plus, il faut le nommer.
# `lib/gate_verdict.py` y est NOMME pour la meme raison : c'est L'AUTORITE qui prononce le verdict
# d'un essai, et `backlog.py` l'atteint par un import python (`from lib import gate_verdict`) —
# invisible a toute derivation de CHEMINS. Ce qui prononce un verdict est epingle, sans exception.
SOCLE="$AP/validators/generic.sh $AP/lib/proof_run.sh $AP/lib/verdict_sources.sh"
SOCLE="$SOCLE $AP/lib/backlog.py $AP/lib/gate_verdict.py"
# LES ACQUIS DE L'OWNER. Ils jugent a chaque fermeture ; ils sont donc des sources du verdict.
for _a in "$AP"/acquis/*.sh; do [ -f "$_a" ] && SOCLE="$SOCLE $_a"; done
[ -n "$ID" ] && [ -f "$AP/lib/census/$ID.sh" ] && SOCLE="$SOCLE $AP/lib/census/$ID.sh"

# CE QU'UN FICHIER CITE — son CODE, pas sa prose. `tests/` en est : un banc dont une jambe est
# une jambe de pytest a ce fichier-la pour source de verdict, au meme titre qu'un script de `lib/`. Le `#` d'un commentaire shell ou python ouvre
# en debut de mot : `${1#debug.}`, `"$#"` et `'^#'` ne sont donc pas touches.
VS_COMMENTS="${AUTOPORT_VS_COMMENTS:-0}"
cites(){
  if [ "$VS_COMMENTS" = 1 ]; then cat -- "$1"
  else sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//' -- "$1"
  fi 2>/dev/null | grep -oE '(lib|validators|acquis|tests)/[A-Za-z0-9_./-]+\.(sh|py)' | sort -u
}

# Point fixe : tant qu'un fichier retenu cite un chemin `.autoport/` qui existe, on l'ajoute.
LISTE=""
FRONT="$SOCLE"
while [ -n "$FRONT" ]; do
  SUIV=""
  for f in $FRONT; do
    case " $LISTE " in *" $f "*) continue ;; esac
    [ -f "$f" ] || continue
    LISTE="$LISTE $f"
    for rel in $(cites "$f"); do
      [ -f "$AP/$rel" ] || continue
      case " $LISTE $SUIV " in *" $AP/$rel "*) continue ;; esac
      SUIV="$SUIV $AP/$rel"
    done
  done
  FRONT="$SUIV"
done
# shellcheck disable=SC2086
LISTE=$(printf '%s\n' $LISTE | sort -u)

# ------------------------------------------------------------------- LES ACQUIS, A PART -----
acquis_liste(){ ls -1 "$AP"/acquis/*.sh 2>/dev/null | sort; }
acquis_sha(){ acquis_liste | xargs -r sha256sum | sha256sum | cut -c1-16; }
acquis_count(){ acquis_liste | grep -c . ; }

# ------------------------------------------------------------------ LE CRITERE, CANONISE ----
# LA MEME LECTURE QUE `validators/generic.sh`, jusqu'au repli et jusqu'au defaut de `frames_min` :
# une canonisation qui divergerait du juge epinglerait un critere que personne n'applique.
# AUCUN ESPACE : une valeur de proof.txt qui en porte un est jetee a la publication.
criterion(){
  python3 - "$ID" <<'PY'
import sys
sys.path.insert(0, '.autoport/lib')
try:
    it = __import__('backlog').load().get(sys.argv[1]) or {}
except Exception:
    try:
        import yaml
        doc = yaml.safe_load(open('.autoport/backlog.yaml', encoding='utf-8')) or {}
        it = next((c for c in (doc.get('items') or []) if c.get('id') == sys.argv[1]), {})
    except Exception:
        it = {}
g = it.get('gate') or {}
brut = "key=%s|op=%s|value=%s|frames_min=%s|device=%s" % (
    g.get('key', ''), g.get('op', ''), g.get('value', ''),
    it.get('frames_min', 300), 1 if it.get('device') else 0)
print(''.join(c if (c.isalnum() or c in '=|<>!.,:;_+*/-') else '_' for c in brut))
PY
}
criterion_sha(){ criterion | tr -d '\n' | sha256sum | cut -c1-16; }

case "$WHAT" in
  list)  printf '%s\n' "$LISTE" ;;
  count) printf '%s\n' "$LISTE" | grep -c . ;;
  sha)   printf '%s\n' "$LISTE" | xargs -r sha256sum | sha256sum | cut -c1-16 ;;
  criterion)     criterion ;;
  criterion_sha) criterion_sha ;;
  acquis_list)   acquis_liste ;;
  acquis_count)  acquis_count ;;
  acquis_sha)    acquis_sha ;;
  newer)
    [ -n "$REF" ] || { echo "verdict_sources.sh newer <fichier>" >&2; exit 2; }
    for f in $LISTE; do [ "$f" -nt "$REF" ] && printf '%s\n' "$f"; done; : ;;
  kv)
    printf 'verdict_sources_count=%s\n' "$(printf '%s\n' "$LISTE" | grep -c .)"
    printf 'verdict_sources_sha=%s\n'   "$(printf '%s\n' "$LISTE" | xargs -r sha256sum | sha256sum | cut -c1-16)"
    # Une valeur de proof.txt ne peut porter AUCUN espace : elle serait jetee a la publication.
    printf 'verdict_sources_list=%s\n'  "$(printf '%s\n' "$LISTE" | paste -sd, -)"
    printf 'verdict_criterion=%s\n'     "$(criterion)"
    printf 'verdict_criterion_sha=%s\n' "$(criterion_sha)"
    printf 'verdict_acquis_count=%s\n'  "$(acquis_count)"
    printf 'verdict_acquis_sha=%s\n'    "$(acquis_sha)" ;;
  *) echo "usage: verdict_sources.sh <item-id> [kv|list|sha|count|newer <fichier>|criterion|criterion_sha|acquis_list|acquis_count|acquis_sha]" >&2; exit 2 ;;
esac
