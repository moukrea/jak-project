#!/usr/bin/env bash
# Gplayability-input-and-loadgate — mesure APRES, sur la MEME sequence que la mesure AVANT.
#
# Grandeurs, et leur nature (les trois questions du contrat) :
#   SON   = `A36-STR-DIAG rpc name="<scene>" chunk=0`  (game/overlord/jak1/stream.cpp:104)
#           NATURE : un INSTANT (le premier chunk du flux part).
#   IMAGE = `F1D-LOADSYNC lev=<niveau> glFinish at load completion` (Loader.cpp:1403)
#           NATURE : un INSTANT (le niveau devient DESSINABLE, GPU compris).
#           REPERE : residence cote renderer, PAS `level-status` cote GOAL.
#   ECART = IMAGE - SON, en ms. Positif = le son est en avance sur l'image (le defaut).
# Ce que la mesure lit quand le defaut est ABSENT : un ecart <= 0.
set -uo pipefail
DEV="${1:-eae4df44}"   # owner 2026-08-30 : Shield INTERDITE, defaut = Redmi
OUT="${2:-/tmp/loadgate_after.log}"
adb connect "$DEV" >/dev/null 2>&1
adb -s "$DEV" logcat -c >/dev/null 2>&1
adb -s "$DEV" shell am force-stop org.opengoal.gk.jak1 >/dev/null 2>&1
sleep 3
adb -s "$DEV" shell monkey -p org.opengoal.gk.jak1 -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
echo "lance; capture 150 s..."
PEAK=0
for i in $(seq 1 30); do
  sleep 5
  R=$(adb -s "$DEV" shell "ps -A -o RSS,NAME 2>/dev/null | grep opengoal.gk.jak1 | head -1 | awk '{print \$1}'" 2>/dev/null | tr -d '\r')
  case "$R" in ''|*[!0-9]*) ;; *) [ "$R" -gt "$PEAK" ] && PEAK="$R" ;; esac
done
adb -s "$DEV" logcat -d -b all > "$OUT" 2>/dev/null
echo "PIC_RSS_KB=$PEAK"
echo "PIC_RSS_MO=$((PEAK/1024))"
echo "--- lignes de la barriere ---"
grep -aE "LOADGATE" "$OUT" || echo "(aucune ligne LOADGATE)"
echo "--- son / image ---"
grep -aE 'A36-STR-DIAG rpc name="(ndi-intro|logo-intro|sage-intro-sequence-e)" chunk=0|F1D-LOADSYNC|GAMEPLAY: enter title|coming out of blackout' "$OUT"
