#!/usr/bin/env bash
# census/harness-gate-verdict-must-outlive-its-log.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course,
# sa sortie `cle=valeur` rejoignant celle du moteur dans le meme journal. Il n'ecrit aucun champ
# de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL MESURE, DANS L'ORDRE DES QUATRE POINTS DU LIVRABLE :
#   1. la porte ECRIT son verdict DANS L'ITEM quand elle le prononce — resultat, date,
#      empreinte des OCTETS de la preuve jugee                                  -> vd_ecriture
#   2. la promotion lit ce champ EN PREMIER, le journal n'est qu'un REPLI : les
#      journaux EFFACES, le bras d'AVANT ne promeut rien, celui d'APRES promeut -> vd_purge
#   3. le perimetre n'est plus devine dans une phrase : un CHAMP fait foi, la
#      prose est un repli, et chaque repli est COMPTE                           -> vd_perimetre
#   4. les quatre termes du chantier precedent gardent leurs valeurs, bancs
#      semes compris — REJOUES, jamais relus dans une table perimee             -> vd_regression
#
# UNE SOURCE POUR LES TROIS PREMIERS, LE BANC (`lib/gate_verdict_durability_selftest.py`) : le
# VRAI `orchestrator.pronounce_gate`, la VRAIE `backlog.machine_proved_to_validated` et la VRAIE
# `gate_verdict.scope_decision`, joues sur des backlogs JETABLES ecrits et relus par le VRAI
# `lib/backlog.py`. Chaque mecanisme est joue par DEUX codes : celui du disque et celui d'AVANT ce
# chantier, ancre par MARQUEUR et jamais par `HEAD:`. Le commit retenu est publie.
#
# LE QUATRIEME TERME REJOUE LE RECENSEMENT PRECEDENT, `lib/census/harness-close-gate-code-free.sh`.
# Relire son `proof.txt` serait lire une table que rien ne regenere : ses quatre termes sont
# RECALCULES ici, semis compris, sur le code de ce disque.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte.
#
# CE QUI EST PUBLIE SANS ETRE COMPTE, ET POURQUOI. L'etat du backlog LIVRE : aucun de ses deux
# items parques ne porte encore le champ — ils ont ete parques AVANT ce chantier, et fabriquer
# leur verdict a leur place serait exactement le faux vert que tout ceci refuse. Le compte le DIT
# (`vd_live_verdict_absents`), et le repli sur le journal les sert encore. De meme pour le
# perimetre : 12 items du backlog ne disent le leur que dans une phrase ; leur liste est publiee,
# leur correction n'est pas une condition de fermeture de CET item. La non-vacuite vient du
# SEMIS, ou tout est FABRIQUE a chaque course par les vrais producteurs.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "vd_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

# LE MOISSONNEUR DE proof_run.sh NE GARDE QUE `^cle=valeur$` SANS ESPACE. Une valeur avec des
# espaces ne serait JAMAIS publiee : on colle donc les espaces ICI, au point de publication.
pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }

