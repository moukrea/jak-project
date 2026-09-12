#!/usr/bin/env bash
# census/proof-context-on-zero-frames.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Il ne peut ecrire aucun champ de la machine : ni `sha`, ni `frames`, ni `crash`.
#
# CE QU'IL COMPTE, ET POURQUOI LES TROIS TERMES SONT NECESSAIRES.
#
#   1. LA COURSE COURANTE. Elle vient de tourner sur l'appareil branche. Son bloc de contexte
#      doit etre PRESENT et COMPLET — six temoins connus, leur carte des composants, un verdict.
#      C'est le seul terme qui mesure de VRAIES sondes sur un VRAI telephone : si la lecture de
#      `dumpsys window` casse sur cet appareil, ce terme rougit. Il ne depend pas de `frames` :
#      exiger le bloc SEULEMENT quand rien n'a ete dessine rendrait la course courante muette
#      des qu'elle dessine, c'est-a-dire toujours.
#
#   2. LES CONTROLES SEMES. Le corpus du depot ne contient AUCUNE preuve a `frames=0` : la
#      population que l'item doit couvrir est VIDE. Une porte posee sur elle seule serait verte
#      par INACTION, sans qu'une ligne de l'instrument ait tourne. Le banc seme donc les deux
#      populations dans un bac a sable jetable — des cas que le detecteur DOIT accuser, des cas
#      qu'il doit LAISSER passer — et chaque cas rate compte ici. Un banc qui ne tourne pas
#      compte pour un defaut : « pas de cas rate » et « pas de cas » ne se lisent pas pareil.
#
#   3. LE CORPUS REEL. Toutes les preuves du depot, les deux bras et les courses archivees.
#      Une preuve a zero image dont le producteur PORTAIT l'instrument et qui n'a pas de bloc
#      est le defaut lui-meme. Une preuve a zero image ANTERIEURE a l'instrument est comptee et
#      NOMMEE a part (`zfc_pop_zero_legacy`) : un seau exclu n'est pas un seau correct, et on
#      n'accuse pas un producteur qui n'existait pas. Aujourd'hui les deux valent zero — c'est
#      precisement pourquoi les termes 1 et 2 existent.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "zfc_ran=0"; exit 1; }
cd "$ROOT" || exit 1
AP="$ROOT/.autoport"
ID="${AUTOPORT_CENSUS_ID:-proof-context-on-zero-frames}"

pub(){ local v; v=$(printf '%s' "${2-}" | tr -s '[:space:]' '_'); [ -n "$v" ] || v='-'; printf '%s=%s\n' "$1" "$v"; }

LIB="$AP/lib/zf_context.sh"
if [ ! -s "$LIB" ] || ! . "$LIB" || ! declare -F zf_juger_preuve >/dev/null; then
  pub zfc_ran 0; pub zfc_lib_sourced 0
  # LA PORTE NE PEUT PAS ETRE VERTE SANS DETECTEUR : on publie un defaut, pas un silence.
  pub zero_frames_without_context 1
  exit 0
fi
pub zfc_ran 1
pub zfc_lib_sourced 1
pub zfc_lib_sha "$(sha256sum "$LIB" | cut -c1-16)"

# ================================================== 1. LA COURSE COURANTE ====================
CTX="${AUTOPORT_CENSUS_CONTEXT:-}"
c(){ [ -n "$CTX" ] && [ -s "$CTX" ] && sed -n "s/^$1=//p" "$CTX" | tail -1; }
absent=0; incomplet=0; muet=0; indep=0
if [ -z "$CTX" ] || [ ! -s "$CTX" ]; then
  absent=1; incomplet=1; muet=1; indep=1
else
  [ "$(c zf_context_present)" = 1 ] || absent=1
  [ "$(c zf_context_complete)" = 1 ] || incomplet=1
  vd=$(c zf_verdict)
  case "${vd:-}" in
    sans-objet|explique|exclut-le-systeme) ;;
    *) muet=1 ;;
  esac
  # L'INDEPENDANCE DOIT ETRE PUBLIEE, PAS SUPPOSEE. Sans la carte des composants et le compte
  # des paires qui en partagent un, deux temoins d'une MEME source se citeraient comme deux
  # voix — c'est la faute proximite+lumiere du 11/09, en toutes lettres.
  for k in zf_witness_map zf_witness_components zf_witness_shared_pairs \
           zf_verdict_independent zf_verdict_shared_pairs; do
    v=$(c "$k"); [ -n "$v" ] && [ "$v" != "-" ] || indep=1
  done
fi
COURSE_DEFAUT=$((absent + incomplet + muet + indep))
pub zfc_course_contexte_absent "$absent"
pub zfc_course_incomplet "$incomplet"
pub zfc_course_verdict_muet "$muet"
pub zfc_course_independance_non_publiee "$indep"
pub zfc_course_defaut "$COURSE_DEFAUT"
pub zfc_course_mode "$(c zf_context_mode)"
pub zfc_course_frames "$(c zf_frames)"
pub zfc_course_verdict "$(c zf_verdict)"
pub zfc_course_temoins_connus "$(c zf_witness_known)"
pub zfc_course_temoins_requis "$(c zf_witness_required)"
pub zfc_course_composants "$(c zf_witness_components)"
pub zfc_course_paires_partagees "$(c zf_witness_shared_pairs)"
pub zfc_course_marqueur "$(c zf_last_render_marker)"
pub zfc_course_carte "$(c zf_witness_map)"

