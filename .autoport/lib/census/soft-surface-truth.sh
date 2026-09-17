#!/usr/bin/env bash
# census/soft-surface-truth.sh — CE QUE LA COURSE DE JEU NE PEUT PAS DIRE.
#
# La course x86 prouve que l'instrument vit DANS le moteur et qu'il tire : elle charge `training`,
# y croise les deux sources pour le sable et publie `soft_surface_engine_*` + `FEATURE ...
# armed=1 hits=<sol classe>`. Elle ne peut pas repondre au point 1 du contrat — la classification
# PAR NIVEAU — parce qu'un `gk` ne charge qu'un niveau, et parce que le crochet moteur vit dans
# `GrassRenderer::rebuild()`, qui n'est appele que sur les niveaux d'herbe
# (`kGrassLevels[] = {"training"}`, background_common.h:109). Or la campagne `soft-*` vise
# d'abord `snow`, `beach`, `village1` et `ogre` : aucun d'eux n'a d'herbe.
#
# LE CODE EST LE MEME DES DEUX COTES. `grass_bake::soft_surface_census()` vit dans
# GrassBakeCore.cpp, compile a la fois dans `gk` et dans `tools/grass_bake`, et il APPELLE le
# lecteur de `grass-surface-truth` (`census_tex_is_grassy`, `surf_build_render_index`,
# `surf_index_probe`) au lieu d'en fabriquer un second. Ce recensement l'appelle hors ligne sur
# TOUS les niveaux, par la PORTE de l'arbre — qui repare `.ninja_deps` et sort en 4 sur un binaire
# plus vieux que ses entrees, donc ce bras ne peut pas etre un vieux binaire.
#
# IL N'ECRIT RIEN DANS LA DONNEE LIVREE. `--soft-surface-census` sort AVANT `scan_level` et
# n'ouvre aucun fichier en ecriture (point 4 du contrat : rien ne change encore).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

# TOUS les `.fr3` de jak1 SAUF `GAME.fr3`, qui n'est pas un niveau (donnee commune, 0 triangle de
# collision) : l'inclure fabriquerait un niveau vide et rendrait `levels_empty` rouge pour rien.
# La liste est ECRITE, pas devinee d'un glob : un `.fr3` qui disparait doit ROUGIR, pas s'effacer
# du denominateur.
LEVELS="beach citadel darkcave demo finalboss firecanyon intro jungle jungleb lavatube maincave
misty ogre robocave rolling snow sunken sunkenb swamp test-zone title training village1 village2
village3"

