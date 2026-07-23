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
