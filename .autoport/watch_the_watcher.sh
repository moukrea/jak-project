#!/usr/bin/env bash
# Garde en vie les deux maillons de la livraison, et RIEN d'autre.
#
# Historique des ratages de ce fichier, tous corriges ici :
#   * le publieur est mort trois fois (tempete d'API, variable non liee, cause inconnue) ;
#   * le constructeur est mort parce que le superviseur a edite son script en vol ;
#   * mon tueur de doublons comptait mal et TUAIT le publieur legitime toutes les 2 minutes
#     (« 2 instances de auto_push_builds » alors qu'il n'y en avait qu'une).
# Les comptages passent donc tous par .autoport/alive.sh, qui exclut soi-meme et ses ancetres.
cd "$(dirname "$0")/.." || exit 1
LOG=.autoport/logs/auto_build_apk.txt

alive() { bash .autoport/alive.sh "$1" 2>/dev/null || echo 0; }

while true; do
  for prog in auto_push_builds.sh auto_build_apk.sh; do
    # alive.sh compte encore le shell `sh -c` que setsid laisse derriere lui : verification
    # directe sur la ligne de commande exacte, c'est la seule qui ne mente pas.
    n=$(ps -eo args | grep -cF "bash .autoport/$prog" || true)
    if [ "${n:-0}" -eq 0 ]; then
      echo "$(date +%H:%M:%S) $prog mort — respawn" >> "$LOG"
      setsid bash ".autoport/$prog" </dev/null >/dev/null 2>&1 &
      sleep 3
    elif [ "${n:-0}" -gt 1 ]; then
      # on ne garde que la plus ancienne ; le constructeur a de toute facon un flock
      echo "$(date +%H:%M:%S) $n instances de $prog — doublons tues" >> "$LOG"
      ps -eo pid,etime,args | grep -F "bash .autoport/$prog" | grep -v grep \
        | sort -k2 -r | awk 'NR>1{print $1}' | while read -r p; do kill -9 "$p" 2>/dev/null; done
    fi
  done
  sleep 120
done
