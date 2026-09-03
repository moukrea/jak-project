#!/usr/bin/env bash
# Gcutscene-npc-flicker-2 — CAMPAGNE APPAREIL, LA CINEMATIQUE DU MAIRE EN TETE.
#
# L'owner voit le defaut sur SON telephone, et il a NOMME le cas : « le pire cas que j'ai observé
# c'est la cinématique avec MAIRE (la première) ». La campagne du cycle 1 fermait trois scenes qui
# n'etaient pas celle-la ; un compte de scenes ne vaut rien sans le cas nomme.
#
# DEUX CONDITIONS DE SORTIE, ET LA PREMIERE EST LE CONTROLE POSITIF : si l'injection ne fait pas
# monter le compteur, l'instrument est muet et son zero ne veut rien dire.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gcutscene-npc-flicker/device2; mkdir -p "$OUT"
R="$OUT/campagne.txt"; : > "$R"
DUR="${DUR:-300}"
KICKS="${KICKS:-mayor,sculptor,bird-lady-beach}"
{
  echo "===== campagne appareil cycle 2 — $(date -Is) ====="
  echo "-- jambe 0 : CONTROLE POSITIF (injection sur TOUS les modeles -lod0) + kick du maire"
} | tee -a "$R"
OUT_OVERRIDE="$OUT" bash .autoport/npcf_device_run.sh beach-start "$DUR" 1 c2-inject -lod0:120:10 "$KICKS" 2>&1 | tail -60 | tee -a "$R"
echo "-- jambe 1 : cinematiques REELLES, aucune injection" | tee -a "$R"
OUT_OVERRIDE="$OUT" bash .autoport/npcf_device_run.sh beach-start "$DUR" 1 c2-mayor-hd1 "" "$KICKS" 2>&1 | tail -60 | tee -a "$R"
echo "-- jambe 2 : ablation des modeles HD sur le MEME binaire" | tee -a "$R"
OUT_OVERRIDE="$OUT" bash .autoport/npcf_device_run.sh beach-start "$DUR" 0 c2-mayor-hd0 "" "$KICKS" 2>&1 | tail -60 | tee -a "$R"

D=.autoport/reports/Gcutscene-npc-flicker/device
INJ=$(grep -ac 'NPCFLICK-EV' "$D/dev-c2-inject-logcat.txt" 2>/dev/null || true)
MAYOR=$(cat "$D"/dev-c2-mayor-hd1-logcat.txt "$D"/dev-c2-mayor-hd0-logcat.txt 2>/dev/null \
        | grep -ac 'NPCFLICK .*scene=mayor-introduction' || true)
CYC=$(cat "$D"/dev-c2-mayor-hd1-logcat.txt "$D"/dev-c2-mayor-hd0-logcat.txt 2>/dev/null \
      | grep -a 'NPCFLICK ' | sed -n 's/.*cycles=\([0-9]*\).*/\1/p' | awk '{s+=$1} END {print s+0}')
{
  echo "-- controle positif (jambe injection) : $INJ evenement(s)"
  echo "-- lignes NPCFLICK sur scene=mayor-introduction : $MAYOR"
  echo "-- cycles de cause DEFECTUEUSE (jambes sans injection) : $CYC"
} | tee -a "$R"
OK=1
[ "${INJ:-0}" -ge 1 ] || { echo "FAIL: le controle positif n'a pas tire — instrument muet sur l'appareil" | tee -a "$R"; OK=0; }
[ "${MAYOR:-0}" -ge 1 ] || { echo "FAIL: la cinematique du MAIRE n'a pas ete atteinte — c'est le cas que l'owner a nomme" | tee -a "$R"; OK=0; }
[ "${CYC:-0}" -eq 0 ] || { echo "FAIL: $CYC clignotement(s) mesure(s)" | tee -a "$R"; OK=0; }
echo "===== fin campagne appareil cycle 2 — $(date -Is) =====" | tee -a "$R"
[ "$OK" = 1 ] || exit 1
