#!/usr/bin/env bash
# census/harness-main-agent-context-volume.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Sa sortie `cle=valeur` rejoint celle du moteur. Il n'ecrit aucun champ de `proof.txt`.
#
# CE QU'IL MESURE, DANS L'ORDRE DE CE QUE L'ITEM DEMANDE :
#   1. LE COUT D'AVANT, CHIFFRE sur nos 278 essais opus-5/eleve            -> t_mesure
#   2. LES LEVIERS, CHIFFRES — Y COMPRIS CELUI QUI NE PAIE PAS             -> t_leviers
#   3. LE CORRECTIF EST ARME, ET LE BRAS D'AVANT NE L'EST PAS              -> t_arme
#   4. L'ATTENTE TIENT DANS UN TOUR, ET ELLE NE MENT PAS                   -> t_attente
#   5. LA GARDE QUI MORDRA PLUS TARD : quand 5 essais auront tourne sous
#      la configuration armee, la baisse mesuree devra tenir              -> t_apres
#
# DEUX SOURCES QUI NE SE RECOUVRENT PAS. `lib/census/context-volume/collect.py` ne mesure que
# ce qui a DEJA eu lieu (les journaux d'essai) ; `lib/census/context-volume/selftest.py` fait
# TOURNER les pieces livrees sur de vrais processus et de vraies charges utiles de crochet.
# L'un dit combien le defaut coute, l'autre dit que le correctif marche.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte, et `-1` (cle
# absente) ne passe aucune porte `== 0`. Sans cette polarite, une porte `== 0` serait verte par
# INACTION : il suffirait que rien ne tourne.
#
# CE QUI EST PUBLIE SANS ETRE COMPTE, ET POURQUOI. La population « APRES » est vide le jour ou
# ce correctif est livre : aucun essai n'a encore tourne sous la ligne de lancement armee. On
# publie `cv_apres_essais` et `cv_apres_mesurable` a cote du compte plutot que de fabriquer une
# baisse qui n'a pas ete mesuree. Des que cinq essais armes existent, le terme 5 se met a
# compter TOUT SEUL, sans qu'une ligne de ce fichier change : c'est la garde de non-regression.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "cv_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

# LE MOISSONNEUR DE proof_run.sh NE GARDE QUE `^cle=valeur$` SANS ESPACE, et jette une valeur
# VIDE. On colle les espaces ICI, au point de publication, et le vide devient `-`.
pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }

CV=$(timeout -k 15 600 python3 "$AP/lib/census/context-volume/collect.py" "$AP/logs" 2>/dev/null)
BN=$(timeout -k 15 600 python3 "$AP/lib/census/context-volume/selftest.py" 2>/dev/null)
TOUT=$(printf '\n%s\n%s\n' "$CV" "$BN")

s(){ printf '%s\n' "$TOUT" | sed -n "s/^$1=//p" | tail -1; }
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9.-]*) echo -1 ;; *) echo "${v%%.*}" ;; esac; }

penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }
eq(){  [ "$(n "$1")" = "$2" ] && echo 0 || echo 1; }
eqs(){ [ "$(s "$1")" = "$2" ] && echo 0 || echo 1; }
ge(){  local v; v=$(n "$1"); [ "$v" != -1 ] && [ "$v" -ge "$2" ] 2>/dev/null && echo 0 || echo 1; }
le(){  local v; v=$(n "$1"); [ "$v" != -1 ] && [ "$v" -le "$2" ] 2>/dev/null && echo 0 || echo 1; }
entre(){ local v; v=$(n "$1")
         [ "$v" != -1 ] && [ "$v" -ge "$2" ] && [ "$v" -le "$3" ] 2>/dev/null && echo 0 || echo 1; }

[ -n "$CV" ] || faute recensement-d-archive-muet
[ -n "$BN" ] || faute banc-muet
[ "$(n banc_ran)" = 1 ] || faute banc-n-a-pas-tourne
[ "$(s banc_panne)" = "-" ] || faute "banc-en-panne:$(s banc_panne)"

