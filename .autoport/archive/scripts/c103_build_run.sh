#!/usr/bin/env bash
# cycle 103 : build GOAL + course x86, sous le verrou de deploiement pour que
# l'auto-constructeur ne reecrive pas out/jak1/obj en pleine mesure
# (piege `autobuilder-ships-your-wip`, remordu au cycle 102).
set -uo pipefail
cd "$(dirname "$0")/.."
LOCK=.autoport/.deploy-in-progress
printf 'c103_build_run pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
echo "==== (mi) $(date -Is) ===="
./build/goalc/goalc --user-auto --game jak1 -c '(mi)' 2>&1 | tail -25
if [ ! out/jak1/iso/GAME.CGO -nt goal_src/jak1/pc/phys-room.gc ]; then
  echo "FAIL: (mi) n'a pas rafraichi GAME.CGO"; exit 1
fi
echo "==== course $(date -Is) ===="
ROOM_TIMEOUT=1500 bash .autoport/keira_room_x86.sh 2>&1 | tail -60
echo "==== fini $(date -Is) ===="
