#!/usr/bin/env bash
# glpx_x86_repro.sh — desktop x86 repro of the owner's phantom X shadow lines (Glightprobes owner-repro round).
# Usage: glpx_x86_repro.sh <tag> <"x y z"> <tod_hour> [extra env as KEY=VAL ...]
# Captures frames to build/game/OpenGOAL/jak1/screenshots/ then copies to /tmp/glpx/<tag>/.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
TAG=${1:?tag}; POS=${2:?pos}; HOUR=${3:?hour}; shift 3
OUT=/tmp/glpx/$TAG
mkdir -p "$OUT"
SHOTS=build/game/OpenGOAL/jak1/screenshots
rm -f "$SHOTS"/autoport_f*.png
LOG=$OUT/gk.log

env_extra=("$@")
DISPLAY=:0 XAUTHORITY=$(ls /run/user/1000/.mutter-Xwaylandauth* | head -1) \
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
OG_LEVEL_WARP=village1-hut OG_LEVEL_WARP_POS="$POS" \
OG_TOD_HOUR=$HOUR \
OG_RT_LIGHT=1 OG_PBR_SHADOWMAP=1 \
AUTOPORT_SHOT_EVERY=120 AUTOPORT_SHOT_START=900 AUTOPORT_SHOT_STOP=2100 \
AUTOPORT_SHOT_W=1920 AUTOPORT_SHOT_H=1080 \
"${env_extra[@]}" \
timeout 120 stdbuf -oL -eL ./build/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi \
  -iso-data out/jak1/iso -- -boot -debug-mem > "$LOG" 2>&1
RC=$?
grep -m1 "LEVEL-WARP-SPAWN" "$LOG" || echo "[glpx] WARN: no LEVEL-WARP-SPAWN in log"
cp "$SHOTS"/autoport_f*.png "$OUT"/ 2>/dev/null
N=$(ls "$OUT"/autoport_f*.png 2>/dev/null | wc -l)
echo "[glpx] $TAG rc=$RC frames=$N -> $OUT"
