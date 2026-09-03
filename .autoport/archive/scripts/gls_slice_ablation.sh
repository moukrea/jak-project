#!/usr/bin/env bash
# Gloading-screen (owner 2026-08-29, retour n.4) — CONTROLE PAR ABLATION DU GEL.
#
# « ca freeze par moment (quand ca charge des gros trucs je suppose) ca devrait etre fluide ! »
#
# Le MEME binaire est lance deux fois ; la SEULE difference est `OG_LOADSCREEN_SLICE_MS` :
#   0   -> tranche NON BORNEE = exactement le chemin d'avant (Loader::update_blocking tournait
#          jusqu'a la fin du televersement, thread GOAL parque, aucune frame produite) ;
#   40  -> la valeur livree.
# La grandeur qui tranche est `LOADSCREEN-GAP ecart_max_ms=`, mesuree cote C++ sur une VRAIE
# horloge (steady_clock) : c'est la duree du plus long intervalle entre deux images REELLEMENT
# presentees pendant que l'ecran de chargement est affiche. Elle n'est PAS lisible depuis GOAL :
# sur l'appareil l'horloge de jeu est virtuelle et plafonnee (gk_android_main.cpp:793-799), elle
# sous-estimerait le gel par construction.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=".autoport/reports/Gloading-screen"; mkdir -p "$OUT"
LOCK=".autoport/.deploy-in-progress"
printf 'gls_slice_ablation pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

for MS in 0 40; do
  echo "===================== OG_LOADSCREEN_SLICE_MS=$MS ====================="
  OG_LOADSCREEN_SLICE_MS="$MS" bash .autoport/gls_x86_repl.sh "slice$MS" 30 0 \
      > "$OUT/slice$MS-harness.txt" 2>&1
  sleep 5
done

echo "===================== BILAN ====================="
for MS in 0 40; do
  L="$OUT/repl-slice$MS.log"
  echo "--- slice=${MS} ms  ($L) ---"
  grep -a "LOADSCREEN-GAP" "$L" | tail -8
  echo "  cadence GOAL (LOADSCREEN-SHOW, 60 frames entre deux lignes) :"
  grep -a "LOADSCREEN-SHOW" "$L" | tail -8
  echo "  horloges :"
  grep -a "LOADSCREEN-CLOCK" "$L" | tail -6
  echo "  barrieres :"
  grep -aE "LOADGATE (open|expire)" "$L" | tail -6
done
