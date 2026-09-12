#!/usr/bin/env bash
# census/harness-reload-must-not-kill-the-loop.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course,
# sa sortie `cle=valeur` rejoignant celle du moteur dans le meme journal. Il n'ecrit aucun champ
# de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL MESURE, DANS L'ORDRE DES QUATRE POINTS DU LIVRABLE :
#   1. un rechargement qui ECHOUE ne tue plus la boucle : le module deja charge est conserve
#      PAR SON CONTENU, l'echec est nomme (fichier, ligne, exception), le tour continue,
#      et les deux comptes demandes sont publies                              -> rs_survie
#   2. l'etat degrade est DIT, pas subi : le journal le repete a chaque tour et le texte
#      rendu a l'owner le porte, tant que ca dure — et se tait des que ca passe -> rs_dit
#   3. deux bras sur une COPIE JETABLE, stimulus = un VRAI fichier incoherent : le bras
#      d'AVANT meurt, celui d'APRES tourne                                    -> rs_bras
#   4. le meme filet couvre les QUATRE rechargements, aucun n'a ete retire    -> rs_sites
#
# UNE SEULE SOURCE, LE BANC (`lib/reload_survival_selftest.py`) : six jambes, chacune un
# PROCESSUS a part — « la boucle est morte » ne se lit honnetement que dans un code de retour.
# Le code d'AVANT est ancre par MARQUEUR (`RECHARGEMENT/filet`), jamais par `HEAD:`, et
# `lib/safe_reload.py` est ABSENT de ce bras : la couche n'est pas desarmee, elle n'est pas la.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte.
#
# CE QUI EST PUBLIE SANS ETRE COMPTE, ET POURQUOI. `avant_casse_prompt` : casser
# `directives.py` et `preflight.py` ne TUAIT deja pas la boucle — ces deux sites etaient sous
# `try/except`. Ce que le bras d'AVANT y perd n'est pas la survie, c'est le CONTENU : le prompt
# du worker tombe de 5124 a 4695 octets, sans un mot a personne. Ce delta-la est COMPTE dans
# `rs_survie` et `rs_dit` ; la survie de cette jambe-la ne l'est pas, parce qu'elle n'a jamais
# ete le defaut. Le dire vaut mieux que de fabriquer un rouge qui n'a pas eu lieu.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "rs_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

# LE MOISSONNEUR DE proof_run.sh NE GARDE QUE `^cle=valeur$` SANS ESPACE. Une valeur avec des
# espaces ne serait JAMAIS publiee : on colle donc les espaces ICI, au point de publication.
pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }

# ======================================================================= le banc, six jambes ==
BN=$(timeout 900 python3 "$AP/lib/reload_survival_selftest.py" 2>/dev/null)
s(){ printf '%s\n' "$BN" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }
eq(){ [ "$(n "$1")" = "$2" ] && echo 0 || echo 1; }
eqs(){ [ "$(s "$1")" = "$2" ] && echo 0 || echo 1; }
ne(){ [ "$(n "$1")" != "$2" ] && echo 0 || echo 1; }

[ -n "$BN" ] || faute banc-muet
[ "$(n banc_ran)" = 1 ] || faute banc-n-a-pas-tourne
# LES SIX JAMBES ONT LANCE DES TOURS. Une jambe muette est un defaut, pas une absence.
for j in avant_nu avant_casse avant_casse_backlog avant_casse_prompt apres_nu apres_casse; do
  [ "$(n "${j}_tours_lances")" -ge 1 ] 2>/dev/null || faute "jambe-$j-muette"
done

