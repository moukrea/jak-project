# Phase Gcollision-systemic — pervasive arm64 collision divergence (ROOT cause, not per-site)

## The defect (owner verification, 2026-06-27)
Playing the shipped build, collision is broken **EVERYWHERE** on arm64 (x86 is fine):
- clipping THROUGH walls; jumps under the map.
- near objects/edges: either Jak is **launched far** OR **stuck crouched in place**.
- **invisible walls** / must-jump to advance on visibly FLAT ground.
- the blue-eco zone sometimes **ejects Jak off the cliff** (intermittent).
Owner's read (correct): *"bet it's related with the ARM conversion."* This is a **SYSTEMIC** arm64
collision-math divergence, NOT another per-spot bug.

## Lead — find the ROOT, not more symptoms
The earlier per-site collision fixes (`can-exit-duck?` #f-guard in collide_cache.cpp; collide_edge_grab;
FMA `-ffp-contract=off`; the ledge **`vftoi0`** float→int fix in Gledge-glitch) each patched ONE symptom.
The ledge fix is the smoking gun: an arm64 **float↔int conversion** (PS2 VU0 `vftoi0/4/12/15`, `vitof*`,
and the ftoi/itof codegen) is almost certainly wrong **pervasively** across the collision pipeline —
collision uses fixed-point grid math + float→int everywhere, so one wrong conversion mode (rounding vs
truncate-toward-zero, fixed-point scale, saturation/overflow) corrupts normals/penetration/positions
everywhere → clip, eject, under-map, invisible walls. Investigate the WHOLE conversion family + any other
systemic arm64 float op (FMA contraction across ALL collide TUs not just the 5; VU0 min/max/clip; rounding
mode; denorm/FTZ) — find the ONE (or few) root ops that diverge.

## Method (mandatory) — x86-first, SYSTEMIC, translation-layer, goal_src 1-to-1
1. **Unit-diff the collision math x86 vs arm64** across a LARGE input sweep (the model: Gcollision-arm's
   FMA fix went 2422/60000 → 0/60000). Run the collide_* mips2c TUs + the vftoi/vitof/ftoi conversions on
   both backends over many inputs; the systemic bug shows as MANY diffs. Localize the diverging op(s).
2. **Name the root** arm64 conversion/codegen op (e.g. vftoi truncation/scale/rounding, an FMA TU missed
   by the earlier fix, a VU0 op). State WHY it breaks collision broadly.
3. **Reproduce in-game + state-anchored confirm:** drive Jak (cpad_inject, or replay an owner demo via the
   Ginput-replay harness) into the symptom spots (a wall clip, an edge eject, the blue-eco ledge,
   an under-map jump) and dump the collision STATE (normals, penetration, resulting velocity/position) on
   x86 vs device — anchored on the deterministic LOGICAL/control state (NOT render frames). The first
   divergent value must trace back to the same root.
4. **Regression-check** the recent collision fixes — keep them fixed; if one is over-broad, narrow it.
5. **Fix the ROOT in the translation layer** (mips2c collide TUs / goalc arm64 codegen of the conversion),
   so arm64 collision == x86. NO game-logic rewrite ([[porting-1to1-fix-in-translation-layers]]).
   Owner eye = final.

## Validator (`phase-Gcollision-systemic.sh`) PASS requires
1. `.autoport/reports/Gcollision-systemic/report.txt` with `RESULT: ARM COLLISION MATCHES X86 (SYSTEMIC)`:
   the unit-diff sweep BEFORE (many diffs) → AFTER (0 diffs) with counts; the named root conversion/codegen
   op; the state-anchored x86-vs-device confirm on **≥3 distinct symptom scenarios** (e.g. wall-clip,
   edge-eject, under-map) BEFORE(diverges)→AFTER(==x86); the regression-check documented.
2. goal_src 1-to-1 (or documented pristine revert); real translation-layer change; fix-summary
   `.autoport/reports/Gcollision-systemic-fix-summary.md` ≥60 lines; temp instrumentation removed;
   `.autoport/gold` pristine; x86 `link finish: logo`; `deploy_verify.sh eae4df44` PASS.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; .autoport/gold READ-ONLY; keep device awake. After any failing device run, `bash .autoport/restore_knowngood_device.sh`.
## Max: max_turns 1800, max_retries 5.
