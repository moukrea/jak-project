#!/usr/bin/env bash
# census/harness-close-gate-code-free.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course,
# sa sortie `cle=valeur` rejoignant celle du moteur dans le meme journal. Il n'ecrit aucun champ
# de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL MESURE, DANS L'ORDRE DES QUATRE POINTS DU LIVRABLE :
#   1. GATE 1 se prononce au LANCEMENT : un item dont le perimetre interdit le code recoit
#      `no_code` AVANT que l'essai brule, et le compte des lancements est publie   -> cf_lancement
#   2. aucun essai n'est plus refuse pour ce seul drapeau, deux bras sur les MEMES
#      items jetables : le bras d'AVANT refuse, le bras d'APRES passe               -> cf_porte
#   3. la promotion machine relit le VERDICT : la porte tenue sort, la porte refusee
#      reste, et les controles a LAISSER ne bougent pas                             -> cf_promotion
#   4. le nom de la fonction et ce qu'elle fait cessent de diverger                 -> cf_nom
#
# UNE SOURCE POUR LE VERDICT, LE BANC (`lib/close_gate_code_free_selftest.py`) : le VRAI
# `orchestrator.launch_item`, la VRAIE `orchestrator.close_gate` et la VRAIE
# `backlog.machine_proved_to_validated`, jouees sur des backlogs JETABLES ecrits et relus par le
# VRAI `lib/backlog.py`, dans un depot git jetable SANS un seul fichier moteur — la porte y est
# deterministe des deux cotes, ce qui les separe est la DECISION, pas l'etat de l'arbre de
# travail. Chaque mecanisme est joue par DEUX codes : celui du disque et celui d'AVANT ce
# chantier, ancre par MARQUEUR et jamais par `HEAD:`. Le commit retenu est publie.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte.
#
# CE QUI EST PUBLIE SANS ETRE COMPTE, ET POURQUOI. L'etalonnage du detecteur de perimetre sur le
# backlog LIVRE (233 items, 9 reconnus, 9 drapeaux, et ce sont les memes) : exiger un item mal
# etiquete pour fermer serait exiger une faute. Le journal des lancements de ce depot : il se
# remplit quand l'orchestrateur lance, pas quand le banc tourne. Et le plan de promotion du
# depot d'aujourd'hui : un zero s'y lit « rien a promouvoir », et le denominateur publie a cote
# dit que quelque chose a bien ete regarde. La non-vacuite vient du SEMIS, ou tout est FABRIQUE
# a chaque course par les vrais producteurs.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "cf_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

# LE MOISSONNEUR DE proof_run.sh NE GARDE QUE `^cle=valeur$` SANS ESPACE. Une valeur avec des
# espaces — la raison rendue par la porte — n'arriverait JAMAIS dans proof.txt : elle serait
# publiee pour personne. On colle donc les espaces ICI, au point de publication.
pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }

# ===================================================================== le banc, deux bras ===
BN=$(timeout 900 python3 "$AP/lib/close_gate_code_free_selftest.py" 2>/dev/null)
s(){ printf '%s\n' "$BN" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ==================================================================== les termes du verdict ==
penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }
eq(){ [ "$(n "$1")" = "$2" ] && echo 0 || echo 1; }
eqs(){ [ "$(s "$1")" = "$2" ] && echo 0 || echo 1; }

# Le banc doit AVOIR tourne, chaque bras doit avoir joue, et le temoin d'AVANT doit etre ancre
# par MARQUEUR — jamais par `HEAD:`, ou il s'accuserait lui-meme des le commit.
[ -n "$BN" ] || faute banc-muet
for bras in lc_apres lc_avant lp_apres lp_avant pm_apres pm_avant; do
  [ "$(n "${bras}_ran")" = 1 ] || faute "bras-$bras-muet"
done
[ "$(s before_orch_commit)" = "-" ] && faute temoin-avant-orchestrateur-absent
[ "$(s before_backlog_commit)" = "-" ] && faute temoin-avant-backlog-absent
[ "$(n before_orch_marker_absent)" = 1 ] || faute temoin-avant-orch-porte-le-marqueur
[ "$(n before_backlog_marker_absent)" = 1 ] || faute temoin-avant-backlog-porte-le-marqueur
[ "$(n before_orch_site_lancement)" = 1 ] || faute site-de-lancement-absent-du-blob-d-avant
[ "$(n marker_gate1_live)" = 1 ] || faute marqueur-gate1-absent-du-disque
[ "$(n marker_promo_live)" = 1 ] || faute marqueur-promotion-absent-du-disque

