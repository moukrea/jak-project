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
