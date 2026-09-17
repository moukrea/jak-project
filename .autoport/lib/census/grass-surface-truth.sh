#!/usr/bin/env bash
# census/grass-surface-truth.sh — CE QUE LA COURSE DE JEU NE PEUT PAS DIRE.
#
# La course x86 prouve que l'instrument vit DANS le moteur et qu'il tire : elle charge `training`,
# y croise les deux sources et publie `grass_surface_engine_*` + `FEATURE ... armed=1 hits=<sol
# classe>`. Elle ne peut pas repondre au point 4 du contrat — « LA LECTURE MARCHE SUR LES DIX
# NIVEAUX » — parce qu'un `gk` ne charge qu'un niveau, et parce que neuf de ces dix niveaux
# n'ont pas d'herbe du tout (`kGrassLevels[] = {"training"}`, background_common.h:110) : leur
# `GrassRenderer::rebuild()` n'est jamais appele.
#
# LE CODE EST LE MEME DES DEUX COTES. `grass_bake::surface_census()` vit dans GrassBakeCore.cpp,
# compile a la fois dans `gk` et dans `tools/grass_bake` (meme .cpp, meme `-ffp-contract=off`).
# Ce recensement l'appelle hors ligne sur les dix niveaux, par la PORTE de l'arbre — qui repare
# `.ninja_deps` et sort en 4 sur un binaire plus vieux que ses entrees, donc ce bras ne peut pas
# etre un vieux binaire.
#
# IL N'ECRIT RIEN DANS LA DONNEE LIVREE. `--surface-census` sort AVANT `scan_level` et n'ouvre
# aucun fichier en ecriture. La verification du point 3 du contrat — « RIEN NE CHANGE ENCORE DANS
# LE PLACEMENT » — recuit `training` au palier `medium` dans un bac a sable et compare les octets
# au `.grassbake` LIVRE : c'est une mesure, pas une affirmation.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

# Les dix niveaux qui portent des textures de sol herbeux (SPEC-refonte-herbe.md, section 15).
LEVELS="training beach village1 village2 jungle rolling ogre swamp finalboss firecanyon"

