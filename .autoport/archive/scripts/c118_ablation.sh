#!/usr/bin/env bash
# cycle 118 — JAMBE DESARMEE de la borne de SPEC 21 (controle negatif P5).
# Elle DOIT rendre une course identique au bit a celle d'avant l'edition, hors les lignes
# PHYSE21 (neuves, a n=0) et la banniere de demarrage. L'interrupteur est remis a 0 et le
# moteur rebati A LA FIN, quoi qu'il arrive : une ablation laissee armee contaminerait la suite.
set -uo pipefail
cd "$(dirname "$0")/.."
D=.autoport/reports/Grecharged-secondary-motion
ENG=goal_src/jak1/pc/jak-hd-physics.gc
restore() {
  sed -i 's/^(define \*phys-e21-off\* 1)/(define *phys-e21-off* 0)/' "$ENG"
  grep -q '^(define \*phys-e21-off\* 0)' "$ENG" || { echo "FAIL: interrupteur PAS remis a 0"; exit 9; }
  ./build/goalc/goalc --user-auto --game jak1 -c '(mi)' 2>&1 | tail -2
}
trap restore EXIT
sed -i 's/^(define \*phys-e21-off\* 0)/(define *phys-e21-off* 1)/' "$ENG"
grep -q '^(define \*phys-e21-off\* 1)' "$ENG" || { echo "FAIL: interrupteur pas arme"; exit 9; }
echo "==== (mi) DESARME $(date -Is) ===="
./build/goalc/goalc --user-auto --game jak1 -c '(mi)' 2>&1 | tail -2
echo "==== course DESARMEE $(date -Is) ===="
ROOM_TIMEOUT=1800 bash .autoport/keira_room_x86.sh 2>&1 | tail -12
cp "$D/keira-room-x86.log"     "$D/keira-room-x86.c118-DESARMEE.log"
cp "$D/keira-room-table.txt"   "$D/keira-room-table.c118-DESARMEE.txt"
echo "==== fini $(date -Is) ===="
