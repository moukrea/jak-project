#!/usr/bin/env bash
# gda_a7_capture.sh — Grecharged-directional-ambient ATTEMPT 7 (owner playtest #3) device proof.
# Items:
#   1  GREEN SUN CASTS SHADOWS  — hour 1 (green up, yellow DOWN): shadow-map ON vs OFF. With yellow
#        below the horizon the only up light is the green sun, so any cast shadow == the green sun's.
#        The GDA-GREENSUN state-dump (debug.opengoal.rt.greendbg=1) prints shadow_light=1 (green owns map).
#   2  GREEN SUN INFLUENCES THE DAY — hour 7 (BOTH suns up): greenelev real(-1) vs forced-off(0). The
#        green directional contribution appears/disappears in daylight (A/B, real sky position).
#   4  GROUND gets the SH ambient — hour 7: model=SH default render + world-normal viz (ground normals
#        vary => it IS in the rt smooth-normal SH path, i.e. tfrag, not a flat un-lit renderer) + the
#        green/yellow cast shadow lands ON the ground (directional form).
#   OFF==stock — rt.light=0 (byte-identical stock baked path).
# Smoothness (owner-accepted à-coups fix must NOT regress with the new real-green-sun crossover): a full
# tod.fast day/night sweep at a static camera, analysed for max frame-to-frame luminance step.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
ADB=/home/emeric/Android/platform-tools/adb; S=eae4df44
CAP=.autoport/gda_capture.sh
SWEEPCAP=.autoport/gda_itemAB_capture.sh
OUT=.autoport/reports/Grecharged-directional-ambient/device
adb(){ $ADB -s $S "$@"; }
sp(){ adb shell "setprop $1 '$2'" </dev/null; }
greenlog(){ # $1 TAG -> append the GDA-GREENSUN state-dump lines for this stage
  echo "--- GDA-GREENSUN state-dump ($1) ---"
  grep -a 'GDA-GREENSUN' "$OUT/logcat_$1.log" 2>/dev/null | tail -3 || echo "  (no greendbg lines captured)"
}

export RTL_POS="${RTL_POS:--112.0 42.0 205.0}"   # owner sage-wall / hut vantage (huts + ground visible)
sp debug.opengoal.rt.greendbg 1                   # enable the green-sun elevation / shadow_light state-dump

PROOF="$OUT/a7_proof.txt"; : > "$PROOF"
echo "=== ATTEMPT 7 device proof $(date -Is) ===" >> "$PROOF"

# ---- ITEM 1: green sun casts shadows (night, hour 1) ----
export RTL_HOUR=1 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_AMBIENTMODEL=1 RTL_DEBUG_MODE=''
sp debug.opengoal.rt.greenelev -1                 # real green-sun elevation
export RTL_SHADOW=1; bash "$CAP" still a7_green_shadow_on  || echo "[a7] green_shadow_on FAILED"
greenlog a7_green_shadow_on >> "$PROOF"
export RTL_SHADOW=0; bash "$CAP" still a7_green_shadow_off || echo "[a7] green_shadow_off FAILED"
greenlog a7_green_shadow_off >> "$PROOF"

# ---- ITEM 2: green sun influences the day (hour 7, both up) ----
export RTL_HOUR=7 RTL_SHADOW=1 RTL_AMBIENTMODEL=1
sp debug.opengoal.rt.greenelev -1                 # real green-sun (ON)
bash "$CAP" still a7_green_day_on  || echo "[a7] green_day_on FAILED"
greenlog a7_green_day_on >> "$PROOF"
sp debug.opengoal.rt.greenelev 0                  # green forced OFF (A/B control)
bash "$CAP" still a7_green_day_off || echo "[a7] green_day_off FAILED"
greenlog a7_green_day_off >> "$PROOF"

# ---- ITEM 4: ground SH + world-normal viz (hour 7) ----
sp debug.opengoal.rt.greenelev -1
export RTL_HOUR=7 RTL_AMBIENTMODEL=1 RTL_DEBUG_MODE=''
bash "$CAP" still a7_ground_sh     || echo "[a7] ground_sh FAILED"        # default colored render, SH
export RTL_DEBUG_MODE=2
bash "$CAP" still a7_ground_normviz || echo "[a7] ground_normviz FAILED"  # world-normal viz (ground normals vary)
export RTL_DEBUG_MODE=''
export RTL_AMBIENTMODEL=0
bash "$CAP" still a7_ground_hemi   || echo "[a7] ground_hemi FAILED"      # hemisphere A/B on the ground

# ---- OFF==stock ----
export RTL_LIGHT=0 RTL_AMBIENTMODEL=1
bash "$CAP" still a7_off_stock     || echo "[a7] off_stock FAILED"
export RTL_LIGHT=1

# ---- Smoothness: full tod sweep (new real-green-sun crossover must stay smooth) ----
sp debug.opengoal.rt.greenelev -1
export RTL_AMBIENTMODEL=1
bash "$SWEEPCAP" sweep a7_sweep_smooth || echo "[a7] sweep FAILED"

echo; echo "[a7] captures done. proof: $PROOF"
