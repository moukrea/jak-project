#!/usr/bin/env bash
# acquis/flipped-faces.sh — AUCUNE FACE A L'ENVERS NE TOMBE AU NOIR NI NE PERD L'OMBRE.
#
# CE QU'ON GARDE : sur les deux niveaux ou l'owner a vu le defaut (village3 : sol noir ;
# village1 : ombre de Jak qui disparait sur les ponts), le recensement du moteur
# (`flip_census.cpp`, tournee `OG_FLIP_TOUR=1`) compare, pixel par pixel, l'ombrage rendu a son
# JUMEAU (le meme fragment ombre avec la normale source de sens oppose). Un couple (niveau,
# famille) est en defaut si une face a l'envers y rend moins de la moitie de sa base la ou le
# jumeau n'y tombe pas, ou si l'ombrage de decor depend de l'enroulement (ombre comprise).
#
# CE QU'ON NE GARDE PAS : la part de normales stockees a l'envers (`flipped_ppm`) — c'est la
# donnee du niveau, pas le rendu ; elle est publiee par la preuve de l'item, pas jugee ici.
#
# La ligne jugee est `FLIP-CENSUS RESULT`, ecrite par le moteur a la fin de la tournee.
ACQ_NAME=flipped-faces
. "$(dirname "$0")/_lib.sh"

LOG=$(acq_x86_log flipfaces 300 OG_FLIP_TOUR=1 OG_FLIP_TOUR_LEVELS=village1,village3 OG_TOD_HOUR=12) \
  || acq_unprovable "pas de course x86 mesurable (gk absent, pas d'affichage, ou un build ecrit en ce moment)"
acq_norm "$LOG" > "$LOG.n"
RES=$(grep -a 'FLIP-CENSUS RESULT ' "$LOG.n" | tail -1)
rm -f "$LOG.n"

[ -n "$RES" ] || acq_unprovable "la tournee n'a pas fini en 300 s (aucune ligne FLIP-CENSUS RESULT) : instrument ou warp a verifier avant d'accuser le rendu"
val(){ printf '%s' "$RES" | grep -oE "(^| )$1=[^ ]+" | head -1 | cut -d= -f2; }
VIS=$(val levels_visited); EXP=$(val levels_expected); MES=$(val couples_measured)
DARK=$(val dark_list); UNM=$(val unmeasured_list)
[ "${EXP:-0}" -gt 0 ] && [ "${VIS:-0}" = "$EXP" ] \
  || acq_unprovable "tournee incomplete (${VIS:-?}/${EXP:-?} niveaux) : un warp a echoue, rien a juger — $RES"
[ "${MES:-0}" -gt 0 ] || acq_unprovable "aucun couple mesure : la sonde n'a rien lu — $RES"
[ "${DARK:--}" = "-" ] || acq_broken "couple(s) en defaut : $DARK — $RES"
acq_ok "couples_mesures=$MES sans defaut sur village1+village3, non mesures=${UNM:--} (information)"
