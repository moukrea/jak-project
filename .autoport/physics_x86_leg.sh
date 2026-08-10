#!/usr/bin/env bash
# physics_x86_leg.sh — the DEVICE-ABSENT evidence leg for Grecharged-secondary-motion.
#
# The Redmi is unplugged and the owner authorised a desktop fallback ("au pire teste sur un build PC
# a defaut"). This runs the same measurements the device leg runs, on the same GOAL code, against a
# real x86 build — so what it grades is everything PLATFORM-INDEPENDENT: the solver, the
# written-joint instrument, collision against the real skinned surface, the family classification,
# and the C20 anti-synthesis property. It does NOT prove arm64 codegen, device performance, or any
# device-only path (the external-override asset route, the Android input hook, thermal behaviour).
# That debt is stated in the report and the device leg still owes it.
#
# THE ONE THING THAT IS NOT A PORT: locomotion. The device drives Jak with
# `setprop debug.opengoal.cpad_inject`; that TU is Android-only. On desktop the only working route
# is a synthesized pad_replay v2 file (physics_gen_drive_inputs.py) armed with OG_PAD_REPLAY_REPLAY.
# It matters: measured here, EVERY jak-hd chain reads INERT while he stands and MOVING once he is
# driven, so an undriven leg would have reported the owner's defect on chains that do not have it.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-secondary-motion; mkdir -p "$OUT"
LOG="$OUT/x86_leg.log"; : > "$LOG"
INI=build/game/OpenGOAL/jak1/settings/settings.ini
DRIVE=/tmp/physics_drive.inputs
say(){ echo "$*" | tee -a "$LOG"; }
FAILED=0

say "===== secondary-motion x86 leg — $(date -Is) ====="
say "device absent (adb sees no eae4df44) — graded on x86, DEVICE PROOF STILL OWED"

# ---- freshness: the binary under test must postdate the source it is meant to carry -------------
for src in goal_src/jak1/pc/jak-hd-physics.gc; do
  if [ ! "$ISO/GAME.CGO" -nt "$src" ]; then
    say "FAIL(stale): $ISO/GAME.CGO is not newer than $src — a leg on a stale CGO measures the previous build"
    exit 1
  fi
done
say "freshness: GAME.CGO ($(date -r "$ISO/GAME.CGO" +%H:%M:%S)) newer than jak-hd-physics.gc ($(date -r goal_src/jak1/pc/jak-hd-physics.gc +%H:%M:%S))"

# ---- physical-artifact gate: check the ARTIFACT, never the run ----------------------------------
for s in 'HD-PHYS7' 'remprod=' 'ctmin:' 'ctz:' 'surfpen=' 'cvar:' 'cinr:'; do
  n=$(strings -a "$ISO/GAME.CGO" | grep -c -- "$s" || true)
  [ "${n:-0}" -ge 1 ] || { say "FAIL(artifact): GAME.CGO does not carry the format string '$s'"; exit 1; }
done
say "artifact gate: GAME.CGO carries the cycle-18 instrument strings (HD-PHYS7, remprod, ctmin, ctz, surfpen)"

python3 .autoport/physics_gen_drive_inputs.py "$DRIVE" 900 | tee -a "$LOG"

mkdir -p out/jak1/obj
for c in jak-hd dax-hd keira-hd samos-hd jak2-hd jak3-hd daxp-hd keira3-hd ysamos-hd jakm-hd; do
  cp -f "recharged_assets/hd_anim/$c-ag.go" out/jak1/obj/ || { say "FAIL(stage): $c-ag.go"; exit 1; }
done
say "staged 10 HD art-groups into out/jak1/obj"

cp "$INI" "$OUT/.settings.ini.pre-x86leg"
set_ini(){ if grep -q "^$1 " "$INI"; then sed -i "s|^$1 .*|$1 = $2|" "$INI"
  else sed -i "/^recharged-enhanced-models? = /a $1 = $2" "$INI"
       grep -q "^$1 = $2$" "$INI" || { say "FAIL(ini): could not insert $1"; exit 1; }; fi; }
grep -q '^version = #x' "$INI" || { say "FAIL(ini): settings.ini has no version stamp"; exit 1; }
grep -q '^recharged-master? = #f' "$INI" && { say "FAIL(ini): recharged-master? #f forces STOCK"; exit 1; }

GKPID=0
cleanup(){ [ "${GKPID:-0}" -gt 0 ] && kill "$GKPID" 2>/dev/null; wait 2>/dev/null;
           cp "$OUT/.settings.ini.pre-x86leg" "$INI"; }
trap cleanup EXIT

