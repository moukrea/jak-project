# Phase Grecharged-pbr-realtime-fusion — PBR materials LIT BY the realtime lighting (the killer combo)

ultrathink. Delegate mechanical work to sub-agents; you (manager) design + verify.

## OWNER DIRECTIVE (2026-07-20)
"C'est un peu débile que le PBR soit pas câblé au realtime lighting ! Justement c'est là que ça va briller !
L'autre mode pour le PBR c'est du bidon donc autant le câbler au bon endroit (avec le fallback bidon quand
realtime lighting est désactivé et PBR est activé). Et faut câbler specular et emissive aussi !"

## CURRENT STATE (the problem)
The two features are wired as MUTUALLY EXCLUSIVE branches in the 4 world shaders
(tfrag3/shrub/tie_wind/etie_base, and now hfrag once the directional-ambient phase adds it):
- `if (u_rt_light_on != 0) { ...realtime lighting... }`   ← sun + green-sun + SH ambient, but IGNORES the
  PBR material maps (just albedo × lighting).
- `else if (u_pbr_mode != 0) { ...standalone Cook-Torrance... }`  ← consumes the maps but with its OWN weak
  lighting = the owner's "bidon" fallback.
- `else { stock }`
So today, turning realtime lighting ON (where the good sun/green-sun/ambient live) THROWS AWAY the PBR maps.
The material maps only apply on the "bidon" path. That is backwards.

## GOAL — FUSE them
When **realtime lighting is ON _and_ PBR materials are ON**, the realtime lighting path must become a full
PHYSICALLY-BASED renderer that consumes the material maps and lights them with the realtime analytic lights
(yellow sun + green sun) + the SH/IBL ambient. That is where PBR shines.

Concretely, inside the `u_rt_light_on` branch, when the per-material PBR maps are bound (pbr-materials ON):
1. **normal map** → perturb the reconstructed smooth geometric normal via a TBN frame (screen-space
   derivatives TBN is fine, as the existing standalone PBR path already does) → detail normals that move
   correctly under the realtime sun/green-sun.
2. **roughness + metallic** → Cook-Torrance GGX BRDF (D/G/F) for EACH analytic light: the yellow sun AND the
   green sun each get a diffuse (N·L, energy-conserving vs metalness) + a GGX specular highlight, weighted by
   that light's visibility + shadow (both suns cast shadows per the directional-ambient phase). Metallic tints
   the specular by base colour and kills the diffuse.
3. **ao** → multiplies the SH/IBL AMBIENT term only (never the direct sun — AO is contact/ambient occlusion).
4. **specular map** (NEW — must be wired, see loader below) → supports the spec/gloss inputs: use it as the
   F0 / specular colour (a specular-workflow material). Reconcile with metallic-roughness sensibly (if a
   specular map is present, honour it for F0; document the chosen convention).
5. **emissive map** (NEW — wire it) → ADDED self-illumination on top, UNLIT: the emissive texels glow even in
   full shadow / at night (independent of sun/green-sun/ambient). Prove it glows in a dark/shadowed capture.
6. **height map** → parallax/POM if cheap enough on Adreno 618 (optional tier); if not, leave loaded but
   unused for now (document). Do NOT block the phase on POM.
7. **SH/IBL ambient** → the ambient diffuse (already there) PLUS a simple roughness-aware ambient specular
   (a single ambient reflection term) so smooth metals aren't dead in shadow.

## KEEP the "bidon" fallback + golden rule
- **rt OFF + pbr ON** → the EXISTING standalone `u_pbr_mode` path, UNCHANGED (the owner's accepted fallback).
- **rt ON + pbr OFF** → the current realtime lighting (albedo only), UNCHANGED — no regression to the
  directional-ambient work the owner already accepted.
- **rt OFF + pbr OFF** → stock, BYTE-IDENTICAL (golden rule, code-gated — verify).
- Only the NEW **rt ON + pbr ON** combination changes.

## WIRE specular + emissive in the loader (currently unloaded)
`game/graphics/opengl_renderer/loader/LoaderStages.cpp` loads `_normal/_roughness/_metallic/_ao/_height`
via `custom_tex::lookup_suffixed(...)` + `PbrMaterialMaps`. ADD `_specular` and `_emissive` the same way:
extend `PbrMaterialMaps` (+ `spec_tex`, `emissive_tex`), the make_map/register/free-old-ids arrays, and the
uniform push/bind in the renderers. Then SAMPLE them in the fused shader. (Filenames the owner will drop:
`<tex>.png`, `<tex>_normal.png`, `<tex>_roughness.png`, `<tex>_metallic.png`, `<tex>_ao.png`,
`<tex>_height.png`, `<tex>_specular.png`, `<tex>_emissive.png`.)

## TEST MATERIAL
`vil1-sages-stonewall-01` — the owner's stone wall with the FULL map set (basecolor, normal, roughness,
metallic, ao, height, specular, emissive). Drop under the device custom_assets flat dir
(`/storage/emulated/0/OpenGOAL/jak1/custom_assets/`). Enable: custom assets ON, PBR ON, realtime lighting ON.

## OBJECTIVE GATES (device, ANDROID_SERIAL=eae4df44, jak1 focus, no reboot)
1. **rt ON + pbr ON**: the material maps demonstrably drive the REALTIME-lit result — A/B where the normal
   map adds surface detail that shades correctly as the realtime sun moves (TOD sweep), and roughness/metallic
   change the specular response. Measured, not just asserted.
2. **specular + emissive WIRED**: nm/grep proves `_specular`/`_emissive` load in LoaderStages + the shader
   samples them; **emissive GLOWS in a shadowed/night capture** (self-lit, independent of the suns).
3. **bidon fallback intact**: rt OFF + pbr ON still renders the standalone PBR (unchanged).
4. **no regression**: rt ON + pbr OFF == the accepted directional-ambient look; rt OFF + pbr OFF == stock
   byte-identical.
5. Report `RESULT: PASS` + device mp4/png + `mCurrentFocus ... jak1`. Verify on the DEFAULT colored render,
   NOT a debug viz. Owner's eye is the final gate (owner_verify).

Reserve the last third of the run for the report + device evidence. Write the report EARLY, fill as you go.

---
## OWNER PLAYTEST (2026-07-23) — RELIEF GAINED ✅ BUT PLASTIC SHINE ❌. REOPENED — industry-standard BRDF, "on veut que ça claque".
Owner: "les textures ont gagné en relief, c'est stylé, MAIS ça rend comme une surcouche PLASTIQUE brillante
— surtout sur les textures AU SOL et aux ANGLES EXTRÊMES. La plupart des PBR ont height/normal/roughness —
se baser là-dessus. TOUJOURS conserver le baked en influence (le relief des objets, notre meilleur rendu).
Utiliser les probes pour la cohérence des matériaux PBR. Pas joli pour l'instant. Standards de l'industrie."

DIAGNOSIS (the classic plastic-look causes — audit and fix EACH):
1. **Grazing-angle Fresnel blowout** (his "angles extrêmes" + ground sheen): Schlick F→1.0 at grazing with
   no roughness attenuation and no proper visibility term ⇒ white plastic sheen on floors seen at an angle.
   FIX: full Cook-Torrance with the SMITH-GGX VISIBILITY term (not just D*F), and roughness-aware Fresnel
   (e.g. F0 + (max(1-roughness, F0) - F0) * pow(1-NdotV, 5)) so ROUGH surfaces never get the mirror-edge glow.
2. **Roughness map under-respected**: rough surfaces (ground!) must produce BROAD, DIM highlights — if the
   ground looks glossy, the roughness sampling/mapping is wrong (check channel, sRGB-vs-linear read,
   perceptual-vs-alpha roughness squaring: use alpha = roughness^2 industry convention).
3. **Dielectric F0**: these materials (stone/straw/dirt/sand) are DIELECTRICS — F0 = 0.04 constant (NO
   metallic assumption; most sets have only height/normal/roughness — treat missing metallic as 0.0).
4. **Energy conservation**: kd = (1-F) on the diffuse; specular never ADDS free energy on top of full baked.
5. **Specular occlusion**: crevices/AO (from the baked detail layer we already have!) must attenuate the
   specular too — shiny pits = plastic. Use the baked-detail ratio as cheap specular occlusion.
6. **Specular aliasing/sparkle** on normal-mapped ground: apply geometric specular AA (Toksvig-style
   roughness widening from normal-map variance) or clamp minimum roughness (~0.045) — no fireflies.

ARCHITECTURE (owner-mandated layering — do NOT regress it):
- BASE = the owner-validated BAKED-MODULATION composite (the object relief we fought for). The PBR layer
  sits ON TOP: normal-map detail perturbs the shading, roughness shapes the specular, height (optional
  cheap parallax) — the baked influence ALWAYS remains.
- PROBES = the coherence source for the PBR: IBL diffuse/specular from the probe SH + prefiltered cube at
  the correct ROUGHNESS MIP (a rough ground samples a blurry mip — never the sharp mip0), tinted/leveled by
  the local probe so materials sit IN the scene ("cohérence").
- Suns' specular via the GGX above; shadows kill the sun specular where blocked.
ACCEPTANCE: ground/rough materials show NO plastic sheen at any angle (esp. grazing); highlights match
roughness (broad+dim on rough, tight+bright only on genuinely smooth); baked relief unchanged; the owner
wants "ça claque" — industry-standard, his eye decides. Mechanical bar + READY; his Honor verifies.

**OWNER ADDENDUM (2026-07-23): "le relief des textures, ça pourrait être PLUS PRONONCÉ !"** While fixing the
plastic shine, STRENGTHEN the perceived texture relief: (a) normal-map intensity scale (multiply the tangent
XY of the sampled normal before renormalize — default pushed up, e.g. 1.5-2.0), (b) if cheap on Adreno,
basic parallax from the height map (few-step offset, no full POM needed) adds real depth, (c) ensure the
normal-map shading interacts with BOTH suns AND the ambient (a normal-map that only reacts to the sun looks
flat in shade). Expose a debug prop (e.g. debug.opengoal.pbr.normalstr) AND a sensible menu-less default so
the owner can dial it live; report the default chosen. More relief + zero plastic = the target.

---
## OWNER PLAYTEST #2 (2026-07-23) — "pas beaucoup de différence, toujours plastique, manque de relief, très bof". REOPENED.
The BRDF rework numbers were green but the OWNER SEES BARELY ANY CHANGE. Prime suspects, audit FIRST on
device-truth before touching the BRDF again:
1. **IS THE NEW PATH EVEN ACTIVE on his build/scene?** Prove with a device A/B killswitch (prop) showing an
   OBVIOUS visible difference new-path-on vs off at the same vantage. If barely anything changes, the fused
   path isn't executing where he looks (flag gating? probes OFF by default gating the ambient specular?).
2. **MISSING-MAP DEFAULTS + SOURCE PAIRING (strong suspect)**: his INTERNET pack now WINS precedence (the
   yesterday fix!) — those textures have NO roughness/normal maps. If a base texture resolves from the USER
   pack but PBR maps resolve from the BUNDLED set (different image!) or roughness falls back to a SMOOTH
   default ⇒ plastic exactly where he looks (the ground). FIXES:
   a. Missing roughness ⇒ assume ROUGH (default 0.85-1.0), NEVER smooth — industry rule.
   b. SAME-SOURCE pairing: PBR maps apply ONLY when they come from the same source as the base texture that
      won (user base + user maps, or bundled base + bundled maps — never mixed provenance).
   c. Log per-texture on device: base source, which maps bound, which defaults used — include for the
      ground textures at his vantage.
3. **TUNABLES IN THE MENU, not adb props** (owner looked in settings and found nothing): add Recharged
   Settings rows — "TEXTURE RELIEF" slider (normal-strength+parallax scale) and "SPECULAR INTENSITY" slider
   — live-applied, persisted, menu-tree.md synced. Defaults: relief NOTICEABLY stronger than current.