T=$(mktemp -d "${TMPDIR:-/tmp}/soft-surface-truth.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
die(){ printf 'census soft-surface-truth: %s\n' "$*" >&2; exit 1; }

bash .autoport/lib/build_x86.sh --target grass_bake > "$T/build.log" 2>&1 \
  || die "build_x86.sh --target grass_bake a rendu $? (voir $T/build.log)"
BIN=build/tools/grass_bake/grass_bake
[ -x "$BIN" ] || die "$BIN absent apres la porte."

# ---- LES NIVEAUX, UN PAR UN. Un niveau absent ou un outil qui echoue est NOMME et COMPTE : un
# denominateur qui retrecit sans temoin rend n'importe quel zero vert.
OK=0; N=0; FAILED=0; MISSING=""
for lvl in $LEVELS; do
  N=$((N + 1))
  if [ ! -s "out/jak1/fr3/$lvl.fr3" ]; then
    MISSING="${MISSING:+$MISSING,}$lvl:absent"; FAILED=$((FAILED + 1)); continue
  fi
  if ! "$BIN" "$lvl" --soft-surface-census > "$T/$lvl.out" 2> "$T/$lvl.err"; then
    MISSING="${MISSING:+$MISSING,}$lvl:rc$?"; FAILED=$((FAILED + 1)); continue
  fi
  grep '^soft_census_' "$T/$lvl.out" > "$T/$lvl.kv" 2>/dev/null
  if [ ! -s "$T/$lvl.kv" ]; then
    MISSING="${MISSING:+$MISSING,}$lvl:muet"; FAILED=$((FAILED + 1)); continue
  fi
  OK=$((OK + 1))
done
echo "soft_surface_levels=$N"
echo "soft_surface_levels_ok=$OK"
echo "soft_surface_levels_failed_n=$FAILED"
echo "soft_surface_levels_failed=${MISSING:--}"
echo "soft_surface_levels_list=$(printf '%s' "$LEVELS" | tr '\n' ' ' | tr -s ' ' | tr ' ' ',' | sed 's/,$//')"

# ---- L'AGREGATION ET LA PORTE. `soft_surface_unclassified` est une SOMME DE TERMES PUBLIES
# SEPAREMENT, chacun relisible un par un — jamais un chiffre isole.
python3 - "$T" "$FAILED" $LEVELS <<'PY' || die "l'agregation a echoue."
import os, sys
T = sys.argv[1]
failed_n = int(sys.argv[2])
levels = sys.argv[3:]
NUM = ["ground", "collision", "mode_ground", "mode_wall", "mode_obstacle", "mode_other",
       "mode_wall_soft", "mode_obstacle_soft", "mode_other_soft",
       "by_material", "by_texture", "by_both", "classified", "unclassified",
       "tex_only_unclassified", "mat_only_unclassified",
       "mat_sand", "mat_snow", "mat_deepsnow", "mat_soft", "mat_grass", "mat_unnamed",
       "tex_sand", "tex_snow", "tex_soft", "tex_grass", "tex_reject",
       "soft_by_material", "soft_by_texture", "soft_by_both", "soft_by_either",
       "disagree", "disagree_mat_soft_tex_not", "disagree_tex_soft_mat_not",
       "eligible_soft", "eligible_grass", "cross_eligible", "cross_raw",
       "overlay_soft_tex_on_grass_mat", "overlay_grass_tex_on_soft_mat",
       "render_ground", "render_draws", "textures"]
# PAR NIVEAU (point 1 du contrat : les deux sources, publiees separement, par niveau).
PER = ["ground", "by_material", "by_texture", "unclassified",
       "mat_sand", "mat_snow", "mat_deepsnow", "mat_soft",
       "tex_sand", "tex_snow", "tex_soft", "tex_reject",
       "soft_by_material", "soft_by_texture", "soft_by_either",
       "disagree", "disagree_mat_soft_tex_not", "disagree_tex_soft_mat_not",
       "eligible_soft", "eligible_grass", "cross_eligible", "cross_raw",
       "mode_wall_soft", "overlay_soft_tex_on_grass_mat"]
# LES NOMS DE TEXTURE. Le contrat les exige (point 2) ; les cacher serait le defaut. Publies
# seulement pour les niveaux qui ont quelque chose a dire : `publish_text` garde la derniere
# valeur, mais ici chaque cle est ecrite a chaque course, donc "-" est ecrit tel quel.
TOPS = ["mat_soft_tex_top", "tex_soft_mat_top", "disagree_tex_top", "cross_raw_tex_top",
        "tex_reject_top"]
tot = {k: 0 for k in NUM}
seen = 0
empty = 0
empty_list = []
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
        kv[k[len("soft_census_"):]] = v
    if "ground" not in kv:
        continue
    seen += 1
    if int(kv.get("ground", 0)) == 0:
        empty += 1
        empty_list.append(lvl)
    for k in NUM:
        tot[k] += int(kv.get(k, 0))
    for k in PER:
        print("soft_surface_%s_%s=%s" % (lvl, k, kv.get(k, "0")))
    for k in TOPS:
        print("soft_surface_%s_%s=%s" % (lvl, k, kv.get(k, "-")))
for k in NUM:
    # `unclassified` NE SORT PAS ICI : la cle nue est celle de la PORTE, et elle vaut la SOMME des
    # quatre termes ci-dessous. Publier deux fois la meme cle avec deux valeurs differentes
    # laisserait le validateur lire celle qu'il veut.
    if k == "unclassified":
        continue
    print("soft_surface_%s=%d" % (k, tot[k]))
print("soft_surface_levels_counted=%d" % seen)
print("soft_surface_levels_empty=%d" % empty)
print("soft_surface_levels_empty_list=%s" % (",".join(empty_list) if empty_list else "-"))
# TEMOIN DE NON-VACUITE : une population vide rendrait la porte verte sans rien mesurer.
print("soft_surface_population_empty=%d" % (1 if tot["ground"] == 0 else 0))

# ---- LA PORTE. QUATRE TERMES, PUBLIES SEPAREMENT JUSTE AU-DESSUS, ET LEUR SOMME.
#  1 unclassified          un triangle de sol qu'AUCUNE des deux sources ne classe (point 1)
#  2 cross_eligible        un triangle eligible a la fois a l'herbe et a la coque (point 3)
#  3 levels_failed_n       un niveau que le recensement n'a pas su lire (denominateur honnete)
#  4 levels_empty          un niveau liste dont la population de sol est vide (non-vacuite)
terms = [("unclassified", tot["unclassified"]), ("cross_eligible", tot["cross_eligible"]),
         ("levels_failed_n", failed_n), ("levels_empty", empty)]
print("soft_surface_unclassified_ground=%d" % tot["unclassified"])
print("soft_surface_gate_terms=%d" % len(terms))
print("soft_surface_gate_terms_list=%s" % ",".join("%s:%d" % t for t in terms))
print("soft_surface_unclassified=%d" % sum(v for _, v in terms))
PY
exit 0
