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
