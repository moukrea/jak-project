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
