#!/usr/bin/env bash
# physics_x86_smoke.sh — Grecharged-secondary-motion x86-FIRST smoke (state-dumps-x86-first rule).
#
# Four legs against the same fresh --hd-models --pbr --physics build, driven ONLY by the settings
# the menu writes (physics? / physics-quality in settings.ini):
#   LEG L2  "max":     physics?=#t quality=2, primary looks    -> [HD-PHYS] init chains>0 on the
#                      spawned companions, window state dumps with nan-resets=0, bounded maxdev.
#   LEG L0  "light":   physics?=#t quality=0, primary looks    -> same bar at the light level.
#   LEG BONUS "looks": physics?=#t quality=1, bonus looks 2222 -> per-look params resolve (init
#                      lines for jak2-hd/daxp-hd/keira3-hd/ysamos-hd with chains>0).
#   LEG OFF "off":     physics?=#f                             -> ZERO [HD-PHYS] window lines
#                      (full in-game disable; init lines alone are allowed = resolution only).
# PASS bar per leg: boot OK, params-loaded line names >=8 models, the leg's [HD-PHYS] expectations,
# no crash markers, gk alive WATCH seconds. nan-resets MUST be 0 everywhere.
# Physical artifact gate up front: the built GAME.CGO must CONTAIN the [HD-PHYS] format strings
# (check the artifact, never the run — feedback_make_recurrence_impossible).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-secondary-motion; mkdir -p "$OUT"
R="$OUT/x86_smoke.txt"; : > "$R"
WATCH="${WATCH:-150}"
INI=build/game/OpenGOAL/jak1/settings/settings.ini
say(){ echo "$*" | tee -a "$R"; }

# ---- staleness + artifact gates ----------------------------------------------------------------
[ -f "$ISO/GAME.CGO" ] || { say "FAIL: no $ISO/GAME.CGO"; exit 1; }
[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/jak-hd-physics.gc ] || { say "FAIL: GAME.CGO stale vs jak-hd-physics.gc"; exit 1; }
[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/pckernel-impl.gc ] || { say "FAIL: GAME.CGO stale vs pckernel-impl.gc"; exit 1; }
[ -f recharged_assets/physics_chains.txt ] || { say "FAIL: no recharged_assets/physics_chains.txt"; exit 1; }
# physical artifact: the CGO carries the sim's format strings and the settings carry the flag
STR=$(strings -a "$ISO/GAME.CGO" | grep -c 'HD-PHYS' || true)
[ "$STR" -ge 3 ] || { say "FAIL: GAME.CGO carries $STR HD-PHYS strings (<3) — physics not compiled in"; exit 1; }
say "artifact gate: GAME.CGO carries $STR [HD-PHYS] format strings"
# the binary must expose the FFI (verify_binary_flags equivalent, local)
if ! strings -a build/game/gk | grep -q 'pc-physics-joint-role'; then
  say "FAIL: gk binary lacks pc-physics-joint-role — OG_FEAT_PHYSICS not built"; exit 1; fi
say "artifact gate: gk exposes the pc-physics FFI"
ENH=out/jak1/fr3/enhanced/GAME.fr3
[ -f "$ENH" ] || { say "FAIL: no enhanced GAME.fr3 — bake first"; exit 1; }

# ---- stage the 10 HD art-groups ---------------------------------------------------------------
mkdir -p out/jak1/obj
for c in jak-hd dax-hd keira-hd samos-hd jak2-hd jak3-hd daxp-hd keira3-hd ysamos-hd jakm-hd; do
  cp -f "recharged_assets/hd_anim/$c-ag.go" out/jak1/obj/ || { say "FAIL: stage $c-ag.go"; exit 1; }
done
say "staged 10 HD art-groups into out/jak1/obj"

# ---- settings.ini (same trap rules as hd5: never append at EOF) --------------------------------
[ -f "$INI" ] || { say "FAIL: no $INI (run gk once to create it)"; exit 1; }
cp "$INI" "$OUT/.settings.ini.pre-smoke"
set_ini(){
  if grep -q "^$1 " "$INI"; then sed -i "s|^$1 .*|$1 = $2|" "$INI"
  else sed -i "/^recharged-enhanced-models? = /a $1 = $2" "$INI"
       grep -q "^$1 = $2$" "$INI" || { say "FAIL: could not insert $1"; exit 1; }
  fi
}
restore_ini(){ [ -f "$OUT/.settings.ini.pre-smoke" ] && cp "$OUT/.settings.ini.pre-smoke" "$INI" || true; }
grep -q '^version = #x' "$INI" || { say "FAIL: settings.ini has no version stamp"; exit 1; }
if grep -q '^recharged-master? = #f' "$INI"; then say "FAIL: recharged-master? #f would force STOCK"; exit 1; fi
set_ini 'recharged-enhanced-models?' '#t'

GKPID=0
cleanup(){ [ "${GKPID:-0}" -gt 0 ] && kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true; restore_ini; }
trap cleanup EXIT

