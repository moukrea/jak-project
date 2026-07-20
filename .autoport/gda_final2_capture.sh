#!/usr/bin/env bash
# gda_final2_capture.sh — OUT-OF-BOX proof after the SH-default + floored-gain build.
# The shipped default ambient model is now SH (gfx.h + pckernel-impl.gc = 1). This capture does NOT
# override the ambient MODEL (the stale debug.opengoal.rt.ambientmodel prop is CLEARED first, so the
# GOAL default SH drives the render) => the frames show exactly what a fresh download renders. sunelev=0
# is the owner-sanctioned sun-OFF test knob (isolates the ambient); contrast/strength are left at the
# shipped defaults (0.9 / 0.2) too. Only the flat-A/B stage overrides contrast to 0.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB="${ADB:-/home/emeric/Android/platform-tools/adb}"
S=eae4df44
CAP=.autoport/gda_capture.sh
export RTL_POS="${RTL_POS:--112.0 42.0 205.0}"
export RTL_HOUR="${RTL_HOUR:-8}"
export AO_MODE=0
export RTL_DEBUG_MODE=''

# CLEAR the model/contrast/strength debug props so the shipped GOAL defaults drive (out-of-box).
echo "clearing stale ambient debug props (out-of-box: shipped SH default must drive)..."
"$ADB" -s "$S" shell "setprop debug.opengoal.rt.ambientmodel ''" </dev/null || true
"$ADB" -s "$S" shell "setprop debug.opengoal.rt.ambientcontrast ''" </dev/null || true
"$ADB" -s "$S" shell "setprop debug.opengoal.rt.ambientstrength ''" </dev/null || true
echo "  getprop ambientmodel='$("$ADB" -s "$S" shell getprop debug.opengoal.rt.ambientmodel | tr -d '\r')' (empty => GOAL default SH)"

run(){ # name  LIGHT AMBIENT SUNELEV [CONTRAST]
  local name="$1" light="$2" amb="$3" sun="$4" con="${5:-}"
  echo; echo "==================== STAGE $name (light=$light amb=$amb sunelev=$sun contrast=${con:-DEFAULT} model=DEFAULT-SH) ===================="
  # NOTE: RTL_AMBIENTMODEL and RTL_AMBIENTSTR intentionally UNSET => shipped GOAL defaults (SH, 0.2).
  if [ -n "$con" ]; then
    RTL_LIGHT="$light" RTL_AMBIENT="$amb" RTL_SUNELEV="$sun" RTL_AMBIENTCONTRAST="$con" bash "$CAP" still "$name" || { echo "[final2 FAIL] $name"; return 1; }
  else
    RTL_LIGHT="$light" RTL_AMBIENT="$amb" RTL_SUNELEV="$sun" bash "$CAP" still "$name" || { echo "[final2 FAIL] $name"; return 1; }
  fi
}

run oob_sunoff     1 1 0        || exit 1   # shipped SH default, SUN OFF => the out-of-box form money shot
run oob_sunoff_c0  1 1 0 0.0    || exit 1   # SUN OFF, contrast 0 => the flat "before" A/B (no azimuthal term)
run oob_sunon      1 1 1        || exit 1   # SUN ON => sun ADDS light on top (golden-rule ref)
run oob_off_stock  0 1 0        || exit 1   # realtime OFF => stock baked (OFF==stock ref)
echo; echo "[final2] out-of-box stages captured."
