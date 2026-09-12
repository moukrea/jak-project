#!/usr/bin/env bash
# lib/subsecond_freshness_selftest.sh — LE BANC DE `lib/freshness.sh` ET DE SES QUATRE SITES.
#
# IL MESURE UN COMPORTEMENT, PAS UN TEXTE. Chaque jambe seme un etat dans un depot JETABLE et
# fait jouer LA VRAIE GARDE — `lib/deploy_verify.sh`, `lib/deploy_verify_assets.sh`,
# `lib/build_x86.sh`, `orchestrator.py` — jamais une copie de sa logique. Un deuxieme code
# diverge en silence, et c'est precisement ce qu'on est en train de reparer.
#
# L'ETAT SEME EST TOUJOURS LE MEME, celui du signalement : DEUX FICHIERS DANS LA MEME SECONDE
# ENTIERE, la source etant la plus recente de 0,8 s. Une porte qui lit `stat -c %Y` d'un cote et
# `find -printf %T@ | cut -d. -f1` de l'autre ne peut pas les separer.
#
# LES DEUX BRAS, TOUJOURS. Le bras APRES doit REFUSER ; le bras AVANT — le dernier etat du
# MEME fichier sans le correctif, ancre par `lib/ablation_anchor.sh` sur un MARQUEUR et jamais
# lu a `HEAD:`, qui s'accuserait lui-meme des le commit qui corrige — doit ACCEPTER. Sans lui,
# « la porte refuse » est vert par CONSTRUCTION des qu'on l'a ecrit, et rien ne dit que le
# defaut existait.
#
# ET UN CONTROLE SAIN A CHAQUE FOIS. Une porte qui refuserait TOUT ecart infra-seconde serait
# verte sur la jambe perimee sans rien prouver : on seme donc aussi l'etat inverse — l'artefact
# ecrit APRES sa source, dans la meme seconde — et la porte doit le LAISSER PASSER.
#
# Les horodatages sont POSES (`touch -d '@<epoch>.<ns>'`), jamais attendus : une jambe qui court
# contre la seconde qui tourne mesure sa propre chance.
#
# Sortie : `cle=valeur` sur stdout. `-1` = la jambe n'a pas pu conclure ; JAMAIS 0, qui passerait
# une porte `== 0` en silence.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "selftest_ran=0"; exit 1; }
AP="$ROOT/.autoport"
T="${TMPDIR:-/tmp}/autoport-subsecond-$$"
rm -rf "$T"; mkdir -p "$T" || { echo "selftest_ran=0"; exit 1; }
trap 'rm -rf "$T"' EXIT

pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }

# La seconde de reference et les trois instants qu'on y place. Tout tient dans UNE seconde
# entiere : `1700000000`. Un lecteur tronque a la seconde voit trois fois le meme chiffre.
SEC=1700000000
TOT="@$SEC.100000000"   # le plus ancien
MID="@$SEC.500000000"   # l'egalite se joue ici
TARD="@$SEC.900000000"  # le plus recent

# ====================================================== 0. LA GRANULARITE REELLE DU DISQUE ====
# Elle n'est pas un detail de decor : c'est ce qui decide si `douteux` est un cas d'ecole ou un
# cas reel. Deux fichiers ecrits a la suite peuvent recevoir le MEME horodatage a la nanoseconde
# si l'horloge de l'inode n'a pas avance entre les deux.
. "$AP/lib/freshness.sh" || { echo "selftest_ran=0"; exit 1; }
EGAUX=0; TIC=-1
for i in 1 2 3 4 5 6 7 8 9 10; do
  : > "$T/tic.a"; : > "$T/tic.b"
  a=$(fr_mtime_ns "$T/tic.a"); b=$(fr_mtime_ns "$T/tic.b")
  if [ "$a" = "$b" ]; then EGAUX=$((EGAUX+1));
  else d=$((b - a)); [ "$d" -gt 0 ] && { [ "$TIC" -lt 0 ] || [ "$d" -lt "$TIC" ]; } && TIC=$d; fi
done
pub fs_ecritures_jumelles 10
pub fs_paires_egales "$EGAUX"
pub fs_tic_min_ns "$TIC"
pub fs_sous_seconde_non_nulle "$([ "$(fr_resolution "$(fr_mtime_ns "$T/tic.a")")" = ns ] && echo 1 || echo 0)"

