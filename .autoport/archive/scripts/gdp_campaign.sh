#!/usr/bin/env bash
# gdp_campaign.sh — Ggrass-density-presets : LA CAMPAGNE DE PREUVE x86, EN UNE PASSE.
#
# Sept jambes, dans cet ordre :
#   1. en-direct    training, herbe armee, PRE-CALCUL DESARME -> la ligne de base du chemin lourd.
#                   C'est la SEULE jambe qui emprunte encore `scan_level`, et elle n'existe que
#                   parce qu'une comparaison sans echelle ne veut rien dire.
#   2-6. les cinq paliers, pre-calcul arme, deux chargements chacun = 10 courses.
#   7. apres-beach  la plage APRES son retrait de kGrassLevels -> l'autre moitie du couple
#                   avant/apres que le mandat exige.
#
# Chaque jambe redemarre gk : un palier se lit au CHARGEMENT du niveau, et on veut mesurer un pic
# memoire qui ne traine pas celui de la jambe precedente.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Ggrass-density-presets
RUN=.autoport/gdp_x86_run.sh
mkdir -p "$OUT"
leg(){ # <tag> <continue> <cycles> <herbe> <pre> <palier>
  echo; echo "################ JAMBE $1 ################"
  bash "$RUN" "$2" "$3" "$1" "$4" "$5" "$6" 2>&1 | tee "$OUT/$1.console" | tail -4
}
leg en-direct   training-start 3 on off medium
leg p-very-low  training-start 2 on on  very-low
leg p-low       training-start 2 on on  low
leg p-medium    training-start 2 on on  medium
leg p-high      training-start 2 on on  high
leg p-very-high training-start 2 on on  very-high
leg apres-beach beach-start    3 on on  medium
echo; echo "################ VERDICTS ################"
cat "$OUT"/en-direct.verdict "$OUT"/p-*.verdict "$OUT"/apres-beach.verdict 2>/dev/null
