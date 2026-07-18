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

## OWNER GATE VERDICT (2026-07-18 morning): REJECTED — "ça paraît toujours giga flat, on n'a pas de normal
## maps ou displacement qui fait l'effet 3D, c'est pas possible ! c'est p't-être la texture qui est naze"
Owner looked at the LIVE device at the close sage-wall vantage (warp pos -112.0 42.0 205.0, TOD hour 8,
PBR ON, material registered) and the wall reads FLAT. Supervisor forensics agree on three compounding causes:
1. MATERIAL TOO SOFT: PavingStones070 normal map deviation mean 18.3/255 (p95 58) = gentle; roughness map
   nearly UNIFORM (mean 132, std 11.7) => zero visible per-pixel spec variation. The owner's "texture naze"
   suspicion is partially right.
2. NO DISPLACEMENT: the "3D pop" the owner expects IS parallax. POM was deferred — that deferral is now
   REVOKED by the owner's verdict.
3. Screen-space-derivative TBN further weakens normal response on flat walls.

NEW MANDATE (this phase, not backlog):
A) Implement PARALLAX OCCLUSION MAPPING: support <tex>_height.png in the custom_assets set; POM in
   tfrag3.frag (mobile-tuned steps w/ early-out, quality-gated), silhouette not required. The bricks must
   visibly OFFSET/occlude at grazing view — the un-fakeable 3D tell.
B) Swap to a PUNCHY CC0 material: pick one with DEEP height + strong normals + VARIED roughness (e.g.
   ambientCG Bricks075A/CastleWall — verify stats before adopting: normal dev mean > 35, roughness std > 30,
   height map full-range). Download WITH the Displacement map. Keep license credit.
C) Add a normal-strength multiplier (uniform, debug-prop tunable; default calibrated so relief is obvious
   at 1-3m) and consider 2-3x UV tiling on the test wall if native texel density hides the detail.
D) PROOF at the OWNER'S vantage: close-up captures/video AT THE SAGE WALL (warp pos -112.0 42.0 205.0,
   TOD hour 8) — NOT the stock spawn (mid-distance viz stills are void as owner evidence). Required: A/B
   POM on/off at grazing camera angle, normal on/off, and a slow camera arc where brick depth visibly
   parallaxes. Owner's eye is the gate: "unmistakably 3D relief, not a flat photo".

## OWNER GATE VERDICT ROUND 3 (2026-07-18 ~09:20): up-close relief OK, BUT the WHOLE BUILDING reads
## FLATTER than stock — "le retrait du baked lighting serait bien si ça recevait VRAIMENT de la lumière
## et le shading était vraiment fait selon la lumière; là c'est juste plus plat qu'avant, avec une
## texture 3D. Un peu nul non ?"
Diagnosis (supervisor, confirmed by the owner's eye): dropping the baked per-vertex TOD color on the PBR
path also dropped ALL the MACRO shading it carried — the round building's curvature gradient, the
under-thatch darkening, the doorway occlusion. Replacing that with "directional sun + CONSTANT ambient"
lights every fragment of the shaded side identically -> the building goes uniform/flat, POM micro-relief
notwithstanding. This is the known risk 3 (boundary/macro coherence) biting for real.

NEW MANDATE — reintegrate the baked lighting as the INDIRECT/GI term (modern-engine pattern, no runtime GI):
A) Split the lighting: direct = Cook-Torrance vs the mood sun (keep as-is, keeps relief + realtime);
   indirect/ambient = REPLACE the flat u_pbr_ambient constant with a per-fragment term MODULATED BY THE
   BAKED VERTEX COLOR (fragment_color), e.g. indirect = albedo * baked_rgb * ambient_calib — so under-roof
   stays dark, curvature gradients return, doorway occlusion returns. The baked color acts as baked
   GI/AO, NOT as a second direct-light dose.
B) Double-dose control: the baked color also contains the baked sun. Either scale down the direct term by
   a calibration factor, or subtract/normalize the baked term's directional component — pick the simplest
   approach that looks right at the owner vantage; document the choice. The failure modes to avoid:
   (1) flat building (current defect), (2) obviously double-lit hot side.
