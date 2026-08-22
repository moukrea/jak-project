#!/usr/bin/env bash
# cycle 106 — CONTROLES D'IDENTITE. L'instrument de levier ne doit RIEN deplacer.
# Gauche = c106-BASE (etat livre du cycle 105) ; droite = course courante.
set -uo pipefail
cd "$(dirname "$0")/.."
D=.autoport/reports/Grecharged-secondary-motion
A=$D/keira-room-x86.c106-BASE.log
B=$D/keira-room-x86.log
for rec in PHYSSKIN PHYSSKIN2 PHYSSKINC PHYSE22; do
  echo "================ $rec  (P3/P4)"
  diff <(grep -a "^$rec " "$A") <(grep -a "^$rec " "$B") \
    && echo "    IDENTIQUE AU CHIFFRE ($(grep -ac "^$rec " "$B") lignes)" \
    || echo "    *** DIVERGENT ***"
done
echo "================ tableau : les lignes que les gates lisent"
TA=$D/keira-room-table.c106-BASE.txt
TB=$D/keira-room-table.txt
for pat in '^ROOM-SKINPEN: ' '^ROOM-SKINPEN-DETAIL:' '^ROOM-SKINPEN-REST:' '^ROOM-SKINPEN-VERDICT:' \
           '^ROOM-SKINPEN-COUT:' '^ROOM-IDLE:' '^ROOM-ANIMS:' '^ROOM-POSCONTROL' '^ROOM-AUTHORED'; do
  echo "---- $pat"
  diff <(grep -E "$pat" "$TA" 2>/dev/null) <(grep -E "$pat" "$TB" 2>/dev/null) \
    && echo "    identique" || true
done
echo "================ LA MESURE DU CYCLE"
grep -E '^ROOM-SKINLEVER' "$TB" || echo "  (absente — le tableau ne l'a pas ecrite)"
echo "================ trace brute du levier (tag=run)"
grep -aE '^PHYSSKLV[0-9]? tag=run ' "$B" || echo "  (absente)"
