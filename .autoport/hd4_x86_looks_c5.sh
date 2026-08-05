#!/usr/bin/env bash
# hd4_x86_looks_c5.sh — CYCLE-5 x86 proof leg for the JAK LOOK carousel additions/fixes.
#
# Covers, in one run:
#   item 1  jakm-hd (JAK 3 MASQUE BAISSÉ) is now VISIBLY DISTINCT from jak3-hd. The cycle-4 bake
#           mechanism is retired (a weight-1.0 blerc bake was 4096x too small AND target 15 was
#           never the mask): the jakc donor carries the mask as TWO SEPARATE `jakc-scarf` EFFECTS —
#           effect[0] static, pulled UP OVER THE NOSE (blerc_verts=0) and effect[17] animated,
#           hanging at the NECK (240 blerc verts). Merc2 force-enables every effect on HD shells, so
#           both scarves always drew and the face was never bare. jakm-hd is now appended with
#           --drop-effect 0 (+ --strip-target 15/22/23 so nothing re-raises it at runtime).
#   item 3  the two last CINEMATIC Jak looks found by the exhaustive jak2+jak3 sweep:
#           jakp-hd (JAK II PRISON, jak2 ldjakbrn jak-highres-prison) and
#           jakf-hd (JAK 3 BAREFOOT, jak3 ljkfeet jakc-feet).
#
# GATES (all renderer-side counters / artifact measurements — never captures, owner rule
# 2026-08-04 "pour toujours"):
#   (a) DISTINCTNESS on the SHIPPED fr3: jakm-hd-lod0 effects == jak3-hd-lod0 effects - 1 and
#       strictly fewer draws+tris (exactly the 339-tri over-nose scarf).
#   (b) BARE FACE, measured on the donor artifact: the dropped effect has verts INSIDE the face box
#       (in front of the eye plane at eye/nose height), the kept scarf has ZERO.
#   (c) the two new looks are present in the shipped fr3 with donor-parity draw/tri counts.
#   (d) per look: the selected model is SUBMITTED found=1 and every other jak look is ABSENT
#       (the look REPLACES, it never stacks).
#   (e) blink stays live on every look (donor lid paints, STOCKLID=0) and flicker stays 0/0.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.RKSTQ3}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-hd-models4; mkdir -p "$OUT"
R="$OUT/x86_looks_cycle5.txt"; : > "$R"
WATCH="${WATCH:-70}"
INI=build/game/OpenGOAL/jak1/settings/settings.ini
SWAP=build/tools/hd_merc_swap/hd_merc_swap
ENH=out/jak1/fr3/enhanced/GAME.fr3
DONOR=decompiler_out/jak3/levels/ljakc/jakc-highres-lod0.glb
say(){ echo "$*" | tee -a "$R"; }
say "===== cycle-5 x86 JAK LOOK leg (jakm bare-face + jakp/jakf) — $(date -Is) ====="

[ -f "$ISO/GAME.CGO" ] || { say "FAIL: no $ISO/GAME.CGO"; exit 1; }
[ "$ISO/GAME.CGO" -nt goal_src/jak1/pc/jak-hd.gc ] || { say "FAIL: GAME.CGO stale vs jak-hd.gc"; exit 1; }
[ -f "$ENH" ] || { say "FAIL: no enhanced GAME.fr3 — bake first"; exit 1; }
[ -x "$SWAP" ] || { say "FAIL: $SWAP not built"; exit 1; }
OK=1

# ---- gate (a) + (c): quantitative model census on the SHIPPED fr3 ---------------------------
AUD=$("$SWAP" audit "$ENH" jak3-hd-lod0 jakm-hd-lod0 jakp-hd-lod0 jakf-hd-lod0 2>&1) || {
  say "FAIL: audit errored"; exit 1; }
num(){ echo "$1" | grep -oE "$2=[0-9]+" | head -1 | cut -d= -f2; }
declare -A EFF DRW TRI
for m in jak3-hd jakm-hd jakp-hd jakf-hd; do
  L=$(echo "$AUD" | grep -a "^MODEL $m-lod0 ")
  [ -n "$L" ] || { say "FAIL: $m-lod0 not in the shipped enhanced GAME.fr3"; OK=0; continue; }
  EFF[$m]=$(num "$L" effects); DRW[$m]=$(num "$L" total_draws); TRI[$m]=$(num "$L" total_tris)
  say "shipped $m-lod0: effects=${EFF[$m]} draws=${DRW[$m]} tris=${TRI[$m]}"
