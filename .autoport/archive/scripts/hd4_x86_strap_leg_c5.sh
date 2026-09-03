#!/usr/bin/env bash
# hd4_x86_strap_leg_c5.sh — CYCLE-5 item 2 x86 proof: Keira strap chains x collision, all physics
# levels, BOTH looks (keira-hd look=1, keira3-hd look=3).
# Mechanism under test (WIP checkpoint 5edfbc56c1): per-chain collider filters — `chains=` kv on
# collider lines (strap-only chest r=800 + hips r=700 for botstraps) + chain-bitmask FFI + push=/
# maxpen= window counters. Honest per-level behavior:
#   OFF   physics?=#f       -> ZERO [HD-PHYS] windows (straps = pure cycle-4 retarget)
# Keira looks under test: hd-look-keira=1 (keira-hd) and hd-look-keira=2 (keira3-hd).
#   LIGHT quality=0 cm=1    -> strap chains (class=secondary, bit 2) NOT simulated, collide=0
#   FULL  quality=1 cm=3    -> straps simulated WITH collision (strap colliders live)
#   MAX   quality=2 cm=7    -> same + 240Hz fixed-step
# PASS = per-level expectations hold, keira init resolves 3 colliders at FULL/MAX, zero unknown-
# chain warnings, nan=0, bounded; push/maxpen harvested as the collision instrument (counters,
# never captures).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-hd-models4; mkdir -p "$OUT"
R="$OUT/x86_strap_cycle5.txt"; : > "$R"
WATCH="${WATCH:-120}"
INI=build/game/OpenGOAL/jak1/settings/settings.ini
WARP=village1-hut; WPOS='-130.50 34.50 202.41'
say(){ echo "$*" | tee -a "$R"; }
say "===== cycle-5 x86 keira strap x physics leg — $(date -Is) ====="

[ -f "$ISO/GAME.CGO" ] || { say "FAIL: no GAME.CGO"; exit 1; }
[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/jak-hd-physics.gc ] || { say "FAIL: GAME.CGO stale vs jak-hd-physics.gc"; exit 1; }
grep -q 'chains=topstrapL' recharged_assets/physics_chains.txt || { say "FAIL: strap collider filters absent from physics_chains.txt"; exit 1; }
mkdir -p out/jak1/obj
for c in jak-hd dax-hd keira-hd samos-hd jak2-hd jak3-hd daxp-hd keira3-hd ysamos-hd jakm-hd; do
  cp -f "recharged_assets/hd_anim/$c-ag.go" out/jak1/obj/ || { say "FAIL: stage $c-ag.go"; exit 1; }
done
[ -f "$INI" ] || { say "FAIL: no settings.ini"; exit 1; }
cp "$INI" "$OUT/.settings.ini.pre-strap"
set_ini(){ if grep -q "^$1 " "$INI"; then sed -i "s|^$1 .*|$1 = $2|" "$INI"
  else sed -i "/^recharged-enhanced-models? = /a $1 = $2" "$INI"
       grep -q "^$1 = $2$" "$INI" || { say "FAIL: could not insert $1"; exit 1; }
  fi }
restore_ini(){ [ -f "$OUT/.settings.ini.pre-strap" ] && cp "$OUT/.settings.ini.pre-strap" "$INI" || true; }
GKPID=0
cleanup(){ [ "${GKPID:-0}" -gt 0 ] && kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true; restore_ini; }
trap cleanup EXIT
if grep -q '^recharged-master? = #f' "$INI"; then say "FAIL: recharged-master? #f forces STOCK"; exit 1; fi

