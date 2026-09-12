#!/usr/bin/env bash
# census/harness-proof-impossible-must-be-read.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course,
# sa sortie `cle=valeur` rejoignant celle du moteur dans le meme journal. Il n'ecrit aucun champ
# de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL MESURE, DANS L'ORDRE DES QUATRE POINTS DU LIVRABLE :
#   1. la PORTE DE FERMETURE lit l'etat nomme et ne rend plus « pas de preuve »  -> ird_gate
#   2. `autoport status` — et le digest de l'owner — le font apparaitre           -> ird_statut
#   3. un etat SEME est vu par les DEUX lecteurs apres, par aucun avant           -> ird_semis
#   4. l'AGE de la cause est publie, pas seulement son existence                  -> ird_age
#   + la comptabilite des essais requalifies, et les comptes que le point 1 exige -> ird_compta
#
# TROIS SOURCES, jamais une seule :
#   - LE BANC (`lib/impossible_read_selftest.py`) : la VRAIE `close_gate` et le VRAI
#     `status_report`, sur un etat nomme ECRIT PAR LE VRAI `lib/proof_impossible.sh` dans des
#     dossiers jetables. Chaque lecteur est joue par DEUX codes : celui du disque et celui
#     d'AVANT ce chantier, ancre par MARQUEUR et jamais par `HEAD:`.
#   - CE DEPOT, MAINTENANT : `state.json`, les etats debout dans `reports/`, et le texte que
#     le VRAI `./.autoport/autoport status` rend a la seconde ou le recensement tourne.
#   - LA COURSE EN TRAIN DE SE FAIRE : `reports/<id>/proof-wait.txt`, ecrit par proof_run.sh.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte.
#
# CE QUI N'EST PAS COMPTE, ET POURQUOI. `engine_dirty` — les fichiers moteur sales de CE depot
# — est PUBLIE mais n'entre PAS dans la somme : compter la salete d'un autre item rendrait
# cette porte rouge pour une cause exterieure, exactement ce que le chantier precedent a
# corrige. `impossible_live_*` non plus : le harnais va tres bien la plupart du temps, et
# exiger une impossibilite REELLE pour fermer serait exiger une panne. La non-vacuite vient du
# semis, ou l'etat est FABRIQUE a chaque course par le vrai producteur.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "ird_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

pub(){ printf '%s=%s\n' "$1" "${2:--}"; }

