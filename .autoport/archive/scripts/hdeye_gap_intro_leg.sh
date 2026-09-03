#!/usr/bin/env bash
# hdeye_gap_intro_leg.sh — Grecharged-hd-eye-scale, one leg, CODE-LEVEL ONLY.
#
# Two modes, one runner:
#   MODE=intro   the echo intro. This is the ONLY scene that can answer the phase's "check the
#                other HD characters" item: the eye-pair instrument only sees a model on frames
#                where its face is actually blerc-animated, and at village1-hut only Daxter talks.
#                Either Jak / Keira / Samos produce numbers here, or it is proven they never reach
#                the channel at all — both are answers, and neither is a guess.
#   MODE=warp    village1-hut, the scene the Daxter ceiling was measured in.
#
# It deliberately does NOT touch recharged_assets/physics_chains.txt. The shipped params ARE what
# is under test, and android/build_custom_pack.sh packages that very file, so a leg that rewrote it
# could race a pack build into shipping the feature disabled — the exact class of "the work gets
# destroyed at packaging" the owner has already been bitten by twice. Only the desktop settings.ini
# is switched (packaging is blind to it), and it is restored.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$(ls /run/user/1000/.mutter-Xwaylandauth.* 2>/dev/null | head -1)}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-hd-eye-scale; mkdir -p "$OUT"
MODE="${MODE:-intro}"
TAG="${TAG:-$MODE}"
WARP="${WARP:-village1-hut}"; WPOS="${WPOS:--130.5 34.5 202.4}"
WATCH="${WATCH:-300}"
R="$OUT/x86_eyegap_$TAG.txt"; : > "$R"
GKLOG="$OUT/.gap_$TAG.log"
SETT=build/game/OpenGOAL/jak1/settings/settings.ini
say(){ echo "$*" | tee -a "$R"; }
say "===== Grecharged-hd-eye-scale — leg '$TAG' (MODE=$MODE) — $(date -Is) ====="
say "HEAD=$(git rev-parse --short HEAD)  gk=$(stat -c %y "$GK" 2>/dev/null)"

[ -x "$GK" ] || { say "FAIL: no $GK"; exit 1; }
[ -f "$SETT" ] || { say "FAIL: no settings.ini at $SETT"; exit 1; }
mkdir -p out/jak1/obj
for c in jak dax keira samos; do
  cp -f "recharged_assets/hd_anim/$c-hd-ag.go" out/jak1/obj/ || { say "FAIL: stage $c-hd-ag.go"; exit 1; }
done

SETT_BAK="$OUT/.$TAG.settings.ini.bak"; cp -f "$SETT" "$SETT_BAK"
trap 'kill "${GKPID:-0}" 2>/dev/null; cp -f "$SETT_BAK" "$SETT" 2>/dev/null' EXIT
grep -q '^recharged-enhanced-models? = #[tf]$' "$SETT" || { say "FAIL: enhanced-models key not found"; exit 1; }
sed -i 's/^recharged-enhanced-models? = #[tf]$/recharged-enhanced-models? = #t/' "$SETT"
say "[$TAG] shipped params: $(grep -E '^on=1 gainup=' recharged_assets/physics_chains.txt)"

: > "$GKLOG"
ENVV=(OG_EYEGAP_TRACE=1)
if [ "$MODE" = intro ]; then
  ENVV+=(OG_ECHO_INTRO=1)
  say "[$TAG] enhanced=#t, OG_ECHO_INTRO=1, trace=1, watch=${WATCH}s"
else
  ENVV+=(OG_LEVEL_WARP="$WARP" OG_LEVEL_WARP_POS="$WPOS")
  say "[$TAG] enhanced=#t, warp=$WARP, trace=1, watch=${WATCH}s"
fi
env "${ENVV[@]}" "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
booted=0
for i in $(seq 1 240); do
  kill -0 "$GKPID" 2>/dev/null || { say "[$TAG] FAIL: gk exited during boot"; tail -25 "$GKLOG" >> "$R"; exit 1; }
  grep -aqE "link finish: (default-menu|logo)" "$GKLOG" && { booted=1; break; }
  sleep 1
done
[ "$booted" = 1 ] || { say "[$TAG] FAIL: boot timeout"; tail -25 "$GKLOG" >> "$R"; exit 1; }
if [ "$MODE" != intro ]; then
  w=0
  for i in $(seq 1 180); do
    kill -0 "$GKPID" 2>/dev/null || { say "[$TAG] FAIL: gk died pre-warp"; tail -25 "$GKLOG" >> "$R"; exit 1; }
    grep -aq 'LEVEL-WARP-SPAWN' "$GKLOG" && { w=1; break; }
    sleep 1
  done
  [ "$w" = 1 ] || { say "[$TAG] FAIL: level warp never fired"; tail -25 "$GKLOG" >> "$R"; exit 1; }
fi
say "[$TAG] running; watching ${WATCH}s"
t=0
while [ "$t" -lt "$WATCH" ]; do
  kill -0 "$GKPID" 2>/dev/null || { say "[$TAG] gk exited at ${t}s"; break; }
  sleep 5; t=$((t+5))
done
kill "$GKPID" 2>/dev/null; wait "$GKPID" 2>/dev/null

say "[$TAG] --- every model that reached the eye-pair instrument ---"
grep -a '\[eyegap\] geom' "$GKLOG" | sort -u | while read -r l; do say "  ${l#*\[eyegap\] }"; done
say "[$TAG] --- heartbeats (only models rendered >=600 blerc calls get one) ---"
grep -a '\[eyegap\] model=' "$GKLOG" | awk '{for(i=1;i<=NF;i++) if($i ~ /^model=/) m=$i; L[m]=$0} END{for(k in L) print L[k]}' \
  | sort | while read -r l; do say "  ${l#*\[eyegap\] }"; done
say "[$TAG] --- per-frame summary (catches the short appearances a heartbeat cannot print) ---"
python3 .autoport/hdeye_gap_summary.py "$GKLOG" 2>&1 | sed '1d' >> "$R"
say "[$TAG] eyescale PARAMSRC: $(grep -a '\[eyescale\] PARAMSRC=' "$GKLOG" | tail -1 | sed 's/.*\[eyescale\] //')"
cp -f "$SETT_BAK" "$SETT"
say "settings restored: $(cmp -s "$SETT" "$SETT_BAK" && echo yes || echo NO)"
say "[eyegap leg '$TAG' COMPLETE]"
exit 0
