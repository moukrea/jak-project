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

## SUPERVISOR CORRECTION 2 (owner 2026-07-20 ~02:10, FURIOUS) — the PIVOT above is WRONG, IGNORE IT. KEEP FULL REALTIME LIGHTING.
The "baked as indirect" PIVOT section above is REVOKED. Owner: "on abandonne PAS le realtime lighting."
The goal is a FULL realtime lighting pipeline that stands on its own and BEATS the baked look — NOT falling
back to baked as a crutch. Do NOT use baked as the indirect. Do NOT revert to stock-baked-look for the
shadowed areas.

STAY THE COURSE, within full realtime (no baked crutch):
- KEEP: realtime direct sun (per-face N.L) + dynamic cast shadows + night sun-fade + distance/quality/menu.
- KEEP the OWNER'S REQUESTED PATH: continue the computed directional ambient ladder — hemisphere -> SH
  (L1/L2 irradiance from the mood sky) -> IBL (prefiltered sky env, diffuse irradiance). These are REALTIME/
  computed ambient (no baked), which is exactly the full-realtime vision. The Hemisphere/SH/IBL selector in
  Recharged Settings stays.
- The FLAT-SHADOW problem is real and must be solved WITHIN realtime. AO was a false lead (contact-only, no
  model relief — confirmed). SH/IBL give richer directional ambient than the flat hemisphere; if that is
  still not enough form on flat surfaces, the realtime answer is SCREEN-SPACE DIRECTIONAL occlusion / GI
  (SSDO / SSGI) — directional bounce that sculpts form, unlike plain uniform AO — NOT baked, NOT plain AO.
  Investigate SSDO/SSGI as the realtime form-giver if SH/IBL alone falls short, and report the honest
  assessment.
- Golden rule on any occlusion (ambient only, never the direct sun). OFF==stock byte-identical.
ACCEPTANCE (unchanged bar): full realtime lighting ON looks BETTER than stock baked at a shadowed vantage —
achieved with a REALTIME/computed ambient (hemisphere/SH/IBL [+SSDO/SSGI if needed]), NEVER by using the
baked as the indirect. Owner eye gates.

## SUPERVISOR ROOT-CAUSE + DEFINITIVE MANDATE (2026-07-20 ~02:30) — the flat look = FLAT PER-FACE NORMALS, fix = SMOOTH VERTEX NORMALS
Owner wants this done like contemporary engines, a killer feature, cheap on modest HW + scalable to high.
SUN ONLY for now (night later). No baked when realtime ON (baked=!realtime); OFF==stock. Golden rule.

ROOT CAUSE (supervisor-verified in code, this is the research result — confirm + build on it):
- Static world tfrag3.vert has attributes position(0)/tex_coord(1)/time_of_day(2) — NO per-vertex normal.
  So the realtime shading synthesizes a normal via screen-space derivative cross(dFdx,dFdy) (tfrag3.frag:94)
  = a FLAT PER-FACE normal (faceted). On any curved surface (rounded huts, terrain, models) this looks FLAT
  in shadow — direct AND ambient — because the normal does not vary smoothly across the surface. THIS is
  why "3D in shadow looks flat"; it is NOT an AO or ambient-color problem.
- Actors: merc2.vert:5 HAS `normal_in` (per-vertex, bone-skinned) — real smooth normals exist for characters.
- Jak is a PS2 game: it BAKED lighting into vertex colors instead of storing normals for static geometry —
  that is why the normals are missing and why the baked looks good (it encodes the smooth light transport).

THE CHEAP FIX (what every engine does, ~15yr-old-cheap, runs on modest HW):
1. RECONSTRUCT SMOOTH PER-VERTEX NORMALS for the static world (tfrag + tie). Compute offline in the asset
   pipeline (preferred, one-time) OR at load: for each mesh, accumulate adjacent FACE normals at each shared
   vertex position (angle/area-weighted), normalize -> smooth vertex normals. Handle UV/material seams
   (weld by position). Add the normal as a new vertex attribute (tfrag3.vert location 3, tie equivalent).
2. USE the smooth interpolated normal for the realtime N.L direct + the ambient (replace the screen-
   derivative flat normal in tfrag3/etie/shrub/tie_wind). Curved surfaces regain smooth relief.
