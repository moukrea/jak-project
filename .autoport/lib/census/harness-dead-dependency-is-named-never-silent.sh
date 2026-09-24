#!/usr/bin/env bash
# census/harness-dead-dependency-is-named-never-silent.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Il n'ecrit aucun champ de `proof.txt` : sa sortie `cle=valeur` rejoint le journal de course.
#
# LA GRANDEUR : `dead_dependencies` = dependances d'un item qui ATTEND (open / in-progress /
# blocked) vers un item ARCHIVE ou ABSENT dans le vrai backlog. Doit valoir 0.
#
# DEUX SOURCES, jamais une seule :
#   - LE BANC (`lib/dead_dep_selftest.py`) : la VRAIE classe Backlog sur des backlogs jetables.
#     Controle positif (dependance vers un archive -> comptee, lint et status la NOMMENT),
#     absent, bloque, redirection a l'archivage d'un supplante, controle negatif, et le code
#     d'AVANT (ancre par marqueur) qui doit rester MUET — sinon le banc ne voit rien.
#   - LE BACKLOG LIVRE : `dependency_health()` sur `.autoport/backlog.yaml`.
#
# INCONNU = DEFAUT. Un bras absent, un controle qui ne rougit pas, un negatif qui rougit, un
# banc d'avant qui parle : chacun AJOUTE au compte. Sans cette polarite, un lint supprime tout
# entier donnerait « 0 dependance morte » par inaction.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "dead_dep_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

pub(){ printf '%s=%s\n' "$1" "${2:--}"; }

ST=$(timeout 300 python3 "$AP/lib/dead_dep_selftest.py" 2>/dev/null)
s(){ printf '%s\n' "$ST" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

unknown=0; why=""
faute(){ unknown=$((unknown+1)); why="${why:+$why,}$1"; }
want(){ [ "$(n "$1")" = "$2" ] || faute "$1"; }

for arm in positif absent bloque supplante negatif avant reel; do want "${arm}_ran" 1; done
# CONTROLE POSITIF : l'item fabrique dependant d'un archive rougit, NOMME, jusque dans `status`.
want positif_dead 1; want positif_lint_named 1; want positif_status_named 1
want positif_descendance 1; want positif_digest_wakes 1
[ "$(s positif_next_open)" = libre ] || faute positif_next_open
want absent_dead 1; want absent_lint_named 1
want bloque_lint_named 1; want bloque_stuck 1; want bloque_dead 0
# SUPPLANTE : redirige a l'archivage, par les deux chemins d'ecriture ; un valide n'est pas touche.
[ "$(s supplante_set_status_deps)" = "neuf,autre" ] || faute supplante_set_status
[ "$(s supplante_update_deps)" = "neuf" ] || faute supplante_update
[ "$(s supplante_valide_intact)" = "ancien" ] || faute supplante_touche_un_valide
want supplante_set_status_trace 1; want supplante_dead_after 0
[ "$(s sans_successeur_deps)" = "ancien" ] || faute sans_successeur_invente
want sans_successeur_lint_named 1
# CONTROLE NEGATIF : rien a nommer, rien ne rougit.
want negatif_dead 0; want negatif_lint_dep 0; want negatif_status_block 0
want negatif_game_takeable 1
# LE BANC VOIT LE DEFAUT : le code d'avant se tait sur la meme dependance morte.
[ -n "$(s avant_commit)" ] && [ "$(s avant_commit)" != "-" ] || faute pas-de-code-d-avant
want avant_lint_named 0; want avant_status_named 0

real=$(n reel_dead)
[ "$real" -ge 0 ] 2>/dev/null || { real=1; faute reel-illisible; }
TOTAL=$((real + unknown))

pub dead_dep_census_ran "$([ -n "$ST" ] && echo 1 || echo 0)"
pub dead_dependencies "$TOTAL"
pub dead_dependencies_terms "reel$real+inconnu$unknown${why:+:$why}"
pub dead_dependencies_real "$real"
pub dead_dependencies_real_list "$(s reel_dead_list)"
pub dead_dependencies_unknown "$unknown"
pub dead_dep_blocked_deps "$(s reel_blocked_deps)"
pub dead_dep_game_stuck "$(s reel_game_stuck)"
# LE LIVRABLE (4) : prenables CONTRE ouverts, chantiers de jeu.
pub game_items_takeable "$(s reel_game_takeable)"
pub game_items_open "$(s reel_game_open)"
pub dead_dep_lint_real "$(s reel_lint_dep)"
pub dead_dep_bench_before_commit "$(s avant_commit)"

printf '%s\n' "$ST" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/dead_dep_st_\1=/p'

for f in lib/backlog.py lib/dead_dep_selftest.py lib/census/fake_backlog.py \
         lib/census/harness-dead-dependency-is-named-never-silent.sh backlog.yaml; do
  k="dead_dep_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
