#!/usr/bin/env bash
# glp3_capped.sh — SUPERVISOR-CAPPED (~20 min) evidence set for Grecharged-lightprobes.
# Owner: 75 min of proof captures = waste; 4 core objective metrics, ONE vantage each:
#   1. interiors: int1 pair REUSED (post-deploy fresh) + int2 A/B (NPC-anchored oracle chamber)
#   2. ground checkerboard: deck ON/OFF pair -> gridfft (also feeds contrast + energy-ratio numbers)
#   3. AO flicker: one short walk clip probes ON + the OFF reference clip (same motion protocol)
#   4. moon shadow: ONE night still probes-ON -> in-image shadow/lit contrast
# Everything else (int3/int4, refl pair, model tiers, TOD sweeps, menu re-record) SKIPPED per the cap.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Grecharged-lightprobes/device
SUM="$OUT/capped_summary.txt"; : > "$SUM"
say(){ echo "== $*" | tee -a "$SUM"; }
DECK="-112.0 42.0 205.0"

say "1. interior int2 A/B (oracle chamber, village1-actors NPC anchor, hour 8, native)"
bash .autoport/glp_capture.sh b_int2_p1 1 0 1 village1-hut "86.0 18.5 17.4" 8 2>&1 | tail -6 | tee -a "$SUM"
bash .autoport/glp_capture.sh b_int2_p0 0 0 1 village1-hut "86.0 18.5 17.4" 8 2>&1 | tail -6 | tee -a "$SUM"

say "2. flat-ground deck pair (hour 8, native) — checkerboard FFT + contrast + energy"
bash .autoport/glp_capture.sh b_ctr_on  1 0 1 village1-hut "$DECK" 8 2>&1 | tail -6 | tee -a "$SUM"
bash .autoport/glp_capture.sh b_ctr_off 0 0 1 village1-hut "$DECK" 8 2>&1 | tail -6 | tee -a "$SUM"

say "3. night green-sun shadow still (hour 0, probes ON, native)"
bash .autoport/glp_capture.sh b_night_on 1 0 1 village1-hut "$DECK" 0 2>&1 | tail -6 | tee -a "$SUM"

say "4. AO-flicker walk clips (SSAO, probes ON vs OFF, deterministic motion protocol)"
bash .autoport/glp2_walk_capture.sh b_walk_p1_ao1 1 1 village1-hut "$DECK" 8 0 2>&1 | tail -4 | tee -a "$SUM"
bash .autoport/glp2_walk_capture.sh b_walk_p0_ao1 0 1 village1-hut "$DECK" 8 0 2>&1 | tail -4 | tee -a "$SUM"

say "==================== METRICS ===================="
say "-- interiors: luma + RGB (int1 reused post-deploy pair; int2 fresh)"
python3 .autoport/glp2_measure.py luma "$OUT"/frames_b_int1_p1 "$OUT"/frames_b_int1_p0 "$OUT"/frames_b_int2_p1 "$OUT"/frames_b_int2_p0 2>&1 | tee -a "$SUM"
say "-- interiors: contrast (detail preservation inside)"
python3 .autoport/glp2_measure.py contrast "$OUT"/frames_b_int1_p1 "$OUT"/frames_b_int1_p0 "$OUT"/frames_b_int2_p1 "$OUT"/frames_b_int2_p0 2>&1 | tee -a "$SUM"
say "-- deck pair: luma (energy / no blow-out) + contrast (preserved)"
python3 .autoport/glp2_measure.py luma "$OUT"/frames_b_ctr_on "$OUT"/frames_b_ctr_off 2>&1 | tee -a "$SUM"
python3 .autoport/glp2_measure.py contrast "$OUT"/frames_b_ctr_on "$OUT"/frames_b_ctr_off 2>&1 | tee -a "$SUM"
say "-- ground checkerboard FFT (ON vs OFF: no probe-added periodicity)"
python3 .autoport/glp2_measure.py gridfft "$OUT"/frames_b_ctr_on "$OUT"/frames_b_ctr_off 2>&1 | tee -a "$SUM"
say "-- night green-sun shadow contrast (probes ON; low ratio = shadow clearly visible)"
python3 .autoport/glp2_measure.py shadowcontrast "$OUT"/frames_b_night_on 2>&1 | tee -a "$SUM"
say "-- AO temporal stability on movement (probes ON vs OFF)"
python3 .autoport/glp2_measure.py flicker "$OUT"/frames_b_walk_p1_ao1 "$OUT"/frames_b_walk_p0_ao1 2>&1 | tee -a "$SUM"
# fresh top-level stills for the report evidence
CFR=$(ls "$OUT"/frames_b_ctr_on/*.png 2>/dev/null | sed -n '15p'); [ -n "$CFR" ] && cp "$CFR" "$OUT/glp3_deck_on.png"
NFR=$(ls "$OUT"/frames_b_night_on/*.png 2>/dev/null | sed -n '15p'); [ -n "$NFR" ] && cp "$NFR" "$OUT/glp3_night_on.png"
IFR=$(ls "$OUT"/frames_b_int2_p1/*.png 2>/dev/null | sed -n '15p'); [ -n "$IFR" ] && cp "$IFR" "$OUT/glp3_int2_on.png"
say "capped battery DONE"
