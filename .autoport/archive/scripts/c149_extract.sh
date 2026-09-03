#!/usr/bin/env bash
# c149_extract.sh — sort, en une passe, TOUS les chiffres que le rapport du cycle 149 doit citer.
set -uo pipefail
cd "$(dirname "$0")/.."
L=${1:-.autoport/reports/Grecharged-secondary-motion/keira-room-x86.log}
T=${2:-.autoport/reports/Grecharged-secondary-motion/keira-room-table.txt}
echo "== provenance =="
md5sum "$L" "$T" 2>/dev/null
grep -c PHYSEND "$L" 2>/dev/null | sed 's/^/PHYSEND count: /'
echo; echo "== PHYSSATD (dernier tag = total de course) =="
grep PHYSSATD "$L" 2>/dev/null | tail -2
echo; echo "== compteurs de limiteur (L1 : doivent etre identiques au c148) =="
grep -E "^PHYSLIM4 " "$L" 2>/dev/null | tail -1
grep -E "^PHYSE22 |^PHYSE21 |^PHYSE22A " "$L" 2>/dev/null | tail -6
echo; echo "== gates =="
grep -E "^ROOM-IDLE:|^ROOM-JELLY-WORST|BREAST-PENETRATION|meshpen|skinpen" "$T" 2>/dev/null | head -12
echo; echo "== apex =="
grep -E "^ROOM-APEX:" "$T" 2>/dev/null | head -4
echo; echo "== ROOM-SATD =="
sed -n '/^ROOM-SATD: OPERATEUR/,/^$/p' "$T" 2>/dev/null | head -40
echo; echo "== moteur =="
wc -l goal_src/jak1/pc/jak-hd-physics.gc
md5sum recharged_assets/physics_chains.txt
