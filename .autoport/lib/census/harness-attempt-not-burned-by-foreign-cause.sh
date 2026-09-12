#!/usr/bin/env bash
# census/harness-attempt-not-burned-by-foreign-cause.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course,
# sa sortie `cle=valeur` rejoignant celle du moteur dans le meme journal. Il n'ecrit aucun champ
# de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL MESURE, DANS L'ORDRE DES QUATRE POINTS DU LIVRABLE :
#   1. une salete ETRANGERE ne compte plus comme un essai rate        -> fcd_requal
#   2. un chemin durablement non committable est mis de cote UNE fois -> fcd_quar
#   3. le territoire moteur est defini a UN SEUL endroit              -> fcd_terr
#   4. une preuve impossible se lit « impossible », pas « absente »   -> fcd_lock
#
# TROIS SOURCES, jamais une seule :
#   - LE BANC (`lib/foreign_cause_selftest.py`) : la VRAIE `close_gate`, le VRAI
#     `git_commit_paths` et la VRAIE comptabilite d'essais sur des depots git jetables. Le
#     chemin impossible est fabrique par un `chmod 000` reel — `git add` ET `git commit`
#     sortent en 128 et le chemin reste sale —, jamais par un drapeau. Chaque cause est jouee
#     par DEUX codes : celui du disque et celui d'AVANT ce chantier, ancre par MARQUEUR.
#   - LA COURSE EN TRAIN DE SE FAIRE : l'attente de CE bras, nommee par `lib/impossible.py`, ecrit par `proof_run.sh`
#     juste avant d'amorcer. C'est la duree d'attente de CETTE course, pas une relecture de
#     script.
#   - CE DEPOT, MAINTENANT : l'arbre sale, le registre de mise de cote, `state.json`.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte.
#
# CE QUI N'EST PAS COMPTE, ET POURQUOI. `foreign_dirty_files` — les fichiers moteur sales de
# CE depot — est PUBLIE mais n'entre PAS dans la somme. Les compter rendrait la porte de cet
# item rouge pour la salete d'un autre : exactement le defaut qu'il corrige. La non-vacuite
# ne vient donc pas de l'arbre reel (propre la plupart du temps) mais des depots jetables, ou
# la salete etrangere et le chemin impossible sont SEMES a chaque course.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "fcd_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

pub(){ printf '%s=%s\n' "$1" "${2:--}"; }

