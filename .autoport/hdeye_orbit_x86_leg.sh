#!/usr/bin/env bash
# hdeye_orbit_x86_leg.sh — Grecharged-hd-eye-scale ROUND 3, x86 leg. CODE-LEVEL ONLY, no image.
#
# The owner's ROUND 3 symptom is not an amplitude and not the inter-eye distance: it is a SEAM that
# opens. « ses eye sockets eux c'est comme avant, ce qui fait que ses yeux flottent dans le vide ».
# So the instrument publishes, per frame and per model, THE TWO FACTORS SIDE BY SIDE — the one
# applied to the eyeball (s_globe) and the one applied to the socket (s_orbit) — plus the
# eyeball-to-socket distance in four readings on the same frame:
#     seam_bind  no blerc at all                        (the defect-absent baseline)
#     seam_raw   jak1 + the donor, nothing damped
#     seam_half  eyeball damped, socket NOT             (= round 2 = the defect, on purpose)
#     seam_out   both damped                            (= round 3)
# and the prediction a coupled pair must obey: seam = seam_bind + k (seam_raw - seam_bind).
#
#   legFIX     enhanced ON, shipped params (blerc_orbit=1.0)
#   legDEFECT  enhanced ON, blerc_orbit=0.0 pushed from DATA. POSITIVE CONTROL: the socket stops
#              inheriting, the seam error must RISE, and it must land on legFIX's seam_half.
#   legSTOCK   enhanced OFF. jak1's own Daxter: the reference the HD eye may not exceed.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK=build/game/gk; ISO=out/jak1/iso
export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-$(ls /run/user/1000/.mutter-Xwaylandauth.* 2>/dev/null | head -1)}"
export SDL_VIDEODRIVER=x11 LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
OUT=.autoport/reports/Grecharged-hd-eye-scale; mkdir -p "$OUT"
R="$OUT/x86_eyeorbit.txt"; : > "$R"
SETT=build/game/OpenGOAL/jak1/settings/settings.ini
PARAMS=recharged_assets/physics_chains.txt
WARP="${WARP:-village1-hut}"; WPOS="${WPOS:--130.5 34.5 202.4}"
WATCH="${WATCH:-110}"
LEGS="${LEGS:-FIX DEFECT STOCK}"
say(){ echo "$*" | tee -a "$R"; }
say "===== Grecharged-hd-eye-scale ROUND 3 x86 socket leg — $(date -Is) ====="
say "HEAD=$(git rev-parse --short HEAD)  gk=$(stat -c %y "$GK" 2>/dev/null)"

[ -x "$GK" ] || { say "FAIL: no $GK"; exit 1; }
[ -f out/jak1/fr3/enhanced/GAME.fr3 ] || { say "FAIL: enhanced GAME.fr3 missing"; exit 1; }
[ -f "$SETT" ] || { say "FAIL: no settings.ini at $SETT"; exit 1; }
mkdir -p out/jak1/obj
for c in jak dax keira samos; do
  cp -f "recharged_assets/hd_anim/$c-hd-ag.go" out/jak1/obj/ || { say "FAIL: stage $c-hd-ag.go"; exit 1; }
done

SETT_BAK="$OUT/.orb.settings.ini.bak"; cp -f "$SETT" "$SETT_BAK"
PARAMS_BAK="$OUT/.orb.physics_chains.txt.bak"; cp -f "$PARAMS" "$PARAMS_BAK"
restore_all(){ cp -f "$SETT_BAK" "$SETT" 2>/dev/null || true; cp -f "$PARAMS_BAK" "$PARAMS" 2>/dev/null || true; }
trap 'kill "${GKPID:-0}" 2>/dev/null; restore_all' EXIT
set_enhanced(){
  grep -q '^recharged-enhanced-models? = #[tf]$' "$SETT" || { say "FAIL: enhanced-models key not found"; return 1; }
  sed -i "s/^recharged-enhanced-models? = #[tf]$/recharged-enhanced-models? = #$1/" "$SETT"
  grep -q "^recharged-enhanced-models? = #$1\$" "$SETT" || { say "FAIL: could not set enhanced=#$1"; return 1; }
}
set_orbit(){ # $1 = "shipped" | "off"
  if [ "$1" = shipped ]; then cp -f "$PARAMS_BAK" "$PARAMS"; return 0; fi
  sed -E "s/blerc_orbit=1\.0 /blerc_orbit=0.0 /" "$PARAMS_BAK" > "$PARAMS"
  grep -qE "blerc_orbit=0\.0 " "$PARAMS" || { say "FAIL: could not set blerc_orbit=0.0"; return 1; }
}

run_leg(){ # $1 leg  $2 gklog  $3 enhanced(t|f)  $4 orbit(shipped|off)
  local leg="$1" gklog="$2" enh="$3" orb="$4"
  : > "$gklog"
  set_enhanced "$enh" || return 1
  set_orbit "$orb" || return 1
  say "[$leg] enhanced=#$enh blerc_orbit=$orb warp=$WARP"
  env OG_EYEGAP_TRACE=1 OG_LEVEL_WARP="$WARP" OG_LEVEL_WARP_POS="$WPOS" \
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
  say "[$leg] eyescale params the ENGINE read: $(grep -a 'PARAMSRC=' "$gklog" | tail -1 | sed 's/.*\[eyescale\] //')"
  say "[$leg] --- eyeball geometry ---"
  grep -a '\[eyegap\] geom' "$gklog" | sort -u | while read -r l; do say "  ${l#*\[eyegap\] }"; done
  say "[$leg] --- socket geometry ---"
  grep -a '\[eyeorb\] geom' "$gklog" | sort -u | while read -r l; do say "  ${l#*\[eyeorb\] }"; done
  say "[$leg] --- per-frame summary ---"
  python3 .autoport/hdeye_orbit_summary.py "$gklog" | while read -r l; do say "  $l"; done
  return 0
}

ok=1
for L in $LEGS; do
  case "$L" in
    FIX)    run_leg legFIX    "$OUT/.orb_fix.log"    t shipped || ok=0 ;;
    DEFECT) run_leg legDEFECT "$OUT/.orb_defect.log" t off     || ok=0 ;;
    STOCK)  run_leg legSTOCK  "$OUT/.orb_stock.log"  f shipped || ok=0 ;;
  esac
done
restore_all
say ""
say "params restored: $(cmp -s "$PARAMS" "$PARAMS_BAK" && echo yes || echo NO)"
say "settings restored: $(cmp -s "$SETT" "$SETT_BAK" && echo yes || echo NO)"
[ "$ok" = 1 ] && say "[eyeorbit-x86 legs COMPLETE]" || say "[eyeorbit-x86 legs INCOMPLETE]"
exit 0
