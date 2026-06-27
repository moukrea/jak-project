# Phase Gledge-glitch — ledge/edge grab+fall collision glitches and "launches" Jak

## The defect (owner verification, 2026-06-27)
At borders/ledges Jak can fall off or grab onto, the collision **glitches badly and seems to PROJECT /
launch Jak** ("ça projette on dirait, c'est bizarre"). An arm64-vs-x86 collision-RESPONSE divergence at
edges (the edge-grab / wall / ledge-hang mechanic): a bad velocity / collision-normal / penetration
push-out that ejects Jak instead of grabbing or sliding cleanly. x86 does NOT do this.

## Regression check FIRST
This surfaced after the recent collision fixes. Before anything else, check whether it is a REGRESSION
from `game/mips2c/jak1_functions/collide_cache.cpp` (Gcollision-wallslide `can-exit-duck?` host-tagging),
`collide_edge_grab.cpp` (Gcrash-geyser), or the FMA `-ffp-contract=off` collide TUs — diff those vs their
pre-fix versions for any over-broad arm64 effect on the edge-grab/ledge path. If a recent fix is too
broad, narrow it (keep the original bug fixed). If not a regression, it is a residual arm64 collision
divergence — proceed.

## Method — x86-first, fix the ARM divergence in the TRANSLATION layer, goal_src 1-to-1
Reproduce at an edge (cpad_inject Jak to a ledge/border and grab/fall, or replay an owner demo). Dump the
collision-response state on x86 vs device at the edge interaction — collision normals, penetration depth,
the resulting velocity/impulse, the edge-grab/ledge-hang state floats. Name the FIRST value that diverges
(state-anchored on the deterministic logical/control state, NOT render frame). The "projection" = a
velocity/normal that is wrong on arm64 (NaN/denorm/FTZ, modulo, LDP, #f-guard, or FMA-contraction class).
Fix in the translation layer so arm64 collision-response == x86. NO game-logic rewrite
([[porting-1to1-fix-in-translation-layers]]). Owner eye = final.

## Validator PASS requires
1. `.autoport/reports/Gledge-glitch/report.txt`: `RESULT: ARM LEDGE/EDGE RESPONSE MATCHES X86` — the
   regression check documented; x86-first BEFORE(device ejects/glitches) -> AFTER(device == x86, clean
   grab/fall) with the diverging collision value named; arm64 edge-response == x86 (velocity/normal
   identical at matching control state).
2. goal_src 1-to-1 (or documented pristine revert); real translation-layer change; fix-summary
   `.autoport/reports/Gledge-glitch-fix-summary.md` ≥60 lines; temp instrumentation removed; golden
   pristine; x86 `link finish: logo`; `deploy_verify.sh eae4df44` PASS.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; .autoport/gold READ-ONLY; keep device awake. After any failing device run, `bash .autoport/restore_knowngood_device.sh`.
## Max: max_turns 1500, max_retries 4.
