#!/usr/bin/env bash
# hd4_x86_blink_leg.sh — CYCLE-4 blink proof leg (x86-first, metrics not eyeballs).
#
# Instrument (EyeRenderer, cycle 4): per-eye-slot heartbeat every ~4s of eye frames:
#   [hd-blink] slot=N donor_paints=A skips=B stock_covered=C lid_min=X lid_max=Y
#   - donor_paints  = lid blits done with the DONOR's ported lid texture (the visible blink)
#   - skips         = covered-slot frames with no donor lid available (cycle-3 fail-safe)
#   - stock_covered = stock jak1 lid painted on an HD eye — MUST be 0 (the black-eye bug)
#   - lid_min/max   = driver lid-value excursion in the window (0=closed, 1=open); a real
#                     blink shows lid_min <= 0.5 in some window AND lid_max >= 0.9
# PASS bar per character slot pair: donor_paints>0, zero STOCKLID events, blink excursion
# observed (some heartbeat with lid_min<=0.5 and some with lid_max>=0.9). Plus carried
# no-regress: [hd-flicker] blackouts=0 gaps=0, gk alive, no crash markers.
#
# Leg A (echo-intro): jak slots 0x0/0x1, dax 0x2/0x3, samos 0x4/0x5.
# Leg B (village1-hut assistant warp): keira slots 0x6/0x7 (jak 0x0/0x1 also live).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-hd-models4; mkdir -p "$OUT"
R="$OUT/x86_blink_cycle4.txt"; : > "$R"
WATCH_A="${WATCH_A:-150}"; WATCH_B="${WATCH_B:-90}"
say(){ echo "$*" | tee -a "$R"; }
say "===== cycle-4 x86 blink leg — $(date -Is) ====="

[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/jak-hd.gc ] || { say "FAIL: GAME.CGO stale vs jak-hd.gc — run (mi) first"; exit 1; }
[ -f out/jak1/fr3/enhanced/GAME.fr3 ] || { say "FAIL: enhanced GAME.fr3 missing — run build_enhanced_models.sh"; exit 1; }
mkdir -p out/jak1/obj
for c in jak dax keira samos; do
  cp -f "recharged_assets/hd_anim/$c-hd-ag.go" out/jak1/obj/ || { say "FAIL: stage $c-hd-ag.go"; exit 1; }
done
say "staged 4 HD art-groups into out/jak1/obj"

# ---------- shared per-leg runner -------------------------------------------------------------
run_leg(){ # $1 leg-name  $2 gk-log  $3 watch-secs  $4 extra-env ("" or OG_ECHO_INTRO=1)  $5 warp ("" or level name)  $6 warp-pos
  local leg="$1" gklog="$2" watch="$3" extraenv="$4" warp="$5" wpos="$6"
  : > "$gklog"
  local envs=()
  [ -n "$extraenv" ] && envs+=("$extraenv")
  [ -n "$warp" ] && envs+=("OG_LEVEL_WARP=$warp" "OG_LEVEL_WARP_POS=$wpos")
  env "${envs[@]}" "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$gklog" 2>&1 &
  GKPID=$!
  local booted=0
  for i in $(seq 1 150); do
    kill -0 "$GKPID" 2>/dev/null || { say "[$leg] FAIL: gk exited during boot"; tail -25 "$gklog" >> "$R"; return 1; }
    grep -aqE "link finish: (default-menu|logo)" "$gklog" && { booted=1; break; }
    sleep 1
  done
  [ "$booted" = 1 ] || { say "[$leg] FAIL: boot timeout"; tail -25 "$gklog" >> "$R"; return 1; }
  if [ -n "$extraenv" ]; then
    local w=0
    for i in $(seq 1 120); do
      kill -0 "$GKPID" 2>/dev/null || { say "[$leg] FAIL: gk died pre-warp"; tail -25 "$gklog" >> "$R"; return 1; }
      grep -aq 'ECHO-INTRO-WARP' "$gklog" && { w=1; break; }
      sleep 1
    done
    [ "$w" = 1 ] || { say "[$leg] FAIL: echo-intro warp never fired"; tail -25 "$gklog" >> "$R"; return 1; }
  fi
  if [ -n "$warp" ]; then
    local w=0
    for i in $(seq 1 120); do
      kill -0 "$GKPID" 2>/dev/null || { say "[$leg] FAIL: gk died pre-warp"; tail -25 "$gklog" >> "$R"; return 1; }
      grep -aq 'LEVEL-WARP-SPAWN' "$gklog" && { w=1; break; }
      sleep 1
    done
    [ "$w" = 1 ] || { say "[$leg] FAIL: level warp never fired"; tail -25 "$gklog" >> "$R"; return 1; }
  fi
  say "[$leg] scene reached — watching ${watch}s with [hd-blink] live"
  sleep "$watch"
  kill -0 "$GKPID" 2>/dev/null && ALIVE=yes || ALIVE=no
  kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true
  local crash; crash=$(grep -acE 'SIGSEGV|SIGILL|Segmentation|Assertion' "$gklog" || true)
  say "[$leg] gk alive at end: $ALIVE  crash markers: $crash"
  [ "$ALIVE" = yes ] && [ "$crash" = 0 ] || return 1
  grep -a -m1 'HD-MODELS fr3-select GAME' "$gklog" | tr -d '\r' | tee -a "$R" | grep -q ENHANCED \
    || { say "[$leg] FAIL: enhanced GAME.fr3 not selected"; return 1; }
  return 0
}

