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
