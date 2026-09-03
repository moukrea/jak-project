#!/usr/bin/env bash
# Gfixed-tick-anim-interp — UNE course x86 de mesure de GIGUE D'ANIMATION.
#
# Usage : ajp_x86_leg.sh <fps> <on|off> <etiquette>
#           <fps>  cadence d'affichage imposee (settings.ini + limiteur x86)
#           on|off ETAT DE L'INTERPOLATION DE POSE (OG_ANIM_INTERP). C'est ca,
#                  l'ablation : l'horloge a pas fixe est ARMEE DES DEUX COTES, donc
#                  `time-adjust-ratio` vaut 1.0 des deux cotes et l'ecart image-a-image
#                  est compare a UNITE EGALE. Comparer arme/desarme aurait compare deux
#                  tailles de pas, pas la gigue.
#
# Ce qui sort dans $OUT/<etiquette>.log :
#   `AJP  ...` une ligne par image DESSINEE : alpha, skip, compteur de canaux retimes,
#              et la position MONDE de la racine et de trois joints de Jak ;
#   `GFT  ...` une ligne par image DESSINEE : armed, skip, k, alpha, dt reel.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
FPS="$1"; ANIM="$2"; TAG="$3"
GK=build/game/gk; ISO=out/jak1/iso
OUT=.autoport/reports/Gfixed-tick-anim-interp; mkdir -p "$OUT"
INPUTS="${INPUTS:-/tmp/ajp_stand.inputs}"
LAST_TICK="${LAST_TICK:-899}"
TIMEOUT="${TIMEOUT:-420}"
SETTINGS="build/game/OpenGOAL/jak1/settings/settings.ini"
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.2UGBV3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

[ -f "$SETTINGS" ] || { echo "FAIL: pas de settings.ini a $SETTINGS"; exit 1; }
# Les deux lecteurs (Loader.cpp et le pckernel GOAL) JETTENT un fichier de version
# perimee, et le reglage n'est alors jamais applique -- deux legs A/B identiques sans
# le moindre message. Piege paye par une phase precedente.
sed -i "s/^version = .*/version = #x1000B00000000/" "$SETTINGS"
sed -i "s/^fps = .*/fps = $FPS/" "$SETTINGS"
sed -i "s/^vsync = .*/vsync = #f/" "$SETTINGS"
# COUT D'IMAGE ABAISSE, ET C'EST DECLARE : sur Geyser Rock aux reglages livres la
# machine est bornee par le CONTENU a ~21 images/s, donc le limiteur ne peut pas rendre
# 120. Aucun de ces reglages ne touche le chemin sous test (num-func-* / joint.gc).
sed -i "s/^game-size = .*/game-size = 640 480/" "$SETTINGS"
sed -i "s/^render-scale = .*/render-scale = 25.0000/" "$SETTINGS"
sed -i "s/^min-render-scale = .*/min-render-scale = 25.0000/" "$SETTINGS"
sed -i "s/^recharged-grass? = .*/recharged-grass? = #f/" "$SETTINGS"
sed -i "s/^pbr-materials? = .*/pbr-materials? = #f/" "$SETTINGS"
sed -i "s/^recharged-enhanced-models? = .*/recharged-enhanced-models? = #f/" "$SETTINGS"
sed -i "s/^physics-quality = .*/physics-quality = 0/" "$SETTINGS"
grep -qE "^fps = $FPS\$" "$SETTINGS" || { echo "FAIL: fps non applique dans settings.ini"; exit 1; }

TRACE="$OUT/$TAG.trace"; LOG="$OUT/$TAG.log"; : > "$TRACE"; : > "$LOG"
AI=1; [ "$ANIM" = off ] && AI=0

# PACING REEL, obligatoire : en rejeu DETERMINISTE l'horloge rend 1 tick par image et
# publie alpha=1e6 en permanence (game/graphics/fixed_tick.cpp) -- il n'y aurait alors
# rien a interpoler et l'ablation serait vide des deux cotes.
env OG_F1_WARP=1 OG_FIXED_TICK=1 OG_FIXED_TICK_PROBE=1 \
    OG_ANIM_INTERP="$AI" OG_ANIM_PROBE=1 \
    OG_PAD_REPLAY_REPLAY="$INPUTS" OG_PAD_REPLAY_TRACE="$TRACE" OG_PAD_REPLAY_REALTIME=1 \
    stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
      -iso-data "$ISO" -- -boot -debug-mem > "$LOG" 2>&1 &
GKPID=$!

t0=$SECONDS spawned=0 done=0
while [ $((SECONDS - t0)) -lt "$TIMEOUT" ]; do
  kill -0 "$GKPID" 2>/dev/null || { echo "FAIL: gk mort (leg $TAG)"; break; }
  [ "$spawned" = 0 ] && grep -aq 'F1-SPAWN' "$LOG" && { spawned=1; echo "  [$TAG] F1-SPAWN a t+$((SECONDS-t0))s"; }
  if [ "$spawned" = 1 ] && grep -aq "^CAM frame=$LAST_TICK " "$TRACE"; then done=1; break; fi
  sleep 2
done
kill -TERM "$GKPID" 2>/dev/null; sleep 1; kill -KILL "$GKPID" 2>/dev/null; wait "$GKPID" 2>/dev/null

NA=$(grep -ac '^AJP n=' "$LOG" 2>/dev/null || echo 0)
NG=$(grep -ac '^GFT n=' "$LOG" 2>/dev/null || echo 0)
NC=$(grep -ac '^CAM frame=' "$TRACE" 2>/dev/null || echo 0)
echo "  [$TAG] fps=$FPS animinterp=$ANIM duree=$((SECONDS-t0))s complet=$done ajp=$NA gft=$NG cam=$NC"
[ "$done" = 1 ] || exit 2
exit 0
