#!/usr/bin/env bash
# census/harness-usage-double-counted.sh — LE VERDICT DE L'ITEM `harness-usage-double-counted`.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Il ne peut ecrire aucun champ de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent
# de la machine. Il relit les `cle=valeur` de `lib/usage_accounting_selftest.py` et tranche.
#
# CE QU'IL MESURE, ET DANS QUEL ORDRE :
#   1. le journal FABRIQUE rend le total ECRIT            -> uc_fixture
#   2. les journaux REELS tombent sur l'autorite a 1 %    -> uc_reels
#   3. le code SANS le correctif, lui, se trompe          -> uc_ablation
#   4. la garde de non-regression existe et est VERTE     -> uc_suite
#
# INCONNU = DEFAUT. Une clef manquante, un bras muet, une population qui n'atteint pas le
# regime accuse : tout cela AJOUTE au compte. Sans cette polarite, une porte `== 0` sur un
# compteur est verte par INACTION — il suffirait que le banc ne tourne pas.
#
# L'AUTORITE N'EST PAS RECALCULEE PAR LE CODE JUGE. La grandeur de reference est le
# `result.modelUsage` du DERNIER `result` de chaque journal, relu par une fonction a part
# (`autorite_du_journal`) : c'est ce que la CLI dit avoir FACTURE, pas une somme de notre cru.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "uc_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

