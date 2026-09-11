#version 410 core

out vec4 color;

in vec4 fragment_color;
in vec3 tex_coord;
in float fogginess;
in vec3 v_fringe_rel;  // Grecharged-grass-overhang2: camera-relative world pos (meters)
in vec3 v_world;       // Grecharged-lightprobes: absolute world pos (game units) for probe lookup
in vec3 v_normal;      // Grecharged-directional-ambient: smooth per-vertex world normal (root-cause fix)
in vec4 v_tangent;     // Grecharged-pbr-realtime-fusion REOPEN#7: per-vertex tangent (xyz world, w handedness)
uniform sampler2D tex_T0;

uniform float alpha_min;
uniform float alpha_max;
#include "frame_ubo.glsl"

uniform int gfx_hack_no_tex;

// Grecharged-grass-overhang2: near-fade of the painted grass-fringe alpha strips while the recharged
// 3D droop covers them (owner: the texture showed through the blades). x = enable (set per-draw for
// the two fringe textures only), y/z = fade start/end in METERS. 0 (default) = stock path.
uniform vec4 u_fringe_fade;

#ifdef OG_PBR
// lighting-unify : les uniformes du modele, les deux ambiantes analytiques, le disque de
// Poisson, `Surface` et `shade()` vivent maintenant dans UN seul fichier, partage par les
// cinq programmes monde. Ce bloc etait duplique a l'identique dans les quatre hotes.
// tfrag3 est le SEUL hote qui portait les composites C (u_pbr_mode) et E (u_pbr_shadow_on)
// avant l'unification. Ce jeton les lui rend, et a lui seul : voir la garde dans shade.glsl.
#define SHADE_HOST_LEGACY_PBR 1
#include "shade.glsl"
#endif

