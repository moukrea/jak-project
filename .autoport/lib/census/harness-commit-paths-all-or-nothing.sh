#!/usr/bin/env bash
# census/harness-commit-paths-all-or-nothing.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course,
# sa sortie `cle=valeur` rejoignant celle du moteur dans le meme journal. Il n'ecrit aucun champ
# de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL MESURE, DANS L'ORDRE DES QUATRE POINTS DU LIVRABLE :
#   1. un chemin refuse n'emporte plus les autres, comptes SEPARES  -> cp_batch
#   2. le refus est DIT (chemin + raison de git), commit vide compte -> cp_journal
#   3. deux bras sur un depot jetable, chemin impossible REPRODUIT   -> cp_arms
#   4. la porte refuse de conclure sur un arbre sale herite          -> cp_gate
#
# DEUX SOURCES, jamais une seule :
#   - LE BANC (`lib/commit_paths_selftest.py`) : le VRAI `git_commit_paths` et la VRAIE
#     `close_gate` sur des depots git jetables. Six bras de commit (vieux/neuf x lot
#     impossible / lot normal / lot vide) et trois vantages de porte. Le chemin impossible
#     est fabrique par un `git rm` reel — suppression indexee, fichier absent de l'arbre
#     ET de l'index —, jamais par un drapeau.
#   - L'ARBRE REEL : `engine_dirty_paths()` de l'orchestrateur, lu sur CE depot, et le
#     cablage de la porte verifie dans l'AST de `orchestrator.py`. Une porte que personne
#     n'appelle avec sa ligne de base est une porte morte (le piege de la garde dont la
#     seule occurrence est son en-tete).
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte. Sans cette
# polarite, une porte `== 0` sur un nettoyage serait verte par INACTION : ici l'arbre est
# propre la plupart du temps, et `foreign_dirty=0` ne prouverait rien tout seul.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "cp_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

pub(){ printf '%s=%s\n' "$1" "${2:--}"; }