# ============================ 1. LE COUT D'AVANT, LU SUR NOS PROPRES JOURNAUX ================
# LE DENOMINATEUR D'ABORD : une part calculee sur une population vide serait verte par cecite.
t_mesure=0
t_mesure=$((t_mesure + $(ge cv_journaux_lus 400)))
t_mesure=$((t_mesure + $(ge cv_essais 200)))
t_mesure=$((t_mesure + $(ge cv_tours_x10_par_essai 500)))
t_mesure=$((t_mesure + $(ge cv_integrale_par_essai 10000000)))
t_mesure=$((t_mesure + $(ge cv_prefixe_moyen 20000)))
# LE COUT PAR ESSAI RETROUVE CELUI DE L'ETUDE (17,25 $) : si ce chiffre-la ne se reproduit pas,
# rien de ce qui suit ne parle de la meme population.
t_mesure=$((t_mesure + $(ge cv_cout_essais 200)))
t_mesure=$((t_mesure + $(entre cv_cout_centimes_par_essai 1000 2500)))
# LA PARTITION FERME : prefixe + resultats + reflexion + appels + texte = 1000 pour mille.
SOMME=$(( $(n cv_part_prefixe_pm) + $(n cv_part_resultats_pm) + $(n cv_part_reflexion_pm) \
        + $(n cv_part_appels_pm) + $(n cv_part_texte_pm) ))
[ "$SOMME" -ge 990 ] && [ "$SOMME" -le 1010 ] 2>/dev/null || t_mesure=$((t_mesure + 1))
# ET LA REFLEXION N'EST PAS A ZERO. Son texte est expurge des journaux : un recensement qui la
# lirait aux caracteres publierait 0 et ferait porter sa masse aux resultats d'outil.
t_mesure=$((t_mesure + $(entre cv_part_reflexion_pm 100 450)))

# ================== 2. LES LEVIERS, CHIFFRES — Y COMPRIS CELUI QUI NE PAIE PAS ===============
t_leviers=0
# LE LEVIER QUI PAIE : les tours d'attente. 16,3 par essai, 20,2 % de l'integrale.
t_leviers=$((t_leviers + $(ge cv_part_attente_pm 150)))
t_leviers=$((t_leviers + $(ge cv_attente_tours_x10 100)))
t_leviers=$((t_leviers + $(ge cv_attente_sleep_pm 50)))
t_leviers=$((t_leviers + $(ge cv_sleep_ge10 500)))
# LE LEVIER QUI NE PAIE PAS, ET QUI RESTE NOMME. Tronquer les resultats d'outil a 8 000
# caracteres ne rend que 5,8 % : la masse est dans les MILLIERS de petits resultats (mediane
# 635 caracteres), pas dans quelques gros. Cette borne est une GARDE : le jour ou quelqu'un
# voudra « corriger » par la troncature, ce terme dira que ca ne paie pas.
t_leviers=$((t_leviers + $(le cv_tronque_8k_pm 100)))
t_leviers=$((t_leviers + $(ge cv_res_bash_n 5000)))
t_leviers=$((t_leviers + $(le cv_res_bash_median 5000)))
# LE RISQUE DU RETRAIT DES SERVEURS MCP EST CHIFFRE, AVEC SON DENOMINATEUR.
t_leviers=$((t_leviers + $(ge cv_appels_outil 10000)))
t_leviers=$((t_leviers + $(le cv_appels_mcp 5)))

# ===================== 3. LE CORRECTIF EST ARME, ET LE BRAS D'AVANT NE L'EST PAS =============
t_arme=0
# LA LIGNE DE LANCEMENT : on APPELLE `worker_command`, on ne la grep pas — un grep compterait
# le commentaire qui l'explique.
t_arme=$((t_arme + $(eq banc_cli_arme 1)))
t_arme=$((t_arme + $(eqs banc_cli_premier claude)))
t_arme=$((t_arme + $(ge banc_cli_argv_n 10)))
# LE BRAS D'AVANT EST L'ABSENCE, ancre sur le commit qui precede l'introduction du marqueur.
t_arme=$((t_arme + $(eq banc_cli_avant_arme 0)))
t_arme=$((t_arme + $(eq banc_cli_ancre_porte_le_marqueur 0)))
t_arme=$((t_arme + $(ge banc_cli_ancre_octets 3000)))
[ "$(n banc_cli_argv_n)" = "$(( $(n banc_cli_avant_argv_n) + 1 ))" ] 2>/dev/null \
  || t_arme=$((t_arme + 1))
# LE CROCHET : douze charges utiles reelles, les DEUX bras, et le refus NOMME son remplacant.
t_arme=$((t_arme + $(ge banc_crochet_charges 10)))
[ "$(n banc_crochet_arme_conformes)" = "$(n banc_crochet_charges)" ] || t_arme=$((t_arme + 1))
[ "$(n banc_crochet_avant_conformes)" = "$(n banc_crochet_charges)" ] || t_arme=$((t_arme + 1))
[ "$(n banc_crochet_refus_nommant_await)" = "$(n banc_crochet_refus_attendus)" ] \
  || t_arme=$((t_arme + 1))