# --- 1. LA SURVIE : UN RECHARGEMENT REFUSE NE TUE PLUS LA BOUCLE. ---------------------------
t_survie=0
# LE BRAS D'APRES : sept tours lances, sept tours ABOUTIS, sortie propre.
t_survie=$((t_survie + $(eq apres_casse_rc 0)))
t_survie=$((t_survie + $(eq apres_casse_survecu 1)))
t_survie=$((t_survie + $(eq apres_casse_tours_lances 7)))
t_survie=$((t_survie + $(eq apres_casse_tours_aboutis 7)))
t_survie=$((t_survie + $(eq apres_casse_mort_au_tour 0)))
# LES DEUX COMPTES QUE LE LIVRABLE DEMANDE, publies SEPAREMENT : rechargements REFUSES, et
# tours POURSUIVIS malgre eux. Cinq refus (deux sur l'autorite, un sur le backlog, deux sur
# les modules du prompt) etales sur quatre tours degrades.
t_survie=$((t_survie + $(eq apres_casse_refus 5)))
t_survie=$((t_survie + $(eq apres_casse_compteur_refus 5)))
t_survie=$((t_survie + $(eq apres_casse_compteur_tours 4)))
# LE DEFAUT, MESURE — la panne du 12/09 rejouee a l'octet : le bras d'AVANT MEURT au tour 2,
# sur l'`AttributeError` que `impossible` levait a 15:33.
t_survie=$((t_survie + $(ne avant_casse_rc 0)))
t_survie=$((t_survie + $(eq avant_casse_survecu 0)))
t_survie=$((t_survie + $(eq avant_casse_tours_aboutis 0)))
t_survie=$((t_survie + $(eq avant_casse_mort_au_tour 2)))
t_survie=$((t_survie + $(eqs avant_casse_exc AttributeError)))
# ET LE SECOND SITE DE PRODUCTION, `orchestrator:backlog` : un `lib/backlog.py` tronque tuait
# la boucle aussi. Le bras d'AVANT y meurt en `SyntaxError`.
t_survie=$((t_survie + $(ne avant_casse_backlog_rc 0)))
t_survie=$((t_survie + $(eq avant_casse_backlog_survecu 0)))
t_survie=$((t_survie + $(eqs avant_casse_backlog_exc SyntaxError)))
# LE CONTROLE DE CAUSALITE. Sans lui, la mort du bras d'AVANT pourrait venir du bac a sable :
# le MEME code d'avant, dans le MEME bac, SANS stimulus, fait ses sept tours.
t_survie=$((t_survie + $(eq avant_nu_rc 0)))
t_survie=$((t_survie + $(eq avant_nu_tours_aboutis 7)))
t_survie=$((t_survie + $(eq avant_nu_refus 0)))
# LE MODULE EST CONSERVE PAR SON CONTENU, PAS PAR SON NOM. Un rechargement NU execute le code
# neuf DANS le `__dict__` existant : le cobaye en ressort avec A=99 (neuf) et B,C,D d'avant —
# mi-neuf, mi-vieux, irrecuperable. Repasse par le filet, le MEME fichier casse le laisse a 1.
t_survie=$((t_survie + $(eq photo_nu_A 99)))                    # LE DEFAUT, MESURE
t_survie=$((t_survie + $(eqs photo_nu_exc AttributeError)))
t_survie=$((t_survie + $(eq photo_filet_A 1)))
t_survie=$((t_survie + $(eq photo_filet_rendu 0)))
t_survie=$((t_survie + $(eq photo_filet_dans_sys_modules 1)))
t_survie=$((t_survie + $(eq photo_filet_reprise 1)))
t_survie=$((t_survie + $(eq photo_filet_degrade_final 0)))
# ET LE BANC N'ECRIT PAS DANS L'ETAT DE PRODUCTION : il pose son propre fichier, et celui du
# depot ressort octet pour octet comme il etait. Un instrument qui annonce a l'owner un harnais
# degrade parce qu'un banc a tourne serait un faux vert a l'envers.
t_survie=$((t_survie + $(eq photo_etat_du_banc_ecrit 1)))
t_survie=$((t_survie + $(eq photo_etat_production_intact 1)))
# LA MEME CHOSE AU NIVEAU PRODUCTION : `directives`/`preflight` casses, le bras d'AVANT rend au
# worker un prompt AMPUTE de 429 octets ; celui d'APRES rend les 5124 octets a chaque tour.
t_survie=$((t_survie + $(eqs avant_casse_prompt_prompt_par_tour 5124,4695,4695,5124,5124,5124,5124)))
t_survie=$((t_survie + $(eqs apres_casse_prompt_par_tour 5124,5124,5124,5124,5124,5124,5124)))
t_survie=$((t_survie + $(eq avant_casse_prompt_directives_indispo 2)))
t_survie=$((t_survie + $(eq apres_casse_directives_indispo 0)))
t_survie=$((t_survie + $(eq apres_casse_preflight_indispo 0)))
# ET LE TRAVAIL DU TOUR N'EST PAS PERDU : le backlog est relu, 2 items, a chaque tour.
t_survie=$((t_survie + $(eqs apres_casse_items_par_tour 2,2,2,2,2,2,2)))
t_survie=$((t_survie + $(eqs apres_casse_attrs_par_tour 42,42,42,42,42,42,42)))
t_survie=$((t_survie + $(eqs apres_casse_proof_file_par_tour proof.txt,proof.txt,proof.txt,proof.txt,proof.txt,proof.txt,proof.txt)))

