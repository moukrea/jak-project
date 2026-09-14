#!/usr/bin/env bash
# census/harness-proof-run-erases-proof-only-once-it-runs.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Il ne peut ecrire aucun champ de `proof.txt` : ni `sha`, ni `frames`, ni `crash`.
#
# CE QU'IL MESURE, DANS L'ORDRE DU LIVRABLE :
#   1. LE COUT D'AVANT, CHIFFRE — publie A PART, jamais dans la somme  -> pe_avant_*
#   2. L'EFFACEMENT SUIT L'AMORCAGE                                    -> pe_t2_*
#   3. LE TEMOIN A DEUX BRAS, ET SES VERDICTS COTE A COTE              -> pe_arm_*, pe_t3_*
#   4. `proof-prev.txt` RESTE                                          -> pe_t4_*
#
# LA GRANDEUR, DEFINIE SUR TROIS COLONNES DU REGISTRE ET SUR RIEN D'AUTRE. Une preuve detruite
# sans course, c'est : il y AVAIT une preuve (col.8 > 0), la course n'a PAS atteint son point
# d'amorcage (col.6 = 0), et il n'y en a PLUS (col.9 = 0). Cette definition ne nomme aucune
# ligne de code : elle tient quelle que soit celle qui a fini par tenir le `rm`. C'est ce qui
# permet au bras d'ABSENCE de la faire rendre 1 alors qu'il detruit par un `rm` de `die3` que le
# bras livre, lui, ne detruit plus — deux chemins differents, une seule grandeur.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte : une porte `== 0`
# sur un nettoyage est verte par INACTION si on ne le fait pas.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "pe_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

RAW=$(bash "$AP/lib/proof_erase_selftest.sh" 2>/dev/null)
g(){ printf '%s\n' "$RAW" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(g "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }
pub(){ printf '%s=%s\n' "$1" "${2:--}"; }

DEFAUTS=0
faute(){ DEFAUTS=$((DEFAUTS + $1)); }

# ================================================================ 0. LE BANC A-T-IL TOURNE ===
BANC=$(n selftest_ran); MONTES=$(n selftest_arms_montes); COURUS=$(n selftest_arms_courus)
pub pe_banc_ran "$BANC"
pub pe_banc_arms_montes "$MONTES"
pub pe_banc_arms_courus "$COURUS"
pub pe_banc_preuve_avant_octets "$(g banc_preuve_avant_octets)"
pub pe_banc_preuve_avant_sha "$(g banc_preuve_avant_sha)"
t_banc=0
[ "$BANC" = 1 ] || t_banc=$((t_banc + 1))
[ "$MONTES" = 4 ] || t_banc=$((t_banc + 1))
[ "$COURUS" = 4 ] || t_banc=$((t_banc + 1))
pub pe_banc_incomplet "$t_banc"; faute "$t_banc"

# ===================================== LES QUATRE VERDICTS, COTE A COTE (livrable 3) =========
# On publie ce que CHAQUE bras a fait AVANT d'en juger un seul. Un verdict sans sa table est une
# affirmation ; avec elle, n'importe qui refait le raisonnement.
for a in garde_binaire garde_build amorce vieux; do
  pub "pe_arm_${a}_rc"                "$(g "arm_${a}_rc")"
  pub "pe_arm_${a}_raison"            "$(g "arm_${a}_raison")"
  pub "pe_arm_${a}_amorce"            "$(g "arm_${a}_amorce")"
  pub "pe_arm_${a}_preuve_presente"   "$(g "arm_${a}_preuve_presente")"
  pub "pe_arm_${a}_preuve_octets"     "$(g "arm_${a}_preuve_octets")"
  pub "pe_arm_${a}_preuve_identique"  "$(g "arm_${a}_preuve_identique_avant")"
  pub "pe_arm_${a}_prev_ecrit"        "$(g "arm_${a}_prev_ecrit")"
  pub "pe_arm_${a}_prev_est_la_veille" "$(g "arm_${a}_prev_est_la_veille")"
  pub "pe_arm_${a}_registre_rc"       "$(g "arm_${a}_registre_rc")"
  pub "pe_arm_${a}_registre_efface"   "$(g "arm_${a}_registre_efface")"
  pub "pe_arm_${a}_registre_point"    "$(g "arm_${a}_registre_point")"
  pub "pe_arm_${a}_octets_avant"      "$(g "arm_${a}_registre_octets_avant")"
  pub "pe_arm_${a}_octets_apres"      "$(g "arm_${a}_registre_octets_apres")"
  pub "pe_arm_${a}_detruite_sans_course" "$(g "arm_${a}_detruite_sans_course")"
  pub "pe_arm_${a}_busy_why"          "$(g "arm_${a}_busy_why")"
done

# ============================= 2. L'EFFACEMENT SUIT L'AMORCAGE — LA GRANDEUR CENTRALE ========
# Aucun des trois bras du code LIVRE ne doit avoir detruit une preuve sans avoir amorce. Le bras
# `vieux` n'est pas compte ici : c'est le temoin d'AVANT, et il DOIT valoir 1 (terme 5).
t2=0
for a in garde_binaire garde_build amorce; do
  v=$(n "arm_${a}_detruite_sans_course")
  case "$v" in 0) ;; *) t2=$((t2 + 1)) ;; esac