3. VERIFY actors: ensure the merc realtime sun path uses normal_in (smooth) — if actors also read flat, wire
   normal_in. Characters must have relief in shadow too.

TIERED AMBIENT (owner's ladder — all using the smooth normals; a selector in Recharged Settings):
- LOW (modest HW default): smooth normals + hemisphere ambient (sky-up/ground-down by normal).
- MID: SH ambient (L1/L2 irradiance from the mood sky), richer directional.
- HIGH: IBL (prefiltered procedural sky env, diffuse irradiance by normal).
- BONUS/TOP (optional, gated for strong HW): SSDO / SSGI — screen-space DIRECTIONAL occlusion/GI that adds
  bounce-driven form. Only if the owner wants the high end; NOT the cheap default.
Each tier is a visible step up; low tier must run on modest HW and already give relief (thanks to the smooth
normals). Owner eye picks the default.

REAL RESEARCH REQUIRED (delegate to autoport-researcher; report findings before/with implementation):
- The best smooth-normal reconstruction for jak's tfrag/tie data (angle-weighted, seam welding, where in the
  pipeline: decompiler/asset-build vs runtime loader). Confirm actors already have usable normals.
- Contemporary-engine ambient structure (SH probes vs hemisphere vs IBL) and the cheap/scalable tiering, so
  our tiers mirror how "the greats" do it.
- Honest cost assessment per tier on Adreno 618 (Redmi, modest) vs Snapdragon 8 Elite (Honor, strong).
ACCEPTANCE: with smooth normals, curved shadowed MODELS/geometry show RELIEF (not faceted/flat) even at the
LOW tier on the Redmi; realtime-ON beats stock baked at a shadowed vantage; SH/IBL are visible step-ups;
sun-only; OFF==stock; golden rule. Device A/B: flat-per-face-normal (before) vs smooth-normal (after), and
realtime-ON vs stock-baked. Owner eye gates. This is the killer feature — do it properly.

## OWNER REMINDER (2026-07-20) — EVERYTHING DISABLEABLE, EXACT ORIGINAL GRAPHICS WHEN OFF (as always)
Non-negotiable: realtime-lighting OFF (or the --pbr flag absent) => the render is BYTE-IDENTICAL to stock,
the exact original graphics. Subtle point given we now RECONSTRUCT smooth vertex normals + add a vertex
attribute: the reconstructed normals + all ambient tiers (hemisphere/SH/IBL/SSDO) must be consumed ONLY by
the realtime-lighting path. When OFF: the stock baked-vertex-color path runs untouched, the extra normal
attribute is ignored (or not uploaded), zero pixel difference vs a build without the feature. Prove OFF==
stock with the normal reconstruction present (diff ~0). The smooth-normal precompute must not alter the
shipped stock assets either (keep it in the realtime path / a separate attribute, gold READ-ONLY).

## OWNER ROUND 2 (2026-07-20 morning, Honor) — smooth-normal reconstruction ARTIFACTS + missing menu selector
Owner walked to the STONE BUILDING (the round warp-gate tower in Sandover) — evidence:
device/OWNER-artifact-stone-building.png. The stone wall shows WEIRD facets / incoherent bright & dark
zones that do NOT follow any single light direction (random-looking lit patches on the masonry, on BOTH
buildings present). Supervisor mea culpa: I verified only the rounded sage hut vantage and missed this.

DEFECT 1 — the smooth-normal reconstruction is WRONG on hard-edged geometry. It is welding/averaging
normals ACROSS SHARP EDGES (a stone block / wall corner must KEEP its distinct face normals; smoothing them
into one smears the normal in wrong directions -> the random bright/dark patches). FIX: crease-angle-aware
reconstruction — only average face normals at a shared vertex when the angle between faces is below a crease
threshold (~30-45 deg); above it, keep SEPARATE normals (hard edge). Also: angle/area-weighted averaging,
weld strictly by POSITION (not across UV/material seams incorrectly), skip degenerate/zero-area tris, and
handle the tfrag STRIP topology adjacency correctly. Validate on the STONE BUILDING + several other
buildings/props (NOT just the sage hut): the lit gradient must follow a coherent light direction with NO
random patches; hard edges stay crisp, curved surfaces stay smooth.

