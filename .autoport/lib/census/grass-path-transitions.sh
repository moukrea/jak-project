#!/usr/bin/env bash
# census/grass-path-transitions.sh — CE QUE LA COURSE DE JEU NE PEUT PAS DIRE.
#
# La course x86 charge UN niveau et n'en voit qu'un : elle ne peut pas repondre a la question de
# l'item — « l'herbe s'arrete-t-elle progressivement au bord des chemins, PARTOUT » — parce que
# neuf des dix niveaux herbeux n'ont pas d'herbe a l'ecran (`kGrassLevels[] = {"training"}`,
# background_common.h:110) : leur `GrassRenderer::rebuild()` n'est jamais appele, donc aucune
# bande de transition n'existe cote moteur pour y etre mesuree.
#
# LE CODE EST LE MEME DES DEUX COTES. Le recensement de transition vit dans GrassBakeCore.cpp,
# compile a la fois dans `gk` et dans `tools/grass_bake`. On l'appelle ici hors ligne sur les dix
# niveaux, par la PORTE de l'arbre — qui repare `.ninja_deps` et sort en 4 sur un binaire plus
# vieux que ses entrees : ce bras ne peut donc pas etre un vieux binaire qui dirait un vieux vert.
#
# IL N'ECRIT RIEN DANS LA DONNEE LIVREE. `--transition-census` n'ouvre aucun fichier en ecriture,
# et les deux recuits du controle de determinisme tombent dans le bac a sable `$T`, jamais dans
# `out/jak1/fr3/`.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

# Les dix niveaux qui portent des textures de sol herbeux (SPEC-refonte-herbe.md, section 15).
LEVELS="training beach village1 village2 jungle rolling ogre swamp finalboss firecanyon"

