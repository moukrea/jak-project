#!/usr/bin/env bash
# census/grass-clumps.sh — CE QUE LA COURSE DE JEU NE PEUT PAS DIRE.
#
# La course appareil charge UN niveau, et neuf des dix niveaux herbeux n'ont pas d'herbe a l'ecran
# (`kGrassLevels[] = {"training"}`, background_common.h:110) : leur `GrassRenderer::rebuild()` n'est
# jamais appele, donc aucune touffe n'y existe cote moteur pour y etre mesuree. Le recensement passe
# donc le MEME code — `grass_bake::clump_census`, compile a la fois dans `gk` et dans
# `tools/grass_bake` — sur les dix niveaux, hors ligne, par la PORTE de l'arbre.
#
# LA PORTE NE MESURE PAS UN MIROIR. Pour chaque brin emis, l'outil recalcule aussi la racine que le
# TIRAGE UNIFORME — le code que cet item remplace — lui aurait donnee, et compare le voisinage moyen
# des deux jeux de racines sur la MEME surface, avec le MEME compte de brins. Un regroupement
# qu'aucune mesure ne distingue d'un tirage uniforme n'existe pas.
#
# IL N'ECRIT RIEN DANS LA DONNEE LIVREE. `--clump-census` et `--clump-nest` n'ouvrent aucun fichier
# en ecriture, et les deux recuits du controle de determinisme tombent dans le bac a sable `$T`.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

# Les dix niveaux qui portent des textures de sol herbeux (SPEC-refonte-herbe.md, section 15).
LEVELS="training beach village1 village2 jungle rolling ogre swamp finalboss firecanyon"

