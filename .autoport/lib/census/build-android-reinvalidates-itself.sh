#!/usr/bin/env bash
# census/build-android-reinvalidates-itself.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Sa sortie `cle=valeur` rejoint celle du moteur dans le meme journal. Il n'ecrit aucun champ de
# `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QUE L'ITEM CROYAIT, ET CE QUE LA MESURE DIT. Le `known_cause` annonce « chaque commit
# invalide l'arbre et relance une RECONSTRUCTION COMPLETE », « l'ordre de grandeur du bureau »
# (335 cibles, 444 s). C'EST FAUX SUR CET ARBRE, et la capture versionnee du 12/09 le chiffre :
# un commit fabrique y coute 255-260 ms et ZERO cible recompilee, contre 33 ms sans commit.
# Aucun objet de `build-android` ne depend de `SDL_revision.h` (`ninja -t deps` en compte 0),
# donc la regeneration de l'en-tete ne propage rien. LE DECLENCHEUR, LUI, EST BIEN LA : `.git/HEAD`
# et `.git/refs/heads/<branche>` etaient DEUX ENTREES de `RERUN_CMAKE`, et ninja le NOMME
# (`output build.ninja older than most recent input .../.git/refs/heads/physics-keira-clean`).
# Ce recensement juge donc ce qui est vrai : le declencheur est coupe, la constante est derivee
# et survit a une reconfiguration, le binaire livre ne bouge pas, et le gain est de ~0,2 s par
# commit — pas de 443 s. Un chiffre flatteur sur un defaut plus petit qu'annonce reste un faux
# vert ; c'est la raison de ce paragraphe.
#
# UN TERME PAR POINT DU LIVRABLE, CHAQUE TERME PUBLIE SEPAREMENT :
#   1. TROIS INVOCATIONS, dont une APRES un commit fabrique ici meme  -> ba_defaut_1
#   2. LA CONSTANTE EST DERIVEE, aucun numero de version en dur       -> ba_defaut_2
#   3. ELLE SURVIT A UNE RECONFIGURATION A NEUF                       -> ba_defaut_3
#   4. LE BINAIRE LIVRE EST IDENTIQUE avant/apres                     -> ba_defaut_4
#   5. LE GAIN, CHIFFRE, mesure des deux cotes                        -> ba_defaut_5
#   6. LE BUREAU N'A PAS BOUGE (le hors-perimetre, verifie)           -> ba_defaut_6
#
# DEUX SOURCES, jamais une seule : LA CAPTURE AVANT (`capture-<id>/`), prise sur l'arbre
# DEFECTUEUX avant toute pose, versionnee et empreinte ici — personne ne peut la refaire une fois
# la constante posee ; et L'ARBRE VIVANT, MAINTENANT, avec un commit fabrique par plomberie.
#
# INCONNU = DEFAUT. Toute cle manquante rend -1 (jamais 0, qui passerait une porte `== 0`).
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "ba_census_ran=0"; exit 1; }
cd "$ROOT" || exit 1
AP="$ROOT/.autoport"
E="$AP/lib/census/capture-build-android-reinvalidates-itself"
D="build-android"
SO="$D/lib/arm64-v8a/libgk.so"
HDR="$D/android/sdl_build/include-revision/SDL3/SDL_revision.h"
VERH="third-party/SDL/include/SDL3/SDL_version.h"
# shellcheck source=/dev/null
. "$AP/lib/android-env.sh" >/dev/null 2>&1

# Le moissonneur de proof_run.sh ne garde que `^cle=valeur$` SANS ESPACE : on colle les espaces
# ici, au point de PUBLICATION, sinon la valeur est publiee pour personne.
pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }
num(){ case "${1:-}" in ''|*[!0-9-]*) echo -1 ;; *) echo "$1" ;; esac; }
sup(){ [ "${1:--1}" -gt "${2:-0}" ] 2>/dev/null && echo 1 || echo 0; }
rev(){ sed -n 's/.*define SDL_REVISION "\([^"]*\)".*/\1/p' "$1" 2>/dev/null | tail -1; }
gitin(){ grep -o "$ROOT/\.git/[A-Za-z0-9_./-]*" "$1" 2>/dev/null | sort -u | grep -c . || true; }

