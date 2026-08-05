#!/usr/bin/env bash
# hd4_x86_jakm_leg.sh — CYCLE-4 item 3 x86 proof leg: Jak 3 MASQUE BAISSÉ (jakm-hd, look jak=4).
# Clone of the hd5_x86_smoke.sh harness (settings.ini-driven, the exact mechanism the menu
# carousel writes) with one leg: hd-look-jak=4 -> jakm-hd-lod0 SUBMITTED found=1, the other jak
# looks forbidden, [hd-blink] heartbeats live on the jak eye slots (0/1), flicker 0/0, no crash.
# Renderer counters + state dumps only — never captures (owner rule 2026-08-04).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-hd-models4; mkdir -p "$OUT"
R="$OUT/x86_jakm_cycle4.txt"; : > "$R"
WATCH="${WATCH:-120}"
INI=build/game/OpenGOAL/jak1/settings/settings.ini
say(){ echo "$*" | tee -a "$R"; }
say "===== cycle-4 x86 jakm (masked) leg — $(date -Is) ====="

[ -f "$ISO/GAME.CGO" ] || { say "FAIL: no $ISO/GAME.CGO"; exit 1; }
[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/jak-hd.gc ] || { say "FAIL: GAME.CGO stale vs jak-hd.gc"; exit 1; }
ENH=out/jak1/fr3/enhanced/GAME.fr3
[ -f "$ENH" ] || { say "FAIL: no enhanced GAME.fr3 — bake first"; exit 1; }
AUD=$(build/tools/hd_merc_swap/hd_merc_swap audit "$ENH" "jakm-hd-lod0" 2>&1 || true)
[[ "$AUD" == *"jakm-hd-lod0"* ]] || { say "FAIL: jakm-hd-lod0 not in enhanced GAME.fr3"; exit 1; }
say "enhanced GAME.fr3 contains jakm-hd-lod0 (audit probe)"
BAKELOG=.autoport/logs/build-enhanced-models.log
if grep -qE 'BLERC-BAKE: target=15 .*verts_moved=[1-9]' "$BAKELOG" 2>/dev/null; then
  say "bake evidence: $(grep -m1 -oE 'BLERC-BAKE: target=15[^"]*' "$BAKELOG")"
else
  say "FAIL: no BLERC-BAKE target=15 line in $BAKELOG"; exit 1
fi

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

GKLOG="$OUT/.jakm_gk.log"; : > "$GKLOG"
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
  say "OK: jakm-hd-lod0 SUBMITTED found=1 (masked look renders)"
else say "FAIL: jakm-hd-lod0 never submitted"; OK=0; fi
for m in jak-hd jak2-hd jak3-hd; do
  if grep -aq "SUBMITTED name='$m-lod0' found=1" "$GKLOG"; then
    say "FAIL: forbidden $m-lod0 submitted (look did not replace)"; OK=0
  fi
done
# blink on the masked look (eichar eye slots 0/1) — donor lid paints + excursion + zero STOCKLID
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
if [ "$OK" = 1 ]; then say "[jakm-leg PASS] masked look submits, blink live, flicker clean"; exit 0
else say "[jakm-leg FAIL]"; exit 1; fi
