#!/usr/bin/env bash
# census/harness-supervisor-cost-counter.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Sa sortie `cle=valeur` rejoint celle du moteur. Il n'ecrit aucun champ de `proof.txt`.
#
# CE QU'IL MESURE, DANS L'ORDRE DE CE QUE L'ITEM DEMANDE :
#   1. LE COMPTEUR EXISTE ET SES DENOMINATEURS TIENNENT                  -> t_mesure
#   2. LA DECOMPOSITION NOMME LE POSTE LE PLUS CHER, CHIFFRE             -> t_decomposition
#   3. LE COMPTEUR EST PUBLIE, RELU PAR LE DIGEST, ET NE COUTE RIEN      -> t_publie
#   4. LE BANC : LE COMPTEUR MESURE JUSTE (cout connu, dedoublonnage,
#      lecture incrementale)                                             -> t_banc
#   5. LA VEILLE SANS MODELE EST ARMEE, ET ELLE NE PEUT PAS EFFACER UN
#      MESSAGE DE L'OWNER                                                -> t_veille
#   6. LE LEVIER DE CONTEXTE EST ARME, ET LE BRAS D'AVANT NE L'EST PAS   -> t_levier
#   7. LA GARDE QUI MORDRA : des que 3 jours de superviseur auront tourne
#      sous la configuration armee, la baisse devra etre la              -> t_apres
#
# DEUX SOURCES QUI NE SE RECOUVRENT PAS. `lib/supervisor_cost.py --recensement` ne mesure que
# ce qui a DEJA eu lieu (92 jours de transcriptions du superviseur) ; `lib/census/
# supervisor-cost/selftest.py` fait TOURNER les pieces livrees sur une transcription dont il
# connait le cout au cent pres et sur de vraies charges utiles de crochet. L'un dit combien le
# defaut coute, l'autre dit que le correctif marche.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte, et `-1` (cle
# absente) ne passe aucune porte `== 0`. Sans cette polarite, une porte `== 0` serait verte par
# INACTION : il suffirait que rien ne tourne.
#
# CE QUI EST PUBLIE SANS ETRE COMPTE, ET POURQUOI. La population « APRES » est vide le jour ou
# ce correctif est livre : le superviseur de l'owner tourne depuis le 17/06 et les deux leviers
# ne prennent effet qu'a son prochain demarrage. On publie `sc_apres_jours` et
# `sc_apres_mesurable` a cote du compte plutot que de fabriquer une baisse qui n'a pas ete
# mesuree. Des que trois jours armes existent, le terme 7 se met a compter TOUT SEUL, sans
# qu'une ligne de ce fichier change : c'est la garde de non-regression.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "sc_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

# LE MOISSONNEUR DE proof_run.sh NE GARDE QUE `^cle=valeur$` SANS ESPACE, et jette une valeur
# VIDE. On colle les espaces ICI, au point de publication, et le vide devient `-`.
pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }

SC=$(timeout -k 15 900 python3 "$AP/lib/supervisor_cost.py" \
        --rafraichir --tout --json --recensement 2>/dev/null)
BN=$(timeout -k 15 900 python3 "$AP/lib/census/supervisor-cost/selftest.py" 2>/dev/null)
TOUT=$(printf '\n%s\n%s\n' "$SC" "$BN")

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
memes(){ [ "$(n "$1")" = "$(n "$2")" ] && [ "$(n "$1")" != -1 ] && echo 0 || echo 1; }

[ -n "$SC" ] || faute compteur-muet
[ -n "$BN" ] || faute banc-muet
[ "$(n banc_ran)" = 1 ] || faute banc-n-a-pas-tourne
PANNE=$(s banc_panne); { [ -z "$PANNE" ] || [ "$PANNE" = "-" ]; } || faute "banc-en-panne:$PANNE"