C) The macro test (owner's eye): at the sage-wall vantage, PBR ON must show the SAME macro light
   distribution as OFF (curvature gradient, under-roof darkening — compare luminance PROFILES along the
   wall band, not just mean deltas) PLUS the POM relief PLUS the realtime sun response (TOD sweep still
   changes the wall). Metric: correlation of ON-vs-OFF luminance profiles along the building's curve
   > 0.8 while POM ndiff stays > noise.
D) Keep everything already won: POM, punchy Bricks059, normal-strength, magenta 0, no-crash, OFF==stock.
Proof at the owner vantage (-112 42 205 h8) as before + the TOD sweep. Owner's eye closes the gate.

## OWNER ROUND 4 (2026-07-18 ~10:30): round-3 accepted as better ("OK ça fonctionne mieux") + THREE deeper asks
Owner verbatim (condensed): (1) "fou qu'avec le soleil + la 'lune' (étoile verte) éclairant la scène on
n'ait pas un ombrage naturel comme dans les logiciels 3D, et qu'on soit obligé de mettre du baked — ça n'a
pas trop de sens"; (2) "les modèles 3D ne castent pas d'ombre relative à la position de l'éclairage. PARS
PAS SUR DU RAY TRACING — ces techniques existent depuis bien avant, peu coûteuses"; (3) "des endroits où la
texture PBR est utilisée mais seulement sa texture, pas le reste (normals etc) — bizarre".

Context for the worker — what stays true: baked-as-indirect IS the modern hybrid (UE/Unity bake indirect
GI too); do NOT remove it. What's missing is the DIRECT half being properly occluded — i.e. SHADOWS.

MANDATE (classic techniques ONLY, no ray tracing):
A) AUDIT FIRST (researcher): jak1 has a real shadow system (shadow renderer + update-mood-shadow-direction,
   light-relative projected geometry shadows on PS2). Establish its CURRENT state on Android arm64: ported?
   noop'd in the mips2c allowlist class? direction static? Which casters are enabled (Jak only? NPCs?)?
   The 1:1 rule says restore the stock behavior first if the port dropped it. Report findings BEFORE
   building anything new.
B) SUN SHADOW MAPPING for the PBR direct term (the "ombrage naturel"): classic depth-map from the mood-sun
   direction (single cascade, small res 1024, PCF 2x2, mobile-tuned for Adreno 618), world+actors rendered
   depth-only into it; the PBR path multiplies its DIRECT term by the shadow factor (indirect/baked term
   untouched — shadows don't kill GI). Gated inside --pbr + a quality/off toggle. Casters: start with the
   world tfrag + merc actors near the camera. This is 1978 tech, cheap, exactly what the owner asked.
C) MULTI-LIGHT: consume the level light-group (dir0/dir1/dir2 + ambi — includes the green 'moon' star when
   the mood drives it) in the PBR direct term instead of only current-sun; energy-conserving sum. The
   'moon' must visibly light the scene at night sweep.
D) COVERAGE UNIFICATION (the owner-seen defect): the custom texture replacement is texture-pool-global but
   the BRDF path exists only in the tfrag renderer -> the same replaced texture drawn via the vis-alpha
   tree / TIE / other renderers shows the swapped ALBEDO with NO PBR shading (logcat proof: maps register
   under BOTH village1-vis-tfrag AND village1-vis-alpha). Audit every draw path that samples a replaced
   texture; extend the PBR path (uniforms + maps + POM) to those renderers OR restrict the albedo swap to
   PBR-capable paths so no surface is half-PBR. No surface may show the new albedo without the new shading.
Proofs at the owner vantage + a night/moon beat + a shadow beat (an actor or the hut casting a sun-relative
shadow that MOVES with the TOD sweep). Owner's eye closes the gate.

## OWNER CLARIFICATION (2026-07-18 13:45) — shadows: he means the WORLD, not characters
Owner verbatim: "je vois bien les ombres de Jak, mais moi je te parlais du monde, pas des personnages!"
- DROP the stock-stencil-shadow device-proof task (audit item A): the owner confirms character shadows
  visibly work. Zero effort there.
- The sun shadow map (item B) is THE deliverable, and it must be WORLD-scale:
  * CASTERS: world geometry (tfrag+tie: the sage hut, terrain, bridges...) into the 1024 depth pass.
  * RECEIVERS: not just the PBR-mapped surfaces — the LEGACY world too, else the hut's shadow on the
    (non-PBR) ground is invisible and the owner sees nothing. When pbr-materials? is ON, apply the
    shadow factor as a calibrated darkening on legacy receivers (e.g. lerp towards a shadow tint on
    fragment_color output, strength tunable ~0.35), and on the PBR path multiply the DIRECT term as
    designed. Calibrate so already-baked painted shadows don't double-darken into black.
  * PROOF the owner asked for: the HUT casting a visible shadow on the ground that MOVES across the
    TOD sweep (video at his vantage). That's the acceptance image.