done
pub pe_t2_detruites_sans_course "$t2"; faute "$t2"

# LES DEUX GARDES : elles meurent AVANT l'amorcage, et elles rendent la preuve A L'OCTET.
# « Presente » ne suffit pas : une preuve reecrite a l'identique par hasard n'existe pas, mais
# une preuve TRONQUEE se lirait « presente ». C'est l'empreinte qui juge.
t2g=0
for a in garde_binaire garde_build; do
  [ "$(n "arm_${a}_rc")" = 3 ]                  || t2g=$((t2g + 1))
  [ "$(n "arm_${a}_amorce")" = 0 ]              || t2g=$((t2g + 1))
  [ "$(n "arm_${a}_preuve_presente")" = 1 ]     || t2g=$((t2g + 1))
  [ "$(n "arm_${a}_preuve_identique_avant")" = 1 ] || t2g=$((t2g + 1))
  [ "$(n "arm_${a}_registre_efface")" = 0 ]     || t2g=$((t2g + 1))
  [ "$(g "arm_${a}_registre_point")" = "-" ]    || t2g=$((t2g + 1))
  [ -n "$(g "arm_${a}_raison")" ]               || t2g=$((t2g + 1))
done
pub pe_t2_gardes_defaillantes "$t2g"; faute "$t2g"
# LA CAUSE CITEE PAR LE SIGNALEMENT, NOMMEMENT. Un bras qui mourrait d'autre chose mesurerait
# autre chose : `build-en-cours` est la raison qui a detruit la preuve du 12/09.
t2c=0
[ "$(g arm_garde_build_raison)" = build-en-cours ] || t2c=$((t2c + 1))
[ "$(g arm_garde_binaire_raison)" = binaire-absent ] || t2c=$((t2c + 1))
pub pe_t2_causes_non_conformes "$t2c"; faute "$t2c"

# UNE GARDE QUI EMPECHE UNE COURSE SAINE DE MESURER N'EST PAS UNE GARDE. Le bras `amorce` doit
# AMORCER, effacer AU POINT NOMME, et remplacer la preuve par la sienne.
t2a=0
[ "$(n arm_amorce_rc)" = 0 ]                    || t2a=$((t2a + 1))
[ "$(n arm_amorce_amorce)" = 1 ]                || t2a=$((t2a + 1))
[ "$(n arm_amorce_preuve_presente)" = 1 ]       || t2a=$((t2a + 1))
[ "$(n arm_amorce_preuve_identique_avant)" = 0 ] || t2a=$((t2a + 1))
[ "$(n arm_amorce_registre_efface)" = 1 ]       || t2a=$((t2a + 1))
[ "$(g arm_amorce_registre_point)" = amorcage-moteur-x86 ] || t2a=$((t2a + 1))
pub pe_t2_course_saine_bloquee "$t2a"; faute "$t2a"

