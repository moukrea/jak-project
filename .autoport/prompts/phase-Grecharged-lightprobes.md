# Phase Grecharged-lightprobes — precomputed LOCAL environment probes (the "killer" ambient/IBL system)

ultrathink. Manager designs + verifies; delegate mechanical work to sub-agents. This is a BIG, multi-round
phase — write the report EARLY and fill it as you go; reserve the last third for report + device evidence.

## OWNER DIRECTIVE (2026-07-20) — READ FIRST
The current ambient (hemisphere/SH/IBL) is GLOBAL per level → interiors are wrong, no local variation. Replace
it with precomputed LOCAL environment probes baked from the STOCK game (baked light probes / irradiance
volumes + reflection probes — the AAA-standard technique). Owner calls it "un killer truc qui change la donne".

NON-NEGOTIABLE constraints (owner, verbatim intent):
- **GO ALL IN — full quality, NOT "the simplest".** "Solo, pas AAA" meant it must be **PROGRAMMATIC/automated**
  (no manual per-level work), NOT reduced scope. It's "un remake qui déchire" → build the COMPLETE system,
  done well. Ambition high; feasibility comes from automation, not from cutting corners.
- **PROVE ON VILLAGE1 FIRST** (the starting village, `village1`). Deliver the FULL system on village1. If it
  works and the owner signs off, a follow-up rolls it out to ALL other levels "d'un bloc".
- **100% PROGRAMMATIC bake** — no hand-placed probes.
- **Capture the FULL LIT environment — INCLUDE the suns** (yellow sun, green sun, sun glow "et compagnie").
  Owner (explicit, corrected): "je veux PAS les exclure les soleils, c'est justement de les exclure qui
  fausserait tout." A probe is a real HDRI of the world AS LIT — excluding the suns leaves the surrounding
  surfaces unlit → a wrong, too-dark environment, and reflections (metal/water/Precursor) would reflect a
  dead world. So the capture is the complete lit scene, suns included.
- **NOT a 1:1 reproject of the baked as the final surface colour** (that is the "redite" to avoid). The probe
  is an ENVIRONMENT INPUT (irradiance + prefiltered radiance) to the DYNAMIC runtime pipeline (reflections/IBL,
  ambient, PBR BRDF, dynamic moving shadows, per-pixel normal-mapped detail) — the value-add over flat baked
  is the dynamic relighting + reflections + material response, NOT re-displaying baked.
- **THE DESIGN CRUX = compose WITHOUT DOUBLE-COUNTING the sun.** Since the probe already contains the suns'
  contribution, the runtime must NOT naively re-add a full analytic direct-sun on top of a full-sun probe
  (energy blow-out). Design the energy-consistent composition (e.g. the probe drives reflections + the
  ambient/environment term, while the dynamic realtime layer contributes the DELTA the baked can't: moving
  shadows, dynamic actors, PBR specular highlights, per-pixel normals) — getting this right IS "faire ça bien".