# --- 1. LE LANCEMENT : LE DRAPEAU EST POSE AVANT QUE L'ESSAI BRULE. -------------------------
t_lancement=0
t_lancement=$((t_lancement + $(eq lc_apres_a_launch_item 1)))
t_lancement=$((t_lancement + $(eq lc_apres_pose_sans 1)))       # le drapeau MANQUANT est pose
t_lancement=$((t_lancement + $(eq lc_apres_pose_avec 1)))       # celui deja pose ne bouge pas
# LE CONTROLE A LAISSER : un item dont le perimetre AUTORISE le code ne recoit RIEN. Sans lui,
# un `no_code` pose a tout le monde passerait cette porte et desarmerait GATE 1 partout.
t_lancement=$((t_lancement + $(eq lc_apres_pose_code 0)))
t_lancement=$((t_lancement + $(eqs lc_apres_statuts \
  "zzz-ccgf-lanc-sans:in-progress,zzz-ccgf-lanc-avec:in-progress,zzz-ccgf-lanc-code:in-progress")))
# LE COMPTE QUE LE LIVRABLE EXIGE : les lancements dont le perimetre interdit le code (2 sur 3
# semes), et ceux ou le drapeau a REELLEMENT ete pose ici (1).
t_lancement=$((t_lancement + $(eq lc_apres_journal_existe 1)))
t_lancement=$((t_lancement + $(eq lc_apres_journal_lignes 2)))
t_lancement=$((t_lancement + $(eq lc_apres_journal_poses 1)))
# LE BRAS D'AVANT : MEMES trois items semes, aucun drapeau pose, aucun journal.
t_lancement=$((t_lancement + $(eq lc_avant_a_launch_item 0)))
t_lancement=$((t_lancement + $(eq lc_avant_pose_sans 0)))       # LE DEFAUT, MESURE
t_lancement=$((t_lancement + $(eq lc_avant_pose_avec 1)))
t_lancement=$((t_lancement + $(eq lc_avant_pose_code 0)))
t_lancement=$((t_lancement + $(eq lc_avant_journal_lignes 0)))

# --- 2. LA PORTE : LE BRAS D'AVANT REFUSE, CELUI D'APRES PASSE, MEME ITEM. ------------------
t_porte=0
t_porte=$((t_porte + $(eqs lp_avant_sans_statut fail)))         # AVANT : l'essai brule
t_porte=$((t_porte + $(eq lp_avant_sans_code 1)))               # ... et c'est BIEN GATE 1
t_porte=$((t_porte + $(eqs lp_apres_sans_statut pass)))         # APRES : il passe
t_porte=$((t_porte + $(eq lp_apres_sans_code 0)))
# LE CONTROLE A LAISSER : un item dont le perimetre AUTORISE le code, et qui n'en livre aucun,
# est refuse DES DEUX COTES. GATE 1 mord toujours — on a leve un faux refus, pas la porte.
t_porte=$((t_porte + $(eqs lp_apres_code_statut fail)))
t_porte=$((t_porte + $(eq lp_apres_code_code 1)))
t_porte=$((t_porte + $(eqs lp_avant_code_statut fail)))
t_porte=$((t_porte + $(eq lp_avant_code_code 1)))
# ET LE DRAPEAU EXPLICITE DU SUPERVISEUR N'A PAS CHANGE DE SENS : il passe des deux cotes.
t_porte=$((t_porte + $(eqs lp_apres_drapeau_statut pass)))
t_porte=$((t_porte + $(eqs lp_avant_drapeau_statut pass)))