t_arme=$((t_arme + $(ge banc_crochet_refus_attendus 3)))
t_arme=$((t_arme + $(eq banc_ancre_porte_le_marqueur 0)))
t_arme=$((t_arme + $(ge banc_ancre_octets 5000)))
# LE CROCHET TOURNE AVANT CHAQUE Bash : il doit rester rapide, sinon le correctif se paie en
# latence a chaque commande.
t_arme=$((t_arme + $(le banc_crochet_ms_max 200)))
# ET LA CONSIGNE EST DANS LE PROMPT QUE LE WORKER RECOIT — noeud d'AST, pas un grep.
t_arme=$((t_arme + $(eq banc_preambule_nomme_await 1)))
t_arme=$((t_arme + $(eq banc_preambule_nomme_le_cout 1)))

# ============================= 4. L'ATTENTE TIENT DANS UN TOUR, ET ELLE NE MENT PAS ==========
t_attente=0
# LA CIBLE FINIT : un seul appel, il rend la main quand elle meurt — y compris quand elle est
# devenue un ZOMBIE, ou `kill -0` reussit encore (61 s d'attente sur un mort de 6 s, au banc).
t_attente=$((t_attente + $(eq banc_await_fini_rc 0)))
t_attente=$((t_attente + $(eq banc_await_fini_finished 1)))
t_attente=$((t_attente + $(eqs banc_await_fini_state fini)))
t_attente=$((t_attente + $(entre banc_await_fini_mesure_s 3 20)))
t_attente=$((t_attente + $(eq banc_await_fini_zombie 1)))
# LA MEME CIBLE PAR L'AUTRE CHEMIN : detachee, moissonnee par le systeme, pas zombie.
t_attente=$((t_attente + $(eq banc_await_detache_rc 0)))
t_attente=$((t_attente + $(eq banc_await_detache_finished 1)))
t_attente=$((t_attente + $(eq banc_await_detache_zombie 0)))
t_attente=$((t_attente + $(entre banc_await_detache_mesure_s 3 20)))
# LA BORNE TRANCHE, ET ELLE NE TUE PAS LA CIBLE.
t_attente=$((t_attente + $(eq banc_await_borne_rc 3)))
t_attente=$((t_attente + $(eq banc_await_borne_finished 0)))
t_attente=$((t_attente + $(eqs banc_await_borne_state borne-atteinte)))
t_attente=$((t_attente + $(eq banc_await_borne_cible_vivante 1)))
# « DEJA FINI » ET « AUCUN PID » NE SE CONFONDENT PAS : l'un est un succes, l'autre est nomme.
t_attente=$((t_attente + $(eq banc_await_mort_rc 0)))
t_attente=$((t_attente + $(eqs banc_await_mort_state deja-fini)))
t_attente=$((t_attente + $(eq banc_await_mort_waited 0)))
t_attente=$((t_attente + $(eqs banc_await_sanspid_state aucun-pid)))
t_attente=$((t_attente + $(eq banc_await_sanspid_finished 0)))
# LA SORTIE EST BORNEE : une attente ne rend pas au contexte ce qu'elle vient de lui economiser.
t_attente=$((t_attente + $(ge banc_await_journal_octets 1000000)))
t_attente=$((t_attente + $(le banc_await_sortie_octets 20000)))
t_attente=$((t_attente + $(eq banc_await_plafond_s 3600)))

# ================== 5. LA GARDE QUI MORDRA PLUS TARD — ET QUI LE DIT AUJOURD'HUI =============
# La population « APRES » est celle des essais dont la LIGNE DE LANCEMENT enregistree porte
# `--strict-mcp-config` : c'est la configuration elle-meme qui les designe, pas un seuil sur
# une grandeur qui derive. Tant qu'ils sont moins de cinq, ce terme ne compte pas et le DIT.
APRES=$(n cv_apres_essais)
t_apres=0
if [ "$APRES" != -1 ] && [ "$APRES" -ge 5 ] 2>/dev/null; then
  MESURABLE=1
  t_apres=$((t_apres + $(ge cv_baisse_integrale_pm 200)))
  t_apres=$((t_apres + $(ge cv_apres_tours_x10_par_essai 1)))
else
  MESURABLE=0
fi

TOTAL=$((t_mesure + t_leviers + t_arme + t_attente + t_apres + penalty))

