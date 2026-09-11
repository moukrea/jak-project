#!/usr/bin/env bash
# checkpoint_snapshot.sh — ENREGISTRER UN ARBRE SALE SANS EMPORTER LE TRAVAIL DE PERSONNE.
#
# POURQUOI CE FICHIER EXISTE (2026-09-11).
# ----------------------------------------
# `auto_build_apk.sh` refusait de batir depuis un arbre sale — un APK fabrique pendant que le
# worker ecrit le moteur fait tester a l'owner un moteur a MOITIE reecrit (mesure du 2026-08-11
# 18:28). Le raffinement pose a 18:50 etait : « si ca compile, l'etat est coherent, on en fait un
# point de commit et on livre ». Ce raffinement s'ecrivait :
#
#     git add -- goal_src/ game/ android/ common/ goalc/
#     git commit -q -m "[autoport/builder] checkpoint automatique du constructeur ..."
#
# Or le constructeur ne PRODUIT rien sous ces cinq dossiers. Tout ce que ces deux lignes
# ramassaient appartenait a un chantier en cours, et le `git commit` nu validait en prime tout ce
# qu'un tiers avait pu poser dans l'index. Le 2026-09-11 la purge d'eclairage commandee par
# l'owner est partie EN ENTIER dans deux commits « checkpoint automatique » (2605a2f595,
# a2dcd34b3f), un troisieme en a emporte 73 de plus (ab2073a365) : `git log --grep` ne retrouve
# plus le travail sous le nom de son chantier, et un revert ou une bisection d'un « checkpoint
# constructeur » defait en silence une suppression demandee par l'owner.
#
# CE QUI REMPLACE LE COMMIT : UN INDEX JETABLE.
# ---------------------------------------------
# `GIT_INDEX_FILE` detourne toute ecriture d'index vers un fichier temporaire. On y recopie
# l'arbre de HEAD, on y ajoute l'etat du disque, on en tire un arbre, et on fabrique l'objet
# commit avec `git commit-tree`. AUCUNE de ces commandes ne touche l'index du worker, son arbre
# de travail, HEAD, ni `refs/heads/` : l'objet est range sous
# `refs/autoport/checkpoints/<horodatage>-<pid>`.
#
#   * hors de `refs/heads/` : la branche du worker ne bouge pas d'un octet, `git log` ne montre
#     rien, aucune bisection ni aucun revert ne peut tomber dessus, `git push` n'emporte rien ;
#   * mais l'etat exact qui a ete BATI reste lisible — `git for-each-ref refs/autoport/checkpoints`
#     les liste, `git show <ref>` montre le contenu. La tracabilite que le commit apportait est
#     conservee ; c'est l'appropriation qui disparait.
#
# POURQUOI PAS `git stash create`, QUI TIENDRAIT EN UNE LIGNE. Parce qu'il n'enregistre que les
# fichiers SUIVIS : un `.cpp` ou un `.gc` tout juste cree par un worker n'y entrerait pas, et
# l'instantane decrirait un arbre qui n'est pas celui qu'on a bati. C'est exactement le cas du
# checkpoint ab2073a365 (75 fichiers, dont des fichiers neufs).
#
# Le worker garde ses fichiers, son index et sa liberte de commiter son travail sous le prefixe de
# SON chantier, plus tard, quand il a fini.
#
# CE QUE CE FICHIER NE FAIT JAMAIS : `git commit`, `git reset`, `git checkout --`, `git restore`,
# `git stash push` (qui, lui, NETTOIE l'arbre de travail), ni le moindre `git add` sur l'index
# reel. `lib/checkpoint_selftest.sh` le VERIFIE en exercant la fonction sur un depot bac-a-sable :
# index conserve, arbre conserve, HEAD immobile, zero fichier emporte, et l'instantane complet.
#
# Usage :  . .autoport/lib/checkpoint_snapshot.sh
#          snap=$(checkpoint_snapshot "pourquoi") && echo "instantane $snap"

# Enregistre l'etat du disque. Ecrit l'identifiant de l'objet commit sur la sortie standard.
# Rend 0 = instantane pris ; 2 = rien a enregistrer (l'arbre est celui de HEAD) ; 1 = git a refuse.
checkpoint_snapshot() {
  local why=${1:-sans raison} head idx tree snap ref rc=0
  head=$(git rev-parse --verify HEAD 2>/dev/null) || return 1
  idx=$(mktemp "${TMPDIR:-/tmp}/autoport-checkpoint-index.XXXXXX") || return 1
  rm -f "$idx"   # `git read-tree` veut creer le fichier d'index lui-meme

  # L'INDEX JETABLE EST TOUT LE MECANISME. `GIT_INDEX_FILE` ne vaut que pour ces trois commandes ;
  # l'index du worker n'est ni lu ni ecrit. `:/` ancre le balayage a la racine du depot, quel que
  # soit le repertoire courant de l'appelant.
  if ! GIT_INDEX_FILE="$idx" git read-tree "$head" 2>/dev/null; then rc=1
  elif ! GIT_INDEX_FILE="$idx" git add -A -- :/ 2>/dev/null; then rc=1
  elif ! tree=$(GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null); then rc=1
  fi
  rm -f "$idx"
  [ "$rc" = 0 ] && [ -n "${tree:-}" ] || return 1

  # Meme arbre que HEAD : il n'y a rien a enregistrer, et surtout rien a signaler comme perdu.
  [ "$tree" != "$(git rev-parse --verify "$head^{tree}" 2>/dev/null)" ] || return 2

  snap=$(git commit-tree "$tree" -p "$head" -m "instantane constructeur: $why" 2>/dev/null) || return 1
  snap=$(printf '%s' "$snap" | tr -cd '0-9a-f')
  case "${#snap}" in 40|64) ;; *) return 1 ;; esac

  ref="refs/autoport/checkpoints/$(date -u +%Y%m%dT%H%M%SZ)-$$"
  git update-ref -m "instantane constructeur: $why" "$ref" "$snap" 2>/dev/null || return 1
  printf '%s\n' "$snap"
  return 0
}

# Borne le nombre de references d'instantanes conservees (defaut 100). On ne supprime QUE des
# references de cette famille, jamais un objet, jamais un fichier : l'arbre de travail du worker
# n'est evidemment pas concerne, et le contenu reste joignable tant que git ne ramasse pas ses
# objets.
checkpoint_snapshot_prune() {
  local keep=${1:-100} r
  git for-each-ref --sort=-refname --format='%(refname)' refs/autoport/checkpoints 2>/dev/null \
    | tail -n "+$((keep + 1))" \
    | while IFS= read -r r; do
        case "$r" in refs/autoport/checkpoints/*) git update-ref -d "$r" 2>/dev/null || true ;; esac
      done
}
