#!/usr/bin/env bash
# Garde en vie les deux maillons de la livraison.
#
# CORRECTION DEFINITIVE (2026-08-12 07:15) : plus aucune correspondance de motif. Chaque demon
# ecrit son PID dans .autoport/.<nom>.pid et le superviseur teste `kill -0`. Un PID ne peut pas se
# confondre avec la ligne de commande d'un grep — le piege qui a fait tuer la chaine de livraison
# toutes les deux minutes toute la nuit, et qui etait tombe quatre fois en 24h sous des formes
# differentes (pkill -f, ps|grep -c, alive.sh, grep -cF).
cd "$(dirname "$0")/.." || exit 1
LOG=.autoport/logs/auto_build_apk.txt

vivant() {                                   # $1 = nom du demon sans .sh
  local pf=".autoport/.$1.pid"
  [ -f "$pf" ] || return 1
  local p; p=$(cat "$pf" 2>/dev/null)
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}

while true; do
  for prog in auto_push_builds auto_build_apk; do
    if ! vivant "$prog"; then
      echo "$(date +%H:%M:%S) $prog absent (pas de PID vivant) — respawn" >> "$LOG"
      setsid bash ".autoport/$prog.sh" </dev/null >/dev/null 2>&1 &
      sleep 3
    fi
  done
  sleep 120
done