# --- 3. LA PROMOTION RELIT LE VERDICT. ------------------------------------------------------
t_promotion=0
t_promotion=$((t_promotion + $(eq pm_apres_a_plan 1)))
t_promotion=$((t_promotion + $(eq pm_apres_promus_n 1)))
t_promotion=$((t_promotion + $(eqs pm_apres_promus vert)))
t_promotion=$((t_promotion + $(eqs pm_apres_st_vert validated)))    # porte TENUE : il sort
t_promotion=$((t_promotion + $(eqs pm_apres_st_rouge to-test)))     # porte REFUSEE : il reste
t_promotion=$((t_promotion + $(eqs pm_apres_st_muet to-test)))      # AUCUN journal : il reste
# LE DERNIER verdict compte, pas « un vert quelque part » : vert PUIS rouge doit RESTER, et
# rouge PUIS vert doit SORTIR (c'est le semis de `vert`, qui porte deux journaux).
t_promotion=$((t_promotion + $(eqs pm_apres_st_regresse to-test)))
# LES DEUX CONTROLES A LAISSER : l'owner ferme lui-meme ce qu'il doit regarder, et on ne
# promeut que ce qui est PARQUE.
t_promotion=$((t_promotion + $(eqs pm_apres_st_owner to-test)))
t_promotion=$((t_promotion + $(eqs pm_apres_st_ouvert open)))
# CE QU'ELLE REFUSE EST NOMME : un `owner_test: false` qu'aucun chemin ne sortira doit se dire.
t_promotion=$((t_promotion + $(eqs pm_apres_refuses \
  "rouge:porte-refusee,muet:journal-absent,regresse:porte-refusee")))
# LE BRAS D'AVANT : MEME semis, il en promeut QUATRE — dont trois sans qu'aucune porte ait tenu.
t_promotion=$((t_promotion + $(eq pm_avant_a_plan 0)))
t_promotion=$((t_promotion + $(eq pm_avant_promus_n 4)))
t_promotion=$((t_promotion + $(eqs pm_avant_st_rouge validated)))   # LE DEFAUT, MESURE
t_promotion=$((t_promotion + $(eqs pm_avant_st_muet validated)))
t_promotion=$((t_promotion + $(eqs pm_avant_st_regresse validated)))
t_promotion=$((t_promotion + $(eqs pm_avant_st_owner to-test)))     # identique des deux cotes

# --- 4. LE NOM ET CE QU'ELLE FAIT. ----------------------------------------------------------
t_nom=0
t_nom=$((t_nom + $(eq nm_fonction_existe 1)))                  # le nom RESTE
t_nom=$((t_nom + $(eq nm_corps_lu 1)))
t_nom=$((t_nom + $(eq nm_docstring_promet_la_porte 1)))
t_nom=$((t_nom + $(eq nm_corps_appelle_le_plan 1)))            # ... et la fonction le tient
t_nom=$((t_nom + $(eq nm_corps_sans_garde_nue 1)))             # plus de `if not owner_test:` nu
t_nom=$((t_nom + $(eq src_gate1_lit_autorite 2)))              # UNE autorite, DEUX lecteurs
t_nom=$((t_nom + $(eq src_promotion_lit_verdict 1)))
t_nom=$((t_nom + $(eq src_boucle_appelle_launch 1)))
t_nom=$((t_nom + $(eq src_promotion_dit_ses_refus 1)))
t_nom=$((t_nom + $(eq src_marker_gate1_orch 1)))
t_nom=$((t_nom + $(eq src_marker_gate1_autorite 1)))
t_nom=$((t_nom + $(eq src_marker_promo_backlog 1)))
t_nom=$((t_nom + $(eq src_marker_promo_autorite 1)))

# --- HORS PERIMETRE : le jeu n'est pas touche. ----------------------------------------------
# LA PROPRETE DE L'ARBRE N'EST PLUS AFFIRMEE ICI (signalement 5 du 12/09, chantier
# harness-naming-authority-completion). Un recensement qui assert `git diff --quiet` ou
# `git status --porcelain` rougit pour TOUT chantier qui touche le fichier surveille,
# pour une raison qui n'est pas la sienne. C'est le travail des PORTES — GATE 0 refuse un
# arbre herite sale, GATE 1 lit `code_scope` — pas d'un instrument. La grandeur reste
# PUBLIEE plus bas : on retire l'affirmation, jamais la mesure.

TOTAL=$((t_lancement + t_porte + t_promotion + t_nom + penalty))

# ========================================================================= la publication ====
pub cf_census_ran "$([ -n "$BN" ] && echo 1 || echo 0)"
pub close_gate_code_free_defects "$TOTAL"
pub close_gate_code_free_defects_terms \
  "lancement$t_lancement+porte$t_porte+promotion$t_promotion+nom$t_nom+penalite$penalty${why:+:$why}"
pub cf_lancement "$t_lancement"
pub cf_porte "$t_porte"
pub cf_promotion "$t_promotion"
pub cf_nom "$t_nom"
pub cf_witness_penalty "$penalty"

