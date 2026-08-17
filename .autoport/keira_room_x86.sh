#!/usr/bin/env bash
# keira_room_x86.sh — lance LA SALLE DE TEST DE KEIRA sur x86 et recolte sa trace brute.
#
# Phase Grecharged-secondary-motion, branche physics-keira-clean.
# Contrat : .autoport/prompts/SPEC-keira-physique.md, section 6 (« une test room dans laquelle on
# ne spawn pas le player mais le personnage a tester »).
#
# Ce script ne juge RIEN : il lance, il attend le marqueur de fin (PHYSEND), il ramene le log.
# C'est .autoport/physics_room_table.py qui en fait le tableau, et lui seul qui a le droit de
# refuser d'ecrire une ligne que la trace ne soutient pas.
#
# Prealable : `./build/goalc/goalc --user-auto --game jak1 -c '(mi)'` a jour (le script le verifie
# par une comparaison de dates, pas par confiance).
set -uo pipefail
cd "$(dirname "$0")/.."

GK=build/game/gk
ISO=out/jak1/iso
OUT=.autoport/reports/Grecharged-secondary-motion
LOG="$OUT/keira-room-x86.log"
mkdir -p "$OUT"

# --- 0. LES DEUX VERROUS, POSES AU POINT DE PRODUCTION -----------------------------------------
# Cycle 13, incident (a) : un `gk` orphelin etait encore vivant quand la course a demarre. Les deux
# ouvrent "$LOG" en TRONCATURE et ecrivent chacun a SON offset : le fichier atteint une taille
# plausible (2.0 MB) et ressemble a une trace normale, mais il est ENTRELACE. Rien en aval ne peut
# le detecter — le tableau lit des lignes, pas des offsets.
# Cycle 13, incident (b) : l'auto-constructeur tournait depuis 3 h et peut effacer `out/jak1/obj/*`
# et reecrire `out/jak1/iso` EN PLEINE MESURE, ce qui rend les chiffres inattribuables.
# Les deux ont ete corriges A LA MAIN apres coup. « Quand une perte se repete, on la rend
# IMPOSSIBLE au point de production, pas detectable au point de controle » — donc ici, pas ailleurs.
# Convention DIRECTIVES 2026-08-14 07:10 : un verrou porte TOUJOURS son PID et son horodatage,
# JAMAIS un `touch` nu. Un verrou sans detenteur n'est pas un verrou, c'est une panne silencieuse.
RLOCK=.autoport/.keira-room-x86.lock
DLOCK=.autoport/.deploy-in-progress
_own_r=0; _own_d=0
_stale(){ # 0 = le verrou $1 est libre ou perime (detenteur mort)
  [ -f "$1" ] || return 0
  local p; p=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$1" | head -1)
  [ -n "$p" ] || return 0                       # verrou sans PID = perime par construction
  kill -0 "$p" 2>/dev/null && return 1 || return 0
}
if _stale "$RLOCK"; then
  printf 'keira_room_x86 pid=%s started=%s\n' "$$" "$(date -Is)" > "$RLOCK"; _own_r=1
else
  echo "FAIL: une course est deja en cours ($(cat "$RLOCK")). Deux gk ecriraient le MEME log,"
  echo "      chacun a son offset, et la trace serait entrelacee sans que rien le voie."; exit 1
fi
if _stale "$DLOCK"; then
  printf 'keira_room_x86 pid=%s started=%s\n' "$$" "$(date -Is)" > "$DLOCK"; _own_d=1
else
  echo "note: .deploy-in-progress deja detenu ($(cat "$DLOCK")) — laisse tel quel, pas repris."
fi
# On ne retire QUE les verrous qu'on a poses soi-meme, et le nettoyage NE TOUCHE PAS au code de
# sortie : `exit` nu dans un trap EXIT rend le statut de la DERNIERE commande du trap et masquerait
# les FAIL ci-dessus. INT/TERM passent par `exit`, donc par le meme trap EXIT.
_cleanup(){
  [ "${GKPID:-}" ] && kill "$GKPID" 2>/dev/null   # PID exact, jamais de motif (DIRECTIVES 8)
  [ "$_own_r" = 1 ] && rm -f "$RLOCK"
  [ "$_own_d" = 1 ] && rm -f "$DLOCK"
  return 0
}
trap _cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"

