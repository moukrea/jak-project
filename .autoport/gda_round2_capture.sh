#!/usr/bin/env bash
# gda_round2_capture.sh — Grecharged-directional-ambient ROUND 2 device proofs.
# Drives the crease-aware smooth-normal reconstruction + compositing-base ambient via the
# rt.*/tfrag.crease debug props (all read by the arm64 libgk, HEAD-verified). Captures at the
# STONE BUILDING (sage's warp-gate tower masonry) for defect-1, and the hut for shadowed form.
#
# Each call to gda_capture.sh does its own force-stop + relaunch + warp (crease is read at LEVEL
# LOAD, so a relaunch is mandatory between crease values).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

# Stone masonry vantage (sage's warp-gate tower @ ~-123 46 214; stand SE among the stone buildings).
STONE="-119.0 46.5 209.0"
# Owner sage-wall / hut vantage (curved hut + nearby rock/terrain) — for shadowed FORM.
HUT="-112.0 42.0 205.0"

run(){ echo; echo "======== $* ========"; }

# ---- DEFECT 1: crease-angle A/B at the STONE BUILDING ----
# FIX (crease=45): masonry hard edges kept crisp, curves smooth -> coherent lighting, no random patches.
run "crease FIX (45deg) — lit masonry, stone tower"
RTL_POS="$STONE" RTL_HOUR=10 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_CREASE=45 \
  bash .autoport/gda_capture.sh still crease_fix_stone
run "crease FIX (45deg) — world-normal viz (debug-2): crisp edges + smooth curves"
RTL_POS="$STONE" RTL_HOUR=10 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_CREASE=45 RTL_DEBUG_MODE=2 \
  bash .autoport/gda_capture.sh still crease_fix_stone_nrm
# ARTIFACT (crease=179): round-1 unconditional weld -> normals smeared across hard edges -> the
# random incoherent bright/dark patches the owner saw on the masonry.
run "crease WELD (179deg = round-1 artifact) — lit masonry"
RTL_POS="$STONE" RTL_HOUR=10 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_CREASE=179 \
  bash .autoport/gda_capture.sh still crease_weld_stone
run "crease WELD (179deg) — world-normal viz (debug-2): smeared across hard edges"
RTL_POS="$STONE" RTL_HOUR=10 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_CREASE=179 RTL_DEBUG_MODE=2 \
  bash .autoport/gda_capture.sh still crease_weld_stone_nrm

# ---- OWNER ROOT CAUSE: ambient BASE varies by normal (form in shadow), sun additive ----
# debug-12 = total light fraction. ambient ON: shadowed faces at different normals differ (form).
run "shadowed FORM — ambient BASE on, debug-12 (light fraction varies by normal)"
RTL_POS="$HUT" RTL_HOUR=8 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_DEBUG_MODE=12 \
  bash .autoport/gda_capture.sh still form_base_dbg12
# flat-floor A/B: the OLD constant ~0.2 floor (RTL_AMBIENT=0) -> shadowed faces uniform (flat).
run "shadowed FLAT — flat ~0.2 floor A/B (ambient off), debug-12: uniform (the bug)"
RTL_POS="$HUT" RTL_HOUR=8 RTL_LIGHT=1 RTL_AMBIENT=0 RTL_DEBUG_MODE=12 \
  bash .autoport/gda_capture.sh still form_flat_dbg12

# ---- AMBIENT MODEL TIERS (Hemisphere / SH / IBL selector) at the stone building ----
run "ambient model 0 = HEMISPHERE"
RTL_POS="$STONE" RTL_HOUR=10 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_AMBIENTMODEL=0 \
  bash .autoport/gda_capture.sh still model0_hemi_stone
run "ambient model 1 = SH (L2 irradiance)"
RTL_POS="$STONE" RTL_HOUR=10 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_AMBIENTMODEL=1 \
  bash .autoport/gda_capture.sh still model1_sh_stone
run "ambient model 2 = IBL (procedural sky env)"
RTL_POS="$STONE" RTL_HOUR=10 RTL_LIGHT=1 RTL_AMBIENT=1 RTL_AMBIENTMODEL=2 \
  bash .autoport/gda_capture.sh still model2_ibl_stone

# ---- OFF == STOCK at the stone building ----
run "OFF==stock — realtime lighting off (rt.light=0), stock baked render"
RTL_POS="$STONE" RTL_HOUR=10 RTL_LIGHT=0 \
  bash .autoport/gda_capture.sh still off_stock_stone

echo; echo "[gda-round2-capture] DONE — all stages captured to .autoport/reports/Grecharged-directional-ambient/device"