DEFECT 2 — the ambient-model SELECTOR is missing from Recharged Settings (owner sees only the default
hemisphere). SH and IBL exist in code (captures gda_sh/gda_ibl) but are NOT menu-selectable. WIRE the
Hemisphere / SH / IBL selector as a real Recharged-Settings row (live, persisted), so the owner can A/B the
three on device.

ACCEPTANCE (device, multiple building vantages incl. the stone tower): no random/incoherent lit patches —
lighting follows one coherent direction; hard edges crisp, curves smooth; the 3-model ambient selector works
in-menu; OFF==stock; sun-only; golden rule. Owner eye gates. Test AT the artifact location, not just the hut.

## OWNER ROUND 2 — PRIORITY: SHADOWED AREAS STILL FLAT (the core issue, NOT fixed by smooth normals)
Owner: "dans les parties à l'ombre du soleil, genre sur les rochers, ça fait toujours super plat, t'as pas
corrigé le soucis." IMPORTANT distinction: smooth normals fixed the FACETING artifact, but shadowed static
geometry (rocks, terrain, wall undersides) still looks FLAT — because in shadow the ONLY light is the
hemisphere ambient (a very low-frequency up/down-by-normal gradient) which does NOT sculpt fine form. This
is THE headline problem and it is still open. Supervisor has guessed wrong twice (AO-only; baked-as-indirect)
— so DO REAL RESEARCH before implementing, do not guess.

RESEARCH TASK (delegate to autoport-researcher, deep + honest, report findings first):
"How do contemporary AND ~2010-era game engines make SHADOWED STATIC geometry (rocks/terrain) show FORM
cheaply, WITHOUT baked lightmaps and WITHOUT expensive GI, on modest hardware?" Investigate and cost each,
then recommend a cheap default + a scalable ladder:
- SSAO/HBAO/GTAO applied to the AMBIENT term at a MODEL-SCALE radius (not tiny contact): does a medium-
  radius AO on the ambient sculpt rock form in shadow? (The shipped GTAO may currently NOT occlude the
  realtime floor — verify.) Owner felt "AO is contact only"; test whether a larger radius / proper wiring
  actually gives form. Be empirical on device.
- Richer directional ambient: higher-order SH vs hemisphere, and whether sky/ground CONTRAST (currently
  maybe too weak) is the missing bit — a strong sky-vs-ground colour delta makes the N.y gradient visibly
  sculpt form.
- The real cheap classic: is it actually a combination (medium-radius SSAO on ambient + directional
  ambient), which is what most 2010 games shipped? 
- SSDO/SSGI only as the expensive top tier.
Report: for each, the expected look + the cost on Adreno 618 (Redmi) and Snapdragon 8 Elite (Honor), then
implement the recommended CHEAP one so shadowed rocks/terrain show form on the Redmi. This is the acceptance
that matters: shadowed rocks look sculpted (form), not flat, at a shadowed vantage, cheaply — the owner's
core, repeated complaint. Prove on device at a shadowed rock/terrain spot, AO off vs on, ambient tiers.

## OWNER FOUND THE ROOT CAUSE (2026-07-20 ~06:50) — COMPOSITING ORDER: ambient is the BASE (form on every face), sun ADDS on top
This SUPERSEDES the SSAO/research-guessing for the shadowed-flatness. Owner nailed it: shadowed faces
currently get a FLAT ~0.2 floor (SAME value for every face regardless of normal) -> all faces identical ->
FLAT. Introduced when we added the ~0.2 shadow attenuation. The CORRECT model (owner's, and it is exactly
right):
  final = AMBIENT(normal)                                   // BASE — indirect, varies by normal, applied
                                                            //   to EVERY fragment ALWAYS -> form on every
                                                            //   face even with no sun
        + sun_color * max(dot(N,L),0) * cast_shadow_factor  // DIRECT — sun ADDS on top only where it
                                                            //   reaches; cast shadow removes ONLY this
                                                            //   direct term, NEVER flattens the ambient
- In shadow (sun/NdL/shadow -> 0): final = AMBIENT(normal) -> STILL varies by normal -> rock/terrain form.
  The ~0.2 becomes the ambient's MEAN, not a constant; it must VARY by normal (hemisphere/SH).