# ================================================================= le banc, sept bras =======
BN=$(timeout 900 python3 "$AP/lib/foreign_cause_selftest.py" 2>/dev/null)
s(){ printf '%s\n' "$BN" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ============================================== ce depot, maintenant, et l'etat de la course =
LV=$(python3 - "$ROOT" "${AUTOPORT_CENSUS_DIR:-}" <<'PY' 2>/dev/null
import json, os, sys
from pathlib import Path
root, cdir = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(root, '.autoport'))
import orchestrator as O                                        # noqa: E402

# 1. L'ARBRE. Cet item est `no_code` et son perimetre lui interdit de toucher au jeu : tout
# fichier moteur sale ici appartient a quelqu'un d'autre. PUBLIE, jamais compte.
sales = O.engine_dirty_paths()
print('foreign_dirty=%d' % len(sales))
print('foreign_list=%s' % (','.join(sales[:20]) or '-'))

# 2. LA COMPTABILITE DES ESSAIS REQUALIFIES, telle que state.json la porte.
print('state_key=%d' % int('foreign_cause' in O.STATE_KEYS))
book = {}
try:
    book = (json.loads(Path(root, '.autoport/state.json').read_text())
            .get('foreign_cause') or {})
except Exception:
    book = {}
tot = sum(int((v or {}).get('total', 0) or 0) for v in book.values() if isinstance(v, dict))
print('requalified_total=%d' % tot)
print('requalified_items=%d' % len(book))
print('requalified_list=%s' % (','.join(
    '%s:%s' % (k, (v or {}).get('total', 0)) for k, v in sorted(book.items())) or '-'))

# 3. LE REGISTRE DE MISE DE COTE : les chemins ecartes, et DEPUIS QUAND.
q = O.load_quarantine()
print('quarantine_n=%d' % len(q))
print('quarantine_list=%s' % (','.join(
    '%s@%s' % (k, (v or {}).get('since', '?')) for k, v in sorted(q.items())) or '-'))
print('quarantine_file=%s' % O.quarantine_path().name)
print('quarantine_is_harness_state=%d' % int(
    O._is_harness_state('.autoport/' + O.quarantine_path().name)))

# 4. LE TERRITOIRE, tel que les DEUX portes le liront ici.
print('prefixes=%s' % ','.join(O.engine_prefixes()))
print('ceiling=%d' % int(getattr(O, 'MAX_FOREIGN_IN_A_ROW', -1)))

# 5. L'ATTENTE DE CETTE COURSE, ecrite par proof_run.sh avant l'amorcage. LE NOM VIENT DE
# `lib/impossible.py`, JAMAIS D'UN LITTERAL : ce lecteur cherchait `proof-wait.txt` code en dur
# pendant que le bras d'ablation ecrivait `proof-off-wait.txt`. L'attente de l'ablation n'etait
# donc lue par personne, sous une porte verte (signalement du 12/09).
import os as _os                                                            # noqa: E402
sys.path.insert(0, _os.path.join(root, '.autoport', 'lib'))
import impossible as _I                                                     # noqa: E402
_suf = _I.arm_suffix(_os.environ.get('AUTOPORT_CENSUS_ARMED', '1'))
w = {}
if cdir:
    f = Path(cdir) / _I.arm_name('wait', _suf)
    print('wait_name_read=%s' % f.name)
    print('wait_arm=%s' % (_suf or 'livre'))
    if f.exists():
        for line in f.read_text(errors='replace').splitlines():
            if '=' in line:
                k, v = line.split('=', 1)
                w[k] = v
print('wait_file=%d' % int(bool(w)))
for k in ('proof_wait_s', 'proof_wait_max_s', 'proof_wait_why',
          'deploy_lock_pid', 'deploy_lock_alive', 'deploy_lock_age_s', 'proof_wait_at'):
    print('w_%s=%s' % (k, w.get(k, '-') or '-'))
# L'etat nomme de CETTE course, s'il existe (il n'existe pas quand la course aboutit). LE NOM
# VIENT DE L'AUTORITE, PAR BRAS (signalement 2 du 12/09) : ce lecteur cherchait
# `proof-impossible.txt` code en dur, donc le bras LIVRE seulement. Un etat pose sur le bras
# d'ablation restait invisible — la MEME divergence que celle du fichier d'attente, corrigee
# deux lignes plus haut, laissee intacte deux lignes plus bas.
_nom_imp = _I.arm_name('impossible', _suf)
print('impossible_name_read=%s' % _nom_imp)
print('impossible_file=%d' % int(bool(cdir) and Path(cdir, _nom_imp).exists()))
PY
) || LV=""
l(){ printf '%s\n' "$LV" | sed -n "s/^$1=//p" | tail -1; }
ln_(){ local v; v=$(l "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ==================================================================== les termes du verdict ==
penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }
eq(){ [ "$(n "$1")" = "$2" ] && echo 0 || echo 1; }
eqs(){ [ "$(s "$1")" = "$2" ] && echo 0 || echo 1; }
eql(){ [ "$(l "$1")" = "$2" ] && echo 0 || echo 1; }

# Le banc doit AVOIR tourne, et le temoin d'avant doit etre ancre par MARQUEUR.
for arm in terr_neuf terr_vieux requal_neuf requal_vieux requal_propre quar_neuf quar_vieux; do
  [ "$(n "${arm}_ran")" = 1 ] || faute "bras-$arm-muet"
done
[ "$(s before_commit)" = "-" ] && faute temoin-avant-absent
[ "$(n before_marker_absent)" = 1 ] || faute temoin-avant-porte-le-marqueur
[ -n "$LV" ] || faute lecture-du-depot-muette

# --- 1. UNE SALETE ETRANGERE NE COMPTE PLUS COMME UN ESSAI RATE. ----------------------------
t_requal=0
t_requal=$((t_requal + $(eqs requal_neuf_status foreign)))   # `foreign`, JAMAIS `fail`
t_requal=$((t_requal + $(eq requal_neuf_is_gate0 1)))
t_requal=$((t_requal + $(eq requal_neuf_names_paths 1)))     # les chemins sont NOMMES
t_requal=$((t_requal + $(eq requal_neuf_has_requal 1)))
t_requal=$((t_requal + $(eq requal_neuf_retries_max 0)))     # AUCUN essai debite, jamais
t_requal=$((t_requal + $(eqs requal_neuf_verdicts \
                             "requalifie,requalifie,requalifie,bloque,bloque")))
t_requal=$((t_requal + $(eq requal_neuf_ceiling 3)))
t_requal=$((t_requal + $(eq requal_neuf_total 5)))           # le compte est tenu a part
t_requal=$((t_requal + $(eq requal_neuf_rec_paths 3)))       # et il nomme les chemins
t_requal=$((t_requal + $(eq requal_neuf_streak_after_reset 0)))
t_requal=$((t_requal + $(eql state_key 1)))                  # state.json porte la cle
[ "$(s requal_neuf_since)" = "-" ] && faute requalification-sans-date
# LE BRAS D'AVANT : meme depot, meme heritage, il rend `fail` et n'a pas la comptabilite.
t_requal=$((t_requal + $(eqs requal_vieux_status fail)))
t_requal=$((t_requal + $(eq requal_vieux_is_gate0 1)))
t_requal=$((t_requal + $(eq requal_vieux_has_requal 0)))
# ANTI-FAUX-ROUGE : l'arbre sale du travail DE L'ITEM ne doit pas declencher la porte.
t_requal=$((t_requal + $(eq requal_propre_is_gate0 0)))
t_requal=$((t_requal + $(eqs requal_propre_status awaiting-owner)))
t_requal=$((t_requal + $(eq requal_propre_tree_dirty 3)))    # non vacuite du controle
[ "$(ln_ state_key)" = 1 ] || faute state-json-sans-foreign-cause
[ "$(ln_ ceiling)" = 3 ] || faute plafond-de-serie-absent

# --- 2. UN CHEMIN DURABLEMENT NON COMMITTABLE EST MIS DE COTE, UNE FOIS. --------------------
# Le poison est VRAIMENT impossible pour git, DANS LES DEUX BRAS : sinon on mesure un decor.
for arm in quar_neuf quar_vieux; do
  [ "$(n "${arm}_poison_add_rc")" != 0 ] || faute "chemin-impossible-non-reproduit-$arm"
  [ "$(n "${arm}_poison_commit_rc")" != 0 ] || faute "chemin-impossible-non-reproduit-$arm"
  [ "$(n "${arm}_poison_still_dirty")" = 1 ] || faute "chemin-impossible-non-durable-$arm"
  [ "$(n "${arm}_paths2")" = 2 ] || faute "lot-de-taille-inattendue-$arm"
done
t_quar=0
t_quar=$((t_quar + $(eq quar_neuf_quarantined1 1)))          # mis de cote AU PREMIER refus
t_quar=$((t_quar + $(eq quar_neuf_book1 1)))
t_quar=$((t_quar + $(eq quar_neuf_book1_has_poison 1)))
t_quar=$((t_quar + $(eq quar_neuf_journal_says_aside 1)))    # SIGNALE, pas efface
t_quar=$((t_quar + $(eq quar_neuf_journal_names_poison 1)))
t_quar=$((t_quar + $(eq quar_neuf_refused2_delta 0)))        # plus JAMAIS re-presente
t_quar=$((t_quar + $(eq quar_neuf_skipped2 1)))              # et la mise de cote est comptee
t_quar=$((t_quar + $(eq quar_neuf_ok2 1)))                   # le reste du lot passe quand meme
t_quar=$((t_quar + $(eq quar_neuf_autre_committed 1)))
[ "$(s quar_neuf_book1_since)" = "-" ] && faute mise-de-cote-sans-date
[ "$(n quar_neuf_book1_reason_len)" -gt 20 ] 2>/dev/null || faute mise-de-cote-sans-raison-de-git
# LE BRAS D'AVANT : il le represente et le refait echouer, a chaque essai, indefiniment.
t_quar=$((t_quar + $(eq quar_vieux_refused2_delta 1)))
t_quar=$((t_quar + $(eq quar_vieux_book1 0)))
t_quar=$((t_quar + $(eq quar_vieux_quarantined1 -1)))
t_quar=$((t_quar + $(eq quar_vieux_journal_says_aside 0)))
# Le registre ne doit jamais partir dans le commit d'un worker.
[ "$(ln_ quarantine_is_harness_state)" = 1 ] || faute registre-committable-par-un-worker

# --- 3. LE TERRITOIRE MOTEUR EST DEFINI A UN SEUL ENDROIT, LU PAR LES DEUX PORTES. ----------
t_terr=0
t_terr=$((t_terr + $(eq terr_neuf_identical 1)))             # les deux listes, IDENTIQUES
t_terr=$((t_terr + $(eq terr_neuf_has_recorder 1)))
t_terr=$((t_terr + $(eqs terr_neuf_gate0_list "game/,common/,android/,goal_src/,goalc/")))
t_terr=$((t_terr + $(eqs terr_neuf_gate1_list "game/,common/,android/,goal_src/,goalc/")))
t_terr=$((t_terr + $(eq terr_neuf_is_gate1 0)))              # `common/` compte comme du travail
t_terr=$((t_terr + $(eqs terr_neuf_status awaiting-owner)))
t_terr=$((t_terr + $(eq terr_neuf_tree_dirty 1)))            # non vacuite : UN fichier, common/
t_terr=$((t_terr + $(eqs terr_neuf_dirty_list common/util/Territoire.cpp)))
t_terr=$((t_terr + $(eq src_territory_literals 1)))          # UNE definition, lue dans l'AST
t_terr=$((t_terr + $(eq src_gate_reads_accessor 1)))
t_terr=$((t_terr + $(eq src_dirty_reads_accessor 1)))
# LE BRAS D'AVANT : le MEME fichier de `common/` ne comptait pour rien a GATE 1.
t_terr=$((t_terr + $(eqs terr_vieux_status fail)))
t_terr=$((t_terr + $(eq terr_vieux_is_gate1 1)))
t_terr=$((t_terr + $(eq terr_vieux_has_recorder 0)))
[ "$(l prefixes)" = "game/,common/,android/,goal_src/,goalc/" ] || faute territoire-inattendu

# --- 4. UNE PREUVE IMPOSSIBLE SE LIT « IMPOSSIBLE », JAMAIS « PAS PRODUITE ». ---------------
t_lock=0
t_lock=$((t_lock + $(eq lock_script 1)))
t_lock=$((t_lock + $(eq lock_script_rc 0)))
t_lock=$((t_lock + $(eq lock_file 1)))
t_lock=$((t_lock + $(eq lock_keys 12)))
t_lock=$((t_lock + $(eq lock_wait_echoed 1)))                # la duree ATTENDUE, recopiee
t_lock=$((t_lock + $(eq lock_reason_echoed 1)))              # la raison, NOMMEE
t_lock=$((t_lock + $(eq lock_exit_named 1)))                 # la sortie 3, NOMMEE
t_lock=$((t_lock + $(eq lock_no_machine_field 1)))           # aucun champ de la machine
t_lock=$((t_lock + $(eq pr_prologue_marker 1)))
t_lock=$((t_lock + $(eq pr_die3_defined 1)))
t_lock=$((t_lock + $(eq pr_bare_exit3_after_prologue 0)))    # plus une seule sortie 3 nue
t_lock=$((t_lock + $(eq pr_publishes_wait 1)))
t_lock=$((t_lock + $(eq pr_writes_wait_file 1)))
t_lock=$((t_lock + $(eq pr_clears_impossible 1)))
[ "$(n pr_die3_calls)" -ge 15 ] 2>/dev/null || faute die3-appelee-par-trop-peu-de-sites
# LE TEMOIN DE CETTE COURSE : l'attente publiee par proof_run.sh, avant l'amorcage.
t_lock=$((t_lock + $(eql wait_file 1)))
[ "$(ln_ w_proof_wait_s)" -ge 0 ] 2>/dev/null || faute attente-de-cette-course-non-publiee
[ "$(ln_ w_deploy_lock_age_s)" -ge -1 ] 2>/dev/null || faute verrou-de-cette-course-non-mesure

TOTAL=$((t_requal + t_quar + t_terr + t_lock + penalty))

# ========================================================================= la publication ====
pub fcd_census_ran "$([ -n "$BN" ] && [ -n "$LV" ] && echo 1 || echo 0)"
pub foreign_cause_defects "$TOTAL"
pub foreign_cause_defects_terms \
  "requal$t_requal+quarantaine$t_quar+territoire$t_terr+verrou$t_lock+penalite$penalty${why:+:$why}"
pub fcd_requal "$t_requal"
pub fcd_quar "$t_quar"
pub fcd_terr "$t_terr"
pub fcd_lock "$t_lock"
pub fcd_witness_penalty "$penalty"

# LES GRANDEURS QUE LE LIVRABLE DEMANDE DE PUBLIER, nommees comme il les nomme, SEPAREMENT.
# 1. la salete etrangere, et les essais qu'elle a fait requalifier. PUBLIE, PAS COMPTE.
pub foreign_dirty_files "$(ln_ foreign_dirty)"
pub foreign_dirty_list "$(l foreign_list)"
pub foreign_requalified_attempts "$(ln_ requalified_total)"
pub foreign_requalified_items "$(ln_ requalified_items)"
pub foreign_requalified_list "$(l requalified_list)"
pub foreign_requalify_ceiling "$(ln_ ceiling)"
# 2. les chemins mis de cote, et DEPUIS QUAND.
pub quarantine_paths "$(ln_ quarantine_n)"
pub quarantine_list "$(l quarantine_list)"
pub quarantine_file "$(l quarantine_file)"
# 3. la liste effective de CHAQUE porte, telle que le banc l'a relevee a l'execution.
pub gate0_territory "$(s terr_neuf_gate0_list)"
pub gate1_territory "$(s terr_neuf_gate1_list)"
pub territory_identical "$(n terr_neuf_identical)"
pub territory_definitions "$(n src_territory_literals)"
pub territory_live "$(l prefixes)"
# 4. l'attente et la sortie 3, en etat NOMME.
pub deploy_lock_wait_s "$(l w_proof_wait_s)"
pub deploy_lock_wait_max_s "$(l w_proof_wait_max_s)"
pub deploy_lock_wait_why "$(l w_proof_wait_why)"
pub deploy_lock_pid "$(l w_deploy_lock_pid)"
pub deploy_lock_alive "$(l w_deploy_lock_alive)"
pub deploy_lock_age_s "$(l w_deploy_lock_age_s)"
pub proof_impossible_named "$(n lock_keys)"
pub proof_impossible_this_run "$(ln_ impossible_file)"
pub proof_run_bare_exit3 "$(n pr_bare_exit3_after_prologue)"
pub proof_run_die3_calls "$(n pr_die3_calls)"

# LES BRUTS, recopies tels quels : c'est ce qui rend la somme lisible et falsifiable. Sous un
# prefixe a eux — le moissonneur garde la DERNIERE valeur d'une cle, et un homonyme ecraserait
# un terme du verdict.
printf '%s\n' "$BN" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/fcd_bn_\1=/p'
printf '%s\n' "$LV" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/fcd_live_\1=/p'

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in orchestrator.py lib/proof_run.sh lib/proof_impossible.sh \
         lib/foreign_cause_selftest.py \
         lib/census/harness-attempt-not-burned-by-foreign-cause.sh; do
  k="fcd_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