pub ba_census_ran 1

# ==================================================== 0. LE TEMOIN D'AVANT, VERSIONNE =======
# Empreinte des fichiers bruts : les editer se voit. Ils ne sont pas suivis par
# `lib/verdict_sources.sh` (elle ne suit que les `.sh` et les `.py`) : leur empreinte est publiee
# ICI, a cote des chiffres qu'ils portent.
AV_DECL="$E/avant-declencheur-arm64.txt"
AV_CHRO="$E/avant-chronometrage.txt"
AV_EXPL="$E/avant-apres-commit-explain.txt"
AV_N=0
for f in "$AV_DECL" "$AV_CHRO" "$AV_EXPL"; do [ -s "$f" ] && AV_N=$((AV_N+1)); done
pub ba_avant_fichiers "$AV_N"
pub ba_avant_sha "$(cat "$AV_DECL" "$AV_CHRO" "$AV_EXPL" 2>/dev/null | sha256sum | cut -c1-16)"

av(){ sed -n "s/^$1=//p" "$AV_DECL" 2>/dev/null | tail -1; }
AV_GIT=$(num "$(av rerun_cmake_entrees_git)")
AV_SO=$(av so_sha_avant)
AV_TRAVAIL=$(num "$(av apres_commit_travail)")
AV_CHAINES=$(num "$(av so_chaines_sdl3)")
pub ba_avant_git_entrees "$AV_GIT"
pub ba_avant_so_sha      "${AV_SO:--}"
pub ba_avant_travail     "$AV_TRAVAIL"
pub ba_avant_chaines_sdl "$AV_CHAINES"
# LA PREUVE QUE C'ETAIT BIEN `.git` QUI DECLENCHAIT : ninja le NOMME dans sa trace `-d explain`.
pub ba_avant_explain_git "$(grep -c 'older than most recent input.*\.git/refs/heads/' "$AV_EXPL" 2>/dev/null || true)"

