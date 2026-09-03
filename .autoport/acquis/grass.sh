#!/usr/bin/env bash
# acquis/grass.sh — L'HERBE EST ENCORE POSEE SUR LE NIVEAU.
#
# CE QU'ON GARDE : la pose. `PLACE-TIME ... instances=N` est ecrite une fois par reconstruction
# (chargement de niveau ou changement de densite), sans aucune condition, et N est le nombre
# d'instances reellement montees. Une valeur non nulle prouve que le bake a ete lu ET etendu ;
# zero, ou une exception, veut dire qu'il ne reste rien a dessiner. L'herbe est ON par defaut
# (`recharged-grass? = #t`, decision de l'owner du 2026-07-10), donc cette garde n'est pas vide.
#
# CE QU'ON NE GARDE PAS : `drawn=` par image, qui depend de l'orientation de la camera au
# moment ou le warp depose Jak. On le PUBLIE comme information, on ne le juge pas.
#
# NIVEAU : Geyser Rock (warp F1), le niveau ou l'herbe a ete validee. Aucun rapport n'est lu.
ACQ_NAME=grass
. "$(dirname "$0")/_lib.sh"

LOG=$(acq_x86_log play 85 OG_F1_WARP=1 OG_F1_WARP_DELAY=600) \
  || acq_unprovable "pas de course x86 mesurable (gk absent, pas d'affichage, ou un build ecrit en ce moment)"
acq_norm "$LOG" > "$LOG.n"
SPAWN=$(grep -ac 'F1-SPAWN ' "$LOG.n" || true)
PLACE=$(grep -a 'recharged-grass\] PLACE-TIME ' "$LOG.n" | tail -1)
INST=$(printf '%s' "$PLACE" | grep -oE 'instances=[0-9]+' | head -1 | cut -d= -f2)
DRAWN=$(grep -aoE 'drawn=[0-9]+' "$LOG.n" | cut -d= -f2 | sort -n | tail -1)
MORT=$(grep -a 'GRASS-DEAD exception=\|AUCUN BAKE VALIDE' "$LOG.n" | head -1)
rm -f "$LOG.n"

[ -n "$MORT" ] && acq_broken "le systeme d'herbe s'est desarme pendant la course : $MORT"
[ "${SPAWN:-0}" -gt 0 ] || acq_unprovable "le warp F1 n'a pas depose Jak en 85 s (aucune ligne F1-SPAWN) : l'herbe n'a jamais eu l'occasion d'etre posee"
[ -n "$PLACE" ] || acq_unprovable "Jak est arrive mais aucune ligne PLACE-TIME : la pose n'a pas tourne — instrument ou niveau a verifier avant d'accuser l'herbe"
[ "${INST:-0}" -gt 0 ] || acq_broken "la pose a tourne et n'a monte AUCUNE instance : $PLACE"
acq_ok "instances=$INST posees, drawn max=${DRAWN:-0} (information, non juge)"