# --- 1. fraicheur : un run sur des CGO perimes mesure le code d'hier ---------------------------
for src in goal_src/jak1/pc/phys-room.gc goal_src/jak1/pc/jak-hd-physics.gc; do
  if [ ! "$ISO/GAME.CGO" -nt "$src" ]; then
    echo "FAIL: $ISO/GAME.CGO est plus vieux que $src — relance (mi) d'abord"; exit 1
  fi
done

# --- 2. mise en place de l'art-group HD externe ------------------------------------------------
# loado ouvre out/jak1/obj/<name>-ag.go (Loader.cpp:588), et (mi) repeuple obj/ SANS les assets
# externes : il faut re-stager a chaque build, sinon le compagnon ne spawne jamais.
cp -f recharged_assets/hd_anim/keira-hd-ag.go out/jak1/obj/ || { echo "FAIL: keira-hd-ag.go absent"; exit 1; }
[ -f out/jak1/obj/assistant-ag.go ] || { echo "FAIL: out/jak1/obj/assistant-ag.go absent"; exit 1; }
echo "staged: $(ls -la out/jak1/obj/keira-hd-ag.go out/jak1/obj/assistant-ag.go | tr -s ' ' | cut -d' ' -f5,9 | tr '\n' ' ')"

# --- 3. la course ------------------------------------------------------------------------------
# LE LOG DE LA COURSE PRECEDENTE EST ARCHIVE AVANT D'ETRE ECRASE.
# Paye au cycle 14 : `: > "$LOG"` a efface la trace de la course du cycle 13 (2 118 462 octets,
# celle qui portait la reference k=0) une seconde avant que j'en aie besoin pour comparer. Les
# cycles precedents s'en sortaient en copiant le log A LA MAIN sous un nom `PRE-*` — c'est-a-dire
# en se souvenant de le faire. Un archivage qu'il faut penser a declencher n'est pas un archivage.
# Le TABLEAU derive survivait, lui, mais un tableau ne permet pas de reposer une question neuve a
# la trace : c'est precisement ce qui a manque.
if [ -s "$LOG" ]; then
  ARCH="$OUT/keira-room-x86.$(date -r "$LOG" +%Y%m%d-%H%M%S).log"
  mv -f "$LOG" "$ARCH" && echo "archive: course precedente -> $ARCH"
  # on garde les 6 dernieres : au-dela ce sont des gigaoctets de traces dont plus rien ne parle.
  ls -1t "$OUT"/keira-room-x86.2*.log 2>/dev/null | tail -n +7 | while read -r old; do
    rm -f "$old"; echo "purge: $old"
  done
fi
: > "$LOG"
OG_PHYS_ROOM=1 OG_PHYS_ROOM_DELAY="${OG_PHYS_ROOM_DELAY:-600}" \
  stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
  -iso-data "$ISO" -- -boot -debug-mem > "$LOG" 2>&1 &
GKPID=$!
echo "gk pid=$GKPID  log=$LOG"

DEADLINE="${ROOM_TIMEOUT:-420}"
ok=0
for i in $(seq 1 "$DEADLINE"); do
  if ! kill -0 "$GKPID" 2>/dev/null; then
    echo "gk s'est arrete tout seul apres ${i}s"; break
  fi
  if grep -aq '^PHYSEND' "$LOG" 2>/dev/null; then ok=1; echo "PHYSEND vu apres ${i}s"; break; fi
  sleep 1
done

# PID exact, jamais de kill par motif (DIRECTIVES 8)
kill "$GKPID" 2>/dev/null
for i in $(seq 1 10); do kill -0 "$GKPID" 2>/dev/null || break; sleep 1; done
kill -9 "$GKPID" 2>/dev/null

echo "---- marqueurs ----"
for m in PHYSROOM-START PHYSFAIL PHYSSUBJECT PHYSANIM PHYSCHAIN PHYSROW PHYSIDLE PHYSAUTH PHYSNOPLAY PHYSCOUNTS PHYSPC PHYSEND 'PHYS-ROOM' 'HD-PHYS' 'HD-COMP' 'hd-phys'; do
  printf '%-16s %s\n' "$m" "$(grep -ac "$m" "$LOG" 2>/dev/null || echo 0)"
done
echo "---- premieres lignes utiles ----"
grep -aE '^PHYS|PHYS-ROOM|\[HD-PHYS\]|\[HD-COMP\]|hd-phys' "$LOG" | head -40
[ "$ok" = 1 ] || { echo "FAIL: PHYSEND jamais atteint"; exit 1; }
echo "OK"
