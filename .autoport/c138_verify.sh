#!/usr/bin/env bash
# c138_verify.sh — LES PREDICTIONS DU c138, CONFRONTEES A LA COURSE.
# Ne CHOISIT rien : relit `.autoport/c138-predictions.txt`, ecrit AVANT la compilation.
# Garde : la TABLE est regeneree ici, jamais supposee fraiche (registre validator-reads-a-stale-table).
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=.autoport/reports/Grecharged-secondary-motion
LOG="$OUT/keira-room-x86.log"; TBL="$OUT/keira-room-table.txt"
[ -f "$LOG" ] || { echo "FAIL: pas de log de course"; exit 2; }
echo "log md5 : $(md5sum "$LOG" | cut -d' ' -f1)   ($(stat -c%y "$LOG"))  taille $(stat -c%s "$LOG")"
grep -aq PHYSEND "$LOG" || { echo "!! PAS DE PHYSEND — course TRONQUEE, aucun chiffre recevable"; exit 3; }

echo
echo "== P1..P5 — LE CANAL A-T-IL ETE LU ? (preuve DIRECTE, pas par ses effets) =="
echo "   ligne de base d'un canal ABSENT : r0=0 r1=0 w0=1 w1=1 p=0"
grep -ao "PHYSGRAD31 c=[01] i=[0-9]* .*"  "$LOG" | sort -u | sed 's/^/   /' | head -24
grep -ao "PHYSGRAD31P c=[01] i=[0-9]* .*" "$LOG" | sort -u | sed 's/^/   /' | head -4

echo
echo "== P11/P12 — L'AXE LATERAL DU SOLVEUR EST-IL ANTI-SYMETRIQUE ? (PHYSTRI a=0) =="
grep -ao "PHYSTRI c=[01] a=0 .*" "$LOG" | sort -u | sed 's/^/   /'
echo "   -- et la 3e ligne du triedre d'ANISOTROPIE, ajoutee ce cycle (objet DIFFERENT) --"
grep -ao "PHYSAXR c=[01] a=2 .*" "$LOG" | sort -u | sed 's/^/   /'

echo
echo "== P14 — LES ECHELLES COMMANDEES DOIVENT ETRE INCHANGEES (le gradient agit APRES) =="
grep -ao "PHYSORI2 c=[01] i=[0-9]* sx=[0-9.]* sy=[0-9.]* sz=[0-9.]* det=[0-9.]*" "$LOG" | sort -u > /tmp/c138_ori2.now
echo "   $(wc -l < /tmp/c138_ori2.now) lignes uniques"
if [ -f /tmp/c138_ori2.ref ]; then
  diff -q /tmp/c138_ori2.ref /tmp/c138_ori2.now >/dev/null && echo "   IDENTIQUES a la course de reference" \
    || { echo "   DIFFERENTES :"; diff /tmp/c138_ori2.ref /tmp/c138_ori2.now | sed 's/^/     /'; }
else
  echo "   (pas de reference /tmp/c138_ori2.ref)"
fi

echo
echo "== 1. REGENERATION DE LA TABLE =="
python3 .autoport/physics_room_table.py "$LOG" "$TBL" >/dev/null || { echo "FAIL: table"; exit 5; }
echo "table md5 : $(md5sum "$TBL" | cut -d' ' -f1)"

echo
echo "== P6..P10 — L'ORGANE LIVRE (instrument c133, portage controle) =="
python3 .autoport/c133_delivered_com.py "$LOG" 2>&1 | tee /tmp/c138_after.txt \
  | grep -aE "w>0\.00 +§1[012] +i=[0-9]+ +(LIVREE|DECOMPOSITION SIGNEE)|portage|HORS DEFAUT" \
  | grep -av "w>0.05"

echo
echo "== P6/P7 vus par le predicteur, sur la course NEUVE (w=1 est le controle hors defaut) =="
python3 .autoport/c138_graded_tensor.py "$LOG" 2>&1 | grep -aE "ACTUEL|FALSIFICATION|CONTROLE|r par maillon"

echo
echo "== COUPLAGE DE SECOND ORDRE — le plafond de SPEC 21 mord-il ? (s'il mord, il change la"
echo "   TRANSLATION, que le modele de prediction suppose invariante) =="
grep -ao "PHYSE21 .*" "$LOG" | sort -u | head -4
grep -ao "PHYSE22 .*" "$LOG" | sort -u | head -4

echo
echo "== P13 — ROOM-IDLE =="
grep -a "^ROOM-IDLE:" "$TBL" | sed 's/^/   /'
