#!/usr/bin/env bash
# census/grass-shading.sh — CE QUE LA COURSE DE JEU NE PEUT PAS DIRE.
#
# La course appareil charge UN niveau, et neuf des dix niveaux herbeux n'ont pas d'herbe a l'ecran
# (`kGrassLevels[] = {"training"}`) : leur `GrassRenderer::rebuild()` n'est jamais appele. Le
# recensement passe donc le MEME code — `grass_bake::shading_census`, compile a la fois dans `gk`
# et dans `tools/grass_bake` — sur les dix niveaux, hors ligne, par la PORTE de l'arbre.
#
# LA PORTE NE MESURE PAS UN MIROIR. L'ecart de luminance racine/pointe et l'ecart entre les deux
# faces d'un brin naissent dans le shader ; l'outil ne les recalcule pas, il `#include` LES MEMES
# FICHIERS (`shaders/grass_shade.glsl`, `shaders/grass_shade_face.glsl`) que le pilote compile.
# Et le MOTEUR publie l'empreinte du texte qu'il a REELLEMENT splice : ce script la recalcule sur
# les fichiers de l'arbre, donc un blob GLES d'Android en retard devient un defaut compte.
#
# LE BRAS D'AVANT EST MESURE, PAS SUPPOSE. Pour chaque niveau, l'outil expanse AUSSI le bake avec
# la couleur desarmee et compare brin par brin : c'est l'etat que cet item remplace, sur la meme
# donnee. `intra_tri_cv_off` — la dispersion entre touffes VOISINES avant l'item — doit valoir
# exactement zero, sinon le vert d'`intra_tri_cv` decrirait quelque chose qui existait deja.
#
# IL N'ECRIT RIEN DANS LA DONNEE LIVREE : `--shading-census` sort avant toute ecriture de fichier.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

LEVELS="training beach village1 village2 jungle rolling ogre swamp finalboss firecanyon"