T=$(mktemp -d "${TMPDIR:-/tmp}/grass-path-transitions.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
die(){ printf 'census grass-path-transitions: %s\n' "$*" >&2; exit 1; }

bash .autoport/lib/build_x86.sh --target grass_bake > "$T/build.log" 2>&1 \
  || die "build_x86.sh --target grass_bake a rendu $? (voir $T/build.log)"
BIN=build/tools/grass_bake/grass_bake
[ -x "$BIN" ] || die "$BIN absent apres la porte."

# ---- LES DIX NIVEAUX, UN PAR UN, `training` EN TETE. Un niveau absent, un outil qui echoue ou
# une sortie muette est NOMME dans `_levels_failed`, jamais absorbe en silence : un denominateur
# qui retrecit sans temoin rend n'importe quel zero vert.
OK=0; N=0; MISSING=""
for lvl in $LEVELS; do
  N=$((N + 1))
  if [ ! -s "out/jak1/fr3/$lvl.fr3" ]; then
    MISSING="${MISSING:+$MISSING,}$lvl:absent"
    continue
  fi
  if ! "$BIN" "$lvl" --preset medium --transition-census > "$T/$lvl.out" 2> "$T/$lvl.err"; then
    MISSING="${MISSING:+$MISSING,}$lvl:rc$?"
    continue
  fi
  grep '^trans_' "$T/$lvl.out" > "$T/$lvl.kv" 2>/dev/null
  if [ ! -s "$T/$lvl.kv" ]; then
    MISSING="${MISSING:+$MISSING,}$lvl:muet"
    continue
  fi
  OK=$((OK + 1))
done
echo "grass_transition_levels=$N"
echo "grass_transition_levels_ok=$OK"
echo "grass_transition_levels_list=$(printf '%s' "$LEVELS" | tr ' ' ',')"
echo "grass_transition_levels_failed=${MISSING:--}"

# ---- L'AGREGATION. Chaque terme est publie PAR NIVEAU puis somme ; la grandeur de la porte est
# la somme de termes qu'on peut relire un par un, jamais un chiffre isole. Un niveau auquel il
# MANQUE une cle n'est pas compte comme un zero : il devient `muet` et alimente `levels_missing`,
# parce qu'une valeur absente ne dit pas « zero », elle ne dit RIEN.
python3 - "$T" $LEVELS <<'PY' || die "l'agregation a echoue."
import os, sys
T = sys.argv[1]
levels = sys.argv[2:]

# Les termes ENTIERS publies par niveau puis sommes.
INT = ["blades_total", "blades_band", "blades_inside", "blades_tested", "blades_interior",
       "cand_total", "cand_inside", "cand_limit", "pos_mismatch",
       "gap_over_cap", "gap_cause_object", "gap_cause_inside", "gap_cause_nofloor",
       "gap_cause_nograss", "gap_cause_trans",
       "front_cells", "band_cells", "bare_draws_both", "bare_draws_geom", "bare_draws_mat",
       "bare_tris", "faces_up", "faces_affleurantes", "faces_lifted",
       "mono_ratio_breaks", "mono_height_breaks", "mono_dens_breaks",
       "dens_ramp_missing", "height_ramp_missing", "terms_measured"]
# Les grandeurs FLOTTANTES lues par niveau (jamais sommees : une moyenne de fractions ment).
FLT = ["gap_p50", "gap_p99", "gap_defect_frac", "gap_defect_max", "edge_follow", "graded_frac",
       "gap_defect_frac_cap", "gap_max_cap", "edge_follow_cap", "graded_floor", "ramp_max",
       "band_dens0", "band_dens3", "band_elig0", "band_elig3", "band_height0", "band_height3",
       "band_ratio0", "band_ratio3"]
# La table PAR NIVEAU que le contrat exige : le detail, pas seulement une somme.
PER = ["blades_total", "blades_band", "blades_inside", "cand_limit", "gap_p50", "gap_p99",
       "gap_defect_frac", "gap_defect_max", "gap_cause_object", "gap_cause_inside",
       "gap_cause_nofloor", "edge_follow", "graded_frac", "bare_draws_both", "bare_tris",
       "band_ratio0", "band_ratio3", "band_elig0", "band_elig3", "band_dens0", "band_dens3",
       "band_height0", "band_height3", "mono_dens_breaks", "mono_height_breaks",
       "dens_ramp_missing", "height_ramp_missing", "terms_measured"]
# Un niveau qui ne rend pas TOUTES ces cles n'est pas mesure. On refuse de le lire a zero.
REQ = set(INT) | set(FLT)

tot = {k: 0 for k in INT}
seen = 0
mute = []
gap_frac_bad = 0
gap_max_bad = 0
edge_follow_bad = 0
graded_bad = 0
unmeasured = 0
ramp_bad = 0
mono_dens_bad = 0
mono_h_bad = 0
grassless = []
band_bare_sum = 0     # blades_band, restreint aux niveaux qui ONT une empreinte de chemin
bare_levels = 0       # niveaux ou `bare_tris > 0` : sans eux, rien n'est mesurable

for lvl in levels:
    p = os.path.join(T, lvl + ".kv")
    if not os.path.exists(p):
        continue
    kv = {}
    for line in open(p, encoding="utf-8", errors="replace"):
        line = line.strip()
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        kv[k[len("trans_"):]] = v
    manque = [k for k in REQ if k not in kv]
    if manque:
        mute.append("%s:manque:%s" % (lvl, manque[0]))
        continue
    try:
        ints = {k: int(kv[k]) for k in INT}
        flts = {k: float(kv[k]) for k in FLT}
    except ValueError:
        mute.append("%s:illisible" % lvl)
        continue
    seen += 1
    for k in INT:
        tot[k] += ints[k]
    for k in PER:
        print("grass_transition_%s_%s=%s" % (lvl, k, kv[k]))
    # LES NOMS DE TEXTURE, PAR NIVEAU. Le contrat les exige : cacher qui borde le chemin serait
    # le defaut, pas un detail de presentation.
    print("grass_transition_%s_bare_tex_top=%s" % (lvl, kv.get("bare_tex_top", "-") or "-"))
    print("grass_transition_%s_bare_rej_top=%s" % (lvl, kv.get("bare_rej_top", "-") or "-"))
    print("grass_transition_%s_bare_mat_top=%s" % (lvl, kv.get("bare_mat_top", "-") or "-"))
    # Chaque seuil est celui que l'OUTIL publie, jamais une constante recopiee ici : un seuil
    # duplique dans le juge derive du code mesure et rend la porte fausse en silence.
    if flts["gap_defect_frac"] > flts["gap_defect_frac_cap"]:
        gap_frac_bad = 1
    if flts["gap_defect_max"] > flts["gap_max_cap"]:
        gap_max_bad = 1
    # `edge_follow` et `graded_frac` n'ont de sens que la ou leur population existe : les juger
    # sur zero cellule serait un vert par inaction.
    if ints["front_cells"] > 0 and flts["edge_follow"] > flts["edge_follow_cap"]:
        edge_follow_bad = 1
    if ints["band_cells"] > 0 and flts["graded_frac"] < flts["graded_floor"]:
        graded_bad = 1   # PUBLIE, HORS PORTE : voir la note sur le denominateur, plus bas.
    if ints["bare_tris"] > 0:
        bare_levels += 1
        band_bare_sum += ints["blades_band"]
    # ---- UN NIVEAU SANS AUCUN BRIN NE PORTE PAS DE TRANSITION, ET CE N'EST PAS UN DEFAUT.
    # Le moteur ne construit d'herbe que pour `kGrassLevels` (`training`) ; l'outil hors ligne, lui,
    # place sur tout niveau dont la texture correspond. Huit des dix niveaux rendent zero brin :
    # les compter « non mesures » ferait de l'absence d'herbe — le sujet de `grass-levels` — un
    # defaut de CET item. Ils sont NOMMES, ils ne sont pas juges.
    if ints["blades_total"] == 0:
        grassless.append(lvl)
        continue
    if ints["terms_measured"] < 4:
        unmeasured += 1
    # ---- POINT 4, SUR LE SEUL DENOMINATEUR QUE LA TRANSITION COMMANDE.
    # `band_ratio` divise par TOUS les candidats de la tranche. Sur `beach`, la part ELIGIBLE
    # (plancher et objet tenus) tombe de 0,3587 au bord a 0,1223 au fond de la bande : la
    # « densite » y decroissait a l'envers, et ce qu'elle mesurait etait le cull de plancher et
    # l'occultation d'objet, deux causes hors de cet item qui se renforcent pres d'un chemin.
    # `band_dens` divise par les eligibles ; il rend 0,7697 -> 0,9795 sur `beach` et
    # 0,7457 -> 0,9805 sur `training`. C'est LUI que la porte lit.
    mono_dens_bad += ints["mono_dens_breaks"]
    mono_h_bad += ints["mono_height_breaks"]
    ramp_bad += ints["dens_ramp_missing"] + ints["height_ramp_missing"]

for k in INT:
    print("grass_transition_%s=%d" % (k, tot[k]))
print("grass_transition_terms_measured_levels=%d" % seen)
print("grass_transition_levels_unparsed=%s" % (",".join(mute) if mute else "-"))
print("grass_transition_bare_levels=%d" % bare_levels)
print("grass_transition_levels_grassless=%s" % (",".join(grassless) if grassless else "-"))
print("grass_transition_levels_grassed=%d" % (seen - len(grassless)))
print("grass_transition_band_blades_on_bare_levels=%d" % band_bare_sum)

# ---- LES TERMES DE LA PORTE, PUBLIES SEPAREMENT PUIS SOMMES. Un chiffre unique ne se relit pas :
# ici chaque defaut a son nom, et la somme n'en cache aucun.
terms = {
    "invasion": tot["blades_inside"],
    "gap_frac": gap_frac_bad,
    "gap_max": gap_max_bad,
    "edge_follow": edge_follow_bad,
    "mono_dens": mono_dens_bad,
    "mono_height": mono_h_bad,
    "ramp_missing": ramp_bad,
    "pos_mismatch": tot["pos_mismatch"],
    "levels_missing": len(levels) - seen,
    # Temoins de non-vacuite : sans eux, tous les zeros ci-dessus seraient verts sans rien mesurer.
    "population_empty": 1 if tot["blades_total"] == 0 else 0,
    "band_empty": 1 if (bare_levels > 0 and band_bare_sum == 0) else 0,
    "bare_absent": 1 if bare_levels == 0 else 0,
    "grassed_absent": 1 if (seen - len(grassless)) == 0 else 0,
    "terms_unmeasured": unmeasured,
}
for k in sorted(terms):
    print("grass_transition_term_%s=%d" % (k, terms[k]))
# +1 : `determinisme` est mesure par le shell (deux recuits), il compte dans la porte.
print("grass_transition_terms=%d" % (len(terms) + 1))
open(os.path.join(T, "terms.txt"), "w").write(str(sum(terms.values())))
PY

TERMS=$(cat "$T/terms.txt" 2>/dev/null || echo 99)

# ---- POINT 4 DU CONTRAT : « DEUX CHARGEMENTS DONNENT LA MEME FRONTIERE AU BRIN PRES ».
# On ne l'affirme pas : on recuit `training` DEUX FOIS dans le bac a sable et on compare les
# OCTETS. Identique au bit = la frontiere ne depend ni d'un ordre de conteneur ni d'un aleatoire
# non graine. Rien n'est ecrit dans `out/jak1/fr3/`.
DET=1
if "$BIN" training --preset medium --out "$T/a.grassbake" > "$T/bake_a.log" 2>&1 \
   && "$BIN" training --preset medium --out "$T/b.grassbake" > "$T/bake_b.log" 2>&1; then
  BYTES=$(stat -c %s "$T/a.grassbake" 2>/dev/null || echo 0)
  if cmp -s "$T/a.grassbake" "$T/b.grassbake"; then SAME=1; DET=0; else SAME=0; fi
  echo "grass_transition_bake_identical=$SAME"
  echo "grass_transition_bake_bytes=$BYTES"
else
  # Un recuit qui echoue n'est pas « identique » : il ne dit rien, donc il compte comme defaut.
  echo "grass_transition_bake_identical=-1"
  echo "grass_transition_bake_bytes=0"
fi
echo "grass_transition_term_determinisme=$DET"

# ---- LA GRANDEUR DE LA PORTE : la somme des termes ci-dessus, et rien d'autre.
echo "grass_transition_defects=$((TERMS + DET))"
exit 0