# ====================================== COMBIEN DE TEMOINS ONT VRAIMENT ETE LUS ? ============
# UNE SOMME A ZERO SUR DES TERMES AVEUGLES EST LE FAUX VERT LE PLUS CHER. La liste ci-dessous
# est le contrat de ce verdict : chaque cle qu'un terme interroge. On publie COMBIEN ont ete
# lues et on NOMME celles qui manquent. Recherche par filtrage de motif, SANS TUBE : `grep -q`
# sous `pipefail` rend 141 sur un SIGPIPE et la condition devient fausse sur une population qui
# PORTE le motif.
TEMOINS="cv_journaux_lus cv_essais cv_tours_x10_par_essai cv_integrale_par_essai
cv_prefixe_moyen cv_cout_essais cv_cout_centimes_par_essai cv_part_prefixe_pm
cv_part_resultats_pm cv_part_reflexion_pm cv_part_appels_pm cv_part_texte_pm
cv_part_attente_pm cv_attente_sleep_pm cv_attente_tail_pm cv_attente_ps_pm
cv_attente_tours_x10 cv_sleep_ge10 cv_sleep_heures cv_tronque_2k_pm cv_tronque_4k_pm
cv_tronque_8k_pm cv_tronque_16k_pm cv_res_bash_median cv_res_bash_n cv_appels_outil
cv_appels_mcp cv_essais_avec_mcp cv_apres_essais cv_baisse_integrale_pm cv_baisse_cout_pm
banc_ran banc_panne banc_cli_arme banc_cli_avant_arme banc_cli_argv_n banc_cli_avant_argv_n
banc_cli_premier banc_cli_ancre_commit banc_cli_ancre_octets banc_cli_ancre_porte_le_marqueur
banc_ancre_commit banc_ancre_octets banc_ancre_porte_le_marqueur banc_crochet_charges
banc_crochet_arme_conformes banc_crochet_avant_conformes banc_crochet_refus_nommant_await
banc_crochet_refus_attendus banc_crochet_ms_max banc_preambule_nomme_await
banc_preambule_nomme_le_cout banc_preambule_octets banc_await_fini_rc banc_await_fini_state
banc_await_fini_finished banc_await_fini_mesure_s banc_await_fini_zombie
banc_await_detache_rc banc_await_detache_finished banc_await_detache_zombie
banc_await_detache_mesure_s banc_await_borne_rc banc_await_borne_state
banc_await_borne_finished banc_await_borne_cible_vivante banc_await_mort_rc
banc_await_mort_state banc_await_mort_waited banc_await_sanspid_state
banc_await_sanspid_finished banc_await_sortie_octets banc_await_journal_octets
banc_await_plafond_s"
LUS=0; NTEMOINS=0; MANQUANTS=""
for k in $TEMOINS; do
  NTEMOINS=$((NTEMOINS+1))
  case "$TOUT" in
    *"
$k="*) LUS=$((LUS+1)) ;;
    *) MANQUANTS="${MANQUANTS:+$MANQUANTS+}$k" ;;
  esac
done

# =========================================================================== CE QUI EST PUBLIE
pub cv_census_ran "$([ "$(n banc_ran)" = 1 ] && [ -n "$CV" ] && echo 1 || echo 0)"
pub context_volume_defects "$TOTAL"
pub context_volume_terms \
  "mesure$t_mesure+leviers$t_leviers+arme$t_arme+attente$t_attente+apres$t_apres+penalite$penalty${why:+:$why}"
pub cv_t_mesure "$t_mesure"
pub cv_t_leviers "$t_leviers"
pub cv_t_arme "$t_arme"
pub cv_t_attente "$t_attente"
pub cv_t_apres "$t_apres"
pub cv_apres_mesurable "$MESURABLE"
pub cv_witness_penalty "$penalty"
pub cv_terms_measured "$LUS"
pub cv_terms_total "$NTEMOINS"
pub cv_terms_missing "${MANQUANTS:--}"
pub cv_partition_pm "$SOMME"

# LES BRUTS DES DEUX SOURCES. Le moissonneur garde la DERNIERE valeur d'une cle : les deux
# sources ont des prefixes distincts (`cv_` et `banc_`), aucun homonyme ne peut s'ecraser.
printf '%s\n' "$CV" | awk -F= '/^cv_[a-z0-9_]*=/ {print}'
printf '%s\n' "$BN" | awk -F= '/^banc_[a-z0-9_-]*=/ {print}'

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in lib/census/context-volume/collect.py lib/census/context-volume/selftest.py \
         lib/await.sh lib/cli_backend.py hooks/pre-tool.sh \
         lib/census/harness-main-agent-context-volume.sh; do
  k="cv_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
