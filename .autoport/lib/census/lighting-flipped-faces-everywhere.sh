#!/usr/bin/env bash
# census/lighting-flipped-faces-everywhere.sh — FACES A L'ENVERS : LA PREUVE EST DANS L'ASSET.
#
# Owner 25/09 : « Pourquoi le moteur devrait porter le truc des flipped faces defects si c'est un
# truc qu'on fait sur les assets du jeu directement ? ». La correction vit dans le pack d'assets
# RECHARGES : un compagnon <niveau>.meshweld par niveau, cuit par `tools/mesh_audit --bake` depuis
# le .fr3 extrait de l'ISO (intact), qui oriente la normale stockee de chaque surface du decor du
# cote de la collision coplanaire. Le jeu le prend s'il est la ; sinon l'original tel quel (aucun
# repli dans les shaders).
#
# CE RECENSEMENT NE LANCE PAS LE JEU. Il ouvre le pack livre et publie :
#   flipped_asset_defects = flipped_asset_reversed      triangles du decor dont la normale
#                                                       stockee s'oppose a la collision coplanaire,
#                                                       relus APRES application du compagnon DU PACK
#                         + flipped_asset_levels_missing  niveaux AVEC du decor sans compagnon dans
#                                                         le pack (un niveau sans decor, GAME/title,
#                                                         n'a rien a orienter : publie a part)
#                         + flipped_asset_levels_refused  compagnon present mais refuse au chargement
#                         + flipped_shader_flips          retournements de normale d'asset restant
#                                                         dans les shaders
#                         + flipped_pack_refused          compagnons refuses par la regle
#                                                         d'appartenance de release_verify.sh
# TEMOINS (sinon le recensement sort en erreur et n'ecrit pas la cle jugee) :
#   flipped_asset_reversed_before > 0  la meme mesure sur l'asset d'ORIGINE voit le defaut
#   flipped_shader_control_hits > 0    le detecteur retrouve le retournement du shader d'avant
#                                      (commit 8ac0afe896)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
ROOT=$PWD
export TMPDIR="${TMPDIR:-$HOME/.autoport-tmp}"
mkdir -p "$TMPDIR" || exit 1
T=$(mktemp -d "$TMPDIR/flipped-asset.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
die(){ printf 'census lighting-flipped-faces-everywhere: %s\n' "$*" >&2; exit 1; }

PACK="$ROOT/android/app/src/jak1/assets-slim/bundle/jak1_custom.zip"
FR3="$ROOT/out/jak1/fr3"
SHADERS="$ROOT/game/graphics/opengl_renderer/shaders"
[ -f "$PACK" ] || die "pack recharge absent : $PACK (bash android/build_custom_pack.sh jak1)"
[ -d "$FR3" ] || die "$FR3 absent (niveaux extraits de l'ISO)"

# --- 1. l'outil, par la PORTE de l'arbre (sort en 4 sur un binaire plus vieux que ses entrees)
bash .autoport/lib/build_x86.sh --target mesh_audit > "$T/build.log" 2>&1 \
  || die "build_x86.sh --target mesh_audit a rendu $? (voir $T/build.log)"
BIN="$ROOT/build/tools/mesh_audit/mesh_audit"
[ -x "$BIN" ] || die "$BIN absent apres la porte"

# --- 2. les compagnons DU PACK, et la regle d'appartenance de release_verify.sh
python3 - "$PACK" "$T/pack" > "$T/members.txt" <<'PY' || die "lecture du pack impossible"
import sys, zipfile, os
z = zipfile.ZipFile(sys.argv[1])
os.makedirs(os.path.join(sys.argv[2], 'fr3'), exist_ok=True)
for n in z.namelist():
    if n.startswith('fr3/') and n.endswith('.meshweld') and '/' not in n[4:]:
        open(os.path.join(sys.argv[2], n), 'wb').write(z.read(n))
        print(n)
PY
MEMBERS=$(grep -c . "$T/members.txt")
mapfile -t MW < "$T/members.txt"
bash .autoport/lib/custom_pack_membership.sh --check 0 0 "${MW[@]}" > "$T/membership.txt" \
  || die "custom_pack_membership.sh a echoue"
PACK_REFUSED=$(sed -n 's/^refused=//p' "$T/membership.txt")
[ -n "$PACK_REFUSED" ] || die "custom_pack_membership.sh n'a pas rendu refused="

# fraicheur du pack contre la cuisson du depot (information : le pack EST ce qui part)
STALE=0
for m in "${MW[@]}"; do
  b=${m#fr3/}
  [ -f "$FR3/$b" ] && cmp -s "$FR3/$b" "$T/pack/$m" || STALE=$((STALE + 1))
done

# --- 3. relecture hors ligne : .fr3 d'origine + compagnon du pack
"$BIN" --fr3-dir "$FR3" --check-orient "$T/pack/fr3" > "$T/check.txt" 2>&1 \
  || die "mesh_audit --check-orient a rendu $? : $(tail -3 "$T/check.txt")"
TOT=$(grep -a '^CHECK-ORIENT-TOTAL ' "$T/check.txt" | tail -1)
[ -n "$TOT" ] || die "pas de ligne CHECK-ORIENT-TOTAL : $(tail -3 "$T/check.txt")"
v(){ printf '%s' "$TOT" | grep -oE "(^| )$1=[0-9]+" | cut -d= -f2; }
LEVELS=$(v levels); APPLIED=$(v sidecars_applied); MISSING=$(v levels_missing)
REFUSED=$(v levels_refused); NODECOR=$(v levels_no_decor); TRIS=$(v tris); JUDGED=$(v judged); UNJ=$(v unjudged)
NONORM=$(v no_normal); REV=$(v reversed); REVB=$(v reversed_before); JUDB=$(v judged_before)
for x in LEVELS APPLIED MISSING REFUSED NODECOR TRIS JUDGED REV REVB; do
  [ -n "${!x}" ] || die "champ $x absent de : $TOT"
done
BADLEV=$(grep -a '^CHECK-ORIENT level=' "$T/check.txt" \
  | awk '{l="";r=0;s="";for(i=1;i<=NF;i++){split($i,a,"=");if(a[1]=="level")l=a[2];if(a[1]=="reversed")r=a[2];if(a[1]=="sidecar")s=a[2]} if(r>0||s!="applied")printf "%s%s:%s:%s",(n++?",":""),l,s,r}')

# --- 4. shaders : retournements de normale d'asset restants + temoin sur le shader d'avant
python3 .autoport/lib/census/flipped_faces_shader_scan.py "$SHADERS" > "$T/shaders.txt" \
  || die "flipped_faces_shader_scan.py a echoue"
SFLIPS=$(sed -n 's/^flips=//p' "$T/shaders.txt"); SFILES=$(sed -n 's/^files=//p' "$T/shaders.txt")
mkdir -p "$T/control"
for f in shade.glsl merc2.frag merc2.vert; do
  git show "8ac0afe896:game/graphics/opengl_renderer/shaders/$f" > "$T/control/$f" 2>/dev/null \
    || die "temoin : $f introuvable au commit 8ac0afe896"
done
SCTRL=$(python3 .autoport/lib/census/flipped_faces_shader_scan.py "$T/control" | sed -n 's/^flips=//p')
SLIST=$(grep -a '^flip ' "$T/shaders.txt" | awk '{sub(".*/shaders/","",$2); printf "%s%s", (n++?",":""), $2}')

# --- 5. temoins : un instrument aveugle ne juge pas
[ "${REVB:-0}" -gt 0 ] || die "temoin aveugle : 0 triangle a l'envers dans l'asset d'ORIGINE ($TOT)"
[ "${SCTRL:-0}" -gt 0 ] || die "temoin aveugle : le detecteur ne voit pas le retournement du shader d'avant"
[ "$LEVELS" -gt 0 ] && [ "$TRIS" -gt 0 ] || die "rien relu : $TOT"

DEFECTS=$((REV + MISSING + REFUSED + SFLIPS + PACK_REFUSED))
cat <<EOF
flipped_asset_levels_checked=$LEVELS
flipped_asset_levels_applied=$APPLIED
flipped_asset_levels_missing=$MISSING
flipped_asset_levels_refused=$REFUSED
flipped_asset_levels_no_decor=$NODECOR
flipped_asset_tris_read=$TRIS
flipped_asset_tris_judged=$JUDGED
flipped_asset_tris_unjudged=$UNJ
flipped_asset_tris_no_normal=$NONORM
flipped_asset_reversed=$REV
flipped_asset_judged_before=$JUDB
flipped_asset_reversed_before=$REVB
flipped_asset_bad_levels=${BADLEV:--}
flipped_pack_meshweld_members=$MEMBERS
flipped_pack_refused=$PACK_REFUSED
flipped_pack_stale_vs_repo=$STALE
flipped_shader_files=$SFILES
flipped_shader_flips=$SFLIPS
flipped_shader_flip_list=${SLIST:--}
flipped_shader_control_hits=$SCTRL
flipped_asset_defects=$DEFECTS
EOF
