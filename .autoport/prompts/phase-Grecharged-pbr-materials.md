# Phase Grecharged-pbr-materials — REALTIME LIGHTING + PBR shading path, proven on ONE downloaded material

## Owner mandate (2026-07-17, verbatim intent)
"Je pense 217 en premier, le plus probable que t'arrives à faire en autonomie, en ajoutant le realtime
lighting et le support de PBR complet. Tu peux même télécharger un matériel PBR d'internet pour tester en
remplaçant une texture. On verra plus tard pour la full pipeline de conversion."

Reprioritized to NEXT (idx 214) because it is the most autonomously-verifiable: the proof is an
OBJECTIVE A/B on ONE texture, using the custom_assets override system we shipped in P3 — no dependence on
the owner's device to iterate.

## Scope of THIS run (and what is DEFERRED)
IN scope:
1. A REALTIME PBR shading path in the GLES renderer (Cook-Torrance-ish, mobile-tuned) driven by the
   game's EXISTING dynamic mood/TOD light environment (NOT a new light rig — reuse it, see enabler below)
   PLUS a realtime specular/BRDF response that visibly reacts to the sun direction as the surface/camera
   moves (that is the "realtime lighting" the owner wants — a moving highlight, not baked).
2. Extend the P3 custom_assets override from single-texture-replace to a MULTI-MAP PBR SET keyed by
   filename convention on ONE base texture:
     <tex>.png            -> albedo/base-color (already works)
     <tex>_normal.png     -> tangent-space normal map
     <tex>_roughness.png  -> roughness (grayscale)
     <tex>_metallic.png   -> metallic (grayscale)
     <tex>_ao.png         -> ambient occlusion (optional)
   Presence of at least a normal OR roughness/metallic map flips that material onto the PBR path.
3. DOWNLOAD a real CC0 PBR material from the internet (e.g. ambientCG / Poly Haven — CC0, credit in the
   report) and drop it over ONE recognizable world texture (a floor/wall tfrag on the title-flythrough or
   village1 is ideal — flat, well-lit, easy A/B). Rename its maps to the convention above.
4. Build-flag gated via the PILLAR dual-plumbing: add `--pbr` to build.sh (CMake `OG_FEAT_PBR` +
   generated `FLAG_PBR` defconstant), feature EXCLUDED from the build when the flag is absent, its
   Recharged-Settings menu row `#when`-compiled only when on. Runtime toggle "PBR Materials: Off/On"
   inside that gate. This keeps default builds clean (owner pillar rule).

DEFERRED (owner "on verra plus tard"): the full offline extraction + AI/tooling batch material-generation
+ ORM-packing + de-lighting pipeline. This run hand-drops ONE downloaded material to prove the runtime
path; the asset pipeline is a later phase.

## KEY ENABLER — the dynamic light env already exists (verified in engine 2026-07-11)
Reuse the mood/time-of-day system as the PBR light source — do NOT invent lights:
- `*time-of-day-context*` -> `current-sun` (sun direction/color), `light-group` (NINE per level, :inline),
  `title-light-group`, `sun-fade`, `light-interp` (time-of-day-h.gc:53-91).
- `update-mood-shadow-direction` (mood-tables.gc) — per-mood TOD-driven directional key light = the PBR
  directional. Actors already consume `light-group` on their normals (lights-h.gc).
So the PBR surface is lit by the SAME authored lights the game already interpolates -> coherent with the
non-PBR world by construction. VERIFY these symbols still exist before building on them.

