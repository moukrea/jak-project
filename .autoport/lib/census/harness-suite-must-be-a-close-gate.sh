#!/usr/bin/env bash
# census/harness-suite-must-be-a-close-gate.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course,
# sa sortie `cle=valeur` rejoignant celle du moteur dans le meme journal. Il n'ecrit aucun champ
# de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL MESURE, DANS L'ORDRE DES QUATRE POINTS DU LIVRABLE :
#   1. la porte LANCE la suite et LIT son resultat                        -> sg_porte
#      La suite LIVREE, jugee par le juge LIVRE : collectes, rouges, empreinte du registre.
#   2. le cout est borne, mesure, et le depassement est DIT               -> sg_cout
#      Le budget est ABLATE sur le meme semis (3600 s puis 0 s), et le plafond dur est
#      declenche par une suite qui PEND vraiment.
#   3. un item ne se donne pas du vert en s'inscrivant au registre        -> sg_registre
#   4. deux bras sur des depots jetables : AVANT ferme, APRES refuse      -> sg_bras
#
# DEUX SOURCES, jamais une seule :
#   - LE BANC `lib/suite_gate_selftest.py` : la VRAIE `orchestrator.close_gate` jouee sur six
#     semis jetables, avec le module d'orchestrateur d'AVANT puis celui d'APRES. Le bras
#     d'avant est ancre par MARQUEUR (`CLOSE-GATE/suite`), jamais lu a `HEAD:` — lu la, le
#     temoin s'accuserait lui-meme des le commit de ce chantier.
#   - LA SUITE LIVREE, lue par `lib/suite_gate.py` exactement comme la porte la lira : meme
#     fonction, meme registre, meme derivation de nodeid. Un recensement qui recopierait la
#     regle de la porte mesurerait sa recopie.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte. Sans cette
# polarite une porte `== 0` sur « la suite est lue » serait verte par INACTION : un banc qui ne
# tourne pas ne rate rien, et une suite qui ne collecte rien ne rougit jamais.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "sg_census_ran=0"; exit 1; }
cd "$ROOT" || exit 1
AP="$ROOT/.autoport"
ID="${AUTOPORT_CENSUS_ID:-harness-suite-must-be-a-close-gate}"

pub(){ printf '%s=%s\n' "$1" "${2:--}"; }

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/sg-census.XXXXXX") || { echo "sg_census_ran=0"; exit 1; }
trap 'rm -rf "$TMPD"' EXIT

# ============================================== 1. LE BANC : LA VRAIE PORTE, LES DEUX BRAS ===
timeout -k 15 900 python3 "$AP/lib/suite_gate_selftest.py" > "$TMPD/banc.txt" 2>"$TMPD/banc.err"
BANC_RC=$?
b(){ sed -n "s/^$1=//p" "$TMPD/banc.txt" 2>/dev/null | tail -1; }
bn(){ local v; v=$(b "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ====================== 2. LA SUITE LIVREE, LUE PAR LE JUGE LIVRE (ce que la porte lira) =====
# `--item` est pose : le juge impute au chantier COURANT toute entree du registre absente de la
# base, et va lire SON rapport. C'est exactement l'appel que fera `close_gate`.
timeout -k 15 900 python3 "$AP/lib/suite_gate.py" judge --item "$ID" --prefix live_ \
  > "$TMPD/live.txt" 2>"$TMPD/live.err"
LIVE_RC=$?
l(){ sed -n "s/^live_$1=//p" "$TMPD/live.txt" 2>/dev/null | tail -1; }
ln_(){ local v; v=$(l "$1"); case "$v" in ''|*[!0-9.-]*) echo -1 ;; *) echo "${v%%.*}" ;; esac; }

# ================================================================= les termes du verdict =====
penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }
eq(){ [ "$(bn "$1")" = "$2" ] && echo 0 || echo 1; }          # temoin du banc, valeur attendue
eqs(){ [ "$(b "$1")" = "$2" ] && echo 0 || echo 1; }          # idem, chaine
eql(){ [ "$(l "$1")" = "$2" ] && echo 0 || echo 1; }          # temoin de la course livree

[ "$BANC_RC" = 0 ] || faute banc-sorti-en-erreur
[ -s "$TMPD/banc.txt" ] || faute banc-muet
[ "$LIVE_RC" = 0 ] || faute juge-livre-sorti-en-erreur
[ -s "$TMPD/live.txt" ] || faute juge-livre-muet
[ "$(bn apres_ran)" = 1 ] || faute bras-apres-non-joue
[ "$(bn avant_ran)" = 1 ] || faute bras-avant-non-joue
[ "$(bn jg_ran)" = 1 ] || faute juge-non-interroge

