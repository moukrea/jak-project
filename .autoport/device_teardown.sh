#!/usr/bin/env bash
# device_teardown.sh — vide les proprietes de debogage que notre outillage pose sur un appareil.
#
# POURQUOI CE FICHIER EXISTE (2026-08-28) : `debug.opengoal.cpad_inject` etait restee a `x` sur
# la Shield de l'owner. Le jeu lit cette propriete en continu, `x` = bit 14 = CROIX : le bouton
# de saut etait donc TENU en permanence. Un bouton tenu n'emet aucun front, et le saut ne tire
# que sur le front -- le jeu etait injouable pendant des semaines, avec une chaine d'entree qui
# mesurait « saine » a chaque controle. 94 des 101 scripts qui posent cette propriete ne la
# vident jamais.
#
# A APPELER A LA FIN DE TOUTE SESSION SUR APPAREIL, y compris en cas d'echec :
#   trap '.autoport/device_teardown.sh "$DEV"' EXIT
set -u
DEV="${1:-}"
PROPS="cpad_inject f1.warp level.warp gspeed.measure gspeed.off render.scale"
targets(){ [ -n "$DEV" ] && echo "$DEV" || adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1}'; }
for d in $(targets); do
  for p in $PROPS; do
    v=$(adb -s "$d" shell "getprop debug.opengoal.$p" 2>/dev/null | tr -d '\r')
    if [ -n "$v" ]; then
      adb -s "$d" shell "setprop debug.opengoal.$p ''" 2>/dev/null
      echo "[teardown] $d: debug.opengoal.$p etait '$v' -> vide"
    fi
  done
  adb -s "$d" shell "run-as org.opengoal.gk.jak1 rm -f files/cpad_inject" 2>/dev/null
done
exit 0
