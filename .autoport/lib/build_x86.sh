#!/usr/bin/env bash
# lib/build_x86.sh — LA PORTE UNIQUE DE LA CONSTRUCTION DE BUREAU.
#
# POURQUOI (build-tree-reinvalidates-itself, 2026-09-12). Mesure sur l'arbre `build/` de ce
# depot, instrument `ninja -n -d explain` sur une COPIE du manifeste (la copie evite la
# regeneration cmake, qui masquerait la mesure) :
#
#     335 aretes a relancer SANS AUCUNE EDITION DE SOURCE
#       320  « stored deps info out of date for 'X' (<enregistre> vs <mtime de l'objet>) »
#        11  « deps for 'X' are missing »
#         4  bibliotheques salies par les objets ci-dessus
#
# LA CAUSE, NOMMEE ET REPRODUITE (lib/build_freshness_selftest.sh) : `build/.ninja_deps` etait
# CORROMPU EN SON MILIEU. A chaque chargement ninja s'arretait sur l'enregistrement casse —
# « ninja: warning: premature end of file; recovering » — et JETAIT tout ce qui suivait. Or
# chaque construction AJOUTE ses enregistrements a la fin : ils tombaient donc tous du mauvais
# cote de la coupure. Experience du 12/09, sur le vrai arbre : `SystemThread.cpp.o` recompile a
# 15:45, le journal grossit de 1 764 octets, et `ninja -t deps` rend toujours l'enregistrement
# du 30 aout. L'objet est donc plus RECENT que son enregistrement de dependances, ninja le
# declare sale, le recompile, note un enregistrement neuf... que le chargement suivant jette
# encore. Boucle fermee : 338 cibles recompilees a CHAQUE invocation, pour toujours.
#
# CE QUE CETTE PORTE FAIT, ET QUE `cmake --build` NE FERA JAMAIS :
#   1. AVANT — elle CHARGE le journal de dependances et refuse de construire sur un journal
#      casse : recompactage (`ninja -t recompact`), et mise en quarantaine si ca ne suffit pas.
#      La perte est rendue impossible au POINT DE PRODUCTION, pas detectable au controle.
#   2. APRES — elle compare l'horodatage du binaire a celui de CHACUNE de ses entrees directes,
#      A LA NANOSECONDE. Un binaire plus vieux qu'une de ses dependances SORT EN 4. Jamais zero.
#      La seconde entiere ne suffisait pas : un lien saute dont l'entree est reecrite 0,4 s plus
#      tard portait le MEME `stat -c %Y`, et la porte le declarait frais (mesure : jambe F
#      infra-seconde du banc, ou la porte du commit 14ba12bd23 rend 0 sur l'etat que celle-ci
#      refuse en 4).
#   3. APRES — elle rejoue le graphe a vide : une construction reussie ne laisse AUCUNE arete de
#      compilation ou de lien a faire. S'il en reste, elle SORT EN 5 et les NOMME.
# Les trois verdicts sont publies en `cle=valeur` sur la sortie standard, et recopies dans
# `<dir>/.build_x86.report` pour qui veut les relire.
#
# `ninja` DIRECTEMENT, PAS `cmake --build` : `cmake --build <dir> --target T -j N` n'est qu'un
# lanceur de `ninja -C <dir> T -j N` (la regeneration du manifeste est une regle DU manifeste,
# elle se joue pareil). Appeler ninja est ce qui permet au banc de faire jouer CETTE porte-ci
# sur un arbre jetable, au lieu d'en recopier la logique — un deuxieme code diverge en silence.
# Aucune reconfiguration : `cmake -B` jette le cache d'objets, cette porte ne l'appelle jamais.
#
# Usage : lib/build_x86.sh [--dir build] [--target gk] [-j N] [--check-only]
#   --check-only : ne construit pas, ne repare pas ; mesure et juge l'arbre tel qu'il est.
# Sorties : 0 tout va bien | 2 usage/arbre non configure | 3 la construction a echoue
#           4 binaire plus vieux qu'une de ses dependances | 5 aretes restantes apres coup
set -uo pipefail
export LC_ALL=C

