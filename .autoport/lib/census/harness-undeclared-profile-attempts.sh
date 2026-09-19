#!/usr/bin/env bash
# census/harness-undeclared-profile-attempts.sh — LE VERDICT DE L'ITEM
# `harness-undeclared-profile-attempts` (2026-09-19).
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Il ne peut ecrire aucun champ de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent
# de la machine. Il relit les `cle=valeur` de `lib/undeclared_profile_selftest.py` et tranche.
#
# CE QU'IL MESURE, ET DANS QUEL ORDRE :
#   1. les 28 journaux sans modele sont CLASSES par voie de lancement    -> up_hist
#   2. le code livre REFUSE un profil non resolu, et NOMME le champ      -> up_refus
#   3. un profil RESOLU passe, et sa commande porte les deux modeles     -> up_positif
#   4. le code SANS le correctif, lui, ACCEPTE le vide                   -> up_ablation
#   5. la garde de non-regression existe, la nomme, et est VERTE         -> up_suite
#
# INCONNU = DEFAUT. Une clef manquante, un bras muet, une population vide : tout cela AJOUTE au
# compte. Sans cette polarite, une porte `== 0` serait verte par INACTION — il suffirait que le
# banc ne tourne pas.
#
# LA POPULATION HISTORIQUE N'EST PAS RECOPIEE ICI. Elle est relue a chaque course sur
# `.autoport/logs/*/attempt-*.jsonl` par le banc : un chiffre en dur dans ce fichier ne
# mesurerait que lui-meme. Le seul litteral de date du chantier est dans le banc, et c'est
# l'instant ou la DONNEE a ete corrigee (commit 50e9dc5af6), pas un seuil choisi.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "up_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

