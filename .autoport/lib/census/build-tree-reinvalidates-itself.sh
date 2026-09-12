#!/usr/bin/env bash
# census/build-tree-reinvalidates-itself.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Sa sortie `cle=valeur` rejoint celle du moteur dans le meme journal. Il n'ecrit aucun champ de
# `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL MESURE, UN TERME PAR POINT DU LIVRABLE, CHAQUE TERME PUBLIE SEPAREMENT :
#   1. LA CAUSE NOMMEE    ce qui invalidait les 338 cibles, mesure AVANT, et REJOUE sur un arbre
#                         jetable pour montrer que c'est bien ce mecanisme-la    -> br_defaut_1
#   2. ZERO CIBLE         deux invocations consecutives sans edition, sur le VRAI arbre, par la
#                         porte, chacune publiee                                  -> br_defaut_2
#   3. LE LIEN            binaire contre CHACUNE de ses entrees directes, et la porte sort en 4
#                         sur un binaire perime — les DEUX bras joues             -> br_defaut_3
#   4. LE GAIN            secondes AVANT (journal de ninja du 12/09) contre APRES -> br_defaut_4
#
# TROIS SOURCES, jamais une seule :
#   - LA CAPTURE AVANT (`<id>.d/`), prise sur l'arbre DEFECTUEUX avant toute reparation, versionnee
#     et empreinte ici. C'est la sortie BRUTE de `ninja -d explain` et le `.ninja_log` de la
#     journee : personne ne peut la refaire une fois l'arbre repare, et la recopier a la main
#     serait ecrire soi-meme le chiffre qu'on veut lire.
#   - LE BANC (`lib/build_freshness_selftest.sh`) : le VRAI ninja et la VRAIE porte sur des etats
#     SEMES dans un arbre jetable, chaque jambe avec son controle. Il rejoue a chaque course.
#   - L'ARBRE VIVANT, MAINTENANT : trois invocations de la porte, ici, sur `build/`.
#
# INCONNU = DEFAUT. Toute cle manquante rend -1 (jamais 0, qui passerait une porte `== 0`) et
# ajoute au compte.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "br_census_ran=0"; exit 1; }
cd "$ROOT" || exit 1
AP="$ROOT/.autoport"
PORTE="$AP/lib/build_x86.sh"
BANC="$AP/lib/build_freshness_selftest.sh"
E="$AP/lib/census/capture-build-tree-reinvalidates-itself"

# Le moissonneur de proof_run.sh ne garde que `^cle=valeur$` SANS ESPACE : on colle les espaces
# ici, au point de publication, sinon la valeur est publiee pour personne.
pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }
# -1 quand la cle manque ou n'est pas un nombre.
num(){ case "${1:-}" in ''|*[!0-9-]*) echo -1 ;; *) echo "$1" ;; esac; }
g(){ printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1; }

pub br_census_ran 1

# ============================================================ 1. LA CAPTURE AVANT ============
# Empreinte des trois fichiers bruts : les editer se voit. Ils ne sont pas dans la liste de
# `lib/verdict_sources.sh` (elle ne suit que les `.sh` et les `.py`), donc leur empreinte est
# publiee ICI, a cote du chiffre qu'ils portent.
AV_EXPL="$E/avant-explain.txt"
AV_EDGE="$E/avant-edges.txt"
AV_LOG="$E/avant-ninja_log.txt"
AV_N=0
for f in "$AV_EXPL" "$AV_EDGE" "$AV_LOG"; do [ -s "$f" ] && AV_N=$((AV_N+1)); done
pub br_avant_fichiers "$AV_N"
pub br_avant_sha "$(cat "$AV_EXPL" "$AV_EDGE" "$AV_LOG" 2>/dev/null | sha256sum | cut -c1-16)"