## Architecture — per-material branch, default == stock (unchanged from owner's 2026-07-11 design)
At shade time:
- PBR maps present + toggle ON  -> MODERN path: sample albedo/normal/roughness/metal(+AO), light with the
  mood directional (current-sun / mood-shadow-direction) + an ambient/sky term + the level light-group;
  IGNORE the baked per-vertex TOD color for that surface (avoids the owner's double-dose).
- No PBR maps (or toggle OFF)   -> LEGACY path UNCHANGED: texture x baked per-vertex TOD color, exactly as
  today. OFF everywhere == byte-identical stock (prove it).

## The real work / risks (honest)
1. GLES PBR fragment path + mood-light binding (uniforms for sun dir/color, ambient, exposure).
2. TANGENTS for world geometry (normal mapping is tangent-space): tfrag is vertex-colored — synthesize
   per-vertex tangents from UVs at load (or in the renderer). Pick a test surface where this is tractable.
3. BOUNDARY COHERENCE (main aesthetic risk): the PBR-relit patch next to legacy-baked neighbours must
   match brightness/contrast — calibrate the PBR response to the level's mood/exposure so the A/B looks
   integrated, not a glowing sticker.
4. Alpha/transparent meshes excluded (same as AO) — pick an opaque test surface.
5. Perf/memory — one material this run, so minimal; note APK/memory implications for the rollout phase.

## Deliverable + PROOF (objective, supervisor-checkable WITHOUT the owner's device)
- The realtime PBR path compiles and runs on the Redmi (eae4df44).
- ONE downloaded CC0 material dropped via custom_assets over one world texture, rendered through the PBR
  path lit by the mood sun.
- REALTIME proof: a short device video where the specular highlight MOVES across the surface as the sun
  direction / camera changes (screenrecord; a still cannot prove "realtime"). Baked legacy has no such
  moving highlight.
- A/B: PBR toggle ON vs OFF at the SAME vantage (device captures), plus OFF==stock byte-identity claim
  backed by the flag-absent build.
- FALLBACK proof: a neighbouring non-PBR surface still renders the legacy baked path in the same frame —
  no double-dose, boundary coherent.
- Report: material source + license/credit, the naming convention used, ON/OFF captures, the realtime
  video path, perf note, and honest limitations.

## Verification philosophy (LEARN from the AO/grass/foliage history)
- Gate on what a HUMAN SEES + a supervisor-owned objective metric, never a worker-chosen number that
  measures the zone the feature happens to exist in. A moving specular highlight is the human-visible tell.
- Timing-dependent screenshot pixel-diffs are noisy: prefer deterministic STATE dumps + the realtime
  VIDEO for the "does it react" claim.
- Do NOT declare "livré" from code or from my eyes — this ships to the owner as a flag-gated experiment he
  will judge; my job is to make the A/B objectively real first.

## Locks
ANDROID_SERIAL=eae4df44 only; no adb reboot; engine goal_src stays 1:1 (all work in the renderer / pc
layer / GLES shaders / custom_assets loader + downloaded assets); gold READ-ONLY; force-stop the game
after every device window; slim-APK + external custom_assets is the real delivery path (never adb-push
assets as the proof). Redmi max-settings fps is informational only.

## Budget
max_turns 3500, max_retries 6. device: true, owner_verify: true.
Flag plumbing must pass the pillar's anti-staleness marker checks (ogflags hash) like every other flag.

## OWNER-REPORTED DEFECTS (2026-07-17 evening) — supervisor could NOT reproduce on the current build, but HARDEN
Owner, looking at a device state (build/attempt unknown), reported TWO things:
1. "beaucoup de violet" — a LOT of magenta/purple across the render (low render-scale, which is just the
   render-scaling blur = NOT a problem per owner).
2. "rendu à plein res ça a crash instant" — setting render-scale to 100% (full) crashed the game instantly.

Supervisor repro (build ogflags:465b53fe1394, Redmi eae4df44, render-scale=100, PBR active, material
vil-beach-01 N=1 R=1 M=0 AO=1, 2 PBR materials, village1-hut spot): 40s STABLE, NO crash, NO magenta,
sharp render. Could NOT reproduce EITHER symptom. Evidence: reports/Grecharged-pbr-materials/device/
supervisor-repro/. IMPORTANT FIND: the device drop dir was half-cleaned (only vil-beach-01.png albedo, the
_normal/_roughness/_ao were gone) — so a PARTIAL map set is a real on-device state.

HARDEN against both regardless (these are the prime suspects — verify and fix):
A) MAGENTA ("beaucoup de violet"): almost certainly a PBR GL texture-unit STATE LEAK — the PBR tfrag path
   binds sampler units for N/R/M/AO and does not fully restore unit state, so subsequent NON-PBR draws
   sample a stale/unbound unit -> magenta ACROSS the scene ("beaucoup", not one patch). This is the SAME
   class as the old AO GL-state leak (fixed by full save/restore). ALSO: an absent map (e.g. metallic M=0,
   or a partial set) must bind a 1x1 neutral default, never leave a sampler unbound (unbound sampler2D on
   Adreno = garbage/magenta). Fix: full save/restore of texture-unit + sampler bindings around the PBR
   draw; neutral 1x1 defaults for every absent PBR map; prove OFF==stock and a partial-set renders albedo
   cleanly (no magenta).