T=$(mktemp -d "${TMPDIR:-/tmp}/grass-shading.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
die(){ printf 'census grass-shading: %s\n' "$*" >&2; exit 1; }

bash .autoport/lib/build_x86.sh --target grass_bake > "$T/build.log" 2>&1 \
  || die "build_x86.sh --target grass_bake a rendu $? (voir $T/build.log)"
BIN=build/tools/grass_bake/grass_bake
[ -x "$BIN" ] || die "$BIN absent apres la porte."

# ---- LES DIX NIVEAUX, UN PAR UN. Un niveau absent, un outil qui echoue ou une sortie muette est
# NOMME dans `_levels_failed`, jamais absorbe en silence.
OK=0; N=0; MISSING=""
for lvl in $LEVELS; do
  N=$((N + 1))
  if [ ! -s "out/jak1/fr3/$lvl.fr3" ]; then
    MISSING="${MISSING:+$MISSING,}$lvl:absent"; continue
  fi
  if ! "$BIN" "$lvl" --preset medium --shading-census > "$T/$lvl.out" 2> "$T/$lvl.err"; then
    MISSING="${MISSING:+$MISSING,}$lvl:rc$?"; continue
  fi
  grep '^shade_' "$T/$lvl.out" > "$T/$lvl.kv" 2>/dev/null
  if [ ! -s "$T/$lvl.kv" ]; then
    MISSING="${MISSING:+$MISSING,}$lvl:muet"; continue
  fi
  OK=$((OK + 1))
done
echo "grass_shade_levels=$N"
echo "grass_shade_levels_ok=$OK"
echo "grass_shade_levels_list=$(printf '%s' "$LEVELS" | tr ' ' ',')"
echo "grass_shade_levels_failed=${MISSING:--}"

# ---- LE MODELE QUE LE MOTEUR A COMPILE EST-IL CELUI DE L'ARBRE ?
# FNV-1a 64 bits sur les OCTETS du fichier, la meme boucle que `Shader.cpp`. `to_gles_chunk()` les
# recopie octet pour octet (verifie : ses deux transformations ne mordent sur aucun des deux), donc
# l'empreinte du blob Android doit etre celle d'ici. Une divergence = un pack en retard.
fnv(){ python3 - "$1" <<'PY'
import sys
h = 0xcbf29ce484222325
for b in open(sys.argv[1], 'rb').read():
    h = ((h ^ b) * 0x100000001b3) & 0xffffffffffffffff
print(h)
PY
}
SHD=game/graphics/opengl_renderer/shaders
FNV_MODEL=$(fnv "$SHD/grass_shade.glsl" 2>/dev/null || echo -1)
FNV_FACE=$(fnv "$SHD/grass_shade_face.glsl" 2>/dev/null || echo -1)
echo "grass_shade_tree_model_fnv=$FNV_MODEL"
echo "grass_shade_tree_face_fnv=$FNV_FACE"

ELOG="${AUTOPORT_CENSUS_DIR:-}/proof-engine.log"
eng(){ # $1 = cle publiee par le moteur ; rend -1 si absente
  local v=""
  if [ -n "${AUTOPORT_CENSUS_DIR:-}" ] && [ -s "$ELOG" ]; then
    v=$(grep -ao "$1=[0-9]\+" "$ELOG" 2>/dev/null | tail -1 | cut -d= -f2)
  fi
  printf '%s' "${v:--1}"
}
ENG_MODEL_FNV=$(eng grass_shade_model_fnv)
ENG_FACE_FNV=$(eng grass_shade_face_fnv)
ENG_BLADES=$(eng grass_shade_engine_blades)
ENG_PERCLUMP=$(eng grass_shade_engine_per_clump)
ENG_BASES=$(eng grass_shade_engine_base_colours)
ENG_LBEFORE=$(eng grass_shade_engine_light_before)
ENG_LAFTER=$(eng grass_shade_engine_light_after)
ENG_HITS=$(eng grass_shade_engine_hits)
ENG_CULL=$(eng grass_shade_engine_cull_face)
echo "grass_shade_engine_model_fnv_seen=$ENG_MODEL_FNV"
echo "grass_shade_engine_face_fnv_seen=$ENG_FACE_FNV"
echo "grass_shade_engine_blades_seen=$ENG_BLADES"
echo "grass_shade_engine_per_clump_seen=$ENG_PERCLUMP"
echo "grass_shade_engine_base_colours_seen=$ENG_BASES"
echo "grass_shade_engine_light_before_seen=$ENG_LBEFORE"
echo "grass_shade_engine_light_after_seen=$ENG_LAFTER"
echo "grass_shade_engine_hits_seen=$ENG_HITS"
echo "grass_shade_engine_cull_face_seen=$ENG_CULL"
echo "grass_shade_engine_log=${ELOG:--}"

# LE MODELE LIVRE. Une empreinte que le moteur n'a pas publiee ne dit pas « egale » : elle ne dit
# rien, donc elle compte comme defaut — sauf sous le bras DESARME, ou le shader tourne toujours
# mais ou rien n'oblige la course a avoir charge l'herbe.
MODEL_STALE=0
if [ "${AUTOPORT_CENSUS_ARMED:-1}" != "0" ]; then
  [ "$ENG_MODEL_FNV" = "$FNV_MODEL" ] || MODEL_STALE=$((MODEL_STALE + 1))
  [ "$ENG_FACE_FNV" = "$FNV_FACE" ] || MODEL_STALE=$((MODEL_STALE + 1))
fi
echo "grass_shade_term_model_stale=$MODEL_STALE"

# LE MOTEUR A-T-IL SEULEMENT COLORE PAR TOUFFE ? Ce recensement tourne HORS LIGNE : il rendrait
# ses zeros meme si la course appareil n'avait affiche aucun brin. On lit le temoin que SEUL le
# moteur peut ecrire, dans le journal de CETTE course. Desarme, l'absence est le resultat ATTENDU.
BLIND=0
if [ "${AUTOPORT_CENSUS_ARMED:-1}" != "0" ]; then
  { [ "$ENG_PERCLUMP" = 1 ] && [ "${ENG_HITS:--1}" -gt 0 ] 2>/dev/null; } || BLIND=1
  # Et la resolution de la lumiere doit avoir gagne SUR L'APPAREIL, pas seulement sur le disque.
  if [ "${ENG_LAFTER:--1}" -le "${ENG_LBEFORE:-0}" ] 2>/dev/null; then BLIND=$((BLIND + 1)); fi
  # Et les deux faces du ruban doivent etre rasterisees, sinon l'ecart entre elles ne sort pas de
  # l'ordinateur. `-1` = le moteur ne l'a pas dit : ce n'est pas « faux », c'est muet, donc defaut.
  [ "$ENG_CULL" = 0 ] || BLIND=$((BLIND + 1))
fi
echo "grass_shade_term_engine_blind=$BLIND"

# ---- L'AGREGATION. Chaque terme est publie PAR NIVEAU puis somme ; la grandeur de la porte est la
# somme de termes qu'on peut relire un par un, jamais un chiffre isole.
python3 - "$T" $LEVELS <<'PY' || die "l'agregation a echoue."
import os, sys
T = sys.argv[1]
levels = sys.argv[2:]

INT = ["blades_total", "base_colours", "base_colours_floor", "clumps_coloured",
       "clump_colour_breaks", "sampled", "light_values_before", "light_values_after",
       "light_tris", "intra_tri_sampled", "ablation_diffs", "terms_measured"]
FLT = ["clump_lum_cv", "clump_lum_cv_off", "intra_tri_cv", "intra_tri_cv_off", "clump_mod_mean",
       "clump_amp_max", "root_tip_delta_mean", "root_tip_delta_min", "root_tip_rel_mean",
       "root_tip_rel_min", "face_delta_mean", "face_delta_max", "light_gain", "root_tip_floor",
       "root_tip_rel_floor", "face_floor", "clump_cv_floor", "light_gain_floor", "amp_cap",
       "mean_tol"]
PER = INT + FLT
REQ = set(INT) | set(FLT)

tot = {k: 0 for k in INT}
seen = 0
mute, grassless = [], []
base_bad = cv_bad = cv_off_bad = rt_bad = rel_bad = face_bad = light_bad = amp_bad = 0
mean_bad = 0
unmeasured = 0

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
        kv[k[len("shade_"):]] = v
    manque = [k for k in REQ if k not in kv]
    if manque:
        mute.append("%s:manque:%s" % (lvl, sorted(manque)[0]))
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
        print("grass_shade_%s_%s=%s" % (lvl, k, kv[k]))
    # UN NIVEAU SANS AUCUN BRIN NE PORTE PAS DE COULEUR, ET CE N'EST PAS UN DEFAUT : l'absence
    # d'herbe hors `training` est le sujet de `grass-levels`, pas de celui-ci. On le NOMME.
    if ints["blades_total"] == 0:
        grassless.append(lvl)
        continue
    if ints["terms_measured"] < 6:
        unmeasured += 1
        continue
    # Chaque seuil est celui que L'OUTIL publie, jamais une constante recopiee ici.
    if ints["base_colours"] < ints["base_colours_floor"]:
        base_bad += 1
    # LA GRANDEUR DECISIVE : deux touffes VOISINES (meme triangle) different-elles ? Et le bras
    # d'avant doit rendre EXACTEMENT zero, sinon on mesurerait un etat qui existait deja.
    if ints["intra_tri_sampled"] > 0:
        if flts["intra_tri_cv"] < flts["clump_cv_floor"]:
            cv_bad += 1
        if flts["intra_tri_cv_off"] > 1e-9:
            cv_off_bad += 1
    if ints["sampled"] > 0:
        # LE BRIN TYPIQUE en absolu, LE PIRE BRIN en relatif. Un plancher absolu pose sur un
        # MINIMUM jugerait l'ombre du lieu, pas la forme du degrade : tout le modele est multiplie
        # par la lumiere cuite, et `beach` descend a 0,0497 sur son brin le plus sombre pendant
        # que son rapport pointe/racine tient 0,608, comme partout ailleurs.
        if flts["root_tip_delta_mean"] < flts["root_tip_floor"]:
            rt_bad += 1
        if flts["root_tip_rel_min"] < flts["root_tip_rel_floor"]:
            rel_bad += 1
        if flts["face_delta_mean"] < flts["face_floor"]:
            face_bad += 1
    if ints["light_values_before"] > 0 and flts["light_gain"] < flts["light_gain_floor"]:
        light_bad += 1
    # POINT 4 : LA DIRECTION ARTISTIQUE TIENT. Amplitude bornee, et la moyenne du champ ne bouge
    # pas — une modulation qui eclaircit ou assombrit TOUTE la pelouse serait une regression que
    # personne n'a demandee.
    if flts["clump_amp_max"] > flts["amp_cap"]:
        amp_bad += 1
    if abs(flts["clump_mod_mean"] - 1.0) > flts["mean_tol"]:
        mean_bad += 1

for k in INT:
    print("grass_shade_%s=%d" % (k, tot[k]))
print("grass_shade_levels_parsed=%d" % seen)
print("grass_shade_levels_unparsed=%s" % (",".join(mute) if mute else "-"))
print("grass_shade_levels_grassless=%s" % (",".join(grassless) if grassless else "-"))
print("grass_shade_levels_grassed=%d" % (seen - len(grassless)))

terms = {
    "base_colours_shortfall": base_bad,
    "neighbour_tufts_identical": cv_bad,
    "before_arm_not_flat": cv_off_bad,
    "root_tip_shortfall": rt_bad,
    "root_tip_worst_blade_flat": rel_bad,
    "face_shortfall": face_bad,
    "light_resolution_shortfall": light_bad,
    "amplitude_exceeded": amp_bad,
    "field_mean_moved": mean_bad,
    "clump_colour_breaks": tot["clump_colour_breaks"],
    "ablation_diffs": tot["ablation_diffs"],
    "levels_missing": len(levels) - seen,
    # Temoins de non-vacuite : sans eux, tous les zeros ci-dessus seraient verts sans population.
    "population_empty": 1 if tot["blades_total"] == 0 else 0,
    "clumps_uncoloured": 1 if tot["clumps_coloured"] == 0 else 0,
    "grassed_absent": 1 if (seen - len(grassless)) == 0 else 0,
    "terms_unmeasured": unmeasured,
}
for k in sorted(terms):
    print("grass_shade_term_%s=%d" % (k, terms[k]))
# +2 : l'empreinte du modele livre et la cecite du moteur sont mesurees par le shell ; elles
# comptent dans la porte au meme titre que celles d'ici.
print("grass_shade_terms=%d" % (len(terms) + 2))
open(os.path.join(T, "terms.txt"), "w").write(str(sum(terms.values())))
PY

TERMS=$(cat "$T/terms.txt" 2>/dev/null || echo 99)

# ---- LA GRANDEUR DE LA PORTE : la somme des termes ci-dessus, et rien d'autre.
echo "grass_shading_defects=$((TERMS + MODEL_STALE + BLIND))"
exit 0
