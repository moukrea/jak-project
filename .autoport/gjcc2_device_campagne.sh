#!/usr/bin/env bash
# Gjak1-crate-collision-2 — LA CAMPAGNE APPAREIL, EN PAIRE.
# Deux courses ABLATEES (gjcc=35 : garde NaN retiree = comportement d'avant ce cycle)
# puis trois courses CORRIGEES (gjcc=3), sur le MEME BINAIRE, a la cadence que le
# Redmi rend vraiment. Sans la paire, un zero ne veut rien dire.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
D="${DUR:-300}"
# Les caisses de Geyser Rock ne sont PAS au point de depart : la plus proche est a 39 m et
# elles s'etalent sur 244 m. Une course a l'aveugle depuis le spawn n'en approche AUCUNE
# (mesure : course `probe`, 2700 images, approchees=0, dist confirmee par GJCC-POS).
# On fait donc naitre le joueur AU MILIEU d'un amas, par `debug.opengoal.level.warp.pos`
# (metres). Les trois amas couvrent 24 des 31 caisses ; leurs centres sont calcules a
# partir de .autoport/gjcc_waypoints.txt, pas choisis a la main.
C1="-1159.72 30.0 995.85"    # 11 caisses, rayon 28 m
C2="-1196.10 31.0 862.06"    #  8 caisses, rayon 21 m
C3="-1182.03 21.0 913.49"    #  5 caisses, rayon 18 m
run(){ echo "############ COURSE $1 (gjcc=$2, amas $4) ############"
       bash .autoport/gjcc2_device_run.sh "$1" "$2" "$D" "$3" || echo "  (course $1 en echec, on continue)"
       sleep 5; }
# DEUX courses ABLATEES d'abord : sans reproduction, le vert des suivantes ne vaut rien.
run a1 35 "$C1" C1
run a2 35 "$C2" C2
run f1  3 "$C1" C1
run f2  3 "$C2" C2
run f3  3 "$C3" C3
echo "CAMPAGNE TERMINEE"
