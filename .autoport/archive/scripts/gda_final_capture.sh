#!/usr/bin/env bash
# gda_final_capture.sh — Grecharged-directional-ambient: FINAL owner-core-gate proof after the
# floored-gain shader fix (gain 2.0 + max()0.15 floor on the azimuthal directional-ambient term).
# The SHIPPED DEFAULT (contrast 0.9, strength 0.2, hemisphere) must now show sun-OFF FORM on the
# DEFAULT colored render — the round-2 build's 0.9-no-gain was too subtle. All stages: DEFAULT render.
#
#   fin_sunoff     shipped default, SUN OFF (sunelev=0) -> lit=albedo*base(N): the money shot (FORM)
#   fin_sunoff_c0  SUN OFF, contrast 0 -> pure hemisphere = flat vertical faces (the A/B "before")
#   fin_sunon      SUN ON (sunelev=1), default -> sun ADDS light on top (golden-rule ref)
#   fin_sunoff_sh  SUN OFF, SH tier (model 1) -> the mid tier also sculpts sun-off
#   fin_off_stock  realtime OFF (light=0) -> stock baked path (OFF==stock ref)
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
CAP=.autoport/gda_capture.sh
export RTL_POS="${RTL_POS:--112.0 42.0 205.0}"   # sage-hut: curved vertical wall + cliff rock + terrain
export RTL_HOUR="${RTL_HOUR:-8}"
export AO_MODE=0                                  # AO OFF: the relief must come from the AMBIENT, not AO
export RTL_DEBUG_MODE=''                          # DEFAULT colored render (NOT the dbg viz — owner ban)
STR="${RTL_AMBIENTSTR:-0.2}"                      # shipped-default ambient strength

run(){ # name  LIGHT AMBIENT SUNELEV CONTRAST MODEL
  local name="$1" light="$2" amb="$3" sun="$4" con="$5" model="$6"
  echo; echo "==================== STAGE $name (light=$light amb=$amb sunelev=$sun contrast=$con model=$model str=$STR) ===================="
  RTL_LIGHT="$light" RTL_AMBIENT="$amb" RTL_SUNELEV="$sun" RTL_AMBIENTCONTRAST="$con" \
  RTL_AMBIENTMODEL="$model" RTL_AMBIENTSTR="$STR" \
  bash "$CAP" still "$name" || { echo "[final FAIL] stage $name"; return 1; }
}

run fin_sunoff     1 1 0 0.9 0 || exit 1
run fin_sunoff_c0  1 1 0 0.0 0 || exit 1
run fin_sunon      1 1 1 0.9 0 || exit 1
run fin_sunoff_sh  1 1 0 0.9 1 || exit 1
run fin_off_stock  0 1 0 0.9 0 || exit 1
echo; echo "[final] all stages captured."
