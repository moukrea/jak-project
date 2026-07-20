#!/usr/bin/env bash
# gda_round2_mason.sh — supplementary crease A/B framed on the tfrag STONE MASONRY exterior of the
# sage's warp-gate tower (owner's artifact structure). The main campaign's stone vantage landed
# INSIDE the tower (wood + portal); this stands SOUTH of the tower base looking N at the exterior
# masonry (matching device/OWNER-artifact-stone-building.png: ocean W/left, tower ahead/N).
# A meaningful crease A/B needs HARD-EDGED TFRAG (masonry) in frame — TIE props keep authored normals
# and are unaffected by the tfrag crease prop, so the interior wood shelves cannot show the A/B.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

MASON="-123.0 45.0 200.0"   # ~14m S of the warpgate (-123 46 214), 1m lower -> exterior masonry face

run(){ echo; echo "======== $* ========"; }

# ORBIT survey at crease=45 (the fix): Jak circles, catching the masonry from many angles; the lit
# gradient must follow ONE coherent light direction with NO random patches.
run "MASONRY orbit — crease FIX (45)"
RTL_POS="$MASON" RTL_HOUR=10 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_CREASE=45 \
  bash .autoport/gda_capture.sh orbit crease_fix_mason
# ORBIT survey at crease=179 (round-1 unconditional weld): the masonry should show the random
# incoherent bright/dark patches the owner saw.
run "MASONRY orbit — crease WELD (179 = artifact)"
RTL_POS="$MASON" RTL_HOUR=10 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_CREASE=179 \
  bash .autoport/gda_capture.sh orbit crease_weld_mason
# debug-2 normal-viz stills (matched vantage) — the definitive mechanism proof: weld smears normals
# across the block edges, fix keeps crisp steps at edges + smooth within faces.
run "MASONRY normal-viz — crease FIX (45)"
RTL_POS="$MASON" RTL_HOUR=10 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_CREASE=45 RTL_DEBUG_MODE=2 \
  bash .autoport/gda_capture.sh still crease_fix_mason_nrm
run "MASONRY normal-viz — crease WELD (179)"
RTL_POS="$MASON" RTL_HOUR=10 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_CREASE=179 RTL_DEBUG_MODE=2 \
  bash .autoport/gda_capture.sh still crease_weld_mason_nrm

echo; echo "[gda-round2-mason] DONE"