- The bug to remove: any code path that, when a fragment is in cast shadow or facing away, sets it to a
  CONSTANT floor. Replace with the normal-varying ambient term. Direct sun is ADDITIVE on top of that base.
- This is the compositing ORDER the owner intuited: indirect ambient reveals geometry first; directional
  sun + cast shadows come over it, darkening an already-present shaded base.
- Cheap: we already compute a normal-varying hemisphere; make it the ALWAYS-ON base, drop the flat floor.
  No SSAO/GI needed for this base form (AO/SSDO stay OPTIONAL bonus tiers for extra crevice/GI detail).
- Ensure enough normal-contrast in the ambient (sky vs ground colour delta) that the form is clearly
  visible on shadowed rocks/terrain, not washed to near-uniform.
ACCEPTANCE (device, shadowed rock/terrain vantage): shadowed geometry shows FORM (faces at different normals
have visibly different brightness) with the sun off/occluded — NOT a uniform flat floor. Sunlit adds on top.
OFF==stock. This is the owner's core fix; verify at the stone building + rocks, not just the sage hut.

## CLARIFICATION (owner 2026-07-20 ~07:00) — the sun ADDS light, it does NOT add shadow. Verify vs real engines.
Owner asked: does the sun add light on an already-shaded surface, or add shadow on top? ANSWER (the standard
rendering equation, forward+deferred): light is ACCUMULATED ADDITIVELY. The sun ADDS a light contribution;
it never "adds darkness."
  final = ambient(N)                              // indirect base, always present, gives form
        + sun_color * max(N·L,0) * shadow_factor  // sun's contribution, ADDED where it reaches
