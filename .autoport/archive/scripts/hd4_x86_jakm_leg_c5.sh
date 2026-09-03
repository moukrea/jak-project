#!/usr/bin/env bash
# hd4_x86_jakm_leg_c5.sh — CYCLE-5 item 1 x86 proof leg: Jak 3 MASQUE BAISSÉ (jakm-hd, look jak=4).
# Cycle-5 REPLACES the cycle-4 bake mechanism (retired: weight-1.0 bake was 4096x too small AND the
# real mask is a duplicated scarf EFFECT, not a morph): jakm-hd is now the jakc donor appended with
# --drop-effect 0 (over-nose scarf gone) + --strip-target 15/22/23 (nothing can re-raise the mask).
# GATES:
#   (a) DISTINCTNESS (quantitative, on the SHIPPED fr3): jakm-hd-lod0 effects == jak3-hd-lod0
#       effects - 1, and fewer draws+tris (the dropped scarf); numbers logged for the report.
#   (b) look jak=4 -> jakm-hd-lod0 SUBMITTED found=1, other jak looks forbidden.
#   (c) blink slots 0/1 live (donor lid paints, zero STOCKLID), flicker 0/0, no crash.
# Renderer counters + state dumps only — never captures (owner rule 2026-08-04).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-hd-models4; mkdir -p "$OUT"
R="$OUT/x86_jakm_cycle5.txt"; : > "$R"
WATCH="${WATCH:-120}"
INI=build/game/OpenGOAL/jak1/settings/settings.ini
SWAP=build/tools/hd_merc_swap/hd_merc_swap
say(){ echo "$*" | tee -a "$R"; }
say "===== cycle-5 x86 jakm (mask-down bare-face) leg — $(date -Is) ====="

[ -f "$ISO/GAME.CGO" ] || { say "FAIL: no $ISO/GAME.CGO"; exit 1; }
[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/jak-hd.gc ] || { say "FAIL: GAME.CGO stale vs jak-hd.gc"; exit 1; }
ENH=out/jak1/fr3/enhanced/GAME.fr3
[ -f "$ENH" ] || { say "FAIL: no enhanced GAME.fr3 — bake first"; exit 1; }
[ -x "$SWAP" ] || { say "FAIL: $SWAP not built"; exit 1; }

# ---- gate (a): quantitative distinctness on the SHIPPED fr3 --------------------------------
AUD=$("$SWAP" audit "$ENH" jak3-hd-lod0 jakm-hd-lod0 2>&1) || { say "FAIL: audit errored"; exit 1; }
J3=$(echo "$AUD" | grep -a '^MODEL jak3-hd-lod0 ')
JM=$(echo "$AUD" | grep -a '^MODEL jakm-hd-lod0 ')
[ -n "$J3" ] || { say "FAIL: jak3-hd-lod0 not in enhanced GAME.fr3"; exit 1; }
[ -n "$JM" ] || { say "FAIL: jakm-hd-lod0 not in enhanced GAME.fr3"; exit 1; }
num(){ echo "$1" | grep -oE "$2=[0-9]+" | head -1 | cut -d= -f2; }
J3E=$(num "$J3" effects); J3D=$(num "$J3" total_draws); J3T=$(num "$J3" total_tris)
JME=$(num "$JM" effects); JMD=$(num "$JM" total_draws); JMT=$(num "$JM" total_tris)
say "jak3-hd-lod0: effects=$J3E draws=$J3D tris=$J3T"
say "jakm-hd-lod0: effects=$JME draws=$JMD tris=$JMT"
if [ "$JME" -eq $((J3E - 1)) ] && [ "$JMD" -lt "$J3D" ] && [ "$JMT" -lt "$J3T" ]; then
  say "DISTINCT PASS: jakm-hd = jak3-hd minus the over-nose scarf effect (effects $J3E->$JME, draws $J3D->$JMD, tris $J3T->$JMT, delta_tris=$((J3T - JMT)))"
else
  say "FAIL: models NOT distinct (drop-effect did not land in the shipped fr3)"; exit 1
fi
# strip-target proof: the appended jakm blerc data may not reference donor targets 15/22/23
JMEFF=$(echo "$AUD" | sed -n '/^MODEL jakm-hd-lod0 /,/^MODEL /p' | grep -a 'max_blerc_target=' || true)
BADT=$(echo "$JMEFF" | grep -oE 'max_blerc_target=[0-9]+' | cut -d= -f2 | sort -n | tail -1)
say "jakm-hd max blerc target in shipped fr3: ${BADT:-none} (strip gate: report-side, channel-map is the instrument)"

mkdir -p out/jak1/obj
for c in jak-hd dax-hd keira-hd samos-hd jak2-hd jak3-hd daxp-hd keira3-hd ysamos-hd jakm-hd; do
  cp -f "recharged_assets/hd_anim/$c-ag.go" out/jak1/obj/ || { say "FAIL: stage $c-ag.go"; exit 1; }
done
say "staged 10 HD art-groups into out/jak1/obj"