# =============================================================== LE DEPOT JETABLE =============
# Les deux gardes font `cd "$(git rev-parse --show-toplevel)"` : le bac a sable DOIT etre un
# depot git, sinon elles remontent dans le vrai et mesurent autre chose que ce qu'on a seme.
BAC="$T/bac"
mkdir -p "$BAC" && git -C "$BAC" init -q 2>/dev/null || { echo "selftest_ran=0"; exit 1; }
mkdir -p "$BAC/.autoport/lib" "$BAC/game/graphics" "$BAC/game/kernel" "$BAC/android" \
         "$BAC/build-android/lib/arm64-v8a" "$BAC/out/jak1/iso" "$BAC/goal_src/jak1"
cp "$AP/lib/freshness.sh" "$BAC/.autoport/lib/freshness.sh"

# Le faux `adb` : il ne rend QUE ce qu'il faut pour amener chaque garde a sa comparaison de
# fraicheur, et rien de plus. Ce qui vient apres (la chaine d'empreintes, les md5) echoue, et
# c'est voulu — on ne juge pas le code de retour, on juge CE QUE LA GARDE A DIT sur la fraicheur.
cat > "$T/adb" <<'ADB'
#!/usr/bin/env bash
case "$*" in
  *devices*) printf 'List of devices attached\n%s\tdevice\n' "${FAUX_SERIAL:-serie0}" ;;
  *"ls files/cgo/"*) exit 0 ;;
  *) exit 0 ;;
esac
ADB
chmod +x "$T/adb"

# Les deux etats semes, et l'etat d'egalite. `semer <artefact-ns> <source-ns>` place les DEUX
# familles d'un coup : le libgk.so et sa source C++, le CGO et sa source GOAL.
semer(){
  local a="$1" s="$2"
  printf 'x\n' > "$BAC/build-android/lib/arm64-v8a/libgk.so"
  printf 'x\n' > "$BAC/game/graphics/sonde.cpp"
  printf 'x\n' > "$BAC/out/jak1/iso/GAME.CGO"
  printf 'x\n' > "$BAC/goal_src/jak1/sonde.gc"
  touch -d "$a" "$BAC/build-android/lib/arm64-v8a/libgk.so" "$BAC/out/jak1/iso/GAME.CGO"
  touch -d "$s" "$BAC/game/graphics/sonde.cpp" "$BAC/goal_src/jak1/sonde.gc"
}

# `jouer <script> <marqueur-de-vert>` : lance la garde dans le bac et rend `accepte` ou `refuse`.
# LE VERDICT SE LIT SUR CE QUE LA GARDE A IMPRIME, jamais sur son code de retour : les deux bras
# meurent plus loin (pas d'APK, pas de md5) et rendraient le meme chiffre.
jouer(){
  local script="$1" vert="$2" sortie
  sortie=$(cd "$BAC" && ADB="$T/adb" FAUX_SERIAL=serie0 \
           AUTOPORT_FRESHNESS_TRACE="${TRACE:-}" bash "$script" serie0 jak1 2>&1)
  printf '%s\n' "$sortie" > "$T/derniere-sortie.txt"
  if printf '%s' "$sortie" | grep -qF "$vert"; then echo accepte; else echo refuse; fi
}

# Le bras d'AVANT d'un chemin, ecrit dans le bac. `-` si aucun etat d'avant n'existe.
avant(){ # <chemin-relatif> <marqueur> <destination>
  local c m
  c=$(bash "$AP/lib/ablation_anchor.sh" "$ROOT" "$1" "$2" commit 2>/dev/null)
  [ -n "$c" ] || return 1
  git -C "$ROOT" show "$c:$1" > "$3" 2>/dev/null || return 1
  printf '%s' "$c"
}

