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
// composite D, leur seul lecteur, a ete retire (SPEC §2.4).
in vec3 v_fringe_rel;
in vec3 v_normal;
// lighting-unify : les uniformes du modele, les deux ambiantes analytiques, le disque de
// Poisson, `Surface` et `shade()` vivent maintenant dans UN seul fichier, partage par les
// cinq programmes monde. Ce bloc etait duplique a l'identique dans les quatre hotes.
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
    s.gN = gN;
    s.V = Vv;
    s.N = N;
    s.shadow_N = N;
    s.shadow_ndl = max(dot(N, normalize(u_rt_sun_dir)), 0.0);
    color = shade(s);
#endif
  } else {
    color = fragment_color/2.0;
  }

  if (color.a < alpha_min || color.a > alpha_max) {
    discard;
  }

  color.rgb = mix(color.rgb, fog_color.rgb, clamp(fogginess * fog_color.a, 0.0, 1.0));
#ifdef OG_PBR
  // ETIQUETTE DE PROGRAMME (u_pbr_debug == 30) : quel programme a dessine ce pixel. Les teintes
  // sont espacees d'au moins 127 pour survivre a un enregistrement H.264 ; les scripts de mesure
  // de couverture s'appuient sur ces couleurs exactes. tie_wind = cyan.
  // color.a n'est JAMAIS touche et le bloc est APRES le discard alpha et APRES le brouillard,
  // pour que l'etiquette atteigne le framebuffer sans melange.
  if (u_pbr_debug == 30) {
    color.rgb = vec3(0.0, 1.0, 1.0);
  }
#endif
  // Alpha is a blend weight, even when RGB has floating-point HDR headroom.
  // Keep the original alpha tests above, then match the normalized target range.
  color.a = clamp(color.a, 0.0, 1.0);
}