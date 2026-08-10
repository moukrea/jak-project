#!/usr/bin/env bash
# hdeye_gap_x86_leg.sh — Grecharged-hd-eye-scale ROUND 2, x86 leg. CODE-LEVEL ONLY, no image.
#
# The owner's symptom is a DISTANCE: "les deux yeux se TOUCHENT". So the instrument reports, per
# frame and per model, the minimum vertex-to-vertex distance between the LEFT eye cloud and the
# RIGHT eye cloud, read off the very vertices Merc2 is about to upload — i.e. after blerc, on both
# the raw field and the damped one.  Three legs:
#
#   legHD    enhanced models ON, shipped params (blerc_gain from the data file).
#            raw_gap_min = what the owner's current build does;  gap_min = what the fix does.
#   legSTOCK enhanced models OFF. sidekick-lod0, jak1's own model: the reference the HD eye must
#            not be more exaggerated than. raw == out here by construction (no HD model on screen).
#   legOPEN  enhanced models ON with blerc_gain=1.0 pushed from DATA. Negative control: the damping
#            must go away entirely (gap_min == raw_gap_min), proving the knob is the knob and that
#            legHD's difference is not some other edit.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$(ls /run/user/1000/.mutter-Xwaylandauth.* 2>/dev/null | head -1)}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-hd-eye-scale; mkdir -p "$OUT"
R="$OUT/x86_eyegap.txt"; : > "$R"
SETT=build/game/OpenGOAL/jak1/settings/settings.ini
PARAMS=recharged_assets/physics_chains.txt
WARP="${WARP:-village1-hut}"; WPOS="${WPOS:--130.5 34.5 202.4}"
WATCH="${WATCH:-110}"
say(){ echo "$*" | tee -a "$R"; }
say "===== Grecharged-hd-eye-scale ROUND 2 x86 eye-gap leg — $(date -Is) ====="
say "HEAD=$(git rev-parse --short HEAD)  gk=$(stat -c %y "$GK" 2>/dev/null)"

[ -x "$GK" ] || { say "FAIL: no $GK"; exit 1; }
[ -f out/jak1/fr3/enhanced/GAME.fr3 ] || { say "FAIL: enhanced GAME.fr3 missing"; exit 1; }
[ -f "$SETT" ] || { say "FAIL: no settings.ini at $SETT"; exit 1; }
mkdir -p out/jak1/obj
for c in jak dax keira samos; do
  cp -f "recharged_assets/hd_anim/$c-hd-ag.go" out/jak1/obj/ || { say "FAIL: stage $c-hd-ag.go"; exit 1; }
done

SETT_BAK="$OUT/.gap.settings.ini.bak"; cp -f "$SETT" "$SETT_BAK"
PARAMS_BAK="$OUT/.gap.physics_chains.txt.bak"; cp -f "$PARAMS" "$PARAMS_BAK"
restore_all(){ cp -f "$SETT_BAK" "$SETT" 2>/dev/null || true; cp -f "$PARAMS_BAK" "$PARAMS" 2>/dev/null || true; }
trap 'kill "${GKPID:-0}" 2>/dev/null; restore_all' EXIT
set_enhanced(){
  grep -q '^recharged-enhanced-models? = #[tf]$' "$SETT" || { say "FAIL: enhanced-models key not found"; return 1; }
  sed -i "s/^recharged-enhanced-models? = #[tf]$/recharged-enhanced-models? = #$1/" "$SETT"
  grep -q "^recharged-enhanced-models? = #$1\$" "$SETT" || { say "FAIL: could not set enhanced=#$1"; return 1; }
}
set_gain(){ # $1 = "shipped" | "off"  (off = on=0, i.e. every eye cap disabled -> jak1 raw)
  if [ "$1" = shipped ]; then cp -f "$PARAMS_BAK" "$PARAMS"; return 0; fi
  sed -E "s/^on=1( gainup=)/on=0\1/" "$PARAMS_BAK" > "$PARAMS"
  grep -qE "^on=0 gainup=" "$PARAMS" || { say "FAIL: could not set on=0"; return 1; }
}

run_leg(){ # $1 leg  $2 gklog  $3 enhanced(t|f)  $4 gain  $5 trace(0|1)
  local leg="$1" gklog="$2" enh="$3" gain="$4" trace="$5"
  : > "$gklog"
  set_enhanced "$enh" || return 1
  set_gain "$gain" || return 1
  say "[$leg] enhanced=#$enh blerc_gain=$gain warp=$WARP trace=$trace"
  local envtrace=()
  [ "$trace" = 1 ] && envtrace=(OG_EYEGAP_TRACE=1)
  env "${envtrace[@]}" OG_LEVEL_WARP="$WARP" OG_LEVEL_WARP_POS="$WPOS" \
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
  say "[$leg] warped; watching ${WATCH}s"
  local t=0
  while [ "$t" -lt "$WATCH" ]; do
    kill -0 "$GKPID" 2>/dev/null || { say "[$leg] FAIL: gk died during watch at ${t}s"; tail -25 "$gklog" >> "$R"; return 1; }
    sleep 5; t=$((t+5))
  done
  kill "$GKPID" 2>/dev/null; wait "$GKPID" 2>/dev/null
  say "[$leg] --- geometry seen ---"
  grep -a '\[eyegap\] geom' "$gklog" | sort -u | while read -r l; do say "  ${l#*\[eyegap\] }"; done
  say "[$leg] --- last heartbeat per model ---"
  grep -a '\[eyegap\] model=' "$gklog" | awk '{for(i=1;i<=NF;i++) if($i ~ /^model=/) m=$i; L[m]=$0} END{for(k in L) print L[k]}' \
    | sort | while read -r l; do say "  ${l#*\[eyegap\] }"; done
  say "[$leg] eyescale PARAMSRC: $(grep -a 'PARAMSRC=' "$gklog" | tail -1 | sed 's/.*\[eyescale\] //')"
  return 0
}

ok=1
run_leg legHD    "$OUT/.gap_hd.log"    t shipped 1 || ok=0
run_leg legSTOCK "$OUT/.gap_stock.log" f shipped 1 || ok=0
run_leg legOPEN  "$OUT/.gap_open.log"  t off     1 || ok=0
restore_all
say ""
say "params restored: $(cmp -s "$PARAMS" "$PARAMS_BAK" && echo yes || echo NO)"
say "settings restored: $(cmp -s "$SETT" "$SETT_BAK" && echo yes || echo NO)"
[ "$ok" = 1 ] && say "[eyegap-x86 legs COMPLETE]" || say "[eyegap-x86 legs INCOMPLETE]"
exit 0
