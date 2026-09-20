#!/usr/bin/env bash
# census/grass-blade-variants.sh — CE QUE LA COURSE DE JEU NE PEUT PAS DIRE.
#
# La course appareil charge UN niveau a UN palier. Trois des quatre points du livrable ne s'y
# mesurent pas : la distribution sur les dix niveaux herbeux, la STABILITE de la variante d'un
# palier a l'autre (il faudrait deux courses), et l'accord entre la table GLSL et la table C++. Le
# recensement passe donc le MEME code — `grass_bake::variant_census` / `variant_nest`, compile a la
# fois dans `gk` et dans `tools/grass_bake` — hors ligne, par la PORTE de l'arbre.
#
# CE QU'IL NE PEUT PAS FAIRE SEUL, ET QU'IL NE PRETEND PAS FAIRE. Il rendrait ses zeros meme si la
# course appareil n'avait affiche AUCUN brin : il lit donc le temoin que SEUL le moteur ecrit, dans
# le journal de CETTE course, et il compare l'EMPREINTE du moteur a la sienne.
#
# IL N'ECRIT RIEN DANS LA DONNEE LIVREE : aucune option utilisee ici n'ouvre un fichier en ecriture.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

# Les dix niveaux qui portent des textures de sol herbeux (SPEC-refonte-herbe.md, section 15).
LEVELS="training beach village1 village2 jungle rolling ogre swamp finalboss firecanyon"
# Le palier de la course livree (backlog `proof_props: debug.opengoal.grass.preset=2`).
PRESET=medium

