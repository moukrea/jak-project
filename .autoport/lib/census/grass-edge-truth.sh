#!/usr/bin/env bash
# census/grass-edge-truth.sh — CE QUE LA COURSE DE JEU NE PEUT PAS DIRE.
#
# La course x86 prouve que l'instrument vit DANS le moteur et qu'il tire : elle charge `training`,
# y classe ses aretes de sol et publie `grass_edge_engine_*` + `FEATURE ... armed=1 hits=<aretes
# classees>`. Elle ne peut pas repondre au point 1 du contrat — « publier la table PAR NIVEAU » —
# parce qu'un `gk` ne charge qu'un niveau, et parce que neuf des dix niveaux herbeux n'ont pas
# d'herbe du tout (`kGrassLevels[] = {"training"}`, background_common.h:110) : leur
# `GrassRenderer::rebuild()` n'est jamais appele.
#
# LE CODE EST LE MEME DES DEUX COTES. `grass_bake::edge_census()` et `edge_probe_selftest()`
# vivent dans GrassBakeCore.cpp, compile a la fois dans `gk` et dans `tools/grass_bake` (meme
# .cpp, meme `-ffp-contract=off`). Ce recensement les appelle hors ligne sur les dix niveaux, par
# la PORTE de l'arbre — qui repare `.ninja_deps` et sort en 4 sur un binaire plus vieux que ses
# entrees, donc ce bras ne peut pas etre un vieux binaire.
#
# IL N'ECRIT RIEN DANS LA DONNEE LIVREE. `--edge-census` sort AVANT `scan_level` et n'ouvre aucun
# fichier en ecriture. La verification du point 4 du contrat — « AUCUN PLACEMENT NE CHANGE
# ENCORE » — recuit `training` au palier `medium` dans un bac a sable et compare les OCTETS au
# `.grassbake` livre : c'est une mesure, pas une affirmation.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

# Les dix niveaux qui portent des textures de sol herbeux (SPEC-refonte-herbe.md, section 15).
LEVELS="training beach village1 village2 jungle rolling ogre swamp finalboss firecanyon"

