# Phase Grecharged-pbr-materials — REAL PBR with elegant per-material fallback (owner architecture)

## Owner design (2026-07-11, verbatim distilled)
"On sait que les images utilisées existent, on peut les extraire. Avec des logiciels et du tooling IA
dédiés, on peut en sortir tout ce qu'il faut pour en faire des matériaux PBR (par batch) -> donc les
données manquantes ne sont PAS un blocker. Fallback élégant: si un asset n'a PAS de PBR, on utilise la
texture par défaut + l'éclairage/teinte/ombre baked par-vertex comme actuellement; si l'asset A un PBR,
on y va all-in moderne. C'est pas du faux-PBR, c'est du PBR avec fallback élégant. Premier pas concret
vers un support PBR."

## KEY ENABLER (verified in engine, 2026-07-11) — the dynamic light env already exists
The mood/time-of-day system ALREADY provides a dynamic, day-cycle-interpolated light environment we can
drive PBR from — NO need to invent lights:
- `*time-of-day-context*` -> `current-sun` (mood-sun, sun direction/color), `light-group` (NINE per
  level, :inline), `title-light-group`, `sun-fade`, `light-interp` (time-of-day-h.gc:53-91).
- `update-mood-shadow-direction` (mood-tables.gc) — a per-mood SHADOW/sun DIRECTION, already authored +
  TOD-driven. This is the directional key light for PBR surfaces.
- Actors already consume `light-group` (dir0/dir1/dir2 + ambi) per-frame on their normals (lights-h.gc).
So the PBR path reuses the SAME authored mood lights the game already interpolates -> coherent with the
non-PBR world by construction.

## Architecture — per-material branch, default == stock
Each material carries a PBR flag. At shade time:
- PBR material present + toggle ON  -> MODERN path: sample albedo/normal/roughness/metal(+ORM/AO), light
  with the mood directional (current-sun / mood-shadow-direction) + ambient/sky term + the level
  light-group; IGNORE the baked vertex-color lighting for that surface (avoids the owner's double-dose).
- No PBR material (or toggle OFF)   -> LEGACY path UNCHANGED: texture x baked per-vertex TOD color, exactly
  as today. OFF everywhere == byte-identical stock.

## Offline material pipeline (batch, out of the runtime)
Extract the game textures -> AI/tooling material generation (albedo DE-LIGHT to strip baked shading;
generate normal/roughness/metal/height; pack ORM = occlusion+roughness+metal in one RGB + a normal map to
bound memory). Per-material opt-in so it scales asset-by-asset. QA/curation pass on hero assets (AI
normal/roughness from a diffuse is a GUESS: painted highlights -> fake bumps, logos/text -> bad normals).

## The REAL remaining work (honest — not blockers, but the effort/risks)
1. Runtime PBR shading path in GLES (Cook-Torrance-ish, mobile-tuned) + mood-light binding.
2. TANGENTS for world geometry (normal mapping is tangent-space): tfrag is vertex-colored (synthesize
   tangents from UVs at load/offline); tie has more per-vertex data. Actors have normals already.
3. COHERENCE at the PBR<->legacy boundary (main aesthetic risk): a PBR-relit floor next to a legacy-baked
   wall must match brightness/contrast -> calibrate the PBR response to the level's mood/exposure.
4. Alpha/transparent meshes (foliage, grass cards) — same caveat as AO; handle alpha correctly.
5. Memory/APK size — ORM packing + per-material opt-in.

## Staging (this phase = the architecture SPIKE; later phases implement)
P0 AO (queued) · P1 actor lighting + HD normal maps (actors already dynamic) · P2 PBR shading path driven
by mood lights on ONE test material/level · P3 batch material pipeline + per-material fallback flag · P4
world rollout. All toggle-gated ("PBR Materials: Off/On" in Recharged Settings), default Off == stock.

## This phase deliverable
A concrete architecture doc + a minimal PROOF: one material taken through the batch pipeline, rendered on
device via the PBR path lit by the mood sun, A/B vs the legacy baked path, with the fallback proven (a
non-PBR neighbor still renders legacy, no double-dose, boundary coherent). Report device captures ON/OFF.
## Locks: ANDROID_SERIAL=eae4df44 only; engine goal_src untouched (renderer/pc layer + assets); gold
READ-ONLY; force-stop after tests. Redmi max-settings fps informational only (see perf philosophy).
## Max: max_turns 3500, max_retries 6. device: true, owner_verify: true.