# LE CHRONOMETRE D'AVANT. Quatre paires ALTERNEES — une invocation sans commit, une apres un
# commit fabrique — pour que la derive de la machine ne se lise pas comme un effet. On prend le
# MINIMUM du cote « apres commit » : c'est le chiffre le moins flatteur pour l'item.
CH=$(awk -F'[= ]' '
  /^sans_commit_/  {n1++; if (m1=="" || $2<m1) m1=$2; if ($2>x1) x1=$2}
  /^apres_commit_/ {n2++; if (m2=="" || $2<m2) m2=$2; if ($2>x2) x2=$2; r+=$4}
  END {printf "n1=%d p_min=%s p_max=%s n2=%d c_min=%s c_max=%s reruns=%d\n",
       n1, (m1==""?-1:m1), (x1==""?-1:x1), n2, (m2==""?-1:m2), (x2==""?-1:x2), r}
' "$AV_CHRO" 2>/dev/null)
c(){ printf '%s\n' "$CH" | tr ' ' '\n' | sed -n "s/^$1=//p" | tail -1; }
AV_PAIRES=$(num "$(c n2)")
AV_PLANCHER=$(num "$(c p_max)")
AV_COMMIT_MS=$(num "$(c c_min)")
pub ba_avant_paires        "$AV_PAIRES"
pub ba_avant_plancher_ms   "$(num "$(c p_min)")"
pub ba_avant_plancher_max  "$AV_PLANCHER"
pub ba_avant_commit_ms_min "$AV_COMMIT_MS"
pub ba_avant_commit_ms_max "$(num "$(c c_max)")"
# Le MECANISME, pas seulement la duree : les 4 invocations d'avant RELANCAIENT cmake.
pub ba_avant_reruns "$(num "$(c reruns)")"

# ============================== 1. L'ARBRE VIVANT : TASSEMENT, PUIS TROIS INVOCATIONS =======
# LE TASSEMENT est publie, PAS juge a zero : il absorbe ce qu'un AUTRE item aurait laisse en
# attente dans l'arbre arm64. Le confondre avec les trois invocations jugees ferait rougir cet
# item pour le travail d'un voisin (« defaut vu sous un acquis casse »). Ce qu'il a coute se lit.
inv(){ # -> "<ms> <rc> <aretes> <travail> <reruns>"
  local t0 t1 rc log; log=$(mktemp /tmp/ba-inv-XXXXXX.log)
  t0=$(date +%s%N); timeout "${2:-120}" ninja -C "$D" gk > "$log" 2>&1; rc=$?; t1=$(date +%s%N)
  printf '%s %s %s %s %s\n' "$(( (t1 - t0) / 1000000 ))" "$rc" \
    "$(grep -cE '^\[[0-9]+/[0-9]+\]' "$log" || true)" \
    "$(grep -E '^\[[0-9]+/[0-9]+\]' "$log" | grep -cE '(Building|Linking|Archiving|Creating library)' || true)" \
    "$(grep -c 'Re-running CMake' "$log" || true)"
  rm -f "$log"
}
f(){ printf '%s\n' "$1" | awk -v i="$2" '{print $i}'; }

T0=$(inv tassement 400)
pub ba_tassement_ms      "$(num "$(f "$T0" 1)")"
pub ba_tassement_rc      "$(num "$(f "$T0" 2)")"
pub ba_tassement_aretes  "$(num "$(f "$T0" 3)")"
pub ba_tassement_travail "$(num "$(f "$T0" 4)")"

SO_AVANT_INV=$(sha256sum "$SO" 2>/dev/null | cut -c1-32)

I1=$(inv 1 120)

# LE COMMIT FABRIQUE, PAR PLOMBERIE. `git commit-tree` + `git update-ref` fabriquent un commit
# vide sur l'arbre de HEAD : il ne prend NI l'index NI l'arbre de travail. Un `git commit
# --allow-empty` aurait emporte tout ce qu'un autre acteur avait indexe — c'est exactement la
# perte que « commiter en NOMMANT ses chemins » decrit, et ici il n'y a AUCUN chemin a nommer.
# `update-ref` porte l'ancienne valeur en garde : si quelqu'un a bouge la branche entre-temps,
# il refuse au lieu d'ecraser.
BR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
OLD=$(git rev-parse HEAD 2>/dev/null)
DESC_AVANT=$(git describe --tags 2>/dev/null)
NEW=$(git commit-tree "$OLD^{tree}" -p "$OLD" \
      -m "[autoport/build-android-reinvalidates-itself] commit fabrique par le recensement : le declencheur arm64 doit rester coupe" 2>/dev/null)
FABRIQUE=0
if [ -n "$NEW" ] && git update-ref "refs/heads/$BR" "$NEW" "$OLD" 2>/dev/null; then FABRIQUE=1; fi
DESC_APRES=$(git describe --tags 2>/dev/null)
pub ba_commit_fabrique "$FABRIQUE"
pub ba_commit_sha      "$(printf '%s' "${NEW:--}" | cut -c1-12)"
pub ba_describe_avant  "${DESC_AVANT:--}"
pub ba_describe_apres  "${DESC_APRES:--}"

I2=$(inv 2 120)
I3=$(inv 3 120)

for n in 1 2 3; do
  eval "R=\$I$n"
  pub "ba_live_ms$n"      "$(num "$(f "$R" 1)")"
  pub "ba_live_rc$n"      "$(num "$(f "$R" 2)")"
  pub "ba_live_aretes$n"  "$(num "$(f "$R" 3)")"
  pub "ba_live_travail$n" "$(num "$(f "$R" 4)")"
  pub "ba_live_rerun$n"   "$(num "$(f "$R" 5)")"
done
GIT_APRES=$(gitin "$D/build.ninja")
pub ba_git_entrees_apres "$(num "$GIT_APRES")"

D1=0
[ "$AV_N" = 3 ] || D1=$((D1+1))
# L'AVANT DOIT ETRE NON NUL. Une capture absente rend 0 entree `.git` — c'est-a-dire le chiffre
# meme qu'on attend de l'APRES : sans ce plancher, perdre le temoin se lirait comme la reussite.
[ "$(sup "$AV_GIT" 0)" = 1 ] || D1=$((D1+1))
# Et ninja doit y NOMMER `.git/refs/heads/` comme l'entree qui a perime le manifeste : c'est la
# trace qui dit que le declencheur etait bien celui-la, et pas une coincidence de dates.
[ "$(sup "$(num "$(grep -c 'older than most recent input.*\.git/refs/heads/' "$AV_EXPL" 2>/dev/null || echo 0)")" 0)" = 1 ] || D1=$((D1+1))
[ "$GIT_APRES" = 0 ] || D1=$((D1+1))
[ "$FABRIQUE" = 1 ] || D1=$((D1+1))
[ -n "$DESC_AVANT" ] && [ "$DESC_AVANT" != "$DESC_APRES" ] || D1=$((D1+1))
for n in 1 2 3; do
  eval "R=\$I$n"
  [ "$(num "$(f "$R" 2)")" = 0 ] || D1=$((D1+1))      # rc
  [ "$(num "$(f "$R" 4)")" = 0 ] || D1=$((D1+1))      # ZERO cible recompilee
  [ "$(num "$(f "$R" 5)")" = 0 ] || D1=$((D1+1))      # et cmake ne s'est PAS rejoue
done

# ==================================================== 2. LA CONSTANTE EST DERIVEE ===========
# LE RECENSEMENT RE-DERIVE LA CONSTANTE LUI-MEME, depuis le MEME en-tete que cmake lit, avec sa
# propre lecture. Comparer l'en-tete genere a une chaine que ce script porterait en dur serait un
# miroir : on compare a une valeur RECONSTRUITE depuis la source de verite.
vpart(){ sed -n "s/^#define[ \t]*SDL_$1_VERSION[ \t]*\([0-9][0-9]*\).*$/\1/p" "$VERH" 2>/dev/null | head -1; }
VMAJ=$(vpart MAJOR); VMIN=$(vpart MINOR); VMIC=$(vpart MICRO)
pub ba_sdl_version_header "$VERH"
pub ba_sdl_majeur "$(num "$VMAJ")"; pub ba_sdl_mineur "$(num "$VMIN")"; pub ba_sdl_micro "$(num "$VMIC")"
ATTENDU=""
[ -n "$VMAJ" ] && [ -n "$VMIN" ] && [ -n "$VMIC" ] && ATTENDU="SDL-$VMAJ.$VMIN.$VMIC-jak-project-android"
ENTETE=$(rev "$HDR")
CACHE=$(sed -n 's/^SDL_REVISION:STRING=//p' "$D/CMakeCache.txt" 2>/dev/null | head -1)
DESC=$(git describe --tags 2>/dev/null | tr -d ' ')
# AUCUN NUMERO DE VERSION EN DUR DANS LA SOURCE DE LA POSE : le bureau a laisse ce defaut
# derriere lui (`SDL-3.4.4-jak-project-desktop` ecrit en toutes lettres dans `build_x86.sh`).
DUR=$(grep -cE 'SDL-[0-9]+\.[0-9]+' android/CMakeLists.txt 2>/dev/null || true)
pub ba_const_attendue "${ATTENDU:--}"
pub ba_const_entete   "${ENTETE:--}"
pub ba_const_cache    "${CACHE:--}"
pub ba_const_en_dur   "$(num "$DUR")"
pub ba_describe       "${DESC:--}"

D2=0
[ -n "$ATTENDU" ] || D2=$((D2+1))
[ -n "$ENTETE" ] && [ "$ENTETE" = "$ATTENDU" ] || D2=$((D2+1))
[ -n "$CACHE" ] && [ "$CACHE" = "$ATTENDU" ] || D2=$((D2+1))
[ "$(num "$DUR")" = 0 ] || D2=$((D2+1))
# ET ELLE A DECOUPLE : la chaine ne porte plus le `describe`. Un `describe` vide rendrait la
# comparaison vraie pour rien — on exige donc de l'avoir LU.
[ -n "$DESC" ] || D2=$((D2+1))
case "$ENTETE" in *"$DESC"*) D2=$((D2+1)) ;; esac