void main() {
  // ROUND 22 (owner defect A step 1 — MEASURE before porting): per-pixel displacement coverage,
  // 1.0 only where this fragment actually received displacement (tessellated geometry, or a POM
  // march that actually ran). Painted by u_pbr_debug == 31. Declared unconditionally so the
  // non-OG_PBR build still compiles; it simply stays 0.
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
  if (gfx_hack_no_tex == 0) {
    //vec4 T0 = texture(tex_T0, tex_coord);
    vec4 T0 = texture(tex_T0, tex_coord.xy);
    color = fragment_color * T0;
#ifdef OG_PBR
    // ===== REMPLIR Surface, APPELER shade(). L'hote ne decide plus d'aucun composite. =====
    // Le modele vit dans shade.glsl et il est LE MEME pour les cinq programmes monde.
    // ── GEOMETRIE : la normale d'ombrage. Elle reste chez l'hote parce qu'elle DIFFERE
    // reellement d'un hote a l'autre, et parce que ce n'est pas une decision d'eclairage.
    vec3 gN = cross(dFdx(v_fringe_rel), dFdy(v_fringe_rel));
    float gNl = length(gN);
    gN = gNl > 1e-6 ? gN * (1.0 / gNl) : vec3(0.0, 1.0, 0.0);
    vec3 Vv = -normalize(v_fringe_rel);
    if (dot(gN, Vv) < 0.0) gN = -gN;           // double-sided level tris (outward convention)
    vec3 Ns = v_normal;
    float Nsl2 = dot(Ns, Ns);
    vec3 N;
    if (u_rt_flat_normal == 0 && Nsl2 > 0.2) {  // valid smooth normal present (default)
      Ns *= inversesqrt(Nsl2);
      // ROUND 26, DEFECT D2 : la main du repere ne doit pas dependre de la camera.
      // lighting-legacy-purge (2026-09-11) : u_pbr_bisect RETIRE, valeur livree figee a 0 (chemin complet).
      N = Ns;
    } else {
      N = gN;                                  // A/B force-plat, ou pas de normale reconstruite
    }
    // La carte d'ombre de tfrag3 porte son offset sur la normale de FACE et le N.L de
    // `u_pbr_light_dir[0]` ; TIE et shrub le portent sur leur normale d'ombrage et le N.L du
    // soleil temps reel. Les deux formes existaient deja : elles entrent dans Surface.
    vec3 sng = cross(dFdx(v_fringe_rel), dFdy(v_fringe_rel));
    float sngl = length(sng);
    vec3 snrm = sngl > 1e-6 ? sng / sngl : vec3(0.0, 1.0, 0.0);
    vec3 svv = -normalize(v_fringe_rel);
    if (dot(snrm, svv) < 0.0) snrm = -snrm;
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
    s.shadow_N = snrm;
    s.shadow_ndl = max(dot(snrm, u_pbr_light_dir[0]), 0.0);
    color = shade(s, f_disp_cover, f_disp_diag, f_disp_diag2);
#endif
  } else {
    color = fragment_color/2.0;
  }

  if (u_fringe_fade.x > 0.5) {
    // Grecharged-grass-overhang2 (owner defect 1): fade the painted fringe ALPHA out near the camera
    // so the 3D droop REPLACES it instead of poking through it; far keeps the stock strip, crossfaded
    // over the SAME band the droop blades fade out in. STEEPNESS-gated via screen-space derivatives
    // (level tris are planar, so this is the exact face normal): only the steep hang faces fade —
    // flat walkable ground sharing the texture keeps its stock texels. The scan's fringe/walkable
    // split is upness 0.35 (GrassBakeCore GROUND_UPNESS); the 0.30..0.40 smooth edge straddles it.
    vec3 fdx = dFdx(v_fringe_rel);
    vec3 fdy = dFdy(v_fringe_rel);
    vec3 fnrm = cross(fdx, fdy);
    float fl = length(fnrm);
    float upness = fl > 1e-6 ? abs(fnrm.y) / fl : 1.0;
    float steep_w = 1.0 - smoothstep(0.30, 0.40, upness);
    float dist_f = smoothstep(u_fringe_fade.y, u_fringe_fade.z, length(v_fringe_rel));
    // Grecharged-grass-overhang7 ROUND 10 forensics (u_fringe_fade.w, prop
    // debug.opengoal.grass.fringe_dbg; 0 = stock): mode 2 paints the gate state instead of fading
    // (magenta = steep/would-fade, cyan = gate-blocked flat-ish) so one close capture names WHY a
    // painted tuft survived the near-fade; mode 1 ignores the steepness gate entirely (A/B).
    if (u_fringe_fade.w > 1.5) {
      color.rgb = mix(color.rgb, mix(vec3(0.0, 1.0, 1.0), vec3(1.0, 0.0, 1.0), steep_w), 0.8);
    } else {
      if (u_fringe_fade.w > 0.5) {
        steep_w = 1.0;
      }
      color.a *= mix(1.0, dist_f, steep_w);
    }
  }

  if (color.a < alpha_min || color.a > alpha_max) {
    discard;
  }

  color.rgb = mix(color.rgb, fog_color.rgb, clamp(fogginess * fog_color.a, 0.0, 1.0));
#ifdef OG_PBR
  // ===== ROUND 22 PER-PIXEL SCREEN-COVERAGE INSTRUMENTATION (owner defect A step 1) =====
  // The owner reports "la plupart des endroits n'ont aucun displacement". Before porting the PBR
  // material path to the other renderers we must MEASURE, per pixel, (30) which program drew the
  // pixel and (31) whether that pixel actually received displacement. The tag colours are chosen
  // with a min pairwise distance of 127 so they survive H.264 screenrecord.
  //   30: yellow = tessellated tfrag3 draw, red = plain tfrag3 / TIE-non-envmap
  //   31: white = displaced, black = not displaced
  // color.a is NEVER touched and the block sits AFTER the alpha discard, so alpha-tested foliage
  // discards exactly the same fragments and the coverage number is not inflated by solid quads.
  // It is also after the fog mix, so the tag reaches the framebuffer unblended (a fogged tag would
  // drift toward fog_color and break the classification at distance).
  if (u_pbr_debug == 30) {
    // lighting-legacy-purge (2026-09-11) : plus aucun programme tesselé, la marque jaune ne peut plus sortir.
    color.rgb = vec3(1.0, 0.0, 0.0);
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