A cast shadow = shadow_factor -> 0 => the sun's term is simply NOT added there => that fragment has ONLY the
ambient (identical to a face turned away from the sun). Shadow is the ABSENCE of the sun's added light, NOT a
painted-on dark overlay. So a shadowed rock == ambient-only (with form); a sunlit rock == ambient + sun
(brighter + directional highlight on top). Never subtract/flatten the ambient in shadow.
REQUIREMENT: the researcher must CONFIRM this additive model against real-engine references (the rendering
equation; forward/deferred light accumulation; shadow maps multiplying ONLY the light's own term) and cite
them in the report, so our compositing matches how contemporary engines actually do it — no hand-waving.

## OWNER CLARIFICATION 2 (2026-07-20 ~07:15) — blend semantics + the ambient control is CONTRAST, not brightness
Owner (rendering-literate, correct) framed it in Photoshop blend terms; confirm + implement exactly:
1. SUNLIT = ADD / Linear Dodge of the sun term onto the ambient-shaded base: final = ambient(N) +
   sun·N·L·shadow. (Screen is a soft approximation; true light accumulation is ADD, then tone-map so the
   sunlit side doesn't blow to white.)
2. SHADOW is NOT a Multiply over the whole model. The shadow_factor multiplies ONLY the sun's own term
   (before it is added). In shadow: sun·0 = 0 -> the AMBIENT remains FULLY intact. NEVER multiply the whole
   surface / the ambient by the shadow (that would flatten the ambient relief — the exact bug). 
   => Both sunlit AND shadowed fragments KEEP their full ambient relief; sunlit just adds the sun on top,
   shadowed is ambient-only. Verify neither loses ambient form.
3. THE AMBIENT CONTROL IS CONTRAST/LEVELS, NOT A BRIGHTNESS SLIDER. The current ~0.2 is a brightness scalar
   that shifts every face equally -> adds NO form. What creates form is the CONTRAST: the spread between
   sky-lit (up-facing) and ground-lit (down-facing) ambient. Make ~0.2 the MEAN, and expose/tune the
   CONTRAST = the sky-colour-vs-ground-colour delta (the range around the mean). A strong sky<->ground
   spread makes the normal gradient visibly sculpt shadowed rocks/terrain. The Recharged-Settings control
   for the ambient should be this contrast/strength (levels), not a flat brightness. Tune it so shadowed
   geometry reads as sculpted, not washed flat.
ACCEPTANCE add: prove (a) shadowed fragment = ambient-only with full normal-varying form (no flattening),
(b) sunlit = ambient + additive sun, tone-mapped (not blown out), ambient form still visible under the sun,
(c) raising the ambient CONTRAST visibly increases shadowed-rock form (not just overall brightness).

## OWNER CLARIFICATION 3 (2026-07-20 ~07:25) — DEFINITIVE clean model: cast shadow = sun VISIBILITY, not a darkening op
Owner (correct, cleaner than the earlier "multiply" framing): the ambient IS "not directly sun-lit" and it
already carries the relief, so there is NO "shadow to apply" as a separate darkening. There is only: does
the sun reach this fragment? THE implementation must be exactly this — NOT a shadow-multiply overlay:
  sun_visible = (N·L > 0) AND (not occluded per the sun shadow-map)   // soft (PCF) at the penumbra
  final = ambient(N)  +  sun_color * N·L * sun_visible
- Sun reaches -> ambient + sun. Sun does NOT reach (away-facing N·L<=0 OR cast-shadow-occluded) -> AMBIENT
  ONLY, with full normal-varying relief. A cast-shadowed fragment and an away-facing fragment are the SAME
  state (ambient only). Unify them; do not treat cast shadow as a separate multiply/darken over the surface.
- There is NO flat floor, NO "shadow term added", NO multiply of the ambient. The ambient(N) term is the
  complete appearance of anything the sun doesn't directly hit, and it varies by normal (contrast/levels
  tunable) so it shows form.
This is the single source of truth for the compositing; the earlier "shadow multiplies only the sun term"
note is equivalent but this framing is cleaner — implement THIS. Confirm against real-engine references
(forward/deferred: sun contribution gated by NdotL and shadow visibility, added to the indirect/ambient).

## SUPERVISOR CORRECTION (2026-07-20 ~09:40, owner still sees FLAT shadows) — hemisphere can't sculpt VERTICAL surfaces; verify the REAL render, not the debug viz
Owner tested the WIP build: shadowed areas STILL flat. Two findings (verified in code):
1. My earlier "form proven" was on the dbg12 VIZ (amplified grayscale lighting fraction), NOT the DEFAULT
   colored render. The default render (tfrag3.frag: lit = albedo*(base + ...)) has the form mathematically
   but it is TOO SUBTLE. NEVER again claim the fix works from the dbg viz — verify the DEFAULT render.
2. The HEMISPHERE ambient varies ONLY by N.y (up/down): base = mix(ground, sky, N.y*0.5+0.5). VERTICAL
   surfaces (rock faces, walls — N.y~0) all get the SAME base -> FLAT no matter the contrast. The hemisphere
   fundamentally cannot sculpt vertical geometry. Also gtint={0.65,0.55,0.45} at strength 0.2 is weak.
FIX (empirical, on the DEFAULT render, at a ROCK-FACE / VERTICAL vantage on the Redmi):
- The form on ALL orientations (not just up/down) needs a FULLER directional ambient. The SH and IBL models
  vary in every direction (not just N.y) — MAKE THEM WORK and be the answer for vertical-surface form. Test
  each model (Hemisphere / SH / IBL) on the DEFAULT colored render at a vertical rock face; the SH/IBL must
  visibly give a left/right/forward gradient (form) that the hemisphere cannot. If they don't, they are
  mis-implemented — fix them.
- BOOST the ambient CONTRAST (the sky<->ground and the directional spread) so the form is clearly visible in
  the REAL render, not just the viz. Expose it as the owner's "Ambient Contrast" control (a levels/spread
  notion, not the brightness level). Default it high enough to sculpt.
- Verify: at a shadowed VERTICAL rock face on the Redmi, the DEFAULT render shows the rock's form (faces at
  different orientations visibly different) — with SH or IBL, contrast up. Capture the DEFAULT render (NOT
  dbg12) A/B: hemisphere-flat vs SH/IBL-with-form, at the rock face. Owner eye is the gate; the debug viz is
  NOT acceptable as the proof.
ACCEPTANCE OVERRIDE: the phase does NOT pass until a shadowed VERTICAL surface (rock/wall) shows visible form
in the DEFAULT colored render on the Redmi (not the viz). This is the owner's repeated core complaint.