T=$(mktemp -d "${TMPDIR:-/tmp}/grass-surface-truth.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
die(){ printf 'census grass-surface-truth: %s\n' "$*" >&2; exit 1; }

bash .autoport/lib/build_x86.sh --target grass_bake > "$T/build.log" 2>&1 \
  || die "build_x86.sh --target grass_bake a rendu $? (voir $T/build.log)"
BIN=build/tools/grass_bake/grass_bake
[ -x "$BIN" ] || die "$BIN absent apres la porte."

# ---- LES DIX NIVEAUX, UN PAR UN. Un niveau absent ou un outil qui echoue est NOMME, jamais
# absorbe en silence : un denominateur qui retrecit sans temoin rend n'importe quel zero vert.
OK=0; N=0; MISSING=""
for lvl in $LEVELS; do
  N=$((N + 1))
  if [ ! -s "out/jak1/fr3/$lvl.fr3" ]; then
    MISSING="${MISSING:+$MISSING,}$lvl:absent"
    continue
  fi
  if ! "$BIN" "$lvl" --surface-census > "$T/$lvl.out" 2> "$T/$lvl.err"; then
    MISSING="${MISSING:+$MISSING,}$lvl:rc$?"
    continue
  fi
  grep '^surface_census_' "$T/$lvl.out" > "$T/$lvl.kv" 2>/dev/null
  if [ ! -s "$T/$lvl.kv" ]; then
    MISSING="${MISSING:+$MISSING,}$lvl:muet"
    continue
  fi
  OK=$((OK + 1))
done
echo "grass_surface_levels=$N"
echo "grass_surface_levels_ok=$OK"
echo "grass_surface_levels_list=$(printf '%s' "$LEVELS" | tr ' ' ',')"
echo "grass_surface_levels_failed=${MISSING:--}"

# ---- L'AGREGATION. Chaque terme est publie PAR NIVEAU puis somme ; `unclassified` — la grandeur
# de la porte — est la somme de termes qu'on peut relire un par un, jamais un chiffre isole.
python3 - "$T" $LEVELS <<'PY' || die "l'agregation a echoue."
import os, sys
T = sys.argv[1]
levels = sys.argv[2:]
NUM = ["ground", "collision", "mode_ground", "mode_wall", "mode_obstacle", "mode_other",
       "by_material", "by_texture", "by_both", "classified", "unclassified",
       "tex_only_unclassified", "mat_only_unclassified",
       "mat_grass", "mat_sand", "mat_dirt", "mat_stone", "mat_other", "mat_unnamed",
       "tex_grass", "tex_grass_legacy3", "legacy3_unclassified",
       "disagree", "disagree_mat_grass_tex_not", "disagree_tex_grass_mat_not",
       "render_ground", "render_draws", "textures"]
# Publie par niveau (le contrat exige le recensement PAR NIVEAU, point 4).
PER = ["ground", "by_material", "by_texture", "unclassified", "tex_only_unclassified",
       "mat_grass", "mat_sand", "mat_dirt", "mat_stone", "tex_grass", "tex_grass_legacy3",
       "legacy3_unclassified", "disagree", "mode_wall"]
tot = {k: 0 for k in NUM}
seen = 0
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
        kv[k[len("surface_census_"):]] = v
    if "ground" not in kv:
        continue
    seen += 1
    for k in NUM:
        tot[k] += int(kv.get(k, 0))
    for k in PER:
        print("grass_surface_%s_%s=%s" % (lvl, k, kv.get(k, "0")))
    # LES NOMS DE TEXTURE DES DESACCORDS. Le contrat les exige ; les cacher serait le defaut.
    print("grass_surface_%s_disagree_tex=%s" % (lvl, kv.get("disagree_tex_top", "-")))
    print("grass_surface_%s_mat_grass_tex=%s" % (lvl, kv.get("mat_grass_tex_top", "-")))
    print("grass_surface_%s_tex_grass_mat=%s" % (lvl, kv.get("tex_grass_mat_top", "-")))
for k in NUM:
    print("grass_surface_%s=%d" % (k, tot[k]))
print("grass_surface_levels_counted=%d" % seen)
# TEMOINS DE NON-VACUITE : une population vide rendrait `unclassified=0` sans rien mesurer.
print("grass_surface_population_empty=%d" % (1 if tot["ground"] == 0 else 0))
print("grass_surface_levels_with_ground=%d" % seen)
PY

# ---- POINT 3 DU CONTRAT : LE PLACEMENT N'A PAS BOUGE, ET ON LE MESURE.
# On recuit `training` au palier `medium` dans le bac a sable et on compare les octets au fichier
# LIVRE. Identique = le scan, l'expansion et le format n'ont pas bouge d'un bit sous cet item.
REF=out/jak1/fr3/training.medium.grassbake
if [ -s "$REF" ]; then
  if "$BIN" training --preset medium --out "$T/training.medium.grassbake" > "$T/rebake.log" 2>&1; then
    NEWB=$(stat -c %s "$T/training.medium.grassbake" 2>/dev/null || echo 0)
    REFB=$(stat -c %s "$REF")
    if cmp -s "$REF" "$T/training.medium.grassbake"; then SAME=1; else SAME=0; fi
    echo "grass_surface_bake_identical=$SAME"
    echo "grass_surface_bake_ref_bytes=$REFB"
    echo "grass_surface_bake_new_bytes=$NEWB"
    echo "grass_surface_bake_instances=$(sed -n 's/.*round-trip @150:.*instances=\([0-9]\+\).*/\1/p' "$T/rebake.log" | tail -1)"
    echo "grass_surface_bake_roundtrip=$(grep -c 'round-trip @150: IDENTICAL' "$T/rebake.log")"
  else
    echo "grass_surface_bake_identical=-1"
  fi
else
  echo "grass_surface_bake_identical=-2"
fi
exit 0