# ============================ 3. ELLE SURVIT A UNE RECONFIGURATION A NEUF ====================
# LE BUREAU N'A LA SIENNE QUE DANS LE CACHE DE SON ARBRE : un dossier `build/` supprime repart
# sans elle (signalement du 12/09, ecarte la-bas). Le livrable l'exige ici, donc la pose vit dans
# `android/CMakeLists.txt` et se rejoue a CHAQUE configuration. On le montre sur un arbre NEUF,
# configure hors du depot — dans le depot, ses fichiers entreraient dans les globs de l'arbre
# vivant. On ne le CONSTRUIT pas : le declencheur se lit dans le manifeste genere.
RECONF_RC=-1; RECONF_S=-1; RECONF_GIT=-1; RECONF_OCTETS=0; RECONF_CONST="-"; NETTOYE=0
NDK="${ANDROID_NDK_HOME:-}/build/cmake/android.toolchain.cmake"
if [ -f "$NDK" ]; then
  TMP=$(mktemp -d /tmp/ba-reconf-XXXXXX)
  t0=$(date +%s%N)
  timeout 200 cmake -S "$ROOT" -B "$TMP" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$NDK" \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29 \
    -DGOALC_BACKEND=arm64 -DCMAKE_BUILD_TYPE=RelWithDebInfo >/tmp/ba-reconf.log 2>&1
  RECONF_RC=$?
  RECONF_S=$(( ($(date +%s%N) - t0) / 1000000000 ))
  RECONF_GIT=$(gitin "$TMP/build.ninja")
  RECONF_OCTETS=$(stat -c %s "$TMP/build.ninja" 2>/dev/null || echo 0)
  RECONF_CONST=$(rev "$TMP/android/sdl_build/include-revision/SDL3/SDL_revision.h")
  # Le chemin est celui que `mktemp` vient de rendre, et il doit commencer par notre prefixe :
  # une variable vide ou detournee ne peut pas devenir une racine.
  case "$TMP" in /tmp/ba-reconf-??????) rm -rf -- "$TMP" ;; esac
  [ -d "$TMP" ] || NETTOYE=1