# LE COMPARATEUR DE FRAICHEUR, RESOLU AVANT LE `cd`. Cette porte lisait deja a la nanoseconde
# depuis le 12/09 ; ce qu'elle ne faisait pas, c'est refuser l'EGALITE
# (harness-subsecond-freshness-is-blind). Elle partage desormais le seul comparateur du harnais
# au lieu d'en porter une copie : deux regles ecrites a deux endroits divergent en silence.
FR_LIB=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/freshness.sh
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "build_x86: hors depot git" >&2; exit 2; }
cd "$ROOT" || exit 2
# shellcheck source=freshness.sh
. "$FR_LIB" || { echo "build_x86: lib/freshness.sh introuvable ($FR_LIB) — cette porte ne compare plus aucun horodatage elle-meme et refuse de deviner." >&2; exit 2; }

DIR=build; TARGET=gk; J=$(nproc 2>/dev/null || echo 4); CHECK_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)        DIR=${2:-}; shift 2 ;;
    --target)     TARGET=${2:-}; shift 2 ;;
    -j|--jobs)    J=${2:-}; shift 2 ;;
    --check-only) CHECK_ONLY=1; shift ;;
    -h|--help)    sed -n '/^# Usage/,/^# *4 /p' "$0"; exit 0 ;;
    *) echo "build_x86: argument inconnu : $1" >&2; exit 2 ;;
  esac
done

# LE BUILD ANDROID N'EST PAS DE SON RESSORT (perimetre de l'item : bureau seulement). Le dire
# ici vaut mieux que de laisser quelqu'un croire que la porte a juge un arbre qu'elle ignore.
case "$DIR" in
  */build-android*|*/build-arm64*|build-android*|build-arm64*) echo "build_x86: $DIR n'est pas un arbre de bureau ; cette porte ne le juge pas." >&2; exit 2 ;;
esac
[ -f "$DIR/build.ninja" ] || { echo "build_x86: $DIR/build.ninja absent — arbre non configure, et cette porte ne reconfigure JAMAIS." >&2; exit 2; }

RPT="$DIR/.build_x86.report"
: > "$RPT"
say(){ printf '%s\n' "build_x86: $*" >&2; }
# Le moissonneur de proof_run.sh ne garde que `^cle=valeur$` SANS ESPACE : on colle les espaces
# ici, au point de publication, sinon la valeur est publiee pour personne.
pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')" | tee -a "$RPT"; }

nj(){ ninja -C "$DIR" "$@"; }

# ------------------------------------------------------- 1. LE JOURNAL DE DEPENDANCES -------
# Le seul juge honnete de l'integrite du journal est le CHARGEUR de ninja lui-meme : reecrire un
# lecteur du format serait un deuxieme nommeur, et il divergerait le jour ou le format bouge.
deps_broken(){
  local e
  e=$(nj -t deps 2>&1 >/dev/null)
  case "$e" in
    *"premature end of file"*|*"bad deps log"*|*"premature end"*) return 0 ;;
    *) return 1 ;;
  esac
}

CORRUPT_BEFORE=0; REPAIRED=0; QUARANTINED=0
if deps_broken; then
  CORRUPT_BEFORE=1
  if [ "$CHECK_ONLY" = 1 ]; then
    say "journal de dependances CASSE ($DIR/.ninja_deps) — --check-only ne repare pas."
  else
    say "journal de dependances CASSE ($DIR/.ninja_deps) : recompactage."
    nj -t recompact >/dev/null 2>&1
    if deps_broken; then
      Q="$DIR/.ninja_deps.corrompu.$(date +%Y%m%d-%H%M%S)"
      mv -f "$DIR/.ninja_deps" "$Q" 2>/dev/null && QUARANTINED=1
      say "recompactage insuffisant : journal mis en quarantaine dans $Q."
      say "la prochaine construction sera COMPLETE, une seule fois."
    else
      REPAIRED=1
      say "journal recompacte, il se relit maintenant en entier."
    fi
  fi
fi
pub bx_deps_corrupt_before "$CORRUPT_BEFORE"
pub bx_deps_recompacted    "$REPAIRED"
pub bx_deps_quarantined    "$QUARANTINED"