# --- 1. LA PORTE LANCE LA SUITE ET LIT SON RESULTAT. -----------------------------------------
# LE DEFAUT, MESURE : `grep -n pytest orchestrator.py validators/` ne rendait RIEN. C'est la
# mesure du known_cause, rejouee sur le blob d'AVANT et sur le fichier d'aujourd'hui.
t_porte=0
t_porte=$((t_porte + $(eq src_pytest_orch_avant 0)))     # avant : personne ne lisait la suite
t_porte=$((t_porte + $(eq src_suite_gate_appels 1)))     # apres : la porte l'appelle, une fois
t_porte=$((t_porte + $(eq src_import_suite_gate 1)))
t_porte=$((t_porte + $(eq src_marqueur_vivant 1)))
t_porte=$((t_porte + $(eq src_marqueur_avant 0)))
# AUCUN RECHARGEMENT NEUF NI RETIRE : `harness-reload-must-not-kill-the-loop` publie « trois
# sites dans l'orchestrateur, zero rechargement nu ». Ce chantier ne lui prend pas son compte.
t_porte=$((t_porte + $(eq src_reload_sites_orch 3)))
t_porte=$((t_porte + $(eq src_reload_bruts_orch 0)))
# LA SUITE LIVREE, TELLE QUE LA PORTE LA LIRA. Non-vacuite : une suite qui ne collecte rien ne
# rate rien. Le plancher est dimensionne sur la population REELLEMENT lue (560 le 12/09).
t_porte=$((t_porte + $(eql verdict pass)))
t_porte=$((t_porte + $(eql unwaived 0)))
t_porte=$((t_porte + $(eql registry_read 1)))
t_porte=$((t_porte + $(eql rc 0)))
[ "$(ln_ collected)" -ge 540 ] 2>/dev/null || faute suite-livree-trop-maigre
[ -n "$(l registry_sha)" ] || faute empreinte-du-registre-absente

# --- 2. LE COUT EST BORNE, MESURE, ET LE DEPASSEMENT EST DIT. --------------------------------
t_cout=0
# Le budget ABLATE sur le MEME semis : rabaisse a zero il DOIT dire le depassement, et il ne
# doit PAS refuser — un cout qui derive n'est pas la faute de l'item qui ferme.
t_cout=$((t_cout + $(eq jg_budget_haut_over 0)))
t_cout=$((t_cout + $(eqs jg_budget_haut_verdict pass)))
t_cout=$((t_cout + $(eq jg_budget_bas_over 1)))
t_cout=$((t_cout + $(eqs jg_budget_bas_verdict pass)))
# LE PLAFOND DUR, sur une suite qui PEND vraiment : il tue, et il REFUSE.
t_cout=$((t_cout + $(eq jg_plafond_timed_out 1)))
t_cout=$((t_cout + $(eqs jg_plafond_verdict refuse)))
# La duree de la suite LIVREE est MESUREE, pas supposee, et elle tient sous le plafond dur.
[ "$(ln_ duration_s)" -ge 1 ] 2>/dev/null || faute duree-livree-non-mesuree
[ "$(ln_ budget_s)" -ge 1 ] 2>/dev/null || faute budget-non-publie
[ "$(l timed_out)" = 0 ] || faute suite-livree-tuee-par-le-plafond

# --- 3. UN ITEM NE SE DONNE PAS DU VERT EN S'INSCRIVANT AU REGISTRE. -------------------------
t_registre=0
t_registre=$((t_registre + $(eqs apres_dispense_ancienne_statut pass)))  # dispense d'AVANT : tient
t_registre=$((t_registre + $(eq jg_dispense_ancienne_self_added 0)))
t_registre=$((t_registre + $(eqs apres_dispense_propre_statut fail)))    # dispense a SOI : non
t_registre=$((t_registre + $(eq apres_dispense_propre_dit_propre 1)))
t_registre=$((t_registre + $(eq jg_dispense_propre_self_added 1)))
t_registre=$((t_registre + $(eqs apres_ajout_non_nomme_statut fail)))    # ajout MUET : refuse
t_registre=$((t_registre + $(eq apres_ajout_non_nomme_dit_non_nomme 1)))
t_registre=$((t_registre + $(eqs apres_ajout_nomme_statut pass)))        # ajout NOMME : ferme
t_registre=$((t_registre + $(eq jg_ajout_nomme_self_added_named 1)))