# ================================================== 2. LES CONTROLES SEMES ===================
BANC=$(bash "$AP/lib/zf_context_selftest.sh" 2>/dev/null); BRC=$?
b(){ printf '%s\n' "$BANC" | sed -n "s/^$1=//p" | tail -1; }
num(){ local v; v=$(b "$1"); case "${v:-}" in ''|*[!0-9]*) echo -1 ;; *) echo "$v" ;; esac; }
BTOTAL=$(num banc_cas_total); BRATES=$(num banc_cas_rates); BPASSES=$(num banc_cas_passes)
BANC_DEFAUT=0
[ "$BRC" = 0 ] || BANC_DEFAUT=$((BANC_DEFAUT+1))
[ "$(b banc_ran)" = 1 ] || BANC_DEFAUT=$((BANC_DEFAUT+1))
[ "$(b banc_lib_sourced)" = 1 ] || BANC_DEFAUT=$((BANC_DEFAUT+1))
# UN BANC QUI N'A AUCUN CAS N'EST PAS UN BANC VERT. Le plancher est la population SEMEE, pas
# un nombre choisi : au moins un cas a accuser et un cas a laisser, sinon la porte est vide.
[ "${BTOTAL:-0}" -gt 0 ] 2>/dev/null || BANC_DEFAUT=$((BANC_DEFAUT+1))
if [ "${BRATES:-1}" -ge 0 ] 2>/dev/null; then BANC_DEFAUT=$((BANC_DEFAUT + BRATES))
else BANC_DEFAUT=$((BANC_DEFAUT+1)); fi
# LES DEUX CONTROLES QUI PORTENT LA POLARITE, NOMMES : un a traiter, un a laisser. S'ils
# disparaissent du banc, la porte ne mesure plus rien et elle le dit.
for cas in muette_detectee det_ampute_accusee det_legacy_laissee appop_laissee; do
  v=$(b "banc_cas_$cas"); [ "${v:-}" = ok ] || BANC_DEFAUT=$((BANC_DEFAUT+1))
  pub "zfc_banc_$cas" "${v:-absent}"
done
pub zfc_banc_rc "$BRC"
pub zfc_banc_cas_total "$BTOTAL"
pub zfc_banc_cas_passes "$BPASSES"
pub zfc_banc_cas_rates "$BRATES"
pub zfc_banc_lib_sha "$(b banc_lib_sha)"
pub zfc_banc_defaut "$BANC_DEFAUT"
printf '%s\n' "$BANC" | sed -n 's/^banc_cas_\([a-z_0-9]*\)=KO\(.*\)$/zfc_banc_rate_\1=KO\2/p'

# ================================================== 3. LE CORPUS REEL ========================
# LES NOMS DES BRAS VIENNENT DE L'AUTORITE (NOMMAGE/un-seul-endroit) : un nom de preuve
# retape ici passerait a cote d'un bras le jour ou il change.
NOMS=$(python3 "$AP/lib/impossible.py" name proof "" 2>/dev/null; \
       python3 "$AP/lib/impossible.py" name proof "-off" 2>/dev/null; \
       python3 "$AP/lib/impossible.py" name prev_proof "" 2>/dev/null; \
       python3 "$AP/lib/impossible.py" name prev_proof "-off" 2>/dev/null)
NOMS=$(printf '%s\n' "$NOMS" | grep -a . | sort -u)
pub zfc_pop_noms "$(printf '%s\n' "$NOMS" | paste -sd, -)"

tot=0; zero=0; expl=0; legacy=0; sans=0; autres=0
l_legacy=""; l_sans=""
for d in "$AP"/reports/*/; do
  [ -d "$d" ] || continue
  item=$(basename "$d")
  # LE DOSSIER DE CET ITEM EST ECARTE, ET ON LE DIT : `proof_run.sh` efface sa preuve au
  # DEMARRAGE, une population qui l'inclurait mesurerait un fichier absent, jamais une course.
  [ "$item" = "$ID" ] && continue
  while IFS= read -r nom; do
    [ -n "$nom" ] || continue
    f="$d$nom"
    [ -s "$f" ] || continue
    tot=$((tot+1))
    J=$(zf_juger_preuve "$f")
    cl=$(printf '%s\n' "$J" | sed -n 's/^zfd_classe=//p' | tail -1)
    case "$cl" in
      dessine) ;;
      zero-explique)      zero=$((zero+1)); expl=$((expl+1)) ;;
      zero-legacy)        zero=$((zero+1)); legacy=$((legacy+1)); l_legacy="${l_legacy:+$l_legacy,}$item/$nom" ;;
      zero-sans-contexte) zero=$((zero+1)); sans=$((sans+1));     l_sans="${l_sans:+$l_sans,}$item/$nom" ;;
      *) autres=$((autres+1)) ;;
    esac
  done <<< "$NOMS"
done
pub zfc_pop_proofs "$tot"
pub zfc_pop_zero "$zero"
pub zfc_pop_zero_explique "$expl"
pub zfc_pop_zero_legacy "$legacy"
pub zfc_pop_zero_legacy_list "${l_legacy:--}"
pub zfc_pop_zero_sans_contexte "$sans"
pub zfc_pop_zero_sans_contexte_list "${l_sans:--}"
pub zfc_pop_sans_frames "$autres"
# UN RECENSEMENT QUI NE LIT RIEN N'EST PAS UN RECENSEMENT VERT. Aucun plancher choisi : la
# seule affirmation est qu'il a lu au moins une preuve, sinon il ne mesure pas le corpus.
POP_DEFAUT=0
[ "$tot" -gt 0 ] || POP_DEFAUT=1
pub zfc_pop_defaut "$POP_DEFAUT"

# ================================================== LA PORTE =================================
TOTAL_DEFAUT=$((sans + COURSE_DEFAUT + BANC_DEFAUT + POP_DEFAUT))
pub zero_frames_without_context "$TOTAL_DEFAUT"