# ------------------------------------------ 1 bis. CE QUE LE MANIFESTE PREND DANS `.git` ----
# POURQUOI (mesure du 12/09, DEUX courses de cet item, capture brute sous
# `lib/census/capture-build-tree-reinvalidates-itself/avant-reconfiguration-sur-commit.txt`).
# `third-party/SDL/CMakeLists.txt:3705` derive `SDL_REVISION` du `git describe` de NOTRE depot.
# `cmake/GetGitRevisionDescription.cmake` pose alors `.git/HEAD` et `.git/refs/heads/<branche>`
# en ENTREES de la regle `RERUN_CMAKE` : TOUT commit — y compris un commit du superviseur que
# l'essai en cours n'a pas fait — regenere `SDL3/SDL_revision.h`, puis `SDL.c.o`, `libSDL3.so`,
# `libcommon.so`, et RELIE `game/gk`. 7 aretes et des bibliotheques dont l'empreinte bouge sans
# qu'une ligne du moteur ait change : c'est la confusion que cette porte existe pour empecher,
# entree par l'autre bout. Les courses des essais 3 et 4 sont mortes exactement la-dessus.
#
# ON NE RECONFIGURE PAS POUR AUTANT. `SDL_REVISION` est une entree de CACHE (branche `else()`
# de SDL, `CMakeCache.txt:1193`, vide). On lui donne une constante DANS LE CACHE DE CET ARBRE
# DE BUREAU, et la regeneration que ninja joue DEJA d'elle-meme la lit : aucun `cmake -B` — que
# `hooks/pre-tool.sh` refuse et qui jetterait le cache d'objets —, et aucun fichier du SOURCE
# touche, donc le build Android, qui partage `third-party/SDL`, reste hors de portee.
# LA POSE EST IDEMPOTENTE, et elle doit l'etre : `CMakeCache.txt` est lui-meme une ENTREE de
# `RERUN_CMAKE`: le reecrire a chaque invocation rendrait la porte sale a chaque invocation,
# c'est-a-dire le defaut qu'elle mesure, fabrique par elle.
SDL_PIN='SDL-3.4.4-jak-project-desktop'
CACHE="$DIR/CMakeCache.txt"
SDL_PINNED=0
if [ "$CHECK_ONLY" = 0 ] && [ -f "$CACHE" ]; then
  cur=$(sed -n 's/^SDL_REVISION:STRING=//p' "$CACHE" | head -1)
  if [ "$cur" != "$SDL_PIN" ]; then
    if grep -q '^SDL_REVISION:STRING=' "$CACHE"; then
      sed -i "s|^SDL_REVISION:STRING=.*|SDL_REVISION:STRING=$SDL_PIN|" "$CACHE"
    else
      printf 'SDL_REVISION:STRING=%s\n' "$SDL_PIN" >> "$CACHE"
    fi
    SDL_PINNED=1
    say "SDL_REVISION fige a '$SDL_PIN' dans $CACHE : un commit ne regenerera plus SDL_revision.h."
  fi
fi
pub bx_sdl_pin    "$SDL_PIN"
pub bx_sdl_pinned "$SDL_PINNED"

# ------------------------------------------------------------------ 2. LA CONSTRUCTION ------
LOG="$DIR/.build_x86.log"
EDGES=0; WEDGES=0; OEDGES=0; OLIST=aucune; SECS=0; RC=0
if [ "$CHECK_ONLY" = 0 ]; then
  T0=$(date +%s)
  nj -j "$J" "$TARGET" > "$LOG" 2>&1; RC=$?
  SECS=$(( $(date +%s) - T0 ))
  EDGES=$(grep -cE '^\[[0-9]+/[0-9]+\]' "$LOG" 2>/dev/null || true)
  # CE QUI A ETE RECOMPILE, ET CE QUI S'EST SEULEMENT REJOUE. Une construction a vide fait
  # toujours tourner deux aretes de menage — « Re-checking globbed directories » de cmake et le
  # `clang-format` de discord-rpc, dont la sortie n'existe jamais — pour 0,45 s au total. Les
  # confondre avec une recompilation rendrait « zero cible » intenable pour une raison qui ne
  # compile rien ; les taire fabriquerait un zero. On publie les deux, separes et nommes.
  WEDGES=$(grep -E '^\[[0-9]+/[0-9]+\]' "$LOG" 2>/dev/null | grep -cE '(Building|Linking|Archiving|Creating library)' || true)
  OEDGES=$(( ${EDGES:-0} - ${WEDGES:-0} ))
  OLIST=$(grep -E '^\[[0-9]+/[0-9]+\]' "$LOG" 2>/dev/null | grep -vE '(Building|Linking|Archiving|Creating library)' \
          | sed -E 's/^\[[0-9]+\/[0-9]+\] //' | cut -c1-40 | head -3 | paste -sd, -)
  [ "$RC" = 0 ] || { sed -n '$p;/error:/p' "$LOG" | tail -20 >&2; }