# --- 2. L'ETAT DEGRADE EST DIT, PAS SUBI. --------------------------------------------------
t_dit=0
# LE JOURNAL LE REPETE A CHAQUE TOUR DEGRADE — quatre tours, quatre repetitions.
t_dit=$((t_dit + $(eq apres_casse_journal_tours 4)))
# LE TEXTE RENDU A L'OWNER LE PORTE, ET SEULEMENT TANT QUE CA DURE. La forme par tour est
# publiee : c'est elle qui interdit un bloc colle en permanence.
t_dit=$((t_dit + $(eq apres_casse_owner_tours 4)))
t_dit=$((t_dit + $(eqs apres_casse_owner_par_tour 0,1,1,1,1,0,0)))
# ET CA SE REFERME : quatre reprises annoncees, plus un seul site degrade a la fin.
t_dit=$((t_dit + $(eq apres_casse_reprises 4)))
t_dit=$((t_dit + $(eq apres_casse_compteur_sites 0)))
# LE DEFAUT, MESURE : le bras d'AVANT tourne degrade sur les deux sites du prompt — prompt
# ampute, deux tours — et ne le dit NULLE PART, ni au journal ni a l'owner.
t_dit=$((t_dit + $(eq avant_casse_prompt_journal_tours 0)))
t_dit=$((t_dit + $(eq avant_casse_prompt_owner_tours 0)))
t_dit=$((t_dit + $(eq avant_casse_prompt_survecu 1)))
# OFF DOIT EGALER L'ABSENCE. Rien de casse : zero refus, zero ligne de journal, zero mot a
# l'owner — le filet n'invente aucun degrade, et les deux bras rendent le MEME texte.
t_dit=$((t_dit + $(eq apres_nu_refus 0)))
t_dit=$((t_dit + $(eq apres_nu_journal_tours 0)))
t_dit=$((t_dit + $(eq apres_nu_owner_tours 0)))
t_dit=$((t_dit + $(eqs apres_nu_owner_par_tour 0,0,0,0,0,0,0)))
t_dit=$((t_dit + $(eq apres_nu_compteur_refus 0)))
t_dit=$((t_dit + $(eq apres_nu_compteur_tours 0)))
t_dit=$((t_dit + $(eq apres_nu_rc 0)))
t_dit=$((t_dit + $(eq apres_nu_tours_aboutis 7)))
# LE SITE DU TEXTE OWNER EXISTE VRAIMENT DANS `lib/backlog.py` : sans lui, les quatre `1`
# ci-dessus viendraient d'un banc qui se parle a lui-meme.
t_dit=$((t_dit + $(eq vivant_backlog_texte_owner 1)))
t_dit=$((t_dit + $(eq vivant_orch_battement 1)))

# --- 3. LES DEUX BRAS, SUR UNE COPIE JETABLE, AVEC UN VRAI FICHIER INCOHERENT. --------------
t_bras=0
t_bras=$((t_bras + $(eq banc_ran 1)))
t_bras=$((t_bras + $(eq banc_bras_avant_introuvable 0)))
# LE BRAS D'AVANT EST ANCRE PAR MARQUEUR, et son commit est PUBLIE.
t_bras=$((t_bras + $([ "$(s avant_orch_commit)" = "-" ] && echo 1 || echo 0)))
t_bras=$((t_bras + $([ "$(s avant_backlog_commit)" = "-" ] && echo 1 || echo 0)))
t_bras=$((t_bras + $(eq avant_orch_a_le_filet 0)))
t_bras=$((t_bras + $(eq avant_backlog_a_le_filet 0)))
t_bras=$((t_bras + $(eq avant_filet_fichier_absent 1)))
t_bras=$((t_bras + $(eq vivant_orch_a_le_filet 1)))
t_bras=$((t_bras + $(eq vivant_backlog_a_le_filet 1)))
# LE STIMULUS EST UN VRAI FICHIER, ET IL EST VERIFIE. A rejoue la panne du 12/09 a l'octet :
# la ligne 345 existe encore, elle est bien changee, et le fichier COMPILE — il explose a
# l'EXECUTION, comme ce jour-la. B est le fichier a moitie ecrit : il ne compile PAS.
t_bras=$((t_bras + $(eq stimulus_ligne_345_presente 1)))
t_bras=$((t_bras + $(eq stimulus_a_change_le_fichier 1)))
t_bras=$((t_bras + $(eq stimulus_a_compile 1)))
t_bras=$((t_bras + $(eq stimulus_b_compile 0)))
t_bras=$((t_bras + $([ "$(n stimulus_b_octets)" -lt "$(n stimulus_b_octets_sain)" ] 2>/dev/null && echo 0 || echo 1)))
# LES DEUX BRAS ONT VU LE MEME MONDE quand rien ne casse : meme nombre de tours, meme prompt.
t_bras=$((t_bras + $(eq avant_nu_tours_aboutis 7)))
t_bras=$((t_bras + $(eq apres_nu_tours_aboutis 7)))
t_bras=$((t_bras + $([ "$(s avant_nu_prompt_par_tour)" = "$(s apres_nu_prompt_par_tour)" ] && echo 0 || echo 1)))

