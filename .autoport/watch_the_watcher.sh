#!/usr/bin/env bash
# Garde en vie les DEUX maillons de la livraison. Le publieur est mort trois fois (tempête d'API,
# variable non liée, cause inconnue) ; le constructeur d'APK est mort le 2026-08-11 à 15:15 parce
# que le superviseur a ÉDITÉ le script pendant qu'il tournait — bash relit le fichier au fil de
# l'exécution, donc toute édition en vol tue l'instance. Le respawn rend l'incident sans effet.
cd "$(dirname "$0")/.." || exit 1
while true; do
  if ! ps -eo args | grep -q '[a]uto_push_builds.sh'; then
    echo "$(date +%H:%M:%S) publieur mort — respawn" >> .autoport/logs/auto_push_builds.txt
    setsid bash .autoport/auto_push_builds.sh </dev/null >/dev/null 2>&1 &
  fi
  if ! ps -eo args | grep -q '[a]uto_build_apk.sh'; then
    echo "$(date +%H:%M:%S) constructeur d'APK mort — respawn" >> .autoport/logs/auto_build_apk.txt
    setsid bash .autoport/auto_build_apk.sh </dev/null >/dev/null 2>&1 &
  fi
  sleep 120
done