fi
pub bx_rc          "$RC"
pub bx_edges       "${EDGES:-0}"
pub bx_work_edges  "${WEDGES:-0}"
pub bx_other_edges "${OEDGES:-0}"
pub bx_other_list  "${OLIST:-aucune}"
pub bx_seconds     "$SECS"
[ "$RC" = 0 ] || { say "la construction a echoue (code $RC). Journal : $LOG"; exit 3; }

# --------------------------------------------------- 3. CE QUE LE GRAPHE DIT APRES COUP -----
# Sur une COPIE du manifeste : avec `build.ninja`, ninja verifie d'abord s'il doit le
# regenerer, et cette etape (`restat`) masque la mesure qu'on vient chercher.
MAN=".build_x86.explain.ninja"
cp -f "$DIR/build.ninja" "$DIR/$MAN" 2>/dev/null || { say "copie du manifeste impossible"; exit 2; }
DRY="$DIR/.build_x86.dry"
ninja -C "$DIR" -f "$MAN" -n "$TARGET" > "$DRY" 2>/dev/null
RESID=$(grep -cE '^\[[0-9]+/[0-9]+\]' "$DRY" 2>/dev/null || true)
# Une arete de TRAVAIL produit un objet, une bibliotheque ou un binaire. Les autres — une cible
# personnalisee dont la sortie n'existe jamais, un `clang-format` de courtoisie — se rejouent par
# CONSTRUCTION et ne recompilent rien : on les publie NOMMEES plutot que de les confondre.
RESWORK=$(grep -E '^\[[0-9]+/[0-9]+\]' "$DRY" 2>/dev/null | grep -cE '(Building|Linking|Archiving|Creating library)' || true)
RESOTHER=$(( ${RESID:-0} - ${RESWORK:-0} ))
RESLIST=$(grep -E '^\[[0-9]+/[0-9]+\]' "$DRY" 2>/dev/null | grep -vE '(Building|Linking|Archiving|Creating library)' \
          | sed -E 's/^\[[0-9]+\/[0-9]+\] //' | cut -c1-40 | head -3 | paste -sd, -)
pub bx_residual_edges "${RESID:-0}"
pub bx_residual_work  "${RESWORK:-0}"
pub bx_residual_other "${RESOTHER:-0}"
pub bx_residual_other_list "${RESLIST:-aucune}"

