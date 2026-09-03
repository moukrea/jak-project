#!/usr/bin/env bash
# Gcutscene-npc-flicker-2, CYCLE 3 — CAMPAGNE APPAREIL SUR LA CINEMATIQUE DU MAIRE.
#
# L'owner (2026-09-03) : « bah non c'est toujours pété, première cinématique avec le Maire est le
# worst offender ». La preuve du 02/09 etait prise SUR PC. Celle-ci est prise sur le Redmi
# eae4df44, avec la ROUTE qui atteint le maire (spawn devant `mayor-5`, beach amene en 'active puis
# affiche, kick de type `mayor`), et TROIS jambes :
#   0  CONTROLE POSITIF : injection de disparitions sur tous les modeles -lod0 — si le compteur ne
#      monte pas SUR L'APPAREIL, l'instrument y est muet et son zero ne vaut rien ;
#   1  modeles HD ACTIFS, aucune injection — la configuration de l'owner ;
#   2  ablation des modeles HD sur le MEME binaire.
# Chaque jambe attend la fin de la course precedente (un seul gk sur l'appareil, un seul logcat).
#
# usage : npcf3_device_campagne.sh [duree_s]
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gcutscene-npc-flicker/device3; mkdir -p "$OUT"
R="$OUT/campagne.txt"; : > "$R"
DUR="${1:-${DUR:-480}}"
KICKS="${KICKS:-mayor}"
export POS="${POS--116 14 40}" WANTLEV="${WANTLEV-village1,beach}" WANTDISP="${WANTDISP-beach,display}"
export OUT_OVERRIDE="$OUT"
say(){ echo "$*" | tee -a "$R"; }
say "===== campagne appareil cycle 3 — $(date -Is) ====="
say "kicks=$KICKS duree=${DUR}s spawn='$POS' want-levels='$WANTLEV' want-display='$WANTDISP'"
LEGS="${LEGS:-inject hd1 hd0}"
for leg in $LEGS; do
  case "$leg" in
    inject) say "-- jambe 0 : CONTROLE POSITIF (injection -lod0:120:10) + kick du maire"
            bash .autoport/npcf_device_run.sh village1-hut "$DUR" 1 c3-inject -lod0:120:10 "$KICKS" 2>&1 | tail -40 | tee -a "$R" ;;
    hd1)    say "-- jambe 1 : cinematiques REELLES, modeles HD actifs, aucune injection"
            bash .autoport/npcf_device_run.sh village1-hut "$DUR" 1 c3-mayor-hd1 "" "$KICKS" 2>&1 | tail -40 | tee -a "$R" ;;
    hd0)    say "-- jambe 2 : ablation des modeles HD sur le MEME binaire"
            bash .autoport/npcf_device_run.sh village1-hut "$DUR" 0 c3-mayor-hd0 "" "$KICKS" 2>&1 | tail -40 | tee -a "$R" ;;
  esac
done

INJ=$(grep -ac 'NPCFLICK-EV .*scene=mayor-introduction' "$OUT/dev-c3-inject-logcat.txt" 2>/dev/null || true)
MAYOR=$(cat "$OUT"/dev-c3-mayor-hd1-logcat.txt "$OUT"/dev-c3-mayor-hd0-logcat.txt 2>/dev/null \
        | grep -a 'NPCFLICK .*scene=mayor-introduction .*pnj=mayor' | grep -ac 'plateforme=redmi' || true)
CYC=$(cat "$OUT"/dev-c3-mayor-hd1-logcat.txt "$OUT"/dev-c3-mayor-hd0-logcat.txt 2>/dev/null \
      | grep -a 'NPCFLICK ' | sed -n 's/.*cycles=\([0-9]*\).*/\1/p' | awk '{s+=$1} END {print s+0}')
GARB=$(cat "$OUT"/dev-c3-*-logcat.txt 2>/dev/null | grep -ac 'MATRICE-INVALIDE' || true)
FILE=$("${ADB:-adb}" -s eae4df44 shell "wc -l < /storage/emulated/0/OpenGOAL/jak1/npc_flicker.txt" 2>/dev/null | tr -d '\r' || true)
{
  echo "-- controle positif : $INJ evenement(s) NPCFLICK-EV sur mayor-introduction (jambe injection)"
  echo "-- lignes NPCFLICK du MAIRE sur scene=mayor-introduction, plateforme=redmi : $MAYOR"
  echo "-- cycles de cause DEFECTUEUSE (jambes sans injection) : $CYC"
  echo "-- paquets MATRICE-INVALIDE (toutes jambes) : $GARB"
  echo "-- fichier npc_flicker.txt sur l'appareil : ${FILE:-absent} ligne(s)"
} | tee -a "$R"
OK=1
[ "${INJ:-0}" -ge 1 ] || { echo "FAIL: le controle positif n'a pas tire sur la scene du maire — instrument muet sur l'appareil" | tee -a "$R"; OK=0; }
[ "${MAYOR:-0}" -ge 1 ] || { echo "FAIL: le MAIRE n'est pas suivi dans sa propre cinematique sur le Redmi" | tee -a "$R"; OK=0; }
[ "${CYC:-0}" -eq 0 ] || { echo "FAIL: $CYC clignotement(s) mesure(s)" | tee -a "$R"; OK=0; }
echo "===== fin campagne appareil cycle 3 — $(date -Is) =====" | tee -a "$R"
[ "$OK" = 1 ] || exit 1
