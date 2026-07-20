#!/usr/bin/env bash
# gda_sunon_coherence_capture.sh — attempt-5 proof that the NEW ADDITIVE sun composite is COHERENT.
# Owner (playtest): sun-OFF relief ACCEPTED; but the WIP sun looked "bizarre" (the old screen blend
# base+(1-base)*sun re-flattened the relief to a flat albedo on the lit side as the sun saturated).
# The fix: true additive  lit = albedo*base + albedo*sun_color*sun_scalar  (C1 soft-shoulder tonemap).
#
# This is OUT-OF-BOX: the ambient MODEL/contrast/strength debug props are CLEARED, so the shipped GOAL
# defaults (SH model 1, strength 0.2, contrast 1.0) drive — exactly what a fresh download renders.
# The ONLY knob is RTL_SUNELEV (owner-sanctioned sun on/off), which gates the DIRECT sun term only.
#   oob_sunoff2  sunelev 0 -> ambient only: the accepted relief (must survive the composite change)
#   oob_sunon2   sunelev 1 -> additive sun ON: brighter lit side, relief PRESERVED, clean terminator
#   oob_stock2   rt.light 0 -> stock baked (OFF==stock ref)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44
CAP=.autoport/gda_capture.sh
export RTL_POS="${RTL_POS:--112.0 42.0 205.0}"   # owner sage-wall hut: curved wall => VERTICAL faces at every azimuth
export RTL_HOUR="${RTL_HOUR:-8}"
export AO_MODE=0                                   # AO OFF: relief must come from the ambient, not AO
export RTL_DEBUG_MODE=''                           # DEFAULT colored render — NOT the dbg viz (owner ban)

echo "clearing ambient MODEL/contrast/strength props => shipped GOAL defaults drive (out-of-box)..."
"$ADB" -s "$S" shell "setprop debug.opengoal.rt.ambientmodel ''"    </dev/null || true
"$ADB" -s "$S" shell "setprop debug.opengoal.rt.ambientcontrast ''" </dev/null || true
"$ADB" -s "$S" shell "setprop debug.opengoal.rt.ambientstrength ''" </dev/null || true
"$ADB" -s "$S" shell "setprop debug.opengoal.rt.flatnormal 0"       </dev/null || true
echo "  ambientmodel='$("$ADB" -s "$S" shell getprop debug.opengoal.rt.ambientmodel | tr -d '\r')' (empty => GOAL default SH=1)"

run(){ # name LIGHT SUNELEV
  local name="$1" light="$2" sun="$3"
  echo; echo "==================== STAGE $name (light=$light sunelev=$sun MODEL/CONTRAST/STR=DEFAULT-out-of-box) ===================="
  # RTL_AMBIENTMODEL / RTL_AMBIENTCONTRAST / RTL_AMBIENTSTR intentionally UNSET => shipped defaults.
  RTL_LIGHT="$light" RTL_AMBIENT="1" RTL_SUNELEV="$sun" bash "$CAP" still "$name" || { echo "[coh FAIL] $name"; return 1; }
}

run oob_sunoff2  1 0 || exit 1   # ambient-only: accepted relief must survive
run oob_sunon2   1 1 || exit 1   # ADDITIVE sun ON: the coherence money shot
run oob_stock2   0 0 || exit 1   # realtime OFF => stock baked (OFF==stock)
echo; echo "[coh] out-of-box sun on/off coherence stages captured."