fi
pub ba_reconf_rc      "$(num "$RECONF_RC")"
pub ba_reconf_s       "$(num "$RECONF_S")"
pub ba_reconf_git     "$(num "$RECONF_GIT")"
pub ba_reconf_octets  "$(num "$RECONF_OCTETS")"
pub ba_reconf_const   "${RECONF_CONST:--}"
pub ba_reconf_nettoye "$NETTOYE"

D3=0
[ "$RECONF_RC" = 0 ] || D3=$((D3+1))
[ "$RECONF_GIT" = 0 ] || D3=$((D3+1))
[ -n "$ATTENDU" ] && [ "$RECONF_CONST" = "$ATTENDU" ] || D3=$((D3+1))
# LE PLANCHER DE VACUITE : une configuration qui echoue rend 0 entree `.git` — c'est-a-dire le
# chiffre meme qu'on attend du succes. On exige donc un manifeste REEL. L'arbre vivant en pese
# 1,05 Mo ; le plancher est mis a la moitie, pas a une valeur ronde inventee.
[ "$(sup "$RECONF_OCTETS" $(( $(stat -c %s "$D/build.ninja" 2>/dev/null || echo 0) / 2 )) )" = 1 ] || D3=$((D3+1))
[ "$NETTOYE" = 1 ] || D3=$((D3+1))

# ================================================ 4. LE BINAIRE LIVRE EST IDENTIQUE =========
SO_SHA=$(sha256sum "$SO" 2>/dev/null | cut -c1-32)
pub ba_so_sha        "${SO_SHA:--}"
pub ba_so_sha_avant  "${AV_SO:--}"
pub ba_so_octets     "$(num "$(stat -c %s "$SO" 2>/dev/null || echo "")")"
# POURQUOI il ne bouge pas, mesure et non suppose : la chaine de revision n'est dans AUCUNE
# section du `.so`, et aucun objet de l'arbre ne depend de l'en-tete qui la porte.
pub ba_so_chaines_sdl "$(num "$(strings -a "$SO" 2>/dev/null | grep -c 'SDL-3' || true)")"
pub ba_deps_sur_entete "$(num "$(ninja -C "$D" -t deps 2>/dev/null | grep -c 'include-revision/SDL3/SDL_revision.h' || true)")"

