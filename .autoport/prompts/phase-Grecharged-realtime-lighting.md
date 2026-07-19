# Phase Grecharged-realtime-lighting — SUN-ONLY realtime lighting, rewritten from scratch, minimal + correct

## Owner mandate (2026-07-19, verbatim intent — FURIOUS about the round-1..5 lighting quality)
The owner ACCEPTS "PBR Materials On/Off" as good-enough (he saw custom PBR materials render — "j'ai vu que
t'arrivais à en rendre, probablement mal mais ça fonctionne good enough"). He REJECTS the realtime lighting
ENTIRELY ("le real-time lighting, t'as tout faux, rien ne fonctionne bien du tout... t'es incroyablement
mauvais"). This phase is a COMPLETE REWRITE of the lighting, dead simple and correct.

New structure (owner's words):
- KEEP the existing "PBR Materials: On/Off" toggle as-is (material replacement system). Not this phase.
- ADD a SEPARATE "Realtime Lighting: On/Off" toggle.
- When Realtime Lighting is ON, ADD a sub-option to turn baked lighting OFF; the WORKING/DEV state is
  baked OFF ("tu désactives baked lighting everywhere, no baked lighting used, comme ça on va vraiment
  pouvoir s'occuper du lighting pour de vrai").
- REDO realtime lighting from scratch:
  * ONE light: the SUN. Its direction = the vector that places the VISIBLE sun (current-sun /
    update-mood-shadow-direction). "Tu fais venir la lumière du soleil, même si c'est un sprite je m'en tape."
  * The sun lights objects on the sun-facing side; the opposite side is in shadow (N.L, per-face normal).
  * Each object CASTS a shadow onto whatever is behind it (relative to the sun).
  * NO OTHER LIGHT SOURCES. NO ambient term. No fill, no moon, no multi-light. ONLY the sun.
  * "Comme c'est censé l'être en fait." A clean slate to build lighting on — correctness over features.

## This is a REWRITE, not a patch — STRIP the round-1..5 accretion
Delete / hard-gate-off when realtime-lighting is ON with baked OFF:
- u_pbr_ambient constant term, the multi-light light-group loop, the green-moon light, the baked-GI
  indirect blend, u_pbr_baked_weight lerp machinery. Gone from the active path.
REBUILD clean (do NOT carry the round-5 patched code forward — see SUPERVISOR CORRECTION below):
- Per-face geometric normal N.L from the visible-sun direction (camera-independent) — the Stage 1 base.
- The sun shadow map is REBUILT minimally from scratch in Stage 2 (fresh depth pass + Adreno-safe
  sampler2D + manual PCF, casters = FULL static world, camera-stable sphere-fit, contact bias). Reference
  the round-5 code only to avoid known pitfalls (Adreno HW-compare returns 1.0; bucket-order; vis-cull) —
  do not inherit it wholesale.
- PBR-mapped surfaces keep their Cook-Torrance+POM BRDF, but lit by the SAME single sun with NO ambient —
  so material and lighting are consistent (no special-casing).
The point: the ENTIRE visible world (tfrag + tie + actors) is lit by ONE sun and casts/receives ONE set of
shadows. Nothing else.

## OBVIOUS-MODEL ACCEPTANCE (hard criteria FIRST, per feedback_acceptance_obvious_first)
At a spot with a clear caster (sage hut / fence post / crate), sun pinned:
1. SUN-SIDE LIT / OPPOSITE DARK: the face toward the visible sun is bright, the away face is dark, clear
   terminator. NO ambient lifting the dark side — it is genuinely dark (measure: dark-face luminance low).
2. CAST SHADOW: the object casts a shadow on the ground/wall behind it, STARTING at its base (contact, no
   peter-panning), extending directly AWAY from the visible sun.
3. SUN-CONSISTENT: lit side + shadow direction + on-screen sun position all agree. h8 vs h16 → the shadow
   flips to the correct opposite side.
4. CAMERA-INDEPENDENT: 360° camera orbit → lit/dark sides and cast shadow stay PINNED to world geometry
   (no swim/pop/shape-change). This is the round-5 bug the owner kept seeing — it MUST be clean here.
5. BAKED OFF MEANS OFF: with the sub-option on, zero baked vertex color anywhere (prove a formerly
   baked-dark surface is now lit purely by sun N.L).
If any of 1-5 fails, the feature is not done — these are what a human checks in 10 seconds.

## Toggles / plumbing
- `realtime-lighting?` (settings.ini + Recharged Settings row). Reuse the `--pbr` build-flag family
  (simplest; document the choice) OR a `--realtime-lighting` flag — pick one, keep OFF==stock byte-identical.
- `realtime-lighting-baked?` sub-row (shown/meaningful only when realtime-lighting? is ON; dev default OFF).
- `pbr-materials?` stays independent and untouched.
- Every non-OFF path stays inside the flag; a flag-absent build is stock.

## Proof (device Redmi eae4df44, at a clear-caster vantage + the owner sage-wall vantage)
- Annotated stills: sun-side/dark-side + cast-shadow at h8 AND h16 (shadow flips).
- 360° orbit clip: lighting + shadow pinned to geometry.
- Baked-off still: a formerly-baked-dark surface now lit purely by sun.
- No-ambient measurement: shadowed side / cast shadow luminance is genuinely low.
- deploy_verify PASS, magenta 0, no sig 11/6/4, mCurrentFocus=jak1 every capture, gold pristine.
Owner's eye closes the gate. THE BAR: it looks like a real sun lighting a real world — obvious, not clever.

## Delivery / discipline
Real flow = slim APK + external custom_assets (no adb asset push as proof). Budget the session: reserve the
LAST THIRD for deploy+capture+report; write report.txt EARLY (RESULT: WIP with device evidence if not
passing, so the fingerprint reflects progress). ONE tractable correct win beats a broken everything.

## Locks / budget
ANDROID_SERIAL=eae4df44 only; no adb reboot; engine goal_src stays 1:1 (renderer / pc layer / GLES shaders
/ custom_assets only); gold READ-ONLY; force-stop after every device window.
max_turns 3500, max_retries 6. device: true, owner_verify: true.

## SUPERVISOR CORRECTION (owner 2026-07-19 01:45): do NOT inherit the round-5 shadow map — REBUILD it clean
Owner doubts "keeping" the shadow map because the round-1..5 lighting was bad. He is right about the CODE
(not the technique). Adjust the mandate:
- The shadow-MAP TECHNIQUE stays (it is the correct, cheap, standard way to cast shadows — the owner's ask;
  dropping it = no cast shadows at all). But do NOT reuse the round-5 patched implementation the owner
  never validated. REBUILD the depth pass + sampling MINIMALLY FROM SCRATCH as part of this sun-only system.
- Stage it so each half is independently correct and provable:
  STAGE 1 — DIRECTIONAL SUN SHADING (no shadow map needed): per-face N.L from the visible-sun direction,
    sun-side lit / opposite dark, NO ambient, baked OFF. This is trivially correct — land it, prove
    criteria 1 + 3 + 4 + 5, report it. A correct Stage 1 alone is a real win.
  STAGE 2 — CAST SHADOWS (fresh minimal shadow map): a clean single-cascade depth pass from the SAME
    visible-sun direction, casters = full static world, camera-stable fit, contact bias. Prove criterion 2
    (object casts a shadow at its base, opposite the visible sun) AND that it stays attributable + pinned
    under a 360 orbit. Build this ONLY after Stage 1 is solid; if the shadow map fights you, ship Stage 1
    and report Stage 2 as WIP with the exact blocker — do NOT let a broken shadow map sink the whole phase.
- Treat attributability as a first-class check: in a still, ONE shadow must visibly connect to ONE caster
  at its base. If you cannot point at a shadow and name its caster, Stage 2 is not done.
The point: a clean, minimal, CORRECT sun. No inherited complexity, no unproven code carried forward.

## OWNER ROUND 2 (2026-07-19 09:20, playtest on Honor) — the DIRECTION is validated, now PERFECT THE SUN
Owner CONFIRMS the design: sun-only for now, un-lit = genuinely BLACK is INTENDED ("c'est voulu"), ambient
(indirect/bounce) and other light sources come LATER, only once the sun is PERFECT. Do NOT add ambient or
other lights this phase. Fix the SUN's cast shadows — specific defects the owner saw:

1. SHADOW DOESN'T FOLLOW GROUND RELIEF (top priority — a correctness bug): the cast shadow looks like a
   FLAT DECAL laid on a plane, not draping over the terrain's bumps. Root cause to fix: the shadow factor
   must be computed per RECEIVER FRAGMENT at its TRUE world position (including height), i.e. a real
   per-fragment shadow-map depth compare using the fragment's reconstructed world pos — NOT a planar
   projection / flat ground-darkening. The shadow must conform to whatever surface it lands on.
2. POP IN/OUT ON APPROACH/RECEDE + BEYOND THE REALTIME ZONE: shadows appear/disappear as the camera moves
   toward/away. The shadow frustum/range has a hard boundary being crossed. Fix: (a) stabilize the range so
   normal movement doesn't cross a hard edge; (b) at the realtime-zone edge, FADE the shadow out smoothly
   (distance fade) instead of a hard cut; (c) beyond the realtime zone, fall back to something COHERENT and
   STABLE (a low-freq/pre-baked or faded approximation) so distant geometry doesn't pop. Fade, never cut.
3. NOT ALL GEOMETRY PARTICIPATES: some objects neither cast nor receive. Complete the sets — EVERY world
   caster (all tfrag + all tie categories, not a subset) writes depth; every world receiver samples. Audit
   which draw paths are missing and add them.
4. RESOLUTION PIXELATED + NO CONTROLS: add a "Shadow Quality" setting (shadow-map resolution: e.g.
   Low 1024 / Med 2048 / High 4096, mobile-safe) AND a "Shadow Distance" setting (the realtime shadow
   range). Expose both in Recharged Settings (under Realtime Lighting) + prop-tunable for headless A/B.
   Higher quality = crisper shadow edges (visible on device).

DESIGN GUARDRAILS (unchanged): ONE light = the sun. NO ambient, NO other lights, baked OFF, un-lit = black
(intended). Keep the round-1 wins (per-face N.L sun shading, sun dir = visible sun, camera-independent).

ROUND-2 ACCEPTANCE (device, owner vantage + a relief/terrain vantage):
- Walk a caster toward/away: its shadow does NOT pop in/out — it fades smoothly at the range edge.
- The cast shadow DRAPES over ground relief (follows terrain bumps, not a flat decal) — prove on a bumpy
  surface, not just the flat deck.
- Every clearly-occluding object in view has a shadow (no missing casters).
- Shadow Quality setting visibly changes edge crispness; Shadow Distance setting visibly changes range.
- Still sun-only, un-lit still black. OFF==stock.

## OWNER ROUND 3 (2026-07-19 13:10, Honor playtest — "c'est bien mieux! au moins t'as fait du progrès!")
Direction confirmed good, polishing continues. Four defects:

DEFECT A (TOP PRIORITY — a real bug the round-2 report mis-described): OUT-OF-RANGE = NO SHADING AT ALL.
  Owner: "les zones hors de portée n'ont aucun shading, un rendu 3D tout pourri sans shading dès que c'est
  pas dans la zone ombrée realtime, ça fait tâche." The round-2 report CLAIMED per-face N.L continues
  beyond the shadow zone — it DOES NOT on device. ROOT ISSUE: the directional sun N.L shading is being
  gated to the shadow ortho box / shadow range. FIX: the sun's DIRECTIONAL N.L shading (sun-side lit /
  dark-side dark) must apply to the ENTIRE WORLD, everywhere, unconditionally — it is per-face and free.
  ONLY the high-frequency CAST SHADOW (occlusion lookup) is range-limited and fades. Beyond the shadow
  range a surface must STILL be sun-lit/dark-shaded (just without a cast shadow on it). PROVE it: a distant
  object well beyond the shadow range still shows a lit side and a dark side.

DEFECT B: SHRUBS neither cast nor receive (they were "documented out"). Add shrub geometry to BOTH the
  depth/caster pass AND the receiver shading (shrub has its own shader program — extend it with the same
  sun N.L + shadow sample). Shrubs must be lit and cast/receive like the rest of the world.

DEFECT C: SHADOW RANGE TOO SHORT — the fade is "à peine quelques mètres devant Jak". Raise the DEFAULT
  shadow distance substantially (the near-field cast-shadow zone should extend well ahead, not a few
  meters), and verify the fade band lands far out, not in Jak's face. Re-check the fade math vs the range.

DEFECT D: PUT ALL SETTINGS IN THE RECHARGED-SETTINGS MENU (deferred twice as "destabilizing" — NOT
  acceptable anymore, solve the menu instability): four real menu rows —
   1. Realtime Lighting: On/Off
   2. Baked Lighting: On/Off (sub, when Realtime Lighting is On)
   3. Shadow Distance: a value/slider
   4. Shadow Quality: Low/Med/High (1024/2048/4096)
  They must be adjustable ON DEVICE via the menu (not adb), take effect live, and persist. If the jak1 menu
  widget is unstable for value rows, fix that — do not defer again.

ACCEPTANCE (device): distant object beyond shadow range is STILL sun-lit/dark-shaded (defect A); a shrub
  casts AND receives (defect B); the cast-shadow zone reaches well ahead of Jak with the fade far out
  (defect C); all 4 rows work from the in-game menu, live + persisted (defect D). Sun-only, no ambient,
  baked OFF stay. OFF==stock.

## OWNER ROUND 4 (2026-07-19 15:15, Honor playtest — "c'est vraiment pas mal je trouve!") — final sun polish
Owner pleased; these are the LAST sun refinements before moving to other light sources (owner: "fais ce
que je t'ai demandé et on pourra ENFIN passer aux autres sources de lumière, mais APRÈS!"). Four items:

1. DEFAULT SHADOW DISTANCE = 150 (was 40). Set recharged_rt_shadow_dist default to 150 m.

2. OUT-OF-RANGE FALLBACK = BAKED (revises round-3's "bare N.L far"): within the realtime shadow zone the
   surface is lit by the realtime sun + cast shadows (baked suppressed there if the baked-off toggle is
   on); BEYOND the shadow distance, CROSSFADE BACK TO THE BAKED lighting so distant areas stay coherent
   (baked carries AO/bounce/painted detail — better than bare N.L far). The baked-off toggle only
   suppresses baked INSIDE the realtime zone; the far fallback always uses baked. Smooth distance
   crossfade at the range boundary (reuse/extend the existing fade band). Result: no flat/unshaded far,
   the world reads coherently to the horizon.

3. SHADOW ANTI-PIXELATION — shadows must NEVER look pixelated in the field of view, EVER (owner emphatic).
   Distant-object cast shadows are "très très pixelisées, c'est pas beau". Add distance-aware softening:
   adaptive/wider PCF kernel that grows with shadow-map texel footprint at distance (and/or a screen-space
   blur of the shadow term), so a far caster's shadow is SMOOTH, never blocky. The requirement is absolute:
   nowhere in the FOV should a shadow edge look pixelated. Prove it on a distant caster (its shadow is
   smooth) and at Very-Low quality (still smooth, just softer).

4. QUALITY = 5 TIERS (add Very Low + Very High to the current Low/Med/High): e.g. Very Low 512 / Low 1024 /
   Med 2048 / High 4096 / Very High 8192. Very High targets strong GPUs (owner's Honor = Snapdragon 8
   Elite); guard VRAM so a weak GPU (Redmi Adreno 618) does not crash at the top tier (clamp or fail-safe).
   Update the menu Shadow Quality row to cycle all 5.

ACCEPTANCE (device): default distance 150 (visibly far); far areas fall back to baked (coherent, not flat);
NO pixelated shadow anywhere in view incl. distant casters + Very-Low tier (smooth); 5 quality tiers
selectable in the menu, each visibly different. Keep round-1..3 wins. Sun-only still (ambient/other lights
come in the NEXT phase, after this). OFF==stock.

## OWNER ROUND 5 (2026-07-19 16:20, real-world observation outside) — cast shadow must NOT be pure black + blur harder
Owner is outside looking at real sunlit shadows. Two corrections (still perfecting the sun, before other lights):

1. CAST SHADOW = PARTIAL DARKENING, NOT PURE BLACK. For testing, shadow=black was fine, but real cast
   shadows under a CLEAR SKY are only ~80-85% darker than the lit area (the shadow still receives ~15-20%
   from skylight). We have no ambient yet, so CHEAT: the cast-shadow term MULTIPLIES the surface by a
   residual factor (~0.2 = shadow keeps ~20% brightness), NOT 0. Make it a tunable "Shadow Strength" /
   opacity (default = 0.8 darkening i.e. shadow ≈ 0.2× lit, realistic clear-sky). This applies to the CAST
   SHADOW occlusion term specifically. (The N·L dark side stays as before — owner previously said un-lit
   black is intended; do NOT change that unless the owner asks. This item is about the projected shadow.)
   Real-world reference the owner asked for: direct sun ~100k lux, clear-sky shade ~10-20k lux → shadow ≈
   15-20% of lit. Default the residual to ~0.2, expose a strength control.

2. BLUR HARDER — the round-4 adaptive blur DID NOT work: distant cast shadows are STILL staircased/
   pixelated ("toujours pixelisé"). Fix it for real: widen the PCF kernel substantially, make the penumbra
   GROW with distance (a real distance-scaled soft edge), more taps / Poisson or a genuine separable blur
   on the shadow term. Owner: more blur is GOOD, it adds realism (distant-occluder shadows have wide
   penumbra). ABSOLUTE requirement (repeat): NO shadow anywhere in the FOV may look pixelated/staircased —
   prove specifically on a DISTANT caster's shadow that it is smooth, not blocky.

ACCEPTANCE: cast shadow is a soft, ~0.2-residual darkening (not black), tunable; a distant caster's cast
shadow is visibly SMOOTH (no staircase) at every quality tier. Everything else (round-1..4) preserved.
Still sun-only; ambient + other lights are the NEXT phase, after the owner signs off the sun.

## OWNER ROUND 5 CORRECTION (2026-07-19 16:45) — the ~0.2 residual is UNIFORM (away-face == cast shadow)
Owner (correct physics): a face turned AWAY from the sun is lit only by skylight, EXACTLY like a cast
shadow — so it must ALSO keep ~20% brightness, not be pure black. My earlier "N·L dark side stays black"
was inconsistent — OVERRIDE it. The residual ~0.2 is a UNIFORM SKY-FILL FLOOR applied to everything not in
direct sun:
  final = floor(~0.2) + (1 - floor) * sun_color * max(N·L, 0) * shadow_factor
  - Face toward sun, unshadowed: ~full brightness.
  - Face AWAY from sun (N·L<=0): the ~0.2 floor (NOT black).
  - In a cast shadow (shadow_factor->0): the ~0.2 floor (NOT black).
So the darkest anything gets anywhere = ~20%, consistently, whether self-shadowed (away-face) or
cast-shadowed. Nothing is pure black. This uniform floor IS the "cheat" the owner asked for; it is NOT the
full ambient/bounce/multi-light system (colored GI, per-mood ambient, other lights) — that richer ambient
is still the NEXT phase. Tie the floor to the same tunable Shadow Strength (floor = 1 - strength) so one
control governs "how dark is not-in-sun". Default strength ~0.8 -> floor ~0.2.
ACCEPTANCE update: at a vantage, the away-from-sun faces AND the cast shadows sit at the SAME ~20% level
(measure both — they should match), and nothing in view is pure black. Everything else round-1..5 preserved.

## OWNER ROUND 6 (2026-07-19 18:20, discussed) — FORM-AO on the skylight floor (relief in shadow)
Owner tested round-5 ("pas mal du tout!"). One addition: shadowed areas (the ~0.2 uniform sky-fill floor)
look FLAT — no relief. Add a WIDE-radius ambient occlusion that modulates ONLY the ~0.2 skylight floor so
shadowed surfaces regain their FORM (a surface that "sees" less sky — nooks, undersides, valleys — gets
darker; open surfaces keep the full floor). This is the LARGE-SCALE / form counterpart of the shipped
contact-AO (owner: "l'opposé de l'AO de contact, beaucoup plus large pour donner du relief à tous les
objets").

DESIGN (owner-decided):
- SEPARATE, INDEPENDENT FEATURE from the shipped standalone AO (Grecharged-ambient-occlusion: Off/SSAO/
  HBAO/GTAO + Quality + Strength). That existing AO keeps ALL its settings and MUST keep working with this
  new one OFF; this new one must work with the existing AO OFF. They are decoupled; the two scales may
  stack (contact + form) or run alone.
- OWN CONTROLS (new, in Recharged Settings under Realtime Lighting): a Form-AO On/Off toggle + a Form-AO
  Strength. (Owner: "nouveaux toggles on off, et strength pour ça, en plus du type d'AO et qualité
  actuelle" of the existing AO.)
- GOLDEN RULE (from the AO saga, non-negotiable): the Form-AO darkens ONLY the ambient/skylight floor term,
  NEVER the direct-sun-lit surfaces. Sunlit areas stay identical. Prove it: a sunlit face is unchanged
  Form-AO on vs off; only shadowed/floor-lit areas gain the occlusion form.
- Implementation left to the worker (dedicated pass or reuse): may borrow the GTAO horizon-based math
  internally, but it is its OWN toggle/path with a WIDE (form-scale, not contact-scale) radius, mobile-
  tuned, and BLURRED/denoised so it never looks noisy or pixelated (consistent with round-5's no-pixel
  requirement). Runs inside the --pbr / realtime-lighting flag.

ACCEPTANCE (device): a currently-flat shadowed object visibly regains relief/form with Form-AO on; sunlit
areas byte-comparable on/off (golden rule); the new On/Off + Strength work in the menu and are live; the
shipped standalone AO feature still works independently (test both-on, both-off, each-alone). This is the
LAST realtime-sky item; ambient/colored-bounce/other light sources remain the NEXT phase after owner sign-off.
Keep all round-1..5 wins (uniform floor, partial shadow, blur, distance 150, baked fallback, 5 tiers, menu).

## OWNER ROUND 6 ADDENDUM — NIGHT SUN-FADE (mood night-lights leaking into the sun-only path)
Owner watched the title fast day/night cycle: when the sun lights, perfect; but when the SUN IS ABSENT
(night), "3 other lighting combinations succeed each other with no sense, like spotlights turning on/off,
no visible source." ROOT CAUSE (verified in code): the realtime sun's COLOR/INTENSITY is pulled from
`*time-of-day-context* current-sun sun-color / env-color` (hud-classes-pc.gc:1688) = the MOOD system, which
at night still supplies non-zero night-mood light presets and interpolates between discrete moods -> the
"3 spotlights". And there is NO night fade (rt_intensity is a constant 1.5). Direction is the real sun
(sky-parms, below horizon at night) so it doesn't move. Net: the mood's night lights LEAK into the
sun-only path.

FIX: the realtime SUN's direct contribution must be gated by the SUN's ACTUAL ELEVATION / visibility (from
the sky-parms sun dome vector — e.g. its up-component, or the sky sun fade), NOT by the mood current-sun
presets. Sun high -> full; sun near the horizon -> smooth fade; sun BELOW the horizon (night) -> ZERO
direct sun. At night only the ~0.2 uniform floor remains => the world goes genuinely dark, NO phantom
lights, no discrete mood-light jumps. Sun-only stays pure: no visible sun = no direct light. (Sunrise/
sunset warm tint is fine as long as it is driven by the sun's own position and fades with elevation, not by
the mood night presets.) Do NOT consume current-sun/env-color as a light when the sun is down. Moonlight /
other sources are the NEXT phase.
ACCEPTANCE: run the title (or in-game) day/night cycle — as the sun sets the direct light fades smoothly to
nothing; at night the scene is the dark ~0.2 floor only, with NO spotlight-like discrete lighting appearing
from nowhere; as the sun rises it fades back in. Prove with a cycle clip (sun-up bright -> dusk fade ->
night dark/floor-only -> dawn) showing no phantom night lights.

## OWNER ROUND 7 (2026-07-19 21:50, Honor playtest) — DROP Form-AO + FIX the night leak (CRUCIAL, before any ambient)
Daytime sun = OK. Two directives:

1. DROP THE FORM-AO ENTIRELY. Owner: "le second niveau d'AO qu'on a ajouté tu peux complètement drop,
   c'est un carnage, vraiment vilain et mal foutu." REMOVE it — the round-6 Form-AO code, its shader terms,
   its On/Off + Strength toggle, its menu row. Revert to the flat uniform ~0.2 sky-fill floor as the
   baseline. (Directional ambient — hemisphere/SH/IBL — is the SEPARATE next phase Grecharged-directional-
   ambient, NOT this ad-hoc AO.) Make sure removing it does not regress round-1..5.

2. FIX THE NIGHT LEAK — TOP PRIORITY, must be clean BEFORE the ambient phase (owner: "règle ça avant
   l'hémisphère ambiant, SH/probes et IBL, c'est crucial"). At night (sun absent / below horizon) the owner
   STILL sees lit zones "as if it were day" in places — inconsistent, some geometry lit, some dark. We said
   NO light except the sun to start, so at night the ONLY thing anywhere must be the ~0.2 floor (dark).
   The round-6 night sun-fade did NOT fully work. AUDIT EVERY LIT WORLD PATH and kill every night light
   source except the floor:
   - The sun shading was extended to FOUR shaders (tfrag3.frag, etie_base.frag, shrub.frag, tie_wind.frag).
     The night sun-fade (sun elevation -> 0 at night) MUST be applied IDENTICALLY in ALL of them. A path
     that skipped it leaves its geometry (envmap tie / shrubs / wind-tie) lit at night = the "some zones lit"
     the owner sees. Verify each shader's direct-sun term goes to exactly 0 at night.
   - NO path may consume `current-sun sun-color / env-color` (the mood) as a light — that is the discrete
     night-preset leak. Drive intensity ONLY from the real sun elevation (sky-parms sun pos up-component).
   - Check for MULTIPLE sun indices (sky-parms sun 0 vs sun 1...) or any other directional term a path
     might use.
   - Ensure the floor itself has no bright/directional component at night (no Form-AO/hemisphere leaking in).
   PROVE IT: a night beat (or the fast TOD cycle) where EVERY surface in view is the dark ~0.2 floor — NO
   lit zone anywhere, across tfrag AND tie AND shrub AND envmap. Sweep the camera; nothing lights up.

Keep round-1..5 wins (uniform floor, partial shadow ~0.2, blur, distance 150, baked-far fallback, 5 quality
tiers, menu Realtime/Baked/Distance/Quality). Sun-only; ambient/other lights = next phase after owner signs
off the sun+night.