if [ "$AV_N" = 3 ]; then
  AV_EDGES=$(grep -cE '^\[[0-9]+/[0-9]+\]' "$AV_EDGE" || true)
  AV_STALE=$(grep -c 'stored deps info out of date' "$AV_EXPL" || true)
  AV_MISS=$(grep -c 'deps for .* are missing' "$AV_EXPL" || true)
else
  AV_EDGES=-1; AV_STALE=-1; AV_MISS=-1
fi
pub br_avant_aretes            "$(num "$AV_EDGES")"
pub br_avant_enreg_perimes     "$(num "$AV_STALE")"
pub br_avant_enreg_absents     "$(num "$AV_MISS")"
pub br_cause "journal-de-dependances-illisible:les-enregistrements-ecrits-apres-la-coupure-ne-sont-jamais-relus"

# Les invocations que le journal de ninja du 12/09 a conservees. L'heure de depart d'une
# invocation se deduit de chaque ligne (`mtime - fin`), et les lignes d'une meme invocation se
# regroupent d'elles-memes : aucun decoupage a la main.
INV=$(python3 - "$AV_LOG" <<'PY' 2>/dev/null
import sys
rows = []
try:
    for ln in open(sys.argv[1]):
        if ln.startswith('#'):
            continue
        f = ln.rstrip('\n').split('\t')
        if len(f) != 5:
            continue
        rows.append((int(f[0]), int(f[1]), int(f[2])))
except Exception:
    sys.exit(1)
if not rows:
    sys.exit(1)
pts = sorted(((mt / 1e6 - en) / 1000.0, en / 1000.0) for st, en, mt in rows)
groups = [[pts[0]]]
for p in pts[1:]:
    if p[0] - groups[-1][-1][0] > 120:
        groups.append([])
    groups[-1].append(p)
for i, g in enumerate(groups[-2:], 1):
    print("inv%d_aretes=%d" % (i, len(g)))
    print("inv%d_s=%d" % (i, round(max(x[1] for x in g))))
PY
)
A1E=$(num "$(g "$INV" inv1_aretes)"); A1S=$(num "$(g "$INV" inv1_s)")
A2E=$(num "$(g "$INV" inv2_aretes)"); A2S=$(num "$(g "$INV" inv2_s)")
pub br_avant_inv1_aretes "$A1E"; pub br_avant_inv1_s "$A1S"
pub br_avant_inv2_aretes "$A2E"; pub br_avant_inv2_s "$A2S"

# ================================================================== 2. LE BANC ===============
BN=$(timeout 600 bash "$BANC" 2>/dev/null)
b(){ num "$(g "$BN" "$1")"; }
pub br_banc_ran           "$(b bf_banc_ran)"
pub br_banc_sain          "$(b bf_a_sain_2e_passe)"
pub br_banc_perime_objet  "$(b bf_b_abime_recompile)"
pub br_banc_perime_temoin "$(b bf_b_temoin_recompile)"
pub br_banc_perime_motif  "$(b bf_b_motif_ninja)"
pub br_banc_absent_aretes "$(b bf_c_sans_journal_aretes)"
pub br_banc_absent_motif  "$(b bf_c_motif_ninja)"
pub br_banc_queue_repare  "$(b bf_d_queue_retrecit)"
pub br_banc_porte_voit    "$(b bf_e_porte_a_vu_casse)"
pub br_banc_porte_repare  "$(b bf_e_porte_recompacte)"
pub br_banc_apres_aretes  "$(b bf_e_2e_passe_aretes)"
pub br_banc_lien_sain_rc  "$(b bf_f_sain_rc)"
pub br_banc_lien_perime_rc "$(b bf_f_perime_rc)"
pub br_banc_lien_perime_frais "$(b bf_f_perime_frais)"