# run_leg <tag> <physics> <quality> <mode> <warp> <pos> <vis> <watch> <drive:1|0>
run_leg(){
  local TAG="$1" PHY="$2" QUAL="$3" MODE="$4" WARP="$5" WPOS="$6" VIS="$7" WATCH="$8" DRV="$9"
  local GKLOG="$OUT/x86_leg_$TAG.log"; : > "$GKLOG"
  local ENH='#t'; [ "$MODE" = rider ] && ENH='#f'
  set_ini 'recharged-enhanced-models?' "$ENH"
  set_ini 'physics?' "$PHY"; set_ini 'physics-quality' "$QUAL"
  set_ini 'hd-look-jak' 1; set_ini 'hd-look-daxter' 1
  set_ini 'hd-look-keira' 1; set_ini 'hd-look-samos' 1
  say ""
  say "=== LEG $TAG: physics?=$PHY quality=$QUAL mode=$MODE warp=${WARP:-none} vis=${VIS:-none} drive=$DRV watch=${WATCH}s ==="
  local envs=()
  [ -n "$WARP" ] && envs+=("OG_LEVEL_WARP=$WARP")
  [ -n "$WPOS" ] && envs+=("OG_LEVEL_WARP_POS=$WPOS")
  [ -n "$VIS" ]  && envs+=("OG_WANT_VIS=$VIS")
  [ "$DRV" = 1 ] && envs+=("OG_PAD_REPLAY_REPLAY=$DRIVE" "OG_PAD_REPLAY_REALTIME=1")
  env "${envs[@]}" stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
      -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
  GKPID=$!
  local booted=0 i
  for i in $(seq 1 200); do
    kill -0 "$GKPID" 2>/dev/null || { say "FAIL($TAG): gk exited during boot"; tail -20 "$GKLOG" >> "$LOG"; return 1; }
    grep -aqE "link finish: (default-menu|logo)" "$GKLOG" && { booted=1; break; }
    sleep 1
  done
  [ "$booted" = 1 ] || { say "FAIL($TAG): boot timeout"; tail -20 "$GKLOG" >> "$LOG"; return 1; }
  if [ -n "$WARP" ]; then
    local w=0
    for i in $(seq 1 200); do
      kill -0 "$GKPID" 2>/dev/null || { say "FAIL($TAG): gk died before the warp landed"; tail -20 "$GKLOG" >> "$LOG"; return 1; }
      grep -aq 'LEVEL-WARP-SPAWN' "$GKLOG" && { w=1; break; }
      sleep 1
    done
    [ "$w" = 1 ] || { say "FAIL($TAG): warp never landed ($WARP)"; return 1; }
    say "leg $TAG: warp landed ($WARP) after ${i}s"
  fi
  sleep "$WATCH"
  local ALIVE=no; kill -0 "$GKPID" 2>/dev/null && ALIVE=yes
  kill "$GKPID" 2>/dev/null; wait 2>/dev/null; GKPID=0
  say "leg $TAG: alive-at-end=$ALIVE ($(wc -l < "$GKLOG") log lines)"
  [ "$ALIVE" = yes ] || { say "FAIL($TAG): gk died during the watch window"; return 1; }
  python3 .autoport/physics_x86_grade.py "$TAG" "$MODE" "$QUAL" "$GKLOG" 2>&1 | tee -a "$LOG"
  return "${PIPESTATUS[0]}"
}

# village1 = Sandover: Jak + Daxter (companions) and Keira at the Zoomer. The only leg that DRIVES,
# because it is the only one where the player character exists and the owner's locomotion
# complaints ("en courant les cheveux de Jak ne bougent pas") live.
run_leg "X-MAX"   '#t' 2 phys  "village1-hut"   "-130.5 34.5 202.4" ""    170 1 || FAILED=1
# the owner's named non-regression case: the intro cinematic, Jak lying down, collar in close-up —
# and the only place Maia and Gol exist at all.
run_leg "X-INTRO" '#t' 2 intro "intro-start"    ""                  ""    200 0 || FAILED=1
# OFF must be OFF: not one window line. This is the toggle proof.
run_leg "X-OFF"   '#f' 1 off   "village1-hut"   "-130.5 34.5 202.4" ""    90  0 || FAILED=1
# the stock-actor rider path with the HD companions deliberately disabled — the ~50 -lod0 rigs.
run_leg "X-RIDER" '#t' 1 rider "village1-hut"   "-130.5 34.5 202.4" ""    120 0 || FAILED=1
# cast coverage: two villages full of stock NPCs.
run_leg "X-CAST"  '#t' 2 cast  "village2-start" ""                  ""    130 0 || FAILED=1
run_leg "X-CAST2" '#t' 2 cast  "village3-start" ""                  ""    130 0 || FAILED=1
# the mayor, whom in-world navigation never reached: his bow vs his belly is an owner-named site.
run_leg "X-MAYOR" '#t' 2 cast  "beach-start"    "-116.15 11.00 45.91" "vi1" 120 0 || FAILED=1

say ""
python3 .autoport/physics_x86_grade.py --run "$OUT" 2>&1 | tee -a "$LOG"
[ "${PIPESTATUS[0]}" = 0 ] || FAILED=1

if [ "$FAILED" = 0 ]; then
  say "[physics x86 leg PASS] every leg green on x86 — DEVICE PROOF STILL OWED (arm64 codegen, device perf, device-only paths unproven here)"
else
  say "[physics x86 leg FAIL] see the legs above"
fi
exit "$FAILED"