# ======================================================================= le banc a 9 bras ===
BN=$(timeout 600 python3 "$AP/lib/commit_paths_selftest.py" 2>/dev/null)
s(){ printf '%s\n' "$BN" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ====================================================================== l'arbre reel ========
LV=$(python3 - "$ROOT" <<'PY' 2>/dev/null
import ast, os, sys
from pathlib import Path
root = sys.argv[1]
sys.path.insert(0, os.path.join(root, '.autoport'))
import orchestrator as O                                        # noqa: E402

# CE DEPOT, MAINTENANT. Cet item est `no_code` et son perimetre interdit de toucher au jeu :
# tout fichier moteur sale ici appartient donc a quelqu'un d'autre.
sales = O.engine_dirty_paths()
print('foreign_dirty=%d' % len(sales))
print('foreign_list=%s' % (','.join(sales[:20]) or '-'))
print('helper=%d' % int(hasattr(O, 'foreign_dirty_engine_paths')))
print('stats_keys=%d' % len([k for k, v in O.COMMIT_PATHS_STATS.items() if isinstance(v, int)]))
print('state_key=%d' % int('commit_paths' in O.STATE_KEYS))

# LE CABLAGE. Une porte qu'on n'appelle jamais avec sa ligne de base ne juge rien :
# on lit l'AST, pas un grep — un commentaire qui cite l'appel ne compte pas.
tree = ast.parse(Path(root, '.autoport/orchestrator.py').read_text(encoding='utf-8'))
fn = next((x for x in ast.walk(tree)
           if isinstance(x, ast.FunctionDef) and x.name == 'run_attempt'), None)
seed = called = gate_arg = 0
if fn is not None:
    for node in ast.walk(fn):
        if (isinstance(node, ast.Assign) and isinstance(node.value, ast.Call)
                and getattr(node.value.func, 'id', '') == 'engine_dirty_paths'
                and any(getattr(t, 'id', '') == 'pre_dirty_engine' for t in node.targets)):
            seed = 1
        if isinstance(node, ast.Call) and getattr(node.func, 'id', '') == 'close_gate':
            called = 1
            gate_arg = int(len(node.args) >= 2
                           and getattr(node.args[1], 'id', '') == 'pre_dirty_engine')
print('wire_seed=%d' % seed)
print('wire_call=%d' % called)
print('wire_arg=%d' % gate_arg)
# La porte elle-meme lit-elle le helper ? (sinon GATE 0 est un commentaire)
g = next((x for x in ast.walk(tree)
          if isinstance(x, ast.FunctionDef) and x.name == 'close_gate'), None)
print('gate_reads_helper=%d' % int(g is not None and any(
    isinstance(c, ast.Call) and getattr(c.func, 'id', '') == 'foreign_dirty_engine_paths'
    for c in ast.walk(g))))
PY
) || LV=""
l(){ printf '%s\n' "$LV" | sed -n "s/^$1=//p" | tail -1; }
ln_(){ local v; v=$(l "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ==================================================================== les termes du verdict ==
penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }
add(){ local v=$1; [ "$v" -ge 0 ] 2>/dev/null || v=1; echo "$v"; }
eq(){ [ "$(n "$1")" = "$2" ] && echo 0 || echo 1; }

# Le banc doit AVOIR tourne, et le temoin d'avant doit etre ancre par MARQUEUR.
for arm in vieux_lot neuf_lot vieux_ok neuf_ok vieux_vide neuf_vide; do
  [ "$(n "${arm}_ran")" = 1 ] || faute "bras-$arm-muet"
done
[ "$(s before_commit)" = "-" ] && faute temoin-avant-absent
[ "$(n before_marker_absent)" = 1 ] || faute temoin-avant-porte-le-marqueur

# --- 1. UN CHEMIN REFUSE N'EMPORTE PLUS LES AUTRES. Deux bras, MEME depot, MEME lot.
t_batch=0
t_batch=$((t_batch + $(eq neuf_lot_returned 1)))       # le neuf commite
t_batch=$((t_batch + $(eq neuf_lot_head_moved 1)))
t_batch=$((t_batch + $(eq neuf_lot_committed 8)))      # les 8, suppressions comprises
t_batch=$((t_batch + $(eq neuf_lot_dirty_after 0)))    # plus rien ne traine
t_batch=$((t_batch + $(eq neuf_lot_indexed 6)))        # comptes SEPARES, jamais un booleen
t_batch=$((t_batch + $(eq neuf_lot_refused 2)))
t_batch=$((t_batch + $(eq neuf_lot_rescued 6)))        # indexes APRES la chute du lot
t_batch=$((t_batch + $(eq vieux_lot_returned 0)))      # le vieux perd TOUT
t_batch=$((t_batch + $(eq vieux_lot_head_moved 0)))
t_batch=$((t_batch + $(eq vieux_lot_committed 0)))
t_batch=$((t_batch + $(eq vieux_lot_dirty_after 8)))
[ "$(s neuf_lot_refused_list)" = \
  "game/graphics/opengl_renderer/loader/PbrTestPattern.cpp,game/graphics/shaders/pbr_fused.glsl" ] \
  || faute chemins-refuses-mal-nommes

# --- 2. LE REFUS EST DIT, ET LE COMMIT VIDE EST COMPTE.
t_journal=0
t_journal=$((t_journal + $(eq neuf_lot_journal_names_path 1)))  # le chemin, en toutes lettres
t_journal=$((t_journal + $(eq neuf_lot_journal_quotes_git 1)))  # la raison RENDUE PAR GIT
t_journal=$((t_journal + $(eq neuf_lot_journal_says_perpath 1)))
t_journal=$((t_journal + $(eq neuf_vide_empty_avoided 1)))      # compte des commits vides evites
t_journal=$((t_journal + $(eq neuf_vide_journal_says_empty 1))) # et DIT
t_journal=$((t_journal + $(eq neuf_vide_head_moved 0)))
t_journal=$((t_journal + $(eq neuf_vide_commits 0)))
# Le bras d'AVANT doit etre MUET sur les deux, sinon le neuf ne dit rien de plus.
[ "$(n vieux_lot_journal_quotes_git)" = 0 ] || faute bras-vieux-deja-bavard
[ "$(n vieux_vide_journal_says_empty)" = 0 ] || faute bras-vieux-deja-corrige
# L'ancien garde-fou de vacuite etait MORT (`git diff --cached --pathspec-from-file` sort en
# 129) : le vieux bras allait donc jusqu'a `git commit` et sortait une erreur trompeuse.
[ "$(n vieux_vide_journal_says_commit_failed)" = 1 ] || faute garde-vide-d-avant-non-eprouve
[ "$(n neuf_vide_journal_says_commit_failed)" = 0 ] || faute neuf-va-encore-au-commit-vide

# --- 3. LES DEUX BRAS, ET LE CONTROLE POSITIF QUI LES REND COMPARABLES.
t_arms=0
t_arms=$((t_arms + $(eq vieux_ok_committed 6)))   # sans chemin impossible, le VIEUX marche
t_arms=$((t_arms + $(eq neuf_ok_committed 6)))    # et le NEUF ne casse pas le cas normal
t_arms=$((t_arms + $(eq vieux_ok_returned 1)))
t_arms=$((t_arms + $(eq neuf_ok_returned 1)))
t_arms=$((t_arms + $(eq neuf_ok_refused 0)))
t_arms=$((t_arms + $(eq vieux_ok_dirty_after 0)))
# Le chemin est VRAIMENT impossible pour git, dans LES DEUX bras : sinon on mesure un decor.
[ "$(n vieux_lot_git_reason_len)" -gt 20 ] 2>/dev/null || faute chemin-impossible-non-reproduit
[ "$(n neuf_lot_git_reason_len)" -gt 20 ] 2>/dev/null || faute chemin-impossible-non-reproduit
[ "$(n neuf_lot_paths)" = 8 ] || faute lot-de-taille-inattendue
[ "$(n vieux_lot_paths)" = 8 ] || faute lot-de-taille-inattendue

# --- 4. LA PORTE REFUSE DE CONCLURE SUR UN ARBRE SALE HERITE.
t_gate=0
[ "$(s porte_neuf_herite_status)" = "fail" ] || t_gate=$((t_gate+1))
t_gate=$((t_gate + $(eq porte_neuf_herite_is_gate0 1)))
t_gate=$((t_gate + $(eq porte_neuf_herite_reason_names_paths 1)))
t_gate=$((t_gate + $(eq porte_neuf_herite_accepts_baseline 1)))
# ANTI-FAUX-ROUGE : l'arbre sale du travail de l'item NE DOIT PAS fermer la porte.
t_gate=$((t_gate + $(eq porte_neuf_propre_is_gate0 0)))
t_gate=$((t_gate + $(eq porte_neuf_propre_tree_dirty 6)))       # non vacuite du controle
# LE BRAS D'AVANT : meme arbre, meme heritage, la porte n'existe pas.
t_gate=$((t_gate + $(eq porte_vieux_herite_is_gate0 0)))
t_gate=$((t_gate + $(eq porte_vieux_herite_accepts_baseline 0)))
t_gate=$((t_gate + $(eq porte_vieux_herite_tree_dirty 6)))
# LE CABLAGE, lu dans l'AST : une porte que personne n'appelle avec sa ligne de base ment.
for k in wire_seed wire_call wire_arg gate_reads_helper helper state_key; do
  [ "$(ln_ "$k")" = 1 ] || faute "cablage-$k"
done
[ "$(ln_ stats_keys)" -ge 6 ] 2>/dev/null || faute comptes-non-publies-separement
# L'ARBRE REEL. Cet item ne produit aucun code moteur : tout fichier moteur sale ici est
# le chantier non commite de quelqu'un d'autre, et la preuve porte alors sur un arbre
# que personne ne peut rejouer depuis HEAD.
FD=$(ln_ foreign_dirty)
t_gate=$((t_gate + $(add "$FD")))

TOTAL=$((t_batch + t_journal + t_arms + t_gate + penalty))

# ========================================================================= la publication ====
pub cp_census_ran "$([ -n "$BN" ] && [ -n "$LV" ] && echo 1 || echo 0)"
pub commit_paths_defects "$TOTAL"
pub commit_paths_defects_terms \
  "lot$t_batch+journal$t_journal+bras$t_arms+porte$t_gate+penalite$penalty${why:+:$why}"
pub cp_batch "$t_batch"
pub cp_journal "$t_journal"
pub cp_arms "$t_arms"
pub cp_gate "$t_gate"
pub cp_witness_penalty "$penalty"

# LES GRANDEURS QUE LE LIVRABLE DEMANDE DE PUBLIER, nommees comme il les nomme, SEPAREMENT.
pub commit_paths_indexed "$(n neuf_lot_indexed)"             # chemins indexes
pub commit_paths_refused "$(n neuf_lot_refused)"             # chemins refuses
pub commit_paths_refused_list "$(s neuf_lot_refused_list)"
pub commit_paths_empty_avoided "$(n neuf_vide_empty_avoided)"   # commits vides evites
pub commit_paths_rescued "$(n neuf_lot_rescued)"
pub commit_paths_lost_before "$(n vieux_lot_dirty_after)"    # ce que le code d'AVANT perdait
pub commit_paths_saved_after "$(n neuf_lot_committed)"       # ce que le code d'APRES sauve
pub commit_paths_foreign_dirty "$FD"                         # fichiers sales etrangers a l'item
pub commit_paths_foreign_list "$(l foreign_list)"

# LES BRUTS, recopies tels quels : c'est ce qui rend la somme lisible et falsifiable. Sous un
# prefixe a eux — le moissonneur garde la DERNIERE valeur d'une cle, et un homonyme ecraserait
# un terme du verdict.
printf '%s\n' "$BN" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/cp_bn_\1=/p'
printf '%s\n' "$LV" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/cp_live_\1=/p'

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in orchestrator.py lib/commit_paths_selftest.py \
         lib/census/harness-commit-paths-all-or-nothing.sh; do
  k="cp_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