# --- 4. LES QUATRE SITES, ET AUCUN RECHARGEMENT RETIRE. ------------------------------------
t_sites=0
t_sites=$((t_sites + $(eq sites_declares_n 4)))
t_sites=$((t_sites + $(eqs sites_declares \
  orchestrator:backlog,orchestrator:directives,orchestrator:preflight,backlog:gate_verdict)))
# LE SOURCE LIVRE : trois sites dans l'orchestrateur, un dans backlog.py, et plus AUCUN
# rechargement nu dans le code de production.
t_sites=$((t_sites + $(eq vivant_orch_sites_filet 3)))
t_sites=$((t_sites + $(eq vivant_backlog_sites_filet 1)))
t_sites=$((t_sites + $(eq vivant_orch_reloads_bruts 0)))
t_sites=$((t_sites + $(eq vivant_backlog_reloads_bruts 0)))
# HORS PERIMETRE : ON NE RETIRE AUCUN RECHARGEMENT. Le compte d'AVANT doit egaler le compte
# d'APRES, site pour site — un filet qui aurait supprime un rechargement serait vert ici sans
# ce controle-la, et l'autorite recommencerait a diverger du point de production.
t_sites=$((t_sites + $(eq avant_orch_reloads 3)))
t_sites=$((t_sites + $(eq avant_backlog_reloads 1)))
t_sites=$((t_sites + $([ "$(n avant_orch_reloads)" = "$(n vivant_orch_sites_filet)" ] && echo 0 || echo 1)))
t_sites=$((t_sites + $([ "$(n avant_backlog_reloads)" = "$(n vivant_backlog_sites_filet)" ] && echo 0 || echo 1)))
# ET LES QUATRE ONT VRAIMENT REFUSE PENDANT LA COURSE : une liste de sites declares ne prouve
# que la liste. Ceux-ci sont NOMMES par le journal de la jambe, un par un.
t_sites=$((t_sites + $(eqs apres_casse_refus_sites \
  backlog:gate_verdict,orchestrator:backlog,orchestrator:directives,orchestrator:preflight)))

TOTAL=$((t_survie + t_dit + t_bras + t_sites + penalty))

# ========================================================================= la publication ====
pub rs_census_ran "$([ -n "$BN" ] && echo 1 || echo 0)"
pub reload_survival_defects "$TOTAL"
pub reload_survival_defects_terms \
  "survie$t_survie+dit$t_dit+bras$t_bras+sites$t_sites+penalite$penalty${why:+:$why}"
pub rs_survie "$t_survie"
pub rs_dit "$t_dit"
pub rs_bras "$t_bras"
pub rs_sites "$t_sites"
pub rs_witness_penalty "$penalty"

# 1. LA SURVIE — les deux bras cote a cote, et les deux comptes du livrable.
pub rs_after_rc "$(n apres_casse_rc)"
pub rs_after_turns_completed "$(n apres_casse_tours_aboutis)"
pub rs_before_rc "$(n avant_casse_rc)"
pub rs_before_died_at_turn "$(n avant_casse_mort_au_tour)"
pub rs_before_exception "$(s avant_casse_exc)"
pub rs_before_last_line "$(s avant_casse_queue)"
pub rs_before_backlog_rc "$(n avant_casse_backlog_rc)"
pub rs_before_backlog_exception "$(s avant_casse_backlog_exc)"
pub rs_control_before_clean_rc "$(n avant_nu_rc)"
pub rs_control_before_clean_turns "$(n avant_nu_tours_aboutis)"
pub rs_reloads_refused "$(n apres_casse_compteur_refus)"
pub rs_turns_continued "$(n apres_casse_compteur_tours)"
pub rs_refused_sites "$(s apres_casse_refus_sites)"
# LE MODULE CONSERVE PAR SON CONTENU — le temoin qui separe « garder le module » de « garder
# son nom » : A=99 apres un rechargement nu, A=1 apres le filet, sur le MEME fichier casse.
pub rs_naked_reload_value "$(n photo_nu_A)"
pub rs_netted_reload_value "$(n photo_filet_A)"
pub rs_netted_reload_returned "$(n photo_filet_rendu)"
pub rs_netted_recovers "$(n photo_filet_reprise)"
pub rs_bench_left_prod_state_intact "$(n photo_etat_production_intact)"
# LE PROMPT DU WORKER, PAR TOUR — la perte que le bras d'AVANT subissait sans un mot.
pub rs_before_prompt_bytes "$(s avant_casse_prompt_prompt_par_tour)"
pub rs_after_prompt_bytes "$(s apres_casse_prompt_par_tour)"