# ================= 1. LE COMPTEUR EXISTE, ET SES DENOMINATEURS TIENNENT ======================
# LE DENOMINATEUR D'ABORD : une part calculee sur une population vide serait verte par cecite.
t_mesure=0
t_mesure=$((t_mesure + $(ge sc_sessions_superviseur 1)))
t_mesure=$((t_mesure + $(ge sc_jours 30)))
t_mesure=$((t_mesure + $(ge sc_requetes 5000)))
t_mesure=$((t_mesure + $(ge sc_cout_total_cents 100000)))
t_mesure=$((t_mesure + $(ge sc_cout_jour_cents 1000)))
t_mesure=$((t_mesure + $(ge sc_cout_essai_cents 20)))
t_mesure=$((t_mesure + $(ge sc_essais_recents 5)))
t_mesure=$((t_mesure + $(ge sc_prefixe_median_k 100)))
# LE DOSSIER DE TRANSCRIPTIONS N'EST PAS « LE SUPERVISEUR ». C'est la faute qui a fait annoncer
# 11 000 $ : 746 des 1 028 sessions sont des ESSAIS. Si le role « essai » n'est plus peuple, la
# separation ne marche plus et le total du superviseur redevient celui du dossier.
t_mesure=$((t_mesure + $(ge sc_role_essai_sessions 100)))
# TOUT CE QUI A DES JETONS A UN TARIF. Un modele neuf non tarife ferait SOUS-compter en silence.
t_mesure=$((t_mesure + $(eq sc_jetons_non_tarifes 0)))
# LE DEDOUBLONNAGE TIENT DANS SA FENETRE (16). Publie, pas suppose.
t_mesure=$((t_mesure + $(le sc_rid_ecart_max 8)))
# LA PARTITION FERME : lecture + ecriture + sortie + entree = 1000 pour mille.
SOMME=$(( $(n sc_part_lecture_pm) + $(n sc_part_ecriture_pm) \
        + $(n sc_part_sortie_pm) + $(n sc_part_entree_pm) ))
[ "$SOMME" -ge 990 ] && [ "$SOMME" -le 1010 ] 2>/dev/null || t_mesure=$((t_mesure + 1))
# ET LA RELECTURE DE CONTEXTE N'EST PAS A ZERO : c'est elle qu'on accuse, elle doit etre vue.
t_mesure=$((t_mesure + $(ge sc_part_lecture_pm 400)))

# ============ 2. LA DECOMPOSITION NOMME LE POSTE LE PLUS CHER, ET LE CHIFFRE =================
t_decomposition=0
SOMMEF=$(( $(n sc_famille_veille_pm) + $(n sc_famille_owner_pm) \
         + $(n sc_famille_fin_de_tache_pm) + $(n sc_famille_reprise_pm) \
         + $(n sc_famille_autre_pm) ))
