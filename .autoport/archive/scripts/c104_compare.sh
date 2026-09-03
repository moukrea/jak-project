#!/usr/bin/env bash
# cycle 104 — extrait COTE A COTE les grandeurs que les predictions nomment.
# Gauche = table c104-BASE (etat livre du cycle 103) ; droite = table courante.
set -uo pipefail
cd "$(dirname "$0")/.."
D=.autoport/reports/Grecharged-secondary-motion
A=$D/keira-room-table.c104-BASE.txt
B=$D/keira-room-table.txt
for pat in \
  '^ROOM-SKINPEN: ' '^ROOM-SKINPEN-DETAIL:' '^ROOM-SKINPEN-REST:' '^ROOM-SKINPEN-REST-DETAIL:' \
  '^ROOM-SKINPEN-VERDICT:' '^ROOM-SKINPEN-COUT:' '^ROOM-SKINPEN-CAL' '^ROOM-STG:' '^ROOM-STG-PHASE:' \
  '^ROOM-APEX: ' '^ROOM-STRETCH:' '^ROOM-POSCONTROL' '^ROOM-IDLE:' '^ROOM-AUTHORED' '^ROOM-ANIMS:' ; do
  echo "================ $pat"
  echo "--- c103 (avant) :"; grep -E "$pat" "$A" 2>/dev/null | sed 's/^/    /'
  echo "--- c104 (apres) :"; grep -E "$pat" "$B" 2>/dev/null | sed 's/^/    /'
done
echo "================ PHYSE22 (trace brute)"
echo "--- c103 (avant) :"; grep -a '^PHYSE22 tag=run' $D/keira-room-x86.c104-BASE.log | tail -2 | sed 's/^/    /'
echo "--- c104 (apres) :"; grep -a '^PHYSE22 tag=run' $D/keira-room-x86.log | tail -2 | sed 's/^/    /'
