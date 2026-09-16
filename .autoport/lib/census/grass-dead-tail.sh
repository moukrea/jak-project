#!/usr/bin/env bash
# census/grass-dead-tail.sh — CE QUE LA COURSE APPAREIL NE PEUT PAS DIRE.
#
# La course sur l'appareil prouve le verdict : `grass_dead_instances = construites - atteintes par
# un appel de dessin = 0`. Elle ne peut pas prouver les trois autres termes du contrat, parce
# qu'ils demandent de comparer DEUX BINAIRES :
#
#   (2) LE GAIN CHIFFRE  — combien d'instances, d'octets d'instances et d'octets de lumiere ne sont
#       plus construits. Il faut faire tourner la MEME expansion avec l'option ALLUMEE.
#   (3) RIEN DE VISIBLE NE CHANGE — les instances de la plage DESSINEE [0, droop_start) doivent
#       etre les memes. Il faut les deux dumps pour les comparer champ par champ.
#   (4) LE CHEMIN RESTE CONSTRUCTIBLE — la queue doit ETRE EMISE quand l'option est allumee a la
#       compilation. Un temoin qui ne ferait que COMPILER ne dirait pas qu'elle est emise : on
#       EXECUTE le chemin et on compte ce qu'il emet.
#
# L'INSTRUMENT N'EST PAS NEUF : `tools/grass_bake` appelle `grass_bake::expand()` — LA fonction
# conditionnee, il n'en existe qu'une — et imprime deja `instances=` et `droop_start=` sur sa ligne
# de controle de round-trip, plus un dump CSV par instance sous `--dump`. Les deux bras sortent
# de la MEME source, compilee ici, aux memes options : le seul delta est `-DOG_FEAT_GRASS_OVERHANG=1`.
#
# NIVEAU : training (le seul cuit et valide, acquis/grass.sh juge la meme pose). Curseur 150 =
# le defaut de livraison que la ligne de round-trip mesure.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

LVL=training
T=$(mktemp -d "${TMPDIR:-/tmp}/grass-dead-tail.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
die(){ printf 'census grass-dead-tail: %s\n' "$*" >&2; exit 1; }

[ -f "out/jak1/fr3/$LVL.fr3" ] || die "out/jak1/fr3/$LVL.fr3 absent : pas de donnee a etendre."

# ---- BRAS LIVRE (option ETEINTE). Par la PORTE de l'arbre : elle repare .ninja_deps et sort en 4
# si le binaire est plus vieux qu'une de ses entrees, donc ce bras ne peut pas etre un vieux binaire.
bash .autoport/lib/build_x86.sh --target grass_bake > "$T/build-off.log" 2>&1 \
  || die "build_x86.sh --target grass_bake a rendu $? (voir $T/build-off.log)"
OFFBIN=build/tools/grass_bake/grass_bake
[ -x "$OFFBIN" ] || die "$OFFBIN absent apres la porte."

# ---- BRAS OPTION ALLUMEE. On relit les commandes de ninja plutot que de les recopier : un drapeau
# recopie a la main mesurerait la recopie. Seul `GrassBakeCore.cpp.o` est recompile (c'est le seul
# fichier conditionne) ; `main.cpp.o` est celui du bras livre, le drapeau ne le traverse pas.
CMDS="$T/cmds.txt"
ninja -C build -t commands grass_bake > "$CMDS" 2>/dev/null || die "ninja -t commands a echoue."
CORE=$(grep -m1 -- 'GrassBakeCore.cpp.o' "$CMDS") || die "commande de GrassBakeCore.cpp.o introuvable."
LINK=$(grep -m1 -- '-o tools/grass_bake/grass_bake ' "$CMDS") || die "commande de lien introuvable."
OLDOBJ='tools/grass_bake/CMakeFiles/grass_bake.dir/__/__/game/graphics/opengl_renderer/GrassBakeCore.cpp.o'
case "$CORE" in *"$OLDOBJ"*) ;; *) die "la commande de compilation ne nomme pas $OLDOBJ." ;; esac
case "$LINK" in *"$OLDOBJ"*) ;; *) die "la commande de lien ne nomme pas $OLDOBJ." ;; esac

