#!/usr/bin/env bash
# gda_sunoff_capture.sh — Grecharged-directional-ambient: the OWNER CORE GATE proof.
# "Turn the realtime SUN fully OFF; the ambient alone must SCULPT relief on every object incl VERTICAL
#  rock/wall faces, on the DEFAULT colored render (NOT the debug viz)."
#
# Method: force rt.sunelev=0 (sun off => lit = albedo*base(N)) at the sage hut. The hut's CURVED
# cylindrical wall presents vertical faces (N.y~=0) at every azimuth and is reliably framed by the
# follow-cam, so it is the ideal test of the new AZIMUTHAL ambient contrast. A/B contrast 0 vs 0.9.
#
# Stages (all DEFAULT colored render, pbr.debug=''):
#   sunoff_c0   sun OFF, contrast 0    -> flat vertical faces (the pre-fix look)
#   sunoff_c9   sun OFF, contrast 0.9  -> FORM (azimuthal gradient) = the money shot
#   sunoff_sh   sun OFF, contrast 0.9, model SH  -> the mid tier also sculpts
#   sunon_c0    sun ON (full), contrast 0    -> golden-rule reference
#   sunon_c9    sun ON (full), contrast 0.9   -> golden rule: sunlit == sunon_c0 (sun saturates bracket)
#   sunoff_orbit  sun OFF, contrast 0.9 ORBIT -> geometry-pinned moving proof
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
CAP=.autoport/gda_capture.sh
export RTL_POS="${RTL_POS:--112.0 42.0 205.0}"   # owner sage-wall hut (curved wall in frame)
export RTL_HOUR="${RTL_HOUR:-8}"                 # daytime mood colours; sunelev override kills the direct sun
export AO_MODE=0                                  # AO OFF: the relief must come from the ambient, not AO
export RTL_DEBUG_MODE=''                          # DEFAULT colored render — NOT the dbg viz (owner ban)
STR="${RTL_AMBIENTSTR:-0.3}"                      # a touch above 0.2 so the sun-off scene isn't crushed black

run(){ # name  LIGHT AMBIENT SUNELEV CONTRAST MODEL  stage
  local name="$1" light="$2" amb="$3" sun="$4" con="$5" model="$6" stage="${7:-still}"
  echo; echo "==================== STAGE $name (light=$light amb=$amb sunelev=$sun contrast=$con model=$model $stage) ===================="
  RTL_LIGHT="$light" RTL_AMBIENT="$amb" RTL_SUNELEV="$sun" RTL_AMBIENTCONTRAST="$con" \
  RTL_AMBIENTMODEL="$model" RTL_AMBIENTSTR="$STR" \
  bash "$CAP" "$stage" "$name" || { echo "[sunoff FAIL] stage $name"; return 1; }
}

# --- the owner core gate: sun OFF, contrast A/B, hemisphere (LOW tier) ---
run sunoff_c0  1 1 0   0    0  still || exit 1
run sunoff_c9  1 1 0   0.9  0  still || exit 1
# --- the ambient TIER also sculpts sun-off (SH) ---
run sunoff_sh  1 1 0   0.9  1  still || exit 1
# --- golden rule: sun ON full, contrast off vs on -> sunlit identical ---
run sunon_c0   1 1 1   0    0  still || exit 1
run sunon_c9   1 1 1   0.9  0  still || exit 1
# --- moving geometry-pinned proof of the sun-off form ---
run sunoff_orbit 1 1 0 0.9  0  orbit || exit 1
echo; echo "[sunoff] all stages captured."