RAW=$(python3 "$AP/lib/usage_accounting_selftest.py" 2>/dev/null)
g(){ printf '%s\n' "$RAW" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la clef manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(g "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }
pub(){ printf '%s=%s\n' "$1" "${2:--}"; }

penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }

# ============================================================ 1. LE JOURNAL FABRIQUE =========
# Son total attendu est ECRIT EN CLAIR dans le banc, il n'est pas recalcule avec la regle que
# l'on juge : un banc qui recalculerait l'attendu ne prouverait que sa propre coherence.
t_fixture=0
[ "$(n fixture_ok)" = 1 ]      || t_fixture=$((t_fixture+1))
[ "$(n sansresult_ok)" = 1 ]   || t_fixture=$((t_fixture+1))
[ "$(n legacy_ok)" = 1 ]       || t_fixture=$((t_fixture+1))
# Le flux fabrique doit VRAIMENT porter le defaut : quatre messages distincts, onze
# republications, trois `result`. Un flux sans doublon rendrait le bon total par accident.
[ "$(n fixture_dup_msgs)" -ge 10 ] 2>/dev/null || faute fixture-sans-doublon
[ "$(n fixture_results)" -ge 3 ] 2>/dev/null   || faute fixture-sans-cumul-republie
[ "$(g fixture_source)" = "result-modelusage" ] || faute fixture-mauvaise-autorite
[ "$(n fixture_cost_usd_x100)" = "$(n fixture_cost_attendu_x100)" ] || faute cout-faux

# ============================================================ 2. LES JOURNAUX REELS ==========
# Deux temoins choisis (un seul `result` sans sous-agent ; ONZE `result` republiant un cumul)
# et les trois essais les plus recents qui portent une autorite. Le seuil est celui de l'item.
t_reels=$(n reels_hors_seuil); [ "$t_reels" -ge 0 ] 2>/dev/null || t_reels=1
[ "$(n reels_n)" -ge 5 ] 2>/dev/null            || faute population-trop-maigre
[ "$(n reels_multi_results)" -ge 1 ] 2>/dev/null || faute aucun-essai-a-plusieurs-result
# Si AUCUN doublon n'a ete rencontre, le chemin de deduplication n'a pas tourne : le zero
# d'ecart ne dit alors rien du defaut qu'on corrige.
[ "$(n reels_dup_ignores)" -ge 100 ] 2>/dev/null || faute aucun-doublon-rencontre

# ============================================================ 3. LE BRAS D'AVANT ============
# Le MEME journal fabrique ET le MEME journal reel, lus par l'orchestrateur du dernier commit
# SANS ce correctif (ancre par MARQUEUR, `lib/ablation_anchor.sh`). Les deux bras au vert
# voudraient dire que la porte ne mesure rien.
t_ablation=0
[ "$(n ablation_ran)" = 1 ] || t_ablation=$((t_ablation+1))
[ "$(n ablation_ok)" = 0 ]  || t_ablation=$((t_ablation+1))    # 1 = le vieux code passe aussi
[ "$(n ablation_gonflement_pm)" -ge 100 ] 2>/dev/null || t_ablation=$((t_ablation+1))
[ "$(n ablation_reel_ecart_pm)" -ge 100 ] 2>/dev/null || t_ablation=$((t_ablation+1))

# ============================================================ 4. LA GARDE ====================
# La suite du harnais porte la non-regression. On la rejoue ICI, sur son seul fichier : la
# porte de fermeture la lancera entiere, mais un item dont la garde est rouge ne doit pas
# attendre la fermeture pour le savoir. On lit le junit, jamais le seul code de retour :
# pytest rend 2, 3, 4 et 5 pour « usage / collecte impossible / rien collecte ».
GARDE="$AP/tests/harness/test_usage_accounting.py"
t_suite=0
if [ -f "$GARDE" ]; then
  JX=$(mktemp -t uc-junit-XXXXXX.xml)
  timeout -k 15 600 python3 -m pytest "$GARDE" -q --junitxml="$JX" >/dev/null 2>&1
  read -r STESTS SFAIL SERR < <(python3 - "$JX" <<'PY'
import sys, xml.etree.ElementTree as ET
try:
    r = ET.parse(sys.argv[1]).getroot()
    s = r if r.tag == 'testsuite' else r.find('testsuite')
    print(s.get('tests', '-1'), s.get('failures', '-1'), s.get('errors', '-1'))
except Exception:
    print('-1 -1 -1')
PY
)
  rm -f "$JX"
  [ "${STESTS:--1}" -ge 9 ] 2>/dev/null || t_suite=$((t_suite+1))
  [ "${SFAIL:--1}" = 0 ] 2>/dev/null    || t_suite=$((t_suite+1))
  [ "${SERR:--1}" = 0 ] 2>/dev/null     || t_suite=$((t_suite+1))
else
  t_suite=3; faute garde-absente
  STESTS=-1; SFAIL=-1; SERR=-1
fi

# ============================================================ le banc a-t-il parle ? =========
RAN=0
[ -n "$RAW" ] && [ "$(n fixture_ok)" -ge 0 ] 2>/dev/null && RAN=1
[ "$RAN" = 1 ] || faute banc-muet

TOTAL=$((t_fixture + t_reels + t_ablation + t_suite + penalty))

# ================================================================== la publication ===========
pub uc_census_ran "$RAN"
pub usage_double_count_defects "$TOTAL"
pub usage_double_count_defects_terms \
  "fabrique$t_fixture+reels$t_reels+ablation$t_ablation+garde$t_suite+penalite$penalty${why:+:$why}"
pub uc_fixture "$t_fixture"
pub uc_reels "$t_reels"
pub uc_ablation "$t_ablation"
pub uc_suite "$t_suite"
pub uc_witness_penalty "$penalty"
pub uc_garde_tests "${STESTS:--1}"
pub uc_garde_fail "${SFAIL:--1}"
pub uc_garde_err "${SERR:--1}"

# LES GRANDEURS BRUTES, recopiees telles quelles : c'est ce qui rend la somme falsifiable.
# Sous un prefixe a elles — le moissonneur garde la DERNIERE valeur d'une clef, un brut
# homonyme d'un terme du verdict ecraserait le terme.
printf '%s\n' "$RAW" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/uc_raw_\1=/p'

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in orchestrator.py lib/cli_backend.py lib/usage_accounting_selftest.py \
         tests/harness/test_usage_accounting.py lib/census/harness-usage-double-counted.sh; do
  k="uc_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