# 2. L'ETAT DEGRADE, DIT — par tour, dans les deux canaux, et dans les deux bras.
pub rs_journal_turns "$(n apres_casse_journal_tours)"
pub rs_owner_turns "$(n apres_casse_owner_tours)"
pub rs_owner_per_turn "$(s apres_casse_owner_par_tour)"
pub rs_recoveries "$(n apres_casse_reprises)"
pub rs_degraded_sites_at_end "$(n apres_casse_compteur_sites)"
pub rs_before_prompt_journal_turns "$(n avant_casse_prompt_journal_tours)"
pub rs_before_prompt_owner_silent "$(n avant_casse_prompt_owner_tours)"
pub rs_before_prompt_survived "$(n avant_casse_prompt_survecu)"
pub rs_off_refusals "$(n apres_nu_refus)"
pub rs_off_owner_turns "$(n apres_nu_owner_tours)"
pub rs_off_rc "$(n apres_nu_rc)"

# 3. LES BRAS — leurs commits, l'absence de la couche, et les stimuli verifies.
pub rs_before_orch_commit "$(s avant_orch_commit)"
pub rs_before_backlog_commit "$(s avant_backlog_commit)"
pub rs_before_has_net_orch "$(n avant_orch_a_le_filet)"
pub rs_before_has_net_backlog "$(n avant_backlog_a_le_filet)"
pub rs_live_has_net_orch "$(n vivant_orch_a_le_filet)"
pub rs_live_has_net_backlog "$(n vivant_backlog_a_le_filet)"
pub rs_stimulus_line345_present "$(n stimulus_ligne_345_presente)"
pub rs_stimulus_a_compiles "$(n stimulus_a_compile)"
pub rs_stimulus_b_compiles "$(n stimulus_b_compile)"
pub rs_stimulus_b_bytes "$(n stimulus_b_octets)"
pub rs_stimulus_sane_bytes "$(n stimulus_b_octets_sain)"

# 4. LES SITES — declares, comptes dans le source, et refuses pour de vrai.
pub rs_sites_declared "$(s sites_declares)"
pub rs_sites_declared_n "$(n sites_declares_n)"
pub rs_live_net_sites_orch "$(n vivant_orch_sites_filet)"
pub rs_live_net_sites_backlog "$(n vivant_backlog_sites_filet)"
pub rs_live_raw_reloads_orch "$(n vivant_orch_reloads_bruts)"
pub rs_live_raw_reloads_backlog "$(n vivant_backlog_reloads_bruts)"
pub rs_before_reloads_orch "$(n avant_orch_reloads)"
pub rs_before_reloads_backlog "$(n avant_backlog_reloads)"
pub rs_heartbeat_site "$(n vivant_orch_battement)"
pub rs_owner_text_site "$(n vivant_backlog_texte_owner)"

# LES BRUTS, recopies tels quels : c'est ce qui rend la somme lisible et falsifiable. Sous un
# prefixe a eux — le moissonneur garde la DERNIERE valeur d'une cle, et un homonyme ecraserait
# un terme du verdict. Espaces colles, valeur vide rendue `-`.
brut(){ awk -v p="$1" -F= '/^[a-z_][a-z0-9_]*=/ {k=$1; sub(/^[^=]*=/,"",$0);
          gsub(/[[:space:]]+/,"_",$0); if($0=="") $0="-"; printf "%s%s=%s\n", p, k, $0}'; }
printf '%s\n' "$BN" | brut rs_bn_

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in orchestrator.py lib/backlog.py lib/safe_reload.py lib/reload_survival_selftest.py \
         lib/census/harness-reload-must-not-kill-the-loop.sh; do
  k="rs_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