# --- 4. LES DEUX BRAS : AVANT FERME SUR UN TEST CASSE, APRES REFUSE EN LE NOMMANT. -----------
t_bras=0
[ -n "$(b before_commit)" ] && [ "$(b before_commit)" != "-" ] || faute temoin-avant-introuvable
t_bras=$((t_bras + $(eq before_marqueur_absent 1)))
t_bras=$((t_bras + $(eqs avant_casse_statut pass)))        # LE DEFAUT : il fermait
t_bras=$((t_bras + $(eq avant_casse_suite 0)))
t_bras=$((t_bras + $(eqs apres_casse_statut fail)))        # LE CORRECTIF : il refuse
t_bras=$((t_bras + $(eq apres_casse_suite 1)))
t_bras=$((t_bras + $(eq apres_casse_nomme_le_test 1)))     # et il NOMME le test casse
# LES CONTROLES A LAISSER : une porte qui refuse un vert ne vaut rien, des deux cotes.
t_bras=$((t_bras + $(eqs apres_vert_statut pass)))
t_bras=$((t_bras + $(eqs avant_vert_statut pass)))
t_bras=$((t_bras + $(eqs jg_vert_verdict pass)))
t_bras=$((t_bras + $(eqs jg_casse_verdict refuse)))
t_bras=$((t_bras + $(eq jg_casse_unwaived 1)))
t_bras=$((t_bras + $(eq jg_vert_unwaived 0)))

TOTAL=$((t_porte + t_cout + t_registre + t_bras + penalty))

# ========================================================================= la publication ====
pub sg_census_ran "$([ "$BANC_RC" = 0 ] && [ -s "$TMPD/banc.txt" ] && echo 1 || echo 0)"
pub suite_gate_defects "$TOTAL"
pub suite_gate_defects_terms \
  "porte$t_porte+cout$t_cout+registre$t_registre+bras$t_bras+penalite$penalty${why:+:$why}"
pub sg_porte "$t_porte"
pub sg_cout "$t_cout"
pub sg_registre "$t_registre"
pub sg_bras "$t_bras"
pub sg_witness_penalty "$penalty"
pub sg_banc_rc "$BANC_RC"
pub sg_juge_rc "$LIVE_RC"

# 1. LA SUITE LIVREE, TELLE QUE LA PORTE LA LIT. Les cles du juge sont recopiees TELLES QUELLES.
grep -E '^live_[a-z_]+=' "$TMPD/live.txt" 2>/dev/null | sed 's/^live_/suite_/'

# 1 bis. LE SOURCE : qui lit la suite, avant et maintenant.
for k in src_pytest_orch_avant src_pytest_orch_vivant src_suite_gate_appels \
         src_import_suite_gate src_marqueur_vivant src_marqueur_avant src_validators_pytest \
         src_reload_sites_orch src_reload_bruts_orch src_engine_dirty; do
  pub "sg_$k" "$(b "$k")"
done

# 2. LE COUT, ablate.
for k in jg_budget_haut_over jg_budget_haut_verdict jg_budget_bas_over jg_budget_bas_verdict \
         jg_budget_bas_secondes jg_plafond_timed_out jg_plafond_verdict jg_plafond_secondes; do
  pub "sg_$k" "$(b "$k")"
done

# 3 et 4. LES SIX SEMIS, chacun dans les deux bras, et ce que le juge en a dit.
for cas in vert casse dispense_ancienne dispense_propre ajout_non_nomme ajout_nomme; do
  pub "sg_avant_$cas" "$(b "avant_${cas}_statut")"
  pub "sg_apres_$cas" "$(b "apres_${cas}_statut")"
  pub "sg_apres_${cas}_suite" "$(b "apres_${cas}_suite")"
  pub "sg_jg_${cas}" "$(b "jg_${cas}_verdict")/$(b "jg_${cas}_unwaived")/$(b "jg_${cas}_self_added")/$(b "jg_${cas}_self_added_named")"
done
pub sg_apres_casse_nomme_le_test "$(b apres_casse_nomme_le_test)"
pub sg_apres_dispense_propre_dit_propre "$(b apres_dispense_propre_dit_propre)"
pub sg_apres_ajout_non_nomme_dit_non_nomme "$(b apres_ajout_non_nomme_dit_non_nomme)"
pub sg_before_commit "$(b before_commit)"
pub sg_banc_sha "$(b sha_lib_suite_gate_selftest_py)"
pub sg_juge_sha "$(b sha_lib_suite_gate_py)"