# ================================= 3. LE TEMOIN A DEUX BRAS EST-IL SEULEMENT CAPABLE ? =======
# Deux bras qui rendent LE MEME verdict ne temoignent de rien : ils diraient « la preuve survit
# toujours » aussi bien que « l'instrument est aveugle ». On exige que les deux DIFFERENT, sur
# la grandeur qui compte — la preuve tenue d'un cote, remplacee de l'autre.
t3=0
[ "$(n arm_garde_build_preuve_identique_avant)" = 1 ] || t3=$((t3 + 1))
[ "$(n arm_amorce_preuve_identique_avant)" = 0 ]      || t3=$((t3 + 1))
[ "$(n arm_garde_build_registre_efface)" = 0 ]        || t3=$((t3 + 1))
[ "$(n arm_amorce_registre_efface)" = 1 ]             || t3=$((t3 + 1))
pub pe_t3_temoin_aveugle "$t3"; faute "$t3"

# ===================================== 4. LE FILET `proof-prev.txt` N'EST PAS RETIRE =========
# Il n'est pas le sujet de l'item, et c'est pour ca qu'il faut le VERIFIER : un correctif qui
# deplace un geste emporte souvent son voisin. Le bras qui amorce doit l'ecrire, et ce qu'il
# porte doit etre la preuve de la VEILLE, pas autre chose.
t4=0
[ "$(n arm_amorce_prev_ecrit)" = 1 ]          || t4=$((t4 + 1))
[ "$(n arm_amorce_prev_est_la_veille)" = 1 ]  || t4=$((t4 + 1))
pub pe_t4_filet_prev_perdu "$t4"; faute "$t4"
# ET IL N'EST PAS ECRIT PAR UNE COURSE QUI N'A PAS AMORCE : archiver la preuve d'hier sous
# `proof-prev` en la retirant de `proof.txt` serait la meme destruction, sous un autre nom.
t4b=0
for a in garde_binaire garde_build; do
  [ "$(n "arm_${a}_prev_ecrit")" = 0 ] || t4b=$((t4b + 1))
done
pub pe_t4_filet_ecrit_sans_course "$t4b"; faute "$t4b"

# ===================================== 5. LE TEMOIN D'AVANT, FABRIQUE ========================
# LE BRAS D'ABSENCE. Le correctif est DEFAIT dans la copie du bac — ligne par ligne, et le
# nombre de lignes transformees est publie : une transformation qui ne change rien serait une
# ablation VIDE, et un zero s'y lirait « rien ne se perd » alors qu'il voudrait dire « personne
# n'a regarde ». Ce bras DOIT detruire, sinon le banc ne prouve rien du bras livre.
t5=0
[ "$(n arm_vieux_transform_lignes)" -ge 2 ] 2>/dev/null || t5=$((t5 + 1))
[ "$(n arm_vieux_detruite_sans_course)" = 1 ]           || t5=$((t5 + 1))
[ "$(n arm_vieux_preuve_presente)" = 0 ]                || t5=$((t5 + 1))
[ "$(n arm_vieux_amorce)" = 0 ]                         || t5=$((t5 + 1))
pub pe_t5_temoin_avant_absent "$t5"; faute "$t5"
pub pe_t5_ablation_lignes_transformees "$(g arm_vieux_transform_lignes)"

