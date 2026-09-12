#version 410 core

out vec4 color;

in vec4 fragment_color;
in vec3 tex_coord;
in float fogginess;
in vec3 v_fringe_rel;  // Grecharged-grass-overhang2: camera-relative world pos (meters)
in vec3 v_world;       // Grecharged-lightprobes: absolute world pos (game units) for probe lookup
in vec3 v_normal;      // Grecharged-directional-ambient: smooth per-vertex world normal (root-cause fix)
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
// lighting-unify : les uniformes du modele, le disque de Poisson, `Surface` et `shade()`
// vivent dans UN seul fichier, partage par les cinq programmes monde. Ce bloc etait
// duplique a l'identique dans les quatre hotes.
#include "shade.glsl"
#endif

void main() {
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
      N = Ns;
    } else {
      N = gN;                                  // A/B force-plat, ou pas de normale reconstruite
    }
    // La carte d'ombre de tfrag3 porte son offset sur la normale de FACE et le N.L du soleil ;
    // TIE et shrub le portent sur leur normale d'ombrage. Les deux formes existaient deja :
    // elles entrent dans Surface.
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
    s.gN = gN;
    s.V = Vv;
    s.N = N;
    s.shadow_N = snrm;
    // lighting-legacy-purge (2026-09-12) : le N.L de l'offset d'ombre lisait le premier
    // vecteur de l'ancien tableau de lumieres, retire avec la pile de matiere. La
    // substitution est BIT-EXACTE et mesuree : background_common.cpp:2459 poussait ce
    // tableau depuis `light_dir[9]`, et :2505 pousse u_rt_sun_dir depuis light_dir[0..2] —
    // le MEME triplet, dans le MEME appel, sur la MEME image.
    s.shadow_ndl = max(dot(snrm, u_rt_sun_dir), 0.0);
    color = shade(s);
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
  // ETIQUETTE DE PROGRAMME (u_pbr_debug == 30) : quel programme a dessine ce pixel. Les teintes
  // sont espacees d'au moins 127 pour survivre a un enregistrement H.264. tfrag3 = rouge.
  // color.a n'est JAMAIS touche et le bloc est APRES le discard alpha et APRES le brouillard,
  // pour que l'etiquette atteigne le framebuffer sans melange.
  if (u_pbr_debug == 30) {
    color.rgb = vec3(1.0, 0.0, 0.0);
  }
#endif
  // Alpha is a blend weight, even when RGB has floating-point HDR headroom.
  // Keep the original alpha tests above, then match the normalized target range.
  color.a = clamp(color.a, 0.0, 1.0);
}
