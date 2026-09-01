#!/usr/bin/env bash
# Gcutscene-npc-flicker — campagne appareil : 3 cinematiques + le CONTROLE POSITIF sur le
# telephone. Une course a zero cycle ne vaut rien si l'instrument peut etre muet : la premiere
# jambe injecte une disparition et exige que le compteur monte.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gcutscene-npc-flicker/device; mkdir -p "$OUT"
R="$OUT/campagne.txt"; : > "$R"
DUR="${DUR:-220}"
{
  echo "===== campagne appareil — $(date -Is) ====="
  echo "-- jambe 0 : CONTROLE POSITIF (injection sur sage-lod0)"
} | tee -a "$R"
bash .autoport/npcf_device_run.sh intro-start "$DUR" 1 inject sage-lod0:120:12 2>&1 | tail -40 | tee -a "$R"
for s in intro-start village1-intro village1-warp; do
  echo "-- jambe $s (modeles HD actifs, pas d'injection)" | tee -a "$R"
  bash .autoport/npcf_device_run.sh "$s" "$DUR" 1 2>&1 | tail -40 | tee -a "$R"
done
# UNE CAMPAGNE QUI NE PEUT PAS ECHOUER N'EST PAS UNE PORTE. Deux conditions, et la premiere est
# le controle positif : si l'injection ne fait pas monter le compteur, l'instrument est muet et un
# zero ne veut rien dire.
INJ=$(grep -ac 'NPCFLICK-EV' "$OUT/dev-inject-logcat.txt" 2>/dev/null || true)
# La jambe d'injection est EXCLUE du compte : ses cycles sont voulus, c'est le controle positif.
CYC=$(cat "$OUT"/dev-intro-start-hd1-logcat.txt "$OUT"/dev-village1-intro-hd1-logcat.txt \
          "$OUT"/dev-village1-warp-hd1-logcat.txt 2>/dev/null \
      | grep -a 'NPCFLICK ' | sed -n 's/.*cycles=\([0-9]*\).*/\1/p' | awk '{s+=$1} END {print s+0}')
{
  echo "-- controle positif (jambe injection) : $INJ evenement(s)"
  echo "-- cycles de cause DEFECTUEUSE sur les 3 cinematiques : $CYC"
} | tee -a "$R"
OK=1
[ "${INJ:-0}" -ge 1 ] || { echo "FAIL: le controle positif n'a pas tire — instrument muet sur l'appareil" | tee -a "$R"; OK=0; }
[ "${CYC:-0}" -eq 0 ] || { echo "FAIL: $CYC clignotement(s) mesure(s)" | tee -a "$R"; OK=0; }
echo "===== fin campagne appareil — $(date -Is) =====" | tee -a "$R"
[ "$OK" = 1 ] || exit 1
