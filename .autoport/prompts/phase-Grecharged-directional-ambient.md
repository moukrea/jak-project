# Phase Grecharged-directional-ambient — the "pro way" ambient (form in shadow without AO)


## PREREQUISITE FIXES (owner 2026-07-19, at realtime-lighting sign-off) — do these FIRST, they are correctness bugs
The realtime-lighting feature has two toggle bugs to fix before/with the hemisphere work:
1. REALTIME-LIGHTING OFF MUST == STOCK, BYTE-IDENTICAL. Owner: "quand on désactive le lighting dans les
   paramètres rechargés, ça revient pas à comme c'est sensé être par défaut." When realtime-lighting? is #f,
   every world shader (tfrag3/etie/shrub/tie_wind) must take the EXACT legacy baked-vertex×texture path,
   pixel-identical to a build without the feature — no residual uniforms, no leftover floor/fade/shadow
   state. Prove: realtime OFF frame == stock frame (diff ~0).
2. REMOVE the useless separate baked toggle; HARDWIRE baked = NOT realtime-lighting. Owner: "le toggle
   on/off du baked lighting sert à rien; quand on active le realtime, le baked doit être off, et il est on
   quand on désactive le realtime — exactement comme par défaut, comme si on n'avait jamais implémenté la
   feature." So: realtime ON -> baked suppressed; realtime OFF -> baked ON = stock. Delete the
   realtime-lighting-baked? setting + its menu row; drive baked purely from realtime-lighting?.
These land as part of this phase (they touch the same lighting path the hemisphere ambient does).

## WHY THIS PHASE (owner motivation)
Owner: with realtime sun-only ON, shadowed models look FLAT — "en l'état c'est moins beau que du baked
lighting." The flat ~0.2 floor is the cause. This phase's hemisphere/SH/IBL directional ambient fixes that
(form in shadow without AO), so realtime-lighting ON finally beats the baked look.

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

## OWNER ROUND 2 (2026-07-20 ~01:15) — CONTINUE the progression: SH then IBL
Hemisphere ambient landed + owner pushed to Honor to test ("continue avec SH et IBL!"). Climb the quality
ladder ON TOP of the hemisphere base (keep OFF==stock + baked=!realtime + all round-1..7 sun wins):