# ---------- per-slot blink assertions ---------------------------------------------------------
check_slots(){ # $1 leg-name  $2 gk-log  $3.. slots
  local leg="$1" gklog="$2"; shift 2
  local ok=1
  local stocklid; stocklid=$(grep -ac '\[hd-blink\] STOCKLID' "$gklog" || true)
  say "[$leg] STOCKLID events: $stocklid (must be 0)"
  [ "$stocklid" = 0 ] || ok=0
  for s in "$@"; do
    local hb; hb=$(grep -a "\[hd-blink\] slot=$s " "$gklog" | tr -d '\r')
    local n; n=$(echo "$hb" | grep -c 'donor_paints' || true)
    if [ "$n" = 0 ]; then say "[$leg] FAIL slot=$s: no [hd-blink] heartbeat"; ok=0; continue; fi
    local donor stock closed open
    donor=$(echo "$hb" | grep -oE 'donor_paints=[0-9]+' | grep -cv 'donor_paints=0$' || true)
    stock=$(echo "$hb" | grep -oE 'stock_covered=[0-9]+' | grep -cv 'stock_covered=0$' || true)
    closed=$(echo "$hb" | awk 'match($0,/lid_min=([0-9.]+)/,m){ if (m[1]+0<=0.5) c++ } END{print c+0}')
    open=$(echo "$hb" | awk 'match($0,/lid_max=([0-9.]+)/,m){ if (m[1]+0>=0.9) c++ } END{print c+0}')
    say "[$leg] slot=$s heartbeats=$n donor-active-windows=$donor stock-nonzero-windows=$stock closed-windows(lid_min<=0.5)=$closed open-windows(lid_max>=0.9)=$open"
    [ "$donor" -ge 1 ] || { say "[$leg] FAIL slot=$s: no donor lid paints"; ok=0; }
    [ "$stock" = 0 ] || { say "[$leg] FAIL slot=$s: stock lid painted while covered"; ok=0; }
    [ "$closed" -ge 1 ] || { say "[$leg] FAIL slot=$s: lid never dipped <=0.5 — no visible blink"; ok=0; }
    [ "$open" -ge 1 ] || { say "[$leg] FAIL slot=$s: lid never opened >=0.9"; ok=0; }
  done
  # carried no-regress: flicker detector clean
  local evb evg
  evb=$(grep -ac '\[hd-flicker\] BLACKOUT' "$gklog" || true)
  evg=$(grep -ac '\[hd-flicker\] GAP' "$gklog" || true)
  say "[$leg] flicker BLACKOUT=$evb GAP=$evg (carried, must be 0/0)"
  [ "$evb" = 0 ] && [ "$evg" = 0 ] || ok=0
  [ "$ok" = 1 ]
}

PASS=1
GKLOG_A="$OUT/.blink_gk_legA.log"
if run_leg legA "$GKLOG_A" "$WATCH_A" "OG_ECHO_INTRO=1" "" ""; then
  check_slots legA "$GKLOG_A" 0 1 2 3 4 5 || PASS=0
else
  PASS=0
fi

GKLOG_B="$OUT/.blink_gk_legB.log"
if run_leg legB "$GKLOG_B" "$WATCH_B" "" "village1-hut" "-130.5 34.5 202.4"; then
  check_slots legB "$GKLOG_B" 6 7 || PASS=0
else
  PASS=0
fi

if [ "$PASS" = 1 ]; then
  say "[blink-leg PASS] donor lid paints + blink excursion on all character slots, zero STOCKLID, flicker clean"
  exit 0
else
  say "[blink-leg FAIL]"
  exit 1
fi
