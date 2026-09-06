#version 410 core

out vec4 color;

in vec4 fragment_color;
in vec3 tex_coord;
in float fogginess;
uniform sampler2D tex_T0;

uniform float alpha_min;
uniform float alpha_max;
uniform vec4 fog_color;

uniform int gfx_hack_no_tex;

#ifdef OG_PBR
// Grecharged-realtime-lighting round-3 (defect A/B): the SAME sun-only N.L path
// tfrag3.frag uses, replicated so envmap-tie base / wind-tie / shrub are sun-lit
// EVERYWHERE (not only inside the shadow zone) and receive the cast shadow. All
// Varyings consommes par le modele d'ombrage. shrub n'a PAS de tangente par sommet : il pousse
// (0,0,0,1) dans `Surface.T`, comme il fabriquait un local avant. `v_world` / `v_todc` ne sont plus
// declares : le composite D, leur seul lecteur, a ete retire (SPEC §2.4).
in vec3 v_fringe_rel;
in vec3 v_normal;
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
  vec3 f_disp_diag2 = vec3(0.0);  // ROUND 24 mode 34: (tess_disp_w, |h-0.5|*2, amp_m)
#endif
  if (gfx_hack_no_tex == 0) {
    vec4 T0 = texture(tex_T0, tex_coord.xy);
    color = fragment_color * T0;
#ifdef OG_PBR
    // ===== REMPLIR Surface, APPELER shade(). L'hote ne decide plus d'aucun composite. =====
    // Le modele vit dans shade.glsl et il est LE MEME pour les cinq programmes monde.
    // ── GEOMETRIE : la normale d'ombrage de shrub. Elle DIFFERE : seuil 1e-6 au lieu de 0.2,
    // bit de bisect 134217728 au lieu de 2, et `u_rt_flat_normal` n'existe pas ici. La fusionner
    // avec celle de tfrag3 aurait retourne le relief des arbustes ; elle reste donc chez l'hote,
    // et c'est exactement ce que le contrat de Surface prevoit.
    vec3 gN = cross(dFdx(v_fringe_rel), dFdy(v_fringe_rel));
    float gNl = length(gN);
    gN = gNl > 1e-6 ? gN * (1.0 / gNl) : vec3(0.0, 1.0, 0.0);
    bool has_vn = dot(v_normal, v_normal) > 1e-6;
    vec3 N = has_vn ? normalize(v_normal) : gN;
    vec3 Vv = -normalize(v_fringe_rel);
    if ((!has_vn || (u_pbr_bisect & 134217728) != 0) && dot(N, Vv) < 0.0) N = -N;
    Surface s;
    s.base = color;
    s.baked = fragment_color;
    s.tex0 = T0;
    s.P_rel = v_fringe_rel;
    s.uv = tex_coord;
    s.vnormal = v_normal;
    s.T = vec4(0.0, 0.0, 0.0, 1.0);  // shrub n'a pas de tangente par sommet
    s.tess_disp_w = 0.0;
    s.gN = gN;
    s.V = Vv;
    s.N = N;
    s.shadow_N = N;
    s.shadow_ndl = max(dot(N, normalize(u_rt_sun_dir)), 0.0);
    color = shade(s, f_disp_cover, f_disp_diag, f_disp_diag2);
#endif
  } else {
    color = fragment_color;
  }

  if (color.a < alpha_min || color.a > alpha_max) {
    discard;
  }

  color.xyz = mix(color.xyz, fog_color.rgb, clamp(fogginess * fog_color.a, 0.0, 1.0));
#ifdef OG_PBR
  // ===== ROUND 22 PER-PIXEL SCREEN-COVERAGE INSTRUMENTATION (owner defect A step 1) =====
  // Program tag (30) and displacement tag (31). See tfrag3.frag for the full rationale.
  // shrub = blue (unchanged — the coverage measurement scripts key on these exact colours).
  // ROUND 22 UPDATE: this renderer now HAS a PBR/displacement path, so tag 31 reports the real
  // per-pixel flag the fused chunk sets instead of the hardcoded 0.0 it used while it had none.
  // color.a is NEVER touched and this sits AFTER the alpha discard AND after the fog mix, so the
  // discard keeps rejecting the same fragments and the tag reaches the framebuffer unblended.
  if (u_pbr_debug == 30) {
    color.rgb = vec3(0.0, 0.0, 1.0);
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
}
