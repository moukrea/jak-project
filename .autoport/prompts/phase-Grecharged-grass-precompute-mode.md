# Phase Grecharged-grass-precompute-mode — PRECOMPUTED (day-cycle-baked) grass for perf, same fidelity

## Owner request (2026-07-11, backlog after grass-poc) + CORRECTION
Original: "tu penses que ça peut valoir le coup de tout pre-calculer en aval pour économiser du
processing en jeu (placement, teinte, shading/lighting) etc avec un toggle... soit le pre-calculé,
soit du live plus coûteux ?"
CORRECTION (2026-07-11, verbatim): "T'as pas compris pour le lighting l'idée c'est que ce soit baked
sans recalcul tout au long de la journée, pas une seule fois, comme ça l'est nativement pour le jeu !
L'idée c'est de gagner de la perf tout en gardant la fidélité of course, sinon ça serait débile."

## KEY IDEA (do NOT re-misread this)
The GAME's own tfrag ground lighting is NOT computed live — it is BAKED for the DAY CYCLE (multiple
time-of-day states, interpolated at runtime). The precompute mode must do the SAME for the grass:
bake the per-instance grass lighting for the WHOLE DAY CYCLE (N time-of-day keyframes, matching how
the engine stores/interpolates the tfrag baked light), then at runtime just LOOK UP + interpolate the
two nearest keyframes by current time-of-day. This is NOT freezing at one time — it KEEPS FULL DAY-
CYCLE FIDELITY (identical look to the live mode) while replacing the per-update live tfrag sampling
with a cheap precomputed lookup. Goal: gain perf WITHOUT losing fidelity. Freezing at one time would
be a downgrade and is NOT the ask.

## Scope
Precompute OFFLINE (a build step, per level; start with the training level), bake into asset data:
1. PLACEMENT (instance positions) — skip the at-load geometry scan.
2. Per-instance TINT / SIZE / ORIENTATION / CURVATURE — skip the at-load hashing.
3. LIGHTING as DAY-CYCLE KEYFRAMES per instance — bake the baked-ground colour under each blade at N
   time-of-day steps (same day states the engine bakes the tfrag for). Runtime = pick current time,
   interpolate the 2 nearest baked keyframes. Cheaper than live tfrag sampling, SAME result.
Load the baked blob straight into the instance buffer. Storage cost is bounded (N small keyframes ×
instances) — report the asset size.

## Toggle (GRASS SETTINGS nested submenu)
"GRASS MODE" = PRECOMPUTED (baked day-cycle, cheaper, SAME fidelity) / LIVE (computes at load+runtime;
needed for levels not yet baked, and for dev). PRECOMPUTED should be the preferred mode for baked
levels. Persisted. OFF (grass off) still == stock.

## Verify (device eae4df44) — perf gain WITH fidelity
- PRECOMPUTED vs LIVE at the SAME spot + SAME time-of-day look IDENTICAL (A/B, no visual difference);
  cycle the time-of-day in PRECOMPUTED and confirm it STILL varies correctly (not frozen).
- PRECOMPUTED measurably cheaper: report fps (higher) + load-time (lower) vs LIVE on device.
- deploy_verify + deploy_verify_assets PASS; force-stop after tests.

## Report (.autoport/reports/Grecharged-grass-precompute-mode/report.txt) RESULT: GRASS PRECOMPUTE MODE <verdict>
bake format (placement/tint + N-keyframe day-cycle lighting), the toggle, per-mode fps + load-time on
device, PROOF precomputed keeps day-cycle fidelity (time-of-day still varies), asset-size cost,
device captures both modes at 2 times-of-day.
## Locks: ANDROID_SERIAL=eae4df44 only; engine goal_src untouched; gold READ-ONLY; force-stop after tests.
## Max: max_turns 3000, max_retries 6. device: true, owner_verify: true.
