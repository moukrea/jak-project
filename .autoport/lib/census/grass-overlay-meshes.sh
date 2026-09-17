#!/usr/bin/env bash
# census/grass-overlay-meshes.sh — CE QUE LA COURSE DE JEU NE PEUT PAS DIRE.
#
# La course x86 prouve que l'instrument vit DANS le moteur et qu'il tire : elle charge `training`,
# y cherche les superpositions et publie `grass_overlay_engine_*` + `FEATURE ... armed=1
# hits=<paires testees>`. Elle ne peut pas repondre au point 1 du contrat — « SUR LES DIX NIVEAUX »
# — parce qu'un `gk` ne charge qu'un niveau, et parce que neuf de ces dix niveaux n'ont pas
# d'herbe du tout (`kGrassLevels[] = {"training"}`) : leur `GrassRenderer::rebuild()` n'est jamais
# appele.
#
# LE CODE EST LE MEME DES DEUX COTES. `grass_bake::overlay_census()` vit dans GrassBakeCore.cpp,
# compile a la fois dans `gk` et dans `tools/grass_bake`. Ce recensement l'appelle hors ligne sur
# les dix niveaux, par la PORTE de l'arbre — qui repare `.ninja_deps` et sort en 4 sur un binaire
# plus vieux que ses entrees, donc ce bras ne peut pas etre un vieux binaire.
#
# POURQUOI UN CONTROLE POSITIF ICI, ALORS QUE LES DIRECTIVES LE RATIONNENT. Le contrat dit qu'un
# ZERO ferme l'item (« la superposition n'existe pas » est une reponse valable). Un zero de
# detecteur mort s'ecrirait exactement comme ce zero-la. `--overlay-census` fait donc traverser a
# `overlay_census()` LUI-MEME un niveau fabrique de trois zones, ou les trois classes doivent etre
# PRODUITES ; c'est une passe en memoire de quelques millisecondes dans la MEME course, pas une
# jambe de campagne.
#
# IL N'ECRIT RIEN DANS LA DONNEE LIVREE. `--overlay-census` sort AVANT `scan_level` et n'ouvre
# aucun fichier en ecriture. Le point 4 du contrat — « RIEN NE CHANGE DANS LE PLACEMENT » — est
# verifie en recuisant `training` au palier `medium` dans un bac a sable et en comparant les octets
# au `.grassbake` LIVRE : c'est une mesure, pas une affirmation.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

# Les dix niveaux qui portent des textures de sol herbeux (SPEC-refonte-herbe.md, section 15).
LEVELS="training beach village1 village2 jungle rolling ogre swamp finalboss firecanyon"