T=$(mktemp -d "${TMPDIR:-/tmp}/grass-variants.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
die(){ printf 'census grass-blade-variants: %s\n' "$*" >&2; exit 1; }

bash .autoport/lib/build_x86.sh --target grass_bake > "$T/build.log" 2>&1 \
  || die "build_x86.sh --target grass_bake a rendu $? (voir $T/build.log)"
BIN=build/tools/grass_bake/grass_bake
[ -x "$BIN" ] || die "$BIN absent apres la porte."

# ---- LES DIX NIVEAUX. Un niveau absent, un outil qui echoue ou une sortie muette est NOMME dans
# `_levels_failed`, jamais absorbe : un denominateur qui retrecit sans temoin rend tout zero vert.
OK=0; N=0; MISSING=""
for lvl in $LEVELS; do
  N=$((N + 1))
  if [ ! -s "out/jak1/fr3/$lvl.fr3" ]; then
    MISSING="${MISSING:+$MISSING,}$lvl:absent"; continue
  fi
  if ! "$BIN" "$lvl" --preset "$PRESET" --variant-census > "$T/$lvl.out" 2> "$T/$lvl.err"; then
    MISSING="${MISSING:+$MISSING,}$lvl:rc$?"; continue
  fi
  grep '^variant_' "$T/$lvl.out" > "$T/$lvl.kv" 2>/dev/null
  if [ ! -s "$T/$lvl.kv" ]; then
    MISSING="${MISSING:+$MISSING,}$lvl:muet"; continue
  fi
  OK=$((OK + 1))
done
echo "grass_variant_levels=$N"
echo "grass_variant_levels_ok=$OK"
echo "grass_variant_levels_list=$(printf '%s' "$LEVELS" | tr ' ' ',')"
echo "grass_variant_levels_failed=${MISSING:--}"

# ---- POINT 3 DU LIVRABLE : « un brin donne recoit la meme variante a TOUS les paliers qui la
# proposent ». Trois jambes, choisies pour que le support commun soit de taille differente a chaque
# fois : 1 variante contre 6, 2 contre 6, 4 contre 6. Une jambe qui ne tourne pas ne dit pas « zero »,
# elle ne dit RIEN — elle compte comme defaut. Une jambe qui compare ZERO brin aussi.
NEST_CHANGED=0; NEST_LEGS=0; NEST_CMP=0; NEST_MISSING=0; NEST_DUP=0
for pair in "very-low:very-high" "low:high" "medium:very-high"; do
  lo=${pair%%:*}; hi=${pair##*:}
  if "$BIN" training --preset "$lo" --variant-nest "$hi" > "$T/nest-$lo-$hi.out" 2>&1; then
    c=$(grep -m1 '^variant_nest_compared=' "$T/nest-$lo-$hi.out" | cut -d= -f2)
    x=$(grep -m1 '^variant_nest_changed=' "$T/nest-$lo-$hi.out" | cut -d= -f2)
    m=$(grep -m1 '^variant_nest_missing=' "$T/nest-$lo-$hi.out" | cut -d= -f2)
    f=$(grep -m1 '^variant_nest_folded=' "$T/nest-$lo-$hi.out" | cut -d= -f2)
    u=$(grep -m1 '^variant_nest_dup=' "$T/nest-$lo-$hi.out" | cut -d= -f2)
    if [ -n "${c:-}" ] && [ -n "${x:-}" ] && [ -n "${m:-}" ]; then
      NEST_LEGS=$((NEST_LEGS + 1))
      NEST_CHANGED=$((NEST_CHANGED + x)); NEST_CMP=$((NEST_CMP + c))
      NEST_MISSING=$((NEST_MISSING + m))
      echo "grass_variant_nest_${lo}_${hi}_compared=$c"
      echo "grass_variant_nest_${lo}_${hi}_changed=$x"
      echo "grass_variant_nest_${lo}_${hi}_folded=${f:--}"
      echo "grass_variant_nest_${lo}_${hi}_missing=$m"
      echo "grass_variant_nest_${lo}_${hi}_dup=${u:--}"
      NEST_DUP=$((NEST_DUP + ${u:-0}))
    fi
  fi
done
echo "grass_variant_nest_legs=$NEST_LEGS"
echo "grass_variant_nest_compared=$NEST_CMP"
echo "grass_variant_nest_changed=$NEST_CHANGED"
echo "grass_variant_nest_missing=$NEST_MISSING"
# RACINES EN DOUBLE, EXCLUES ET COMPTEES. L'ecretage de touffe ramene quelques brins EXACTEMENT sur
# l'origine de leur touffe : la racine n'y identifie plus un brin. Les apparier mesurerait
# l'ecretage. Le nombre est publie pour qu'il ne grossisse pas en silence.
echo "grass_variant_nest_dup=$NEST_DUP"
NEST_MUTE=$((3 - NEST_LEGS))
NEST_EMPTY=0
[ "$NEST_CMP" -gt 0 ] || NEST_EMPTY=1

# ---- AGREGATION + LES DEUX TABLES. La table de forme vit dans `shaders/grass.vert` (le seul
# consommateur), le nombre de segments aussi dans `grass_blade_variants.h` (le seul qui en fasse un
# budget de sommets). C'est une duplication ; elle est donc MESUREE, pas supposee : on relit la
# table GLSL et on la compare a ce que l'OUTIL publie depuis la table C++.
python3 - "$T" "$PRESET" $LEVELS <<'PY' || die "l'agregation a echoue."
import os, re, sys
T, PRESET = sys.argv[1], sys.argv[2]
levels = sys.argv[3:]

NV = 6
SCALARS = ["blades", "k", "preset", "folded", "off_profile", "verts_strip", "verts_max",
           "verts_over", "verts_active_total", "verts_strip_total", "terms_measured", "count",
           # ESSAI 2 : les grandeurs de TOUFFE. Une seule absente NOMME le niveau au lieu de
           # laisser la porte sommer des zeros qu'elle n'a pas mesures.
           "blades_clumped", "clumps", "clumps_dominant", "dominant_pm", "dominant_pm_floor",
           "dominant_share_pm", "height_cv_pm", "height_cv_pm_floor", "height_mean_mm",
           "neigh_compared", "neigh_diff", "neigh_diff_pm", "neigh_diff_pm_floor",
           "seg_angle_max_mdeg", "seg_angle_cap_mdeg", "seg_angle_over", "variants_seen"]
PERV = ["v%d", "base_v%d", "share_pm_v%d", "expect_pm_v%d", "tol_pm_v%d", "seg_v%d"]

seen, mute, grassless = 0, [], []
tot = {k: 0 for k in ("blades", "folded", "off_profile", "verts_over",
                      "verts_active_total", "verts_strip_total")}
budget_bad, unmeasured, k_bad = 0, 0, 0
dom_bad, hcv_bad, neigh_bad, angle_bad, submitted_bad, clumpless = 0, 0, 0, 0, 0, 0
angle_over_tot = 0
per_v_tot = [0] * NV
train = {}

for lvl in levels:
    p = os.path.join(T, lvl + ".kv")
    if not os.path.exists(p):
        continue
    kv = {}
    for line in open(p, encoding="utf-8", errors="replace"):
        line = line.strip()
        if "=" in line:
            a, b = line.split("=", 1)
            kv[a[len("variant_"):]] = b
    req = list(SCALARS) + [f % v for f in PERV for v in range(NV)]
    manque = [k for k in req if k not in kv]
    if manque:
        mute.append("%s:manque:%s" % (lvl, manque[0]))
        continue
    try:
        num = {k: int(kv[k]) for k in req}
    except ValueError:
        mute.append("%s:illisible" % lvl)
        continue
    seen += 1
    if lvl == "training":
        train = dict(kv)
    for k in ("blades", "folded", "off_profile", "verts_over",
              "verts_active_total", "verts_strip_total"):
        tot[k] += num[k]
    for v in range(NV):
        per_v_tot[v] += num["v%d" % v]
        print("grass_variant_%s_v%d=%d" % (lvl, v, num["v%d" % v]))
        print("grass_variant_%s_share_pm_v%d=%d" % (lvl, v, num["share_pm_v%d" % v]))
        print("grass_variant_%s_expect_pm_v%d=%d" % (lvl, v, num["expect_pm_v%d" % v]))
        print("grass_variant_%s_tol_pm_v%d=%d" % (lvl, v, num["tol_pm_v%d" % v]))
    for k in ("blades", "k", "folded", "off_profile", "verts_max", "verts_over",
              "terms_measured", "blades_clumped", "clumps", "clumps_dominant", "dominant_pm",
              "dominant_pm_floor", "dominant_share_pm", "height_cv_pm", "height_cv_pm_floor",
              "height_mean_mm", "neigh_compared", "neigh_diff", "neigh_diff_pm",
              "neigh_diff_pm_floor", "seg_angle_max_mdeg", "seg_angle_cap_mdeg",
              "seg_angle_over", "variants_seen"):
        print("grass_variant_%s_%s=%d" % (lvl, k, num[k]))
    print("grass_variant_%s_digest=%s" % (lvl, kv.get("digest", "-") or "-"))
    # Un niveau sans AUCUN brin ne porte pas de variante, et ce n'est pas un defaut de CET item :
    # l'herbe n'est construite que pour `kGrassLevels` (`training`). Les muets sont NOMMES.
    if num["blades"] == 0:
        grassless.append(lvl)
        continue
    if num["terms_measured"] < 9:
        unmeasured += 1
        continue
    # LE BUDGET : ce que la diversite DEMANDE en sommets ne depasse jamais ce que le GPU transforme.
    if num["verts_active_total"] > num["verts_strip_total"]:
        budget_bad += 1
    # LE PALIER COMMANDE LE NOMBRE DE VARIANTES : le seuil vient de l'outil, jamais d'ici.
    if num["k"] <= 0 or num["k"] > num["count"]:
        k_bad += 1
    # ---- ESSAI 2. Les quatre grandeurs que l'owner a nommees le 20/09. Tous les PLANCHERS sont
    # publies par l'outil a cote de la mesure : aucun seuil n'est ecrit ici.
    if num["blades_clumped"] == 0 or num["clumps"] == 0:
        clumpless += 1          # sans touffe, les trois termes suivants ne mesurent rien
        continue
    if num["dominant_pm"] < num["dominant_pm_floor"]:
        dom_bad += 1            # (1) une touffe a-t-elle UNE silhouette dominante ?
    if num["height_cv_pm"] < num["height_cv_pm_floor"]:
        hcv_bad += 1            # (2) les touffes ont-elles des hauteurs differentes ENTRE elles ?
    if num["neigh_compared"] == 0 or num["neigh_diff_pm"] < num["neigh_diff_pm_floor"]:
        neigh_bad += 1          # (1 bis) les touffes VOISINES different-elles ?
    if num["seg_angle_max_mdeg"] > num["seg_angle_cap_mdeg"]:
        angle_bad += 1          # (3) voit-on encore les polygones des brins ?
    angle_over_tot += num["seg_angle_over"]
    # SOMMETS SOUMIS INCHANGES : ce que le GPU transforme reste blades * 10, quelle que soit la
    # silhouette. La diversite ne se paie pas en geometrie — point 2 du livrable, exige mot pour
    # mot par le perimetre du 20/09.
    if num["verts_strip_total"] != num["blades"] * num["verts_strip"]:
        submitted_bad += 1

for k in sorted(tot):
    print("grass_variant_total_%s=%d" % (k, tot[k]))
for v in range(NV):
    print("grass_variant_total_v%d=%d" % (v, per_v_tot[v]))
print("grass_variant_levels_parsed=%d" % seen)
print("grass_variant_levels_unparsed=%s" % (",".join(mute) if mute else "-"))
print("grass_variant_levels_grassless=%s" % (",".join(grassless) if grassless else "-"))
print("grass_variant_levels_grassed=%d" % (seen - len(grassless)))
print("grass_variant_census_digest=%s" % train.get("digest", "-"))
print("grass_variant_census_k=%s" % train.get("k", "-"))
print("grass_variant_census_blades=%s" % train.get("blades", "-"))

# ---- LES DEUX TABLES, LIGNE A LIGNE. `VAR_B[i].z` est le nombre de segments cote GLSL ;
# `variant_seg_v<i>` est celui que l'outil publie depuis `grass_blade_variants.h`. On compare les
# DONNEES des deux tables, jamais un commentaire : une legende ne se mesure pas.
src = open("game/graphics/opengl_renderer/shaders/grass.vert", encoding="utf-8").read()


def glsl_rows(name):
    mm = re.search(r"const\s+vec4\s+%s\[6\]\s*=\s*vec4\[6\]\((.*?)\);" % name, src, re.S)
    if not mm:
        return None
    out = []
    for row in re.findall(r"vec4\(([^)]*)\)", mm.group(1)):
        out.append([float(x.strip()) for x in row.split(",")])
    return out


ga, gb = glsl_rows("VAR_A"), glsl_rows("VAR_B")
glsl_seg, table_mismatch = [], 0
if gb is None or ga is None:
    table_mismatch += 1
    print("grass_variant_glsl_table=absente")
else:
    glsl_seg = [int(r[2]) if len(r) >= 3 else -1 for r in gb]
    print("grass_variant_glsl_segments=%s" % ",".join(str(x) for x in glsl_seg))
    if len(glsl_seg) != NV or len(ga) != NV:
        table_mismatch += 1
# LES HUIT NOMBRES DE CHAQUE LIGNE, PAS LE SEUL COMPTE DE SEGMENTS. L'essai 2 CALCULE un angle
# depuis la table C++ ; si la table GLSL en differait d'un chiffre, l'angle publie ne serait pas
# celui du brin dessine. La duplication reste, elle est mesuree en entier.
shape_mismatch, shape_compared = 0, 0
if ga is not None and gb is not None and train:
    for v in range(NV):
        cpp = train.get("shape_v%d" % v, "")
        got = [x for x in cpp.split(",") if x != ""]
        if len(got) != 8 or v >= len(ga) or v >= len(gb) or len(ga[v]) < 4 or len(gb[v]) < 4:
            shape_mismatch += 1
            continue
        want = [ga[v][0], ga[v][1], ga[v][2], ga[v][3], gb[v][0], gb[v][1], gb[v][2], gb[v][3]]
        for a, b in zip(want, [float(x) for x in got]):
            shape_compared += 1
            if abs(a - b) > 1.0e-4:
                shape_mismatch += 1
else:
    shape_mismatch += 1
print("grass_variant_shape_compared=%d" % shape_compared)
print("grass_variant_shape_mismatch=%d" % shape_mismatch)
cpp_seg = [int(train.get("seg_v%d" % v, -1)) for v in range(NV)] if train else [-1] * NV
print("grass_variant_cpp_segments=%s" % ",".join(str(x) for x in cpp_seg))
for v in range(NV):
    a = glsl_seg[v] if v < len(glsl_seg) else -1
    if a != cpp_seg[v]:
        table_mismatch += 1
# Le ruban : `SEGMENTS` du shader contre `verts_strip` publie par l'outil (2*(SEGMENTS+1)).
ms = re.search(r"const\s+int\s+SEGMENTS\s*=\s*(\d+)\s*;", src)
glsl_strip = 2 * (int(ms.group(1)) + 1) if ms else -1
print("grass_variant_glsl_strip_verts=%d" % glsl_strip)
print("grass_variant_cpp_strip_verts=%s" % train.get("verts_strip", "-"))
if not train or glsl_strip != int(train.get("verts_strip", -1)):
    table_mismatch += 1
# Publie sous son nom de MESURE ici ; il entre dans la somme par le dictionnaire `terms`
# ci-dessous, sous `grass_variant_term_table_mismatch`. Deux cles distinctes, pas un doublon.
print("grass_variant_table_mismatch=%d" % table_mismatch)

terms = {
    "off_profile": tot["off_profile"],
    "verts_over": tot["verts_over"],
    "verts_budget": budget_bad,
    "k_out_of_range": k_bad,
    "table_mismatch": table_mismatch,
    "levels_missing": len(levels) - seen,
    # Temoins de non-vacuite : sans eux tous les zeros ci-dessus seraient verts sans rien mesurer.
    "population_empty": 1 if tot["blades"] == 0 else 0,
    "grassed_absent": 1 if (seen - len(grassless)) == 0 else 0,
    "variants_absent": 1 if sum(1 for v in per_v_tot if v > 0) < 2 else 0,
    "terms_unmeasured": unmeasured,
    # ---- ESSAI 2 : les quatre oui/non de l'owner, un terme chacun, plus les temoins de non-vacuite.
    "clump_dominance": dom_bad,
    "clump_height_spread": hcv_bad,
    "clump_neighbors": neigh_bad,
    "seg_angle": angle_bad,
    "seg_angle_over": angle_over_tot,
    "verts_submitted": submitted_bad,
    "clumps_absent": clumpless,
    "shape_mismatch": shape_mismatch,
    "shape_uncompared": 1 if shape_compared < 8 * NV else 0,
}
for k in sorted(terms):
    print("grass_variant_term_%s=%d" % (k, terms[k]))
# +6 : les trois jambes de palier, la cecite du moteur, son empreinte et l'absence de maillage sont
# mesurees par le shell ; elles comptent dans la porte au meme titre que celles d'ici.
print("grass_variant_terms=%d" % (len(terms) + 6))
open(os.path.join(T, "terms.txt"), "w").write(str(sum(terms.values())))
open(os.path.join(T, "digest.txt"), "w").write(str(train.get("digest", "-")))
open(os.path.join(T, "k.txt"), "w").write(str(train.get("k", "-")))
PY

TERMS=$(cat "$T/terms.txt" 2>/dev/null || echo 99)
CDIG=$(cat "$T/digest.txt" 2>/dev/null || echo "-")
CK=$(cat "$T/k.txt" 2>/dev/null || echo "-")

# ---- LE MOTEUR A-T-IL SEULEMENT DESSINE DES VARIANTES ? Ce recensement tourne HORS LIGNE : il
# rendrait ses zeros meme si la course appareil n'avait affiche aucun brin. On lit donc, dans le
# journal de CETTE course, les trois temoins que seul le moteur ecrit.
ELOG="${AUTOPORT_CENSUS_DIR:-}/proof-engine.log"
EB=-1; EDIG="-"; EK=-1; EAV=-1; EAI=-1
if [ -n "${AUTOPORT_CENSUS_DIR:-}" ] && [ -s "$ELOG" ]; then
  v=$(grep -ao 'grass_variant_engine_blades=[0-9]\+' "$ELOG" 2>/dev/null | tail -1 | cut -d= -f2); [ -n "${v:-}" ] && EB=$v
  v=$(grep -ao 'grass_variant_engine_digest=[0-9a-f]\+' "$ELOG" 2>/dev/null | tail -1 | cut -d= -f2); [ -n "${v:-}" ] && EDIG=$v
  v=$(grep -ao 'grass_variant_engine_k=[0-9]\+' "$ELOG" 2>/dev/null | tail -1 | cut -d= -f2); [ -n "${v:-}" ] && EK=$v
  v=$(grep -ao 'grass_variant_attr_vertex=[0-9]\+' "$ELOG" 2>/dev/null | tail -1 | cut -d= -f2); [ -n "${v:-}" ] && EAV=$v
  v=$(grep -ao 'grass_variant_attr_instance=[0-9]\+' "$ELOG" 2>/dev/null | tail -1 | cut -d= -f2); [ -n "${v:-}" ] && EAI=$v
fi
echo "grass_variant_engine_blades_seen=$EB"
echo "grass_variant_engine_digest_seen=$EDIG"
echo "grass_variant_engine_k_seen=$EK"
echo "grass_variant_engine_attr_vertex_seen=$EAV"
echo "grass_variant_engine_attr_instance_seen=$EAI"
echo "grass_variant_census_log=${ELOG:--}"

BLIND=0; MIRROR=0; MESH=0
if [ "${AUTOPORT_CENSUS_ARMED:-1}" != "0" ]; then
  # DESARME, k=1 et aucun brin n'a recu de variante : ces trois termes ne sont pas comptes, c'est le
  # resultat ATTENDU du bras d'ablation.
  [ "$EB" -gt 0 ] 2>/dev/null || BLIND=1
  # MEME BINAIRE, MEME DONNEE, MEME PALIER : l'empreinte (racine, variante) du moteur doit etre celle
  # du recensement. Un ecart veut dire que ce qui est DESSINE n'est pas ce qui est mesure ici.
  if [ "$EDIG" = "-" ] || [ "$CDIG" = "-" ] || [ "$EDIG" != "$CDIG" ]; then MIRROR=$((MIRROR + 1)); fi
  if [ "$EK" = "-1" ] || [ "$CK" = "-" ] || [ "$EK" != "$CK" ]; then MIRROR=$((MIRROR + 1)); fi
  # POINT 4 : AUCUNE MODELISATION. Un maillage arriverait par un attribut de sommet (diviseur 0) du
  # VAO reellement dessine. Zero est exige ; zero attribut d'INSTANCE veut dire que la sonde n'a rien
  # vu, et c'est un defaut, pas un succes.
  [ "$EAV" = "0" ] || MESH=$((MESH + 1))
  [ "$EAI" -gt 0 ] 2>/dev/null || MESH=$((MESH + 1))
fi
echo "grass_variant_term_engine_blind=$BLIND"
echo "grass_variant_term_engine_mirror=$MIRROR"
echo "grass_variant_term_mesh_assets=$MESH"
echo "grass_variant_term_nest_changed=$NEST_CHANGED"
echo "grass_variant_term_nest_unmeasured=$((NEST_MUTE + NEST_EMPTY))"

# ---- LA GRANDEUR DE LA PORTE : la somme des termes ci-dessus, et rien d'autre.
echo "grass_variant_defects=$((TERMS + BLIND + MIRROR + MESH + NEST_CHANGED + NEST_MUTE + NEST_EMPTY))"
exit 0
