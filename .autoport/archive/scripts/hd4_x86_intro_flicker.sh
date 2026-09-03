#!/usr/bin/env bash
# hd4_x86_intro_flicker.sh — CYCLE-3 P1 proof leg (x86-first, metrics not eyeballs):
# run the REAL intro cutscene (OG_ECHO_INTRO=1, same kmachine echo-intro path the device
# prop uses) with the Merc2 flicker detector live, and require ZERO blackout/gap events.
#
# Detector semantics (Merc2.cpp, cycle 3):
#   BLACKOUT = a covered driver's stock packet was suppressed although its companion had not
#              submitted for >1.25 frames -> the actor was invisible that frame (the owner's
#              cutscene NPC flicker, frame-exact).
#   GAP      = a companion re-armed after missing 1.5-2 frames while its TTL was still alive
#              (the brief miss window that produces a blink; longer misses expire the TTL and
#              are the designed hidden-driver drain, not counted).
#   heartbeat "[hd-flicker] calls=N blackouts=B gaps=G expiries=E" every ~4s; expiries are
#   normal (hidden-driver drains), NOT gated.
# PASS bar: intro scene reached, all 4 HD models submitted, last heartbeat blackouts=0 gaps=0,
# zero BLACKOUT/GAP event lines, no crash, gk alive.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-hd-models4; mkdir -p "$OUT"
R="$OUT/x86_flicker_cycle3.txt"; : > "$R"
GKLOG="$OUT/.flicker_gk.log"; : > "$GKLOG"
WATCH="${WATCH:-150}"
say(){ echo "$*" | tee -a "$R"; }
say "===== cycle-3 x86 intro-cutscene flicker leg — $(date -Is) ====="

[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/jak-hd.gc ] || { say "FAIL: GAME.CGO stale vs jak-hd.gc — run (mi) first"; exit 1; }
[ -f out/jak1/fr3/enhanced/GAME.fr3 ] || { say "FAIL: enhanced GAME.fr3 missing — run build_enhanced_models.sh"; exit 1; }
mkdir -p out/jak1/obj
for c in jak dax keira samos; do
  cp -f "recharged_assets/hd_anim/$c-hd-ag.go" out/jak1/obj/ || { say "FAIL: stage $c-hd-ag.go"; exit 1; }
done
say "staged 4 HD art-groups into out/jak1/obj"

OG_ECHO_INTRO=1 "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
cleanup(){ kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true; }
trap cleanup EXIT
booted=0
for i in $(seq 1 150); do
  kill -0 "$GKPID" 2>/dev/null || { say "FAIL: gk exited during boot"; tail -25 "$GKLOG" >> "$R"; exit 1; }
  grep -aqE "link finish: (default-menu|logo)" "$GKLOG" && { booted=1; break; }
  sleep 1
done
[ "$booted" = 1 ] || { say "FAIL: boot timeout"; tail -25 "$GKLOG" >> "$R"; exit 1; }
say "booted — waiting for the echo-intro warp + scene"
WARP=0
for i in $(seq 1 120); do
  kill -0 "$GKPID" 2>/dev/null || { say "FAIL: gk died pre-warp"; tail -25 "$GKLOG" >> "$R"; exit 1; }
  grep -aq 'ECHO-INTRO-WARP' "$GKLOG" && { WARP=1; break; }
  sleep 1
done
[ "$WARP" = 1 ] || { say "FAIL: echo-intro warp never fired"; tail -25 "$GKLOG" >> "$R"; exit 1; }
say "warp fired — watching the cutscene for ${WATCH}s with the flicker detector"
sleep "$WATCH"

ALIVE=no; kill -0 "$GKPID" 2>/dev/null && ALIVE=yes
FRSEL=$(grep -a -m1 'HD-MODELS fr3-select GAME' "$GKLOG" | tr -d '\r')
SUBM=$(grep -a 'SUBMITTED' "$GKLOG" | grep -oE "name='[a-z]+-hd-lod0' found=1" | sort -u | wc -l)
SCENE=$(grep -ac 'JAK-HD-TGT' "$GKLOG" || true)
HB_LAST=$(grep -a '\[hd-flicker\] calls=' "$GKLOG" | tail -1 | tr -d '\r')
HB_COUNT=$(grep -ac '\[hd-flicker\] calls=' "$GKLOG" || true)
EV_BLACK=$(grep -ac '\[hd-flicker\] BLACKOUT' "$GKLOG" || true)
EV_GAP=$(grep -ac '\[hd-flicker\] GAP' "$GKLOG" || true)
CRASH=$(grep -acE 'SIGSEGV|SIGILL|Segmentation|Assertion' "$GKLOG" || true)
say "gk alive: $ALIVE   crash markers: $CRASH"
say "fr3-select: ${FRSEL:-NONE}"
say "distinct HD models SUBMITTED found=1: $SUBM / 4"
say "scene evidence ([JAK-HD-TGT] lines): $SCENE"
say "flicker heartbeat count: $HB_COUNT   last: ${HB_LAST:-NONE}"
say "flicker BLACKOUT events: $EV_BLACK   GAP events: $EV_GAP"

PASS=1
[ "$ALIVE" = yes ] || PASS=0
[ "$CRASH" = 0 ] || PASS=0
echo "$FRSEL" | grep -q 'ENHANCED' || { say "FAIL: enhanced GAME.fr3 not selected"; PASS=0; }
[ "$SUBM" -ge 4 ] || { say "FAIL: expected 4 HD models submitting, saw $SUBM"; PASS=0; }
[ "$HB_COUNT" -ge 1 ] || { say "FAIL: no detector heartbeat — detector not running?"; PASS=0; }
[ "$EV_BLACK" = 0 ] || { say "FAIL: $EV_BLACK blackout events (the flicker)"; PASS=0; }
[ "$EV_GAP" = 0 ] || { say "FAIL: $EV_GAP gap events (blink-class misses)"; PASS=0; }
if echo "$HB_LAST" | grep -qE 'blackouts=0 gaps=0'; then
  say "last heartbeat clean (blackouts=0 gaps=0)"
else
  say "FAIL: last heartbeat not clean: ${HB_LAST:-NONE}"; PASS=0
fi
if [ "$PASS" = 1 ]; then
  say "[flicker-leg PASS] zero blackout/gap events across the intro cutscene"
  exit 0
else
  say "[flicker-leg FAIL]"
  exit 1
fi