- Everything stays inside the --pbr flag + runtime toggle (OFF==stock untouched).

## OWNER ROUND 4bis (2026-07-18 14:15) — "si notre vrai lighting realtime marche vraiment, on n'a plus
## besoin du baked quand activé !"
The owner wants the FULL-REALTIME end state: once world shadow map + multi-light work, the baked term
should become unnecessary with the feature ON. Honest decomposition (share in the report): baked carries
(1) direct sun + painted shadows -> replaced by realtime sun+shadow map (keeping both = DOUBLE shadows,
so the baked DIRECT component must fade out when shadows are on); (2) occlusion -> covered by the shipped
AO feature (SSAO/HBAO/GTAO) when enabled; (3) colored bounce/GI -> the only real loss; approximated by the
light-group ambient. MANDATE E (this attempt if the build allows, else immediately next):
- Add u_pbr_baked_weight (1.0 = round-3 hybrid, 0.0 = FULL REALTIME: indirect = light-group ambi * AO
  only), prop-tunable (debug.opengoal.pbr.bakedw) + a settings-exposed choice later if the owner picks it.
- Device A/B AT THE OWNER VANTAGE: bakedw=1.0 vs bakedw=0.0 with world shadows + multi-light ON, same
  hour + a night beat — so the owner judges by eye which world he wants. Report both captures.
- Watch for the failure modes: double-shadowing (baked painted + realtime) at w=1 with shadows on ->
  document/calibrate; flat-under-roof at w=0 if AO off -> note that full-realtime pairs with AO ON.

## OWNER ROUND 5 (2026-07-18 ~20:20, playtest on HIS Honor, round-4 build + his saves) — two verdicts
1. GOOD: "Le PBR brique rend pas mal" — BUT the material must be RACCORD (faithful) with what it
   replaces: the brick does NOT match the original sage-wall look. MANDATE A — MULTI-MATERIAL MATCHING SET:
   pick 3-5 world surfaces around the owner vantage (sage wall, thatch roof, wooden walkway planks,
   village stone/sand) and for EACH download a CC0 material whose ALBEDO/look matches the ORIGINAL surface
   it replaces (thatch->straw/thatch, planks->worn wood planks, sage wall->sandstone/adobe matching the
   original palette, NOT red brick). Stats-verify punch (normal dev>35 / rough std>30 / height full-range —
   post-process via pbr_material_prep.py as before if raw fails). Report a side-by-side original-vs-PBR
   per material: the goal is "the same surface, upgraded", not "a different surface".
2. BUG (the important one): "les ombres/shading temps réel a l'air perdu — ombres qui apparaissent/
   disparaissent/bougent/changent de forme sur SIMPLE ROTATION CAMÉRA". Classic shadow-map instability,
   two known root causes to fix:
   a) CASTER SET IS CAMERA-VIS-CULLED: the depth pass renders the camera-PVS/vis-culled tree draws, so an
      off-screen caster stops casting -> its shadow pops in/out as the camera rotates. FIX: the depth pass
      must ignore camera visibility — render ALL NORMAL-tree draws (or light-frustum-cull), never the
      camera vis set.
   b) VIEW-DEPENDENT ORTHO FIT: the +/-40m box is fit/centered relative to the camera view, so rotating
      the camera changes the light-space projection -> shadows swim/change shape. FIX: standard stabilized
      fit — light-space axis-aligned box of CONSTANT size from a camera-position-anchored bounding SPHERE
      (radius fixed; rotation cannot change a sphere), center snapped to the shadow-texel grid each frame.
   ACCEPTANCE (owner's exact repro): a device clip at the vantage doing a FULL CAMERA ORBIT with the sun
   pinned — every shadow must stay PINNED to the ground (no pop, no swim, no shape change). Add an
   objective check: per-frame shadow-mask IoU across the orbit (>0.9 between consecutive frames on the
   static scene band).
Keep everything else won (POM, baked-GI hybrid, bakedw, multi-light, coverage). Owner's eye closes.

## OWNER ROUND 5 ADDENDUM (20:30) — "on n'arrive pas à identifier la provenance d'UNE SEULE ombre projetée"
Beyond instability: the shadows are INCOHERENT — no shadow visually connects to its caster. Additional
root-cause suspects (verify each):
c) LIGHT DIRECTION != VISIBLE SUN: the depth pass uses the weighted dominant light-group dir; if that
   direction does not match where the sun VISIBLY sits in the sky at the test hour, every shadow points
   "wrong" and becomes unattributable. FIX: drive the shadow direction from the same vector that places
   the visible sun (mood current-sun / update-mood-shadow-direction), and PROVE alignment: at h8 and h16,
   a pole/hut shadow must extend exactly opposite the on-screen sun.