FAILED=0
run_leg(){ # run_leg <tag> <physics> <quality> <keira-look> <expect: off|nostrap|collide>
  local TAG="$1" PHY="$2" QUAL="$3" KLOOK="$4" EXPECT="$5"
  # hd-look-keira: 1 -> entry 2 keira-hd, 2 -> entry 7 keira3-hd (jak-hd.gc hd-entry-for-char-look).
  # Anything else maps to -1 = NO companion (stock Keira) — driving 3 here would silently test stock.
  local AGN="keira-hd"; [ "$KLOOK" = 2 ] && AGN="keira3-hd"
  [ "$KLOOK" = 1 ] || [ "$KLOOK" = 2 ] || { say "FAIL($1): keira look $KLOOK has no HD entry"; FAILED=1; return; }
  set_ini 'recharged-enhanced-models?' '#t'
  set_ini 'physics?' "$PHY"
  set_ini 'physics-quality' "$QUAL"
  set_ini 'hd-look-jak' 1; set_ini 'hd-look-daxter' 1; set_ini 'hd-look-samos' 1
  set_ini 'hd-look-keira' "$KLOOK"
  local GKLOG="$OUT/.strap_gk_$TAG.log"; : > "$GKLOG"
  say ""
  say "=== LEG $TAG: physics?=$PHY quality=$QUAL keira-look=$KLOOK ($AGN) ==="
  OG_LEVEL_WARP="$WARP" OG_LEVEL_WARP_POS="$WPOS" \
    "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
  GKPID=$!
  local w=0
  for i in $(seq 1 200); do
    kill -0 "$GKPID" 2>/dev/null || { say "FAIL($TAG): gk exited"; tail -20 "$GKLOG" >> "$R"; FAILED=1; return; }
    grep -aq 'LEVEL-WARP-SPAWN' "$GKLOG" && { w=1; break; }; sleep 1
  done
  [ "$w" = 1 ] || { say "FAIL($TAG): warp never landed"; FAILED=1; kill "$GKPID" 2>/dev/null; wait 2>/dev/null||true; GKPID=0; return; }
  sleep "$WATCH"
  kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true; GKPID=0
  local CRASH; CRASH=$(grep -acE 'SIGSEGV|SIGBUS|Segmentation|Assertion' "$GKLOG" || true)
  [ "$CRASH" = 0 ] || { say "FAIL($TAG): crash markers=$CRASH"; FAILED=1; }
  local UNK; UNK=$(grep -ac 'chains= references unknown chain\|resolved to zero chains' "$GKLOG" || true)
  [ "$UNK" = 0 ] || { say "FAIL($TAG): $UNK collider chain-filter resolution warnings"; FAILED=1; }
  local KWIN; KWIN=$(grep -a "\[HD-PHYS\] ag=$AGN " "$GKLOG" | grep -ac 'window: chains=' || true)
  case "$EXPECT" in
    off)
      local NWIN; NWIN=$(grep -ac 'window: chains=' "$GKLOG" || true)
      if [ "$NWIN" = 0 ]; then say "OK($TAG): OFF -> zero [HD-PHYS] windows (straps = pure retarget)"
      else say "FAIL($TAG): $NWIN windows with physics off"; FAILED=1; fi
      ;;
    nostrap)
      [ "$KWIN" -ge 1 ] || { say "FAIL($TAG): no $AGN windows"; FAILED=1; return; }
      local CM; CM=$(grep -a "\[HD-PHYS\] ag=$AGN .*window" "$GKLOG" | grep -oE 'cm=[0-9]+' | sort -u | tr '\n' ' ')
      local PUSH; PUSH=$(grep -a "\[HD-PHYS\] ag=$AGN " "$GKLOG" | grep -oE 'push=[0-9]+' | cut -d= -f2 | awk '{s+=$1} END{print s+0}')
      say "$TAG: $AGN windows=$KWIN cm={$CM} pushes=$PUSH"
      if echo "$CM" | grep -qE '^cm=1 $' && [ "$PUSH" = 0 ]; then
        say "OK($TAG): LIGHT -> secondary strap chains not simulated (cm=1), collide off (push=0)"
      else say "FAIL($TAG): LIGHT expectations broken (cm={$CM} push=$PUSH)"; FAILED=1; fi
      ;;
    collide)
      [ "$KWIN" -ge 1 ] || { say "FAIL($TAG): no $AGN windows"; FAILED=1; return; }
      local NCOL; NCOL=$(grep -a "\[HD-PHYS\] init ag=$AGN " "$GKLOG" | grep -oE 'colliders=[0-9]+' | tail -1 | cut -d= -f2)
      [ "${NCOL:-0}" -ge 3 ] || { say "FAIL($TAG): $AGN resolved colliders=$NCOL (<3: strap colliders missing)"; FAILED=1; }
      local NNAN; NNAN=$(grep -a "\[HD-PHYS\] ag=$AGN " "$GKLOG" | grep -a 'nan-resets=' | grep -cv 'nan-resets=0 ' || true)
      [ "$NNAN" = 0 ] || { say "FAIL($TAG): nan resets on $AGN"; FAILED=1; }
      local NBIG; NBIG=$(grep -a "\[HD-PHYS\] ag=$AGN " "$GKLOG" | awk -F'maxdev=' 'NF>1{if ($2+0>=5000) n++} END{print n+0}')
      [ "$NBIG" = 0 ] || { say "FAIL($TAG): $NBIG unbounded windows"; FAILED=1; }
      local PUSH MAXPEN WITHPUSH
      # instrument gate: the window MUST be one line carrying push= (see jak-hd-physics.gc emitter).
      WITHPUSH=$(grep -a "\[HD-PHYS\] ag=$AGN " "$GKLOG" | grep -ac 'window: chains=.*push=' || true)
      [ "$WITHPUSH" -ge "$KWIN" ] || { say "FAIL($TAG): $KWIN window lines but only $WITHPUSH carry push= — [HD-PHYS] window split across lines, push/maxpen NOT measurable"; FAILED=1; }
      PUSH=$(grep -a "\[HD-PHYS\] ag=$AGN " "$GKLOG" | grep -oE 'push=[0-9]+' | cut -d= -f2 | awk '{s+=$1} END{print s+0}')
      MAXPEN=$(grep -a "\[HD-PHYS\] ag=$AGN " "$GKLOG" | grep -oE 'maxpen=[0-9.]+' | cut -d= -f2 | sort -g | tail -1)
      say "OK($TAG): $AGN windows=$KWIN colliders=$NCOL pushes=$PUSH maxpen=${MAXPEN:-0} nan=0 bounded"
      ;;
  esac
}

run_leg OFF  '#f' 1 1 off
run_leg L0   '#t' 0 1 nostrap
run_leg L1-K '#t' 1 1 collide
run_leg L1-3 '#t' 1 2 collide
run_leg L2-K '#t' 2 1 collide
run_leg L2-3 '#t' 2 2 collide

say ""
if [ "$FAILED" = 0 ]; then say "[strap-c5-leg PASS] per-level behavior + both looks proven"; exit 0
else say "[strap-c5-leg FAIL]"; exit 1; fi
