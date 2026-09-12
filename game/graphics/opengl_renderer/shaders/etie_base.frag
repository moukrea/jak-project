#version 410 core

out vec4 color;

in vec4 fragment_color;
in vec3 tex_coord;
in float fogginess;
uniform sampler2D tex_T0;

uniform float alpha_min;
uniform float alpha_max;
#include "frame_ubo.glsl"

uniform int gfx_hack_no_tex;

#ifdef OG_PBR
// Grecharged-realtime-lighting round-3 (defect A/B): the SAME sun-only N.L path
// tfrag3.frag uses, replicated so envmap-tie base / wind-tie / shrub are sun-lit
// EVERYWHERE (not only inside the shadow zone) and receive the cast shadow. All
// Varyings consommes par le modele d'ombrage. `v_world` et `v_todc` ne sont plus declares : le
// composite D, leur seul lecteur, a ete retire (SPEC §2.4). Un varying produit par le vertex sans
// consommateur cote fragment est legal.
in vec3 v_fringe_rel;
in vec3 v_normal;
in vec4 v_tangent;
// lighting-unify : les uniformes du modele, les deux ambiantes analytiques, le disque de
// Poisson, `Surface` et `shade()` vivent maintenant dans UN seul fichier, partage par les
// cinq programmes monde. Ce bloc etait duplique a l'identique dans les quatre hotes.
#include "shade.glsl"
#endif


void main() {
#ifdef OG_PBR
  // ROUND 22 per-pixel displacement coverage (u_pbr_debug == 31). Now that this program has a real
  // PBR path this is no longer hardcoded 0: it is set to 1.0 exactly where the POM march actually
  // ran, by the shared fused chunk.
  float f_disp_cover = 0.0;
  // ROUND 24 DEAD-ZONE DIAGNOSTIC (u_pbr_debug == 33), filled by the shared fused chunk:
  //   R = the vertex displacement the TESSELLATION tier actually applied at this fragment, in
  //       cm/10 (|h-0.5| * amp_m * falloff*seam) — 0 means the tier moved nothing HERE.
  //   G = the final POM offset after every cap, converted to world cm/10 — 0 means the parallax
  //       tier moved nothing HERE.
  //   B = camera distance in m/40 (the driver of both LOD fades), so a dead pixel can be
  //       attributed to distance without a second capture.
  vec3 f_disp_diag = vec3(0.0);
  vec3 f_disp_diag2 = vec3(0.0);  // ROUND 24 mode 34: (« tess-disp-w », |h-0.5|*2, amp_m)
#endif
  if (gfx_hack_no_tex == 0) {
    //vec4 T0 = texture(tex_T0, tex_coord);
    vec4 T0 = texture(tex_T0, tex_coord.xy);
    color = fragment_color * T0;
#ifdef OG_PBR
    // ===== REMPLIR Surface, APPELER shade(). L'hote ne decide plus d'aucun composite. =====
    // Le modele vit dans shade.glsl et il est LE MEME pour les cinq programmes monde.
    // ── GEOMETRIE : la normale d'ombrage (identique a tfrag3 ; shrub en a une autre).
    vec3 gN = cross(dFdx(v_fringe_rel), dFdy(v_fringe_rel));
    float gNl = length(gN);
    gN = gNl > 1e-6 ? gN * (1.0 / gNl) : vec3(0.0, 1.0, 0.0);
    vec3 Vv = -normalize(v_fringe_rel);
    if (dot(gN, Vv) < 0.0) gN = -gN;
    vec3 Ns = v_normal;
    float Nsl2 = dot(Ns, Ns);
    vec3 N;
    if (u_rt_flat_normal == 0 && Nsl2 > 0.2) {
      Ns *= inversesqrt(Nsl2);
      // lighting-legacy-purge (2026-09-11) : u_pbr_bisect RETIRE, valeur livree figee a 0 (chemin complet).
      N = Ns;
    } else {
      N = gN;
    }
    Surface s;
    s.base = color;
    s.baked = fragment_color;
    s.tex0 = T0;
    s.P_rel = v_fringe_rel;
    s.uv = tex_coord;
    s.vnormal = v_normal;
    s.T = v_tangent;
    s.gN = gN;
    s.V = Vv;
    s.N = N;
    s.shadow_N = N;
    s.shadow_ndl = max(dot(N, normalize(u_rt_sun_dir)), 0.0);
    color = shade(s, f_disp_cover, f_disp_diag, f_disp_diag2);
#endif
  } else {
    color = fragment_color/2.0;
  }

  if (color.a < alpha_min || color.a > alpha_max) {
    discard;
  }

  color.rgb = mix(color.rgb, fog_color.rgb, clamp(fogginess * fog_color.a, 0.0, 1.0));
#ifdef OG_PBR
  // ===== ROUND 22 PER-PIXEL SCREEN-COVERAGE INSTRUMENTATION (owner defect A step 1) =====
  // Program tag (30) and displacement tag (31). See tfrag3.frag for the full rationale.
  // etie_base = green (unchanged — the coverage measurement scripts key on these exact colours).
  // ROUND 22 UPDATE: this renderer now HAS a PBR/displacement path, so tag 31 reports the real
  // per-pixel flag the fused chunk sets instead of the hardcoded 0.0 it used while it had none.
  // color.a is NEVER touched and this sits AFTER the alpha discard AND after the fog mix, so the
  // discard keeps rejecting the same fragments and the tag reaches the framebuffer unblended.
  if (u_pbr_debug == 30) {
    color.rgb = vec3(0.0, 1.0, 0.0);
  } else if (u_pbr_debug == 31) {
    color.rgb = vec3(f_disp_cover);
  } else if (u_pbr_debug == 32) {
    // ROUND 24 DENOMINATOR MASK (owner's own framing: "la geometrie ou c'est sense etre le cas,
    // car utilise une texture qui a les maps"). White iff THIS fragment's material has a HEIGHT
    // map bound — nothing else. Deliberately independent of the displacement setting, the tier,
    // the distance and the amplitude, so it is a pure denominator and can never be inflated by
    // the very capability the numerator is supposed to measure.
    color.rgb = ((u_pbr_mode & 16) != 0) ? vec3(1.0) : vec3(0.0);
  } else if (u_pbr_debug == 33) {
    color.rgb = f_disp_diag;
  } else if (u_pbr_debug == 34) {
    color.rgb = f_disp_diag2;
  }
#endif

  // Alpha is a blend weight, even when RGB has floating-point HDR headroom.
  // Keep the original alpha tests above, then match the normalized target range.
  color.a = clamp(color.a, 0.0, 1.0);
}