D4=0
[ -n "$SO_SHA" ] || D4=$((D4+1))
[ -n "$AV_SO" ] || D4=$((D4+1))
[ "$SO_SHA" = "$AV_SO" ] || D4=$((D4+1))
# Et il n'a pas bouge NON PLUS pendant les trois invocations de ce recensement.
[ -n "$SO_AVANT_INV" ] && [ "$SO_AVANT_INV" = "$SO_SHA" ] || D4=$((D4+1))

# =========================================================== 5. LE GAIN, CHIFFRE ============
# LE MOINS FLATTEUR DES DEUX COTES : le MINIMUM d'avant contre le MAXIMUM d'apres. Le bruit de
# l'instrument est publie a cote (l'etendue du plancher d'avant, 4 invocations sans commit) pour
# qu'un ecart de quelques millisecondes ne se lise pas comme un gain.
AP_MAX=-1
for n in 1 2 3; do eval "R=\$I$n"; m=$(num "$(f "$R" 1)")
  [ "$m" -gt "$AP_MAX" ] 2>/dev/null && AP_MAX=$m; done
pub ba_apres_ms_max "$AP_MAX"
D5=0
if [ "$AV_COMMIT_MS" -gt 0 ] 2>/dev/null && [ "$AP_MAX" -ge 0 ] 2>/dev/null \
   && [ "$AP_MAX" -lt "$AV_COMMIT_MS" ]; then
  G=$(( AV_COMMIT_MS - AP_MAX ))
  pub ba_gain_ms "$G"
  pub ba_gain_s  "$(awk -v g="$G" 'BEGIN{printf "%.3f", g/1000}')"
else
  D5=1; pub ba_gain_ms -1; pub ba_gain_s -1
fi
# CE SUR QUOI LE « AVANT » REPOSE, juge et non pas seulement publie : au moins deux paires
# retenues, et les invocations d'avant devaient TOUTES relancer cmake — sinon le chiffre d'avant
# ne mesure pas le declencheur qu'on a coupe.
[ "$(sup "$AV_PAIRES" 1)" = 1 ] || D5=$((D5+1))
[ "$(num "$(c reruns)")" = "$AV_PAIRES" ] || D5=$((D5+1))
[ "$(sup "$AV_PLANCHER" 0)" = 1 ] || D5=$((D5+1))

# ================================================= 6. LE BUREAU N'A PAS BOUGE ===============
# LE HORS-PERIMETRE, VERIFIE PLUTOT QU'AFFIRME (« Ne change pas le build de bureau »).
# `android/CMakeLists.txt` n'est lu que sous `if(ANDROID)`, mais le dire ne le prouve pas : on
# lit ce que l'arbre de BUREAU porte. On ne le CONSTRUIT pas — le relier pendant la course
# changerait le `sha=` que `validators/generic.sh` compare au binaire mesure.
BUR_GIT=$(gitin "build/build.ninja")
BUR_CONST=$(rev "build/third-party/SDL/include-revision/SDL3/SDL_revision.h")
pub ba_bureau_git_entrees "$(num "$BUR_GIT")"
pub ba_bureau_const       "${BUR_CONST:--}"
D6=0
[ "$BUR_GIT" = 0 ] || D6=$((D6+1))
[ -n "$BUR_CONST" ] || D6=$((D6+1))
# Il porte TOUJOURS la sienne, pas la notre : une pose qui aurait debord n'est pas une pose.
[ -n "$ATTENDU" ] && [ "$BUR_CONST" != "$ATTENDU" ] || D6=$((D6+1))

pub ba_defaut_1_zero      "$D1"
pub ba_defaut_2_derivee   "$D2"
pub ba_defaut_3_reconf    "$D3"
pub ba_defaut_4_binaire   "$D4"
pub ba_defaut_5_gain      "$D5"
pub ba_defaut_6_bureau    "$D6"
pub build_android_reinval_defects "$(( D1 + D2 + D3 + D4 + D5 + D6 ))"
