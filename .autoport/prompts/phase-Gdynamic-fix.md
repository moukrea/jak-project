# Phase Gdynamic-fix — dynamic render scale must seek the MAX quality that holds the target (+ runtime re-clamp)

## Why (owner 2026-07-01, TOP PRIORITY — feature is unusable as-is)
The dynamic-render-scale feature (shipped in Gdynamic-renderscale) does NOT actually work in practice.
Two concrete bugs the owner found in deeper testing:
1. **Runtime Min-Render-Scale change not applied.** With dynamic ON and the scale already dropped hard
   (e.g. to 10%, the old floor), RAISING the "Minimum Render Scale" setting (e.g. to 30%) does NOT take
   effect — the running/effective scale is not re-clamped to the new floor.
2. **The controller gets STUCK at the floor with obvious headroom.** Owner repro: a zone that, at a FIXED
   60% scale, runs ~32 fps; with dynamic ON and target = 30 fps, the scaler STAYED at the minimum (30%)
   even though 60% would still run 32 fps (≥ target, ~2-10 fps of headroom). So instead of the best
   quality that meets the target, dynamic mode gives the WORST quality. Owner's exact expectation:
   "la qualité qui s'ajuste vraiment selon la target FPS de façon constante pour garder la fluidité
   maximale dans les pires conditions (grosses scènes) au détriment de la qualité, MAIS la meilleure
   qualité possible quand le framerate le permet." = continuously converge to the HIGHEST scale in
   [min,100] such that fps stays >= target.

## Root to fix (build on the existing dynamic-scale code from Gdynamic-renderscale)
The raise logic is still too timid / not converging to the optimum — it does not climb back when fps is
comfortably ABOVE target. Likely the raise only nudges when fps is "near target" and does nothing when
fps is WAY above target (it reads "fine" and never improves quality). FIX the controller to:
 - CLIMB whenever fps is >= target with margin (or frame-time budget has clear headroom), stepping the
   scale UP toward 100% — aggressively when fps is well above target, gently near the target — until the
   scale is the HIGHEST that still holds fps >= target. Do NOT sit at the floor when fps > target.
 - DESCEND only when fps < target. Equilibrium = max scale meeting target.
 - Keep anti-thrash (smoothed fps, cooldown, bounded steps, small dead-band AT the target boundary) but
   it must actively seek the optimum, not park at the floor.
 - RE-CLAMP on setting change: when Minimum Render Scale (or target, or the ON/OFF toggle) changes at
   runtime, immediately re-clamp the effective scale into the new [min,100] range and let the controller
   re-converge.

## Verify (state-anchored + owner) — the owner's exact repro must pass
On device eae4df44: in a scene where a FIXED scale S would run above target, dynamic mode (target below
that fps) CONVERGES the scale UP to ~S (highest meeting target), NOT stuck at the floor — quantify
(e.g. target 30 in the owner's ~32fps@60% zone → scale climbs to ~60%, fps stays >= 30). Raising the
Minimum Render Scale at runtime immediately re-clamps the running scale. Still anti-thrash (bounded
adjustment cadence). Floor respected. OFF = manual. x86 builds + boots. Full CONSISTENT build,
deploy_verify PASS.

## Report (`.autoport/reports/Gdynamic-fix/report.txt`) with `RESULT: DYNAMIC SCALE SEEKS MAX QUALITY AT TARGET`
a trace showing the scale CLIMBING to the highest value holding target (not stuck at floor) in a
headroom zone; the runtime Min-Render-Scale re-clamp working; anti-thrash cadence; floor respected;
OFF=manual; x86 link finish: logo.

## Locks: ANDROID_SERIAL=eae4df44; no goalc/emitter/IGenX86_64.*; engine goal_src untouched; pc/ only goal_src; .autoport/gold READ-ONLY.
## Max: max_turns 2000, max_retries 5. device: true, owner_verify: true.
