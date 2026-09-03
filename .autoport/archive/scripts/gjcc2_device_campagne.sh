#!/usr/bin/env bash
# Gjak1-crate-collision-2 — LA CAMPAGNE APPAREIL, EN PAIRE.
# Deux courses ABLATEES (gjcc=99 : garde NaN retiree = comportement d'avant ce cycle)
# puis trois courses CORRIGEES (gjcc=67), sur le MEME BINAIRE, a la cadence que le
# Redmi rend vraiment. Sans la paire, un zero ne veut rien dire.
#   bit 1  : resume par course (GJCC-RUN, GJCC-POS, GJCC-WAITFAIL)
#   bit 2  : audit du collide-cache
#   bit 32 : ABLATION de la garde de sphere degeneree
#   bit 64 : recensement complet periodique (toutes les 300 images)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
# UNE SEULE CAMPAGNE A LA FOIS. Deux campagnes lancees en parallele ecrivent dans LES
# MEMES fichiers : mesure, `dev-a1-logcat.txt` (course ABLATEE) contenait une ligne
# `GJCC-MODE mode=67` d'une course CORRIGEE, et `dev-f3-logcat.txt` portait l'horodatage
# d'une course qui n'avait pas encore commence. Deux experiences dans un fichier, et
# aucun moyen de savoir laquelle on lit. On refuse de demarrer plutot que de produire ca.
_autres=$(pgrep -f "gjcc2_device_ru[n]" | wc -l)
if [ "$_autres" -gt 0 ]; then
  echo "REFUS : $_autres course(s) deja en vol — une campagne concurrente melangerait les fichiers"
  exit 1
fi
for _p in $(pgrep -f "eae4df44 logcat" 2>/dev/null); do kill -9 "$_p" 2>/dev/null; done
D="${DUR:-420}"
# LES SEPT AMAS DE GEYSER ROCK, calcules depuis les positions relevees par le recensement
# (`GJCC-CRATE ... x= y= z=`), pas choisis a la main. Ils couvrent LES 31 caisses.
# La chaine entiere est jouee a chaque course : c'est elle qui fait TRAVERSER le rocher,
# donc naitre et mourir des caisses — l'evenement meme qui fabrique une sphere perdue.
#          amas :  C1(3)          C2(2)          C3(11)         C4(2)          C5(5)          C6(3)          C7(5)
CHAINE="-1285 1030   -1230 994    -1160 996    -1153 948    -1180 913    -1190 875    -1198 855"
run(){ echo "############ COURSE $1 (gjcc=$2) ############"
       bash .autoport/gjcc2_device_run.sh "$1" "$2" "$D" "$CHAINE" || echo "  (course $1 en echec, on continue)"
       sleep 5; }
# DEUX courses ABLATEES d'abord : sans reproduction, le vert des suivantes ne vaut rien.
run a1 99
run a2 99
run f1 67
run f2 67
run f3 67
echo "CAMPAGNE TERMINEE"