- **Effective EVERYWHERE**, with grids covering **ALL explorable HEIGHT levels** ("les bonnes infos aux bons
  endroits") — every platform/ledge/floor/roof the player can reach, plus interiors.
- Bake WITHOUT enemies/allies/player/collectibles/FX, at ALL TOD keys where the baked changes, on stock (no
  recharged mods).
- Must benefit ALL consumers, each with its own adaptation: realtime ambient, PBR, reflections on metal /
  Precursor tech / water / etc.
- **Coherent Recharged Settings menu entries** — toggle local-probe ambient, reflections on/off + quality
  tier; follow the existing selector/row conventions (greyed when parent off, clean labels), **ZERO unknown-ID
  garbage**.

## GROUNDED CODE HOOKS (verified — use these, don't reinvent)
- Sun/ambient separation (anti-redite): the mood has a SEPARATE `current-sun sun-color` / `mood-lights`
  distinct from ambient (`goal_src/jak1/engine/gfx/mood/`). Bake with the sun light-group ZEROED → indirect only.
- Interiors: levels carry `inside-box` / `inside-sphere` / `meta-inside?` volumes (`level.gc`) → auto-place a
  probe at each ROOM CENTER programmatically.
- 6-face capture: offscreen FBO infra exists (`DepthCue.cpp`, `OpenGLRenderer.cpp` glGenFramebuffers,
  `m_offscreen_mode`).
- 8 TOD keys: `time-of-day-palette` + `time-of-day-interp-colors` ("group of 8 palette fade controls",
  `goal_src/jak1/engine/gfx/mood/time-of-day-h.gc`).
- Camera teleport for the bake: `OG_LEVEL_WARP` / `debug.opengoal.level.warp` already exists.
- Baked per-vertex irradiance already in the DATA (`Tfrag3Data.h PackedTimeOfDay colors`, pre-interp, 8 TOD
  slots, tfrag/tie/shrub/HFRAG) — a cheap SEED / cross-check for the diffuse SH; the owner still wants the
  gridded spherical captures as the method, but the vertex data validates them.

## BAKE (offline tool, programmatic, on a STOCK build)
1. Stock build, recharged OFF; strip all dynamic actors (enemies/allies/player/collectibles/particles) — load
   village1 geometry + baked lighting only.
2. AUTO probe placement (village1): a 3D grid over the explorable AABB — one probe layer just above EACH
   walkable collision surface (every platform/ledge/floor/roof), PLUS volume layers for tall/open spaces, PLUS
   the center of each `inside-box`/`inside-sphere`. Collision-clip: drop probes inside solid / in the void.
3. For each probe × each of the 8 TOD keys: set the TOD and render a 6-face cubemap to an offscreen FBO of the
   FULL LIT environment — INCLUDING the suns (do NOT zero the sun light-group; the captured world must be lit).
4. Process each cubemap into: (a) L2 irradiance SH (9 coeffs × RGB) for diffuse; (b) a GGX-prefiltered
   roughness-mip cubemap for reflections, mip0 kept sharp (water/polished metal/Precursor).
5. Store a per-level probe asset (new asset type), TOD-indexed: SH grid dense, cubemaps sparse + compressed;
   shipped in the recharged asset bundle. Log the probe count + storage size.

## RUNTIME consumers (each adapted)
- **Ambient**: local probe SH (trilinear grid blend + interior-room selection) + TOD interpolation → REPLACES
  the global analytic SH with a LOCAL one (analytic SH = fallback where no probe). Fixes interiors + TOD-smooth
  by construction. The dynamic suns are added on top (probe is ambient/indirect only).
- **PBR**: diffuse = probe SH irradiance; specular = prefiltered cubemap at the material roughness (real IBL).
- **Metal / Precursor tech**: prefiltered cubemap at surface roughness.
- **Water**: mip0 sharp cubemap as the reflection source (optional SSR for dynamic actors on top).
- **Color grading**: probe average tone per location/TOD.
- **Tiers (Adreno 618)**: low = SH only (cheap, big win); mid = + low-res sparse cubemaps; high = dense grid +
  sharp cubemaps.

## GOLDEN RULE + MENU
- OFF (probes off) == the current directional-ambient behaviour; the whole feature is code-gated. rt-off +
  pbr-off + probes-off == stock byte-identical.
- Add the coherent Recharged menu entries (probe ambient on/off, reflections on/off + quality) following the
  existing menu conventions; no unknown-ID garbage.

## OBJECTIVE GATES (device eae4df44, jak1 focus, no reboot; owner_verify — owner's eye is final)
1. A village1 probe asset is built PROGRAMMATICALLY (file exists, non-trivial size, TOD-indexed) with probes
   at all explorable heights + inside-box room centers (report the counts/placement, incl. an interior probe).
2. Bake captures the FULL LIT environment INCLUDING the suns (the probe is a real HDRI — a sunlit-world
   reflection/env, not a dead dark cube). Prove the composition does NOT double-count the sun (energy-
   consistent: probe env + dynamic delta, no blow-out vs the same scene without probes).
3. Runtime ambient uses the LOCAL probe SH (shader references the probe uniform/sampler); an interior A/B shows
   the interior gets its correct LOCAL ambient (different from the global sky SH) — MEASURED, not eyeballed.
4. PBR specular IBL + at least one reflection consumer (metal/Precursor/water) sample the prefiltered cubemap
   (shows the LOCAL environment, not a flat/global cube) — MEASURED A/B.
5. Coherent Recharged menu entries present, no unknown-ID; OFF==stock byte-identical (code-gated).
6. Report `RESULT: PASS` + device mp4/png + `mCurrentFocus ... jak1`, on the DEFAULT colored render (not a
   debug viz). Verification is OBJECTIVE/numeric; the visual/aesthetic call is the owner's (push to his Honor).