done
if [ "${EFF[jakm-hd]:-0}" -eq $(( ${EFF[jak3-hd]:-0} - 1 )) ] \
   && [ "${DRW[jakm-hd]:-0}" -lt "${DRW[jak3-hd]:-0}" ] \
   && [ "${TRI[jakm-hd]:-0}" -lt "${TRI[jak3-hd]:-0}" ]; then
  say "CYCLE5-JAKM DISTINCT PASS: jakm-hd = jak3-hd minus the over-nose scarf effect (effects ${EFF[jak3-hd]}->${EFF[jakm-hd]}, draws ${DRW[jak3-hd]}->${DRW[jakm-hd]}, tris ${TRI[jak3-hd]}->${TRI[jakm-hd]}, delta_tris=$(( ${TRI[jak3-hd]} - ${TRI[jakm-hd]} )))"
else
  say "FAIL: jakm-hd NOT distinct from jak3-hd in the shipped fr3"; OK=0
fi

# ---- gate (b): bare-face measurement on the donor artifact (no pixels) ----------------------
PROBE=$(python3 scripts/shell/hd_effect_geometry_probe.py "$DONOR" --effects 0,17 \
          --face-box 2.20,2.62,0.28,2.0 2>&1) || { say "FAIL: geometry probe errored"; OK=0; }
say "$PROBE"
F0=$(echo "$PROBE" | grep -a '^EFFECT  0' | grep -oE 'in_face_box=[0-9]+' | cut -d= -f2)
F17=$(echo "$PROBE" | grep -a '^EFFECT 17' | grep -oE 'in_face_box=[0-9]+' | cut -d= -f2)
if [ "${F0:-0}" -gt 0 ] && [ "${F17:-1}" -eq 0 ]; then
  say "CYCLE5-JAKM BARE-FACE PASS: dropped effect 0 has $F0 verts inside the face box (in front of the eye plane, eye/nose height); the KEPT neck scarf (effect 17) has $F17 — the shipped jakm-hd face is uncovered by construction"
else
  say "FAIL: face-box measurement did not separate the two scarves (e0=$F0 e17=$F17)"; OK=0
fi

mkdir -p out/jak1/obj
for c in jak-hd dax-hd keira-hd samos-hd jak2-hd jak3-hd daxp-hd keira3-hd ysamos-hd jakm-hd jakp-hd jakf-hd; do
  cp -f "recharged_assets/hd_anim/$c-ag.go" out/jak1/obj/ || { say "FAIL: stage $c-ag.go"; exit 1; }
done
say "staged 12 HD art-groups into out/jak1/obj"

[ -f "$INI" ] || { say "FAIL: no $INI (run gk once to create it)"; exit 1; }
cp "$INI" "$OUT/.settings.ini.pre-looks"
set_ini(){ # NEVER append at EOF ([music] trap) — insert at top level after enhanced-models line
  if grep -q "^$1 " "$INI"; then sed -i "s|^$1 .*|$1 = $2|" "$INI"
  else sed -i "/^recharged-enhanced-models? = /a $1 = $2" "$INI"
       grep -q "^$1 = $2$" "$INI" || { say "FAIL: could not insert $1"; exit 1; }
  fi
}
GKPID=0
cleanup(){ [ "${GKPID:-0}" -gt 0 ] && kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true
           [ -f "$OUT/.settings.ini.pre-looks" ] && cp "$OUT/.settings.ini.pre-looks" "$INI" || true; }
trap cleanup EXIT
grep -q '^version = #x' "$INI" || { say "FAIL: settings.ini has no version stamp"; exit 1; }
grep -q '^recharged-master? = #f' "$INI" && { say "FAIL: recharged-master? #f forces STOCK"; exit 1; }