# ========================================== 3. L'ARBRE VIVANT, TROIS INVOCATIONS =============
# La PREMIERE absorbe ce qui restait a faire (une regeneration cmake apres un commit, par
# exemple) : elle est publiee, elle n'est pas jugee. Les DEUX SUIVANTES sont les « deux
# invocations consecutives sans edition » du livrable, et elles doivent rendre zero.
P1=$(timeout 800 bash "$PORTE" --dir build --target gk 2>/dev/null); R1=$?
P2=$(timeout 300 bash "$PORTE" --dir build --target gk 2>/dev/null); R2=$?
P3=$(timeout 300 bash "$PORTE" --dir build --target gk 2>/dev/null); R3=$?
pub br_live_rc1 "$R1"; pub br_live_rc2 "$R2"; pub br_live_rc3 "$R3"
pub br_live_aretes1 "$(num "$(g "$P1" bx_edges)")"
pub br_live_aretes2 "$(num "$(g "$P2" bx_edges)")"
pub br_live_aretes3 "$(num "$(g "$P3" bx_edges)")"
pub br_live_s1 "$(num "$(g "$P1" bx_seconds)")"
pub br_live_s2 "$(num "$(g "$P2" bx_seconds)")"
pub br_live_s3 "$(num "$(g "$P3" bx_seconds)")"
# CE QUI A ETE RECOMPILE (`bx_work_edges`) et ce qui s'est seulement REJOUE (`bx_other_edges`,
# le menage de cmake et le clang-format de discord-rpc, 0,45 s). Deux comptes, jamais un seul :
# additionner les deux rendrait « zero cible » intenable pour une raison qui ne compile rien.
pub br_live_recompile1 "$(num "$(g "$P1" bx_work_edges)")"
pub br_live_recompile2 "$(num "$(g "$P2" bx_work_edges)")"
pub br_live_recompile3 "$(num "$(g "$P3" bx_work_edges)")"
pub br_live_menage3    "$(num "$(g "$P3" bx_other_edges)")"
pub br_live_menage_liste "$(g "$P3" bx_other_list)"
pub br_live_travail1 "$(num "$(g "$P1" bx_residual_work)")"
pub br_live_travail2 "$(num "$(g "$P2" bx_residual_work)")"
pub br_live_travail3 "$(num "$(g "$P3" bx_residual_work)")"
# Ce qui se rejoue par CONSTRUCTION et ne recompile rien : publie NOMME, jamais confondu avec
# une recompilation.
pub br_live_hors_compil "$(num "$(g "$P3" bx_residual_other)")"
pub br_live_hors_compil_liste "$(g "$P3" bx_residual_other_list)"
pub br_live_journal_casse "$(num "$(g "$P1" bx_deps_corrupt_before)")"
# Le lien, sur le vrai binaire.
pub br_live_bin        "$(g "$P3" bx_bin)"
pub br_live_bin_mtime  "$(num "$(g "$P3" bx_bin_mtime)")"
pub br_live_dep_mtime  "$(num "$(g "$P3" bx_newest_dep)")"
pub br_live_dep_nom    "$(g "$P3" bx_newest_name)"
pub br_live_dep_vues   "$(num "$(g "$P3" bx_deps_seen)")"
pub br_live_bin_frais  "$(num "$(g "$P3" bx_bin_fresh)")"
pub br_live_bin_retard "$(num "$(g "$P3" bx_bin_lag_s)")"

# ================================================================= 4. LES QUATRE TERMES =====
sup(){ [ "${1:--1}" -gt "${2:-0}" ] 2>/dev/null && echo 1 || echo 0; }

