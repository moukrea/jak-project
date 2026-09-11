#!/usr/bin/env bash
# checkpoint_selftest.sh — CE QUI REND `checkpoint_stolen_files == 0` FALSIFIABLE.
#
# POURQUOI. Le constructeur ne commite plus rien (voir `lib/checkpoint_snapshot.sh`). Un
# recensement de l'historique le dirait donc « zero fichier emporte » meme si la garde n'existait
# pas, tant qu'aucun checkpoint n'a lieu : une porte verte PAR INACTION, exactement ce que les
# DIRECTIVES refusent. Ce script fabrique la condition au lieu de l'attendre.
#
# Il monte un depot BAC-A-SABLE (jamais le depot du jeu), y plante le travail d'un chantier
# imaginaire dans les QUATRE etats que le checkpoint d'avant ramassait — un fichier modifie, un
# fichier modifie PUIS INDEXE, un fichier supprime, un fichier NEUF jamais suivi — puis :
#
#   BRAS LIVRE     : appelle `checkpoint_snapshot`, LA fonction que `auto_build_apk.sh` appelle.
#                    Doit emporter ZERO fichier : HEAD immobile, index intact, arbre intact, et
#                    l'instantane doit tout de meme CONSERVER les quatre gestes (tracabilite) —
#                    le fichier NEUF compris, que `git stash create` aurait laisse dehors.
#   BRAS ABLATION  : rejoue le code d'AVANT, mot pour mot (`git add -- goal_src/ game/ android/
#                    common/ goalc/` puis `git commit`). Doit emporter les quatre. C'est le
#                    controle positif : sans lui, un compteur toujours a zero — parce qu'il est
#                    casse — serait indistinguable d'une garde qui marche.
#
# Le juge n'est pas ici : ce script IMPRIME des `cle=valeur` et rien d'autre. C'est
# `game/system/checkpoint_census.cpp` qui applique la polarite « inconnu = defaut ».
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "selftest_ran=0"; exit 1; }
LIB="$ROOT/.autoport/lib/checkpoint_snapshot.sh"
[ -r "$LIB" ] || { echo "selftest_ran=0"; echo "selftest_guard_present=0"; exit 1; }

SB=$(mktemp -d "${TMPDIR:-/tmp}/autoport-checkpoint-selftest.XXXXXX") || { echo "selftest_ran=0"; exit 1; }
# Le nettoyage ne peut viser QUE le bac a sable qu'on vient de creer : le motif est verifie avant
# la suppression, et aucun chemin ne vient d'ailleurs.
cleanup() { case "$SB" in */autoport-checkpoint-selftest.*) rm -rf "$SB" ;; esac; }
trap cleanup EXIT
mkdir -p "$SB/nohooks"

# Monte un depot avec une base commitee, puis plante quatre gestes de chantier non commites.
plant() {
  local d="$1"
  # Les CINQ dossiers que le code d'avant nommait doivent exister : `git add -- a/ b/` refuse en
  # bloc des qu'un seul chemin ne correspond a rien, et le bras d'ablation n'emporterait alors
  # qu'un fichier au lieu de trois — un controle positif affaibli par son bac a sable.
  mkdir -p "$d/game/system" "$d/goal_src/jak1/pc" "$d/android/app" "$d/common/util" \
           "$d/goalc/compiler" || return 1
  cd "$d" || return 1
  git init -q . >/dev/null 2>&1 || return 1
  git config user.email selftest@autoport
  git config user.name "autoport selftest"
  git config commit.gpgsign false
  git config core.hooksPath "$SB/nohooks"
  printf 'origine\n' > game/system/moteur.cpp
  printf 'origine\n' > goal_src/jak1/pc/chantier.gc
  printf 'origine\n' > android/app/pont.java
  printf 'origine\n' > common/util/base.cpp
  printf 'origine\n' > goalc/compiler/base.cpp
  git add -- game goal_src android common goalc >/dev/null 2>&1 || return 1   # git-sandbox-ok
  git commit -q -m "base du chantier" >/dev/null 2>&1 || return 1   # git-sandbox-ok
  # LE TRAVAIL DU CHANTIER, dans les quatre etats que le checkpoint d'avant ramassait.
  printf 'purge demandee par l owner\n' >> game/system/moteur.cpp        # modifie
  printf 'purge demandee par l owner\n' >> goal_src/jak1/pc/chantier.gc  # modifie PUIS indexe
  git add -- goal_src/jak1/pc/chantier.gc >/dev/null 2>&1   # git-sandbox-ok
  rm -f android/app/pont.java                                            # supprime
  printf 'fichier neuf du chantier\n' > game/system/neuf.cpp             # NEUF, jamais suivi
  return 0
}

# ── BRAS LIVRE ────────────────────────────────────────────────────────────────────────────────
if ! plant "$SB/livre"; then echo "selftest_ran=0"; exit 1; fi
head_before=$(git rev-parse HEAD)
index_before=$(git diff --cached --name-only | LC_ALL=C sort | md5sum | cut -d' ' -f1)
wt_before=$(git status --porcelain | LC_ALL=C sort | md5sum | cut -d' ' -f1)
planted=$(git status --porcelain | grep -c .)

# shellcheck source=/dev/null
. "$LIB"
snap=$(checkpoint_snapshot "selftest") ; snap_rc=$?

head_after=$(git rev-parse HEAD)
index_after=$(git diff --cached --name-only | LC_ALL=C sort | md5sum | cut -d' ' -f1)
wt_after=$(git status --porcelain | LC_ALL=C sort | md5sum | cut -d' ' -f1)

stolen=0
[ "$head_before" = "$head_after" ] || stolen=$(git diff --name-only "$head_before" "$head_after" | grep -c .)
snap_files=0
[ "$snap_rc" = 0 ] && [ -n "$snap" ] && snap_files=$(git diff --name-only "$head_after" "$snap" | grep -c .)
snap_refs=$(git for-each-ref --format='%(refname)' refs/autoport/checkpoints | grep -c .)

echo "selftest_ran=1"
echo "selftest_guard_present=1"
echo "selftest_planted=$planted"
echo "selftest_stolen=$stolen"
echo "selftest_head_moved=$([ "$head_before" = "$head_after" ] && echo 0 || echo 1)"
echo "selftest_index_kept=$([ "$index_before" = "$index_after" ] && echo 1 || echo 0)"
echo "selftest_worktree_kept=$([ "$wt_before" = "$wt_after" ] && echo 1 || echo 0)"
echo "selftest_snapshot_files=$snap_files"
echo "selftest_snapshot_refs=$snap_refs"
echo "selftest_snapshot_rc=$snap_rc"

# ── BRAS ABLATION : le code d'AVANT, mot pour mot ─────────────────────────────────────────────
if ! plant "$SB/ablation"; then echo "selftest_ablation_ran=0"; exit 0; fi
abl_head_before=$(git rev-parse HEAD)
abl_planted=$(git status --porcelain | grep -c .)
git add -- goal_src/ game/ android/ common/ goalc/ >/dev/null 2>&1                    # git-sandbox-ok
git commit -q -m "[autoport/builder] checkpoint automatique du constructeur : l'arbre compile, etat coherent livrable" >/dev/null 2>&1  # git-sandbox-ok
abl_head_after=$(git rev-parse HEAD)
abl_stolen=0
[ "$abl_head_before" = "$abl_head_after" ] || abl_stolen=$(git diff --name-only "$abl_head_before" "$abl_head_after" | grep -c .)
echo "selftest_ablation_ran=1"
echo "selftest_ablation_planted=$abl_planted"
echo "selftest_ablation_stolen=$abl_stolen"
exit 0
