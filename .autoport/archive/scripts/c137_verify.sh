#!/usr/bin/env bash
# c137_verify.sh — LES NEUF PREDICTIONS DU c137, CONFRONTEES A LA COURSE.
# Ce script ne CHOISIT rien : il relit `.autoport/c137-predictions.txt`, ecrit AVANT le lot.
# Garde : la TABLE est regeneree ici, jamais supposee fraiche (registre validator-reads-a-stale-table).
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=.autoport/reports/Grecharged-secondary-motion
LOG="$OUT/keira-room-x86.log"; TBL="$OUT/keira-room-table.txt"
[ -f "$LOG" ] || { echo "FAIL: pas de log de course"; exit 2; }
echo "log md5 : $(md5sum "$LOG" | cut -d' ' -f1)   ($(stat -c%y "$LOG"))  taille $(stat -c%s "$LOG")"
grep -aq PHYSEND "$LOG" || echo "!! ATTENTION : pas de PHYSEND — course TRONQUEE, aucun chiffre n'est recevable"

echo
echo "== F2 — LE CANAL A-T-IL ETE LU ? (preuve DIRECTE, pas par ses effets) =="
echo "   ligne de base d'un canal ABSENT : mw=0.0000 d=0.0000"
grep -ao "PHYSMEDW c=[01] i=[0-9]* mw=[0-9.-]* sx=[0-9.-]* d=[0-9.-]*" "$LOG" | sort -u -t= -k2 | awk '
 {print "   " $0}' | sort -u
echo
echo "   -- les cellules qui portent les verdicts --"
for i in 0 2 4 6 8 9; do grep -ao "PHYSMEDW c=[01] i=$i .*" "$LOG" | sort -u | sed 's/^/   /'; done

echo
echo "== P9 — LES ECHELLES COMMANDEES DOIVENT ETRE INCHANGEES =="
grep -ao "PHYSORI2 c=[01] i=[0-9]* sx=[0-9.]* sy=[0-9.]* sz=[0-9.]* det=[0-9.]*" "$LOG" | sort -u > /tmp/c137_ori2.now
echo "   $(wc -l < /tmp/c137_ori2.now) lignes uniques ; reference = course du c136"
if [ -f /tmp/c137_ori2.ref ]; then diff -q /tmp/c137_ori2.ref /tmp/c137_ori2.now && echo "   IDENTIQUES" || { echo "   DIFFERENTES :"; diff /tmp/c137_ori2.ref /tmp/c137_ori2.now | sed 's/^/     /'; }; fi

echo
echo "== 1. REGENERATION DE LA TABLE =="
python3 .autoport/physics_room_table.py "$LOG" "$TBL" >/dev/null || { echo "FAIL: table"; exit 5; }
echo "table md5 : $(md5sum "$TBL" | cut -d' ' -f1)"

echo
echo "== P1..P7 — L'ORGANE LIVRE (instrument c133, portage controle) =="
python3 .autoport/c133_delivered_com.py "$LOG" 2>&1 | tee /tmp/c137_after.txt \
  | grep -aE "w>0\.00 +§1[012] +i=[0-9]+ +(LIVREE|DIAGNOSTIC DIRECTIONNEL|DECOMPOSITION SIGNEE)|portage|HORS DEFAUT" \
  | grep -av "w>0.05" | grep -av "POIDS DE PEAU"

echo
echo "== P5 — LES LONGUEURS LIVREES (§11), qui ne doivent pas bouger =="
grep -a "deciles" /tmp/c137_after.txt | sed 's/^/   /'

echo
echo "== P8 — ROOM-IDLE =="
grep -a "^ROOM-IDLE:" "$TBL" | sed 's/^/   /'
