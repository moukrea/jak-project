#!/usr/bin/env bash
# r5_run_all.sh — drive the full Grecharged-realtime-lighting ROUND 5 device proof set.
# Assumes the round-5 android-arm64 --pbr build is already installed + deploy-verified.
# ROUND-5 deliverables: (1) cast shadow = partial darkening (~0.2 residual), NOT black,
# tunable via Shadow Strength; (2) blur HARDER -> distant cast shadows smooth, no staircase.
# Also re-affirms every round-1..4 criterion on the SAME fresh round-5 build.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
CAP=.autoport/r5_rtl_capture.sh
OUT=.autoport/reports/Grecharged-realtime-lighting/device
PROOF="$OUT/device_proof_round5.txt"
: > "$PROOF"
echo "ROUND-5 device proof — build $(git rev-parse --short HEAD) — $(date -Is)" >> "$PROOF"
echo >> "$PROOF"

SAGE="-112.0 42.0 205.0"     # owner sage-hut vantage (clear caster + terminator + ground shadow)
DIST="80 15 -10"             # village1-hut open vantage (distant geometry + shrubs)

run(){ echo ">>> $*"; env "${ENVV[@]}" bash "$CAP" "$@" || echo "  [WARN] shot $2 failed (continuing)"; }

# ================= Re-affirm the round-1..4 criteria on the FRESH round-5 build =================
# crit 1: sun-side lit / opposite dark terminator (default Med 2048 / dist 150 / strength 0.8).
ENVV=(RTL_POS="$SAGE" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0);                                    run shot base_h8
# crit 3: h8 vs h16 -> lit + cast shadow flip to the opposite side.
ENVV=(RTL_POS="$SAGE" RTL_HOUR=16 RTL_LIGHT=1 RTL_BAKED=0);                                    run shot flip_h16
# crit 5 / OFF==stock: feature off = stock baked look (A/B baseline).
ENVV=(RTL_POS="$SAGE" RTL_HOUR=8  RTL_LIGHT=0 RTL_BAKED=0);                                    run shot off
# no-ambient: N.L viz -> opposite side genuinely 0 (black), no fill.
ENVV=(RTL_POS="$SAGE" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_DEBUG_MODE=1);                   run shot noambient_ndl
# crit 4: 360 orbit -> lit/dark + cast shadow pinned to geometry (KEEPS mp4).
ENVV=(RTL_POS="$SAGE" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0);                                    run orbit orbit_h8

# ================= ROUND-5 ITEM 1: partial (NOT black) cast shadow, tunable Strength =================
# default strength 0.8 -> residual 0.2: the ground cast shadow is a SOFT ~20% darkening, not black.
ENVV=(RTL_POS="$SAGE" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_STRENGTH=0.8);                   run shot shadow_partial_str08
ENVV=(RTL_POS="$SAGE" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_STRENGTH=0.8 RTL_DEBUG_MODE=12); run shot shadow_partial_str08_viz
# A/B: strength 1.0 -> residual 0.0 = the OLD pure-black cast shadow (proves the residual is real+tunable).
ENVV=(RTL_POS="$SAGE" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_STRENGTH=1.0);                   run shot shadow_black_str10
ENVV=(RTL_POS="$SAGE" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_STRENGTH=1.0 RTL_DEBUG_MODE=12); run shot shadow_black_str10_viz

# ================= ROUND-5 ITEM 2: blur HARDER -> distant cast shadow SMOOTH (no staircase) =========
# distant caster at Very Low 512 (worst case): the Poisson wide-penumbra PCF must be SMOOTH, not blocky.
ENVV=(RTL_POS="$DIST" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_RES=512  RTL_DIST=150 RTL_DEBUG_MODE=12); run shot distant_smooth_512_viz
ENVV=(RTL_POS="$DIST" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_RES=512  RTL_DIST=150);                   run shot distant_smooth_512_beauty
# distant caster at Med 2048: still smooth (wider penumbra with distance), crisper near.
ENVV=(RTL_POS="$DIST" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_RES=2048 RTL_DIST=150 RTL_DEBUG_MODE=12); run shot distant_smooth_2048_viz

# ================= Round-3/4 prior evidence on the r5 build =================
# defect A: distant object beyond the (20 m) shadow zone STILL sun-lit/dark-shaded, coherent.
ENVV=(RTL_POS="$DIST" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_DIST=20);                        run shot defectA_distant_dist20
# item #2: far = baked crossfade (dist 150, coherent to horizon).
ENVV=(RTL_POS="$DIST" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_DIST=150);                       run shot farbaked_dist150
# defect B: shrub casts + receives.
ENVV=(RTL_POS="$DIST" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_DIST=90);                        run shot shrub_render
# item #4: 5 quality tiers — extremes A/B (shadowviz).
ENVV=(RTL_POS="$SAGE" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_RES=512  RTL_DEBUG_MODE=12);     run shot tier_vlow_512_viz
ENVV=(RTL_POS="$SAGE" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_RES=8192 RTL_DEBUG_MODE=12);     run shot tier_vhigh_8192_viz

echo
echo "=== ROUND-5 proof log ==="
cat "$PROOF"
echo
echo "=== stills produced ==="
ls -la "$OUT"/r5_*.png "$OUT"/r5_*.mp4 2>/dev/null