#!/usr/bin/env bash
# hdeye_x86_scale_leg.sh — Grecharged-hd-eye-scale x86 leg (CODE-LEVEL ONLY, no image anywhere).
#
# WHAT THIS LEG IS AND IS NOT.
# The exhaustive stock-vs-HD measurement is OFFLINE (.autoport/hdeye_anim_scan.py): jak1 only moves
# the cartoon eye-size channel inside 21 spooled cutscene animations, so no reachable gameplay scene
# can exercise its min/max. What this leg proves instead, on a running game:
#   legA  shipped params : the HD eye path is LIVE (covered>0) and the per-character anchors match
#                          the authored rest the scene actually shows (histogram mode), so the base
#                          look is not being shifted. With the shipped anchors the curve is an exact
#                          identity at rest, so changed=0 here is the CORRECT outcome.
#   legB  ARMED control  : the same scene with every per-slot rest pushed to 0.0 from DATA. The
#                          resting value is then above the anchor, so the rewrite MUST fire and MUST
#                          shrink. This is the positive control that keeps legA's zero from being
#                          vacuous — and it doubles as proof that the per-slot data knob works.
#   legC  stock          : enhanced models OFF. Coverage must be 0 and nothing may be rewritten: a
#                          stock player keeps jak1's exact channel.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$(ls /run/user/1000/.mutter-Xwaylandauth.* 2>/dev/null | head -1)}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-hd-eye-scale; mkdir -p "$OUT"
R="$OUT/x86_eyescale.txt"; : > "$R"
SETT=build/game/OpenGOAL/jak1/settings/settings.ini
PARAMS=recharged_assets/physics_chains.txt
WARP="${WARP:-village1-hut}"; WPOS="${WPOS:--130.5 34.5 202.4}"
WATCH="${WATCH:-95}"
say(){ echo "$*" | tee -a "$R"; }
say "===== Grecharged-hd-eye-scale x86 leg — $(date -Is) ====="
say "HEAD=$(git rev-parse --short HEAD)  gk=$(stat -c %y "$GK" 2>/dev/null)"

[ -x "$GK" ] || { say "FAIL: no $GK"; exit 1; }
[ -f out/jak1/fr3/enhanced/GAME.fr3 ] || { say "FAIL: enhanced GAME.fr3 missing"; exit 1; }
[ -f "$SETT" ] || { say "FAIL: no settings.ini at $SETT"; exit 1; }
mkdir -p out/jak1/obj
for c in jak dax keira samos; do
  cp -f "recharged_assets/hd_anim/$c-hd-ag.go" out/jak1/obj/ || { say "FAIL: stage $c-hd-ag.go"; exit 1; }
done
say "staged 4 HD art-groups into out/jak1/obj"

# Both the enhanced-models toggle and the eye-scale params are restored byte-for-byte at exit; the
# toggle is flipped IN PLACE on the existing key (an EOF append lands inside the last INI section
# and silently drops the tail).
SETT_BAK="$OUT/.settings.ini.bak"; cp -f "$SETT" "$SETT_BAK"
PARAMS_BAK="$OUT/.physics_chains.txt.bak"; cp -f "$PARAMS" "$PARAMS_BAK"
restore_all(){ cp -f "$SETT_BAK" "$SETT" 2>/dev/null || true; cp -f "$PARAMS_BAK" "$PARAMS" 2>/dev/null || true; }
trap 'kill "${GKPID:-0}" 2>/dev/null; restore_all' EXIT
set_enhanced(){ # t|f
  grep -q '^recharged-enhanced-models? = #[tf]$' "$SETT" || { say "FAIL: enhanced-models key not found"; return 1; }
  sed -i "s/^recharged-enhanced-models? = #[tf]$/recharged-enhanced-models? = #$1/" "$SETT"
  grep -q "^recharged-enhanced-models? = #$1\$" "$SETT" || { say "FAIL: could not set enhanced=#$1"; return 1; }
}
arm_params(){ # 1 = push every per-slot rest to 0.0, 0 = shipped file
  if [ "$1" = 1 ]; then
    sed -E 's/^(slot [0-7]) rest_iris=[0-9.]+ +rest_pupil=[0-9.]+/\1 rest_iris=0.0 rest_pupil=0.0/' \
      "$PARAMS_BAK" > "$PARAMS"
    local n; n=$(grep -cE '^slot [0-7] rest_iris=0\.0 rest_pupil=0\.0$' "$PARAMS")
    say "ARMED params: $n of 8 slot lines pushed to rest 0.0"
    [ "$n" = 8 ] || { say "FAIL: arming rewrote $n/8 slot lines"; return 1; }
  else
    cp -f "$PARAMS_BAK" "$PARAMS"
  fi
}