B) FULL-RES CRASH: booting at render-scale=100 does NOT crash. The prime suspect is CHANGING render-scale
   AT RUNTIME via the menu slider (FBO/framebuffer realloc while PBR textures/FBO are bound) -> GL crash.
   Reproduce the RUNTIME render-scale change path (not just boot-at-100) and make PBR resources survive an
   FBO resize. Test: boot low -> menu -> slide render-scale to 100 -> must not crash.
Add both to the device proof: a magenta-scan (no pixels near (255,0,255)) ON at the spot, and a
runtime-render-scale-to-100 no-crash clip.

## OWNER CRITIQUE 2 (2026-07-17 late) — "looks like just a diffuse/base-color swap, no normals/rough/etc; can't tell if realtime"
Owner saw the PoC briefly and said it looks like ONLY the base-color photo of pavers was swapped over the
sand — no visible normals / metallic / ORM / roughness / scattering / displacement / AO — and he can't tell
if the lighting is realtime or baked.

SUPERVISOR CODE VERIFICATION (so the next attempt targets the REAL gap, not a rewrite):
- It IS real PBR in code: tfrag3.frag does full Cook-Torrance GGX (D/G/F), samples tex_PBR_N/R/M/AO, gamma
  correct. Maps ARE fed into the BRDF. NOT a plain albedo swap.
- It IS realtime: hud-classes-pc.gc:1686-1689 pushes `*time-of-day-context* current-shadow / current-sun
  sun-color / env-color` EVERY FRAME via pc-set-pbr-sun! -> kmachine pc_set_pbr_sun -> g_global_settings ->
  background_common.cpp:507-544 binds u_pbr_sun_dir/color/ambient per frame. So it tracks the day cycle.
WHY IT STILL READS AS A FLAT PHOTO (the real weaknesses to fix — this is the mandate):
1. NO REAL TANGENTS: tfrag has no tangent attribute, so the normal map uses a screen-space-derivative
   cotangent frame (tfrag3.frag:52-63). On near-flat surfaces that frame is weak/degenerate -> normal relief
   barely shows. Fix: robust tangents (from UV gradients with proper handedness, or precomputed), and PROVE
   the normal map changes shading (toggle N on/off A/B).
2. BAD TEST SURFACE/LIGHT: flat water at high sun -> specular off-screen, normal flat. Use a surface + sun
   angle where relief + a specular highlight actually READ (a wall / stone floor, rake the sun).
3. WEAK/rich channels: make EACH channel visibly contribute (a per-channel debug viz: albedo-only,
   +normal, +roughness, +spec, +AO) so the owner can SEE each map do work.
MISSING CHANNELS the owner explicitly listed (implement or explicitly scope): height/DISPLACEMENT (parallax
occlusion mapping), SUBSURFACE SCATTERING ("scattering color"), ORM packing (currently separate R/M/AO).
REALTIME PROOF owed: a single continuous clip (or TOD sweep) where the specular highlight MOVES with the
sun — the un-fakeable "realtime" tell the owner asked for.
The bar is now: make it look UNMISTAKABLY like PBR (relief that catches moving light), not a pasted photo.

## REPORTING DISCIPLINE (MANDATORY — 3 attempts died on "no report" = session exhausted before writing it)
The last 3 attempts produced real code (tangents, pbr_ndiff.py, device runbook) but NEVER wrote
.autoport/reports/Grecharged-pbr-materials/report.txt before the session ended -> validator "[Gpbr FAIL]
no report" -> orchestrator STUCK-halted 3x on the same fingerprint. Break the cycle:
1. BUDGET THE SESSION. This is a big feature — do NOT spend the whole session building. Reserve the LAST
   third of your turns to: rebuild -> deploy_verify -> device capture -> WRITE THE REPORT. A perfect build
   with no report is a guaranteed FAIL and wastes the whole attempt.
2. WRITE report.txt EARLY AND KEEP UPDATING IT. Create it as soon as you have ANY device evidence; rewrite
   it as you progress. It must exist at session end no matter what.
3. Only write `RESULT: PASS` when `bash validators/phase-Grecharged-pbr-materials.sh` truly exits 0. If you
   are not there yet, write `RESULT: WIP — <precise state + exact next step>` so the fingerprint reflects
   REAL progress (not the null "no report"), the orchestrator sees movement, and the next attempt resumes
   from your documented state instead of restarting. An honest WIP report with device captures beats silence.
4. Prefer ONE tractable, verifiable win per attempt (e.g. "robust tangents + normal A/B proves relief")
   over trying to land every channel at once and reporting nothing. Land it, capture it, report it, then
   build on it next attempt.
