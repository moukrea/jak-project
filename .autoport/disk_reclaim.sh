#!/usr/bin/env bash
# MENAGE DES JOURNAUX BRUTS — pose le 2026-08-31 apres que le disque plein a TUE LE SHELL.
# Mesure de cette nuit : 99 % d'occupation, 6,7 Go libres et en baisse ; un seul fichier de
# journal pesait 3,2 Go. La session est morte en pleine analyse et l'owner a perdu 30 min.
#
# REGLES DE SURETE, dans l'ordre :
#  1. On ne touche QU'AUX phases que l'owner a FERMEES (.autoport/owner-ok/<phase> existe).
#     Une phase en cours ou en attente de son verdict garde TOUT.
#  2. On ne supprime QUE des journaux bruts volumineux (>= SEUIL). Les rapports, verdicts,
#     captures, tableaux et documents restent : ce sont eux qui portent les preuves.
#  3. Jamais de `rm -rf` sur un dossier. On supprime fichier par fichier, sur un motif.
#  4. On ne descend jamais hors de .autoport/reports/.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
SEUIL_MO=${1:-50}
PLANCHER_GO=${2:-15}     # sous ce seuil de libre, on nettoie ; au-dessus, on ne touche a rien
libre_go() { df --output=avail -BG /home 2>/dev/null | tail -1 | tr -dc '0-9'; }
L0=$(libre_go)
if [ "${L0:-0}" -ge "$PLANCHER_GO" ]; then
  echo "$(date +%H:%M:%S) disque a ${L0} Go libres (>= ${PLANCHER_GO}) — rien a faire"
  exit 0
fi
n=0; mo=0
for ok in .autoport/owner-ok/*; do
  [ -f "$ok" ] || continue
  ph=$(basename "$ok"); d=".autoport/reports/$ph"
  [ -d "$d" ] || continue
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    sz=$(( $(stat -c %s "$f" 2>/dev/null || echo 0) / 1048576 ))
    rm -f "$f" && { n=$((n+1)); mo=$((mo+sz)); echo "  supprime ${sz}Mo $f"; }
  done < <(find "$d" -type f \( -name '*.log' -o -name '*logcat*.txt' -o -name '*.jsonl' \) -size +${SEUIL_MO}M 2>/dev/null)
done
L1=$(libre_go)
echo "$(date +%H:%M:%S) menage: $n fichier(s), ~${mo} Mo ; libre ${L0} -> ${L1} Go"