T=$(mktemp -d "${TMPDIR:-/tmp}/grass-edge-truth.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
die(){ printf 'census grass-edge-truth: %s\n' "$*" >&2; exit 1; }

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
  if ! "$BIN" "$lvl" --edge-census > "$T/$lvl.out" 2> "$T/$lvl.err"; then
    MISSING="${MISSING:+$MISSING,}$lvl:rc$?"
    continue
  fi
  grep -E '^edge_(census|selftest)_' "$T/$lvl.out" > "$T/$lvl.kv" 2>/dev/null
  if [ ! -s "$T/$lvl.kv" ]; then
    MISSING="${MISSING:+$MISSING,}$lvl:muet"
    continue
  fi
  OK=$((OK + 1))
done
echo "grass_edge_levels=$N"
echo "grass_edge_levels_ok=$OK"
echo "grass_edge_levels_list=$(printf '%s' "$LEVELS" | tr ' ' ',')"
echo "grass_edge_levels_failed=${MISSING:--}"

# ---- L'AGREGATION. La grandeur de la porte est la SOMME de termes qu'on peut relire un par un,
# jamais un chiffre isole. Le banc nomme est rejoue A CHAQUE NIVEAU : sa signature doit etre la
# meme partout, sans quoi elle vaut DIVERGENTE et la porte le voit.
python3 - "$T" $LEVELS <<'PY' || die "l'agregation a echoue."
import os, sys
T = sys.argv[1]
levels = sys.argv[2:]
NUM = ["collision", "mode_ground", "tris_used", "tris_xz_degenerate", "verts_raw", "verts_welded",
       "edges", "edges_zero_length", "edge_slots", "deg1", "deg2", "deg3plus",
       "cls_triangle", "cls_uv_seam", "cls_material", "cls_normal_break", "cls_chunk",
       "cls_overlay", "cls_path", "cls_void",
       "classified", "claimed_none", "claimed_multi",
       "beyond_found", "beyond_missing", "probe_selfhit",
       "void_with_far_floor", "void_no_floor_at_all", "void_out_far", "void_drop_far",
       "unshared_but_floor", "shared_but_void", "own_unrendered", "beyond_unrendered",
       "beyond_mat_unnamed", "legacy_tris", "legacy_edges", "old_rule_void",
       "geom_void_on_legacy", "old_only", "geom_only", "void_both",
       "void_edges_with_wall", "terrace_dirt_void", "terrace_sand_void", "terrace_stone_void",
       "terrace_dirt_void_old", "terrace_dirt_on_grass", "terrace_nongrass_void"]
# LA TABLE PAR NIVEAU que le point 1 du contrat exige.
PER = ["tris_used", "edges", "cls_triangle", "cls_uv_seam", "cls_material", "cls_normal_break",
       "cls_chunk", "cls_overlay", "cls_path", "cls_void", "claimed_none", "claimed_multi",
       "class_sum_check", "unshared_but_floor", "shared_but_void", "legacy_edges",
       "old_rule_void", "old_only", "geom_only", "void_both",
       "terrace_dirt_void", "terrace_nongrass_void", "void_edges_with_wall"]
tot = {k: 0 for k in NUM}
seen = 0
sum_fail = 0
st_seen = 0
st_sig = None
st_divergent = 0
st = {}
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
        if k.startswith("edge_census_"):
            kv[k[len("edge_census_"):]] = v
        elif k.startswith("edge_selftest_"):
            kv["ST_" + k[len("edge_selftest_"):]] = v
    if "edges" not in kv:
        continue
    seen += 1
    for k in NUM:
        tot[k] += int(kv.get(k, 0))
    if kv.get("class_sum_check", "0") != "1":
        sum_fail += 1
    for k in PER:
        print("grass_edge_%s_%s=%s" % (lvl, k, kv.get(k, "0")))
    # LES MATERIAUX DES FACES DE CHUTE, NOMMES PAR NIVEAU. Le contrat les exige : c'est la
    # reponse au faux vert du round 4, et la cacher serait le defaut.
    print("grass_edge_%s_wall_mat=%s" % (lvl, kv.get("void_wall_mat_top", "-")))
    print("grass_edge_%s_mat_pair=%s" % (lvl, kv.get("material_pair_top", "-")))
    print("grass_edge_%s_void_tex=%s" % (lvl, kv.get("void_tex_top", "-")))
    # LE BANC NOMME, rejoue a chaque niveau : sa reponse ne doit pas dependre du niveau.
    sig = "%s/%s/%s/%s" % (kv.get("ST_cases", "?"), kv.get("ST_agree", "?"),
                           kv.get("ST_disagree", "?"), kv.get("ST_ok", "?"))
    st_seen += 1
    if st_sig is None:
        st_sig = sig
        st = kv
    elif sig != st_sig:
        st_divergent = 1
for k in NUM:
    print("grass_edge_%s=%d" % (k, tot[k]))
print("grass_edge_levels_counted=%d" % seen)
print("grass_edge_sum_check_failed=%d" % sum_fail)
# ---- LE BANC NOMME : dix cas geometriques, dix-neuf aretes, les deux polarites.
print("grass_edge_selftest_runs=%d" % st_seen)
print("grass_edge_selftest_signature=%s" % ("DIVERGENT" if st_divergent else (st_sig or "-")))
print("grass_edge_selftest_cases=%s" % st.get("ST_cases", "0"))
print("grass_edge_selftest_agree=%s" % st.get("ST_agree", "0"))
print("grass_edge_selftest_disagree=%s" % st.get("ST_disagree", "0"))
print("grass_edge_selftest_not_found=%s" % st.get("ST_not_found", "0"))
print("grass_edge_selftest_expect_void=%s" % st.get("ST_expect_void", "0"))
print("grass_edge_selftest_expect_floor=%s" % st.get("ST_expect_floor", "0"))
print("grass_edge_selftest_verdicts=%s" % st.get("ST_verdicts", "-"))
print("grass_edge_selftest_disagreements=%s" % st.get("ST_disagreements", "-"))
st_dis = int(st.get("ST_disagree", "0") or 0) if st else 0
if st_divergent or st_seen == 0:
    st_dis = max(st_dis, 1)
# UN BANC QUI N'ATTENDRAIT QUE « VIDE » SERAIT VERT POUR UNE SONDE QUI REPOND TOUJOURS « VIDE ».
polarity = 0 if (int(st.get("ST_expect_void", "0") or 0) > 0 and
                 int(st.get("ST_expect_floor", "0") or 0) > 0) else 1
print("grass_edge_selftest_polarity_missing=%d" % polarity)
# ---- TEMOINS DE NON-VACUITE. Une population vide rendrait tous les zeros verts sans rien mesurer.
print("grass_edge_population_empty=%d" % (1 if tot["edges"] == 0 else 0))
print("grass_edge_classes_produced=%d" % sum(1 for k in NUM if k.startswith("cls_") and tot[k] > 0))
# ---- LE FAUX VERT DU ROUND 4 : le compte doit etre NON NUL (point 3 du contrat).
print("grass_edge_terrace_dirt_absent=%d" % (1 if tot["terrace_dirt_void"] == 0 else 0))
print("grass_edge_terrace_nongrass_absent=%d" % (1 if tot["terrace_nongrass_void"] == 0 else 0))
# ---- LES TERMES DE LA PORTE, PUBLIES SEPAREMENT PUIS SOMMES.
terms = {
    "claimed_none": tot["claimed_none"],
    "claimed_multi": tot["claimed_multi"],
    "sum_check_failed": sum_fail,
    "selftest_disagree": st_dis,
    "selftest_polarity_missing": polarity,
    "levels_missing": len(levels) - seen,
    "population_empty": 1 if tot["edges"] == 0 else 0,
    "terrace_dirt_absent": 1 if tot["terrace_dirt_void"] == 0 else 0,
    "probe_selfhit": tot["probe_selfhit"],
}
for k in sorted(terms):
    print("grass_edge_term_%s=%d" % (k, terms[k]))
print("grass_edge_terms=%d" % len(terms))
open(os.path.join(T, "terms.txt"), "w").write(str(sum(terms.values())))
PY

TERMS=$(cat "$T/terms.txt" 2>/dev/null || echo 99)

# ---- POINT 4 DU CONTRAT : LE PLACEMENT N'A PAS BOUGE, ET ON LE MESURE.
# On recuit `training` au palier `medium` dans le bac a sable et on compare les octets au fichier
# LIVRE. Identique = le scan, l'expansion et le format n'ont pas bouge d'un bit sous cet item.
BAKE_CHANGED=1
REF=out/jak1/fr3/training.medium.grassbake
if [ -s "$REF" ]; then
  if "$BIN" training --preset medium --out "$T/training.medium.grassbake" > "$T/rebake.log" 2>&1; then
    NEWB=$(stat -c %s "$T/training.medium.grassbake" 2>/dev/null || echo 0)
    REFB=$(stat -c %s "$REF")
    if cmp -s "$REF" "$T/training.medium.grassbake"; then SAME=1; BAKE_CHANGED=0; else SAME=0; fi
    echo "grass_edge_bake_identical=$SAME"
    echo "grass_edge_bake_ref_bytes=$REFB"
    echo "grass_edge_bake_new_bytes=$NEWB"
    echo "grass_edge_bake_instances=$(sed -n 's/.*round-trip @150:.*instances=\([0-9]\+\).*/\1/p' "$T/rebake.log" | tail -1)"
    echo "grass_edge_bake_roundtrip=$(grep -c 'round-trip @150: IDENTICAL' "$T/rebake.log")"
  else
    echo "grass_edge_bake_identical=-1"
  fi
else
  echo "grass_edge_bake_identical=-2"
fi
echo "grass_edge_term_bake_changed=$BAKE_CHANGED"

# ---- LA GRANDEUR DE LA PORTE : la somme des termes ci-dessus, et rien d'autre.
echo "grass_edge_misclassified=$((TERMS + BAKE_CHANGED))"
exit 0
