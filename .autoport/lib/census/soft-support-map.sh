#!/usr/bin/env bash
# census/soft-support-map.sh — LA COQUE, SOMMET PAR SOMMET, SUR LES 25 NIVEAUX.
#
# La course x86 prouve que l'instrument vit DANS le moteur et qu'il a tire : elle charge
# `training`, y cuit le support et l'epaisseur, publie `soft_map_engine_*` et
# `FEATURE soft-support-map armed=1 hits=<sommets ayant recu une epaisseur>`. Elle ne peut pas
# repondre au contrat PAR NIVEAU — un `gk` ne charge qu'un niveau, et le crochet moteur vit dans
# `GrassRenderer::rebuild()`, appele seulement sur les niveaux d'herbe
# (`kGrassLevels[] = {"training"}`). Or la campagne vise d'abord `snow`, `beach`, `village1` et
# `ogre` : aucun d'eux n'a d'herbe. C'est donc ICI que la grandeur de la porte est produite.
#
# LE CODE EST LE MEME DES DEUX COTES. `grass_bake::soft_support_map()` vit dans GrassBakeCore.cpp,
# compile a la fois dans `gk` et dans `tools/grass_bake`, et il APPELLE le lecteur de
# `soft-surface-truth` (`soft_resolve_class`, `census_tex_is_sandy/_snowy/_grassy`,
# `surf_build_render_index`) au lieu d'en fabriquer un second.
#
# IL N'ECRIT RIEN DANS LA DONNEE LIVREE. `--soft-support-map` sort AVANT `scan_level` et n'ouvre
# aucun fichier en ecriture : rien n'est serialise, c'est `soft-bake-format` qui le fera.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

# TOUS les `.fr3` de jak1 SAUF `GAME.fr3`, qui n'est pas un niveau. La liste est ECRITE, pas
# devinee d'un glob : un `.fr3` qui disparait doit ROUGIR, pas s'effacer du denominateur.
LEVELS="beach citadel darkcave demo finalboss firecanyon intro jungle jungleb lavatube maincave
misty ogre robocave rolling snow sunken sunkenb swamp test-zone title training village1 village2
village3"