[ "$SOMMEF" -ge 990 ] && [ "$SOMMEF" -le 1010 ] 2>/dev/null || t_decomposition=$((t_decomposition + 1))
t_decomposition=$((t_decomposition + $(ge sc_famille_veille_pm 300)))
t_decomposition=$((t_decomposition + $(ge sc_famille_veille_tours 1000)))
t_decomposition=$((t_decomposition + $(ge sc_veilles 1000)))
t_decomposition=$((t_decomposition + $(ge sc_veilles_par_jour_x10 100)))
t_decomposition=$((t_decomposition + $(ge sc_veille_cout_moyen_cents 10)))
t_decomposition=$((t_decomposition + $(ge sc_veilles_muettes 100)))
t_decomposition=$((t_decomposition + $(ge sc_famille_owner_tours 500)))
# DEUX TEMOINS INDEPENDANTS DU MEME FAIT : les reveils comptes par le TEXTE des prompts, et les
# `scheduled_task_fire` poses par Claude Code. S'ils divergent de plus de 20 %, l'un des deux
# ment et la decomposition ne repose plus sur rien.
V=$(n sc_veilles); P=$(n sc_reveils_programmes)
if [ "$V" -gt 0 ] && [ "$P" -gt 0 ] 2>/dev/null; then
  ECART=$(( (V - P) * 100 / V )); ECART=${ECART#-}
  [ "$ECART" -le 20 ] || t_decomposition=$((t_decomposition + 1))
else
  t_decomposition=$((t_decomposition + 1)); ECART=-1
fi

# ============ 3. LE COMPTEUR EST PUBLIE, RELU PAR LE DIGEST, ET NE COUTE RIEN ================
t_publie=0
# `autoport status` porte le bloc : on APPELLE le renderer (banc), on ne grep pas le fichier.
t_publie=$((t_publie + $(eq banc_status_porte_le_cout 1)))
t_publie=$((t_publie + $(eq banc_signature_stable 1)))
t_publie=$((t_publie + $(eq banc_signature_octets 64)))
# L'INSTANTANE MACHINE EXISTE ET DIT LA MEME CHOSE QUE LE RECENSEMENT.
INSTANT=$(python3 - <<'PY' 2>/dev/null
import json, os
p = os.path.join(".autoport", ".supervisor_cost.json")
try:
    d = json.load(open(p, encoding="utf-8"))
    print("instant_cents=%d" % round(d.get("total_usd", 0) * 100))
    print("instant_familles=%d" % len(d.get("familles") or {}))
    print("instant_jours=%d" % int(d.get("jours") or 0))
except Exception:
    print("instant_cents=-1"); print("instant_familles=-1"); print("instant_jours=-1")
PY
)
TOUT=$(printf '%s\n%s\n' "$TOUT" "$INSTANT")
t_publie=$((t_publie + $(ge instant_familles 4)))
t_publie=$((t_publie + $(memes instant_jours sc_jours)))
D=$(( $(n instant_cents) - $(n sc_cout_total_cents) )); D=${D#-}
[ "$D" -le 100 ] 2>/dev/null || t_publie=$((t_publie + 1))
# LE CHEMIN QUE LE DIGEST EMPRUNTE RESTE GRATUIT : une relecture incrementale, pas 2 Go.
t_publie=$((t_publie + $(le sc_cache_ms 30000)))
t_publie=$((t_publie + $(eq sc_cache_sautes 0)))
# ET IL NE VOLE PAS LA NOTIFICATION DU SUPERVISEUR.
t_publie=$((t_publie + $(eq banc_memo_digest_intact 1)))

# ================== 4. LE BANC : LE COMPTEUR MESURE JUSTE ===================================
t_banc=0
t_banc=$((t_banc + $(eq banc_compteur_rc 0)))
t_banc=$((t_banc + $(memes banc_cout_cents banc_cout_attendu_cents)))
t_banc=$((t_banc + $(memes banc_prefixe_median_k banc_prefixe_median_attendu_k)))
# LE DEDOUBLONNAGE N'EST PAS DECORATIF : l'ecart est CHIFFRE, pas suppose.
t_banc=$((t_banc + $(ge banc_cout_sans_dedoublonnage_cents 200)))
t_banc=$((t_banc + $(eq banc_rid_ecart_max 1)))
# LA LECTURE INCREMENTALE REND LE MEME CHIFFRE QUE LA PASSE UNIQUE, avec une coupure AU MILIEU
# D'UNE LIGNE — et la premiere moitie doit avoir vu MOINS, sinon la coupure n'a rien coupe.
t_banc=$((t_banc + $(memes banc_incremental_cents banc_cout_cents)))
A=$(n banc_incremental_moitie_cents); B=$(n banc_cout_cents)
[ "$A" -lt "$B" ] 2>/dev/null && [ "$A" -gt 0 ] || t_banc=$((t_banc + 1))
t_banc=$((t_banc + $(memes banc_incremental_veilles banc_veilles)))
# LES FAMILLES SONT ATTRIBUEES, ET PAS TOUTES AU MEME SEAU.
t_banc=$((t_banc + $(eq banc_veilles 2)))
t_banc=$((t_banc + $(eq banc_veilles_muettes 1)))
t_banc=$((t_banc + $(eq banc_famille_veille_cents 25)))
t_banc=$((t_banc + $(eq banc_famille_owner_cents 117)))
t_banc=$((t_banc + $(eq banc_famille_tache_cents 3)))
t_banc=$((t_banc + $(eq banc_sessions_superviseur 1)))
t_banc=$((t_banc + $(eq banc_role_essai_sessions 1)))
t_banc=$((t_banc + $(eq banc_jetons_non_tarifes 0)))

# ====== 5. LA VEILLE EST ARMEE, ET ELLE NE PEUT PAS EFFACER UN MESSAGE DE L'OWNER ===========
t_veille=0
t_veille=$((t_veille + $(memes banc_veille_reconnues banc_veille_charges)))
t_veille=$((t_veille + $(ge banc_veille_charges 4)))
t_veille=$((t_veille + $(ge banc_veille_charges_jamais 4)))
t_veille=$((t_veille + $(eq banc_veille_faux_positifs 0)))
t_veille=$((t_veille + $(eq banc_veille_refus_interdits 0)))
# LA VRAIE POPULATION, pas cinq exemples : tous les messages tapes par l'owner dans la session
# du superviseur. UN SEUL efface serait un defaut inacceptable.
t_veille=$((t_veille + $(eq banc_population_faux_positifs 0)))
t_veille=$((t_veille + $(ge banc_population_owner 500)))
t_veille=$((t_veille + $(ge banc_population_reveils_detectes 3000)))
# LES DEUX BRAS : rien n'a bouge -> refus ; quelque chose a bouge -> passage.
t_veille=$((t_veille + $(memes banc_veille_refus_sur_etat_inchange banc_veille_charges)))
t_veille=$((t_veille + $(eqs banc_veille_etat_change passe)))
t_veille=$((t_veille + $(eqs banc_veille_etat_change_raison etat-change)))
t_veille=$((t_veille + $(eqs banc_veille_echeance passe)))
t_veille=$((t_veille + $(eqs banc_veille_premier_passage passe)))
# LE REVEIL QUI PASSE EMPORTE CE QUE LA VEILLE A DEJA MESURE : sinon le modele le refait.
t_veille=$((t_veille + $(ge banc_veille_etat_change_contexte_octets 500)))
# L'ECHEC EST OUVERT : une veille cassee ne peut pas faire taire le superviseur.
t_veille=$((t_veille + $(eqs banc_veille_echec_ouvert passe)))
# LE CROCHET, LANCE COMME CLAUDE CODE LE LANCERA : 2 = refus, 0 = laisse passer.
t_veille=$((t_veille + $(eq banc_crochet_rc 2)))
t_veille=$((t_veille + $(eq banc_crochet_owner_rc 0)))
t_veille=$((t_veille + $(eq banc_crochet_owner_sortie_octets 0)))
# ELLE TOURNE AVANT CHAQUE PROMPT : elle doit rester rapide.
t_veille=$((t_veille + $(le banc_veille_ms_max 2000)))
# ET ELLE EST DECLAREE DANS LE FICHIER QUI EST LIVRE, pas seulement en local.
t_veille=$((t_veille + $(eq banc_crochet_declare 1)))
t_veille=$((t_veille + $(eq banc_settings_suivi_par_git 1)))

# ============ 6. LE LEVIER DE CONTEXTE EST ARME, ET LE BRAS D'AVANT NE L'EST PAS =============
t_levier=0
t_levier=$((t_levier + $(entre banc_lanceur_autocompact 100000 1000000)))
t_levier=$((t_levier + $(eq banc_lanceur_autocompact_dans_exec 1)))
t_levier=$((t_levier + $(eq banc_lanceur_journal 1)))
t_levier=$((t_levier + $(eq banc_lanceur_pose_1m 0)))
# LA VALEUR EST ACCEPTEE PAR LE BINAIRE — on l'a lance — et une valeur absurde est REFUSEE.
t_levier=$((t_levier + $(eq banc_cli_accepte_valeur 0)))
[ "$(n banc_cli_refuse_absurde)" != 0 ] || t_levier=$((t_levier + 1))
# LE BRAS D'AVANT EST L'ABSENCE, ancre sur le commit qui precede l'introduction du marqueur.
t_levier=$((t_levier + $(eq banc_avant_porte_le_marqueur 0)))
t_levier=$((t_levier + $(ge banc_avant_octets 1000)))

# ============ 7. LA GARDE QUI MORDRA PLUS TARD — ET QUI LE DIT AUJOURD'HUI ===================
# La population « APRES » est celle des jours de superviseur posterieurs au premier lancement
# enregistre AVEC `autocompact` : c'est la configuration elle-meme qui les designe, pas un
# seuil sur une grandeur qui derive. Tant qu'il y en a moins de trois, ce terme ne compte pas
# et le DIT.
t_apres=0
if [ "$(n sc_apres_mesurable)" = 1 ]; then
  t_apres=$((t_apres + $(ge sc_baisse_prefixe_pm 300)))
  t_apres=$((t_apres + $(le sc_apres_prefixe_median_k 250)))
fi

TOTAL=$((t_mesure + t_decomposition + t_publie + t_banc + t_veille + t_levier + t_apres + penalty))

# ====================================== COMBIEN DE TEMOINS ONT VRAIMENT ETE LUS ? ============
# UNE SOMME A ZERO SUR DES TERMES AVEUGLES EST LE FAUX VERT LE PLUS CHER. La liste ci-dessous
# est le contrat de ce verdict : chaque cle qu'un terme interroge. On publie COMBIEN ont ete
# lues et on NOMME celles qui manquent. Recherche par filtrage de motif, SANS TUBE : `grep -q`
# sous `pipefail` rend 141 sur un SIGPIPE et la condition devient fausse sur une population qui
# PORTE le motif.
TEMOINS="sc_sessions_superviseur sc_jours sc_requetes sc_cout_total_cents sc_cout_jour_cents
sc_cout_jour_recent_cents sc_cout_essai_cents sc_essais_recents sc_prefixe_median_k
sc_prefixe_median_recent_k sc_part_lecture_pm sc_part_ecriture_pm sc_part_sortie_pm
sc_part_entree_pm sc_famille_veille_pm sc_famille_veille_tours sc_famille_veille_cents
sc_famille_owner_pm sc_famille_owner_tours sc_famille_fin_de_tache_pm sc_famille_reprise_pm
sc_famille_autre_pm sc_veilles sc_veilles_muettes sc_veilles_par_jour_x10
sc_veille_cout_moyen_cents sc_reveils_programmes sc_rid_ecart_max sc_modeles_inconnus
sc_jetons_non_tarifes sc_ecriture_sans_ttl sc_role_essai_sessions sc_role_atelier_sessions
sc_cache_ms sc_cache_sautes sc_lancements_armes sc_arme_depuis sc_apres_jours
sc_apres_mesurable sc_apres_prefixe_median_k sc_baisse_prefixe_pm instant_cents
instant_familles instant_jours banc_ran banc_panne banc_compteur_rc banc_cout_cents
banc_cout_attendu_cents banc_cout_sans_dedoublonnage_cents banc_prefixe_median_k
banc_prefixe_median_attendu_k banc_veilles banc_veilles_muettes banc_famille_veille_cents
banc_famille_owner_cents banc_famille_tache_cents banc_role_essai_sessions
banc_sessions_superviseur banc_rid_ecart_max banc_jetons_non_tarifes
banc_incremental_moitie_cents banc_incremental_cents banc_incremental_veilles
banc_coupure_octets banc_veille_charges banc_veille_charges_jamais banc_veille_reconnues
banc_veille_faux_positifs banc_veille_premier_passage banc_veille_refus_sur_etat_inchange
banc_veille_ms_max banc_veille_etat_change banc_veille_etat_change_raison
banc_veille_etat_change_contexte_octets banc_veille_echeance banc_veille_refus_interdits
banc_veille_echec_ouvert banc_crochet_rc banc_crochet_owner_rc banc_crochet_owner_sortie_octets
banc_memo_digest_intact banc_population_owner banc_population_injectes
banc_population_faux_positifs banc_population_reveils_detectes banc_lanceur_autocompact
banc_lanceur_autocompact_dans_exec banc_lanceur_journal banc_lanceur_pose_1m
banc_cli_accepte_valeur banc_cli_refuse_absurde banc_avant_commit banc_avant_octets
banc_avant_porte_le_marqueur banc_settings_suivi_par_git banc_crochet_declare
banc_status_porte_le_cout banc_signature_stable banc_signature_octets"
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
pub sc_census_ran "$([ "$(n banc_ran)" = 1 ] && [ -n "$SC" ] && echo 1 || echo 0)"
pub supervisor_cost_defects "$TOTAL"
pub supervisor_cost_terms \
  "mesure$t_mesure+decomposition$t_decomposition+publie$t_publie+banc$t_banc+veille$t_veille+levier$t_levier+apres$t_apres+penalite$penalty${why:+:$why}"
pub sc_t_mesure "$t_mesure"
pub sc_t_decomposition "$t_decomposition"
pub sc_t_publie "$t_publie"
pub sc_t_banc "$t_banc"
pub sc_t_veille "$t_veille"
pub sc_t_levier "$t_levier"
pub sc_t_apres "$t_apres"
pub sc_witness_penalty "$penalty"
pub sc_terms_measured "$LUS"
pub sc_terms_total "$NTEMOINS"
pub sc_terms_missing "${MANQUANTS:--}"
pub sc_partition_pm "$SOMME"
pub sc_familles_pm "$SOMMEF"
pub sc_ecart_temoins_veille_pct "$ECART"

# LES BRUTS DES TROIS SOURCES. Le moissonneur garde la DERNIERE valeur d'une cle : les sources
# ont des prefixes distincts (`sc_`, `banc_`, `instant_`), aucun homonyme ne peut s'ecraser.
printf '%s\n' "$SC" | awk -F= '/^sc_[a-z0-9_]*=/ {print}'
printf '%s\n' "$BN" | awk -F= '/^banc_[a-z0-9_]*=/ {print}'
printf '%s\n' "$INSTANT" | awk -F= '/^instant_[a-z0-9_]*=/ {print}'

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in lib/supervisor_cost.py lib/wake_gate.py hooks/user-prompt.sh supervisor.sh \
         lib/census/supervisor-cost/selftest.py lib/census/supervisor-cost/charges.json \
         lib/census/harness-supervisor-cost-counter.sh; do
  k="sc_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
pub sc_sha__claude_settings_json "$(sha256sum "$ROOT/.claude/settings.json" 2>/dev/null | cut -c1-16)"
