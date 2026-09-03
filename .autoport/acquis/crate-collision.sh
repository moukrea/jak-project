#!/usr/bin/env bash
# acquis/crate-collision.sh — LES CAISSES NAISSENT ENCORE PAR PORTEE PHYSIQUE.
#
# CE QU'ON GARDE. Le defaut que l'owner a signale (des caisses qu'on traverse) venait de ceci :
# la VISIBILITE gouvernait l'EXISTENCE PHYSIQUE, donc un acteur hors champ n'avait pas de
# collision. Le correctif fait naitre l'acteur par PORTEE : `*actor-collision-birth-radius*`,
# pose a (meters 30). Le moteur publie ce rayon une fois par demarrage, sans condition :
#     GJCC-MODE mode=0 rayon=122880.0000 maxtris=460
# Un rayon a zero, c'est le correctif desarme — et c'est exactement ce que fait le bit 4 de
# `*gjcc-mode*`. C'est la seule chose que cette garde juge, et elle la juge sur le nombre.
#
# CE QU'ON NE GARDE PAS : les lignes GJCC-THRU. Elles sont ecrites par plusieurs `format`
# successifs sans retour a la ligne, donc le journal peut les couper ; une garde batie dessus
# serait rouge pour une raison de mise en forme. Aucun rapport n'est lu.
ACQ_NAME=crate-collision
. "$(dirname "$0")/_lib.sh"

LOG=$(acq_x86_log play 85 OG_F1_WARP=1 OG_F1_WARP_DELAY=600) \
  || acq_unprovable "pas de course x86 mesurable (gk absent, pas d'affichage, ou un build ecrit en ce moment)"
acq_norm "$LOG" > "$LOG.n"
MODE=$(grep -a 'GJCC-MODE ' "$LOG.n" | tail -1)
SPAWN=$(grep -ac 'F1-SPAWN ' "$LOG.n" || true)
rm -f "$LOG.n"

[ -n "$MODE" ] || acq_unprovable "aucune ligne GJCC-MODE en 85 s (warp F1 : $SPAWN) : le tick de naissance n'a pas publie son rayon"
RAYON=$(printf '%s' "$MODE" | grep -oE 'rayon=[0-9.]+' | head -1 | cut -d= -f2)
[ -n "$RAYON" ] || acq_unprovable "la ligne GJCC-MODE ne porte pas de rayon : $MODE"
awk -v r="$RAYON" 'BEGIN{exit (r+0 > 0) ? 0 : 1}' \
  || acq_broken "la naissance par portee est desarmee (rayon=$RAYON) : un acteur hors champ n'a plus de collision. $MODE"
acq_ok "naissance par portee active, rayon=$RAYON — $MODE"