# 1. LA CAUSE. La capture AVANT doit porter les deux motifs en nombre, et le banc doit les
# rejouer TOUS LES DEUX avec leur controle : l'objet abime recompile, son voisin NON.
D1=0
[ "$(sup "$AV_EDGES" 0)" = 1 ] || D1=$((D1+1))
[ "$(sup "$AV_STALE" 0)" = 1 ] || D1=$((D1+1))
[ "$(sup "$AV_MISS" 0)" = 1 ]  || D1=$((D1+1))
[ "$(b bf_a_sain_2e_passe)" = 0 ]      || D1=$((D1+1))
[ "$(sup "$(b bf_b_abime_recompile)" 0)" = 1 ] || D1=$((D1+1))
[ "$(b bf_b_temoin_recompile)" = 0 ]   || D1=$((D1+1))
[ "$(sup "$(b bf_b_motif_ninja)" 0)" = 1 ]     || D1=$((D1+1))
[ "$(sup "$(b bf_c_sans_journal_aretes)" 0)" = 1 ] || D1=$((D1+1))
[ "$(sup "$(b bf_c_motif_ninja)" 0)" = 1 ]     || D1=$((D1+1))
[ "$(b bf_c_apres_reconstruction)" = 0 ] || D1=$((D1+1))
[ "$AV_N" = 3 ] || D1=$((D1+1))

# 2. ZERO CIBLE sur deux invocations consecutives du VRAI arbre, plus la meme demonstration sur
# l'arbre jetable une fois la porte passee.
D2=0
[ "$R1" = 0 ] && [ "$R2" = 0 ] && [ "$R3" = 0 ] || D2=$((D2+1))
[ "$(num "$(g "$P2" bx_work_edges)")" = 0 ] || D2=$((D2+1))
[ "$(num "$(g "$P3" bx_work_edges)")" = 0 ] || D2=$((D2+1))
[ "$(num "$(g "$P2" bx_residual_work)")" = 0 ] || D2=$((D2+1))
[ "$(num "$(g "$P3" bx_residual_work)")" = 0 ] || D2=$((D2+1))
[ "$(b bf_e_porte_a_vu_casse)" = 1 ] || D2=$((D2+1))
[ "$(b bf_e_2e_passe_aretes)" = 0 ]  || D2=$((D2+1))

# 3. LE LIEN. Sur le vrai binaire, et les DEUX bras de la porte sur l'arbre jetable : un bras
# seul serait vert par inaction.
D3=0
[ "$(num "$(g "$P3" bx_bin_fresh)")" = 1 ] || D3=$((D3+1))
[ "$(sup "$(num "$(g "$P3" bx_deps_seen)")" 0)" = 1 ] || D3=$((D3+1))
[ "$(b bf_f_sain_rc)" = 0 ]       || D3=$((D3+1))
[ "$(b bf_f_perime_rc)" = 4 ]     || D3=$((D3+1))
[ "$(b bf_f_perime_frais)" = 0 ]  || D3=$((D3+1))

# 4. LE GAIN, en secondes, compare a ce que le journal du 12/09 a garde. Pas de seuil invente :
# la plus LENTE des invocations d'apres doit rester sous la plus RAPIDE de celles d'avant.
AVMIN=-1
if [ "$A1S" -ge 0 ] 2>/dev/null && [ "$A2S" -ge 0 ] 2>/dev/null; then
  AVMIN=$A1S; [ "$A2S" -lt "$AVMIN" ] && AVMIN=$A2S
fi
APMAX=-1
for s in "$(num "$(g "$P1" bx_seconds)")" "$(num "$(g "$P2" bx_seconds)")" "$(num "$(g "$P3" bx_seconds)")"; do
  [ "$s" -gt "$APMAX" ] 2>/dev/null && APMAX=$s
done
pub br_avant_s_min "$AVMIN"
pub br_apres_s_max "$APMAX"
if [ "$AVMIN" -gt 0 ] 2>/dev/null && [ "$APMAX" -ge 0 ] 2>/dev/null && [ "$APMAX" -lt "$AVMIN" ]; then
  D4=0; pub br_gain_s $(( AVMIN - APMAX ))
else
  D4=1; pub br_gain_s -1
fi

pub br_defaut_1_cause  "$D1"
pub br_defaut_2_zero   "$D2"
pub br_defaut_3_lien   "$D3"
pub br_defaut_4_gain   "$D4"
pub build_reinvalidation_defects "$(( D1 + D2 + D3 + D4 ))"