[ -f "$INI" ] || { say "FAIL: no $INI (run gk once to create it)"; exit 1; }
cp "$INI" "$OUT/.settings.ini.pre-jakm"
set_ini(){ # NEVER append at EOF ([music] trap) — insert at top level after enhanced-models line
  if grep -q "^$1 " "$INI"; then sed -i "s|^$1 .*|$1 = $2|" "$INI"
  else sed -i "/^recharged-enhanced-models? = /a $1 = $2" "$INI"
       grep -q "^$1 = $2$" "$INI" || { say "FAIL: could not insert $1"; exit 1; }
  fi
}
restore_ini(){ [ -f "$OUT/.settings.ini.pre-jakm" ] && cp "$OUT/.settings.ini.pre-jakm" "$INI" || true; }
grep -q '^version = #x' "$INI" || { say "FAIL: settings.ini has no version stamp"; exit 1; }
if grep -q '^recharged-master? = #f' "$INI"; then say "FAIL: recharged-master? #f would force STOCK"; exit 1; fi
set_ini 'recharged-enhanced-models?' '#t'
set_ini 'hd-look-jak' 4
set_ini 'hd-look-daxter' 1
set_ini 'hd-look-keira' 1
set_ini 'hd-look-samos' 1

GKPID=0
cleanup(){ [ "${GKPID:-0}" -gt 0 ] && kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true; restore_ini; }
trap cleanup EXIT

GKLOG="$OUT/.jakm_gk_c5.log"; : > "$GKLOG"
"$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem > "$GKLOG" 2>&1 &
GKPID=$!
booted=0
for i in $(seq 1 150); do
  kill -0 "$GKPID" 2>/dev/null || { say "FAIL: gk exited during boot"; tail -25 "$GKLOG" >> "$R"; exit 1; }
  grep -aqE "link finish: (default-menu|logo)" "$GKLOG" && { booted=1; break; }
  sleep 1
done
[ "$booted" = 1 ] || { say "FAIL: boot timeout"; tail -25 "$GKLOG" >> "$R"; exit 1; }
say "booted — watching ${WATCH}s (look jak=4)"
sleep "$WATCH"
ALIVE=no; kill -0 "$GKPID" 2>/dev/null && ALIVE=yes
OK=1
grep -aq 'HD-MODELS fr3-select GAME: ENHANCED' "$GKLOG" || { say "FAIL: GAME not ENHANCED"; OK=0; }
if grep -aq "SUBMITTED name='jakm-hd-lod0' found=1" "$GKLOG"; then
  say "OK: jakm-hd-lod0 SUBMITTED found=1 (bare-face look renders)"
else say "FAIL: jakm-hd-lod0 never submitted"; OK=0; fi
for m in jak-hd jak2-hd jak3-hd; do
  if grep -aq "SUBMITTED name='$m-lod0' found=1" "$GKLOG"; then
    say "FAIL: forbidden $m-lod0 submitted (look did not replace)"; OK=0
  fi
done
# strip-target runtime instrument: targets 15/22/23 must be ABSENT from jakm's BLERC-MAP lines
STRIPBAD=0
for t in 15 22 23; do
  if grep -a 'BLERC-MAP.*jakm-hd' "$GKLOG" | grep -qE "target[ =]$t\b"; then
    say "FAIL: stripped target $t still in jakm-hd runtime channel map"; STRIPBAD=1; OK=0
  fi
done
[ "$STRIPBAD" = 0 ] && say "strip gate: targets 15/22/23 absent from jakm-hd runtime channel map"
# blink on the bare-face look (eichar eye slots 0/1) — donor lid paints + zero STOCKLID
STOCKLID=$(grep -ac '\[hd-blink\] STOCKLID' "$GKLOG" || true)
say "STOCKLID events: $STOCKLID (must be 0)"; [ "$STOCKLID" = 0 ] || OK=0
for s in 0 1; do
  HB=$(grep -a "\[hd-blink\] slot=$s " "$GKLOG" | tr -d '\r')
  N=$(echo "$HB" | grep -c 'donor_paints' || true)
  if [ "$N" = 0 ]; then say "FAIL slot=$s: no [hd-blink] heartbeat"; OK=0; continue; fi
  DON=$(echo "$HB" | grep -oE 'donor_paints=[0-9]+' | grep -cv 'donor_paints=0$' || true)
  say "slot=$s heartbeats=$N donor-active-windows=$DON"
  [ "$DON" -ge 1 ] || { say "FAIL slot=$s: no donor lid paints"; OK=0; }
done
EVB=$(grep -ac '\[hd-flicker\] BLACKOUT' "$GKLOG" || true)
EVG=$(grep -ac '\[hd-flicker\] GAP' "$GKLOG" || true)
say "flicker BLACKOUT=$EVB GAP=$EVG (must be 0/0)"
[ "$EVB" = 0 ] && [ "$EVG" = 0 ] || OK=0
CRASH=$(grep -acE 'SIGSEGV|SIGILL|Segmentation|Assertion' "$GKLOG" || true)
NOSLOT=$(grep -ac 'no free blerc override slot' "$GKLOG" || true)
say "alive=$ALIVE crash-markers=$CRASH blerc-exhaustion=$NOSLOT"
[ "$ALIVE" = yes ] && [ "$CRASH" = 0 ] && [ "$NOSLOT" = 0 ] || OK=0
kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true; GKPID=0
if [ "$OK" = 1 ]; then say "[jakm-c5-leg PASS] bare-face look distinct + submits, blink live, flicker clean"; exit 0
else say "[jakm-c5-leg FAIL]"; exit 1; fi