# ================================================= 1. `lib/deploy_verify.sh` (libgk vs source) =
VERT_DV="ok: libgk.so newer than newest source"
MARQ=fr_verdict
cp "$AP/lib/deploy_verify.sh" "$BAC/.autoport/lib/deploy_verify.sh"
DV_AV_REF=$(avant .autoport/lib/deploy_verify.sh "$MARQ" "$BAC/.autoport/lib/deploy_verify-avant.sh" || true)
eval "$(bash "$AP/lib/ablation_anchor.sh" "$ROOT" .autoport/lib/deploy_verify.sh "$MARQ" kv 2>/dev/null | sed 's/^/DV_/')"
pub dv_avant_ref     "${DV_AV_REF:--}"
pub dv_avant_methode "${DV_anchor_method:-absent}"
pub dv_avant_octets  "$(stat -c %s "$BAC/.autoport/lib/deploy_verify-avant.sh" 2>/dev/null || echo 0)"

TRACE="$T/trace-dv.txt"; : > "$TRACE"
semer "$TOT" "$TARD"                       # source PLUS RECENTE, meme seconde -> doit REFUSER
pub dv_apres_perime "$(jouer .autoport/lib/deploy_verify.sh "$VERT_DV")"
pub dv_avant_perime "$(jouer .autoport/lib/deploy_verify-avant.sh "$VERT_DV")"
semer "$TARD" "$TOT"                       # CONTROLE SAIN : artefact plus recent -> doit ACCEPTER
pub dv_apres_sain  "$(jouer .autoport/lib/deploy_verify.sh "$VERT_DV")"
pub dv_avant_sain  "$(jouer .autoport/lib/deploy_verify-avant.sh "$VERT_DV")"
semer "$MID" "$MID"                        # EGALITE A LA NANOSECONDE -> doit REFUSER (douteux)
pub dv_apres_egal  "$(jouer .autoport/lib/deploy_verify.sh "$VERT_DV")"
pub dv_avant_egal  "$(jouer .autoport/lib/deploy_verify-avant.sh "$VERT_DV")"
# LA RESOLUTION, RELEVEE A L'EXECUTION. Une troncature d'un seul cote se LIT ici : la trace
# porte les deux valeurs telles que la garde les a comparees, et `res_*` dit si la sous-seconde
# a survecu. C'est le point d'APPEL qui parle, pas une lecture du texte du script.
pub dv_trace_lignes  "$(grep -c . "$TRACE" 2>/dev/null || echo 0)"
pub dv_res_art       "$(sed -n 's/.* res_art=\([a-z]*\) .*/\1/p' "$TRACE" | sort -u | paste -sd, -)"
pub dv_res_src       "$(sed -n 's/.* res_src=\([a-z]*\)$/\1/p' "$TRACE" | sort -u | paste -sd, -)"
pub dv_verdicts      "$(sed -n 's/.* verdict=\([a-z]*\) .*/\1/p' "$TRACE" | paste -sd, -)"
pub dv_sites         "$(sed -n 's/^site=\([^ ]*\) .*/\1/p' "$TRACE" | sort -u | paste -sd, -)"
DV_EGAL=$(grep -c 'verdict=douteux' "$TRACE" 2>/dev/null || echo 0)

# ============================================ 2. `lib/deploy_verify_assets.sh` (CGO vs GOAL) ==
VERT_DVA="built CGO/DGO newer than newest goal_src"
cp "$AP/lib/deploy_verify_assets.sh" "$BAC/.autoport/lib/deploy_verify_assets.sh"
DVA_AV_REF=$(avant .autoport/lib/deploy_verify_assets.sh "$MARQ" "$BAC/.autoport/lib/deploy_verify_assets-avant.sh" || true)
eval "$(bash "$AP/lib/ablation_anchor.sh" "$ROOT" .autoport/lib/deploy_verify_assets.sh "$MARQ" kv 2>/dev/null | sed 's/^/DVA_/')"
pub dva_avant_ref     "${DVA_AV_REF:--}"
pub dva_avant_methode "${DVA_anchor_method:-absent}"
pub dva_avant_octets  "$(stat -c %s "$BAC/.autoport/lib/deploy_verify_assets-avant.sh" 2>/dev/null || echo 0)"