4. Side-by-side same-vantage captures old-vs-new proving an OBVIOUS difference (if pixels barely change,
   it's not done).

**OWNER CORRECTION (2026-07-23): his internet pack is DISABLED — the bundled PBR textures (with maps) ARE
displaying.** So the missing-maps/precedence hypothesis is DEAD (skip 2a/2b unless trivially cheap). The
plastic persists WITH roughness maps bound ⇒ narrow to:
1. (unchanged, PRIORITY) prove the new BRDF path is ACTIVE at his vantage (killswitch A/B, obvious delta).
2. **THE ROUGHNESS MAP IS NOT RESPECTED IN PRACTICE** — device-truth it: log/dump the ACTUAL sampled
   roughness values for the ground/wall textures in the fused path. Audit hard:
   - sRGB-vs-LINEAR: a roughness PNG uploaded/sampled as sRGB gets gamma-darkened ⇒ surface reads smoother
     ⇒ plastic. Data maps (roughness/normal/height/ao) MUST be linear (no sRGB decode).
   - channel (R? G? grayscale?), inversion (gloss-vs-roughness), and the alpha=r^2 convention actually
     applied in the highlight shape.
   - specular INTENSITY scale possibly swamping the roughness shaping.
3. Menu sliders (Texture Relief / Specular Intensity) UNCHANGED as mandated — the owner dials.

---
## OWNER PLAYTEST #3 (2026-07-23) — PLASTIC SURVIVES SPECULAR=0. STOP THEORIZING: TERM BISECTION. REOPENED.
Owner (furious, justified): "toujours ces reflets plastique PEU IMPORTE le relief/specular défini. Shimmering
quand le relief est élevé. Le displacement est pas réel, le parallax est naze — pourquoi pas TESSELLATION
(toggleable) ? Pourquoi ce putain de reflet comme un revêtement plastique sur TOUTES les textures PBR ??
Dans les jeux récents le relief est poussé et super intégré. Là c'est ultra moche alors que les textures
sont très quali. Fais un vrai truc pro qui claque."

**THE KEY DATAPOINT: the sheen SURVIVES specular-intensity = 0.** Therefore it does NOT come from the
slider-scaled specular term. Three rounds of BRDF theory failed. New method — NO fix until the culprit is
IDENTIFIED BY BISECTION:

### STEP 1 — TERM BISECTION on device (the owner's vantages: ground + wall, day)
Add a debug prop (e.g. debug.opengoal.pbr.bisect=<mask>) that zeroes lighting components INDIVIDUALLY in the
fused path: (a) sun GGX specular, (b) green-sun specular, (c) IBL/probe ambient-specular + reflection cube,
(d) the Fresnel factor everywhere it appears (incl. any Fresnel-ish term on the diffuse/ambient),
(e) specular-map (_specular F0) contribution, (f) emissive, (g) normal-map perturbation, (h) parallax.
Capture the SAME vantage for each mask. THE FIRST capture where the plastic sheen DISAPPEARS names the
culprit term. Report the full bisect matrix (one line per mask: sheen present yes/no + mean spec-band luma).
Suspects the theory rounds ignored: the AMBIENT-SPECULAR/IBL term (likely NOT scaled by the specular
slider!), a Fresnel term applied to ambient/diffuse, the _specular map ADDED as brightness instead of F0.

### STEP 2 — fix THE identified term (industry method for that term), nothing else. Re-capture, sheen gone.

### STEP 3 — SHIMMERING at high relief: the normal-map mip chain + specular AA are not effective. Verify the
PBR maps actually HAVE mips and are min-filtered LINEAR_MIPMAP_LINEAR; apply Toksvig/variance roughness
widening FROM THE FITTED MIP (not base); clamp min roughness. Prove: high-relief moving capture without
sparkle (frame-to-frame spec-band delta).

### STEP 4 — REAL DISPLACEMENT: replace the weak offset parallax with proper STEEP POM (16-32 steps, tiered)
AND add TESSELLATION displacement as a TOGGLEABLE menu option (OFF by default): GLES 3.2 requires
EXT_tessellation_shader — Adreno 618 supports it; tessellate the near ground/walls with the height map
(distance-based level, cheap falloff). Menu: "DISPLACEMENT: Off / Parallax / Tessellation" (menu-tree sync).
The bar: "comme les jeux récents — relief poussé, super intégré."

Mechanical + bisect matrix + READY; the owner judges. His textures are quality — make them look it.

**OWNER (2026-07-23) — SEAMLESS INTEGRATION CONTRACT.** "Le PBR doit rendre comme dans les jeux actuels,
pas comme une preview grossière de textures 3D — intégré seamless dans le jeu, prenant en compte le baked,
l'environnement actuel, l'éclairage actuel." The "pasted material-preview" look has precise causes — audit
each on the fused path:
(a) **FOG**: the game's fog/depth-cue MUST apply to the PBR-lit result exactly as to neighbors — a PBR wall
    that skips fog pops out like a sticker. Verify the fused branch goes through the same fog stage.
(b) **LIGHT INPUTS = the scene's actual lights**: sun/green-sun specular+diffuse must use the CURRENT TOD
    sun colours/intensities (the same driving the baked modulation) — never fixed white/unit lights; the
    ambient/env from the LOCAL probe. Alien-coloured highlights = instant preview-look.
(c) **BAKED influence retained on the PBR surfaces** (already mandated — re-verify after the bisect fix).
(d) **SAME OUTPUT TRANSFORM**: gamma/tone of the fused branch identical to the neighbouring non-PBR
    surfaces (no brighter/washier branch).
(e) **BORDER COHERENCE**: a PBR-textured surface next to a non-PBR one must not pop — check a boundary
    vantage; lighting continuity across the seam.
Acceptance stays: the owner's eye — "seamless, comme les jeux récents".

**SUPERVISOR HARNESS FIX (mandatory, 2 min): every `adb logcat` spawned by your capture scripts MUST be
wrapped in `timeout 240` (4 min covers any capture) — the un-timeouted logcat has zombied 5 times now,
wedging captures ~30 min each until the supervisor kills it. Patch the gpbrf/glp-style scripts you use.**

**OWNER (2026-07-23): "je target pas que mobile, je target PC AUSSI."** The Karis EnvBRDFApprox is the
MOBILE/low tier ONLY — it must NOT cap the quality ceiling. Tier the env BRDF: mobile/low = Karis approx
(shipped fix), PC/high = the FULL split-sum with a precomputed 2D BRDF LUT texture (industry standard),
selected by tier/platform (desktop GL build gets the LUT path by default). Same principle everywhere the
tiers exist: PC defaults to the full-quality variant (higher POM steps / real tessellation / bigger shadow
maps); mobile approximations never become the only path. Wire the tier plumbing now even if the LUT lands
as a fast-follow — document what's tiered where.

**OWNER CORRECTION (2026-07-23): NO platform gating — SAME FEATURES on mobile and PC.** Quality is a USER
SETTINGS tier, not a platform cap: Karis approx = the LOWEST settings tier only (explicitly selectable);
the full split-sum LUT, real tessellation, high POM, big shadow maps must be selectable ON MOBILE TOO
("on doit pouvoir aller all-in sur mobile autant que PC"). Defaults may differ per device class, but every
feature exists everywhere — future mobile APUs keep scaling (the owner's Honor runs a Snapdragon 8 Elite
Gen 5 and can go very far; the Redmi/Adreno 618 is merely the low-end test device). Tier plumbing =
settings-driven, not #ifdef-platform.

**OWNER (2026-07-23) — DEBUG PRESET MENU ROW (temporary, removable later).** Add a "PBR TEST PRESET"
carousel row in Recharged Settings that applies, in ONE selection, the EXACT intended setting combination —
so the owner is guaranteed to test in the designed best conditions. Presets:
- **ALL-IN**: everything at the intended maximum for his Honor (SD 8 Elite Gen 5): full BRDF path,
  intended specular/relief values, best displacement mode (tessellation if real, else steep POM high),
  shadows high, probes as designed — exactly what YOU intend as the showcase config.
- If several combinations need validation, add ONE PRESET PER COMBINATION (e.g. ALL-IN / MOBILE-LOW /
  POM-vs-TESSELLATION variants) so he can flip between them and validate each.
- Selecting a preset WRITES the underlying individual settings (so the fine sliders reflect it and he can
  then adjust from there). Label clean, no unknown-ID, menu-tree.md synced, marked as DEBUG (will be
  removed later). Report which presets exist and what each sets.

---
## OWNER CRASH REPORT (2026-07-23 soir) — ALL-IN preset = INSTANT CRASH on the Honor (SD 8 Elite Gen 5) + CRASH-LOOP via persisted setting
1. **The tessellation path (pbr-displacement=2) instantly crashes the Honor** (Adreno 8xx driver) — and
   since the setting persists, the game crash-looped on every launch until the supervisor reset the ini.
   FIX: (a) runtime capability check — query EXT_tessellation_shader + patch support + PROGRAM LINK success
   at init; if anything fails, fall back to Parallax gracefully (log it), never crash; (b) find the actual
   crash cause on a tessellation-capable driver path (shader compile/link on Adreno 8xx? missing
   glPatchParameteri? draw-mode GL_PATCHES on a non-tess program?). The Redmi (Adreno 618) may not repro —
   treat "works on 618" as insufficient; the code must be driver-defensive.
2. **CRASH-LOOP GUARD (mandatory, general): a persisted setting must NEVER brick the game.** Boot sentinel:
   write a marker at launch, clear it on reaching gameplay; if the previous boot died before gameplay N=2
   times consecutively, auto-reset the risky recharged settings (displacement->Off, preset->default) and
   log "[recharged] crash-loop guard: settings reset". This protects every future setting too.
3. The ALL-IN preset must apply the SAFE maximum per device (capability-checked), not blind tessellation.

---
## OWNER PRESET REPORT (2026-07-23 soir) — THE "GLASS PANE" DEFECT + preset triage. (Crash fix still due.)
Owner tested the presets (before the tessellation re-crash):
- **Fusion**: very CONTRASTED + materials look like they're BEHIND GLASS PANES — the reflective layer sits
  on the FLAT GEOMETRY surface, floating over the material ("les surfaces planes de la géométrie par
  dessus").
- **Fusion plate**: very contrasted, flatter, "pas foufou".
- **PBR seul**: not bad, less contrasted = more natural, BUT the same GLASS effect ruins it.
- The two remaining presets: "quasiment juste les textures" — no visible effect (are they wired at all?).

### DIAGNOSIS 1 — THE GLASS PANE (the dominant defect, precise signature):
Specular/env reflections that follow the FLAT polygon instead of the texture grain = the specular and
ambient/env terms are computed with the GEOMETRIC/smooth normal, not the NORMAL-MAPPED (and POM-offset)
normal. FIX: EVERY term that shapes highlights/reflections (sun GGX NdH/NdV, green-sun, famb_env reflection
vector Rf, Fresnel NdV) must use the PERTURBED normal Nm (and the parallax-corrected view/UV where POM is
on). The material grain then breaks up the reflection — no more glass sheet. Verify per-term (the bisect
prop makes this easy to eyeball per component).
### DIAGNOSIS 2 — "very contrasted" on Fusion modes: the baked-modulation × PBR stacking double-applies
contrast (baked lit/shadow fmod × GGX sun on top). Rebalance so the fused mode's overall contrast matches
the accepted baked-modulation look (the sun specular ADDS sparkle, not another contrast multiply).
### DIAGNOSIS 3 — the two "nothing" presets: verify they actually wire what they claim (report said each
preset writes the underlying settings — audit what those two set; if they're meant to be subtle tiers,
label them accordingly; if broken, fix).
Plus the STILL-DUE crash work: tessellation capability check + graceful fallback + CRASH-LOOP GUARD
(the owner bricked twice more re-enabling ALL-IN/tessellation — the guard is not optional).

---
## OWNER ARCHITECTURE DECISION (2026-07-23 soir) — DELETE THE PROBE GRID ENTIRELY. DYNAMIC FOLLOW-PROBE IN.
Owner verdict (final, no archive): "30k probes par niveau = un gouffre de perfs anyway, on dégage TOUT,
archive même pas. GO pour la follow-probe. Pour le PBR c'est ce qui est PROCHE de nous qui compte — on ne
voit pas l'autre bout du niveau et on s'en fiche. INDUSTRY STANDARD — technos modernes, pas des hacks
pourris (le rendu plat de l'ère probes-remplace-baked était une idée à la con)."

### A. FULL REMOVAL of the baked probe-grid system (delete, not archive):
- Delete from the repo: `custom_assets/jak1/probes/village1.probes` (36MB), `tools/probe_bake/`,
  `game/graphics/opengl_renderer/ProbeBakeCore.{h,cpp}` and `LightProbeGrid.{h,cpp}`, their CMake entries
  (BOTH game/CMakeLists.txt AND android/CMakeLists.txt), the APK bundle packaging of .probes, the probe
  GL_TEXTURE_3D/SH upload path, the probe uniforms in shaders, gfx.h recharged_rt_probe_* flags/FFI.
- Delete the probe MENU rows (Baked Ambient / Baked Reflections / Baked Ambient Quality) + settings keys;
  update `.autoport/menu-tree.md` (mark [SUPPR] with the history note per the owner's doc rule).
- The world ambient stays the owner-validated BAKED-MODULATION (untouched — that fight is won).

### B. DYNAMIC FOLLOW-PROBE (the industry-standard replacement, feeding the PBR env term):
- ONE low-res cubemap CENTERED ON/NEAR THE CAMERA, re-rendered from the live world (so it automatically
  contains the current baked, TOD, all recharged layers = coherence by construction).
- AMORTIZED: 1 face per frame (full refresh every 6 frames) or a tier-selected cadence; face res tiered
  (e.g. 64/128/256). Render a CHEAP pass (world geometry, no actors needed first pass, low LOD ok).
- Prefilter cheap mips for roughness (the split-sum path consumes it exactly like before — only the env
  SOURCE changes). NEAR-FOCUS is the design point: correct for what's around the player; distant parallax
  wrongness is accepted ("on s'en fiche").
- Tiers = USER SETTINGS (same features mobile/PC): lowest = the corrected procedural IBL (no capture);
  low/mid/high = follow-probe at rising res/cadence. Wire into the presets.
- This is the env source for PBR specular now, water reflections later, dynamic-actor ambient later.

---
## OWNER PLAYTEST #4 (2026-07-23 soir) — GLASS PERSISTS. Screenshots analyzed. THE FIX = MATTE BY DEFAULT (relief without gloss).
Owner's mode decomposition (the decisive signal) + 5 screenshots (/tmp/honor_glass, archived to device dir):
- **Original (no realtime)**: GOOD. **Lighting only (realtime, no PBR)**: GOOD — no glass, no hard contrast.
- **PBR only**: acceptable DEPTH but glass-plate. **Fusion flat**: extreme contrast + hard-edge transfusions
  that DON'T occur with realtime-lighting alone. **Fusion / All-in**: contrast + "walking on glass floating
  above the textures / parts behind glass". **No tessellation** — capability check fell back to PBR (the
  crash-loop guard + fallback WORKED, no brick this time).
- Screenshot obs: rock-cliff highlight SHIFTS WITH CAMERA (view-dependent specular sheen); sand has a glossy
  wet sheen; one shot has a hard diagonal contrast line splitting grass with no geometric cause.

### ROOT INSIGHT (owner-confirmed by decomposition): glass = the PBR SPECULAR/ENV-REFLECTION term, visible
on MATTE materials where it must not be. The "depth" the owner likes = the NORMAL-MAPPED DIFFUSE relief.
SEPARATE them: keep the diffuse relief, KILL the visible gloss by default.

### MANDATE — MATTE-DIELECTRIC DEFAULT (industry-correct):
1. **Rough dielectrics (stone/sand/grass/wood = all of village1) reflect almost NOTHING.** The specular +
   env-reflection contribution must be NEAR-INVISIBLE at default on high-roughness surfaces. Drive it hard
   by roughness: at roughness≳0.6 the specular/env term → ~0. Only genuinely low-roughness/metallic texels
   get a visible highlight. Today the default specular is far too strong on matte surfaces.
2. **The default fused look = "Lighting only" + normal-mapped DIFFUSE relief, MINUS any added gloss.** A/B
   at the owner's cliff/sand vantage: PBR-ON must equal Lighting-only PLUS depth, with NO reflective sheen
   and NO camera-dependent highlight on the rock/sand. That equality IS the acceptance test.
3. **View-dependent sheen**: any term that changes with camera on a matte surface is the bug — the env
   reflection (Rf) and the Fresnel-grazing on rough surfaces must be clamped so rough matte = view-stable.
4. **Hard contrast edges (Fusion modes)**: match the contrast of "Lighting only" — the PBR path must not add
   contrast beyond the accepted baked-modulation. The "transfusions on sharp edges" = a discontinuity in the
   PBR term at geometry/UV seams; find and kill it (likely the specular/env at grazing on edge faces).
5. **Simplify the modes**: owner finds only Original / Lighting-only / (acceptable) PBR-only usable. Make the
   shipped DEFAULT = matte relief (as above); keep specular as an explicit low-default slider for shiny mats.
6. Specular INTENSITY slider default should be LOW (e.g. 0.1-0.2), not 1.0 — matte is the norm.
ACCEPTANCE: at the owner's vantages, PBR-ON = Lighting-only + depth, zero glass/sheen, no hard edges.
His eye decides; push to Honor. (Tessellation crash root-cause still open but fallback is safe — separate.)

---
## OWNER CLARIFICATION #5 (2026-07-23 soir) — SUPERSEDES THE "matte/specular" FRAMING. THE BUG IS PARALLAX/POM (DEPTH), NOT SPECULAR.
The owner corrected the diagnosis precisely — DO NOT chase specular/gloss, that was the wrong axis:
- It is NOT glossy/wet/reflective. "SANS REFLETS, aucune variation de couleur/luminosité." Ignore specular.
- It looks like a CRYSTAL-CLEAR NON-REFLECTIVE GLASS/EPOXY ~10cm in front of the textures. On grass, Jak
  appears to walk ~10cm ABOVE it; the grass seems to move DIFFERENTLY from the model it sits on
  ("parallax mais pas cohérent"). On walls: like refraction behind 10cm of a perfectly transparent prism.
- OWNER'S MENTAL MODEL OF CORRECT PBR: real-game PBR gives DEPTH TO THE 3D MODEL — surface relief that
  looks like the geometry itself has bumps (via NORMAL-MAP SHADING; tessellation makes it even more
  convincing). It must NOT look like the texture is imprisoned in clear epoxy inside the model. On a
  material-preview sphere, good PBR makes the SPHERE'S GEOMETRY look influenced — not the texture trapped
  in epoxy. THAT is the target sensation.

### ROOT CAUSE (near-certain): the PARALLAX OCCLUSION MAPPING is the "epoxy/floating texture" bug.
1. **POM depth scale is FAR too large / miscalibrated** (~10cm apparent vs the ~cm-or-less real surface
   micro-relief) AND/OR the parallax view vector / tangent-space math is wrong, so the UV-offset makes the
   texture appear to float at a wrong depth, decoupled from the geometry (the "moves differently than the
   model" = the incoherent parallax).
2. **THE RELIEF MUST COME FROM NORMAL-MAP SHADING, NOT UV DISPLACEMENT.** Default DISPLACEMENT = the shading
   approach: perturb the normal so the LIGHT reacts to fake bumps that are LOCKED to the surface — the model
   reads as having depth, nothing floats. This is surface-locked and cannot produce the epoxy effect.
3. **Parallax/POM**: either DISABLE it by default (normal-map shading alone already gives the game-correct
   relief), or fix it to be coherent + subtle (tiny depth scale, correct tangent-space offset, proper
   self-occlusion) so it never floats. When it's on, the offset must be visually LOCKED to the surface.
4. **Tessellation** = the REAL geometric displacement (actual vertices moved) — that's the convincing one
   when the driver supports it; its crash/fallback is a separate track.
5. **Extreme contrast without cause (still open)**: unrelated to the epoxy bug — the PBR path adds contrast
   discontinuities where realtime-lighting-alone does not. Match "Lighting only" contrast.
ACCEPTANCE (owner vantages, grass + cliff): the texture relief is LOCKED to the surface (no floating, no
10cm epoxy, no independent parallax motion) — the MODEL looks like it has depth, exactly like PBR in modern
games / a preview sphere with influenced geometry. His eye decides.
NOTE: the earlier "matte-dielectric / low specular" changes are FINE to keep (rough = low spec is correct)
but they are NOT the fix for this defect — the epoxy/parallax fix is the priority.

---
## OWNER CORRECTION #6 (2026-07-23) — DISPLACEMENT IS REQUIRED (do NOT disable it). Make it CORRECT + make TESSELLATION actually WORK.
Refines #5: the owner does NOT want POM/displacement turned off. He wants displacement WITH the PBR —
tessellation ON or OFF — but DONE RIGHT (not the broken 10cm-epoxy floating version). And the tessellation
path must actually FUNCTION (not just crash→fallback).
1. **KEEP displacement, FIX its calibration** (this is the "well done" bar):
   - Depth scale is ~100x too large (the ~10cm float). Calibrate to real surface micro-relief (millimetres–
     low cm), material-appropriate, tunable via the existing Texture-Relief slider but with a SANE default
     that reads as surface depth, never floating.
   - Correct tangent-space + view-vector math so the parallax offset is LOCKED to the surface (silhouette
     and motion coherent with the geometry — no independent drift, no "grass moves differently than model").
   - Steep POM with proper ray-march + self-occlusion + edge/silhouette handling so it looks like the MODEL
     has depth, not a floating texture layer. Parallax = the fallback tier; tessellation = the premium tier.
2. **MAKE TESSELLATION WORK (mandatory this round)**: root-cause the Adreno 8xx (SD 8 Elite Gen 5) crash —
   shader compile/link log, glPatchParameteri, GL_PATCHES draw path, EXT_tessellation_shader init, patch
   vertex count. It must actually tessellate + displace real geometry on the Honor without crashing (the
   capability-check FALLBACK stays as the safety net, but the goal is REAL tessellation running, not falling
   back). Prove it renders displaced geometry on-device (wireframe/pixel evidence that vertices moved).
3. Displacement quality bar = "like PBR in modern games": depth belongs to the 3D MODEL surface; tessellation
   makes it more convincing (real vertices), parallax approximates it (surface-locked). Neither floats.
4. (still open) extreme-contrast-without-cause on the fused path — match "Lighting only" contrast.
ACCEPTANCE: displacement present and CORRECT (surface-locked depth, no epoxy float) in BOTH parallax and
tessellation modes; tessellation runs on the Honor. Owner's eye at the grass/cliff vantages.

---
## OWNER PLAYTEST #7 (2026-07-23 nuit) — ITERATION FAILED. ROOT CAUSE = BROKEN TANGENT BASIS (TBN). Fix the foundation.
Owner (justified fury): the last build NEUTERED displacement (reduced depth to invisible = NOT fixed), the
extreme contrast was IGNORED, and TESSELLATION STILL FALLS BACK TO PARALLAX (does not run — "me mens pas").
Observed: PBR-only ≈ Lighting-only except the texture "offsets a bit", NO relief, NO displacement. Fusion /
Fusion-flat / All-in: same — "the normals play a bit", lackluster. AND: **as soon as Texture Relief > 0.0,
hard ultra-contrasted CRACKS appear on faces where it makes no sense.**

### ROOT CAUSE (the two symptoms together prove it): THE TANGENT BASIS IS BROKEN.
tfrag/tie/shrub geometry has NO per-vertex tangents; the shader reconstructs TBN from screen-space
derivatives (dFdx/dFdy of pos+UV), which are DISCONTINUOUS at triangle edges / UV seams. Result:
(a) normal-mapped relief is incoherent and weak (no convincing depth), and (b) scaling relief amplifies the
discontinuities into HARD CONTRAST CRACKS on faces (exactly the owner's report). The parallax also rode this
broken TBN (the earlier "floating/epoxy"). STOP tuning depth scales — FIX THE TBN.

### MANDATE — build a PROPER TANGENT BASIS (the foundation of all normal-mapping + parallax):
1. **Compute real per-vertex tangents at LOAD time** (MikkTSpace-style / industry standard): derive tangent
   + bitangent from the mesh positions + UVs per triangle, accumulate per vertex, orthonormalize
   (Gram-Schmidt vs the vertex normal), store handedness (w sign). Add a tangent vertex attribute to the
   tfrag/tie/shrub vertex format (or a parallel buffer) and feed it to the shaders. This is where the
   real per-vertex smooth normals already are — attach tangents alongside.
2. **Shader uses the interpolated per-vertex TBN** (not screen-space derivatives) for BOTH the normal-map
   perturbation AND the parallax offset. Continuous across faces => no cracks, coherent relief.
3. **THEN restore VISIBLE displacement** with a sane depth (the neutered 0.02 was over-corrected): with a
   correct TBN the relief reads as real surface depth without floating or cracking. Parallax must be
   clearly visible (not "offsets a bit") yet surface-locked. Default relief that actually shows depth.
4. **HARD GATE: at Texture Relief > 0 there must be NO contrast cracks on flat faces.** This is a blocker.
5. **TESSELLATION MUST ACTUALLY RUN (not fallback) — root-cause it for real:** the capability check is
   either wrongly disabling it or the tess control/eval shaders fail to compile/link on Adreno 8xx. Get the
   REAL GL error (glGetProgramInfoLog / glGetError around patch setup + link). If EXT_tessellation_shader is
   present, GL_PATCHES + glPatchParameteri must work. Do not claim it works without device proof; if you
   cannot access the Honor, emit clear on-screen/logcat diagnostics so the SUPERVISOR can pull the Honor
   logcat and feed back the exact error. Fallback stays as safety, but the GOAL is real tessellation.
6. Extreme contrast (#4) and displacement (#3) are the same TBN fix — do not treat them separately.
ACCEPTANCE: relief clearly visible + surface-locked (looks like the MODEL has depth), zero cracks at any
relief level, tessellation actually running on the Honor (or a captured GL error explaining why not).
This is a FOUNDATION fix (per-vertex tangents), not another parameter tune. Owner's eye decides.

**OWNER (2026-07-23) — PRECOMPUTE the tangents, don't compute them every load.** The tfrag/tie/shrub mesh is
STATIC (baked in fr3) so the tangent basis never changes at runtime — computing it at each level load is
wasted CPU. Do it the industry way (like glTF ships tangents in the asset):
1. **BAKE the per-vertex tangents ONCE** in a deterministic programmatic step (mirror GrassBakeCore style):
   read the stock fr3 mesh (positions+UVs+normals), compute MikkTSpace tangent+bitangent+handedness per
   vertex, write a small per-level sidecar (e.g. `<level>.tangents`) — tiny data (~one vec4/vertex, a few
   hundred KB/level, NOTHING like the 36MB probe grid). COMMIT it to the repo + BUNDLE in the APK (same
   packaging path the probes used, now freed).
2. **At load: just UPLOAD the baked tangents** as the vertex attribute — zero per-load tangent computation.
3. **Load-time compute stays ONLY as a graceful FALLBACK** when the baked sidecar is absent (dev builds
   before the bake runs, or a level without baked tangents) — so the feature always works, but ships
   optimized. Log which path was used.
This is the clean, cheap, correct approach; it reuses the (now-free) bundled-asset plumbing.

---
## OWNER PLAYTEST #8 (2026-07-24) — FACETED SHADING = the base NORMAL is per-face, not smooth per-vertex. + displacement FLAT + tessellation still fallback.
Owner: epoxy/floating is GONE (good), but displacement is now FLAT (no depth), tessellation still not working
(silent fallback to parallax — supervisor confirmed the game runs at displacement=2 without crashing but
shows parallax), and the "TBN cracks" are NOT much better — same severity, DIFFERENT places.
SCREENSHOT (device/owner_facets/tbn_1.jpg, archived): the GRASS around Jak is broken into HARD TRIANGULAR
PATCHES of different brightness that follow the mesh triangulation — classic FACETED / FLAT-SHADED lighting.

### ROOT CAUSE (from the screenshot, objective): the BASE SHADING NORMAL (the N in TBN) used by the fused
PBR path is PER-FACE (screen-space derivative of position, or a flat face normal), NOT the smooth
per-vertex normal. The tangent round added T/B but kept a FACETED N. Consequences:
- hard triangular lighting patches (each triangle shades flat → visible facets = the owner's "cracks"),
- the faceting WASHES OUT the normal-map relief → looks FLAT.
Note: "Lighting only" looks smooth because it leans on the baked per-vertex vertex-colors; the PBR N·L path
introduces the faceted normal, so facets appear only with PBR.

### MANDATE:
1. **Use the SMOOTH per-vertex normal as the base N in the fused PBR path.** tfrag/tie/shrub have (or can get,
   as the grass-overhang work did with barycentric smooth vertex normals) smooth per-vertex normals — pass
   them as a vertex attribute and interpolate; DO NOT reconstruct the base normal from screen-space
   derivatives. Then build the TBN from this smooth N + the per-vertex tangent (already added) → continuous
   frame → NO facets. This fixes BOTH the triangular cracks AND the flatness (relief no longer washed out).
2. **After the smooth-normal fix, the normal-map + parallax relief must read as real surface depth** (not
   flat). Calibrate relief to be clearly visible now that the base is smooth.
3. **TESSELLATION diagnostics (mandatory): the renderer emits NOTHING about why tessellation falls back** —
   the supervisor could not extract any GL/capability log on the Honor. ADD a clear, greppable log line
   (tag e.g. "[pbr-tess]") at: capability query result (EXT_tessellation_shader present?), tess control/eval
   shader compile status + infolog, program link status + infolog, and the fallback decision + reason. Route
   it through GK_STDOUT so `adb logcat -s GK_STDOUT:I` shows it. THEN root-cause + fix using that output.
ACCEPTANCE: grass/faces show SMOOTH lighting (no triangular facets) at any relief, relief reads as depth,
and tessellation either runs or logs exactly why it can't. Owner's eye + the supervisor can pull the tess log.

**SUPERVISOR DEVICE FINDING (Honor Adreno 840, 2026-07-24): the hardware EXPOSES `GL_EXT_tessellation_shader`
(confirmed in the system GL context).** So the tessellation fallback is a SOFTWARE issue, NOT hardware:
- Check the APP's actual runtime GL context: `glGetString(GL_EXTENSIONS)` / GLES-3.2-core — does it list
  tessellation there too? (SDL/EGL context may differ from the system compositor's.)
- If the extension IS present but tessellation still falls back, the bug is one of: (a) `glPatchParameteri`
  / tess entry points are NULL (function-pointer resolution via SDL_GL_GetProcAddress/eglGetProcAddress
  failed — the A23-class fn-ptr issue), (b) the tess-control/tess-eval shaders fail to compile/link (get the
  infolog), or (c) the capability check is wrongly gating it off. The `[pbr-tess]` GK_STDOUT logs must print
  which of these it is. The supervisor will pull that log on the Honor once the build lands.
The owner has GRANTED free use of the Honor to the supervisor for objective capture (tess logcat, boot
checks on the real Adreno 840 target) — leverage it: after the build, the supervisor captures the exact
tessellation diagnostic on-device and feeds the root cause back if the worker hasn't nailed it.

**SUPERVISOR FINDING #2 (Honor, 2026-07-24): the Honor OBSCURES logcat (Honor "HKS" encrypted markers) — the
app's stdout/GK_STDOUT is NOT readable via `adb logcat` on the Honor, and the app writes no .log file.** So
routing tess diagnostics only through GK_STDOUT/logcat is USELESS on the real tessellation-capable device
(the Redmi Adreno 618 has readable logcat but does NOT support tessellation, so it can't diagnose the Honor
path). REQUIRED: the `[pbr-tess]` diagnostics MUST be written to a FILE in the app's files dir
(e.g. `files/pbr_tess_diag.txt`) that the supervisor can pull via `run-as org.opengoal.gk.jak1 cat
files/pbr_tess_diag.txt` on the Honor. Log there: EXT_tessellation_shader present in the APP GL context
(y/n), glPatchParameteri/tess entry-point addresses (NULL?), tess-control/eval compile status + infolog,
program link status + infolog, and the final on/off decision + reason. (An on-screen debug line the owner
can screenshot is an acceptable secondary channel.) With this file, the supervisor will read the exact
Adreno-840 tessellation root cause off the Honor and feed it back.

---
## OWNER PLAYTEST #9 (2026-07-24) — FACETS UNCHANGED. My #8 base-normal diagnosis was WRONG. Real cause = the NORMAL-MAP TANGENT frame is per-triangle (degenerate per-vertex tangents).
Owner: "les facettes sont toujours là, ça n'a rien changé." Supervisor READ THE ACTUAL SHADER (tfrag3.frag):
- The BASE lighting normal N is ALREADY the smooth per-vertex normal `v_normal` when present (line ~473,
  `u_rt_flat_normal==0 && Nsl2>0.2`) — so the base normal is NOT the facet source for tfrag ground.
- The facets appear ONLY at Texture-Relief > 0 (owner) => they come from the NORMAL-MAP application, i.e.
  the TANGENT frame. In the shader (line ~550): the per-vertex tangent `v_tangent` is used ONLY if
  `dot(v_tangent.xyz,v_tangent.xyz) > 0.04`; OTHERWISE it FALLS BACK to a screen-space-derivative TBN
  (dFdx/dFdy, line ~558) which is PER-TRIANGLE CONSTANT => the normal-map is applied in a discontinuous
  frame => hard triangular facets that scale with normal-map strength (= Texture Relief). THIS is the bug.

### ROOT CAUSE: the per-vertex tangent `v_tangent` is DEGENERATE / near-zero for the ground geometry (grass
is where the owner sees it) → the shader silently falls back to the screen-derivative TBN → facets. Round #7
"added tangents" but they are not actually populated / non-degenerate for the surfaces the owner looks at.

### MANDATE:
1. **DEVICE-PROVE the tangent coverage FIRST (bisection, not theory):** add a debug viz / counter that reports,
   for the visible ground, the FRACTION of fragments taking the degenerate-tangent FALLBACK (the `else`
   branch). Write it to `files/pbr_tess_diag.txt` (or a `pbr_tan_diag.txt`) — the Honor obscures logcat, use a
   FILE. The supervisor will pull it off the Honor. If the fallback fraction is high on the grass, the
   tangents are degenerate there = confirmed.
2. **FIX the tangent generation so v_tangent is valid (non-degenerate, unit, correct handedness) for ALL
   drawn geometry the PBR touches — tfrag ground FIRST** (that is the grass). Likely causes: the MikkTSpace
   accumulation produces ~0 tangents where UVs are degenerate/mirrored, or the tangent attribute isn't
   populated for tfrag draws, or it's not uploaded/bound for the ground buckets. Handle degenerate-UV verts
   with a stable fallback tangent DERIVED FROM THE SMOOTH NORMAL (an arbitrary but CONTINUOUS per-vertex
   tangent, e.g. Frisvad/Duff branchless basis from N), NEVER the screen-space derivative (which is the
   facet source). A per-vertex continuous tangent — even an arbitrary one — kills the facets.
3. Re-verify on device: fallback fraction ~0 on the grass, and facets GONE at relief>0.
ACCEPTANCE: grass/faces smooth at any relief (owner's eye), and the tangent-fallback fraction file proves
near-zero screen-derivative usage. Stop theorizing base-normal; the tangent frame is the proven culprit.

---
## OWNER PLAYTEST #10 (2026-07-24) — FACETS STILL PRESENT despite 0% tangent-fallback. STOP GUESSING. Give the owner an IN-MENU BISECTION + attack parallax.
Facets persist on the grass (owner screenshots f_1/f_2, archived) even though the tangent-fallback device
diag proved 0% screen-derivative fallback. So the tangent was NOT the (whole) cause. The supervisor cannot
reach the owner's grass vantage headlessly (title waits for input) — so the OWNER must be able to isolate the
term himself at his vantage.
1. **ADD an IN-MENU debug carousel "PBR ISOLATE" (Recharged Settings, debug, removable):** wired to the
   existing bisect mask so the owner can flip, at his vantage, WITHOUT adb:
   - "BOTH" (normal-map + parallax on) = bisect 0
   - "NORMAL-MAP ONLY" (parallax off) = bisect 128
   - "PARALLAX ONLY" (normal-map off) = bisect 64
   - "NEITHER" (both off) = bisect 192
   Live-applied, persisted, menu-tree synced. This lets the owner report EXACTLY which term produces the
   triangular facets. That answer drives the real fix — no more supervisor theories.
2. **PRIME SUSPECT to investigate now (tangent is proven continuous, base normal is smooth): the PARALLAX.**
   Texture-Relief scales normal-map AND parallax. With a continuous tangent, per-triangle facets most likely
   come from the STEEP-POM: (a) UV-offset ray-march clipping at triangle/UV-chart boundaries, (b) the
   tangent-space view vector or height-scale having a per-triangle component, (c) self-occlusion silhouette
   snapping per triangle. Audit the POM: does turning parallax OFF (normal-map on) remove the facets? If yes,
   the POM is the source — fix the per-triangle discontinuity (clamp offset at chart edges, continuous view
   vector, smooth height sampling). Add the POM's per-triangle-fallback (if any) to files/pbr_tan_diag.txt.
3. Report which of normal-map-only vs parallax-only shows facets in YOUR device A/B (the worker can capture
   via the bisect prop on the Redmi even if the grass differs — the facet PATTERN presence is the signal),
   and let the owner confirm on the Honor with the menu carousel.
ACCEPTANCE: the owner can isolate the term in-menu; the identified term's per-triangle discontinuity is
fixed; facets gone at his vantage. No more "fixed" claims without the owner's in-menu bisection confirming.

---
## OWNER PLAYTEST #11 (2026-07-24) — the PBR-ISOLATE menu I shipped is BROKEN: options show "Unknown ID 5924-5927" and flipping does NOTHING. Fix it properly + supervisor verifies before shipping.
The 4 carousel options are UNREGISTERED text-ids (Unknown ID 5924-5927) and the isolate value does not
reach the shader (flipping has no effect). This is a broken diagnostic tool handed to the owner — unacceptable.
1. **REGISTER the 4 carousel option strings** ("BOTH" / "NORMAL-MAP ONLY" / "PARALLAX ONLY" / "NEITHER") the
   SAME WAY the working carousels do (no Unknown-ID — see the ao-low/high or displacement carousel text-id
   pattern; reuse existing text-ids or add proper ones). The row label already works; the OPTIONS must too.
2. **WIRE the isolate value so it ACTUALLY applies**: selecting an option must set the pbr_bisect mask that
   the fused shader reads (background_common.cpp already reads it at ~line 1422 from gs.recharged.., and the
   debug prop overrides at ~1482 — make sure the MENU path writes the same gs field, and that no stale prop
   overrides it to a fixed value). Prove it: write the ACTIVE isolate value + resolved bisect mask to
   files/pbr_tan_diag.txt each time it changes, so the supervisor can confirm flipping changes it on device.
3. **SUPERVISOR PRE-SHIP VERIFICATION (mandatory this round):** the supervisor will navigate the Redmi menu
   via cpad_inject (project_goptions_reorder_menu_tooling) to the PBR ISOLATE row, screenshot it to confirm
   the 4 options render as REAL LABELS (not Unknown-ID), and confirm via the diag file that flipping changes
   the bisect mask — BEFORE pushing to the owner. No more broken tools reach the owner.
4. Relationship to PBR TEST PRESET: document it — the ISOLATE row is an independent DEBUG override of the
   bisect mask; state whether it composes with or overrides the preset, and label it clearly.
5. Keep attacking the PARALLAX-continuity fix (prime suspect: tangent proven continuous, base normal smooth,
   facets tied to relief>0 => parallax/POM per-triangle discontinuity).
ACCEPTANCE: menu options are real labels + flipping provably changes the bisect mask (diag file) + parallax
investigated. Supervisor verifies the menu on the Redmi before the owner ever sees it.

---
## SUPERVISOR PRE-SHIP VERIFICATION CAUGHT IT (2026-07-24) — menu STILL Unknown-ID. NOT pushed to owner. Exact fix below.
The REOPEN#11 attempt did NOT fix the Unknown-ID. It only added a C++ LOG label in kmachine.cpp
(pc_set_pbr_isolate). The MENU DISPLAY strings are still unregistered. ROOT (I traced it):
- text-h.gc defines `pc-text-pbr-iso-both #x1724 / -nm #x1725 / -pom #x1726 / -neither #x1727` — these are
  ENUM text-ids with NO registered display STRING => the carousel shows "Unknown ID 5924-5927" (0x1724-27).
- The carousels that WORK (e.g. displacement) do NOT use bare text-ids for their visible label — they use a
  RUNTIME GLOBAL STRING: `(define *displacement-label* (new 'global 'string ...))` +
  `(format (clear *displacement-label*) "DISPLACEMENT...")`. The `*pbr-isolate-label*` row label works for
  exactly this reason; the OPTIONS do not because they use unregistered text-ids.
EXACT FIX:
1. Give the 4 carousel OPTIONS real display strings the SAME WAY the working carousels do — either register
   the strings for text-ids 0x1724-0x1727 in the game text bank, OR (simpler, matches displacement) define
   runtime global strings (`*pbr-iso-both-label*` etc. via format) and point the carousel at those. No bare
   unregistered text-id may remain. Result: the 4 options render as BOTH / NORMAL-MAP ONLY / PARALLAX ONLY /
   NEITHER, never "Unknown ID".
2. The wiring (mask 0/128/64/192) looks correct now — keep it; confirm flipping writes the mask to
   files/pbr_tan_diag.txt so the supervisor's Redmi check can confirm it applies.
3. DO NOT claim the menu is fixed in the report unless the option strings are registered as above.
The SUPERVISOR will re-verify on the Redmi (navigate to the row, screenshot real labels) before any push.
Keep the parallax-continuity fix from #11.

---
## OWNER ROOT-CAUSE BREAKTHROUGH (2026-07-24) — THE MESH IS UNWELDED. Vertex welding is the real fix. (Owner's diagnosis — correct.)
The owner found it. Observations that prove it:
- Tessellation now RUNS (deformation visible) but OPENS HOLES between polygons — "des polygones qui flottent,
  pas attachés, on voit au travers", and the holes COINCIDE with the high-contrast facet zones.
- Parallax mode: the facet/contrast zones are there but NO holes (no real displacement/subdivision).
- PBR ISOLATE (normal-map only / parallax only / etc.) makes NO visible difference → the facets are NOT from
  the normal-map or parallax; they are in the BASE geometry.
=> The tfrag/tie/shrub mesh has DUPLICATE, UNWELDED vertices at shared edges. Each triangle carries its own
copy of a shared-edge vertex. Consequences (all our symptoms):
- "Smooth per-vertex normals" never actually smoothed ACROSS seams — each duplicate only averaged its own
  triangle's face normal → faceted lighting. (This is why REOPEN#8/#9 smooth-normal + tangent work didn't
  cure the facets: the vertices aren't shared, so there was nothing to average across the seam.)
- Tessellation displaces the coincident-but-separate vertices along DIVERGENT normals → the edge tears open
  → the visible holes.

### MANDATE — VERTEX WELDING / MESH CONSOLIDATION (owner-proposed, correct):
1. In the load-time (or baked) mesh preprocessing for tfrag/tie/shrub, build a WELD MAP: vertices whose
   POSITIONS are coincident within an epsilon AND that share the same texture/tpage/material are the SAME
   logical vertex. (Do NOT weld across different textures where a genuine hard seam must stay.)
2. Compute the SMOOTH NORMAL by averaging the face normals of ALL triangles incident to each WELDED vertex
   (area/angle-weighted) — so the normal is continuous ACROSS seams → facets gone.
3. Recompute the TANGENT the same way over welded vertices (consistent with the smooth normal).
4. For TESSELLATION: the tess-eval displacement must move the WELDED (shared) vertex identically on both
   sides of a seam so edges stay CLOSED → no holes/tears. Snap coincident boundary verts to the same
   displaced position (same height sample + same normal) so neighbouring patches share the edge.
5. Bonus the owner noted: welding also fixes texture/normal discontinuities at seams.
6. DEVICE-PROVE on the Honor (supervisor will pull the diag + capture): weld stats (how many verts merged),
   facets GONE at relief>0, and tessellation with NO holes. Write weld/normal stats to files/pbr_tan_diag.txt.
This is the foundational fix all prior rounds missed. Do it in the deterministic bake if possible (owner's
earlier "precompute, don't compute every load" preference applies — a `<level>.tangents`/weld sidecar).
ACCEPTANCE: no facets (welded smooth normals cross seams), no tessellation holes (welded edges), owner's eye.

**OWNER CLARIFICATION (2026-07-24, precise framing — READ THIS):** it is NOT duplicate/overlapping polygons.
It is TWO-OR-MORE DISTINCT ADJACENT polygons sharing the same texture whose COMMON EDGES ARE NOT WELDED —
their shared-edge vertices are SEPARATE COPIES (one per polygon) instead of being the same shared vertex, so
the polygons are not topologically LINKED along that edge. Do NOT deduplicate/remove any polygon. The fix is
EDGE WELDING / topology stitching: for adjacent same-texture triangles that touch along an edge, make their
two edge vertices become ONE shared vertex (index-share), so:
- the smooth normal averages the face normals of BOTH polygons across that edge (no more contrast facet),
- tessellation moves the shared edge vertex once for both polygons (edge stays closed, no hole/see-through).
Build proper EDGE ADJACENCY (weld coincident-position + same-texture vertices into shared indices); keep
genuine hard seams (different texture/material) UN-welded. This is standard mesh stitching. Everything else
in the vertex-welding mandate above stands — this just nails that it's adjacent-polygon edge linking, not
polygon de-duplication.

---
## OWNER PLAYTEST #12 (2026-07-24) — welding "clairement mieux" but INCOMPLETE. Remaining seams = CROSS-CHUNK / CROSS-BUCKET boundaries.
Owner: "il y a encore plein de polygones pas attachés correctement... clairement mieux qu'avant, mais t'as
pas tout couvert." Screenshots (device/owner_weld2/w_1..4.jpg): the REMAINING seams are LONG straight/curved
LINES crossing large surfaces (a dark curved seam across the grass in w_4, a diagonal across the sand in w_2,
lines in w_1/w_3) — NOT micro triangle edges. These are boundaries between LARGE MESH CHUNKS / DRAW BUCKETS
(and where tfrag meets tie). The current weld only stitched WITHIN each bucket/vertex-array (hence 52-55%
welded) but did NOT weld ACROSS bucket/chunk/system boundaries → those inter-chunk seams remain.

### MANDATE — make the welding GLOBAL and COMPLETE:
1. **Weld ACROSS ALL draw buckets / chunks / fragments of the level, not per-array.** Build ONE global spatial
   hash over EVERY tfrag (and tie, and shrub) vertex in the level and weld coincident positions across bucket
   AND system boundaries. The big remaining seams are exactly the chunk edges — they must be stitched.
2. **Weld coincident POSITIONS regardless of texture for GEOMETRY** (close ALL tessellation holes — the owner
   wants surfaces connected even across a sand↔grass or chunk↔chunk boundary; no see-through gaps anywhere).
3. **Normal averaging with a CREASE-ANGLE threshold**: average normals across welded verts when the surfaces
   are near-coplanar (kills the grass/terrain facet lines), but KEEP a crease where the real angle is sharp
   (e.g. a wall meeting the ground ~90° stays a crisp edge — don't over-smooth genuine corners). Position is
   still shared there (no hole), only the normal keeps the crease.
4. **Possibly widen the weld epsilon** if 3 cm misses chunk-boundary verts that are marginally apart (snap
   near-coincident boundary verts), but stay conservative to avoid welding unrelated geometry.
5. DEVICE-PROVE on the Honor (supervisor pulls the file): the CROSS-CHUNK stitched-vert count is now large,
   and report the remaining unwelded-seam-vert count → target ~0. Facets AND holes gone at the owner's
   vantages (grass fields + sand + chunk boundaries in w_1..4).
ACCEPTANCE: no remaining seam LINES across surfaces, no tessellation holes anywhere, owner's eye on w_1..4-
type vantages.

**OWNER INSIGHT #2 (2026-07-24, coupled with the welding — do BOTH in this round):** some normals point
INWARD (into the model) instead of OUTWARD. Averaging an inward normal with an outward one across a welded
seam produces a GARBAGE average (near-opposite vectors cancel) => that is another source of the extreme
contrasts, and it CANNOT be smoothed by edge-welding alone. FIX = a NORMAL ORIENTATION CONSISTENCY pass that
runs BEFORE the normal averaging:
1. Make every vertex/face normal point toward the OPEN/visible side (outward), consistently across the welded
   mesh. Do it via consistent-winding flood-fill over the welded topology (propagate one orientation from a
   seed across shared edges), so a whole connected surface agrees.
2. **Owner's disambiguation for the "which side is outside" question (use it):** the COLLISION mesh. Where a
   render surface is coincident with WALKABLE collision, the normal must point toward the WALKABLE side (the
   side the player/camera occupies — we are meant to be there). This resolves ambiguous cases and NATURALLY
   handles interiors/tunnels: inside a house the player is on the inside, so the normal points inward-toward-
   player (correct for that room). Use collision-side as the orientation authority where available; fall back
   to the renderer's existing toward-viewer double-sided convention elsewhere.
3. ORDER: (a) global weld across chunks/buckets/systems, (b) orientation-consistency pass (flood-fill +
   collision authority), THEN (c) average normals across welded seams with the crease-angle threshold. If you
   average before fixing orientation, inverted normals poison the average = the extreme contrasts persist.
4. Device-prove: count inverted/flipped normals corrected; the extreme-contrast lines gone at w_1..4 vantages.
This is coupled with the global welding — deliver both together.

**OWNER SCOPE (2026-07-24): the welding + orientation MUST apply to the WHOLE GAME, every level — NOT just
Sandover/village1.** Implement it in the GENERIC per-level tfrag/tie/shrub load path (TFrag3Data.cpp runs for
EVERY level's fr3 data) with NO village1-specific gating or hardcoded level id. It must run automatically for
any level that loads (village1, jungle, beach, misty, rolling hills, snowy, etc.). If any part is a
precomputed bake, the bake must cover ALL levels, not just village1. VERIFY on at least ONE non-village1
level too (weld/orient stats present for it). No level-specific hardcoding anywhere in the weld/orient pass.

**OWNER (2026-07-24): PRECOMPUTE the weld+orient (don't do it every load) — but AFTER correctness is proven.**
Order the owner wants:
- STEP 1 (this round, OK as-is): compute weld + orientation + averaged normals LIVE at load, to prove the
  RESULT is visually correct (no point baking a wrong result).
- STEP 2 (follow-up, once the owner validates the LOOK): PRECOMPUTE the whole weld/orient/normal result ONCE,
  deterministically, into a per-level BAKED SIDECAR (extend the `<level>.tangents` sidecar or a
  `<level>.meshweld` — welded index map + consolidated smooth normals + corrected orientation), committed to
  the repo + bundled in the APK, uploaded directly at load = ZERO per-load weld/orient computation. Do this
  for ALL levels (whole-game bake). Load-time weld/orient stays ONLY as a graceful FALLBACK for levels with
  NO baked sidecar — e.g. future MOD support (owner's example). Log which path (baked vs live-fallback) ran.
Do STEP 2 only after STEP 1 is owner-eye-validated. The live path is expensive per load; the bake is the
shipping solution, same as the tangent precompute preference.

---
## OWNER FULL SPEC (2026-07-24) — COMPLETE GEOMETRY CONSOLIDATION. Do ALL of it. Killer feature, do NOT park.
The 96%-weld metric did NOT translate to the owner's eye — hard grass seams persist near the player.
Owner's clues + full spec (implement ALL, comprehensively, programmatically):
1. **BAKED MOVES WITH TOD** — for ALL testing/verification, FREEZE the time of day at a DAYTIME hour so the
   baked is stable AND the PBR is visible (PBR is invisible/flat at night, so night tests are useless). Add
   a debug prop to freeze TOD if not already reliable (debug.opengoal.tod.hour + freeze). Report captures at
   a fixed daytime hour only.
2. **WELD every adjacent same-texture polygon/chunk that SHOULD be connected** — not 96%, aim for the VISIBLE
   seams gone. Widen the epsilon / handle the remaining ~47k open-seam verts; weld coincident positions
   across chunk/bucket/tree/system boundaries for same-texture neighbours (and geometry-weld across texture
   boundaries to close holes).
3. **ORIENTATION: fix adjacent chunks with OPPOSITE orientation** (owner: "deux chunks côte à côte, un à
   l'endroit, un à l'envers"). Flood-fill a consistent outward winding over the welded topology; use the
   COLLISION mesh as the authority for "which side is outward" (walkable side); handle interiors/tunnels.
4. **SMOOTH THE UVs at seams** (owner: "lisser les UV") — texture-coordinate continuity across welded seams
   so textures don't break at chunk boundaries.
5. **NORMAL SMOOTHING with a threshold that ACTUALLY smooths the terrain**: adjacent grass/ground chunks meet
   at GENTLE angles and must be smoothed to a nuance (not a hard face) — tune the crease-angle threshold so
   these gentle seams smooth out, while genuine sharp corners (wall↔ground ~90°) stay crisp. The owner's
   remaining hard grass edges = gentle seams being wrongly kept as creases OR still-faceted normals; fix so
   "faces clairement visibles où ça devrait juste être nuancé" become nuanced.
6. **DEBUG A/B TOGGLE (mandatory, so the supervisor can verify on-device):** debug.opengoal.mesh.weld (or
   similar) that DISABLES the whole weld/orient/smooth pass at runtime, so weld-ON vs weld-OFF can be A/B'd
   at a fixed daytime vantage — proving the seams come from the geometry pass.
7. DEVICE-PROVE (Redmi is available to the supervisor): at a FIXED DAYTIME hour + a grass vantage, the
   visible seams are GONE with weld ON vs the seamy weld-OFF. Not a % — the actual seams.
This is the whole-game geometry consolidation the owner has been describing. Live at load for now
(precompute/sidecar is the documented STEP 2 after the LOOK is validated). Do it thoroughly this round.

---
## OWNER CRITIQUE (2026-07-24) — the weld is FAKE: it only averages normals, it does NOT fuse the points. + WORSE (new clean cuts). + supervisor tested BLIND.
Supervisor READ the code (TFrag3Data.cpp reconstruct_*_smooth_normals): it groups coincident verts into
`vert_group`, averages the face normals per group, and writes the averaged normal back — but it NEVER
rewrites the INDEX BUFFER. The coincident vertices stay SEPARATE (each triangle keeps its own vertex copy);
only the normal is equalized. Owner is right: "tu lies les arêtes pour de vrai (fusion des points)?" — NO,
it doesn't. Consequences: geometry never truly linked => tessellation subdivides coincident-but-separate
verts independently => HOLES persist; and normal-averaging + crease threshold on still-separate verts create
NEW CLEAN CUTS where there were none two builds ago (owner: "c'est même pire").

### MANDATE — TRUE TOPOLOGICAL WELD (index-buffer merge), not normal-averaging:
1. **Rewrite the INDEX BUFFER**: for each group of coincident same-texture vertices, pick ONE representative
   vertex and REMAP every index in the draw's index buffer to that representative. The two triangles must
   reference the SAME shared vertex (real point fusion), so the shared edge is topologically ONE edge.
2. Only merge verts that are safe to merge (coincident position + same texture/tpage; and compatible UV —
   if UVs differ at a legit texture seam, keep separate OR handle UV continuity per the owner's "lisser les
   UV"). Do NOT merge across genuine hard seams (different material).
3. **TESSELLATION crack-free**: with a truly shared edge, ensure the tess-control emits MATCHING edge
   tessellation factors on the shared edge so the two patches subdivide it identically => no cracks/holes.
4. Orientation pass + averaged normals still apply, but now on the MERGED (shared) vertices.
5. Verify NO NEW clean cuts are introduced (the fix must not regress previously-smooth areas — the owner saw
   new cuts). Compare against a build with the weld OFF.

### SUPERVISOR TEST METHOD FIX (owner: "tes tests Redmi tu fais pas avec tessellation, ni relief, ni PBR,
tu y vas à l'aveugle"): every device capture MUST enable the FULL stack in settings.ini/props before
capturing: pbr-materials? = #t, realtime lighting ON, pbr-texture-relief > 0 (e.g. 1.5), pbr-displacement = 2
(tessellation), tod.hour = 12 (daytime, PBR visible), AND wait PAST the ND logo (~40s after first render)
before capturing actual grass — else the capture shows a PBR-less / logo frame = worthless. The worker's
fullspec_weldon/off captures were the ND LOGO = invalid; do not repeat.
ACCEPTANCE: real index-merge (shared verts, provable: index buffer references shrink / shared-edge count),
no tessellation holes, NO new clean cuts, owner's eye at a daytime grass vantage with the full PBR stack on.

**OWNER — THE STRICT ORDER (2026-07-24): FUSE FIRST, THEN smooth, THEN orient. Everything before was bogus
because it smoothed/oriented on a NON-fused topology.**
STEP A — TRUE FUSE: rewrite the index buffer so coincident same-texture verts become ONE shared vertex/index
  (real topological merge). After this step the mesh has genuinely shared edges — the seam is ONE edge, not
  two coincident copies.
STEP B — SMOOTH: only NOW average the normals, over the truly-merged vertices. (Averaging before fusing =
  bogus, the current bug.)
STEP C — ORIENT: the winding/orientation flood-fill runs on the MERGED topology so it can propagate ACROSS
  the (now real) shared edges; collision authority for outward side. (Orientation on non-fused topology
  could not cross the fake seams = also bogus.)
STEP D — UV continuity + tessellation matching-edge-factors on the shared edges.
Do them in THIS order. If STEP A (real index merge) is not done, B/C/D are all meaningless — that is exactly
what has been shipped so far. The whole point is STEP A must be a genuine geometry merge.

---
## OWNER PLAYTEST #14 (2026-07-24) — seams PERSIST after real fusion. THE GAP: fusion only merged 24-30% (fully-identical verts); the UV/COLOR-seam verts (70%) were NEVER SMOOTHED.
Screenshots device/owner_seam3/s_1..3.jpg: diagonal grass seam (s_1), hill brightness seam (s_2), hard line
in the SAND (s_3). The real index-fusion merged only index_fused_tfrag=37642/158078 (24%) and
tie=466933/1563934 (30%) — i.e. ONLY the fully-attribute-identical coincident verts. The remaining ~70% are
coincident verts at chunk/UV boundaries whose UV or baked COLOR differ, so they were NOT fully fused AND (per
the "fuse then smooth" order) were NEVER given an averaged normal => their per-triangle normals persist =>
the visible LIGHTING seams (they show in daytime PBR, so it is the lit-normal contribution, not baked color).

### THE COMPLETE FIX — split-by-UV, SHARED NORMAL (industry standard). Two classes of coincident verts:
1. **Fully identical (position+color+UV)** → REAL index fusion (already done). Keep.
2. **Coincident position + SAME TEXTURE but different UV and/or color** (the ~70%, the seam verts) → they
   CANNOT be index-merged (a vertex can't hold two UVs), BUT their SMOOTH NORMAL must still be AVERAGED BY
   POSITION across all same-texture coincident corners. This is the standard "smoothing group by position,
   split by UV" technique: the verts stay separate for UV/color, but SHARE the averaged normal => the
   LIGHTING is continuous across the UV/chunk seam => the seams GO AWAY.
   → Compute smooth normals over a POSITION+texture weld map (~all coincident same-texture verts, the ~96%),
     and ASSIGN that averaged normal to every coincident corner (fused or UV-split alike).
3. **Orientation** flood-fill likewise over the position weld map (not only the fully-fused subset).
4. **Tessellation crack-free at UV-split edges**: the two UV-split verts share position + normal; ensure they
   get MATCHING edge tessellation factors and the SAME height displacement so they stay coincident after
   displacement (no hole). For fully-fused edges it is automatic.
So: normal SMOOTHING is by POSITION (all coincident same-texture, ~96% coverage), while index FUSION is only
for identical verts (tessellation topology). The bug: normals were only smoothed on the 24-30% fused subset.
The owner's "fuse then smooth" is right — but the SMOOTH step must cover the position-coincident verts too,
not just the index-fused ones.
ACCEPTANCE: no lighting seams at chunk/UV boundaries (grass s_1/s_2 + sand s_3), no tessellation holes,
daytime + full PBR/relief/tessellation stack. Report the normal-smoothed-corner coverage (must be ~the full
coincident set, not 24-30%).

**OWNER WORKFLOW (2026-07-24): position-dump for deterministic A/B.** The owner will position at a seam; the
supervisor must READ his exact world position to warp there for A/B captures. The Honor obscures logcat
(HKS), so lg::info is unreadable there. ADD a small debug: on debug.opengoal.dump.pos = "1" (or each frame
while set), WRITE Jak's current world position "X Y Z" (and camera heading if easy) to
files/pos_dump.txt (app files dir, readable via `run-as $PKG cat files/pos_dump.txt`). Cheap, tiny. This
lets the workflow be: owner stands on a seam -> supervisor triggers the dump -> reads pos_dump.txt off the
Honor -> warps to that exact debug.opengoal.level.warp.pos on the Redmi/Honor for weld-ON vs weld-OFF
daytime A/B. Keep it in this round.

---
## ★ SUPERVISOR LIVE A/B ON THE OWNER'S HONOR (2026-07-24) — DEFINITIVE: the hard patches are caused by the NORMAL-MAP APPLICATION (relief>0), and the remaining discontinuity is the PER-CHUNK **UV FRAME**.
Captured at the owner's exact vantage, same frame, only the relief prop changed (device/relief_ab/):
- `debug.opengoal.pbr.relief 0`   -> ground SMOOTH, NO hard transitions (R0.png)
- `debug.opengoal.pbr.relief 2.5` -> HARD PATCHES appear (distinct dark/light polygon regions in the grass)
  (R25.png)
So the seams are created by APPLYING THE NORMAL MAP, and they scale with relief — exactly as the owner said.
Tangents are now continuous (0% screen-deriv fallback) and normals are smoothed by position, so the ONLY
remaining per-chunk discontinuity in the normal-map application is the **UV FRAME / UV PARAMETERISATION**:
each tfrag chunk has its own UV layout (offset/scale/rotation/mirroring), so the SAME world surface samples
the normal map with a DIFFERENT tangent-space orientation on each side of a chunk boundary => the fake relief
is lit from opposite directions => hard plates. The diag confirms the UV work was minimal:
global_uv_snapped_seam_verts = 11,139 out of ~2.3M verts.

### MANDATE — make the normal-map tangent frame CONSISTENT across chunk boundaries:
1. **Detect UV-frame discontinuity at welded seams**: for coincident verts from different chunks, compare the
   derived tangent frame (dU/dV direction + handedness + UV scale). Where the surface is continuous but the
   UV frame differs (rotation/mirror/scale), the normal-map lighting will break.
2. **Fix options (pick what works, in order of preference):**
   a. **Align the tangent frame across the seam** — recompute/rotate the tangent basis of the neighbouring
      chunk so the tangent-space orientation is CONTINUOUS across the boundary (the normal map may still be
      offset in UV, but the LIGHTING direction becomes consistent => no plates).
   b. If UV scale/mirroring differs drastically, fall back to a **world-space-derived tangent frame** for the
      normal map on terrain (triplanar-style or a stable world-aligned frame), which is inherently continuous
      across chunks. This is the standard trick for chunked terrain with per-chunk UVs.
   c. Blend/fade the normal-map perturbation strength near a detected frame discontinuity as a last resort.
3. Verify with the SAME live A/B (relief 0 vs 2.5 at the owner's vantage): at relief 2.5 the ground must stay
   free of hard patches. The supervisor can now do this A/B live on the Honor while the owner plays
   (screencap + `debug.opengoal.pbr.relief`), so verification is cheap and objective.
ACCEPTANCE: relief 2.5 shows RELIEF, not plates. The relief-0 vs relief-2.5 pair must differ only in surface
detail, not in flat brightness patches.

---
## OWNER PLAYTEST #16 (2026-07-24 23h) — "BEAUCOUP BEAUCOUP MIEUX" (UV-frame fix works!) but TWO precise defects remain. Screenshots device/owner_final2/n_1..5.jpg.
The world-axis seam-stable tangent frame FIXED the hard plates (owner: "beaucoup beaucoup mieux"). Remaining:

### DEFECT A — TESSELLATION HOLES (n_5 sand close-up, n_4): visible DARK SLITS between polygons — you can
SEE THROUGH the mesh along polygon edges when tessellation is on.
ROOT (near-certain): at a chunk/UV seam the two coincident verts are still SEPARATE vertices (they must be:
different UVs). The tess-eval displaces each along the normal by a HEIGHT SAMPLED AT ITS OWN UV — and because
each chunk has its own UV layout, the two sides sample DIFFERENT height texels => DIFFERENT displacement
amounts => the shared edge tears open => the slit.
FIX: make the DISPLACEMENT identical on both sides of a seam:
  1. Mark seam/boundary verts (the weld map already knows them: coincident position, different UV).
  2. For those verts, use a SEAM-CONSISTENT height: e.g. sample the height with the SAME world-derived
     coordinate used for the seam-stable tangent frame (world-space/triplanar height lookup at boundary
     verts), OR average the height across the weld group and force that value on every member, OR simply
     FADE THE DISPLACEMENT TO ZERO within a small band around detected open-boundary edges (safest).
  3. Also match tess EDGE FACTORS on shared edges (already mandated) so the subdivision matches.
  Acceptance: no see-through slits at any relief/tessellation setting (n_5 vantage).

### DEFECT B — SEAM LINES STILL VISIBLE AT RELIEF 0 (n_1/n_3 grass, n_4 sand at relief 0 AND 3; the owner
notes it is "surtout sans relief" on grass): so this is NOT the normal-map — the remaining discontinuity is
either (a) the smoothed NORMAL still differing across the seam for some verts (crease-threshold splitting
them, or verts not in the same weld group), or (b) the BAKED VERTEX COLOR differing per chunk at the seam
(per-chunk baked lighting => a brightness step no normal work can fix).
FIX: diagnose which, then:
  (a) if normals: widen/repair the weld grouping for those verts, verify the crease threshold isn't splitting
      gentle terrain seams; report the fraction of boundary verts whose normal still differs > few degrees.
  (b) if baked color: blend/average the baked vertex COLOR across welded seam groups (position-coincident,
      same texture) so the lit brightness is continuous — a small, safe, artist-invisible correction.
  Use a debug viz (u_pbr_debug mode) that renders the normal delta and the baked-color delta at seams so the
  cause is identified objectively, and report the numbers.
ACCEPTANCE: no visible seam lines on grass/sand at relief 0 AND at relief 3, no tessellation slits.
The supervisor can A/B live on the owner's Honor (screencap + props) — use that.

---
## MESH-CONSOLIDATION VALIDATED BY THE OWNER (2026-07-25): "call me impressed, c'est validé... plus aucune
erreur vraiment remarquable, c'est nickel". Residuals he still notices (LOW priority, fold in opportunistically
while doing the PBR work, do NOT regress the mesh result): a few remaining NORMAL issues and small COUTURES.
THIS PHASE NOW = THE PBR RENDERING POLISH. The owner's recorded defects (from playtest #16):
1. **Displacement in the WRONG DIRECTION** in places on the SAME texture (sign/handedness of the height or
   the tangent frame flipping per patch) — find and fix the sign consistency.
2. **Completely FLAT in shadow / where the sun does not hit** — the relief must remain readable in shade:
   the ambient/indirect term must also be modulated by the normal-mapped surface (currently only the direct
   sun lights the relief, so shadowed areas lose all depth). Industry: ambient occlusion + normal-influenced
   ambient (SH/irradiance dotted with the perturbed normal), not a flat ambient constant.
3. **Displacement reads FLAT despite tessellation/parallax — "un bump map glorifié avec un peu de normales"**:
   needs real perceived depth — correct displacement amplitude/scale on the tessellated geometry, self-
   shadowing of the relief (parallax self-occlusion / micro-shadowing from the height map), and silhouette
   effect where tessellation is on. The goal is "comme les jeux modernes", not a shaded bump.
Keep the validated mesh consolidation intact (it is the foundation everything now rests on).

---
## OWNER PLAYTEST #17 (2026-07-25) — displacement direction FIXED ✅, mesh not regressed ✅. STILL: flat in shadow, glorified bump, tessellation lacks detail.
Owner: "je vois plus le displacement inversé, ça a l'air bon... par contre ça fait toujours juste bump map
glorifié, la tesselation manque de détail et ne donne pas vraiment de profondeur, à l'ombre c'est toujours
plat, le parallax c'est pareil. TRÈS CONTRASTÉ À LA LUMIÈRE (mais quand même plat), TRÈS PLAT À L'OMBRE.
La consolidation des mesh n'a pas régressé."

### ROOT CAUSE OF "FLAT IN SHADOW" — MATHEMATICAL, found by the supervisor in tfrag3.frag (~line 1002):
The ambient-relief term is a RATIO `rt_amb_eval(Nm) / rt_amb_eval(N)` (ambient evaluated at the perturbed vs
smooth normal). Our ambient (baked-modulation) has almost NO directional variation, so that ratio is ≈1.0 =>
fdt_amb ≈ 1 => **the term does nothing in shade**. You cannot extract relief from a function that does not
vary with the normal. THIS IS WHY IT IS STILL FLAT IN SHADOW.
**FIX (industry standard): a DIRECTION-INDEPENDENT cavity/AO term from the height field.**
 - Compute a micro-AO / cavity factor from the HEIGHT map (and the _ao map when present): crevices darker,
   ridges brighter — e.g. multi-tap height comparison around the texel (or a precomputed cavity from the
   height map), normalised so the mean stays ~1 (no global darkening).
 - Apply it to the AMBIENT/indirect share (the share that dominates in shadow), so relief reads in FULL SHADE
   and at night. This is what makes shaded PBR surfaces still look carved in modern games.
 - Keep it energy-safe (multiply ≤1 on ambient, mean-preserving) so the accepted baked look is not darkened.

### "GLORIFIED BUMP / NO REAL DEPTH / TESSELLATION LACKS DETAIL" — three concrete levers, do ALL:
1. **Tessellation detail**: the current tesc gates the whole patch beyond 30 m and the edge levels appear low.
   RAISE the near-field tessellation (higher max level, distance-scaled), so displaced geometry actually has
   the density to show relief. Report the ACHIEVED tess factors and triangle counts near the camera.
2. **Displacement amplitude**: height_scale = 0.05 * relief (so ~7 cm at relief 1.5). On tessellated geometry
   that is small; scale the displacement with the ACTUAL material (height map range) and expose it so the
   relief is physically visible at the silhouette. Verify the silhouette breaks (the classic proof that real
   displacement is happening, vs a bump).
3. **Parallax depth cue**: the parallax path must use steep POM WITH self-occlusion and a silhouette/edge
   clip, not a single-offset lookup — motion parallax is what sells depth when tessellation is off.
4. **"Très contrasté à la lumière mais plat"**: the direct-sun normal-map term is over-driven while the depth
   cues (AO/cavity, self-shadow, parallax) are under-driven. Rebalance: less raw N·L contrast, more cavity +
   self-shadow + parallax => reads as DEPTH instead of high-contrast noise.
ACCEPTANCE (owner's eye): relief clearly visible IN SHADOW, real depth (not a shaded bump) with tessellation
AND with parallax, no over-contrast in sunlight, mesh consolidation intact.

---
## OWNER PLAYTEST #18 (2026-07-25) — "bien mieux, bien plus cohérent et consistant" ✅. Remaining: GROUND relief.
Owner: "la tessellation manque toujours de relief EN PARTICULIER AU SOL, et je crois avoir identifié pourquoi
avec le parallax: on dirait que le displacement du parallax est HORIZONTAL au sol, comme si au lieu de
s'élever, ça s'étale à plat." (Rendering quality/look comes later — he wants the RELIEF right first.)

### SUPERVISOR ROOT-CAUSE (read from tfrag3.frag / tfrag3_tess.tese — the owner's observation is exactly right)
**(A) PARALLAX SMEARS ON THE GROUND — inherent to the formula at grazing view.** The offset is
`P = (Vt.xy / vz) * height_scale * uv_tile`, with `vz = max(Vt.z, 0.20)`. On a near-horizontal FLOOR seen at
a GRAZING angle (the normal gameplay camera looks along the ground), Vt.z → small, so the amplifier blows up
and P becomes a large HORIZONTAL UV TRANSLATION: the texture SLIDES sideways instead of reading as depth —
literally "ça s'étale à plat". The 0.08 UV clamp caps the magnitude but not the nature of the artifact.
FIX (industry): 
  1. FADE the parallax amplitude toward 0 as the view becomes grazing (weight by Vt.z / N·V, e.g. smoothstep
     from ~0.15 to ~0.5) — parallax is only trustworthy near head-on; at grazing it must not smear.
  2. Cap the offset in *world* terms (a few cm of apparent depth), not only in UV, so it never exceeds the
     real feature depth.
  3. On surfaces where parallax is faded out (grazing floors), the relief must come from TESSELLATION
     displacement instead => (B).

**(B) GROUND TESSELLATION IS FAR TOO COARSE.** tfrag GROUND triangles are HUGE (many metres per edge). With
a tess level capped at 32, a 20 m edge yields ~60 cm segments — while the height features are cm-scale. So on
the GROUND the displaced geometry is still ~10-40x under Nyquist (the earlier v/feature measurement was
likely taken on a wall-sized material, not the ground).
FIX: drive the tess factor from the **WORLD-SPACE EDGE LENGTH**, targeting a fixed segment size near the
camera (e.g. ~5-10 cm/segment within ~8 m, degrading with distance), clamped by GL_MAX_TESS_GEN_LEVEL and a
perf budget. Large ground triangles must therefore receive MUCH higher factors than small wall triangles —
a distance-only heuristic cannot do that. Report the achieved segment size (cm/segment) and vertices per
height feature **ON THE GROUND** specifically, at the owner's grass/sand vantages, plus the fps cost.
Consider a near-camera detail radius so the cost stays bounded (industry: distance-based LOD on top of a
world-space edge-length target).
ACCEPTANCE: on the GROUND, the relief reads as actual raised/carved detail (no horizontal smearing at grazing
angles), with measured cm/segment and v/feature on ground materials; tessellation and parallax each behave
correctly in their regime. Owner's eye at his grass/sand vantages. Rendering/look polish comes AFTER.

---
## SUPERVISOR DEVICE MEASUREMENT (2026-07-25) — TESSELLATION IS ~INVISIBLE ON THE GROUND. Hardware ceiling. Fix = OFFLINE PRE-SUBDIVISION.
Measured by the supervisor on the Redmi at the owner's vantage (village1, noon, relief 2.0), ground band:
    tessellation vs displacement-OFF : mean delta 0.77/255, only 4.6% of pixels change
    parallax     vs displacement-OFF : mean delta 2.27/255, 14.5% of pixels change
=> On the GROUND the tessellation displacement does 3x LESS than parallax — it is effectively invisible,
matching the worker's own report (ground v/feature 0.65 < 1, "the ceiling still clips the longest-edge
ground patches"). ROOT: GL_MAX_TESS_GEN_LEVEL (typically 64) CANNOT subdivide a 10-30 m ground triangle down
to cm-scale segments — a 20 m edge at level 64 is still ~31 cm/segment while the height features are ~cm.
No shader-side tuning can beat that ceiling.

### MANDATE — PRE-SUBDIVIDE THE LARGE GROUND TRIANGLES OFFLINE (industry standard: mesh prep + tessellation)
1. In the existing MESH CONSOLIDATION BAKE (the `<level>.meshweld` sidecar pipeline, already validated by the
   owner), add a SUBDIVISION pass: any renderable triangle whose longest edge exceeds a threshold (start
   ~2 m, tune) is recursively split (1-to-4 midpoint subdivision) until under the threshold. Interpolate ALL
   vertex attributes (position, normal — from the consolidated smooth normals —, UV, baked colour, tangent)
   so the result is visually IDENTICAL before displacement and keeps the welded topology (new midpoint verts
   are SHARED between the two triangles that own the edge => no new seams/cracks, the owner's validated
   mesh result must not regress).
2. Bound the cost: only subdivide surfaces that can receive displacement (ground/walls with a height map or
   PBR-capable materials), report the added vertex/triangle counts per level and the memory delta; keep it in
   the precomputed sidecar so there is ZERO per-load cost.
3. THEN the hardware tessellation finishes the job on already-small triangles => real cm-scale displacement
   on the ground. Re-measure: ground cm/segment, ground v/feature (target >= 2 = Nyquist), and the
   tessellation-vs-OFF pixel delta on the ground band (target: clearly above the current 0.77/4.6%).
4. Watch fps on the Adreno 618 (already ~7 fps in that scene, pre-existing) and keep a distance/LOD budget;
   the Honor (Adreno 840) is the quality target, the Redmi the floor.
ACCEPTANCE: measurable, visible ground displacement (delta well above parallax's 2.27, v/feature >= 2), no
new seams/cracks (mesh consolidation intact), fps budget documented.

---
## ★★★ SUPERVISOR DEVICE FINDING (2026-07-25, via the owner's checkerboard idea) — **NO PBR MAPS ARE BOUND AT ALL: 668/668 textures log `maps=NONE (same-source pairing)`**
The owner asked why the sage-hut brick / straw roof / sand / plaster are NOT replaced although they are in
the recharged set. I pushed a synthetic CHECKERBOARD set (base+height+normal+roughness) onto a ground texture
and captured on device: the checkerboard DISPLAYS (so the user-custom base replacement works) but is
COMPLETELY FLAT — and the binding log explains why:
    pbr binding: bch-beach-01          base=stock maps=NONE (same-source pairing ...)
    pbr binding: bch-sages-stonewall-01 base=stock maps=NONE (same-source pairing ...)
    pbr binding: bch-leafyground        base=stock maps=NONE (same-source pairing ...)
    => 668 binding lines, 668 with maps=NONE, ZERO with maps bound.
TWO ROOT CAUSES:
1. **NAME MISMATCH**: the in-game texture names are `bch-*` (bch-beach-01, bch-sages-stonewall-01,
   bch-leafyground, bch-hut-roof-tile-01, bch-beachrock...) while the recharged set ships `vil-*` /
   `vil1-*` names (vil-beach-01, vil1-sages-stonewall-01, vil1-jng-leafyground...). The lookup therefore
   never finds a bundled base => base=stock.
2. **THE SAME-SOURCE PAIRING RULE (mandated in REOPEN #2) THEN REJECTS THE MAPS**: because base=stock, the
   maps are refused even when height/normal/roughness ARE present. That rule was meant to prevent mixing a
   USER base with BUNDLED maps of a different image — it must NOT block the normal case.
### MANDATE
a. **Fix the name matching**: resolve textures by their REAL in-game names (bch-*) — either rename/duplicate
   the recharged assets to the actual names, or add an alias/normalisation (strip level prefix, match on the
   stem) so `vil-beach-01`/`bch-beach-01` resolve to the same material. Audit ALL 7 recharged textures against
   the real names and report the mapping.
b. **Relax the same-source rule to its real intent**: maps may pair with a STOCK base (that is the normal
   case for a bundled/PBR-only set!). Only refuse pairing when a USER base and BUNDLED maps come from
   genuinely different images. Log the decision per texture.
c. **Re-verify with the checkerboard**: with maps bound, the checkerboard height must produce VISIBLE raised
   blocks under tessellation (and parallax) — that is the objective proof the displacement follows the height
   map. Report the binding counts (maps bound > 0!) and the checkerboard delta.
d. This invalidates most previous PBR "look" iterations: the owner has been judging a PBR path running with
   NO material maps. Re-run the visual checks after the fix.

---
## ⚠️ SUPERVISOR RETRACTION (2026-07-25) — THE PREVIOUS "no PBR maps are bound / name mismatch" FINDING IS **WRONG**. IGNORE IT ENTIRELY.
The owner corrected me and he is right. I had sampled the binding log lines for `bch-*` textures = the BEACH
level (streamed alongside village1), which legitimately has no recharged textures. On VILLAGE1 the 7
recharged textures ARE fully bound, verified on device:
    vil1-sages-stonewall-01  base=user    N=user    R=user    M=user AO=user H=user
    vil1-jng-leafyground     base=bundled N=bundled R=bundled H=bundled
    vil-beach-01 / vil-wallplaster / vil1-sages-strawroof-01 / vil-hut-roof-tile-01 / vil-beachrock
                             base=bundled N=bundled R=bundled H=bundled
=> **DO NOT** change the texture-name matching. **DO NOT** relax the same-source pairing rule. Both work.
The map binding is CORRECT; the previous mandate section (name mismatch / 668 maps=NONE) is retracted.

### WHAT REMAINS TRUE AND ACTIONABLE (the owner's actual report + the checkerboard method)
The owner's judgement stands: on the 7 PBR surfaces the result is still "plat et contrasté", the geometry
"fait des vagues mais ne suit pas" the height map, and the displacement does not follow the supplied _height.
KEEP the CHECKERBOARD DEBUG METHOD (the owner's idea, it is the right tool):
 1. Ship a synthetic debug material set (checkerboard base + matching checkerboard HEIGHT + a normal map
    derived from it + checkerboard roughness) that can be enabled on the PBR surfaces via a debug prop or a
    menu row (e.g. debug.opengoal.pbr.testpattern=1) — no need to hand-push files.
 2. With it, verify OBJECTIVELY on device: (a) does the tessellated geometry form VISIBLE RAISED BLOCKS that
    follow the checker height (silhouette + shading), (b) is the normal map interpreted with the right
    orientation/handedness (lighting flips correctly across a known slope), (c) does the parallax offset
    track the checker edges rather than sliding.
 3. Report the checker verdict per mode (tessellation / parallax / off) with a capture and a number.
This is the fastest path to a definitive answer on "does the displacement actually follow the height map".

---
## ★ SUPERVISOR CHECKERBOARD TEST ON ALL 7 PBR TEXTURES (2026-07-25, the owner's method) — THE DISPLACEMENT WORKS, THE **SCALE** IS WRONG.
I generated a synthetic debug material (checkerboard base + matching checkerboard HEIGHT + normal derived
from it + inverted-checker roughness + UV orientation markers) and pushed it onto ALL SEVEN recharged
textures (binding confirmed: base=user N=user R=user H=user). Captures archived in device/dbg7/.
MEASURED (village1, noon, relief 2.5, Adreno 618):
    GROUND  tessellation vs displacement-OFF : delta 16.55/255, 35.0% of pixels  (parallax: 4.38, 15.0%)
    WALL    tessellation vs displacement-OFF : delta 10.99/255, 33.4%
=> The tessellated geometry DOES follow the height map (the checker squares visibly emboss). Mechanically the
displacement pipeline is FUNCTIONAL.
**THE REAL DEFECT, made obvious by the checker: THE UV TILING / HEIGHT SCALE RATIO IS WAY OFF.** My 8x8
checker renders as DOZENS of tiny squares across the hut wall => the material is tiled so densely that each
height feature is a few MILLIMETRES on screen. At that scale the displacement can only read as CONTRAST, never
as depth — exactly the owner's "plat et contrasté / bump map glorifié". The geometry follows the height, but
the height features are far too small relative to the surface.
### MANDATE
1. **Audit the UV tiling per material** (u_pbr_uv_tile and the level's own UV scale): report, for each of the
   7 textures, the WORLD SIZE of one texture tile (cm) and therefore the world size of one height feature.
   A stone wall tile should be ~0.5-2 m, not ~5 cm.
2. **Scale the displacement amplitude to the FEATURE size, not a constant**: height_scale must be derived
   from the tile's world size (e.g. depth ≈ 3-8% of the tile's world extent) so the relief is proportionate
   and readable. A fixed 0.05*relief cannot be right across materials with wildly different tiling.
3. **Expose the debug material IN-BUILD** (the owner's request): debug.opengoal.pbr.testpattern=1 (or a menu
   row) that substitutes a generated checkerboard base+height+normal+roughness on every PBR material, so this
   verification is one prop away instead of hand-pushed files. Include the UV orientation markers.
4. Re-run the checker test after the tiling/scale fix: the checker squares must read as LARGE, clearly raised
   blocks with real shadowing — and then the real materials should finally show depth instead of contrast.

---
## ★★ OWNER CHECKER VERDICT (2026-07-26) — TWO HARD BUGS, both proven by the in-build checkerboard.
Owner ran the CHECKER-DEBUG build (pattern on by default) and reports:
 (A) "le displacement ne correspond pas du tout à la texture, comme si c'était pas aligné" — the height/
     normal/roughness must WRAP EXACTLY like the base colour.
 (B) "des chunks entiers (LA PLUPART) sont juste PLATS alors que le damier est bien présent" — the base
     colour (checker) shows everywhere but the DISPLACEMENT only happens on some chunks.
### BUG A — UV MISMATCH BETWEEN BASE AND MAPS (confirmed in the shader by the supervisor)
    base colour : texture(tex_T0, tex_coord.xy)              <- RAW uv
    PBR maps    : vec2 uv = tex_coord.xy * u_pbr_uv_tile;    <- SCALED uv   (tfrag3.frag ~837, ~1605)
As soon as u_pbr_uv_tile != 1 the maps sample at a DIFFERENT scale than the albedo => the relief does not
line up with the pattern. This came from the previous round applying the "world tiling" idea to the UV
INSTEAD of to the displacement AMPLITUDE (my mandate was ambiguous — this is the correction).
FIX: **the PBR maps MUST use the SAME UV as the base colour** (same coordinates, same wrap, same
tiling) — no extra multiplier. The world-scale reasoning belongs ONLY to the displacement AMPLITUDE
(height_scale in metres), never to the UV lookup. Remove/neutralise u_pbr_uv_tile from all map sampling
(height, normal, roughness, AO, specular, emissive, POM march, tess-eval height) and keep the amplitude
derivation. Verify with the checker: the raised blocks must coincide EXACTLY with the checker squares.
### BUG B — MOST CHUNKS GET NO DISPLACEMENT AT ALL
The checker albedo is applied everywhere the material is bound, but displacement only appears on some
chunks. Find and report WHY, per gate, for the owner's vantage: tess-eligible draw kinds only? the 30 m
whole-patch distance gate? the world-space edge-length law's clamp? a triangle/vertex budget? the tess
capability check? the pre-subdivision only touching some kinds?
FIX: displacement must cover EVERY surface that has a height map bound and is visible near the player —
if hardware tessellation cannot run on a given draw kind/bucket, that draw must fall back to the POM path
so it is never left flat. Report the coverage: % of PBR-bound draws that actually receive displacement
(target ~100% in the near field) and prove it with the checker (no flat checker chunks next to raised ones).
ACCEPTANCE: with the checker pattern, EVERY nearby PBR surface shows raised blocks that line up exactly
with the checker squares. No misalignment, no flat chunks.

**OWNER CORRECTION (2026-07-26) — NO POM FALLBACK EXCUSE. TESSELLATION MUST RUN EVERYWHERE.**
"Bah elle devrait pouvoir tourner partout ! Si les polygones sont trop gros... bah faut subdiviser, c'est un
peu le but de la tessellation (vertex displacement shaders qui rajoutent des polygones). Et au pire tu peux
faire des mesh avec plus de subdivision et des LOD (près = plus de subdivision, puis défaut, puis LOD
natifs). Et s'assurer que les maps (height, normal, roughness) utilisent exactement le même alignement que
la base color."
=> REVISED REQUIREMENT (supersedes the "fall back to POM where tessellation cannot run" line above):
1. **Tessellation displacement must apply to EVERY draw that has a height map bound** — all tfrag/tie/shrub
   draw kinds and buckets, not a "tess-eligible kinds" subset. If a draw kind is currently excluded, find
   WHY (pipeline/program/vertex-format/bucket routing) and FIX the pipeline so it can be tessellated. Do not
   accept a subset; report the exhaustive list of draw kinds and their tessellation status (target: all).
2. **Big triangles are NOT an excuse** — that is what tessellation is for; combine (a) the hardware tess
   factor from the world-space edge-length law, and (b) the offline PRE-SUBDIVISION already in the mesh bake,
   so every surface reaches the target segment size. If the hardware ceiling is still hit, push more of the
   work into the pre-subdivision (that is the owner's "mesh avec plus de subdivision").
3. **Owner-proposed LOD scheme**: build subdivided mesh LODs — NEAR = heavily subdivided (displacement-ready),
   MID = default, FAR = the game's native LOD — and select by distance. This bounds the cost while keeping
   full displacement coverage in the near field where it is visible.
4. **Maps alignment (restated as a hard requirement)**: height, normal and roughness (and AO/specular/
   emissive) must use EXACTLY the same UV/wrap/tiling as the BASE COLOUR. No separate multiplier anywhere.
ACCEPTANCE: with the checker pattern, EVERY nearby PBR surface — whatever its draw kind — shows raised blocks
aligned exactly with the checker squares. Report per-draw-kind tessellation coverage (must be complete) and
the LOD/subdivision scheme used.

## ⭐ OWNER STANDING RULE (2026-07-26) — THE CHECKERBOARD IS THE ACCEPTANCE TEST UNTIL IT IS PERFECT
"On reste avec le damier tant que c'est pas complètement fixé et que le damier est pas parfait en PBR
(autant en parallax qu'en tessellation)."
=> For every round from now until the owner says otherwise:
1. The phase is NOT done while the checkerboard is imperfect. "Perfect" means, at the owner's vantages, in
   BOTH modes (PARALLAX and TESSELLATION), at day, PBR on:
   - the raised blocks coincide EXACTLY with the checker squares (no offset, no different scale, no drift
     when the camera moves),
   - EVERY nearby PBR surface is displaced (no flat chunks next to raised ones, whatever the draw kind),
   - the relief reads as real depth (block edges catch the light, a block shadows its neighbour), not as a
     brightness pattern,
   - the normal map orientation is correct (use the R/G UV markers: red band = +V/top, green = +U/left),
   - roughness varies visibly between the checker cells.
2. **Every build handed to the owner must ALSO be produced in a CHECKER-DEBUG variant** with
   `pbr_testpattern::mode()` defaulting to 1 (pattern ON without adb), uploaded next to the normal build:
   `app-jak1-CHECKER-DEBUG.apk` + `app-jak1-recharged.apk`. The owner has no adb — the debug build must work
   out of the box.
3. Report the checker verdict per mode (parallax / tessellation) with the alignment and coverage numbers.

**OWNER (2026-07-26): "parallax rend complètement plat actuellement".** SUPERVISOR CONFIRMS THE CAUSE — my
own guard-rails stacked up and neutralised it (tfrag3.frag ~863-887):
    POM_MAX_WORLD_M = 0.03                       (my "cap the offset in world cm" mandate)
    pom_graze = smoothstep(LO, HI, Vt.z)         (my "fade parallax at grazing" mandate)
    P = (Vt.xy / vz) * height_scale * uv_tile * pom_graze
On a game-camera view of the ground (mostly grazing), pom_graze -> ~0 AND the offset is capped at 3 cm =>
NO visible parallax at all. I over-corrected the earlier "horizontal smear" report into a dead effect.
FIX (balance, not extremes):
 - Raise the world cap so the depth is actually perceivable (derive it from the material's real height
   range / tile world size — a stone wall can carry several cm, ground detail more; 3 cm flat is too small
   and arbitrary).
 - Make the grazing attenuation a GENTLE floor, not a kill: keep a minimum weight (e.g. never below ~0.35)
   so parallax still reads at typical gameplay angles; only damp the extreme grazing case that produced the
   sideways smear. Better: use proper steep-POM with self-occlusion (which does not smear at grazing) rather
   than fading the effect away.
 - The acceptance is the CHECKER: in PARALLAX mode the checker squares must show clear depth (edges,
   self-occlusion) at normal gameplay camera angles — not a flat pattern, and not a sliding texture.

**OWNER PRECISION (2026-07-26): "le parallax est plat AUTANT SUR LES MURS QUE LE SOL".** That rules out the
grazing-angle explanation alone: on a WALL viewed head-on, Vt.z is LARGE so pom_graze ~= 1 — yet it is still
flat. Therefore the parallax offset is being killed by something that applies EVERYWHERE:
 - the absolute world cap POM_MAX_WORLD_M = 0.03 combined with the UV conversion
   (POM_MAX_WORLD_M * u_pbr_uv_per_m) can clamp the offset to a near-zero UV distance for ALL materials;
 - and/or u_pbr_height_scale itself is now tiny after the "feature-scaled amplitude" round;
 - and/or the POM branch is skipped entirely for these draws (check the branch conditions: u_pbr_mode & 16,
   u_pbr_displacement != 2, bisect bit 128, height map bound) — if the branch never runs, the result is flat
   no matter the parameters.
DIAGNOSE FIRST, in this order, and report the numbers: (a) is the POM branch executed on wall AND ground
draws (add a debug viz/counter), (b) what is the FINAL offset length in UV and in world cm after all caps
(log it for a wall and a ground draw), (c) which term collapses it. THEN fix that term. The checker in
PARALLAX mode must show unmistakable depth on a WALL viewed head-on — that is the simplest, least ambiguous
acceptance case.

================================================================================
ROUND 22 — OWNER PLAYTEST VERDICT (damier, curseurs à 3.0) : REOPEN
================================================================================
Owner, mot pour mot :
  "Alors les rares endroits où la tesselation fonctionne (vrai displacement) ça fonctionne
   mais j'ai poussé les curseurs au maximum (3.0) et c'est pas si obvious que ça (par contre
   ça correspond vraiment), mais la plupart des endroits n'ont toujours pas de displacement
   du tout ! Donc deux choses à corriger... Le fait que ça ne s'applique pas partout et qu'à
   la plupart des endroits ça n'est pas du tout effectif (ça c'est toujours le cas) et le fait
   qu'aux endroits où ça fonctionne, avec le curseur au maximum que ce soit plus extrême !
   Et en parallax c'est exactement les mêmes problèmes."

CE QUI EST ACQUIS — NE LE CASSE PAS. L'ALIGNEMENT EST VALIDÉ : "par contre ça correspond
vraiment". Le round 21 a réglé le bug maps-vs-base-UV. Toute régression de l'alignement du
damier annule le round. C'est un acquis à protéger, pas à re-toucher.

Il reste EXACTEMENT DEUX défauts, et ils valent pour LES DEUX tiers (tessellation ET parallax) :

--------------------------------------------------------------------------------
DÉFAUT A — COUVERTURE : "la plupart des endroits n'ont pas de displacement du tout"
--------------------------------------------------------------------------------
C'est le défaut n°1 en priorité. L'owner voit le damier PARTOUT (donc la base colour est bien
remplacée partout) mais du relief seulement à de RARES endroits. Damier visible + zéro relief
= la surface reçoit la base colour mais PAS le displacement.

FAIT STRUCTUREL MESURÉ PAR LE SUPERVISEUR (grep sur les shaders, à vérifier et à traiter) :
  tfrag3.frag     tex_pbr_height/u_pbr_height : 15 occurrences   tfrag3_tess.tese : OUI
  etie_base.frag  0 occurrence   pas de .tese
  tie_wind.frag   0 occurrence   pas de .tese
  shrub.frag      0 occurrence   pas de .tese
  merc2 / generic / emerc : 0 occurrence, pas de .tese
Et ton propre rapport (l. 964) dit : "PBR maps have only ever bound on the TFRAG3 program".
Donc TOUT ce qui n'est pas dessiné par TFRAG3 est STRUCTURELLEMENT incapable d'afficher du
relief, quelle que soit la valeur des curseurs. Dans un niveau Jak, ça représente une énorme
part de l'écran (objets instanciés TIE à envmap, objets animés par le vent, végétation/shrub).
C'est très probablement l'explication principale de "la plupart des endroits".
Cette note de couverture disait "coverage is unchanged" — c'était acceptable quand la phase
ne traitait que l'éclairage. Ça ne l'est plus : l'owner juge le displacement sur TOUT l'écran.

Ce qu'il faut faire :
1. ÉTABLIR LA VÉRITÉ D'ABORD, avant tout code. Pour un vantage de jeu réel (village1-hut,
   caméra de jeu normale), produis une VENTILATION PAR PROGRAMME de l'écran :
   % de pixels dessinés par tfrag3 / etie_base / tie_wind / shrub / merc / autres,
   et parmi ceux-là le % qui reçoit un displacement non nul. Le chiffre qui compte pour
   l'owner est un POURCENTAGE DE PIXELS À L'ÉCRAN, pas "14 matériaux sur 24". Une métrique
   par matériau ne peut pas répondre à "la plupart des endroits" ; il faut du par-pixel.
   Rends ce tableau lisible dans le rapport. C'est lui qui pilotera le reste du round.
2. PORTER LE CHEMIN MATÉRIAU PBR + DISPLACEMENT sur les programmes du MONDE qui pèsent dans
   ce tableau : etie_base, tie_wind, shrub (et tfrag3 partout où il ne l'a pas déjà).
   Souviens-toi du pattern établi pour les familles de renderers (mémoire Gwater) : ça se
   fait en 3 parties — binder/uniforms côté C++, TU dans le CMakeLists Android, et le
   shader lui-même. Les DEUX tiers doivent suivre : tessellation là où la géométrie le
   permet, POM partout ailleurs, avec la MÊME loi d'amplitude (l'acquis du round 21 : les
   deux tiers montrent la même profondeur par construction).
3. Les acteurs (merc2/generic/emerc) : si tu les exclus, tu l'écris NOIR SUR BLANC dans le
   rapport avec la raison technique et le % de pixels concerné. Règle owner permanente :
   "il faut que tu trouves vraiment un moyen de tout couvrir sans oublis" — une exclusion
   silencieuse est un échec, une exclusion argumentée et chiffrée est recevable.
4. Là où la tessellation ne peut pas tourner (matériel/tier/géométrie), le POM doit prendre
   le relais et le [cover] doit le compter comme couvert — mais alors le POM doit VRAIMENT
   produire de la profondeur (cf. défaut B), pas un bump map glorifié.
5. Rappel owner déjà donné et toujours valable : "au pire tu peux faire des mesh avec plus de
   subdivision et des LOD (près = plus de subdivision, puis défaut, puis LOD natifs)". La
   pré-subdivision offline est un outil légitime pour rendre une surface displaçable.

--------------------------------------------------------------------------------
DÉFAUT B — AMPLITUDE AU MAX : "curseur au maximum, c'est pas si obvious que ça"
--------------------------------------------------------------------------------
Là où ça marche, ça correspond à la texture (acquis) mais l'effet reste discret À 3.0, c'est-à-
dire AU MAXIMUM DU CURSEUR. Le haut de la course doit être SPECTACULAIRE, pas timide.

Ce qu'il faut faire :
1. Re-mapper la course du curseur, pas juste multiplier un scalaire :
   - 1.0 = le rendu physiquement correct actuel (dérivé de la longueur d'onde mesurée). On garde.
   - 3.0 = EXTRÊME et assumé : la silhouette doit se rompre visiblement sur une arête de
     tessellation, et en POM la parallaxe doit décoller franchement quand on bouge la caméra.
   Autrement dit la courbe doit être fortement non linéaire vers le haut, et les caps
   "relatifs au matériau" introduits au round 21 doivent s'ouvrir en conséquence — sinon ils
   re-plafonnent le maximum exactement comme POM_MAX_WORLD_M l'a fait au round 20. C'est le
   piège à ne pas re-tomber dedans : vérifie EXPLICITEMENT quel terme borne l'amplitude à 3.0
   et prouve par la mesure qu'aucun cap ne mord avant le maximum.
2. Prouve-le par des NOMBRES, à 1.0 et à 3.0, sur la même vantage et la même frame :
   - déplacement vertex max en cm (tier tessellation) ;
   - offset UV final ET son équivalent en cm monde (tier POM) ;
   - un delta pixel mesuré entre curseur 1.0 et 3.0 ; s'il est faible, c'est que ça ne marche pas.
   Un cap qui mord doit être nommé et chiffré, pas supposé absent.
3. Nyquist reste la règle pour la tessellation : à 3.0 il faut assez de vertices par feature,
   sinon l'amplitude monte mais le relief reste mou. Si le budget de subdivision est le facteur
   limitant, dis-le avec le chiffre v/feature.

--------------------------------------------------------------------------------
PROTOCOLE DE SORTIE
--------------------------------------------------------------------------------
- Le damier RESTE le matériau de test tant que ce n'est pas parfait (règle owner permanente),
  en parallax ET en tessellation. La variante CHECKER-DEBUG doit continuer à s'activer TOUTE
  SEULE sans adb (l'owner n'a pas adb) — c'est le flag de compilation OG_PBR_CHECKER_DEBUG ;
  vérifie que le libgk de la variante DIFFÈRE de celui du build normal avant de livrer, et
  lance-la réellement pour constater le damier à l'écran sans aucun setprop.
- Captures device obligatoires, même vantage, même heure TOD : (a) curseur 1.0 vs 3.0,
  (b) tessellation vs parallax, (c) un plan large qui montre la couverture écran.
- Le tableau de couverture par-pixel est le livrable central de ce round.
- Rappel harnais : ANDROID_SERIAL=eae4df44, timeout sur tout logcat, force-stop en fin de run.

--------------------------------------------------------------------------------
DÉFAUT C — POLARITÉ DU DISPLACEMENT QUI S'INVERSE D'UN ENDROIT À L'AUTRE
--------------------------------------------------------------------------------
Owner, mot pour mot :
  "j'ai aussi remarqué qu'à certains endroits où le displacement fonctionne c'est les carreaux
   noirs qui ressortent, à d'autres c'est les carreaux blancs... Je crois que ça devrait être
   les carreaux blancs qui ressortent (à moins que tu aies inversé les couleurs pour le
   displacement), mais de sûr ça ne devrait pas s'inverser d'un endroit à l'autre !"

L'owner a raison sur la convention : la carte de hauteur est centrée sur 0.5 (tfrag3_tess.tese :
"0.5 = neutral mid"), donc blanc (1.0) sort, noir (0.0) rentre. LES CARREAUX BLANCS DOIVENT
RESSORTIR, PARTOUT, SANS EXCEPTION.

RAISONNEMENT À NE PAS RATER — c'est la déduction qui rend ce défaut précieux : avec le damier,
TOUS les matériaux partagent LA MÊME height map synthétique (g_shared.height_tex, une seule
texture uploadée une fois). Si la polarité s'inverse d'un endroit à l'autre alors que la carte
est rigoureusement identique, la cause NE PEUT PAS être dans la texture. Elle est forcément en
aval, du côté géométrie/frame :
  - normale de vertex inversée (pointant vers l'intérieur) : la .tese déplace "along the
    interpolated normalized normal", donc une normale retournée déplace vers l'intérieur et
    inverse exactement ce que voit l'owner ;
  - handedness du repère tangent (signe de la bitangente) qui bascule : en POM, le vecteur vue
    en espace tangent change de signe et la parallaxe se creuse au lieu de sortir ;
  - winding / UV miroir sur certaines faces.
Et ça recoupe une remarque que l'owner avait déjà faite en validant la consolidation des mesh :
"je pense qu'il y a encore quelques soucis de normales et autres petites coutures". Le damier
vient de te donner un DÉTECTEUR OBJECTIF de ces normales restantes. Sers-t'en.

Ce qu'il faut faire :
1. Identifier laquelle des trois causes ci-dessus opère, par la mesure, pas par supposition.
   Le test discriminant est simple : sur une surface qui s'inverse, dumpe le signe de
   dot(normale_vertex, normale_géométrique_de_la_face) et le signe du handedness tangent.
   Si c'est la normale : c'est un résidu d'orientation dans les données de mesh.
   Si c'est le handedness : c'est le repère tangent (MikkTSpace / w de la tangente).
2. CORRIGER À LA SOURCE. Interdiction formelle du contournement cosmétique : pas de abs(),
   pas de "je force le signe dans le shader", pas de flag d'inversion par matériau. Ça
   masquerait un défaut de données qui continuerait de pourrir l'éclairage, l'AO, le spéculaire
   et les ombres. Si ce sont des normales retournées, elles se corrigent dans les données de
   mesh, avec la même autorité que la phase de consolidation (côté marchable = vers l'extérieur).
3. FAIRE LE RECENSEMENT COMPLET, tous niveaux, comme la phase de consolidation l'a fait :
   combien de faces/vertices ont une polarité fautive, avant et après, sur les 448 niveaux.
   L'owner a une règle permanente sur ce point : couvrir sans oubli, chiffres à l'appui.
   Si la phase de consolidation a laissé passer ces cas, dis POURQUOI son flood-fill ne les a
   pas attrapés — c'est ça, l'information utile pour ne pas les recréer.
4. Preuve visuelle : une capture device au damier montrant plusieurs surfaces d'orientations
   différentes (mur, sol, plafond/dessous, objet incliné) où les carreaux BLANCS ressortent
   partout, en tessellation ET en parallax.

--------------------------------------------------------------------------------
RÈGLE OWNER PERMANENTE — LE TAUX DE COUVERTURE DES ASSETS N'EXCUSE RIEN
--------------------------------------------------------------------------------
Owner, mot pour mot :
  "Je sais très bien que pour l'instant il n'y a que 7 textures avec des height maps, mais on va
   remplacer genre 80% des textures à terme... En tout cas faut que ce soit nickel automatiquement,
   donc FAUT QUE CE SOIT NICKEL AVEC LES 7 !"

Interdit désormais, dans tout rapport et toute analyse : présenter le faible nombre de matériaux
recharged (7 sur village1) comme une explication, une atténuation ou une raison d'accepter un
défaut. L'owner le sait déjà et va monter à ~80% des textures. Deux conséquences opérationnelles :
1. LA BARRE SE JUGE SUR LES MATÉRIAUX QUI EXISTENT. Sur ces 7 matériaux, le rendu doit être
   IRRÉPROCHABLE : alignement, amplitude au curseur max, polarité, cohérence tessellation/parallax,
   comportement à l'ombre. Un défaut visible sur l'un des 7 est un échec de phase, quel que soit
   le pourcentage de pixels monde couvert par le pipeline en test damier.
2. LE CHEMIN DOIT ÊTRE AUTOMATIQUE ET SANS SEUIL. Quand l'owner déposera 50, 100, 200 nouveaux
   jeux de maps, ils doivent être pris en charge SANS intervention : pas de liste blanche de
   matériaux, pas de constante par matériau écrite à la main, pas de tuning codé en dur qui ne
   vaudrait que pour les 7 actuels. Toute constante dérivée d'un matériau doit être MESURÉE au
   chargement depuis la map elle-même (comme pom_depth_uv() le fait déjà avec la longueur d'onde),
   jamais tabulée. Un futur round qui ajouterait un cas particulier par matériau viole cette règle.
3. Le chiffre de couverture damier (99%) mesure le PIPELINE ; le chiffre de couverture assets (35%)
   mesure le CONTENU. Les deux peuvent être rapportés, mais le second ne doit jamais servir à
   relativiser un défaut constaté par l'owner.

--------------------------------------------------------------------------------
RÈGLE OWNER — LE BUILD DE TEST EST LE BUILD DAMIER (pas de variante à côté)
--------------------------------------------------------------------------------
Owner, mot pour mot :
  "Je veux le damier dans les build de test, tant que le damier n'est pas parfait, nul besoin de
   vraies textures, c'est beaucoup plus simple de voir ce qui va pas avec le damier"

Tant que le damier n'est pas jugé parfait par l'owner (en parallax ET en tessellation) :
- LE build livré à l'owner EST le build damier. On ne livre plus une paire "normal + CHECKER-DEBUG",
  on livre UN SEUL APK, damier actif d'origine, sans adb, sans setprop, sans menu à trouver.
- Le nom du fichier doit dire ce que c'est, pour qu'il ne puisse pas y avoir de doute au moment de
  l'installer.
- Le damier reste un mode de DEBUG dans le code : la valeur par défaut hors build de test reste
  éteinte, et rien de tout ça ne doit fuiter dans un build de sortie. C'est le packaging qui change,
  pas la sémantique du réglage.
- Quand l'owner déclarera le damier parfait, on repasse aux vraies textures pour la validation finale.

================================================================================
ROUND 24 — REOPEN : LA MÉTRIQUE DE COUVERTURE MESURE LA CAPACITÉ, PAS L'EFFET
================================================================================
Owner, en direct sur le Redmi, sur le build de ce round :
  "je peux dire par ce que je vois sur le Redmi que le displacement n'est toujours pas effectif sur
   toute la géométrie où c'est sensé être le cas (car utilise une texture qui a les maps, même si en
   l'état c'est un damier)"

L'oeil de l'owner prime sur le chiffre. Et le chiffre est réfutable — voici le défaut, nommé :
gpbrf_r22_coverage.py classe chaque pixel PAR PROGRAMME DE RENDU via un tag couleur, puis compte
comme "couvert" tout pixel dessiné par un programme monde déclaré displaçable (cf. son propre
commentaire : "is_world marks the static-world programs that CAN be displaced"). Ça mesure une
CAPACITÉ, pas un EFFET. Un pixel est compté couvert même si sa géométrie n'a bougé d'aucun
micromètre : tessellation restée au niveau 1, tier LOD qui a désactivé le displacement, draw passé
par un chemin/bucket sans programme de tessellation, height map liée mais jamais échantillonnée,
amplitude annulée en aval. D'où 99.22% au rapport et du plat à l'écran : les deux peuvent être
vrais en même temps, et c'est la métrique qui est fausse, pas l'owner.

LA MÉTRIQUE CORRECTE — À REFAIRE ENTIÈREMENT
1. Un pixel n'est DISPLACÉ que si l'image CHANGE quand on éteint le displacement, même vantage,
   même frame, même TOD, même caméra : |ON - OFF| au-dessus d'un plancher de dérive mesuré (le
   plancher se mesure avec une paire OFF/OFF, pas se postule). Tag couleur = classification, jamais
   comptage. Interdit de compter un pixel sur la seule foi du programme qui l'a dessiné.
2. Le dénominateur est la géométrie QUI A LES MAPS. L'owner l'a précisé lui-même : "la géométrie où
   c'est sensé être le cas (car utilise une texture qui a les maps)". Donc : parmi les pixels dont
   le matériau possède une height map, quel pourcentage bouge réellement ? C'est LE chiffre.
   Il se rapporte séparément pour la tessellation et pour le parallax.
3. PLUSIEURS VANTAGES, PAS UN. Une seule vue ne peut pas répondre à "toute la géométrie". Balaye un
   parcours : intérieur/extérieur de la hutte du sage, sol du village, toits, plage, falaise, et des
   distances variées (près / moyen / loin) puisque les tiers LOD sont précisément suspects. Rapporte
   le PIRE vantage, pas la moyenne — c'est le pire que l'owner voit.
4. LOCALISER LES ZONES MORTES. Pour chaque zone qui a les maps et ne bouge pas, dis POURQUOI, avec
   la donnée : niveau de tessellation effectif du draw, tier LOD retenu, programme réellement
   utilisé, amplitude finale calculée. Une zone morte non expliquée reste un échec.
5. Suspects prioritaires à instrumenter d'abord, parce qu'ils expliqueraient exactement ce que
   l'owner décrit — même matériau, résultat différent selon l'endroit :
   - le niveau de tessellation retombe à 1 par distance/taille de triangle/budget ;
   - le mesh dessiné est un LOD alternatif qui n'a pas le programme de tessellation ;
   - le POM censé prendre le relais ne s'active pas là où la tessellation abandonne (les deux tiers
     doivent se recouvrir, jamais laisser un trou entre eux) ;
   - un cap d'amplitude dépendant de la distance ou de la taille de triangle.
6. Le validator sera durci : le gate portera sur le POURCENTAGE DE PIXELS QUI BOUGENT parmi ceux qui
   ont les maps, au PIRE vantage — plus sur un comptage par programme.

RAPPEL DE LA RÈGLE QUI VIENT D'ÊTRE POSÉE : le fait qu'il n'y ait que 7 matériaux recharged
aujourd'hui n'excuse RIEN. Sur ces 7, ce doit être irréprochable, partout où ils apparaissent.

--------------------------------------------------------------------------------
ROUND 24 — LES DEUX VANTAGES NOMMÉS PAR L'OWNER (repro obligatoire)
--------------------------------------------------------------------------------
Owner :
  "je vois plat à plusieurs endroits, l'herbe près de la hutte du sage, le toit de la hutte du sage...
   c'est facile à retrouver en fait"

Ce sont les deux cas de reproduction de référence. Ils DOIVENT figurer dans le balayage de vantages,
et le rapport doit dire pour chacun s'il bouge, de combien, et sinon pourquoi.

1. L'HERBE PRÈS DE LA HUTTE DU SAGE. L'herbe n'est pas dessinée par les programmes monde habituels :
   elle a son propre renderer (GrassRenderer.cpp / les phases Grass* de ce projet, cartes GBK*).
   Si le chemin PBR + displacement n'a pas été porté sur CE renderer-là, l'herbe est plate par
   construction, et aucun comptage par programme monde ne l'aurait signalé — c'est exactement le
   trou que la métrique "capacité" masquait. Vérifie d'abord ça, c'est le suspect le plus direct.
   Attention : les brins d'herbe sont de la géométrie fine ; si le displacement n'a pas de sens
   dessus, dis-le explicitement avec la raison — mais alors le SOL sous l'herbe, lui, doit bouger,
   et il faut le prouver séparément.
2. LE TOIT DE LA HUTTE DU SAGE (chaume/paille). Le toit est très probablement un objet instancié
   TIE, pas du terrain tfrag. Si les draws TIE partent sur etie_base (envmap) ou tie_wind plutôt que
   sur le programme qui a reçu le displacement, le toit est plat quel que soit le curseur. Dumpe le
   programme RÉELLEMENT utilisé pour ce draw, son niveau de tessellation effectif et son tier LOD.
   Le matériau du toit fait partie des 7 recharged : il a les maps, donc il doit bouger.

Ces deux surfaces sont voisines et visibles depuis un même point : le warp village1-hut permet de
les cadrer ensemble. Fournis une capture ON/OFF de chacune. Tant que l'une des deux reste plate,
la phase ne passe pas, quels que soient les pourcentages globaux.

NOTE DE LIVRAISON : le build installé sur le Redmi ce round n'avait PAS le damier actif (prop à 0,
libgk du build normal) — l'owner l'a vu immédiatement. Le superviseur a installé l'APK damier. Règle
déjà posée : le build de test EST le build damier, vérifie-le par un getprop/une capture avant de
prétendre livrer, pas par la présence d'un fichier.

--------------------------------------------------------------------------------
ROUND 24 — CORRECTION DE L'OWNER : LES DEUX HYPOTHÈSES CI-DESSUS SONT FAUSSES
--------------------------------------------------------------------------------
Le bloc précédent ("herbe = GrassRenderer", "toit = draw TIE sur un autre programme") est ANNULÉ.
L'owner, mot pour mot :
  "l'herbe 3D n'a rien à voir avec le PBR et elle est que sur l'île d'entraînement, mélange pas les
   sujets. Elle n'est pas présente sur village1 par exemple, on a que la texture"
  "pour le toit tu racontes aussi de la merde, il y a plein de parties du toit où on voit le
   displacement, d'autres totalement plates alors que c'est sur la continuité et que ça utilise la
   même texture... arrête tes excuses bidons"

Ce que ça établit, et c'est BEAUCOUP plus précis que tout ce qui précède :
- L'herbe de village1 est une TEXTURE sur du sol, pas de la géométrie d'herbe. Le GrassRenderer et
  les cartes GBK ne sont pas le sujet. Ne les instrumente pas, ne les cite pas.
- Sur LE MÊME TOIT, en CONTINUITÉ, avec LA MÊME TEXTURE et donc le même matériau et les mêmes maps :
  certaines parties se displacent, d'autres sont totalement plates.
Donc la cause n'est NI le matériau, NI la texture, NI le programme de rendu, NI l'absence de maps :
tout ça est identique de part et d'autre de la frontière. La différence est forcément PLUS FINE que
le matériau — au niveau du DRAW, du CHUNK, du PATCH ou DU SOMMET.

Et ce n'est pas nouveau : l'owner avait déjà signalé exactement ça il y a plusieurs rounds —
"il y a des endroits où en fait il n'y a aucun displacement, juste la texture ! ... pourquoi des
chunks entiers (la plupart) sont juste plats alors que le damier est bien présent ?". Le mot CHUNK
était déjà là. Ce défaut n'a jamais été corrigé ; les rounds suivants ont traité l'alignement,
l'amplitude et la polarité, mais pas celui-là. C'est LE défaut central de la phase.

MÉTHODE IMPOSÉE — DIAGNOSTIC DIFFÉRENTIEL, PAS DE NOUVELLE THÉORIE
Arrête de proposer des hypothèses par famille de renderer. Prends UNE surface continue où la
frontière est visible (le toit de la hutte du sage convient, l'owner dit que c'est facile à
retrouver), et compare DEUX primitives ADJACENTES de part et d'autre de cette frontière : une qui
se displace, une qui reste plate. Elles partagent la texture et le matériau. Dumpe tout ce qui les
distingue, et la réponse est dans ce diff :
  - identifiant du draw / du chunk / du bucket auquel chacune appartient : est-ce la même ?
  - le patch est-il passé par le programme de tessellation, et quel niveau de tessellation effectif
    a été calculé pour chacun (le niveau, pas le réglage) ;
  - la primitive a-t-elle été pré-subdivisée hors-ligne, oui ou non, et pourquoi pas ;
  - les sommets portent-ils les attributs nécessaires : tangente valide, uv, normale, et la height
    est-elle réellement échantillonnée (valeur lue, pas seulement unité liée) ;
  - amplitude finale calculée pour chacun, en cm, et quel terme la met à zéro le cas échéant.
Le rapport doit nommer LA différence, avec les deux jeux de valeurs côte à côte. Une explication
sans ce diff chiffré n'est pas recevable.

INTERDIT : présenter ce défaut comme une limite acceptable, une question de contenu, ou un cas
particulier de matériau. L'owner l'a dit : "arrête tes excuses bidons". Une surface continue avec
une seule texture doit se displacer uniformément, point.

================================================================================
ROUND 25 — OWNER PLAYTEST (build damier 8d4c3f84) : TESSELLATION PRESQUE, PARALLAX CASSÉ
================================================================================
Owner, mot pour mot :
  "en tesselation c'est quand même beaucoup, beaucoup mieux dans la mesure où c'est beaucoup plus
   consistant et plus de displacement. Mais il y a quand même des endroits où le displacement est
   quasi nul si ce n'est nul (plus rare qu'avant) et étrangement le déplacement n'est pas consistant,
   genre on va dire qu'au maximum observé on a environ +15cm et -15cm entre le plus haut et le plus
   bas, mais on a des endroits où ça fait pas plus de +1cm et -1cm (si ce n'est 0 mais normal map
   donnant une impression de relief). On a aussi des endroits où le noir du damier semble être plus
   élevé que le blanc (ce qui est une erreur) à de très rares occasions. Le parallax lui souffre des
   mêmes problèmes mais avec un truc bien pire, sous le bon angle c'est similaire au rendu en
   tesselation (de moins bonne qualité évidemment) sous d'autres on a l'impression que le 'relief'
   s'étale à plat complètement, les carrés blancs recouvrant complètement les carrés noirs comme si
   ça avait été étalé à plat plutôt qu'élevé verticalement. Pour la tesselation on y est presque"

PROGRÈS RECONNU PAR L'OWNER : la tessellation est "beaucoup, beaucoup mieux", plus consistante.
Ne casse rien de ce qui a produit ça.

--------------------------------------------------------------------------------
C1 — TESSELLATION : L'AMPLITUDE VARIE D'UN FACTEUR ~15 SELON L'ENDROIT
--------------------------------------------------------------------------------
Mesure de l'owner, à retenir comme cible chiffrée : là où c'est bon, il observe environ 30 cm
crête-à-crête (+15/-15) ; ailleurs, sur LE MÊME DAMIER donc LA MÊME height map, il ne reste que 2 cm
crête-à-crête (+1/-1), voire zéro avec juste la normal map qui donne une illusion de relief.
Même matériau, même carte, même réglage : l'amplitude obtenue ne devrait pas varier.

HYPOTHÈSE PRINCIPALE À TESTER EN PREMIER — ET ELLE UNIFIE CE DÉFAUT AVEC CELUI DES CHUNKS PLATS :
c'est la DENSITÉ DE SOMMETS qui varie, pas l'amplitude commandée. Un patch qui n'a que quelques
sommets par carreau ne PEUT PAS atteindre les extrêmes de la height map : la surface déplacée
échantillonne la carte trop grossièrement et le résultat est écrêté vers la moyenne. Deux sommets
par feature (critère de Nyquist) est un plancher absolu, pas un objectif. Un patch à 0.5 sommet par
carreau rend ~0 cm ; un patch à 4 sommets par carreau rend les 30 cm. Ça expliquerait d'un seul coup
les zones "quasi nulles", les zones à +1cm et la variation continue entre les deux.
Ce qu'il faut produire :
  - pour au moins 6 emplacements du même matériau : amplitude crête-à-crête EFFECTIVEMENT obtenue
    en cm, ET le nombre de sommets par carreau du damier à cet endroit, côte à côte. La corrélation
    entre les deux confirme ou réfute l'hypothèse. Si elle est confirmée, la correction porte sur la
    densité (pré-subdivision + plancher de niveau de tessellation dérivé de la longueur d'onde de la
    feature, pas seulement de la longueur d'arête écran), pas sur un gain d'amplitude.
  - le gate : l'amplitude du PIRE emplacement doit valoir au moins 60% de celle du meilleur. Un
    facteur 15 comme aujourd'hui est un échec.
  - ne "compense" JAMAIS en poussant l'amplitude commandée là où la densité manque : ça donnerait
    des pics en dents de scie. La densité se corrige par la densité.

--------------------------------------------------------------------------------
C2 — POLARITÉ : IL EN RESTE, RAREMENT
--------------------------------------------------------------------------------
"des endroits où le noir du damier semble être plus élevé que le blanc, à de très rares occasions".
Le recensement doit atteindre ZÉRO, pas 99,9%. Les rares cas restants sont ceux que le critère
retenu ne sait pas trancher — identifie CETTE catégorie précise (surfaces non-manifold ? faces
isolées sans voisin ? géométrie à double face ?) et traite-la, au lieu d'améliorer un pourcentage.

--------------------------------------------------------------------------------
C3 — PARALLAX : LE RELIEF S'ÉTALE À PLAT SELON L'ANGLE (défaut le plus grave)
--------------------------------------------------------------------------------
Symptôme exact : sous certains angles le rendu ressemble à la tessellation (correct, en moins fin) ;
sous d'autres, "les carrés blancs recouvrent complètement les carrés noirs comme si ça avait été
étalé à plat plutôt qu'élevé verticalement". Ce n'est PAS de l'occlusion normale : de l'occlusion
légitime à angle rasant fait grandir modérément les zones hautes, elle ne les fait pas AVALER les
zones basses.

MÉTRIQUE OBJECTIVE À CONSTRUIRE — elle est simple et elle discrimine parfaitement :
sur le damier, la fraction de surface BLANCHE vue à l'écran doit rester proche de 50% quand la
caméra tourne. Un vrai relief la fait monter modérément à angle rasant (les plateaux masquent les
creux). Un étalement à plat la fait exploser vers 100%. Donc : balaye l'angle de vue (au moins 6
angles, de face jusqu'au rasant), trace la fraction blanche en fonction de l'angle, pour la
tessellation ET pour le parallax. La courbe tessellation sert de RÉFÉRENCE puisque l'owner la juge
correcte ; la courbe parallax doit la suivre. L'écart entre les deux courbes est le défaut, et il
est mesurable sans jugement esthétique.

SUSPECTS À INSTRUMENTER, dans cet ordre :
  1. Le plancher sur la composante Z du vecteur vue en espace tangent (le max(Vt.z, seuil) hérité
     des rounds précédents) : à angle rasant il fige le rapport Vt.xy/Vt.z et l'offset cesse de
     dépendre correctement de l'angle — exactement le genre de terme qui transforme un relief en
     étalement.
  2. Le décalage final est-il borné par l'INTERSECTION réellement trouvée par la marche, ou
     appliqué tel quel ? Si la marche ne trouve pas d'intersection et qu'on applique quand même le
     décalage maximal, la texture glisse au lieu de se creuser.
  3. Handedness du repère tangent : s'il bascule, le décalage part dans le mauvais sens et selon
     l'angle ça se lit comme un aplatissement. C'est le même suspect que la polarité (C2) — les deux
     défauts pourraient avoir la même racine, vérifie-le explicitement.
  4. Nombre de couches de la marche en fonction de l'angle : trop peu à angle rasant = la marche
     saute par-dessus les creux et ne voit que les plateaux.

GATE : la fraction blanche du parallax doit rester dans une marge étroite de la courbe tessellation
sur tout le balayage d'angles, et ne jamais dépasser un seuil absolu proche de 100%.
