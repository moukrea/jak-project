# Phase Grecharged-directional-ambient — the "pro way" ambient (form in shadow without AO)

## Owner mandate (2026-07-19, chose Option B after the flat-floor discussion)
Realtime-lighting shipped a FLAT ~0.2 sky-fill floor, so shadowed areas look flat. Owner (correct): modern
games keep shadowed parts non-flat EVEN WITH AO OFF because the AMBIENT ITSELF IS DIRECTIONAL, not a
constant. This phase makes the floor directional. Golden rule (from the AO saga): ambient only darkens/
shapes the ambient term, NEVER touches direct-sun-lit surfaces.

## Progression (start cheap, prove, climb)
1. HEMISPHERE AMBIENT (do first — cheap, huge gain, uses the per-face normal we already compute):
   floor = lerp(ground_color, sky_color, saturate(N.y*0.5+0.5)) * floor_strength.
   Sky_color = the up-hemisphere (sky) tint, ground_color = the down bounce; both driven by the mood/TOD
   env so they track the day cycle (sky brightens at noon, warms at dusk, dark at night — consistent with
   the round-6 night sun-fade). A surface facing up is lit by sky, facing down by ground bounce -> shadowed
   surfaces regain FORM with AO completely OFF. PROVE: a shadowed object shows top-lit/bottom-dark shape,
   AO off.
2. SH / LIGHT-PROBE ambient (next): low-frequency directional ambient (L1/L2 spherical harmonics) sampled
   by normal — softer, richer than a pure hemisphere; optionally per-region probes.
3. IBL (best): prefiltered sky environment map, diffuse irradiance sampled by normal (+ specular later).
   Real PBR ambient.

## Integration / rules
- Replaces the flat constant floor in the realtime-lighting sun-only path (the ~0.2 becomes this directional
  term). Direct sun + cast shadows + Form-AO all stay; this only reshapes the ambient/floor.
- Golden rule: sunlit surfaces unchanged; this shapes ONLY the not-in-direct-sun term. Prove sunlit A/B
  identical.
- Tracks the day/night cycle via the mood/TOD sky/ambient colors (no phantom night lights — reuse the
  round-6 night handling: at night the sky term is dark, not mood spotlights).
- Toggle/strength in Recharged Settings; OFF==stock; flag-gated. Mobile-tuned.
- AFTER this: other light sources / colored bounce / multi-light (the deferred richer system).

## Acceptance (device)
Shadowed surfaces show directional FORM (top-lit / underside-dark) with AO OFF; sunlit areas byte-identical
on/off (golden rule); the sky/ground ambient tracks the TOD cycle; no phantom night lights; toggle+strength
live in menu. Owner's eye gates. Owner RE-SCOPES at phase start — start with hemisphere and climb only if he
wants SH/IBL.

## Locks / budget
ANDROID_SERIAL=eae4df44 only; engine goal_src 1:1 (renderer/pc/shaders); gold READ-ONLY; force-stop after
device windows. Reserve last third for deploy+capture+report; write report EARLY (RESULT: WIP if not done).
max_turns 3500, max_retries 6. device: true, owner_verify: true.