d) DOUBLE-BUFFER MATRIX LAG: receivers sample last frame's map+matrix — one frame of camera/TOD motion
   displaces every shadow from its caster continuously. If this contributes, consider same-frame ordering
   (depth pass before ALL receivers in the frame — bucket order permitting) or accept lag only when
   provably imperceptible (static-scene IoU unaffected by rotation is NOT enough; test while orbiting).
e) BIAS/RES sanity at the vantage: peter-panning (shadow detached from caster base) makes attribution
   impossible even when the direction is right — verify polygon-offset bias so contact points touch.
ATTRIBUTABILITY ACCEPTANCE (owner's words): at the vantage, ONE clearly identifiable shadow per caster —
the hut's shadow starts AT the hut base and extends away from the visible sun; a fence post's shadow
touches the post. Device clip walking the eye from caster to shadow + a still annotated in the report.

## OWNER ROUND 5 ADDENDUM 2 (20:50) — "Jak est éclairé par une source qui match le soleil — pourquoi pas
## pareil pour tous les objets et le monde au global ?"
Owner's observation is the design key: ACTORS are lit per-vertex by the mood light-group on their normals
-> stable, geometry-attached, sun-tracking shading. The world only has static baked + our (buggy) shadow
map "floating like badly-attached projected sprites". MANDATE F — WORLD-WIDE MOOD-LIGHT SHADING
("light the world like Jak"): when the feature is ON, apply the SAME directional response the actors get
to ALL world geometry (tfrag+tie): geometric normal (screen-derivative per-face is fine — it is stable and
camera-independent for shading) x the mood light-group (sun + fill + moon, energy-conserving) as the
DIRECT term, x the shadow factor; indirect stays baked*bakedw. Per-face N.L shading is attached to the
geometry by construction — it CANNOT swim with the camera (unlike the shadow lookup) and instantly makes
the whole world respond to the sun exactly like Jak does. Calibrate direct/indirect so the world does not
double-brighten (the baked already contains sun; reuse the round-3 calibration approach). The PBR-mapped
surfaces keep their full BRDF; non-PBR world surfaces get this lightweight N.L relight. Acceptance: at the
vantage, hut walls facing the sun are brighter than faces away from it, and the contrast FOLLOWS the sun
across the TOD sweep — while camera orbits change NOTHING (stability proof shared with round-5).

## ROUND 5 EXECUTION ORDER (supervisor 2026-07-18 23:45) — the scope is too big for one session; SPLIT IT
Three attempts died on "no report" = the session runs out finishing multi-material downloads + shadow
rebuilds + orbit captures before writing. Converge by prioritizing:
PRIORITY 1 (the owner's actual pain — land + PROVE + report this ALONE, do not touch materials until done):
  the SHADOW BUG. Stable under camera orbit (no swim/pop), direction matches the VISIBLE sun (h8+h16
  alignment), every world object casts (no camera-vis cull), attached at caster base (bias), AND the
  world-wide N.L mood-light relight so the whole world responds to the sun like Jak. Capture the orbit
  clip + sun-alignment stills, WRITE THE REPORT with RESULT: PASS-worthy shadow evidence (or RESULT: WIP
  with exactly what remains). Reserve the last third of the session for capture+report — a shadow fix with
  no report is a wasted attempt.
PRIORITY 2 (only after P1 is reported): matching multi-materials (thatch/planks/sandstone). If the session
  is short, leave these as a documented WIP follow-up — do NOT let them starve the P1 report.
The validator already requires orbit + world-relight + matching markers; if P2 isn't done this session,
write RESULT: WIP (honest) so the gate stays open and P1 progress is preserved for the next attempt.
Budget every session so report.txt ALWAYS exists at end.
