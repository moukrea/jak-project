#!/usr/bin/env bash
# keira_c10_measure.sh — CYCLE 10 : compiler, courir la salle, batir le tableau, en tenant le
# verrou de livraison pendant TOUTE la duree.
#
# Pourquoi un script et pas trois commandes : l'auto-constructeur (auto_build_apk.sh) POSSEDE
# l'arbre de mesure et le bascule en arm64 en cours de course — mesure du 2026-08-14, la course
# est morte a 15 s pres sur `out/jak1/obj/assistant-ag.go absent`. Le seul verrou qu'il lit
# lui-meme est `.autoport/.deploy-in-progress`, et la convention des DIRECTIVES (2026-08-14 07:10)
# exige qu'il porte un PID et son nettoyage : un verrou vide a coute 108 minutes sans APK.
set -uo pipefail
cd "$(dirname "$0")/.."

OUT=.autoport/reports/Grecharged-secondary-motion
LOCK=.autoport/.deploy-in-progress
TAG="${TAG:-C10RAD}"

printf 'keira_c10_measure pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

# --- 0. le tableau precedent est garde : le diff est la seule verification de non-regression ----
if [ -f "$OUT/keira-room-table.txt" ]; then
  cp -f "$OUT/keira-room-table.txt" "$OUT/keira-room-table.PRE-$TAG.txt"
  echo "garde: keira-room-table.PRE-$TAG.txt"
fi
if [ -f "$OUT/keira-room-x86.log" ]; then
  cp -f "$OUT/keira-room-x86.log" "$OUT/keira-room-x86.PRE-$TAG.log"
fi

# --- 1. compilation GOAL ------------------------------------------------------------------------
echo "=== (mi) $(date -Is) ==="
./build/goalc/goalc --user-auto --game jak1 -c '(mi)' > "$OUT/c10_mi.log" 2>&1
MI=$?
tail -6 "$OUT/c10_mi.log"
if [ "$MI" -ne 0 ]; then echo "FAIL: (mi) sort a $MI"; exit 1; fi
grep -qiE '^ *-- compilation error|error:' "$OUT/c10_mi.log" && { echo "FAIL: erreur de compilation"; exit 1; }

# --- 2. empreinte AVANT : l'arbre est-il reste x86 pendant la course ? ---------------------------
MD5A=$(md5sum out/jak1/iso/GAME.CGO | cut -d' ' -f1)
echo "GAME.CGO avant = $MD5A"

# --- 3. la course --------------------------------------------------------------------------------
echo "=== salle $(date -Is) ==="
ROOM_TIMEOUT=1500 bash .autoport/keira_room_x86.sh
RC=$?

MD5B=$(md5sum out/jak1/iso/GAME.CGO | cut -d' ' -f1)
echo "GAME.CGO apres = $MD5B"
[ "$MD5A" = "$MD5B" ] || echo "ALERTE: GAME.CGO a change PENDANT la course — mesure non attribuable"

[ "$RC" -eq 0 ] || { echo "FAIL: la salle sort a $RC"; exit 1; }

# --- 4. le tableau (keira_room_x86.sh ne le fait PAS) --------------------------------------------
echo "=== tableau $(date -Is) ==="
python3 .autoport/physics_room_table.py "$OUT/keira-room-x86.log" "$OUT/keira-room-table.txt"
echo "rc_table=$?"
wc -l "$OUT/keira-room-table.txt"
echo "=== fin $(date -Is) ==="
