#!/usr/bin/env bash
# census/harness-verdict-sources-are-incomplete.sh — LE VERDICT DE CET ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course, sa
# sortie `cle=valeur` rejoignant celle du moteur dans le meme journal. Il ne peut ecrire aucun
# champ de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL COMPTE, DANS L'ORDRE DES CINQ POINTS DU LIVRABLE :
#   1. le CRITERE entre dans l'empreinte epinglee            -> vs_critere_non_epingle
#   2. les scripts d'ACQUIS entrent dans la meme empreinte   -> vs_acquis_non_epingles
#   3. la derivation ignore les COMMENTAIRES                 -> vs_prose_fait_dependance
#   4. `proof.txt` n'est plus ecrit apres son propre `mv`    -> vs_ecriture_apres_mv
#   5. un BAC A SABLE copie la liste de la PORTE             -> vs_bac_a_sable_divergent
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte. Une population
# vide, un bras d'ablation aussi silencieux que le bras neuf, un banc qui n'a pas tourne : tout
# cela rend la porte ROUGE. Sans cette polarite, une porte `== 0` sur une integrite est verte par
# INACTION — c'est le defaut que ce chantier ferme, il ne va pas le refabriquer.
#
# LES CONTROLES A LAISSER. `vsq_crit_avant_rc=0`, `vsq_acq_complet_rc=0` et
# `vsq_deriv_prose_ancienne=1` sont les jambes qui PASSENT. Sans elles, un validateur qui
# refuserait tout, ou un nommeur qui ne verrait plus rien, tiendrait toutes les autres.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "vs_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

RAW=$(bash "$AP/lib/verdict_sources_selftest.sh" 2>/dev/null)
g(){ printf '%s\n' "$RAW" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque ou n'est pas un nombre. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(g "$1"); case "$v" in ''|*[!0-9-]*|-) echo -1 ;; *) echo "$v" ;; esac; }
pub(){ printf '%s=%s\n' "$1" "${2:--}"; }

penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }
eq(){ [ "$(n "$1")" = "$2" ] && echo 0 || echo 1; }
ge(){ [ "$(n "$1")" -ge "$2" ] 2>/dev/null && echo 0 || echo 1; }

[ -n "$RAW" ] || faute banc-muet
[ "$(n vsq_selftest_ran)" = 1 ] || faute banc-non-abouti

# ==================================== 1. LE CRITERE ENTRE DANS L'EMPREINTE EPINGLEE ===========
# Deux bras sur le VRAI `validators/generic.sh`, meme preuve, meme disque : seul le critere bouge.
# Il est DESSERRE sans changer le resultat (`episodes=0` satisfait `== 0` comme `<= 9`) : le bras
# d'apres ne peut donc refuser QUE pour la raison cherchee, et `vsq_crit_apres_constats=1` le dit.
t_crit=0
t_crit=$((t_crit + $(eq vsq_crit_monte 1)))
t_crit=$((t_crit + $(eq vsq_crit_avant_rc 0)))        # le controle a laisser
t_crit=$((t_crit + $(eq vsq_crit_apres_rc 1)))
t_crit=$((t_crit + $(eq vsq_crit_apres_constats 1)))  # UN seul constat : celui du critere
t_crit=$((t_crit + $(eq vsq_crit_apres_nomme 1)))
# ... et `backlog.yaml` n'est toujours PAS epingle comme fichier : un seuil surveille ne doit pas
# faire rougir toutes les preuves des que l'orchestrateur reecrit un statut.
t_crit=$((t_crit + $(eq vsq_crit_fichier_epingle 0)))
[ -n "$(g vsq_crit_sha_preuve)" ] && [ "$(g vsq_crit_sha_preuve)" != "$(g vsq_crit_sha_disque)" ] \
  || faute critere-empreinte-insensible

# ==================================== 2. LES ACQUIS ENTRENT DANS LA MEME EMPREINTE ============
t_acq=0
t_acq=$((t_acq + $(eq vsq_acq_monte 1)))
t_acq=$((t_acq + $(eq vsq_acq_complet_rc 0)))         # le controle a laisser
t_acq=$((t_acq + $(eq vsq_acq_ampute_rc 1)))
t_acq=$((t_acq + $(eq vsq_acq_ampute_nomme 1)))
t_acq=$((t_acq + $(ge vsq_acq_count_reel 1)))
# HUIT QUI TOMBE A SEPT EST UN DEFAUT : le bras ampute doit compter UN DE MOINS, pas « autant ».
[ "$(n vsq_acq_count_disque)" -eq "$(( $(n vsq_acq_count_preuve) - 1 ))" ] 2>/dev/null \
  || faute acquis-amputation-invisible
[ "$(n vsq_acq_count_preuve)" = "$(n vsq_acq_count_reel)" ] || faute acquis-compte-divergent
[ -n "$(g vsq_acq_sha_reel)" ] || faute acquis-empreinte-absente

# ==================================== 3. LA DERIVATION IGNORE LES COMMENTAIRES ================
t_der=0
t_der=$((t_der + $(eq vsq_deriv_code_epingle 1)))     # cite par du CODE  -> epingle
t_der=$((t_der + $(eq vsq_deriv_prose_epingle 0)))    # cite par une PROSE -> jamais
t_der=$((t_der + $(eq vsq_deriv_prose_ancienne 1)))   # le controle a laisser : l'ancienne regle
                                                     # l'epinglait, la sonde n'est donc pas aveugle