T=$(mktemp -d "${TMPDIR:-/tmp}/grass-overlay-meshes.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
die(){ printf 'census grass-overlay-meshes: %s\n' "$*" >&2; exit 1; }

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
  "$BIN" "$lvl" --overlay-census > "$T/$lvl.out" 2> "$T/$lvl.err"
  RC=$?
  if [ "$RC" != 0 ]; then
    MISSING="${MISSING:+$MISSING,}$lvl:rc$RC"
    continue
  fi
  grep -E '^overlay_(census|selftest)_' "$T/$lvl.out" > "$T/$lvl.kv" 2>/dev/null
  if [ ! -s "$T/$lvl.kv" ]; then
    MISSING="${MISSING:+$MISSING,}$lvl:muet"
    continue
  fi
  OK=$((OK + 1))
done
echo "grass_overlay_levels=$N"
echo "grass_overlay_levels_ok=$OK"
echo "grass_overlay_levels_list=$(printf '%s' "$LEVELS" | tr ' ' ',')"
echo "grass_overlay_levels_failed=${MISSING:--}"

# ---- L'AGREGATION. Chaque terme est publie PAR NIVEAU puis somme ; `unclassified` — la grandeur
# de la porte — est la somme de termes qu'on peut relire un par un, jamais un chiffre isole.
python3 - "$T" $LEVELS <<'PY' || die "l'agregation a echoue."
import os, sys
T = sys.argv[1]
levels = sys.argv[2:]
NUM = ["render_up", "render_big", "render_draws", "collision_declared", "collision_indexed",
       "pairs_tested", "pairs_bbox", "pairs_diff_tex", "pairs_one_grassy", "pairs_overlap_area",
       "pairs_close_y", "pairs_far_y", "pairs_bare_over_grass", "pairs_grass_over_bare",
       "pairs_both_grassy", "pairs_coincident",
       "method_a", "method_b", "method_b_probed", "method_b_coll_tris",
       "method_b_rejected_below", "method_b_named_bare", "intersection", "found",
       "cls_path", "cls_patch", "cls_ambiguous",
       "ambig_no_collision", "ambig_material_other", "ambig_zfight",
       "found_texture_unnamed", "unclass_material_unnamed", "unclass_no_rule", "unclassified"]
# Publie par niveau : le contrat exige le compte PAR NIVEAU (point 1).
PER = ["pairs_tested", "pairs_close_y", "pairs_bare_over_grass", "method_a", "method_b",
       "intersection", "found", "cls_path", "cls_patch", "cls_ambiguous", "unclassified",
       "sum_check"]
tot = {k: 0 for k in NUM}
seen = 0
sum_ok = 0
st_ok = 0
st_seen = 0
st_first = None
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
        if k.startswith("overlay_census_"):
            kv[k[len("overlay_census_"):]] = v
        elif k.startswith("overlay_selftest_"):
            kv["st_" + k[len("overlay_selftest_"):]] = v
    # LE CONTROLE POSITIF EST LU MEME SI LE NIVEAU N'A PAS DE RECENSEMENT : c'est lui qui separe
    # « pas de superposition » de « detecteur mort ».
    if "st_ok" in kv:
        st_seen += 1
        st_ok += 1 if kv["st_ok"] == "1" else 0
        sig = ",".join("%s:%s" % (a, kv.get("st_" + a, "?")) for a in
                       ("method_a", "method_b", "intersection", "found", "path", "patch",
                        "ambiguous", "unclassified"))
        if st_first is None:
            st_first = sig
        elif st_first != sig:
            st_first = "DIVERGENT"
    if "found" not in kv:
        continue
    seen += 1
    for k in NUM:
        tot[k] += int(kv.get(k, 0))
    sum_ok += 1 if kv.get("sum_check") == "1" else 0
    for k in PER:
        print("grass_overlay_%s_%s=%s" % (lvl, k, kv.get(k, "0")))
    # LES NOMS. Le contrat exige « la liste des textures impliquees » ; les cacher serait le defaut.
    print("grass_overlay_%s_pair_src=%s" % (lvl, kv.get("pair_src_top", "-")))
    print("grass_overlay_%s_pair_tex=%s" % (lvl, kv.get("pair_tex_top", "-")))
    print("grass_overlay_%s_method_b_tex=%s" % (lvl, kv.get("method_b_tex_top", "-")))
for k in NUM:
    print("grass_overlay_%s=%d" % (k, tot[k]))
print("grass_overlay_levels_counted=%d" % seen)
# L'ARITHMETIQUE DE LA CLASSIFICATION, VERIFIEE ET NON AFFIRMEE : chaque superposition trouvee
# tombe dans UNE classe et une seule, sinon la somme ne retombe pas sur la population.
print("grass_overlay_sum_check_levels=%d" % sum_ok)
print("grass_overlay_sum_check_all=%d" % (1 if seen and sum_ok == seen else 0))
print("grass_overlay_classes_total=%d" % (tot["cls_path"] + tot["cls_patch"] + tot["cls_ambiguous"]
                                          + tot["unclassified"]))
# TEMOINS DE NON-VACUITE. Une population vide rendrait `unclassified=0` sans rien mesurer.
print("grass_overlay_population_empty=%d" % (1 if tot["pairs_tested"] == 0 else 0))
print("grass_overlay_found_empty=%d" % (1 if tot["found"] == 0 else 0))
print("grass_overlay_selftest_levels=%d" % st_seen)
print("grass_overlay_selftest_ok=%d" % st_ok)
print("grass_overlay_selftest_all=%d" % (1 if st_seen and st_ok == st_seen else 0))
print("grass_overlay_selftest_signature=%s" % (st_first or "-"))
PY

# ---- POINT 4 DU CONTRAT : LE PLACEMENT N'A PAS BOUGE, ET ON LE MESURE.
# On recuit `training` au palier `medium` dans le bac a sable et on compare les octets au fichier
# LIVRE. Identique = le scan, l'expansion et le format n'ont pas bouge d'un bit sous cet item.
REF=out/jak1/fr3/training.medium.grassbake
if [ -s "$REF" ]; then
  if "$BIN" training --preset medium --out "$T/training.medium.grassbake" > "$T/rebake.log" 2>&1; then
    NEWB=$(stat -c %s "$T/training.medium.grassbake" 2>/dev/null || echo 0)
    REFB=$(stat -c %s "$REF")
    if cmp -s "$REF" "$T/training.medium.grassbake"; then SAME=1; else SAME=0; fi
    echo "grass_overlay_bake_identical=$SAME"
    echo "grass_overlay_bake_ref_bytes=$REFB"
    echo "grass_overlay_bake_new_bytes=$NEWB"
    echo "grass_overlay_bake_roundtrip=$(grep -c 'round-trip @150: IDENTICAL' "$T/rebake.log")"
  else
    echo "grass_overlay_bake_identical=-1"
  fi
else
  echo "grass_overlay_bake_identical=-2"
fi
exit 0
