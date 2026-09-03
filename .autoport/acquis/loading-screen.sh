#!/usr/bin/env bash
# acquis/loading-screen.sh — L'ECRAN DE CHARGEMENT GARDE UNE HORLOGE QUI NE S'ARRETE PAS EN PAUSE.
#
# CE QU'ON GARDE. Le seuil d'armement de l'ecran a deja ete mesure sur `(current-time)`, qui vit
# sous `(when (not (paused?)))` : en pause le point zero se replacait a chaque image et le seuil
# n'etait jamais atteint. Invisible sur le bureau, systematique en chargement telephone. Le
# correctif a change le repere : la sonde de demarrage publie desormais
#     LOADSCREEN-SEUIL delay=... hold=... repere=300emes-de-seconde pause-ignoree=#t
# Si `pause-ignoree=#t` disparait de cette ligne, le correctif a ete defait.
#
# INSTRUMENT : sonde one-shot au demarrage (engine/game/main.gc), sans condition, plus la paire
# LOADGATE arm/open. Aucun rapport n'est lu.
ACQ_NAME=loading-screen
. "$(dirname "$0")/_lib.sh"

LOG=$(acq_x86_log boot 50) || acq_unprovable "pas de course x86 mesurable (gk absent, pas d'affichage, ou un build ecrit en ce moment)"
acq_norm "$LOG" > "$LOG.n"
SEUIL=$(grep -a 'LOADSCREEN-SEUIL ' "$LOG.n" | tail -1)
GATE=$(grep -ac 'LOADGATE open ' "$LOG.n" || true)
BOOT=$(grep -ac 'BOOTLINE etape=' "$LOG.n" || true)
rm -f "$LOG.n"

[ "${BOOT:-0}" -gt 0 ] || acq_unprovable "aucune ligne BOOTLINE en 50 s : le jeu n'a pas demarre assez loin pour qu'on juge quoi que ce soit"
[ -n "$SEUIL" ] || acq_unprovable "la sonde LOADSCREEN-SEUIL n'a pas parle alors que le demarrage a avance ($BOOT etapes) — instrument a verifier avant d'accuser le correctif"
case "$SEUIL" in
  *pause-ignoree=#t*) ;;
  *) acq_broken "le seuil de l'ecran de chargement n'ignore plus la pause : $SEUIL" ;;
esac
acq_ok "seuil sur une horloge qui ignore la pause ; $GATE ouverture(s) de LOADGATE ; $SEUIL"