# ===================================================================== le banc, deux bras ===
BN=$(timeout 600 python3 "$AP/lib/gate_verdict_durability_selftest.py" 2>/dev/null)
s(){ printf '%s\n' "$BN" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ============================ le BANC du chantier precedent, une fois, sans rejouer sa porte =
# LA CHAINE DE REJEUX EST COUPEE (signalement 10 du 12/09). Ce terme lancait
# `census/harness-close-gate-code-free.sh`, qui lance lui-meme son banc : un recensement qui
# rejoue un recensement qui rejoue un banc finit par mesurer le temps de la machine plutot que
# le defaut, et il RE-JUGE un item dont le verdict n'est pas son affaire. On interroge
# maintenant le banc DIRECTEMENT — meme profondeur que n'importe quel autre recensement — et on
# ne lit que les TEMOINS BRUTS que ce chantier-ci pourrait casser. Les agregats du chantier
# precedent (`close_gate_code_free_defects`, `cf_lancement`, `cf_porte`, `cf_promotion`,
# `cf_nom`) restent le travail de SA porte, pas de celle-ci.
PREV_T0=$(date +%s)
PREV=$(timeout 600 python3 "$AP/lib/close_gate_code_free_selftest.py" 2>/dev/null)
PREV_S=$(( $(date +%s) - PREV_T0 ))
q(){ printf '%s\n' "$PREV" | sed -n "s/^$1=//p" | tail -1; }
qn(){ local v; v=$(q "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ==================================================================== les termes du verdict ==
penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }
eq(){ [ "$(n "$1")" = "$2" ] && echo 0 || echo 1; }
eqs(){ [ "$(s "$1")" = "$2" ] && echo 0 || echo 1; }
eqq(){ [ "$(qn "$1")" = "$2" ] && echo 0 || echo 1; }

# Le banc doit AVOIR tourne, chaque bras doit avoir joue, et les temoins d'AVANT doivent etre
# ancres par MARQUEUR — jamais par `HEAD:`, ou ils s'accuseraient eux-memes des le commit.
[ -n "$BN" ] || faute banc-muet
[ -n "$PREV" ] || faute banc-precedent-muet
for bras in ec_apres ec_avant pu_apres_avec pu_apres_purge pu_avant_avec pu_avant_purge \
            sc_apres sc_avant rl; do
  [ "$(n "${bras}_ran")" = 1 ] || faute "bras-$bras-muet"
done
[ "$(s before_orch_commit)" = "-" ] && faute temoin-avant-orchestrateur-absent
[ "$(s before_backlog_commit)" = "-" ] && faute temoin-avant-backlog-absent
[ "$(s before_gate_verdict_commit)" = "-" ] && faute temoin-avant-autorite-absent
[ "$(n before_orch_marker_absent)" = 1 ] || faute temoin-avant-orch-porte-le-marqueur
[ "$(n before_backlog_marker_absent)" = 1 ] || faute temoin-avant-backlog-porte-le-marqueur
[ "$(n before_gv_marker_absent)" = 1 ] || faute temoin-avant-autorite-porte-le-marqueur
[ "$(n before_orch_site_fermeture)" = 1 ] || faute site-de-fermeture-absent-du-blob-d-avant
[ "$(n marker_verdict_live)" = 1 ] || faute marqueur-verdict-absent-du-disque
[ "$(n marker_scope_live)" = 1 ] || faute marqueur-perimetre-absent-du-disque

# --- 1. L'ECRITURE : LE VERDICT EST DANS L'ITEM, PAS DANS UN JOURNAL. -----------------------
t_ecriture=0
t_ecriture=$((t_ecriture + $(eq ec_apres_a_pronounce 1)))
t_ecriture=$((t_ecriture + $(eq ec_apres_champ 1)))
t_ecriture=$((t_ecriture + $(eqs ec_apres_result porte-tenue)))
t_ecriture=$((t_ecriture + $(eqs ec_apres_date "$(date +%F)")))
# L'EMPREINTE EST CELLE DES OCTETS SEMES, recalculee par le banc : un chemin n'est pas une
# provenance, et un sha recopie ne prouverait que la recopie.
t_ecriture=$((t_ecriture + $(eq ec_apres_sha_concorde 1)))
t_ecriture=$((t_ecriture + $([ "$(n ec_apres_octets)" = "$(n ec_apres_octets_attendus)" ] && echo 0 || echo 1)))
t_ecriture=$((t_ecriture + $(eq ec_apres_essai 7)))
t_ecriture=$((t_ecriture + $(eqs ec_apres_journal validator-007.txt)))
t_ecriture=$((t_ecriture + $(eqs ec_apres_statut to-test)))
# LE CHAMP QUE LA PORTE POSAIT DEJA N'EST PAS PERDU : `delivered` fait voir l'item a l'owner.
t_ecriture=$((t_ecriture + $(eqs ec_apres_delivered 2026-09-12)))
# LES DEUX CONTROLES A LAISSER : un item qu'on n'a PAS prononce n'obtient rien, et un prononce
# SANS preuve sur le disque NOMME l'absence au lieu de fabriquer un sha.
t_ecriture=$((t_ecriture + $(eq ec_apres_temoin_sans_champ 1)))
t_ecriture=$((t_ecriture + $(eqs ec_apres_sans_preuve_sha -)))
t_ecriture=$((t_ecriture + $(eq ec_apres_sans_preuve_octets -1)))
# ET IL SE RELIT PAR L'AUTORITE, source `item`.
t_ecriture=$((t_ecriture + $(eqs ec_apres_relu_source item)))
t_ecriture=$((t_ecriture + $(eq ec_apres_relu_vert 1)))
# LE BRAS D'AVANT : MEME semis, meme statut, meme `delivered` — et AUCUNE trace du verdict.
t_ecriture=$((t_ecriture + $(eq ec_avant_a_pronounce 0)))
t_ecriture=$((t_ecriture + $(eq ec_avant_champ 0)))              # LE DEFAUT, MESURE
t_ecriture=$((t_ecriture + $(eqs ec_avant_statut to-test)))
t_ecriture=$((t_ecriture + $(eqs ec_avant_delivered 2026-09-12)))
# LA PORTE PRONONCE A SES DEUX SORTIES VERTES, et plus une seule ne pose le statut nu.
t_ecriture=$((t_ecriture + $(eq src_orch_prononce 2)))
t_ecriture=$((t_ecriture + $(eq src_orch_to_test_nu 0)))
t_ecriture=$((t_ecriture + $(eq src_orch_valide_nu 0)))

# --- 2. LA PURGE : LE STIMULUS EST L'EFFACEMENT DES JOURNAUX. -------------------------------
t_purge=0
# LE STIMULUS SE MESURE : quatre journaux avant, ZERO fichier apres, dans les deux bras.
t_purge=$((t_purge + $(eq pu_apres_avec_logs_restants 4)))
t_purge=$((t_purge + $(eq pu_apres_purge_logs_restants 0)))
t_purge=$((t_purge + $(eq pu_avant_avec_logs_restants 4)))
t_purge=$((t_purge + $(eq pu_avant_purge_logs_restants 0)))
# JOURNAUX EFFACES — LA CELLULE QUI DECIDE DE TOUT.
t_purge=$((t_purge + $(eq pu_avant_purge_promus_n 0)))            # LE DEFAUT, MESURE
t_purge=$((t_purge + $(eqs pu_avant_purge_promus -)))
t_purge=$((t_purge + $(eq pu_apres_purge_promus_n 1)))
t_purge=$((t_purge + $(eqs pu_apres_purge_promus vert)))
t_purge=$((t_purge + $(eqs pu_apres_purge_st_vert validated)))
t_purge=$((t_purge + $(eqs pu_apres_purge_st_rouge to-test)))     # champ ROUGE : il reste
t_purge=$((t_purge + $(eqs pu_apres_purge_st_journal to-test)))   # repli impossible : il reste
t_purge=$((t_purge + $(eqs pu_apres_purge_st_owner to-test)))     # l'owner ferme le sien
t_purge=$((t_purge + $(eqs pu_apres_purge_st_rien to-test)))      # ni champ ni journal : il reste
# JOURNAUX PRESENTS — LE REPLI MARCHE ENCORE, ET LE CHAMP PASSE DEVANT LUI.
t_purge=$((t_purge + $(eq pu_apres_avec_promus_n 2)))
t_purge=$((t_purge + $(eqs pu_apres_avec_promus vert,journal)))
t_purge=$((t_purge + $(eqs pu_apres_avec_st_rouge to-test)))      # journal VERT, champ ROUGE
t_purge=$((t_purge + $(eqs pu_apres_avec_st_journal validated)))  # aucun champ : le repli sert
t_purge=$((t_purge + $(eq pu_apres_avec_replis 2)))
t_purge=$((t_purge + $(eqs pu_apres_avec_sources vert:item,rouge:item,journal:journal,owner:item,rien:journal)))
t_purge=$((t_purge + $(eqs pu_apres_purge_sources vert:item,rouge:item,journal:journal,owner:item,rien:journal)))
# LE BRAS D'AVANT, JOURNAUX PRESENTS : il en promeut TROIS — dont `rouge`, dont le champ dit
# que la porte a ete REFUSEE et qu'il ne sait pas lire.
t_purge=$((t_purge + $(eq pu_avant_avec_promus_n 3)))
t_purge=$((t_purge + $(eqs pu_avant_avec_promus vert,rouge,journal)))
t_purge=$((t_purge + $(eqs pu_avant_avec_st_rouge validated)))    # LE DEFAUT, MESURE
t_purge=$((t_purge + $(eq pu_avant_avec_replis -1)))              # non mesure de ce cote
# ET L'AUTORITE VOYAGE AVEC `backlog.py` : rechargee a chaque tour, elle ne peut plus etre d'un
# millesime plus vieux que le code qui l'appelle. Le bras d'AVANT tient l'autorite PERIMEE — sans
# `verdict_from_item` —, et la promotion machine se serait arretee EN SILENCE dans une boucle
# deja en vol. Le controle de non-vacuite : l'autorite emulee n'a VRAIMENT pas la fonction neuve.
t_purge=$((t_purge + $(eq rl_perimee_a_le_champ 0)))
t_purge=$((t_purge + $(eq rl_avant_autorite_fraiche 0)))          # LE DEFAUT, MESURE
t_purge=$((t_purge + $(eq rl_apres_autorite_fraiche 1)))
t_purge=$((t_purge + $(eq rl_apres_promus_n 1)))                  # et ca promeut pour de vrai
t_purge=$((t_purge + $(eqs rl_apres_promus vert)))
t_purge=$((t_purge + $(eq src_backlog_reloads_authority 1)))
# L'ORDRE DE LECTURE SE LIT DANS LE SOURCE : le champ d'abord, le journal en repli, UNE FOIS.
t_purge=$((t_purge + $(eq src_plan_lu 1)))
t_purge=$((t_purge + $(eq src_plan_lit_le_champ 1)))
t_purge=$((t_purge + $(eq src_plan_lit_le_journal 1)))
t_purge=$((t_purge + $(eq src_champ_avant_journal 1)))

# --- 3. LE PERIMETRE : UN CHAMP FAIT FOI, LA PROSE EST UN REPLI COMPTE. ---------------------
t_perimetre=0
t_perimetre=$((t_perimetre + $(eq sc_apres_a_decision 1)))
# `champengine` et `conflit` sont les DEUX controles qui font le chantier : la prose dit
# « aucun code », le drapeau aussi, et le CHAMP dit le contraire — c'est le champ qui gagne.
t_perimetre=$((t_perimetre + $(eqs sc_apres_decisions \
  "champnone:1,champengine:0,drapeau:1,prose:1,neuve:0,conflit:0")))
t_perimetre=$((t_perimetre + $(eqs sc_apres_sources \
  "champnone:champ-explicite,champengine:champ-explicite,drapeau:drapeau-no_code,prose:prose-devinee,neuve:perimetre-muet,conflit:champ-explicite")))
# LE BRAS D'AVANT : le champ n'existe pas pour lui. `champnone` se fait refuser du code qu'il
# n'a pas le droit d'ecrire, `champengine` et `conflit` sont declares sans code contre leur
# champ. Trois decisions retournees, MESUREES.
t_perimetre=$((t_perimetre + $(eq sc_avant_a_decision 0)))
t_perimetre=$((t_perimetre + $(eqs sc_avant_decisions \
  "champnone:0,champengine:1,drapeau:1,prose:1,neuve:0,conflit:1")))
# ET LE REPLI EST COMPTE SUR LE DEPOT LIVRE : la liste des items devines existe et n'est pas vide
# — un compte a zero ici voudrait dire que le recensement ne regarde rien.
t_perimetre=$((t_perimetre + $([ "$(n live_scope_devine)" -gt 0 ] 2>/dev/null && echo 0 || echo 1)))
t_perimetre=$((t_perimetre + $([ "$(s live_scope_devine_liste)" = "-" ] && echo 1 || echo 0)))
t_perimetre=$((t_perimetre + $([ "$(n live_items)" -gt 0 ] 2>/dev/null && echo 0 || echo 1)))
t_perimetre=$((t_perimetre + $(eq live_scope_illisible 0)))

# --- 4. LA NON-REGRESSION DU CHANTIER PRECEDENT, SUR SES TEMOINS BRUTS. ---------------------
# Les cles lues ici sont celles du BANC (`lc_apres_*`, `pm_apres_*`), pas les agregats que son
# recensement en tire : on ne recopie pas sa porte, on ne la rejoue pas, et on ne se met pas a
# dependre de son arithmetique.
t_regression=0
t_regression=$((t_regression + $(eqq lc_apres_ran 1)))
t_regression=$((t_regression + $(eqq pm_apres_ran 1)))
# SES BANCS SEMES ONT BIEN TOURNE : le compte d'items promus par sa propre promotion, et la
# liste de ce qu'elle a refuse, mot pour mot.
t_regression=$((t_regression + $(eqq pm_apres_promus_n 1)))
t_regression=$((t_regression + $([ "$(q pm_apres_refuses)" = \
  "rouge:porte-refusee,muet:journal-absent,regresse:porte-refusee" ] && echo 0 || echo 1)))
t_regression=$((t_regression + $(eqq lc_apres_journal_lignes 2)))
t_regression=$((t_regression + $(eqq lc_apres_journal_poses 1)))

# --- HORS PERIMETRE : le jeu n'est pas touche. ----------------------------------------------
# LA PROPRETE DE L'ARBRE N'EST PLUS AFFIRMEE ICI (signalement 5 du 12/09, chantier
# harness-naming-authority-completion). Un recensement qui assert `git diff --quiet` ou
# `git status --porcelain` rougit pour TOUT chantier qui touche le fichier surveille,
# pour une raison qui n'est pas la sienne. C'est le travail des PORTES — GATE 0 refuse un
# arbre herite sale, GATE 1 lit `code_scope` — pas d'un instrument. La grandeur reste
# PUBLIEE plus bas : on retire l'affirmation, jamais la mesure.

TOTAL=$((t_ecriture + t_purge + t_perimetre + t_regression + penalty))

# ========================================================================= la publication ====
pub vd_census_ran "$([ -n "$BN" ] && echo 1 || echo 0)"
pub verdict_durability_defects "$TOTAL"
pub verdict_durability_defects_terms \
  "ecriture$t_ecriture+purge$t_purge+perimetre$t_perimetre+regression$t_regression+penalite$penalty${why:+:$why}"
pub vd_ecriture "$t_ecriture"
pub vd_purge "$t_purge"
pub vd_perimetre "$t_perimetre"
pub vd_regression "$t_regression"
pub vd_witness_penalty "$penalty"

# 1. L'ECRITURE — ce que la porte a laisse dans l'item, et ce qu'elle n'y laissait pas.
pub vd_write_field_after "$(n ec_apres_champ)"
pub vd_write_field_before "$(n ec_avant_champ)"
pub vd_write_result_after "$(s ec_apres_result)"
pub vd_write_date_after "$(s ec_apres_date)"
pub vd_write_proof_sha_after "$(s ec_apres_sha)"
pub vd_write_proof_sha_expected "$(s ec_apres_sha_attendu)"
pub vd_write_proof_bytes_after "$(n ec_apres_octets)"
pub vd_write_no_proof_sha "$(s ec_apres_sans_preuve_sha)"
pub vd_write_no_proof_bytes "$(n ec_apres_sans_preuve_octets)"
pub vd_write_control_untouched "$(n ec_apres_temoin_sans_champ)"
pub vd_write_reread_source "$(s ec_apres_relu_source)"
pub vd_write_orch_pronounce_sites "$(n src_orch_prononce)"
pub vd_write_orch_bare_sites "$(( $(n src_orch_to_test_nu) + $(n src_orch_valide_nu) ))"
# 2. LA PURGE — les quatre cellules, cote a cote, et le stimulus mesure.
pub vd_purge_logs_before_after "$(n pu_apres_avec_logs_restants)"
pub vd_purge_logs_after_purge "$(n pu_apres_purge_logs_restants)"
pub vd_purge_promoted_after_withlogs "$(n pu_apres_avec_promus_n)"
pub vd_purge_promoted_after_purged "$(n pu_apres_purge_promus_n)"
pub vd_purge_promoted_before_withlogs "$(n pu_avant_avec_promus_n)"
pub vd_purge_promoted_before_purged "$(n pu_avant_purge_promus_n)"
pub vd_purge_list_after_purged "$(s pu_apres_purge_promus)"
pub vd_purge_list_before_purged "$(s pu_avant_purge_promus)"
pub vd_purge_plan_after_purged "$(s pu_apres_purge_plan)"
pub vd_purge_plan_before_purged "$(s pu_avant_purge_plan)"
pub vd_purge_sources_after_purged "$(s pu_apres_purge_sources)"
pub vd_purge_fallbacks_after_purged "$(n pu_apres_purge_replis)"
pub vd_purge_states_after_purged "$(s pu_apres_purge_st_vert),$(s pu_apres_purge_st_rouge),$(s pu_apres_purge_st_journal),$(s pu_apres_purge_st_owner),$(s pu_apres_purge_st_rien)"
pub vd_reload_stale_has_field "$(n rl_perimee_a_le_champ)"
pub vd_reload_authority_fresh_before "$(n rl_avant_autorite_fraiche)"
pub vd_reload_authority_fresh_after "$(n rl_apres_autorite_fraiche)"
pub vd_reload_promoted_after "$(n rl_apres_promus_n)"
pub vd_purge_states_before_purged "$(s pu_avant_purge_st_vert),$(s pu_avant_purge_st_rouge),$(s pu_avant_purge_st_journal),$(s pu_avant_purge_st_owner),$(s pu_avant_purge_st_rien)"
# 3. LE PERIMETRE — la decision et sa SOURCE, par bras.
pub vd_scope_decisions_after "$(s sc_apres_decisions)"
pub vd_scope_decisions_before "$(s sc_avant_decisions)"
pub vd_scope_sources_after "$(s sc_apres_sources)"
# 4. LES QUATRE TERMES DU CHANTIER PRECEDENT, REJOUES.
# LA PROFONDEUR DE REJEU, PUBLIEE : 1 = ce recensement appelle un banc, comme tous les autres.
# 2 voudrait dire qu'il rejoue la porte d'un autre item, et c'est ce qu'on vient de retirer.
pub vd_prev_rejeux_profondeur 1
pub vd_prev_banc_secondes "$PREV_S"
pub vd_prev_lancement_ran "$(qn lc_apres_ran)"
pub vd_prev_promotion_ran "$(qn pm_apres_ran)"
pub vd_prev_journal_lignes "$(qn lc_apres_journal_lignes)"
pub vd_prev_journal_poses "$(qn lc_apres_journal_poses)"
pub vd_prev_promo_refused "$(q pm_apres_refuses)"
pub vd_prev_promo_promoted "$(qn pm_apres_promus_n)"
# 5. LES TEMOINS D'AVANT, par leur commit, et le hors-perimetre.
pub vd_before_orch_commit "$(s before_orch_commit)"
pub vd_before_backlog_commit "$(s before_backlog_commit)"
pub vd_before_authority_commit "$(s before_gate_verdict_commit)"
pub engine_dirty_files "$(n src_engine_dirty)"
pub engine_dirty_list "$(s src_engine_dirty_list)"
# 6. CE DEPOT, MAINTENANT — publie, JAMAIS compte (voir l'en-tete).
pub vd_live_items "$(n live_items)"
pub vd_live_parked "$(n live_parques)"
pub vd_live_verdict_carriers "$(n live_verdict_porteurs)"
pub vd_live_verdict_carriers_list "$(s live_verdict_porteurs_liste)"
pub vd_live_verdict_absent "$(n live_verdict_absents)"
pub vd_live_verdict_absent_list "$(s live_verdict_absents_liste)"
pub vd_live_verdict_unreadable "$(n live_verdict_illisibles)"
pub vd_live_promotable "$(n live_promouvables)"
pub vd_live_journal_fallbacks "$(n live_replis_journal)"
pub vd_live_plan "$(s live_plan)"
pub vd_live_scope_explicit "$(n live_scope_explicite)"
pub vd_live_scope_guessed "$(n live_scope_devine)"
pub vd_live_scope_guessed_list "$(s live_scope_devine_liste)"
pub vd_live_scope_silent "$(n live_scope_muet)"
pub vd_live_scope_unreadable "$(n live_scope_illisible)"
pub vd_live_scope_flags "$(n live_scope_drapeaux)"

# LES BRUTS, recopies tels quels : c'est ce qui rend la somme lisible et falsifiable. Sous un
# prefixe a eux — le moissonneur garde la DERNIERE valeur d'une cle, et un homonyme ecraserait
# un terme du verdict. Espaces colles, valeur vide rendue `-`.
brut(){ awk -v p="$1" -F= '/^[a-z_][a-z0-9_]*=/ {k=$1; sub(/^[^=]*=/,"",$0);
          gsub(/[[:space:]]+/,"_",$0); if($0=="") $0="-"; printf "%s%s=%s\n", p, k, $0}'; }
printf '%s\n' "$BN" | brut vd_bn_

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in orchestrator.py lib/backlog.py lib/gate_verdict.py \
         lib/gate_verdict_durability_selftest.py \
         lib/census/harness-gate-verdict-must-outlive-its-log.sh validators/generic.sh; do
  k="vd_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
