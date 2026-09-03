#!/usr/bin/env bash
# physics_x86_probe0.sh — is the x86 leg viable AT ALL for this phase?
# One boot, one warp into Sandover (Keira at the Zoomer + Jak), physics on at quality 2, and a
# straight read of what the SPEC-17 instrument prints. No gates, no report: this answers one
# question — do [HD-PHYS7] window lines appear on x86 with per-chain values that VARY?
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-secondary-motion; mkdir -p "$OUT"
LOG="$OUT/.x86_probe0.log"; : > "$LOG"
INI=build/game/OpenGOAL/jak1/settings/settings.ini
WATCH="${WATCH:-150}"
WARP="${WARP:-village1-hut}"
WPOS="${WPOS:--130.5 34.5 202.4}"

set_ini(){ if grep -q "^$1 " "$INI"; then sed -i "s|^$1 .*|$1 = $2|" "$INI"; else
  sed -i "/^recharged-enhanced-models? = /a $1 = $2" "$INI"; fi; }

cp "$INI" "$OUT/.settings.ini.pre-probe0"
set_ini 'recharged-enhanced-models?' '#t'
set_ini 'physics?' '#t'
set_ini 'physics-quality' '2'

mkdir -p out/jak1/obj
for c in jak-hd dax-hd keira-hd samos-hd jak2-hd jak3-hd daxp-hd keira3-hd ysamos-hd jakm-hd; do
  cp -f "recharged_assets/hd_anim/$c-ag.go" out/jak1/obj/ 2>/dev/null || echo "WARN: no $c-ag.go"
done

echo "launching gk (warp=$WARP watch=${WATCH}s)"
env OG_LEVEL_WARP="$WARP" OG_LEVEL_WARP_POS="$WPOS" \
  stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
  -iso-data "$ISO" -- -boot -debug-mem > "$LOG" 2>&1 &
PID=$!
cleanup(){ kill "$PID" 2>/dev/null; wait 2>/dev/null; cp "$OUT/.settings.ini.pre-probe0" "$INI"; }
trap cleanup EXIT

booted=0
for i in $(seq 1 180); do
  kill -0 "$PID" 2>/dev/null || { echo "gk EXITED during boot"; tail -30 "$LOG"; exit 1; }
  grep -aqE "link finish: (default-menu|logo)" "$LOG" && { booted=1; break; }
  sleep 1
done
[ "$booted" = 1 ] || { echo "boot timeout"; tail -30 "$LOG"; exit 1; }
echo "booted after ${i}s"

w=0
for i in $(seq 1 150); do
  kill -0 "$PID" 2>/dev/null || { echo "gk died pre-warp"; tail -30 "$LOG"; exit 1; }
  grep -aq 'LEVEL-WARP-SPAWN' "$LOG" && { w=1; break; }
  sleep 1
done
[ "$w" = 1 ] && echo "warp landed after ${i}s" || echo "WARP NEVER LANDED"

sleep "$WATCH"
ALIVE=no; kill -0 "$PID" 2>/dev/null && ALIVE=yes
echo "=================================================================="
echo "alive=$ALIVE"
for t in '\[HD-PHYS\] init ag=' '\[HD-PHYS\].*window: chains=' '\[HD-PHYS7\]' '\[HD-PHYS6\]' '\[HD-PHYS-RIDER\]' 'params loaded'; do
  printf '%-34s %s\n' "$t" "$(grep -ac "$t" "$LOG" || true)"
done
echo "---- init lines ----"; grep -a '\[HD-PHYS\] init ag=' "$LOG" | sort -u | head -20
echo "---- last HD-PHYS7 per art-group ----"
grep -a '\[HD-PHYS7\]' "$LOG" | awk '{print $2}' | sort -u | head -30
echo "---- one keira HD-PHYS7 ----"; grep -a '\[HD-PHYS7\].*keira' "$LOG" | tail -1 | cut -c1-1200
echo "---- one jak HD-PHYS7 ----";   grep -a '\[HD-PHYS7\].*jak-hd' "$LOG" | tail -1 | cut -c1-1200
echo "---- crash markers ----"; grep -acE 'SIGSEGV|SIGILL|Segmentation|Assertion' "$LOG" || true
echo "log: $LOG ($(wc -l < "$LOG") lines)"
