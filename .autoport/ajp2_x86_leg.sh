#!/usr/bin/env bash
# Gfixed-tick-anim-interp-2 — UNE course x86 de mesure de GIGUE D'ANIMATION.
#
# Usage : ajp2_x86_leg.sh <fps> <jitter_pct> <on|off> <etiquette>
#   <fps>         cadence d'affichage imposee (settings.ini + limiteur x86)
#   <jitter_pct>  amplitude de la VARIATION DE DUREE D'IMAGE, en % (0 = cadence
#                 parfaitement verrouillee). C'est le stimulus qui manquait au cycle 1 :
#                 a 30 images/s parfaitement verrouillees, l'horloge se verrouille aussi
#                 et il n'y a RIEN a interpoler — les deux bras publient la meme ligne.
#                 La suite de durees est deterministe (generateur indexe sur le numero
#                 d'image), donc IDENTIQUE dans les deux bras de l'ablation.
#   <on|off>      ETAT DE L'INTERPOLATION DE POSE (OG_ANIM_INTERP). L'horloge a pas fixe
#                 est ARMEE DES DEUX COTES : `time-adjust-ratio` vaut 1.0 des deux cotes,
#                 donc l'ecart image-a-image est compare a UNITE EGALE.
#
# DUREE : on attend F1-SPAWN puis on mesure RUN_SECS secondes de temps REEL. Le cycle 1
# attendait un numero de tick, ce qui rendait les cadences basses arbitrairement longues
# (deux legs a 30 images/s sont sorties sur le plafond de temps, `complet=0`, et leurs
# maximums n'etaient donc plus comparables — c'est ecrit dans son propre rapport).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
FPS="$1"; JIT="$2"; ANIM="$3"; TAG="$4"; TL="${5:-1}"
GK=build/game/gk; ISO=out/jak1/iso
OUT=.autoport/reports/Gfixed-tick-anim-interp-2; mkdir -p "$OUT"
INPUTS="${INPUTS:-/tmp/ajp2_idle.inputs}"
RUN_SECS="${RUN_SECS:-40}"
SPAWN_TIMEOUT="${SPAWN_TIMEOUT:-420}"
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
# COUT D'IMAGE ABAISSE, ET C'EST DECLARE : aux reglages livres la machine est bornee par
# le CONTENU a ~21 images/s sur Geyser Rock, donc le limiteur ne pourrait tenir ni 120 ni
# meme une cadence basse REGULIERE. Aucun de ces reglages ne touche le chemin sous test.
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
JITENV=()
[ "$JIT" != 0 ] && JITENV=(OG_FRAME_JITTER_PCT="$JIT")

# PACING REEL, obligatoire : en rejeu DETERMINISTE l'horloge rend 1 tick par image et
# publie alpha=1e6 en permanence -- il n'y aurait rien a interpoler des deux cotes.
env OG_F1_WARP=1 OG_FIXED_TICK=1 OG_FIXED_TICK_PROBE=1 \
    OG_ANIM_INTERP="$AI" OG_ANIM_PROBE=1 OG_TICK_LOCK="$TL" "${JITENV[@]}" \
    OG_PAD_REPLAY_REPLAY="$INPUTS" OG_PAD_REPLAY_TRACE="$TRACE" OG_PAD_REPLAY_REALTIME=1 \
    stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
      -iso-data "$ISO" -- -boot -debug-mem > "$LOG" 2>&1 &
GKPID=$!

t0=$SECONDS spawned=0
while [ $((SECONDS - t0)) -lt "$SPAWN_TIMEOUT" ]; do
  kill -0 "$GKPID" 2>/dev/null || { echo "FAIL: gk mort avant F1-SPAWN (leg $TAG)"; break; }
  grep -aq 'F1-SPAWN' "$LOG" && { spawned=1; echo "  [$TAG] F1-SPAWN a t+$((SECONDS-t0))s"; break; }
  sleep 2
done
if [ "$spawned" = 1 ]; then
  ts=$SECONDS
  while [ $((SECONDS - ts)) -lt "$RUN_SECS" ]; do
    kill -0 "$GKPID" 2>/dev/null || { echo "FAIL: gk mort pendant la mesure (leg $TAG)"; spawned=2; break; }
    sleep 2
  done
fi
kill -TERM "$GKPID" 2>/dev/null; sleep 1; kill -KILL "$GKPID" 2>/dev/null; wait "$GKPID" 2>/dev/null

NA=$(grep -ac '^AJP n=' "$LOG" 2>/dev/null || echo 0)
NG=$(grep -ac '^GFT n=' "$LOG" 2>/dev/null || echo 0)
BAD=$(grep -acE '(=|,)-?(nan|inf)|Segmentation|Assertion|terminate called' "$LOG" 2>/dev/null || echo 0)
echo "  [$TAG] fps=$FPS gigue=$JIT% animinterp=$ANIM ticklock=$TL duree=$((SECONDS-t0))s spawn=$spawned ajp=$NA gft=$NG anomalies=$BAD"
[ "$spawned" = 1 ] || exit 2
exit 0