# ================================================================= le banc, les deux axes ===
BN=$(timeout 900 python3 "$AP/lib/impossible_read_selftest.py" 2>/dev/null)
s(){ printf '%s\n' "$BN" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ============================================== ce depot, maintenant, et l'etat de la course =
LV=$(python3 - "$ROOT" "${AUTOPORT_CENSUS_DIR:-}" <<'PY' 2>/dev/null
import json, os, subprocess, sys
from pathlib import Path
root, cdir = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(root, '.autoport'))
from lib import impossible as I                                  # noqa: E402

# 1. LES ETATS DEBOUT DE CE DEPOT, MAINTENANT. Publies, jamais comptes : exiger une panne
# reelle pour fermer serait exiger une panne.
reports = os.path.join(root, '.autoport', 'reports')
vus = I.read_all(reports)
print('live_states=%d' % len(vus))
print('live_list=%s' % (','.join('%s@%ss' % (k, v['since_s']) for k, v in vus.items()) or '-'))

# 2. LA COMPTABILITE, telle que state.json la porte. `read` = etats LUS par la porte,
# `total` = verdicts REQUALIFIES : les deux comptes que le point 1 du livrable demande.
book = {}
try:
    book = (json.loads(Path(root, '.autoport/state.json').read_text())
            .get('proof_impossible') or {})
except Exception:
    book = {}
lus = sum(int((v or {}).get('read', 0) or 0) for v in book.values() if isinstance(v, dict))
req = sum(int((v or {}).get('total', 0) or 0) for v in book.values() if isinstance(v, dict))
print('state_read=%d' % lus)
print('state_requalified=%d' % req)
print('state_items=%d' % len(book))
print('state_list=%s' % (','.join('%s:%s' % (k, (v or {}).get('total', 0))
                                  for k, v in sorted(book.items())) or '-'))
import orchestrator as O                                         # noqa: E402
print('state_key=%d' % int('proof_impossible' in O.STATE_KEYS))
print('ceiling=%d' % int(getattr(O, 'MAX_IMPOSSIBLE_IN_A_ROW', -1)))
print('counts_fn=%d' % int(hasattr(O, 'impossible_read_counts')))

# 3. LE TEXTE EFFECTIVEMENT RENDU par le VRAI binaire, pas une intention. On le lance, on lit
# sa sortie. Rien ne se ferme si `autoport status` meurt en le faisant.
try:
    r = subprocess.run(['./.autoport/autoport', 'status'], cwd=root,
                       capture_output=True, text=True, timeout=300)
    out, rc = r.stdout, r.returncode
except Exception as exc:                                          # noqa: BLE001
    out, rc = '', 'exc:%s' % type(exc).__name__
print('status_rc=%s' % rc)
print('status_len=%d' % len(out))
bloc = ''
if '## Preuve impossible' in out:
    bloc = out[out.index('## Preuve impossible'):].split('\n\n')[0]
print('status_has_section=%d' % int(bool(bloc)))
print('status_text=%s' % (bloc.replace('\n', ' | ')[:300] or '-'))

# 4. L'ATTENTE DE CETTE COURSE, ecrite par proof_run.sh avant l'amorcage.
w = {}
if cdir:
    f = Path(cdir) / 'proof-wait.txt'
    if f.exists():
        for line in f.read_text(errors='replace').splitlines():
            if '=' in line:
                k, v = line.split('=', 1)
                w[k] = v
print('wait_file=%d' % int(bool(w)))
for k in ('proof_wait_s', 'deploy_lock_pid', 'deploy_lock_alive', 'deploy_lock_age_s'):
    print('w_%s=%s' % (k, w.get(k, '-') or '-'))

# 5. LE LECTEUR LUI-MEME, exerce sur les durees que le livrable exige. `human(-1)` ne doit
# JAMAIS rendre un nombre : une duree qu'on n'a pas mesuree ne s'invente pas.
print('human_638=%s' % I.human(23880))
print('human_30=%s' % I.human(30))
print('human_unknown=%s' % I.human(-1))
print('bucket_638=%s' % I.bucket(23880))
print('bucket_30=%s' % I.bucket(30))
print('paliers=%d' % len(I.PALIERS))
print('suffixes=%s' % ','.join(x or 'livre' for x in I.SUFFIXES))
print('keys=%d' % len(I.KEYS))
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

# Le banc doit AVOIR tourne, et CHAQUE temoin d'avant doit etre ancre par MARQUEUR.
for arm in gate_neuf gate_vieux gate_neuf_vide stat_neuf stat_vieux; do
  [ "$(n "${arm}_ran")" = 1 ] || faute "bras-$arm-muet"
done
[ "$(s before_orch_commit)" = "-" ] && faute temoin-avant-orchestrateur-absent
[ "$(s before_bl_commit)" = "-" ] && faute temoin-avant-statut-absent
[ "$(n before_orch_marker_absent)" = 1 ] || faute temoin-avant-orch-porte-le-marqueur
[ "$(n before_bl_marker_absent)" = 1 ] || faute temoin-avant-statut-porte-le-marqueur
[ "$(n marker_orch_live)" = 1 ] || faute marqueur-orch-absent-du-disque
[ "$(n marker_bl_live)" = 1 ] || faute marqueur-statut-absent-du-disque
[ -n "$LV" ] || faute lecture-du-depot-muette

# --- 1. LA PORTE DE FERMETURE LIT L'ETAT ET NE REND PLUS « PAS DE PREUVE ». -----------------
t_gate=0
t_gate=$((t_gate + $(eqs gate_neuf_status impossible)))
t_gate=$((t_gate + $(eq gate_neuf_is_impossible 1)))
t_gate=$((t_gate + $(eq gate_neuf_names_reason 1)))     # la cause, NOMMEE
t_gate=$((t_gate + $(eq gate_neuf_names_arm 1)))        # et le bras : livre ou ablation
t_gate=$((t_gate + $(eq gate_neuf_sig_validator_ok 1))) # elle voit un essai REFUSE
t_gate=$((t_gate + $(eq gate_neuf_sig_since 1)))
t_gate=$((t_gate + $(eq gate_neuf_seeded 1)))
t_gate=$((t_gate + $(eq gate_neuf_seeded_keys 12)))     # les 12 cles du producteur
t_gate=$((t_gate + $(eq src_close_gate_calls 1)))       # UN appel, et
t_gate=$((t_gate + $(eq src_close_gate_under_rc 0)))    # HORS du `if v.returncode == 0`
t_gate=$((t_gate + $(eq src_outcome_impossible 1)))
t_gate=$((t_gate + $(eq src_main_branch 1)))            # la boucle sait quoi en faire
t_gate=$((t_gate + $(eq src_orch_builds_filename 0)))   # UN SEUL lecteur : lib/impossible.py
t_gate=$((t_gate + $(eq src_bl_builds_filename 0)))
# LE BRAS D'AVANT : meme etat seme, il ne le voit pas — et il ne pouvait meme pas etre appele.
t_gate=$((t_gate + $(eq gate_vieux_is_impossible 0)))
t_gate=$((t_gate + $(eq gate_vieux_names_reason 0)))
t_gate=$((t_gate + $(eq gate_vieux_sig_validator_ok 0)))
t_gate=$((t_gate + $(eq gate_vieux_seeded 1)))          # le MEME etat, pourtant present
t_gate=$((t_gate + $(eq gate_vieux_has_requalify 0)))
# ANTI-BAVARDAGE : la porte neuve ne crie pas « impossible » quand rien ne l'est.
t_gate=$((t_gate + $(eq gate_neuf_vide_is_impossible 0)))
t_gate=$((t_gate + $(eqs gate_neuf_vide_status fail)))  # le verdict du validateur tient
t_gate=$((t_gate + $(eq ctrl_vide_is_impossible 0)))
t_gate=$((t_gate + $(eq ctrl_perime_is_impossible 0)))       # etat perime par un proof.txt
t_gate=$((t_gate + $(eq ctrl_perime_temoin_is_impossible 1))) # ... et debout des qu'il repart
t_gate=$((t_gate + $(eq ctrl_ancien_is_impossible 0)))       # etat d'un essai PRECEDENT
t_gate=$((t_gate + $(eqs ctrl_valide_status pass)))          # rien n'est casse pour les autres

# --- 2. `autoport status` ET LE DIGEST DE L'OWNER LE FONT APPARAITRE. -----------------------
t_statut=0
t_statut=$((t_statut + $(eq stat_neuf_has_section 1)))
t_statut=$((t_statut + $(eq stat_neuf_names_feature 1)))     # dans les mots de l'owner
t_statut=$((t_statut + $(eq stat_neuf_names_reason 1)))
t_statut=$((t_statut + $(eq stat_neuf_says_alive 1)))        # verrou VIVANT, dit comme tel
t_statut=$((t_statut + $(eq stat_neuf_digest_apparition 1))) # le digest se REVEILLE
t_statut=$((t_statut + $(eq stat_neuf_digest_stable 1)))     # puis se tait
t_statut=$((t_statut + $(eq stat_neuf_digest_palier 1)))     # et se rereveille au PALIER
t_statut=$((t_statut + $(eq stat_neuf_digest_meme_palier_muet 1)))  # jamais a la seconde
t_statut=$((t_statut + $(eq src_bl_uses_reader 4)))
[ "$(n stat_neuf_len_delta)" -gt 100 ] 2>/dev/null || faute statut-neuf-texte-trop-court
[ "$(s stat_neuf_text)" = "-" ] && faute texte-rendu-non-publie
# LE BRAS D'AVANT : MEME etat seme, son texte ne bouge pas d'UN SEUL OCTET.
t_statut=$((t_statut + $(eq stat_vieux_has_section 0)))
t_statut=$((t_statut + $(eq stat_vieux_len_delta 0)))
t_statut=$((t_statut + $(eq stat_vieux_digest_apparition 0)))
t_statut=$((t_statut + $(eq stat_vieux_digest_palier 0)))
# LE VRAI BINAIRE, LANCE ICI : il ne doit pas mourir d'avoir appris a lire.
t_statut=$((t_statut + $(eql status_rc 0)))
[ "$(ln_ status_len)" -gt 100 ] 2>/dev/null || faute autoport-status-rendu-vide

# --- 3. UN ETAT SEME EST VU APRES, PAR PERSONNE AVANT. --------------------------------------
t_semis=0
t_semis=$((t_semis + $(eq stat_neuf_avant_has_section 0)))        # avant le semis : rien
t_semis=$((t_semis + $(eq stat_neuf_apres_retrait_has_section 0))) # apres retrait : rien
t_semis=$((t_semis + $(eq stat_vieux_avant_has_section 0)))
t_semis=$((t_semis + $(eq gate_neuf_vide_seeded 0)))
t_semis=$((t_semis + $(eq stat_neuf_has_section 1)))
t_semis=$((t_semis + $(eq gate_neuf_is_impossible 1)))
# Le semis vient du VRAI producteur : 12 cles, jamais un dictionnaire fabrique par le banc.
[ "$(n gate_neuf_seeded_keys)" = 12 ] || faute semis-degenere
[ "$(ln_ keys)" = 12 ] || faute lecteur-ne-connait-pas-les-douze-cles
[ "$(l suffixes)" = "livre,-off" ] || faute les-deux-bras-non-couverts

# --- 4. L'AGE EST PUBLIE, PAS SEULEMENT L'EXISTENCE. ----------------------------------------
t_age=0
t_age=$((t_age + $(eq gate_neuf_names_age 1)))          # « 6 h 38 » dans le verdict
t_age=$((t_age + $(eq gate_neuf_names_lock 1)))         # le pid du verrou, NOMME
# ... et dans le texte de l'owner, qui est RELU EN BOUCLE : un palier + l'instant EXACT ou
# l'etat a ete ecrit. Une duree a la seconde y reveillerait `watch.py` a chaque tour.
t_age=$((t_age + $(eq stat_neuf_names_bucket 1)))
t_age=$((t_age + $(eq stat_neuf_names_at 1)))
t_age=$((t_age + $(eq stat_neuf_stable_60s 1)))         # 60 s de plus : pas UN octet
t_age=$((t_age + $(eq stat_neuf_change_palier 1)))      # un PALIER franchi : ca se voit
t_age=$((t_age + $(eq stat_vieux_names_bucket 0)))
t_age=$((t_age + $(eq stat_vieux_change_palier 0)))
t_age=$((t_age + $(eq stat_neuf_names_lock 1)))
t_age=$((t_age + $(eq compta_dit_names_age 1)))
t_age=$((t_age + $(eq compta_dit_names_lock 1)))
t_age=$((t_age + $(eql human_638 "6 h 38")))
t_age=$((t_age + $(eql human_30 "30 s")))
t_age=$((t_age + $(eql human_unknown inconnu)))         # jamais un nombre invente
t_age=$((t_age + $(eql bucket_638 "plus de 2 h")))
t_age=$((t_age + $(eql bucket_30 "moins de 5 min")))
t_age=$((t_age + $(eql paliers 4)))

# --- 5. LA COMPTABILITE, ET LES DEUX COMPTES QUE LE POINT 1 EXIGE. --------------------------
t_compta=0
t_compta=$((t_compta + $(eqs compta_verdicts "requalifie,requalifie,requalifie,bloque")))
t_compta=$((t_compta + $(eqs compta_retries "3,3,3,3")))   # retries revient a l'avant-essai
t_compta=$((t_compta + $(eq compta_ceiling 3)))
t_compta=$((t_compta + $(eq compta_total 4)))
t_compta=$((t_compta + $(eq compta_read 4)))
t_compta=$((t_compta + $(eq compta_counts_read 4)))
t_compta=$((t_compta + $(eq compta_counts_requalified 4)))
t_compta=$((t_compta + $(eq compta_since_set 1)))
t_compta=$((t_compta + $(eq compta_after_reset_streak 0)))
t_compta=$((t_compta + $(eq compta_after_reset_total 4)))  # le total ne descend jamais
t_compta=$((t_compta + $(eq compta_state_key 1)))
t_compta=$((t_compta + $(eql state_key 1)))
t_compta=$((t_compta + $(eql ceiling 3)))
t_compta=$((t_compta + $(eql counts_fn 1)))
t_compta=$((t_compta + $(eqs compta_reason build-en-cours)))

# --- HORS PERIMETRE : la detection ne bouge pas, le jeu non plus. ---------------------------
[ "$(n src_untouched_lib_proof_run_sh)" = 1 ] || faute proof_run-modifie-hors-perimetre
[ "$(n src_untouched_lib_proof_impossible_sh)" = 1 ] || faute proof_impossible-modifie

TOTAL=$((t_gate + t_statut + t_semis + t_age + t_compta + penalty))

# ========================================================================= la publication ====
pub ird_census_ran "$([ -n "$BN" ] && [ -n "$LV" ] && echo 1 || echo 0)"
pub impossible_read_defects "$TOTAL"
pub impossible_read_defects_terms \
  "porte$t_gate+statut$t_statut+semis$t_semis+age$t_age+compta$t_compta+penalite$penalty${why:+:$why}"
pub ird_gate "$t_gate"
pub ird_statut "$t_statut"
pub ird_semis "$t_semis"
pub ird_age "$t_age"
pub ird_compta "$t_compta"
pub ird_witness_penalty "$penalty"

# LES GRANDEURS QUE LE LIVRABLE DEMANDE DE PUBLIER, nommees comme il les nomme, SEPAREMENT.
# 1. le compte d'etats LUS par la porte, et le compte de verdicts REQUALIFIES.
pub impossible_states_read "$(ln_ state_read)"
pub impossible_verdicts_requalified "$(ln_ state_requalified)"
pub impossible_state_items "$(ln_ state_items)"
pub impossible_state_list "$(l state_list)"
pub impossible_requalify_ceiling "$(ln_ ceiling)"
pub impossible_bench_states_read "$(n compta_counts_read)"
pub impossible_bench_requalified "$(n compta_counts_requalified)"
# 2. le TEXTE effectivement rendu par `./.autoport/autoport status`, pas une intention.
pub impossible_status_rc "$(l status_rc)"
pub impossible_status_len "$(ln_ status_len)"
pub impossible_status_has_section "$(ln_ status_has_section)"
pub impossible_status_text "$(l status_text)"
pub impossible_status_text_seeded "$(s stat_neuf_text)"
pub impossible_status_text_before "$(s stat_vieux_text)"
# 3. les deux bras, sur l'etat SEME comme sur le CODE.
pub impossible_gate_after "$(s gate_neuf_status)"
pub impossible_gate_before "$(s gate_vieux_status)"
pub impossible_gate_reason "$(s gate_neuf_reason)"
pub impossible_status_delta_after "$(n stat_neuf_len_delta)"
pub impossible_status_delta_before "$(n stat_vieux_len_delta)"
pub impossible_before_orch_commit "$(s before_orch_commit)"
pub impossible_before_status_commit "$(s before_bl_commit)"
# 4. l'AGE, des deux cotes : celui de l'etat et celui du verrou.
pub impossible_age_638 "$(l human_638)"
pub impossible_age_30 "$(l human_30)"
pub impossible_age_unknown "$(l human_unknown)"
pub impossible_bucket_638 "$(l bucket_638)"
pub impossible_bucket_30 "$(l bucket_30)"
pub impossible_status_stable_60s "$(n stat_neuf_stable_60s)"
pub impossible_status_change_palier "$(n stat_neuf_change_palier)"
pub impossible_live_states "$(ln_ live_states)"
pub impossible_live_list "$(l live_list)"
pub deploy_lock_pid_this_run "$(l w_deploy_lock_pid)"
pub deploy_lock_alive_this_run "$(l w_deploy_lock_alive)"
pub deploy_lock_age_s_this_run "$(l w_deploy_lock_age_s)"
pub proof_wait_s_this_run "$(l w_proof_wait_s)"
# 5. hors perimetre, PUBLIE et non compte.
pub engine_dirty_files "$(n src_engine_dirty)"
pub engine_dirty_list "$(s src_engine_dirty_list)"

# LES BRUTS, recopies tels quels : c'est ce qui rend la somme lisible et falsifiable. Sous un
# prefixe a eux — le moissonneur garde la DERNIERE valeur d'une cle, et un homonyme ecraserait
# un terme du verdict.
printf '%s\n' "$BN" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/ird_bn_\1=/p'
printf '%s\n' "$LV" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/ird_live_\1=/p'

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in orchestrator.py lib/backlog.py lib/impossible.py lib/proof_impossible.sh \
         lib/proof_run.sh lib/impossible_read_selftest.py \
         lib/census/harness-proof-impossible-must-be-read.sh; do
  k="ird_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
