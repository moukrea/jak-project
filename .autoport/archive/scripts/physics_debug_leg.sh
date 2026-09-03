#!/usr/bin/env bash
# physics_debug_leg.sh — one-off single-leg [HD-PHYS] harvest (debug instrumentation runs).
# Usage: QUAL=2 WATCH=130 bash .autoport/physics_debug_leg.sh
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/tmp; mkdir -p "$OUT"
WATCH="${WATCH:-130}"; QUAL="${QUAL:-2}"
INI=build/game/OpenGOAL/jak1/settings/settings.ini
[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/jak-hd-physics.gc ] || { echo "FAIL: GAME.CGO stale"; exit 1; }
mkdir -p out/jak1/obj
for c in jak-hd dax-hd keira-hd samos-hd jak2-hd jak3-hd daxp-hd keira3-hd ysamos-hd jakm-hd; do
  cp -f "recharged_assets/hd_anim/$c-ag.go" out/jak1/obj/ || exit 1
done
cp "$INI" "$OUT/.dbg.ini.bak"
set_ini(){ if grep -q "^$1 " "$INI"; then sed -i "s|^$1 .*|$1 = $2|" "$INI"; else sed -i "/^recharged-enhanced-models? = /a $1 = $2" "$INI"; fi }
set_ini 'recharged-enhanced-models?' '#t'
set_ini 'physics?' '#t'; set_ini 'physics-quality' "$QUAL"
set_ini 'hd-look-jak' 1; set_ini 'hd-look-daxter' 1; set_ini 'hd-look-keira' 1; set_ini 'hd-look-samos' 1
GKLOG="$OUT/dbg_gk.log"; : > "$GKLOG"
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
trap 'kill $GKPID 2>/dev/null; cp "$OUT/.dbg.ini.bak" "$INI"' EXIT
for i in $(seq 1 150); do
  kill -0 "$GKPID" 2>/dev/null || { echo "gk exited during boot"; tail -20 "$GKLOG"; exit 1; }
  grep -aqE "link finish: (default-menu|logo)" "$GKLOG" && break; sleep 1
done
echo "booted; watching ${WATCH}s"
sleep "$WATCH"
kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true
grep -a '\[HD-PHYS\]' "$GKLOG" | tail -40