TRACE="$T/trace-dva.txt"; : > "$TRACE"
semer "$TOT" "$TARD"
pub dva_apres_perime "$(jouer .autoport/lib/deploy_verify_assets.sh "$VERT_DVA")"
pub dva_avant_perime "$(jouer .autoport/lib/deploy_verify_assets-avant.sh "$VERT_DVA")"
semer "$TARD" "$TOT"
pub dva_apres_sain   "$(jouer .autoport/lib/deploy_verify_assets.sh "$VERT_DVA")"
pub dva_avant_sain   "$(jouer .autoport/lib/deploy_verify_assets-avant.sh "$VERT_DVA")"
semer "$MID" "$MID"
pub dva_apres_egal   "$(jouer .autoport/lib/deploy_verify_assets.sh "$VERT_DVA")"
pub dva_avant_egal   "$(jouer .autoport/lib/deploy_verify_assets-avant.sh "$VERT_DVA")"
pub dva_trace_lignes "$(grep -c . "$TRACE" 2>/dev/null || echo 0)"
pub dva_res_art      "$(sed -n 's/.* res_art=\([a-z]*\) .*/\1/p' "$TRACE" | sort -u | paste -sd, -)"
pub dva_res_src      "$(sed -n 's/.* res_src=\([a-z]*\)$/\1/p' "$TRACE" | sort -u | paste -sd, -)"
pub dva_verdicts     "$(sed -n 's/.* verdict=\([a-z]*\) .*/\1/p' "$TRACE" | paste -sd, -)"
pub dva_sites        "$(sed -n 's/^site=\([^ ]*\) .*/\1/p' "$TRACE" | sort -u | paste -sd, -)"
DVA_EGAL=$(grep -c 'verdict=douteux' "$TRACE" 2>/dev/null || echo 0)

# ================================================ 3. `lib/build_x86.sh` (binaire vs entrees) ==
# La porte du bureau lisait deja a la nanoseconde ; ce qu'elle acceptait encore, c'est l'EGALITE
# (`-ge`). On lui seme un arbre ninja jetable ou le binaire et son entree portent EXACTEMENT le
# meme horodatage, plus le controle sain a cote.
BX=-1; BX_SAIN=-1; BX_EGAL_V="-"; BX_EGAL=0
NT="$T/ninja"; mkdir -p "$NT"
printf 'int main(void){return 0;}\n' > "$NT/m.c"
cat > "$NT/build.ninja" <<'NJ'
rule cc
  command = gcc -c $in -o $out
  description = CC $out
rule link
  command = gcc $in -o $out
  description = LINK $out
build m.o: cc m.c
build app: link m.o
NJ
if ninja -C "$NT" app >/dev/null 2>&1; then
  TRACE="$T/trace-bx.txt"; : > "$TRACE"
  touch -d "$TOT" "$NT/m.o" "$NT/m.c"; touch -d "$TARD" "$NT/app"
  S=$(AUTOPORT_FRESHNESS_TRACE="$TRACE" bash "$AP/lib/build_x86.sh" --dir "$NT" --target app --check-only 2>/dev/null)
  BX_SAIN=$(printf '%s\n' "$S" | sed -n 's/^bx_bin_verdict=//p' | tail -1)
  touch -d "$MID" "$NT/m.o" "$NT/app"
  E=$(AUTOPORT_FRESHNESS_TRACE="$TRACE" bash "$AP/lib/build_x86.sh" --dir "$NT" --target app --check-only 2>/dev/null); BX=$?
  BX_EGAL_V=$(printf '%s\n' "$E" | sed -n 's/^bx_bin_verdict=//p' | tail -1)
  BX_EGAL=$(grep -c 'verdict=douteux' "$TRACE" 2>/dev/null || echo 0)
  pub bx_sites "$(sed -n 's/^site=\([^ ]*\) .*/\1/p' "$TRACE" | sort -u | paste -sd, -)"
  pub bx_res_art "$(sed -n 's/.* res_art=\([a-z]*\) .*/\1/p' "$TRACE" | sort -u | paste -sd, -)"
  pub bx_res_src "$(sed -n 's/.* res_src=\([a-z]*\)$/\1/p' "$TRACE" | sort -u | paste -sd, -)"
else
  pub bx_sites -; pub bx_res_art -; pub bx_res_src -
fi
pub bx_sain_verdict  "${BX_SAIN:--}"
pub bx_egal_verdict  "${BX_EGAL_V:--}"
pub bx_egal_rc       "$BX"

pub egalites_rencontrees "$(( DV_EGAL + DVA_EGAL + BX_EGAL ))"
pub selftest_ran 1
