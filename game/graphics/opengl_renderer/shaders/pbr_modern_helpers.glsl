// ===================================================================================================
// Grecharged-materials-modern-parity — MODERN MATERIAL STACK, function block.
//
// COMPANION CHUNK, appended verbatim after "pbr_helpers.glsl" (Shader.cpp kChunkCompanions). It may
// therefore use everything that chunk declares (hnorm(), the POM depth law, rt_amb_eval()) and every
// uniform from pbr_uniforms.glsl + pbr_modern_uniforms.glsl. It declares no state of its own.
//
// Guarded by OG_PBR exactly like pbr_helpers.glsl: in a build without the --pbr flag the define never
// exists, so not one line of this file reaches the GLSL compiler.
// ===================================================================================================
#ifdef OG_PBR

// ---- ANISOTROPIC GGX (Burley 2012 / Frostbite) -----------------------------------------------------
// The isotropic lobe the fused chunk evaluates assumes the microfacets have no preferred direction.
// Brushed metal, hair, wood grain and woven cloth do have one, and the difference is not subtle: the
// highlight stretches perpendicular to the grain instead of staying a round dot. `at`/`ab` are the two
// roughness values along the tangent and the bitangent; at == ab reduces EXACTLY to the isotropic
// D/Vis the fused chunk uses, which is what makes the delta form below safe.
float mm_ggx_d_aniso(float NdH, float ToH, float BoH, float at, float ab) {
  float a2 = at * ab;
  vec3 v = vec3(ab * ToH, at * BoH, a2 * NdH);
  float v2 = dot(v, v);
  float w2 = a2 / max(v2, 1e-12);
  return a2 * w2 * w2 * (1.0 / 3.14159265);
}

// Height-correlated Smith visibility for the anisotropic lobe (contains the 1/(4 NdL NdV) denominator,
// same convention as the isotropic `Vis` in pbr_fused.glsl).
float mm_ggx_vis_aniso(float NdL,
                       float NdV,
                       float ToV,
                       float BoV,
                       float ToL,
                       float BoL,
                       float at,
                       float ab) {
  float lv = NdL * length(vec3(at * ToV, ab * BoV, NdV));
  float ll = NdV * length(vec3(at * ToL, ab * BoL, NdL));
  return 0.5 / max(lv + ll, 1e-4);
}

// Isotropic D*Vis, transcribed from pbr_fused.glsl term for term so the anisotropic DELTA below is
// exactly zero when the anisotropy is zero. If that chunk's lobe ever changes, change this with it.
float mm_ggx_dvis_iso(float NdH, float NdL, float NdV, float a2) {
  float dd = NdH * NdH * (a2 - 1.0) + 1.0;
  float D = a2 / (3.14159265 * dd * dd);
  float gv = NdL * sqrt(NdV * NdV * (1.0 - a2) + a2);
  float gl = NdV * sqrt(NdL * NdL * (1.0 - a2) + a2);
  return D * (0.5 / max(gv + gl, 1e-4));
}

// ---- CLEARCOAT ------------------------------------------------------------------------------------
// A clearcoat is a thin smooth dielectric film (IOR ~1.5 => F0 = 0.04) lying OVER the base material.
// Two consequences, both implemented: it adds its own sharp specular lobe, and it takes that energy
// out of the layer underneath. Kelemen's visibility term is the standard cheap pairing for it — the
// coat is smooth enough that the full Smith height-correlated form is wasted there.
float mm_coat_dvis(float NdH, float LdH, float ca2) {
  float dd = NdH * NdH * (ca2 - 1.0) + 1.0;
  float D = ca2 / (3.14159265 * dd * dd);
  float Vis = 0.25 / max(LdH * LdH, 1e-4);  // Kelemen
  return D * Vis;
}

// Schlick Fresnel for the coat's fixed dielectric F0.
float mm_coat_fresnel(float c) {
  return 0.04 + 0.96 * pow(clamp(1.0 - c, 0.0, 1.0), 5.0);
}

// ---- SPECULAR + HORIZON OCCLUSION -----------------------------------------------------------------
// Two terms every modern engine applies to image-based specular and this pipeline did not have.
// (1) SPECULAR OCCLUSION (Lagarde/Frostbite, "Moving Frostbite to PBR"): the diffuse occlusion factor
//     is measured over the whole hemisphere, so applying it unchanged to a narrow reflection lobe
//     over-darkens smooth surfaces and under-darkens rough ones. This re-derives an occlusion for the
//     lobe's own solid angle from (NdV, ao, roughness).
// (2) HORIZON OCCLUSION (Frostbite): the reflection vector built from a normal-MAPPED normal routinely
//     points below the real geometric surface, which fetches environment radiance that the surface
//     itself blocks — the classic normal-mapped-ground shimmer of light coming from inside the floor.
// Both can only ever REDUCE the environment specular, so neither can reintroduce the glass sheen the
// owner rejected; they make the existing env term physically defensible.
float mm_spec_occlusion(float NdV, float ao_in, float rough_in, vec3 Rf, vec3 Ngeo) {
  float so = clamp(pow(max(NdV + ao_in, 0.0), exp2(-16.0 * rough_in - 1.0)) - 1.0 + ao_in, 0.0, 1.0);
  float ho = clamp(1.0 + 1.3 * dot(Rf, Ngeo), 0.0, 1.0);
  return so * ho * ho;
}

// ---- FILMIC TONE CURVE (opt-in, never the default) -------------------------------------------------
// Narkowicz's ACES fit. The shipped default remains the C1 soft shoulder the owner's look was
// calibrated against — this exists so a PBR surface pushed hard by a strong scattering or coat term
// rolls off like a modern renderer instead of clipping, and it is reachable only through u_mm_flags
// bit 64 (never set by any default material profile).
vec3 mm_tonemap_aces(vec3 x) {
  const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

#endif