NEWOBJ="$T/GrassBakeCore.on.o"
# LE BRAS ALLUME SE LIE DANS L'ARBRE, PAS DANS LE BAC A SABLE. `file_util::get_jak_project_dir()`
# remonte depuis le CHEMIN DE L'EXECUTABLE ; lance depuis /tmp, le meme binaire meurt sur
# `Assertion failed: g_file_path_info.initialized` avant d'avoir lu un triangle. Il est retire
# par le trap : ce bras ne laisse rien derriere lui.
ONBIN="$PWD/build/tools/grass_bake/grass_bake.on.$$"  # ABSOLU : le lien tourne avec cd build
trap 'rm -rf "$T" "$ONBIN"' EXIT
( cd build && eval "${CORE//$OLDOBJ/$NEWOBJ}"' -DOG_FEAT_GRASS_OVERHANG=1' ) > "$T/cc-on.log" 2>&1 \
  || die "compilation du bras ALLUME a echoue (voir $T/cc-on.log)"
LINK2=${LINK//$OLDOBJ/$NEWOBJ}
LINK2=${LINK2//-o tools\/grass_bake\/grass_bake /-o $ONBIN }
# Le fichier de dependances du LIEN n'est pas nomme d'apres l'objet : sans ce retrait, ce bras
# ecraserait le `link.d` du bras livre dans l'arbre, et la porte relierait pour rien a la course
# suivante. On ne laisse aucune trace de ce bras dans `build/`.
LINK2=$(printf '%s' "$LINK2" | sed 's#-Wl,--dependency-file=[^ ]*##')
( cd build && eval "$LINK2" ) > "$T/ld-on.log" 2>&1 \
  || die "lien du bras ALLUME a echoue (voir $T/ld-on.log)"
[ -x "$ONBIN" ] || die "$ONBIN absent apres le lien."

# ---- LES DEUX EXPANSIONS. `--out` part dans le bac a sable : aucune des cinq `.grassbake` livrees
# n'est touchee (elles sont de la DONNEE, pas un produit de cet item).
run_arm(){  # $1 = binaire, $2 = prefixe de sortie
  "$1" "$LVL" --fr3-dir out/jak1/fr3 --out "$T/$2.grassbake" --dump "$T/$2" > "$T/$2.log" 2>&1 \
    || die "le bras $2 est sorti en $? (voir $T/$2.log)"
  grep -m1 'round-trip @150' "$T/$2.log" > "$T/$2.rt" \
    || die "le bras $2 n'a pas imprime sa ligne de round-trip."
  grep -q 'IDENTICAL' "$T/$2.rt" || die "le bras $2 a rendu un round-trip MISMATCH : son expansion n'est pas reproductible."
}
run_arm "$OFFBIN" off
run_arm "$ONBIN"  on

num(){ sed -n "s/.*$2=\([0-9]\+\).*/\1/p" "$T/$1.rt" | head -1; }
OFF_N=$(num off instances);  OFF_D=$(num off droop_start)
ON_N=$(num on instances);    ON_D=$(num on droop_start)
for v in OFF_N OFF_D ON_N ON_D; do
  case "${!v}" in ''|*[!0-9]*) die "$v illisible dans la ligne de round-trip." ;; esac
done

echo "grass_tail_level=$LVL"
echo "grass_tail_slider=150"
echo "grass_tail_off_instances=$OFF_N"
echo "grass_tail_off_droop_start=$OFF_D"
echo "grass_tail_off_tail=$((OFF_N - OFF_D))"
echo "grass_tail_on_instances=$ON_N"
echo "grass_tail_on_droop_start=$ON_D"
echo "grass_tail_on_tail=$((ON_N - ON_D))"
echo "grass_tail_saved_instances=$((ON_N - OFF_N))"
echo "grass_tail_saved_inst_bytes=$(( (ON_N - OFF_N) * 64 ))"
echo "grass_tail_saved_light_bytes=$(( (ON_N - OFF_N) * 4 ))"

# ---- LA PLAGE DESSINEE, CHAMP PAR CHAMP. Colonnes du dump :
# idx,px,py,pz,h,yaw,tint,curve,phase,gspare,nx,ny,nz,nspare,tri  -> `nspare` est la 14e.
# Le seul octet qui bouge est `nspare` : le marqueur que la passe walkable posait pour la queue.
# Son UNIQUE lecteur est `is_comb_orig && u_overhang > 0.5` (grass.vert:159), et `u_overhang` est
# le LITTERAL 0.0f dans les deux arbres livres (GrassRenderer.cpp, branche #else). On ne le
# suppose pas : on decode les cinq classes que le shader tire de `nspare` et on compte les rangees
# dont la classe CHANGE.
python3 - "$T/off_instances.csv" "$T/on_instances.csv" "$OFF_D" <<'PY' || die "la comparaison de la plage dessinee a echoue."
import sys
off_p, on_p, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
def rows(p, n):
    f = open(p); next(f)
    for _, l in zip(range(n), f):
        yield l.rstrip('\n').split(',')
def cls(v):
    return (v > 1.5, 2.5 < v < 4.5, 4.5 < v < 6.5, v > 8.5,
            max(0.0, min(1.0, v - 5.0)) if 4.5 < v < 6.5 else 0.0)
cmp = diff_non = diff_nsp = cls_diff = neg_on = nonzero_off = 0
for a, b in zip(rows(off_p, n), rows(on_p, n)):
    cmp += 1
    if a[:13] != b[:13] or a[14] != b[14]:
        diff_non += 1
    if a[13] != b[13]:
        diff_nsp += 1
    va, vb = float(a[13]), float(b[13])
    if vb < -0.5: neg_on += 1
    if va != 0.0: nonzero_off += 1
    if cls(va) != cls(vb): cls_diff += 1
print(f"grass_tail_rows_compared={cmp}")
print(f"grass_tail_rows_diff_excl_nspare={diff_non}")
print(f"grass_tail_rows_nspare_diff={diff_nsp}")
print(f"grass_tail_rows_nspare_neg_on={neg_on}")
print(f"grass_tail_rows_nspare_nonzero_off={nonzero_off}")
print(f"grass_tail_rows_shader_class_diff={cls_diff}")
if cmp != n:
    print(f"grass_tail_rows_short=1")
    raise SystemExit(1)
PY

# ---- L'AVANT DES TEMPS DE CHARGEMENT SUR L'APPAREIL. Il ne peut pas venir de cette course : la
# garde est une garde de COMPILATION, les deux regimes ne tiennent pas dans un binaire. Il vient de
# la course de `grass-baseline-cost`, dont cet item DEPEND, capturee sous le code REMPLACE, sur le
# meme appareil et le meme niveau. On le republie NOMME et date, jamais confondu avec l'apres.
BP=.autoport/reports/grass-baseline-cost/proof.txt
if [ -s "$BP" ]; then
  bkv(){ sed -n "s/^$1=//p" "$BP" | tail -1; }
  echo "grass_tail_before_source=grass-baseline-cost"
  echo "grass_tail_before_run=$(bkv proof_run_id)"
  echo "grass_tail_before_serial=$(bkv serial)"
  echo "grass_tail_before_sha=$(bkv sha)"
  echo "grass_tail_before_started_at=$(bkv started_at)"
  echo "grass_tail_before_preset=medium"
  echo "grass_tail_before_instances=$(bkv grass_load_medium_instances)"
  echo "grass_tail_before_drawn=$(bkv grass_load_medium_drawn)"
  echo "grass_tail_before_dead=$(bkv grass_load_medium_dead)"
  echo "grass_tail_before_inst_bytes=$(bkv grass_load_medium_inst_bytes)"
  echo "grass_tail_before_light_bytes=$(bkv grass_load_medium_light_bytes)"
  echo "grass_tail_before_expand_ms=$(bkv grass_load_medium_expand_ms)"
  echo "grass_tail_before_upload_ms=$(bkv grass_load_medium_upload_ms)"
  echo "grass_tail_before_total_ms=$(bkv grass_load_medium_total_ms)"
else
  echo "grass_tail_before_source=absent"
fi
exit 0