STAGE SH (spherical-harmonics ambient): replace/upgrade the pure hemisphere with an L1 (or L2) SH ambient
  probe — a low-frequency directional irradiance function sampled by the surface normal. Richer than a 2-
  color hemisphere (captures the sky's directional colour + a soft wrap), still per-fragment-normal, cheap.
  Drive the SH coefficients from the mood/TOD sky (so it tracks day/night; at night it collapses to the
  dark floor, no phantom lights — reuse the sun-fade discipline). PROVE: shadowed surfaces show smoother,
  richer directional form than hemisphere; sunlit unchanged (golden rule).
STAGE IBL (image-based lighting): a prefiltered SKY environment (small cubemap or a procedural sky) →
  diffuse irradiance sampled by normal (the "real PBR ambient"); optionally a low-res specular prefilter
  for the PBR-mapped materials later. Mobile-tuned (tiny cubemap, precomputed/refreshed on TOD change, not
  per-frame). PROVE: the ambient reads as coming from the actual sky (sky-tinted top, ground-tinted bottom,
  environment colour), best-looking of the three; still golden-rule (ambient only) + tracks TOD + no night
  leak.
Expose a QUALITY selector for the ambient model (Hemisphere / SH / IBL) in Recharged Settings (like the
shadow quality tiers), so the owner can A/B the three on device. Each tier is a visible step up in the
shadowed-area richness. Ship whichever the owner's eye prefers as default (start Hemisphere, prove the climb).
ACCEPTANCE: on device, the three ambient models are selectable and each is a visible improvement in
shadowed-model form/richness; sunlit byte-identical across all three (golden rule); OFF==stock; tracks
day/night with no phantom night lights. Owner's eye gates which becomes default.

## OWNER ROUND 2 ADDENDUM — the RELIEF comes from AO, not the ambient color (owner: hemisphere "donne rien niveau relief, ça éclaircit seulement")
Owner tested hemisphere on Honor: it only BRIGHTENS shadowed areas, gives no relief (correct — a hemisphere
modulates by coarse normal up/down; on a wall N.y~0 so it's ~uniform = brighten, not sculpt). Also asked if
our realtime lighting is "mal foutu vs modern engines" — supervisor verdict: NO, the sun-only path (per-face
N.L + shadow map) is standard/sound; what's missing to match modern engines is the AMBIENT+AO pipeline,
which is this phase.

DECISION (supervisor, owner delegated "à toi de voir"): relief in shadow = AMBIENT OCCLUSION, not the
ambient color model. Root cause found: the SHIPPED, owner-validated GTAO (AmbientOcclusion.cpp, golden-rule
composite `out=dst-(1-dst)*k*(1-ao)`, ambient-fraction masked, strength 0.35) was calibrated for the BAKED
ambient; with realtime-lighting ON (our floor replacing baked) the GTAO does NOT occlude our floor (the
ambient-fraction mask / composite doesn't cover the realtime floor) -> AO ON adds no relief. DO NOT build a
new Form-AO (owner rejected that). Instead:
- WIRE the existing shipped GTAO to occlude the REALTIME-LIGHTING ambient/floor term: ensure the realtime
  floor writes/participates in the ambient-fraction mask so the GTAO post-process darkens the occluded
  fragments of the realtime shadowed areas. When realtime-lighting ON + AO ON, shadowed crevices/undersides
  get darker => relief. Golden rule preserved: AO darkens only the ambient (the floor), never the sunlit
  direct term (sunlit unchanged). Keep the shipped AO's independence (it still works standalone on stock).
- SH/IBL (this round) still add ambient RICHNESS/colour; the GTAO adds the RELIEF. Together = the pro combo.
ACCEPTANCE add: realtime-lighting ON + shipped AO ON -> shadowed surfaces show occlusion RELIEF (crevices/
undersides darker), not just a uniform brighten; AO OFF -> the flat brighten (current); sunlit byte-identical
(golden rule); AO still works standalone with realtime OFF (stock). Prove on device with AO on/off A/B at a
shadowed vantage.

## SUPERVISOR PIVOT (owner 2026-07-20 ~02:00 — I was WRONG about AO; corrected) — INDIRECT = the BAKED GI, not a synthetic floor
Owner (correct, I erred): AO is contact-only, gives NO model relief; real games (even ~10yr old) with
realtime lighting + AO OFF are NOT flat; the realtime sun is cool but the flat shadowed models make it
still uglier than the original BAKED. Root cause (correct this time): the FORM in shadowed areas comes from
INDIRECT light (bounce/GI). In games it is BAKED (lightmaps / SH probes). Jak's baked VERTEX colors ARE its
GI — rich per-location light transport (gradients, darker recesses, form). Our flat/hemisphere floor THREW
THAT AWAY -> flat. Synthetic ambient (hemisphere / SH / IBL from the sky) is a WORSE approximation than the
real baked lightmap for STATIC geometry -> a downgrade. Baked looks better because baked IS the good indirect.

PIVOT — abandon the synthetic-ambient path for the static world. The correct model (what pros do, and what
we had at realtime-lighting round-3 that the owner approved "OK ça fonctionne mieux"):
  final = BAKED (as the INDIRECT/ambient term, carrying GI/form) + REALTIME DIRECT (sun N.L * cast-shadow).
- INDIRECT/ambient = the game's BAKED per-vertex lighting (keep it, it is the GI — do NOT replace it with a
  flat floor / hemisphere / SH / IBL). This restores all the shadowed-area FORM the owner misses.
- DIRECT = the realtime sun (per-face N.L, cast shadow map, night sun-fade) added ON TOP — the moving sun +
  dynamic shadows the baked lacks. Calibrate so it does not double-dose (baked already contains some sun):
  scale the realtime direct and/or use the baked as pure indirect fill; tune at the owner vantage so lit
  faces read like sun and shadowed faces keep the baked form (NOT flat, NOT double-bright).
- DROP the hemisphere floor + the SH/IBL synthesis for the world (they are inferior to baked here). SH/IBL
  stay POTENTIALLY relevant ONLY for DYNAMIC actors that lack baked lighting — DEFER that, it is niche.
- Keep: OFF==stock byte-identical, baked=!realtime hardwire is REVISED (baked is now USED as indirect when
  realtime ON), the sun-only wins (shadows/night-fade/distance/quality/menu), golden rule on any AO.
ACCEPTANCE: realtime-lighting ON now looks BETTER than stock baked (owner's bar) — shadowed models keep the
baked FORM/richness AND gain the moving realtime sun + dynamic cast shadows; no flat areas; no double-dose;
sunlit reads as sun; OFF==stock. Device A/B: realtime-ON vs stock-baked at a shadowed vantage, owner eye.
This supersedes the hemisphere/SH/IBL headline above for the STATIC world.
