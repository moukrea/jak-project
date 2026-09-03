#!/usr/bin/env bash
# acquis/daxter-eyes.sh — LE REGLAGE DES YEUX EST ENCORE CHARGE.
#
# CE QU'ON GARDE. Les tailles d'iris et de pupille validees par l'owner ne vivent pas dans le
# code : elles sont lues dans le bloc `[eyescale]` de `recharged_assets/physics_chains.txt` (un
# fichier externe peut le surcharger). Quand ce fichier n'est plus trouve, le moteur le dit et
# repart sur les valeurs compilees :
#     [eyescale] PARAMSRC=none path=... (compiled defaults)
# C'est exactement le mode d'echec qui a coute la police Urbanist : l'acquis voyageait dans un
# fichier optionnel, il a disparu, et rien ne l'a vu. Ici le moteur PUBLIE la resolution a
# chaque demarrage, y compris quand elle vaut « rien trouve » — donc on peut la juger.
#
# CE QU'ON NE GARDE PAS : le nombre de dessins par slot. Il depend de ce que la camera cadre.
# Publie comme information. Aucun rapport n'est lu.
ACQ_NAME=daxter-eyes
. "$(dirname "$0")/_lib.sh"

LOG=$(acq_x86_log play 85 OG_F1_WARP=1 OG_F1_WARP_DELAY=600) \
  || acq_unprovable "pas de course x86 mesurable (gk absent, pas d'affichage, ou un build ecrit en ce moment)"
acq_norm "$LOG" > "$LOG.n"
SRC=$(grep -a '\[eyescale\] PARAMSRC=' "$LOG.n" | tail -1)
SANSREST=$(grep -a 'is HD-covered but has no measured rest' "$LOG.n" | head -1)
DRAWS=$(grep -aoE '\[eyescale\] slot=[0-9]+ kind=iris draws=[0-9]+' "$LOG.n" | grep -oE 'draws=[0-9]+' | cut -d= -f2 | sort -n | tail -1)
rm -f "$LOG.n"

[ -n "$SRC" ] || acq_unprovable "aucune ligne [eyescale] en 85 s : aucun oeil n'a ete dessine, il n'y a rien a juger"
case "$SRC" in
  *PARAMSRC=none*)
    acq_broken "le fichier de reglage des yeux n'a pas ete trouve, le moteur est reparti sur les valeurs compilees : $SRC" ;;
esac
[ -z "$SANSREST" ] || acq_broken "un slot couvert en HD n'a plus de repos mesure : $SANSREST"
acq_ok "reglage charge — $SRC ; draws iris max=${DRAWS:-0} (information, non juge)"
