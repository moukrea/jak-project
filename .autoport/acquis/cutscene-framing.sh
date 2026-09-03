#!/usr/bin/env bash
# acquis/cutscene-framing.sh — LE CADRAGE N'ETIRE PAS L'IMAGE.
#
# CE QU'ON GARDE : le blit final etire la TOTALITE de la source sur la TOTALITE de la region
# de dessin avec un quad plein ecran. Si les deux formats different, l'image est etiree de
# facon ANISOTROPE — c'est le seul endroit de la chaine ou « on etire en largeur » peut se
# produire APRES le frustum. Le commentaire du moteur (OpenGLRenderer.cpp, bloc CINEVP) l'ecrit
# lui-meme : quand le defaut est absent, srcasp == drawasp.
#
# CE QU'ON NE GARDE PAS : l'offset. Une region decalee (`draw=640x480+-160+-120`) est normale
# pendant un redimensionnement de fenetre — quatre lignes du journal de Gcine-vertical-frame le
# montrent. Une garde qui l'interdirait serait rouge sans defaut.
#
# INSTRUMENT : `CINEVP draw=WxH+X+Y src=WxH srcasp=A drawasp=B`, emis SUR CHANGEMENT, sans
# aucune condition, des la premiere image. Aucun rapport n'est lu.
ACQ_NAME=cutscene-framing
. "$(dirname "$0")/_lib.sh"

LOG=$(acq_x86_log boot 50) || acq_unprovable "pas de course x86 mesurable (gk absent, pas d'affichage, ou un build ecrit en ce moment)"
N=$(acq_norm "$LOG" > "$LOG.n"; grep -ac 'CINEVP draw=' "$LOG.n" || true)
[ "${N:-0}" -gt 0 ] || { rm -f "$LOG.n"; acq_unprovable "aucune ligne CINEVP en 50 s : le rendu n'a jamais presente d'image"; }

MAUVAIS=$(grep -ao 'CINEVP draw=[^ ]* src=[^ ]* srcasp=[0-9.]* drawasp=[0-9.]*' "$LOG.n" \
  | awk '{s=""; d=""; for(i=1;i<=NF;i++){if($i~/^srcasp=/){s=substr($i,8)} if($i~/^drawasp=/){d=substr($i,9)}}
         if(s+0>0 && d+0>0){r=(s-d)/s; if(r<0)r=-r; if(r>0.01) print}}' | head -3)
rm -f "$LOG.n"
[ -z "$MAUVAIS" ] || acq_broken "le blit final etire l'image (srcasp != drawasp a plus de 1 %) :
$MAUVAIS"
acq_ok "$N changements de cadrage, tous a srcasp == drawasp (a 1 % pres)"
