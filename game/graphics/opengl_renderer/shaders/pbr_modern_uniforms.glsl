// ===================================================================================================
// Grecharged-materials-modern-parity — MODERN MATERIAL STACK, uniform block.
//
// COMPANION CHUNK. This file is never #include'd by a shader: Shader.cpp's expand_includes() appends
// it VERBATIM right after "pbr_uniforms.glsl" (see kChunkCompanions there). That is deliberate and it
// is the whole architectural point of this phase:
//
//   the five shaders pbr_helpers.glsl / pbr_fused.glsl / tfrag3.frag / tfrag3_tess.{tesc,tese} carry
//   the owner-ACCEPTED look. Round 27 of the fusion phase edited them and the owner's verdict was
//   "beaucoup, beaucoup moins bien qu'avant"; commit 4b736aab03 reverted them to fc7b815e34 and they
//   have been bit-pristine since. This phase adds a whole material layer on top of that tree WITHOUT
//   editing one byte of it — every modern channel lives in three new chunks that the include expander
//   splices in at the same three points. Consequences that matter:
//     * "OFF == stock" is structural, not measured: with the layer off nothing here writes anything.
//     * the fusion phase can resume on a pristine tree whenever the owner wants it.
//     * one definition of each channel, shared by all four world programs (tfrag3, etie_base,
//       tie_wind, shrub) exactly like the fused chunk itself — no copy-paste divergence.
//
// Everything below defaults to the identity. A material that does not opt in gets u_mm_flags == 0 and
// the shading chunk returns before touching `color`.
// ===================================================================================================

// PER-DRAW capability bitfield = (this material's authored flags) AND (the global master switch),
// resolved C++-side in PbrDrawBinder so the shader never has to know about menus or props.
//    1 = SUBSURFACE SCATTERING (transmission + terminator wrap)
//    2 = CLEARCOAT (second specular lobe over the base layer)
//    4 = ANISOTROPY (tangent-aligned GGX lobe)
//    8 = ENERGY COMPENSATION (Kulla-Conty multiple-scatter, the energy single-scatter GGX loses)
//   16 = SPECULAR + HORIZON OCCLUSION (the two IBL-quality terms modern engines apply to env spec)
//   32 = this material bound a <tex>_thickness.png on tex_PBR_TH (else the scalar in u_mm_sss2.x)
//   64 = FILMIC tone curve instead of the accepted C1 shoulder (opt-in; never the default)
//  128 = informational: this material's occlusion/roughness/metallic came from ONE packed _orm.png.
//        No shader effect at all — the loader splits ORM into the same three single-channel textures
//        the unpacked path uploads, so the render path cannot tell the difference. The bit exists so
//        the debug tag (u_mm_debug 7) can show which materials are packed.
uniform int u_mm_flags;
// SUBSURFACE. rgb = SCATTERING COLOUR in LINEAR space (the colour light takes on after travelling
// through the surface — for a leaf a saturated green, for skin a deep red, for wax an amber). a =
// strength. This is the "scattering color" the owner asked for by name.
uniform vec4 u_mm_sss;
// SUBSURFACE, second half:
//   x = fallback THICKNESS when no _thickness.png is bound (1 = thin/very translucent, 0 = opaque)
//   y = transmission falloff POWER (large = a tight back-light glow, small = broad wash)
//   z = normal DISTORTION of the transmission vector (Frostbite/DICE: bends -L by the surface normal
//       so the glow follows the relief instead of being a flat view-vs-light dot)
//   w = terminator WRAP amount (light bleeding past the geometric terminator, 0 = none)
uniform vec4 u_mm_sss2;
// CLEARCOAT: x = weight 0..1, y = coat roughness, z = ambient-transmission share for SSS (how much of
// the skylight also comes through the surface — a leaf glows in open shade too), w = unused.
uniform vec4 u_mm_coat;
// ANISOTROPY: x = amount in [-0.95, 0.95] (negative = the lobe stretches along the bitangent),
// y = rotation of the tangent frame around the normal, in radians.
uniform vec2 u_mm_aniso;
// Exposure applied to the PBR composite before the tone curve. 1.0 = the accepted calibration.
uniform float u_mm_exposure;
// Per-channel isolation viz, PBR draws only, so each new channel can be A/B'd on its own:
//   0 = off (normal render)      1 = SSS transmission only     2 = clearcoat lobe only
//   3 = anisotropic delta        4 = energy-compensation delta  5 = specular+horizon occlusion factor
//   6 = thickness                7 = capability tag (R=sss, G=coat, B=aniso, white dot = ORM-packed)
uniform int u_mm_debug;
// SUBSURFACE THICKNESS MAP, <tex>_thickness.png. Bound on its own unit; a 1x1 white default keeps the
// sampler complete on every draw, so a material without the map never reads garbage.
uniform sampler2D tex_PBR_TH;
