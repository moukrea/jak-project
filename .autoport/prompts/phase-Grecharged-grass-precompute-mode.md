# Phase Grecharged-grass-precompute-mode — optional PRECOMPUTED grass mode (perf) with a toggle

## Owner request (2026-07-11, backlog after grass-poc)
"Pour une itération future, tu penses que ça peut valoir le coup de tout pre-calculer en aval pour
économiser du processing en jeu (placement, teinte, shading/lighting) etc avec un toggle
supplémentaire dans les paramètres de l'herbe pour soit utiliser le pre-calculé, soit faire du live
plus coûteux ? Pas pour tout de suite, dans le backlog juste après ce sur quoi on travaille."

## Scope + honest engineering assessment
The grass renderer (Grecharged-grass-poc) computes at LEVEL LOAD: placement (scan grass-textured
tris), per-instance tint/size/orientation/curvature (hash of position). Lighting is sampled LIVE
(per-instance ground baked colour, dynamic with time-of-day). This phase adds an OPTIONAL
PRECOMPUTED mode via a new GRASS SETTINGS toggle: "GRASS MODE: LIVE / PRECOMPUTED".

WORTH IT (do these):
1. PLACEMENT + PER-INSTANCE TINT/SIZE/ORIENT precompute -> bake into asset data (per training level),
   so the at-load geometry scan + hashing is skipped (faster load, less load-time af-spike, stable
   memory). Clear win. Store as a compact per-level instance blob loaded directly into the instance
   buffer.
NUANCED (make it a clearly-labelled sub-option, NOT the default):
2. LIGHTING precompute -> baking the baked-ground light FREEZES it at one time-of-day, so the grass
   would NOT follow the day/night cycle (visual downgrade — the exact thing Grecharged-grass-poc #8/#9
   fixed). Offer it only as a "low-end / static lighting" choice for weak hardware; the LIVE dynamic
   lighting stays the DEFAULT.

## Toggle
In GRASS SETTINGS (the nested submenu): "GRASS MODE" = LIVE (default, dynamic) / PRECOMPUTED (cheaper,
static lighting). Persisted. LIVE must be byte-identical to today's behaviour. PRECOMPUTED must load +
render correctly and MEASURABLY cheaper (report fps + load-time both modes on device).

## Verify (device eae4df44)
Both modes render on device; PRECOMPUTED shows lower load time and >= same fps (report numbers);
LIVE unchanged; toggle persists; OFF (grass off) still == stock. deploy_verify + deploy_verify_assets PASS.

## Report (.autoport/reports/Grecharged-grass-precompute-mode/report.txt) RESULT: GRASS PRECOMPUTE MODE <verdict>
placement/tint bake format, the toggle, per-mode fps + load-time numbers on device, the frozen-lighting
tradeoff documented, device captures of both modes.
## Locks: ANDROID_SERIAL=eae4df44 only; engine goal_src untouched; gold READ-ONLY; force-stop after tests.
## Max: max_turns 3000, max_retries 6. device: true, owner_verify: true.