# 1. LE LANCEMENT — le compte du livrable, et les deux bras cote a cote.
pub cf_launch_flag_posed_after "$(n lc_apres_pose_sans)"
pub cf_launch_flag_posed_before "$(n lc_avant_pose_sans)"
pub cf_launch_control_untouched_after "$(n lc_apres_pose_code)"
pub cf_launch_journal_lines "$(n lc_apres_journal_lignes)"
pub cf_launch_journal_posed "$(n lc_apres_journal_poses)"
pub cf_launch_flags_after "$(s lc_apres_drapeaux)"
pub cf_launch_flags_before "$(s lc_avant_drapeaux)"
pub cf_launch_has_launch_item_after "$(n lc_apres_a_launch_item)"
pub cf_launch_has_launch_item_before "$(n lc_avant_a_launch_item)"
# 2. LA PORTE — le statut rendu, par bras et par cas, et la raison recopiee telle quelle.
pub cf_gate_scopefree_after "$(s lp_apres_sans_statut)"
pub cf_gate_scopefree_before "$(s lp_avant_sans_statut)"
pub cf_gate_scopefree_reason_before "$(s lp_avant_sans_raison)"
pub cf_gate_needscode_after "$(s lp_apres_code_statut)"
pub cf_gate_needscode_before "$(s lp_avant_code_statut)"
pub cf_gate_flagged_after "$(s lp_apres_drapeau_statut)"
pub cf_gate_flagged_before "$(s lp_avant_drapeau_statut)"
# 3. LA PROMOTION — le plan, les promus, les refuses, et les statuts RELUS SUR LE DISQUE.
pub cf_promo_plan_after "$(s pm_apres_plan)"
pub cf_promo_promoted_after "$(n pm_apres_promus_n)"
pub cf_promo_promoted_before "$(n pm_avant_promus_n)"
pub cf_promo_promoted_list_after "$(s pm_apres_promus)"
pub cf_promo_promoted_list_before "$(s pm_avant_promus)"
pub cf_promo_refused_after "$(s pm_apres_refuses)"
pub cf_promo_states_after "$(s pm_apres_statuts)"
pub cf_promo_states_before "$(s pm_avant_statuts)"
# 4. LE NOM — la decision, dite.
pub cf_name_decision "$(s nm_decision)"
# 5. LES TEMOINS D'AVANT, par leur commit, et le hors-perimetre.
pub cf_before_orch_commit "$(s before_orch_commit)"
pub cf_before_backlog_commit "$(s before_backlog_commit)"
pub engine_dirty_files "$(n src_engine_dirty)"
pub engine_dirty_list "$(s src_engine_dirty_list)"
# 6. CE DEPOT, MAINTENANT — publie, JAMAIS compte : l'etalonnage du detecteur de perimetre.
pub cf_live_items "$(n live_items)"
pub cf_live_scope_forbids_code "$(n live_exige_sans_code)"
pub cf_live_scope_without_flag "$(n live_exige_sans_drapeau)"
pub cf_live_scope_without_flag_list "$(s live_exige_sans_drapeau_liste)"
pub cf_live_flag_without_scope "$(n live_drapeau_sans_raison)"
pub cf_live_flag_without_scope_list "$(s live_drapeau_sans_raison_liste)"
pub cf_live_launch_journal_lines "$(n live_journal_lancements)"
pub cf_live_parked "$(n live_parques)"
pub cf_live_plan "$(s live_plan)"
pub cf_live_promotable "$(n live_promouvables)"

# LES BRUTS, recopies tels quels : c'est ce qui rend la somme lisible et falsifiable. Sous un
# prefixe a eux — le moissonneur garde la DERNIERE valeur d'une cle, et un homonyme ecraserait
# un terme du verdict. Espaces colles, valeur vide rendue `-`.
brut(){ awk -v p="$1" -F= '/^[a-z_][a-z0-9_]*=/ {k=$1; sub(/^[^=]*=/,"",$0);
          gsub(/[[:space:]]+/,"_",$0); if($0=="") $0="-"; printf "%s%s=%s\n", p, k, $0}'; }
printf '%s\n' "$BN" | brut cf_bn_

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in orchestrator.py lib/backlog.py lib/gate_verdict.py \
         lib/close_gate_code_free_selftest.py \
         lib/census/harness-close-gate-code-free.sh validators/generic.sh; do
  k="cf_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