RAW=$(timeout -k 15 900 python3 "$AP/lib/undeclared_profile_selftest.py" 2>/dev/null)
g(){ printf '%s\n' "$RAW" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la clef manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(g "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }
pub(){ printf '%s=%s\n' "$1" "${2:--}"; }

penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }

# ================================================= 1. LES JOURNAUX, CLASSES PAR VOIE =========
# La porte de l'item : « les 28 journaux sont classes par voie de lancement (nommee) ». Un essai
# sans modele que le banc ne sait pas nommer compte pour un defaut, un par un.
t_hist=0
[ "$(n hist_journaux)" -ge 500 ] 2>/dev/null        || faute balayage-trop-maigre
[ "$(n hist_indeclares)" -ge 1 ] 2>/dev/null        || faute population-accusee-vide
NONCL=$(n hist_non_classes); [ "$NONCL" -ge 0 ] 2>/dev/null || NONCL=1
t_hist=$((t_hist + NONCL))
[ "$(n hist_voies)" -ge 1 ] 2>/dev/null             || t_hist=$((t_hist+1))
# 0 essai sans modele declare APRES le correctif, et le denominateur n'est pas vide : sans lui
# ce zero ne dirait rien (une population vide rend zero toute seule).
APRES=$(n hist_indeclares_apres_correctif); [ "$APRES" -ge 0 ] 2>/dev/null || APRES=1
t_hist=$((t_hist + APRES))
[ "$(n hist_journaux_apres_correctif)" -ge 100 ] 2>/dev/null || faute denominateur-posterieur-vide

# ================================================= 2. LE REFUS DANS LE CODE LIVRE ============
t_refus=0
for c in manager_model worker_model manager_effort; do
  [ "$(n "refus_codex_$c")" = 1 ] || t_refus=$((t_refus+1))
done
[ "$(n refus_codex_champs_nommes)" = 3 ]      || t_refus=$((t_refus+1))
[ "$(n refus_claude_strict)" = 1 ]            || t_refus=$((t_refus+1))
[ "$(n refus_claude_repli_se_denonce)" = 1 ]  || t_refus=$((t_refus+1))

# ================================================= 3. LE CONTROLE POSITIF ====================
# Un `codex_options` qui leverait sur TOUT rendrait les termes 2 et 4 verts sans rien prouver.
t_positif=0
[ "$(n positif_resolu_passe)" = 1 ]      || t_positif=$((t_positif+1))
[ "$(n positif_sous_agents)" = 1 ]       || t_positif=$((t_positif+1))
[ "$(n positif_model_occurrences)" = 1 ] || t_positif=$((t_positif+1))
[ "$(g positif_modele)" = "modele-de-banc" ] || t_positif=$((t_positif+1))

# ================================================= 4. LE BRAS D'AVANT ========================
# Le MEME profil casse, donne au `lib/cli_backend.py` du dernier commit SANS le marqueur
# (ancre par `lib/ablation_anchor.sh`, jamais par `HEAD:` ni par un compte de commits). Les
# deux bras au vert voudraient dire que la porte ne mesure rien.
t_ablation=0
[ "$(n ablation_ran)" = 1 ]                    || t_ablation=$((t_ablation+1))
[ "$(n ablation_accepte_le_vide)" = 1 ]        || t_ablation=$((t_ablation+1))
[ "$(n ablation_commande_sans_modele)" = 1 ]   || t_ablation=$((t_ablation+1))
[ "$(n ablation_champs_vides_acceptes)" = 3 ]  || t_ablation=$((t_ablation+1))

# ================================================= 5. LA GARDE ===============================
# On la rejoue ICI, sur ses deux fichiers. La porte de fermeture lancera la suite entiere, mais
# un item dont la garde est rouge ne doit pas attendre la fermeture pour le savoir. On lit le
# junit, jamais le seul code de retour : pytest rend 2, 3, 4 et 5 pour des causes qui ne sont
# pas un echec de test. Et on exige que LE test du point de production soit NOMME dedans : une
# suite verte dont la garde a ete retiree passerait sans lui.
GARDE="$AP/tests/harness/test_undeclared_profile.py"
GARDE2="$AP/tests/harness/test_cli_backend.py"
CLEF=test_aucun_journal_d_essai_ne_peut_naitre_sans_modele_declare
t_suite=0
if [ -f "$GARDE" ] && [ -f "$GARDE2" ]; then
  JX=$(mktemp -t up-junit-XXXXXX.xml)
  timeout -k 15 900 python3 -m pytest "$GARDE" "$GARDE2" -q --junitxml="$JX" >/dev/null 2>&1
  read -r STESTS SFAIL SERR SCLEF < <(python3 - "$JX" "$CLEF" <<'PY'
import sys, xml.etree.ElementTree as ET
try:
    r = ET.parse(sys.argv[1]).getroot()
    s = r if r.tag == 'testsuite' else r.find('testsuite')
    cas = [c for c in s.iter('testcase') if sys.argv[2] in (c.get('name') or '')]
    net = [c for c in cas if not len(list(c))]
    print(s.get('tests', '-1'), s.get('failures', '-1'), s.get('errors', '-1'), len(net))
except Exception:
    print('-1 -1 -1 -1')
PY
)
  rm -f "$JX"
  [ "${STESTS:--1}" -ge 30 ] 2>/dev/null || t_suite=$((t_suite+1))
  [ "${SFAIL:--1}" = 0 ] 2>/dev/null     || t_suite=$((t_suite+1))
  [ "${SERR:--1}" = 0 ] 2>/dev/null      || t_suite=$((t_suite+1))
  [ "${SCLEF:--1}" -ge 1 ] 2>/dev/null   || t_suite=$((t_suite+1))
else
  t_suite=4; faute garde-absente
  STESTS=-1; SFAIL=-1; SERR=-1; SCLEF=-1
fi

# ================================================= le banc a-t-il parle ? ====================
RAN=0
[ -n "$RAW" ] && [ "$(n hist_journaux)" -ge 0 ] 2>/dev/null && RAN=1
[ "$RAN" = 1 ] || faute banc-muet

TOTAL=$((t_hist + t_refus + t_positif + t_ablation + t_suite + penalty))

# ===================================================== la publication ========================
pub up_census_ran "$RAN"
pub undeclared_profile_defects "$TOTAL"
pub undeclared_profile_defects_terms \
  "journaux$t_hist+refus$t_refus+positif$t_positif+ablation$t_ablation+garde$t_suite+penalite$penalty${why:+:$why}"
pub up_hist "$t_hist"
pub up_refus "$t_refus"
pub up_positif "$t_positif"
pub up_ablation "$t_ablation"
pub up_suite "$t_suite"
pub up_witness_penalty "$penalty"
pub up_garde_tests "${STESTS:--1}"
pub up_garde_fail "${SFAIL:--1}"
pub up_garde_err "${SERR:--1}"
pub up_garde_test_du_point_de_production "${SCLEF:--1}"

# LES GRANDEURS BRUTES, recopiees telles quelles : c'est ce qui rend la somme falsifiable.
# Sous un prefixe a elles — le moissonneur garde la DERNIERE valeur d'une clef, un brut
# homonyme d'un terme du verdict ecraserait le terme.
printf '%s\n' "$RAW" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/up_raw_\1=/p'

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in orchestrator.py lib/model_profile.py lib/cli_backend.py \
         lib/undeclared_profile_selftest.py lib/ablation_anchor.sh \
         tests/harness/test_undeclared_profile.py tests/harness/test_cli_backend.py \
         lib/census/harness-undeclared-profile-attempts.sh; do
  k="up_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