T=$(mktemp -d "${TMPDIR:-/tmp}/grass-clumps.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
die(){ printf 'census grass-clumps: %s\n' "$*" >&2; exit 1; }

bash .autoport/lib/build_x86.sh --target grass_bake > "$T/build.log" 2>&1 \
  || die "build_x86.sh --target grass_bake a rendu $? (voir $T/build.log)"
BIN=build/tools/grass_bake/grass_bake
[ -x "$BIN" ] || die "$BIN absent apres la porte."

# ---- LES DIX NIVEAUX, UN PAR UN. Un niveau absent, un outil qui echoue ou une sortie muette est
# NOMME dans `_levels_failed`, jamais absorbe en silence : un denominateur qui retrecit sans temoin
# rend n'importe quel zero vert.
OK=0; N=0; MISSING=""
for lvl in $LEVELS; do
  N=$((N + 1))
  if [ ! -s "out/jak1/fr3/$lvl.fr3" ]; then
    MISSING="${MISSING:+$MISSING,}$lvl:absent"
    continue
  fi
  if ! "$BIN" "$lvl" --preset medium --clump-census > "$T/$lvl.out" 2> "$T/$lvl.err"; then
    MISSING="${MISSING:+$MISSING,}$lvl:rc$?"
    continue
  fi
  grep '^clump_' "$T/$lvl.out" > "$T/$lvl.kv" 2>/dev/null
  if [ ! -s "$T/$lvl.kv" ]; then
    MISSING="${MISSING:+$MISSING,}$lvl:muet"
    continue
  fi
  OK=$((OK + 1))
done
echo "grass_clump_levels=$N"
echo "grass_clump_levels_ok=$OK"
echo "grass_clump_levels_list=$(printf '%s' "$LEVELS" | tr ' ' ',')"
echo "grass_clump_levels_failed=${MISSING:--}"

# ---- POINT 3 DU CONTRAT : LES PALIERS RESTENT IMBRIQUES, AUX DEUX BOUTS DE L'ECHELLE.
# `training` est le seul niveau que le moteur rend, et la reference de non-regression de la
# campagne. On y compare le palier livre (medium) au plus BAS (very-low, 50) et au plus HAUT
# (very-high, 250) : dans les deux sens, une origine de touffe qui bouge ou un candidat qui n'est
# plus un prefixe est un defaut compte. Les huit autres niveaux ne sont PAS nides ici — c'est une
# limite assumee, nommee par `grass_clump_nest_levels`.
NEST_ORIGIN=0; NEST_COUNT=0; NEST_PREFIX=0; NEST_MISALIGN=0; NEST_LEGS=0; NEST_CLUMPS=0
for other in 50 250; do
  if "$BIN" training --preset medium --clump-nest "$other" > "$T/nest$other.out" 2>&1; then
    o=$(grep -m1 '^clump_nest_origin_moved=' "$T/nest$other.out" | cut -d= -f2)
    k=$(grep -m1 '^clump_nest_count_mismatch=' "$T/nest$other.out" | cut -d= -f2)
    x=$(grep -m1 '^clump_nest_prefix_breaks=' "$T/nest$other.out" | cut -d= -f2)
    m=$(grep -m1 '^clump_nest_tris_misaligned=' "$T/nest$other.out" | cut -d= -f2)
    c=$(grep -m1 '^clump_nest_clumps_compared=' "$T/nest$other.out" | cut -d= -f2)
    if [ -n "${o:-}" ] && [ -n "${x:-}" ] && [ -n "${c:-}" ]; then
      NEST_LEGS=$((NEST_LEGS + 1))
      NEST_ORIGIN=$((NEST_ORIGIN + o)); NEST_COUNT=$((NEST_COUNT + k))
      NEST_PREFIX=$((NEST_PREFIX + x)); NEST_MISALIGN=$((NEST_MISALIGN + m))
      NEST_CLUMPS=$((NEST_CLUMPS + c))
      echo "grass_clump_nest_${other}_origin_moved=$o"
      echo "grass_clump_nest_${other}_count_mismatch=$k"
      echo "grass_clump_nest_${other}_prefix_breaks=$x"
      echo "grass_clump_nest_${other}_tris_misaligned=$m"
      echo "grass_clump_nest_${other}_clumps_compared=$c"
    fi
  fi
done
echo "grass_clump_nest_levels=$NEST_LEGS"
echo "grass_clump_nest_clumps_compared=$NEST_CLUMPS"
# Une jambe de nidification qui n'a pas tourne ne dit pas « zero » : elle ne dit RIEN. Deux jambes
# sont attendues ; il en manque une = un defaut, pas un silence.
NEST_MUTE=$((2 - NEST_LEGS))
# Comparer ZERO touffe rendrait `origin_moved=0` par inaction.
NEST_EMPTY=0
[ "$NEST_CLUMPS" -gt 0 ] || NEST_EMPTY=1

# ---- L'AGREGATION. Chaque terme est publie PAR NIVEAU puis somme ; la grandeur de la porte est la
# somme de termes qu'on peut relire un par un, jamais un chiffre isole. Un niveau auquel il MANQUE
# une cle n'est pas compte comme un zero : il devient `muet`.
python3 - "$T" $LEVELS <<'PY' || die "l'agregation a echoue."
import os, sys
T = sys.argv[1]
levels = sys.argv[2:]

INT = ["blades_total", "clumps_total", "clumps_mounted", "pairs_sampled", "root_outside",
       "pos_mismatch", "clipped", "terms_measured"]
FLT = ["pairs_clumped", "pairs_uniform", "pairs_ratio", "size_mean", "size_cv", "radius_mean_m",
       "radius_cv", "height_mean_ratio", "pair_r_m", "ratio_floor", "size_cv_floor",
       "radius_cv_floor", "blades_medium"]
PER = ["blades_total", "clumps_total", "clumps_mounted", "pairs_sampled", "pairs_clumped",
       "pairs_uniform", "pairs_ratio", "size_mean", "size_cv", "radius_mean_m", "radius_cv",
       "height_mean_ratio", "root_outside", "pos_mismatch", "clipped", "terms_measured"]
REQ = set(INT) | set(FLT)

tot = {k: 0 for k in INT}
seen = 0
mute = []
grassless = []
ratio_bad = 0
size_cv_bad = 0
radius_cv_bad = 0
unmeasured = 0
digests = {}

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
        kv[k[len("clump_"):]] = v
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
        print("grass_clump_%s_%s=%s" % (lvl, k, kv[k]))
    print("grass_clump_%s_digest=%s" % (lvl, kv.get("origin_digest", "-") or "-"))
    digests[lvl] = kv.get("origin_digest", "-")
    # ---- UN NIVEAU SANS AUCUN BRIN NE PORTE PAS DE TOUFFE, ET CE N'EST PAS UN DEFAUT.
    # Le moteur ne construit d'herbe que pour `kGrassLevels` (`training`) ; l'outil hors ligne place
    # sur tout niveau dont la texture correspond. Les niveaux muets sont NOMMES, pas juges — sans
    # quoi l'absence d'herbe, sujet de `grass-levels`, deviendrait un defaut de CET item.
    if ints["blades_total"] == 0:
        grassless.append(lvl)
        continue
    if ints["terms_measured"] < 5:
        unmeasured += 1
        continue
    # Chaque seuil est celui que l'OUTIL publie, jamais une constante recopiee ici : un seuil
    # duplique dans le juge derive du code mesure et rend la porte fausse en silence.
    # Les trois grandeurs n'ont de sens que sur une population non vide : les juger sur zero
    # racine ou zero touffe serait un vert par inaction.
    if ints["pairs_sampled"] > 0 and flts["pairs_uniform"] > 0.0:
        if flts["pairs_ratio"] < flts["ratio_floor"]:
            ratio_bad += 1
    if ints["clumps_mounted"] > 0:
        if flts["size_cv"] < flts["size_cv_floor"]:
            size_cv_bad += 1
        if flts["radius_cv"] < flts["radius_cv_floor"]:
            radius_cv_bad += 1

for k in INT:
    print("grass_clump_%s=%d" % (k, tot[k]))
print("grass_clump_levels_parsed=%d" % seen)
print("grass_clump_levels_unparsed=%s" % (",".join(mute) if mute else "-"))
print("grass_clump_levels_grassless=%s" % (",".join(grassless) if grassless else "-"))
print("grass_clump_levels_grassed=%d" % (seen - len(grassless)))
print("grass_clump_training_digest=%s" % digests.get("training", "-"))

terms = {
    "ratio_shortfall": ratio_bad,
    "size_cv_shortfall": size_cv_bad,
    "radius_cv_shortfall": radius_cv_bad,
    "root_outside": tot["root_outside"],
    "pos_mismatch": tot["pos_mismatch"],
    "levels_missing": len(levels) - seen,
    # Temoins de non-vacuite : sans eux, tous les zeros ci-dessus seraient verts sans rien mesurer.
    "population_empty": 1 if tot["blades_total"] == 0 else 0,
    "clumps_absent": 1 if tot["clumps_mounted"] == 0 else 0,
    "grassed_absent": 1 if (seen - len(grassless)) == 0 else 0,
    "terms_unmeasured": unmeasured,
}
for k in sorted(terms):
    print("grass_clump_term_%s=%d" % (k, terms[k]))
# +7 : nidification (4 termes), determinisme (2) et cecite du moteur (1) sont mesures par le
# shell ; ils comptent dans la porte au meme titre que ceux d'ici.
print("grass_clump_terms=%d" % (len(terms) + 7))
open(os.path.join(T, "terms.txt"), "w").write(str(sum(terms.values())))
open(os.path.join(T, "digest.txt"), "w").write(digests.get("training", "-"))
PY

TERMS=$(cat "$T/terms.txt" 2>/dev/null || echo 99)
DIG1=$(cat "$T/digest.txt" 2>/dev/null || echo "-")

# ---- POINT 4 DU CONTRAT : « DEUX CHARGEMENTS DONNENT LES MEMES TOUFFES AUX MEMES ENDROITS ».
# On ne l'affirme pas. D'abord l'EMPREINTE DES ORIGINES, relue par une seconde course de l'outil :
# elle doit etre identique au caractere pres. Ensuite les OCTETS du bake, recuits deux fois dans le
# bac a sable : identiques au bit = le placement ne depend ni d'un ordre de conteneur ni d'un
# aleatoire non graine. Rien n'est ecrit dans `out/jak1/fr3/`.
DIG2="-"
if "$BIN" training --preset medium --clump-census > "$T/dig2.out" 2>&1; then
  DIG2=$(grep -m1 '^clump_origin_digest=' "$T/dig2.out" | cut -d= -f2)
fi
echo "grass_clump_digest_run1=${DIG1:--}"
echo "grass_clump_digest_run2=${DIG2:--}"
DIGBAD=1
if [ -n "${DIG2:-}" ] && [ "$DIG2" != "-" ] && [ "$DIG1" = "$DIG2" ]; then DIGBAD=0; fi
echo "grass_clump_term_digest_unstable=$DIGBAD"

DET=1
if "$BIN" training --preset medium --out "$T/a.grassbake" > "$T/bake_a.log" 2>&1 \
   && "$BIN" training --preset medium --out "$T/b.grassbake" > "$T/bake_b.log" 2>&1; then
  BYTES=$(stat -c %s "$T/a.grassbake" 2>/dev/null || echo 0)
  if cmp -s "$T/a.grassbake" "$T/b.grassbake"; then SAME=1; DET=0; else SAME=0; fi
  echo "grass_clump_bake_identical=$SAME"
  echo "grass_clump_bake_bytes=$BYTES"
else
  # Un recuit qui echoue n'est pas « identique » : il ne dit rien, donc il compte comme defaut.
  echo "grass_clump_bake_identical=-1"
  echo "grass_clump_bake_bytes=0"
fi
echo "grass_clump_term_determinisme=$DET"

# ---- LE MOTEUR A-T-IL SEULEMENT VU DES TOUFFES ? Ce recensement tourne HORS LIGNE, sur la donnee
# de l'arbre : il rendrait ses zeros meme si la course appareil n'avait affiche AUCUN brin. C'est
# arrive : le pack custom de l'APK deploye portait des `.grassbake` en format 9, le moteur les a
# refuses (« AUCUN BAKE VALIDE ... PAS D'HERBE ») et le recensement, lui, mesurait les bakes
# fraichement recuits du disque. Vert des deux cotes, herbe nulle part.
# On lit donc le temoin que SEUL le moteur peut ecrire, dans le journal de CETTE course.
ELOG="${AUTOPORT_CENSUS_DIR:-}/proof-engine.log"
ENGINE_MOUNTED=-1
if [ -n "${AUTOPORT_CENSUS_DIR:-}" ] && [ -s "$ELOG" ]; then
  v=$(grep -ao 'grass_clump_engine_mounted=[0-9]\+' "$ELOG" 2>/dev/null | tail -1 | cut -d= -f2)
  [ -n "${v:-}" ] && ENGINE_MOUNTED=$v
fi
echo "grass_clump_engine_mounted_seen=$ENGINE_MOUNTED"
echo "grass_clump_engine_log=${ELOG:--}"
# DESARME, zero touffe montee est le RESULTAT ATTENDU du bras d'ablation : on ne le compte pas.
BLIND=0
if [ "${AUTOPORT_CENSUS_ARMED:-1}" != "0" ]; then
  [ "$ENGINE_MOUNTED" -gt 0 ] 2>/dev/null || BLIND=1
fi
echo "grass_clump_term_engine_blind=$BLIND"
echo "grass_clump_term_nest_origin_moved=$NEST_ORIGIN"
echo "grass_clump_term_nest_count_mismatch=$NEST_COUNT"
echo "grass_clump_term_nest_prefix_breaks=$NEST_PREFIX"
echo "grass_clump_term_nest_unmeasured=$((NEST_MISALIGN + NEST_MUTE + NEST_EMPTY))"

# ---- LA GRANDEUR DE LA PORTE : la somme des termes ci-dessus, et rien d'autre.
echo "grass_clump_defects=$((TERMS + DET + DIGBAD + BLIND + NEST_ORIGIN + NEST_COUNT + NEST_PREFIX + NEST_MISALIGN + NEST_MUTE + NEST_EMPTY))"
exit 0