# ======================== LE REGISTRE DE LA MACHINE REELLE, ET SON DENOMINATEUR ==============
# La MEME regle, sur les courses vraies. Il est append-only et ecrit a CHAQUE sortie, y compris
# celles qui meurent : un registre qu'on n'ecrit que dans le cas heureux ne peut pas servir de
# denominateur. La ligne de la course EN COURS n'y est pas encore — elle s'ecrit au `trap EXIT`,
# donc apres ce recensement : le compte porte sur les courses ANTERIEURES, et on le dit.
REG="$AP/logs/proof-erase.tsv"
if [ -s "$REG" ]; then
  REGL=$(grep -c . "$REG")
  REGD=$(awk -F'\t' '$8+0>0 && $6+0==0 && $9+0==0' "$REG" | grep -c . || true)
  pub pe_machine_registre_lignes "$REGL"
  pub pe_machine_detruites_sans_course "${REGD:-0}"
  pub pe_machine_courses_amorcees "$(awk -F'\t' '$6+0==1' "$REG" | grep -c . || true)"
  faute "${REGD:-0}"
else
  # ZERO SUR ZERO N'EST PAS UNE REUSSITE : on le NOMME au lieu de le compter vert. Le poids de
  # la preuve est sur le bac a sable, ou la population est FABRIQUEE.
  pub pe_machine_registre_lignes 0
  pub pe_machine_detruites_sans_course 0
  pub pe_machine_courses_amorcees 0
  pub pe_machine_population_vide 1
fi

# ================================= 1. LE COUT D'AVANT, CHIFFRE, A PART ======================
# Il ne rentre PAS dans la somme : c'est ce que le defaut COUTAIT, pas ce qu'il coute encore.
#
# CE QUE LE DISQUE PEUT DIRE, ET CE QU'IL NE PEUT PAS. `proof.txt` n'est pas versionne
# (`.gitignore` ligne 173) et il est REMPLACE a chaque course : la preuve qui SURVIT est
# toujours celle de la derniere course reussie. La population « preuve detruite » est donc VIDE
# PAR CONSTRUCTION sur le disque. Ce qui se compte, c'est la LIGNE que la course morte a laissee
# dans le journal de son essai, et le FILET qui a du servir.
pub pe_avant_journaux_essais_lus "$(g avant_journaux_essais_lus)"
pub pe_avant_evenements_sans_amorcage "$(g avant_evenements_sans_amorcage)"
pub pe_avant_evenements_liste "$(g avant_evenements_liste)"
pub pe_avant_raisons "$(g avant_raisons)"
pub pe_avant_items_touches "$(g avant_items_touches)"
pub pe_avant_items_avec_porte_tenue_archivee "$(g avant_items_avec_porte_tenue_archivee)"
pub pe_avant_citations_croisees_ecartees "$(g avant_citations_croisees)"
pub pe_avant_citations_croisees_liste "$(g avant_citations_croisees_liste)"
pub pe_avant_verdicts_archives "$(g avant_verdicts_archives)"
pub pe_avant_dossiers_items "$(g avant_dossiers_items)"
pub pe_avant_preuves_presentes "$(g avant_preuves_presentes)"
pub pe_avant_filets_prev "$(g avant_filets_prev)"
pub pe_avant_etats_impossibles "$(g avant_etats_impossibles)"
pub pe_avant_disque_vide_par_construction "$(g avant_disque_vide_par_construction)"
pub pe_avant_fabrique_detruites "$(g arm_vieux_detruite_sans_course)"
# UN COUT D'AVANT NUL SERAIT UN INSTRUMENT AVEUGLE, PAS UNE ABSENCE DE DEFAUT. Les deux voies
# doivent porter : l'archive (un evenement nomme et date) ET la fabrication (le bras d'absence).
t1=0
[ "$(n avant_evenements_sans_amorcage)" -ge 1 ] 2>/dev/null || t1=$((t1 + 1))
[ "$(n arm_vieux_detruite_sans_course)" -ge 1 ] 2>/dev/null || t1=$((t1 + 1))
pub pe_avant_cout_non_chiffre "$t1"; faute "$t1"

# ===================================================================== LA SOMME ==============
pub proofs_erased_without_run "$DEFAUTS"
pub pe_census_ran 1
