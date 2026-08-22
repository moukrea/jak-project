#!/usr/bin/env bash
# cycle 106, 3e temps — AVANT/APRES le remplacement du plafond `-dot(dj,n)` par `|dj|`.
# Gauche = c106-CAP (instrument seul, solveur BIT-IDENTIQUE au cycle 105) ; droite = courant.
set -uo pipefail
cd "$(dirname "$0")/.."
D=.autoport/reports/Grecharged-secondary-motion
A=$D/keira-room-table.c106-CAP.txt
B=$D/keira-room-table.txt
for pat in '^ROOM-SKINADD: ' '^ROOM-SKINPEN: ' '^ROOM-SKINPEN-DETAIL:' '^ROOM-SKINPEN-VERDICT:' \
           '^ROOM-SKINPEN-COUT:' '^ROOM-SKINLEVER' '^ROOM-IDLE:' '^ROOM-STRETCH:' \
           '^ROOM-STG: ' '^ROOM-MEDIAL: ' '^ROOM-MEDIAL-PEN' '^ROOM-ANIMS:' '^ROOM-SHAPE-SPAN' ; do
  echo "================ $pat"
  echo "--- AVANT (c106-CAP) :"; grep -E "$pat" "$A" 2>/dev/null | sed 's/^/    /' | head -12
  echo "--- APRES (correctif) :"; grep -E "$pat" "$B" 2>/dev/null | sed 's/^/    /' | head -12
done
echo "================ tipvar / rootdev / meshpen par chaine"
echo "--- AVANT :"; grep -E '^\s+(chestL|chestR)\s+tipvar=' $D/c106b-run.console | sed 's/^/    /'
echo "--- APRES :"; grep -E '^\s+(chestL|chestR)\s+tipvar=' $D/c106c-run.console | sed 's/^/    /'
echo "================ PHYSSKLV5 tag=run (triplet co-localise)"
echo "--- AVANT :"; grep -a '^PHYSSKLV[56] tag=run' $D/keira-room-x86.c106-CAP.log | sed 's/^/    /'
echo "--- APRES :"; grep -a '^PHYSSKLV[56] tag=run' $D/keira-room-x86.log | sed 's/^/    /'
echo "================ PHYSSKINC / PHYSE22 tag=run"
echo "--- AVANT :"; grep -a '^PHYSSKINC tag=run\|^PHYSE22 tag=run' $D/keira-room-x86.c106-CAP.log | sed 's/^/    /'
echo "--- APRES :"; grep -a '^PHYSSKINC tag=run\|^PHYSE22 tag=run' $D/keira-room-x86.log | sed 's/^/    /'
