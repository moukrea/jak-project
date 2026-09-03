#!/usr/bin/env bash
# gda_sweep_capture.sh — sun-OFF ambient CONTRAST/STRENGTH sweep (runtime props, NO rebuild).
# Find the contrast/strength that makes sun-off ambient FORM clearly visible on the DEFAULT render.
# All stages: rt.light=1 rt.ambient=1 sunelev=0 (sun OFF => lit=albedo*base(N)), model=0 (hemisphere),
# AO OFF, DEFAULT colored render. Only contrast + strength vary.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
CAP=.autoport/gda_capture.sh
export RTL_POS="${RTL_POS:--112.0 42.0 205.0}"
export RTL_HOUR="${RTL_HOUR:-8}"
export AO_MODE=0
export RTL_DEBUG_MODE=''

run(){ # name contrast strength
  local name="$1" con="$2" str="$3"
  echo; echo "==================== SWEEP $name (sunoff contrast=$con strength=$str) ===================="
  RTL_LIGHT=1 RTL_AMBIENT=1 RTL_SUNELEV=0 RTL_AMBIENTCONTRAST="$con" RTL_AMBIENTMODEL=0 RTL_AMBIENTSTR="$str" \
  bash "$CAP" still "$name" || { echo "[sweep FAIL] $name"; return 1; }
}

run sweep_c00_s35 0.0 0.35 || exit 1
run sweep_c15_s35 1.5 0.35 || exit 1
run sweep_c25_s35 2.5 0.35 || exit 1
run sweep_c15_s20 1.5 0.20 || exit 1
echo; echo "[sweep] done."