t_der=$((t_der + $(ge vsq_deriv_sonde_count 4)))
# Sur le depot REEL : la regle ne peut que RETIRER, elle ne vide pas la liste, et aucun membre du
# SOCLE ne sort. Un socle qui s'echapperait serait un vrai defaut, pas un commentaire corrige.
SOCLE_MIN=".autoport/validators/generic.sh .autoport/lib/proof_run.sh .autoport/lib/verdict_sources.sh .autoport/lib/backlog.py .autoport/lib/gate_verdict.py"
for cle in harness_proof_props_pin harness_verdict_integrity harness_verdict_sources_are_incomplete; do
  av=$(n "vsq_deriv_${cle}_avant"); ap=$(n "vsq_deriv_${cle}_apres")
  [ "$av" -ge "$ap" ] 2>/dev/null || { t_der=$((t_der+1)); faute "deriv-$cle-ajoute"; }
  [ "$ap" -ge 15 ] 2>/dev/null     || { t_der=$((t_der+1)); faute "deriv-$cle-liste-videe"; }
  for s in $SOCLE_MIN; do
    case ",$(g "vsq_deriv_${cle}_sortants")," in *",$s,"*) faute "socle-sorti-$cle" ;; esac
  done
done

# ==================== 4. `proof.txt` N'EST PLUS ECRIT APRES SON PROPRE `mv` ===================
# Deux grandeurs, pas une : ce que le CODE porte aujourd'hui contre ce qu'il portait au commit
# d'avant (sans quoi un zero se lirait « personne n'a regarde »), et ce que la MACHINE a relu a la
# sortie de courses REELLES. Le sceau de la course en cours n'existe pas encore quand ce
# recensement tourne : la population est celle des courses precedentes, et elle doit exister.
t_seal=0
t_seal=$((t_seal + $(eq vsq_seal_ecritures_now 0)))
t_seal=$((t_seal + $(ge vsq_seal_ecritures_avant 1)))   # l'ablation VOIT le defaut d'avant
# LA COURSE APPAREIL DU BAC A SABLE : le SEUL chemin du harnais qui passe par le teardown de FIN,
# celui qui ajoutait ses cles apres le `mv`. Une course x86 ne le traverse jamais : compter sur
# ses seuls sceaux serait vert par INACTION.
t_seal=$((t_seal + $(eq vsq_seal_bac_proof 1)))
t_seal=$((t_seal + $(eq vsq_seal_bac_lu 1)))
t_seal=$((t_seal + $(eq vsq_seal_bac_ecart 0)))
# ... et RIEN N'A ETE PERDU en avancant le teardown avant la composition : ses cles sont toujours
# DANS la preuve. Un zero d'ecriture posterieure obtenu en n'ecrivant plus rien ne vaut rien.
t_seal=$((t_seal + $(eq vsq_seal_bac_teardown 1)))
t_seal=$((t_seal + $(ge vsq_seal_bac_props 2)))
# ... et le sceau SAIT ROUGIR : meme course, meme bac, un `proof_run.sh` a qui on rend l'ecriture
# posterieure. Sans cette jambe, `vsq_seal_bac_ecart=0` ne distingue pas « rien apres le mv » de
# « le sceau ne regarde rien ».
t_seal=$((t_seal + $(eq vsq_seal_sonde_detectee 1)))
t_seal=$((t_seal + $(eq vsq_seal_ecarts 0)))            # la population du disque, si elle existe
[ "$(( $(n vsq_seal_paires) + $(n vsq_seal_bac_lu) ))" -ge 1 ] 2>/dev/null \
  || faute sceau-population-vide
[ -n "$(g vsq_seal_ablation_commit)" ] && [ "$(g vsq_seal_ablation_commit)" != "-" ] \
  || faute ablation-sans-ancre

# ==================== 5. UN BAC A SABLE COPIE LA LISTE DE LA PORTE ============================
t_bac=0
t_bac=$((t_bac + $(eq vsq_bac_pin_monte 1)))
t_bac=$((t_bac + $(eq vsq_bac_pin_arms_ok 2)))          # les deux bras du bac ont bien couru
t_bac=$((t_bac + $(eq vsq_bac_pin_ecart 0)))
t_bac=$((t_bac + $(ge vsq_bac_pin_porte 10)))           # la liste de reference n'est pas vide
t_bac=$((t_bac + $(eq vsq_bac_test_rc 0)))
t_bac=$((t_bac + $(eq vsq_bac_test_manque 0)))
t_bac=$((t_bac + $(eq vsq_bac_test_en_trop 0)))
t_bac=$((t_bac + $(ge vsq_bac_test_attendu 10)))
[ "$(n vsq_bac_pin_contenu)" = "$(n vsq_bac_pin_porte)" ] || faute bac-pin-compte-divergent
[ "$(n vsq_bac_test_trouve)" = "$(n vsq_bac_test_attendu)" ] || faute bac-test-compte-divergent

TOTAL=$((t_crit + t_acq + t_der + t_seal + t_bac + penalty))

# ============================================================================ la publication ==
pub vs_census_ran "$([ -n "$RAW" ] && echo 1 || echo 0)"
pub verdict_sources_defects "$TOTAL"
pub verdict_sources_terms \
  "critere$t_crit+acquis$t_acq+prose$t_der+sceau$t_seal+bac$t_bac+penalite$penalty${why:+:$why}"
pub vs_critere_non_epingle   "$t_crit"
pub vs_acquis_non_epingles   "$t_acq"
pub vs_prose_fait_dependance "$t_der"
pub vs_ecriture_apres_mv     "$t_seal"
pub vs_bac_a_sable_divergent "$t_bac"
pub vs_witness_penalty       "$penalty"

# LES GRANDEURS BRUTES DU BANC, telles qu'il les a rendues. Une valeur VIDE est publiee `-` : le
# moissonneur jette `cle=` et la cle disparaitrait sans qu'on sache pourquoi.
printf '%s\n' "$RAW" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/\1=/p' | sed 's/=$/=-/'