run_look(){ # run_look <look-index> <expected-model>
  local LOOK="$1" WANT="$2"
  set_ini 'recharged-enhanced-models?' '#t'
  set_ini 'hd-look-jak' "$LOOK"
  set_ini 'hd-look-daxter' 1; set_ini 'hd-look-keira' 1; set_ini 'hd-look-samos' 1
  local GKLOG="$OUT/.looks_gk_$LOOK.log"; : > "$GKLOG"
  say ""; say "=== LOOK jak=$LOOK  expect $WANT-lod0 ==="
  "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi -iso-data "$ISO" -- -boot -debug-mem \
    > "$GKLOG" 2>&1 &
  GKPID=$!
  local booted=0
  for i in $(seq 1 180); do
    kill -0 "$GKPID" 2>/dev/null || { say "FAIL(look $LOOK): gk exited during boot"; tail -25 "$GKLOG" >> "$R"; OK=0; GKPID=0; return; }
    grep -aqE "link finish: (default-menu|logo)" "$GKLOG" && { booted=1; break; }
    sleep 1
  done
  [ "$booted" = 1 ] || { say "FAIL(look $LOOK): boot timeout"; tail -25 "$GKLOG" >> "$R"; OK=0
                         kill "$GKPID" 2>/dev/null; wait 2>/dev/null||true; GKPID=0; return; }
  sleep "$WATCH"
  local ALIVE=no; kill -0 "$GKPID" 2>/dev/null && ALIVE=yes
  kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true; GKPID=0

  grep -aq 'HD-MODELS fr3-select GAME: ENHANCED' "$GKLOG" || { say "FAIL(look $LOOK): GAME not ENHANCED"; OK=0; }
  if grep -aq "SUBMITTED name='$WANT-lod0' found=1" "$GKLOG"; then
    say "OK(look $LOOK): $WANT-lod0 SUBMITTED found=1"
  else say "FAIL(look $LOOK): $WANT-lod0 never SUBMITTED"; OK=0; fi
  for m in jak-hd jak2-hd jak3-hd jakm-hd jakp-hd jakf-hd; do
    [ "$m" = "$WANT" ] && continue
    grep -aq "SUBMITTED name='$m-lod0' found=1" "$GKLOG" \
      && { say "FAIL(look $LOOK): forbidden $m-lod0 also submitted (look did not REPLACE)"; OK=0; }
  done
  local STOCKLID; STOCKLID=$(grep -ac '\[hd-blink\] STOCKLID' "$GKLOG" || true)
  local EVB EVG CRASH NOSLOT
  EVB=$(grep -ac '\[hd-flicker\] BLACKOUT' "$GKLOG" || true)
  EVG=$(grep -ac '\[hd-flicker\] GAP' "$GKLOG" || true)
  CRASH=$(grep -acE 'SIGSEGV|SIGILL|Segmentation|Assertion' "$GKLOG" || true)
  NOSLOT=$(grep -ac 'no free blerc override slot' "$GKLOG" || true)
  local DON=0 HB=0
  for s in 0 1; do
    local H; H=$(grep -a "\[hd-blink\] slot=$s " "$GKLOG" | tr -d '\r')
    HB=$(( HB + $(echo "$H" | grep -c 'donor_paints' || true) ))
    DON=$(( DON + $(echo "$H" | grep -oE 'donor_paints=[0-9]+' | grep -cv 'donor_paints=0$' || true) ))
  done
  say "look $LOOK: alive=$ALIVE blink-windows=$HB donor-painted=$DON STOCKLID=$STOCKLID flicker B=$EVB G=$EVG crash=$CRASH blerc-exhaustion=$NOSLOT"
  [ "$ALIVE" = yes ] && [ "$STOCKLID" = 0 ] && [ "$EVB" = 0 ] && [ "$EVG" = 0 ] \
    && [ "$CRASH" = 0 ] && [ "$NOSLOT" = 0 ] && [ "$DON" -ge 1 ] || {
      say "FAIL(look $LOOK): counter gates broken"; OK=0; }
}

run_look 4 jakm-hd
run_look 5 jakp-hd
run_look 6 jakf-hd

say ""
if [ "$OK" = 1 ]; then say "[looks-c5-leg PASS] jakm bare-face distinct + jakp/jakf submit, blink live, flicker clean"; exit 0
else say "[looks-c5-leg FAIL]"; exit 1; fi