# CE QUE `.git` PESE ENCORE SUR LE MANIFESTE, lu sur le manifeste REGENERE et non sur la copie :
# c'est la grandeur qui dit si un commit peut encore declencher une reconfiguration. Zero est le
# seul chiffre acceptable, et le temoin d'AVANT (non nul) vit dans la capture versionnee.
# `bx_sdl_revision` est ce que l'en-tete porte REELLEMENT : la constante posee, ou le `describe`
# si la pose n'a pas pris — la difference se lit, elle ne se suppose pas.
pub bx_cmake_git_inputs "$(grep -o "$ROOT/\.git/[A-Za-z0-9_./-]*" "$DIR/build.ninja" 2>/dev/null | sort -u | grep -c . || true)"
pub bx_sdl_revision "$(sed -n 's/.*define SDL_REVISION "\([^"]*\)".*/\1/p' \
  "$DIR/third-party/SDL/include-revision/SDL3/SDL_revision.h" 2>/dev/null | tail -1)"
pub bx_describe "$(git describe --tags 2>/dev/null | tr -d ' ')"

# ---------------------------------------------------------- 4. LE BINAIRE ET SES ENTREES ----
# `ninja -t query` donne les entrees DIRECTES d'une sortie : les `.a`, les `.so`, le `.o` du
# main. C'est exactement la comparaison qui a revele le defaut du 12/09 — `libruntime.a` a
# 14:43:15 pour un `gk` reste a 14:36:03 — et que personne ne faisait.
q_inputs(){ ninja -C "$DIR" -f "$MAN" -t query "$1" 2>/dev/null \
  | awk '/^ *input:/{f=1;next} /^ *outputs:/{f=0} f && NF {sub(/^ *\|\|? */,""); sub(/^ */,""); print $1}'; }

BINOUT="$TARGET"
if [ ! -f "$DIR/$TARGET" ]; then BINOUT=$(q_inputs "$TARGET" | head -1); fi
if [ -z "$BINOUT" ] || [ ! -f "$DIR/$BINOUT" ]; then
  pub bx_bin "absent"; pub bx_bin_fresh 0
  say "la cible $TARGET ne designe aucun fichier sur le disque : rien a juger, et c'est un defaut."
  exit 4
fi
# A LA NANOSECONDE, PAS A LA SECONDE. `stat -c %Y` arrondit a la seconde entiere : un lien saute
# dont l'entree est reecrite DANS LA MEME SECONDE passait la comparaison `-ge` — la porte rendait
# 0 sur un binaire qu'elle aurait du refuser. Ce n'est pas une hypothese : le banc le seme
# (`lib/build_freshness_selftest.sh`, jambe F infra-seconde, 0,4 s d'ecart) et la porte y sortait
# en 0 avec `bx_bin_fresh=1`. Les horodatages sont donc lus en nanosecondes entieres — le point
# decimal retire, `LC_ALL=C` garantit que c'en est un — et les secondes restent publiees telles
# quelles pour qui les lit.
mtime_ns(){ fr_mtime_ns "$1"; }
FR_SITE=build_x86/binaire-vs-entrees-ninja
BMN=$(mtime_ns "$DIR/$BINOUT")
NEWESTN=0; NEWEST_NAME=aucune; NDEPS=0
while IFS= read -r d; do
  [ -n "$d" ] || continue
  [ -f "$DIR/$d" ] || continue
  NDEPS=$((NDEPS+1))
  m=$(mtime_ns "$DIR/$d")
  if [ "$m" -gt "$NEWESTN" ]; then NEWESTN=$m; NEWEST_NAME=$d; fi
done <<EOF
$(q_inputs "$BINOUT")
EOF
BM=$(( BMN / 1000000000 )); NEWEST=$(( NEWESTN / 1000000000 ))
# L'EGALITE N'EST PLUS UNE FRAICHEUR. `-ge` la declarait fraiche ; a horodatage egal, rien ne
# dit lequel a ete ecrit en premier, et cette porte se trompe toujours du cote PERMISSIF quand
# elle devine. Ce n'est pas theorique : sur le btrfs de cette machine, deux fichiers ecrits a la
# suite recoivent le MEME horodatage a la nanoseconde (l'horloge de l'inode avance par tics
# d'environ 300 us). Mesure du 12/09 sur l'arbre livre : le binaire precede sa plus recente
# entree de 2,5 s, la marge reelle est donc de quatre ordres de grandeur au-dessus du tic.
VERDICT=$(fr_verdict "$BMN" "$NEWESTN")
FRESH=0; [ "$VERDICT" = frais ] && FRESH=1
pub bx_bin          "$BINOUT"
pub bx_bin_mtime    "$BM"
pub bx_bin_mtime_ns "$BMN"
pub bx_deps_seen    "$NDEPS"
pub bx_newest_dep   "$NEWEST"
pub bx_newest_dep_ns "$NEWESTN"
pub bx_newest_name  "$NEWEST_NAME"
pub bx_bin_fresh    "$FRESH"
pub bx_bin_verdict  "$VERDICT"
pub bx_bin_lag_s    "$(( NEWEST - BM ))"
pub bx_bin_lag_ns   "$(( NEWESTN - BMN ))"

if [ "$FRESH" = 0 ]; then
  if [ "$VERDICT" = douteux ]; then
    say "BINAIRE DOUTEUX : $DIR/$BINOUT et $NEWEST_NAME portent le MEME horodatage a la nanoseconde ($BMN)."
    say "rien ne dit lequel a ete ecrit en premier, donc rien ne prouve que le lien a ete fait APRES."
  else
    say "BINAIRE PERIME : $DIR/$BINOUT date de $(date -d "@$BM" '+%F %T'), et $NEWEST_NAME de $(date -d "@$NEWEST" '+%F %T')."
    say "le lien n'a PAS ete fait. Une preuve prise sur ce binaire decrirait un autre code que le tien."
  fi
  exit 4
fi
if [ "${RESWORK:-0}" != 0 ]; then
  say "$RESWORK arete(s) de compilation ou de lien restent A FAIRE apres une construction dite reussie :"
  grep -E '^\[[0-9]+/[0-9]+\]' "$DRY" | grep -E '(Building|Linking|Archiving|Creating library)' | head -5 >&2
  exit 5
fi
say "arbre propre : $EDGES arete(s) jouee(s) en ${SECS}s, $RESWORK a refaire, binaire $BINOUT plus recent que ses $NDEPS entrees."
exit 0