T=$(mktemp -d "${TMPDIR:-/tmp}/soft-support-map.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
die(){ printf 'census soft-support-map: %s\n' "$*" >&2; exit 1; }

bash .autoport/lib/build_x86.sh --target grass_bake > "$T/build.log" 2>&1 \
  || die "build_x86.sh --target grass_bake a rendu $? (voir $T/build.log)"
BIN=build/tools/grass_bake/grass_bake
[ -x "$BIN" ] || die "$BIN absent apres la porte."

OK=0; N=0; FAILED=0; MISSING=""
for lvl in $LEVELS; do
  N=$((N + 1))
  if [ ! -s "out/jak1/fr3/$lvl.fr3" ]; then
    MISSING="${MISSING:+$MISSING,}$lvl:absent"; FAILED=$((FAILED + 1)); continue
  fi
  if ! "$BIN" "$lvl" --soft-support-map > "$T/$lvl.out" 2> "$T/$lvl.err"; then
    MISSING="${MISSING:+$MISSING,}$lvl:rc$?"; FAILED=$((FAILED + 1)); continue
  fi
  grep '^soft_map_' "$T/$lvl.out" > "$T/$lvl.kv" 2>/dev/null
  if [ ! -s "$T/$lvl.kv" ]; then
    MISSING="${MISSING:+$MISSING,}$lvl:muet"; FAILED=$((FAILED + 1)); continue
  fi
  OK=$((OK + 1))
done
echo "soft_support_levels=$N"
echo "soft_support_levels_ok=$OK"
echo "soft_support_levels_failed_n=$FAILED"
echo "soft_support_levels_failed=${MISSING:--}"

# ---- L'AGREGATION ET LA PORTE. `soft_thickness_defects` est une SOMME DE TERMES PUBLIES
# SEPAREMENT, chacun relisible un par un — jamais un chiffre isole.
python3 - "$T" "$FAILED" $LEVELS <<'PY' || die "l'agregation a echoue."
import os, sys
T = sys.argv[1]
failed_n = int(sys.argv[2])
levels = sys.argv[3:]
U = 4096.0

# Termes de la porte, lus un par un.
DEFECTS = ["defect_no_support", "defect_below_support", "defect_negative", "defect_boundary",
           "defect_direction"]
# Denominateurs et populations.
NUM = ["render_draws", "render_offered", "render_indexed", "collision", "soft_tris", "hull_tris",
       "hull_tris_sand", "hull_tris_snow", "hull_tris_deepsnow", "hull_tris_dup", "vert_slots",
       "hull_verts", "hull_verts_thick", "hull_verts_tested", "hull_verts_sand",
       "hull_verts_snow", "hull_verts_deepsnow", "boundary_verts", "interior_verts",
       "bnd_by_other", "bnd_by_dead", "bnd_by_open_edge", "verts_coincident",
       "rej_degenerate", "rej_wall_render", "rej_backface", "rej_slope", "rej_unclassified",
       "rej_not_soft", "rej_overlay_grass", "rej_no_support", "rej_support_above",
       "rej_support_wall", "rej_support_obstacle", "rej_support_material", "rej_seafloor",
       "rej_no_headroom", "rej_tie_not_terrain", "rej_off_island",
       "coll_soft", "coll_mode_ground", "coll_mode_wall_soft", "coll_mode_obstacle_soft",
       "static_cells", "static_objects", "static_from_collision", "static_from_tie",
       "static_skipped_large", "depression_verts", "deep_islands",
       "population_empty"] + DEFECTS
# PAR NIVEAU : le contrat demande « chacun compte par niveau ».
PER = ["hull_tris", "hull_verts", "hull_verts_thick", "hull_verts_tested", "boundary_verts",
       "interior_verts", "verts_coincident", "soft_tris", "deep_islands", "fixpoint_rounds",
       "rej_backface", "rej_slope", "rej_support_wall", "rej_overlay_grass", "rej_seafloor",
       "rej_no_support", "rej_no_headroom", "rej_tie_not_terrain", "rej_off_island",
       "rej_support_material", "rej_support_above", "rej_unclassified",
       "coll_mode_wall_soft", "coll_mode_obstacle_soft",
       "static_objects", "static_cells", "depression_verts"] + DEFECTS
FLOATS = ["static_area_u2", "static_area_m2", "objdist_min_u", "objdist_med_u", "objdist_max_u",
          "thick_min_u", "thick_med_u", "thick_max_u",
          "deep_raw_min_u", "deep_raw_med_u", "deep_raw_max_u"]
TOPS = ["reject_tex_top", "support_mat_top", "soft_src_top", "hull_src_top"]

tot = {k: 0 for k in NUM}
seen = 0
empty = 0
empty_list = []
soft_levels = []      # ceux qui portent effectivement de la coque
rounds_max = 0
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
        kv[k[len("soft_map_"):]] = v
    if "hull_verts" not in kv:
        continue
    seen += 1
    if int(kv.get("render_offered", 0)) == 0:
        empty += 1
        empty_list.append(lvl)
    for k in NUM:
        tot[k] += int(kv.get(k, 0))
    rounds_max = max(rounds_max, int(kv.get("fixpoint_rounds", 0)))
    if int(kv.get("hull_verts", 0)) > 0:
        soft_levels.append(lvl)
    # `proof_run.sh` n'accepte qu'un nom de cle en [A-Za-z0-9_] : `test-zone` porte un tiret et
    # ses 40 lignes seraient JETEES en silence, denominateur compris.
    lk = lvl.replace("-", "_")
    for k in PER:
        print("soft_support_%s_%s=%s" % (lk, k, kv.get(k, "0")))
    # EN UNITES *ET* EN METRES : PITFALLS l.411, toute grandeur publiee l'est des deux facons.
    for k in FLOATS:
        raw = float(kv.get(k, "0") or 0)
        print("soft_support_%s_%s=%.6f" % (lk, k, raw))
        if k.endswith("_u"):
            print("soft_support_%s_%s_m=%.6f" % (lk, k[:-2], raw / U))
        elif k.endswith("_u2"):
            print("soft_support_%s_%s_m2=%.6f" % (lk, k[:-3], raw / (U * U)))
    for k in TOPS:
        print("soft_support_%s_%s=%s" % (lk, k, kv.get(k, "-")))
    # LES CONGERES, ILOT PAR ILOT (contrat, terme 2). Epaisseur CUITE et epaisseur MESUREE.
    for k, v in sorted(kv.items()):
        if not k.startswith("island_"):
            continue
        parts = dict(x.split(":", 1) for x in v.split(",") if ":" in x)
        out = []
        for f in ("tris", "verts"):
            out.append("%s:%s" % (f, parts.get(f, "0")))
        for f in ("min_u", "med_u", "max_u", "raw_min_u", "raw_med_u", "raw_max_u"):
            val = float(parts.get(f, "0") or 0)
            out.append("%s:%.3f" % (f, val))
            out.append("%s_m:%.6f" % (f[:-2], val / U))
        print("soft_support_%s_%s=%s" % (lk, k, ",".join(out)))

for k in NUM:
    if k in DEFECTS:
        continue  # publies ci-dessous, une seule fois, comme termes de la porte
    print("soft_support_%s=%d" % (k, tot[k]))
for k in FLOATS:
    pass
print("soft_support_levels_counted=%d" % seen)
print("soft_support_levels_empty=%d" % empty)
print("soft_support_levels_empty_list=%s" % (",".join(empty_list) if empty_list else "-"))
print("soft_support_levels_with_hull=%d" % len(soft_levels))
print("soft_support_levels_with_hull_list=%s" % (",".join(soft_levels) if soft_levels else "-"))
print("soft_support_fixpoint_rounds_max=%d" % rounds_max)
# TEMOIN DE NON-VACUITE. Une porte a zero sur une population vide ne mesure rien : on publie donc
# la population testee, les sommets qui ont RECU une epaisseur, et les rejets NON NULS.
print("soft_support_population_empty=%d" % (1 if tot["render_offered"] == 0 else 0))
print("soft_support_hull_empty=%d" % (1 if tot["hull_verts"] == 0 else 0))
print("soft_support_thick_empty=%d" % (1 if tot["hull_verts_thick"] == 0 else 0))
rejects = ["rej_backface", "rej_slope", "rej_support_wall", "rej_overlay_grass", "rej_seafloor",
           "rej_no_support", "rej_no_headroom", "rej_tie_not_terrain", "rej_off_island",
           "rej_support_material", "rej_support_above", "rej_not_soft", "rej_wall_render",
           "rej_degenerate", "rej_unclassified"]
print("soft_support_rejects_named=%d" % len(rejects))
print("soft_support_rejects_nonzero=%d" % sum(1 for r in rejects if tot[r] > 0))
print("soft_support_rejects_list=%s" % ",".join("%s:%d" % (r, tot[r]) for r in rejects))

# ---- LA PORTE. HUIT TERMES, PUBLIES SEPAREMENT JUSTE AU-DESSUS, ET LEUR SOMME.
#  1..5 les cinq defauts de cuisson, relus sur la donnee CUITE (position, direction, epaisseur)
#  6    levels_failed_n   un niveau que le recensement n'a pas su lire (denominateur honnete)
#  7    levels_empty      un niveau liste dont la population de rendu est vide (non-vacuite)
#  8    thick_empty       AUCUN sommet n'a recu d'epaisseur : la porte serait verte par inaction
terms = [(k, tot[k]) for k in DEFECTS]
terms.append(("levels_failed_n", failed_n))
terms.append(("levels_empty", empty))
terms.append(("thick_empty", 1 if tot["hull_verts_thick"] == 0 else 0))
for k, v in terms:
    print("soft_support_%s=%d" % (k, v))
print("soft_support_gate_terms=%d" % len(terms))
print("soft_support_gate_terms_list=%s" % ",".join("%s:%d" % t for t in terms))
print("soft_thickness_defects=%d" % sum(v for _, v in terms))
PY
exit 0
