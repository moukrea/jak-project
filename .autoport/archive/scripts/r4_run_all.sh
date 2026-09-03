#!/usr/bin/env bash
# r4_run_all.sh — drive the full Grecharged-realtime-lighting ROUND 4 device proof set.
# Assumes the round-4 android-arm64 --pbr build is already installed + deploy-verified.
# Each line sets the per-shot props via env and invokes the proven r4 capture engine.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
CAP=.autoport/r4_rtl_capture.sh
OUT=.autoport/reports/Grecharged-realtime-lighting/device
PROOF="$OUT/device_proof_round4.txt"
: > "$PROOF"   # fresh round-4 proof log
echo "ROUND-4 device proof — build $(git rev-parse --short HEAD) — $(date -Is)" >> "$PROOF"
echo >> "$PROOF"

SAGE="-112.0 42.0 205.0"     # owner sage-hut vantage (clear caster + terminator)
DIST="80 15 -10"             # village1-hut open vantage (distant geometry + shrubs)

run(){ echo ">>> $*"; env "${ENVV[@]}" bash "$CAP" "$@" || echo "  [WARN] shot $2 failed (continuing)"; }

# ---- Re-affirm the round-1..3 criteria on the FRESH round-4 build ----
# crit 1: sun-side lit / opposite dark (terminator), default Med 2048 / dist 150.
ENVV=(RTL_POS="$SAGE" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0);                 run shot base_h8
# crit 3: h8 vs h16 -> lit + cast shadow flip to the opposite side.
ENVV=(RTL_POS="$SAGE" RTL_HOUR=16 RTL_LIGHT=1 RTL_BAKED=0);                 run shot flip_h16
# crit 5 / OFF==stock: feature off = stock baked look (A/B baseline).
ENVV=(RTL_POS="$SAGE" RTL_HOUR=8  RTL_LIGHT=0 RTL_BAKED=0);                 run shot off
# no-ambient: N.L viz -> opposite side is genuinely 0 (black), no fill.
ENVV=(RTL_POS="$SAGE" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_DEBUG_MODE=1); run shot noambient_ndl
# crit 4: 360 orbit -> lit/dark + cast shadow pinned to geometry (KEEPS mp4).
ENVV=(RTL_POS="$SAGE" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0);                 run orbit orbit_h8

# ---- Round-3 defect A + Round-4 item #2 (far = baked crossfade, distant still shaded) ----
# defect A: a DISTANT object beyond the shadow zone (dist=20) must STILL be sun-lit/dark-shaded
# AND read coherent (baked crossfade), not flat/unshaded.
ENVV=(RTL_POS="$DIST" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_DIST=20);      run shot defectA_distant_dist20
ENVV=(RTL_POS="$DIST" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_DIST=20 RTL_DEBUG_MODE=1); run shot defectA_ndl_viz
# item #2 A/B: dist=150 (default, huge sun zone) vs dist=20 above -> crossfade boundary moves.
ENVV=(RTL_POS="$DIST" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_DIST=150);     run shot farbaked_dist150

# ---- Round-4 item #3 (anti-pixelation) ----
# distant cast shadow at Very Low 512 must be SMOOTH (shadowviz dbg=12 shows the shadow term).
ENVV=(RTL_POS="$DIST" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_RES=512  RTL_DIST=150 RTL_DEBUG_MODE=12); run shot antipixel_vlow512_viz
ENVV=(RTL_POS="$DIST" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_RES=512  RTL_DIST=150); run shot antipixel_vlow512_beauty

# ---- Round-4 item #4 (5 tiers) — extremes A/B (shadowviz) ----
ENVV=(RTL_POS="$SAGE" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_RES=512  RTL_DEBUG_MODE=12); run shot tier_vlow_512_viz
ENVV=(RTL_POS="$SAGE" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_RES=8192 RTL_DEBUG_MODE=12); run shot tier_vhigh_8192_viz

# ---- Round-3 defect B (shrub cast + receive) ----
ENVV=(RTL_POS="$DIST" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_DIST=90);      run shot shrub_render
ENVV=(RTL_POS="$DIST" RTL_HOUR=8  RTL_LIGHT=1 RTL_BAKED=0 RTL_DIST=90 RTL_DEBUG_MODE=12); run shot shrub_shadowviz

echo
echo "=== ROUND-4 proof log ==="
cat "$PROOF"
echo
echo "=== stills produced ==="
ls -la "$OUT"/r4_*.png "$OUT"/r4_*.mp4 2>/dev/null