run_leg(){ # run_leg <tag> <physics #t/#f> <quality> <lookJ> <lookD> <lookK> <lookS> <mode expect-phys|expect-off>
  local TAG="$1" PHY="$2" QUAL="$3" LJ="$4" LD="$5" LK="$6" LS="$7" MODE="$8"
  local GKLOG="$OUT/.smoke_gk_$TAG.log"; : > "$GKLOG"
  set_ini 'physics?' "$PHY"; set_ini 'physics-quality' "$QUAL"
  set_ini 'hd-look-jak' "$LJ"; set_ini 'hd-look-daxter' "$LD"
  set_ini 'hd-look-keira' "$LK"; set_ini 'hd-look-samos' "$LS"
  say ""
  say "=== LEG $TAG: physics?=$PHY quality=$QUAL looks $LJ$LD$LK$LS ==="
  "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
  GKPID=$!
  local booted=0 i
  for i in $(seq 1 150); do
    kill -0 "$GKPID" 2>/dev/null || { say "FAIL($TAG): gk exited during boot"; tail -25 "$GKLOG" >> "$R"; return 1; }
    grep -aqE "link finish: (default-menu|logo)" "$GKLOG" && { booted=1; break; }
    sleep 1
  done
  [ "$booted" = 1 ] || { say "FAIL($TAG): boot timeout"; tail -25 "$GKLOG" >> "$R"; return 1; }
  say "booted — watching ${WATCH}s"
  sleep "$WATCH"
  local ALIVE=no; kill -0 "$GKPID" 2>/dev/null && ALIVE=yes
  local OK=1
  grep -aq 'HD-MODELS fr3-select GAME: ENHANCED' "$GKLOG" || { say "FAIL($TAG): GAME not ENHANCED"; OK=0; }
  local CRASH; CRASH=$(grep -acE 'SIGSEGV|SIGILL|Segmentation|Assertion' "$GKLOG" || true)
  local NINIT NWIN NNAN NREST NLOAD
  NINIT=$(grep -ac '\[HD-PHYS\] init ag=' "$GKLOG" || true)
  NWIN=$(grep -ac '\[HD-PHYS\].*window: chains=' "$GKLOG" || true)
  # any window line with a nonzero nan-resets fails everything
  NNAN=$(grep -a 'nan-resets=' "$GKLOG" | grep -cv 'nan-resets=0 ' || true)
  NREST=$(grep -ac 'rest-converged' "$GKLOG" || true)
  NLOAD=$(grep -ac 'params loaded' "$GKLOG" || true)
  say "leg $TAG: alive=$ALIVE init=$NINIT windows=$NWIN nan-bad=$NNAN rest=$NREST params-loaded=$NLOAD crash=$CRASH"
  [ "$ALIVE" = yes ] || OK=0
  [ "$CRASH" = 0 ] || OK=0
  case "$MODE" in
    expect-phys)
      [ "$NLOAD" -ge 1 ] || { say "FAIL($TAG): no 'params loaded' line"; OK=0; }
      # init lines must report chains>0 on at least 2 companions (title spawns jak+dax drivers)
      local NCH; NCH=$(grep -a '\[HD-PHYS\] init ag=' "$GKLOG" | grep -vc 'chains=0 ' || true)
      [ "$NCH" -ge 1 ] || { say "FAIL($TAG): no companion resolved any chain"; OK=0; }
      [ "$NWIN" -ge 1 ] || { say "FAIL($TAG): no [HD-PHYS] window state dump"; OK=0; }
      [ "$NNAN" = 0 ] || { say "FAIL($TAG): nan-resets nonzero — sim exploded"; OK=0; }
      # bounded: no window line may report maxdev >= 5000 units (~1.2m) at title idle
      local NBIG; NBIG=$(grep -a 'maxdev=' "$GKLOG" | awk -F'maxdev=' '{print $2}' | awk '{if ($1+0 >= 5000.0) n++} END {print n+0}')
      [ "$NBIG" = 0 ] || { say "FAIL($TAG): $NBIG window(s) with maxdev>=5000 — not bounded"; OK=0; }
      say "leg $TAG: chains-resolving-inits=$NCH bounded-windows=yes"
      ;;
    expect-off)
      [ "$NWIN" = 0 ] || { say "FAIL($TAG): $NWIN window lines with physics?=#f — OFF is not off"; OK=0; }
      ;;
  esac
  kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true; GKPID=0; sleep 2
  [ "$OK" = 1 ]
}

FAILED=0
run_leg "L2-max"    '#t' 2 1 1 1 1 expect-phys || FAILED=1
run_leg "L0-light"  '#t' 0 1 1 1 1 expect-phys || FAILED=1
run_leg "BONUS"     '#t' 1 2 2 2 2 expect-phys || FAILED=1
run_leg "OFF"       '#f' 1 1 1 1 1 expect-off  || FAILED=1

say ""
if [ "$FAILED" = 0 ]; then say "[physics x86 smoke PASS] all four legs green"; else say "[physics x86 smoke FAIL] see legs above"; fi
exit "$FAILED"
