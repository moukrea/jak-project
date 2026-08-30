#!/usr/bin/env bash
# Gfixed-tick-interpolation — UNE course x86 : meme demo de manette rejouee, a un
# framerate cible donne, avec l'horloge a pas fixe ARMEE ou DESARMEE (ablation sur LE
# MEME BINAIRE).
#
# Usage : gft_x86_leg.sh <fps> <on|off> <det|realtime> <etiquette>
#
# Ce qui sort :
#   $OUT/<etiquette>.trace  — trace pad_replay (lignes « CAM frame= »), une par TICK de
#                             logique : position de Jak => trajectoire de saut ;
#   $OUT/<etiquette>.log    — journal gk, dont les lignes « GFT n= » : une par image
#                             DESSINEE (cadence reelle, k, alpha, lacet camera).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
FPS="$1"; MODE="$2"; PACING="$3"; TAG="$4"
GK=build/game/gk; ISO=out/jak1/iso
OUT=.autoport/reports/Gfixed-tick-interpolation; mkdir -p "$OUT"
INPUTS="${INPUTS:-/tmp/gft_jump.inputs}"
LAST_TICK="${LAST_TICK:-1079}"
TIMEOUT="${TIMEOUT:-420}"
SETTINGS="build/game/OpenGOAL/jak1/settings/settings.ini"
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.2UGBV3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

[ -f "$SETTINGS" ] || { echo "FAIL: pas de settings.ini a $SETTINGS"; exit 1; }
# PIEGE PAYE PAR UNE PHASE PRECEDENTE : les deux lecteurs (Loader.cpp et le GOAL
# pckernel) JETTENT un fichier de version perimee, et le reglage n'est alors jamais
# applique — deux legs « A/B » identiques sans le moindre message.
sed -i "s/^version = .*/version = #x1000B00000000/" "$SETTINGS"
sed -i "s/^fps = .*/fps = $FPS/" "$SETTINGS"
sed -i "s/^vsync = .*/vsync = #f/" "$SETTINGS"
grep -qE "^fps = $FPS\$" "$SETTINGS" || { echo "FAIL: fps non applique dans settings.ini"; exit 1; }

TRACE="$OUT/$TAG.trace"; LOG="$OUT/$TAG.log"; : > "$TRACE"; : > "$LOG"
FT=1; [ "$MODE" = off ] && FT=0
RT=()
[ "$PACING" = realtime ] && RT=(OG_PAD_REPLAY_REALTIME=1)

env OG_F1_WARP=1 OG_FIXED_TICK="$FT" OG_FIXED_TICK_PROBE=1 \
    OG_PAD_REPLAY_REPLAY="$INPUTS" OG_PAD_REPLAY_TRACE="$TRACE" "${RT[@]}" \
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

NC=$(grep -ac '^CAM frame=' "$TRACE" 2>/dev/null || echo 0)
NG=$(grep -ac '^GFT n=' "$LOG" 2>/dev/null || echo 0)
echo "  [$TAG] fps=$FPS fixedtick=$MODE pacing=$PACING duree=$((SECONDS-t0))s complet=$done cam=$NC gft=$NG"
[ "$done" = 1 ] || exit 2
exit 0