run_leg(){ # $1 leg  $2 gklog  $3 enhanced(t|f)  $4 armed(0|1)  $5 want(ENHANCED|STOCK)
  local leg="$1" gklog="$2" enh="$3" armed="$4" want="$5"
  : > "$gklog"
  set_enhanced "$enh" || return 1
  arm_params "$armed" || return 1
  say "[$leg] enhanced=#$enh armed=$armed warp=$WARP"
  env OG_LEVEL_WARP="$WARP" OG_LEVEL_WARP_POS="$WPOS" \
      "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
      -iso-data "$ISO" -- -boot -debug-mem > "$gklog" 2>&1 &
  GKPID=$!
  local booted=0
  for i in $(seq 1 240); do
    kill -0 "$GKPID" 2>/dev/null || { say "[$leg] FAIL: gk exited during boot"; tail -25 "$gklog" >> "$R"; return 1; }
    grep -aqE "link finish: (default-menu|logo)" "$gklog" && { booted=1; break; }
    sleep 1
  done
  [ "$booted" = 1 ] || { say "[$leg] FAIL: boot timeout"; tail -25 "$gklog" >> "$R"; return 1; }
  local w=0
  for i in $(seq 1 180); do
    kill -0 "$GKPID" 2>/dev/null || { say "[$leg] FAIL: gk died pre-warp"; tail -25 "$gklog" >> "$R"; return 1; }
    grep -aq 'LEVEL-WARP-SPAWN' "$gklog" && { w=1; break; }
    sleep 1
  done
  [ "$w" = 1 ] || { say "[$leg] FAIL: level warp never fired"; tail -25 "$gklog" >> "$R"; return 1; }
  say "[$leg] scene reached — watching ${WATCH}s with the [eyescale] counters live"
  sleep "$WATCH"
  local alive; kill -0 "$GKPID" 2>/dev/null && alive=yes || alive=no
  kill "$GKPID" 2>/dev/null || true; wait 2>/dev/null || true
  local crash; crash=$(grep -acE 'SIGSEGV|SIGILL|Segmentation|Assertion' "$gklog" || true)
  say "[$leg] gk alive at end: $alive   crash markers: $crash"
  say "[$leg] $(grep -a -m1 '\[eyescale\] PARAMSRC=' "$gklog" | tr -d '\r')"
  grep -a '\[eyescale\] anchor slot=' "$gklog" | head -8 | tr -d '\r' | sed "s/^/[$leg] /" | tee -a "$R" >/dev/null
  local sel; sel=$(grep -a -m1 'HD-MODELS fr3-select GAME' "$gklog" | tr -d '\r')
  say "[$leg] $sel"
  case "$sel" in *"$want"*) ;; *) say "[$leg] FAIL: wanted fr3-select $want"; return 1;; esac
  [ "$alive" = yes ] && [ "$crash" = 0 ] || return 1
  return 0
}

GA="$OUT/.eyescale_gk_legA.log"; GB="$OUT/.eyescale_gk_legB.log"; GC="$OUT/.eyescale_gk_legC.log"
OKA=0; OKB=0; OKC=0
run_leg legA "$GA" t 0 ENHANCED && OKA=1
run_leg legB "$GB" t 1 ENHANCED && OKB=1
run_leg legC "$GC" f 0 STOCK    && OKC=1
restore_all
say "legs reached: A(HD shipped)=$OKA  B(HD ARMED control)=$OKB  C(STOCK)=$OKC"

PASS=1
grade(){ # $1 tag  $2 log  $3 extra
  say ""; say "---- $1 ----"
  python3 .autoport/hdeye_parse.py "$2" "$1" $3 2>&1 | tee -a "$R"
  return "${PIPESTATUS[0]}"
}
[ "$OKA" = 1 ] && { grade legA-HD-shipped "$GA" ""        || PASS=0; } || PASS=0
[ "$OKB" = 1 ] && { grade legB-HD-armed   "$GB" "--armed" || PASS=0; } || PASS=0
[ "$OKC" = 1 ] && { grade legC-STOCK      "$GC" "--stock" || PASS=0; } || PASS=0

say ""
if [ "$PASS" = 1 ]; then
  say "[eyescale-x86 PASS] path live on HD slots with the authored anchors, armed control fires and"
  say "                    shrinks, stock run untouched, no crash"
  exit 0
fi
say "[eyescale-x86 FAIL]"
exit 1
