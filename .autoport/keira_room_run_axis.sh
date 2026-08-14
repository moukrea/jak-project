#!/usr/bin/env bash
# keira_room_run_axis.sh — UNE course de la salle, avec les trois gardes qui ont deja coute un cycle.
#
# Phase Grecharged-secondary-motion, branche physics-keira-clean.
# DIRECTIVES vee00ab7404 — perimetre : chestL/chestR seules, spec poitrine a 100 %.
#
# Ce script ne juge RIEN et ne mesure RIEN : il sequence. Les trois gardes :
#
#  1. LE VERROU DE LIVRAISON, A LA CONVENTION DU 2026-08-14 07:10 : PID ecrit dedans + `trap EXIT`.
#     Jamais un `touch` nu — un verrou sans detenteur a deja coute 108 minutes sans APK a l'owner.
#     Il tient le constructeur automatique a distance : celui-ci efface `out/jak1/obj/*.go` et
#     reecrit `out/jak1/iso` pour passer en arm64, et la garde de fraicheur de la salle compare des
#     DATES, pas une architecture — une course x86 sur un `out/jak1/iso` arm64 ne dirait rien.
#
#  2. LE HACHAGE DE `GAME.CGO` AVANT ET APRES. C'est la seule preuve que la course a mesure le
#     moteur qu'on vient de compiler, et pas un tiroir qu'un autre processus a change en cours de
#     route.
#
#  3. LA TABLE EST UNE SECONDE COMMANDE. `keira_room_x86.sh` ne fait que recolter le log ; oublier
#     `physics_room_table.py` laisse en place la table de la course PRECEDENTE, ce qui se lit
#     exactement comme « mon changement n'a rien fait ».
#
# Et `ROOM_TIMEOUT=1500` : la course demande ~520 s (31 anims x 5 pilotages + le controle positif),
# le defaut de 420 s du script sous-jacent la tue APRES avoir ecrase le log.
set -uo pipefail
cd "$(dirname "$0")/.."

TAG="${1:-AXIS}"
OUT=.autoport/reports/Grecharged-secondary-motion
LOG="$OUT/keira-room-x86.log"
TBL="$OUT/keira-room-table.txt"
LOCK=.autoport/.deploy-in-progress

# --- garde 1 : le verrou, avec detenteur et nettoyage --------------------------------------------
if [ -e "$LOCK" ]; then
  echo "verrou deja pose : $(cat "$LOCK" 2>/dev/null)"
  echo "on ne l'ecrase pas — un verrou vivant appartient a quelqu'un d'autre."
  exit 3
fi
printf 'keira_room_run_axis pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

# --- la table de la course precedente est archivee AVANT d'etre ecrasee -------------------------
# c'est le seul controle de regression qui tourne : le diff entre deux tables.
[ -f "$TBL" ] && cp -f "$TBL" "$OUT/keira-room-table.${TAG}-PREV.txt"

CGO_BEFORE=$(md5sum out/jak1/iso/GAME.CGO | cut -d' ' -f1)
echo "GAME.CGO avant : $CGO_BEFORE"

ROOM_TIMEOUT=1500 bash .autoport/keira_room_x86.sh
RC=$?

CGO_AFTER=$(md5sum out/jak1/iso/GAME.CGO | cut -d' ' -f1)
echo "GAME.CGO apres : $CGO_AFTER"
if [ "$CGO_BEFORE" != "$CGO_AFTER" ]; then
  echo "FAIL: GAME.CGO a change PENDANT la course — elle n'a pas mesure un moteur unique."
  exit 4
fi
[ "$RC" -eq 0 ] || { echo "FAIL: la course a rendu $RC"; exit "$RC"; }

# --- garde 3 : la table, seconde commande -------------------------------------------------------
python3 .autoport/physics_room_table.py "$LOG" "$TBL" || { echo "FAIL: table"; exit 5; }
cp -f "$LOG" "$OUT/keira-room-x86.${TAG}.log"
cp -f "$TBL" "$OUT/keira-room-table.${TAG}.txt"
echo "OK: log + table ecrits (tag $TAG), CGO stable $CGO_AFTER"
