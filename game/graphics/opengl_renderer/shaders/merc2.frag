#version 410 core

#ifdef OG_FLIP_PROBE
layout(location = 0) out vec4 color;
uniform int u_floor_probe;
layout(location = 4) out vec4 floor_probe_out;
#else
out vec4 color;
#endif
in vec4 vtx_color;
#ifdef OG_FLIP_PROBE
in vec4 vtx_color_twin;
in vec3 vtx_nrm_view;
in vec3 vtx_pos_view;
#endif
in vec2 vtx_st;
in float fog;
in vec3 vtx_view;
in vec4 vtx_color_dir;

uniform sampler2D tex_T0;

uniform vec4 fog_color;
uniform int ignore_alpha;
uniform vec4 light_dir0_fade;
uniform vec4 light_dir1_fade_en;

uniform int decal_enable;

uniform int gfx_hack_no_tex;

// ROUND 22 PER-PIXEL SCREEN-COVERAGE INSTRUMENTATION (owner defect A step 1). Shared PBR debug
// selector (android prop debug.opengoal.pbr.debug), pushed by pbr_push_debug_tag() in
// background_common.cpp. Mode 30 = program tag, 31 = displacement tag. This shader has no PBR
// block, so the uniform is declared plainly. If a program is ever linked without it,
// glGetUniformLocation returns -1 and glUniform1i(-1, ...) is a documented no-op.
uniform int u_pbr_debug;

// lighting-shadows essai 6 (SPEC §4.8) : reception de l'atlas d'ombre par MERC. Les ponts de
// village1 (ropebridge-4/5) sont des acteurs dessines par ce programme ; merc2.frag n'incluait
// shade.glsl NULLE PART, donc aucune ombre portee ne pouvait jamais y tomber. Seule la part
// DIRECTIONNELLE (vtx_color_dir) est ombree — l'ambiante ne l'est jamais. La composition complete
// des acteurs par shade() (lighting-actors, SPEC 4.13) n'est pas ce chunk : c'est une visibilite
// PARTAGEE avec le decor (meme atlas, meme force).
uniform int u_rt_light_on;
uniform vec4 u_rt_regime;
uniform vec3 u_rt_sun_dir;
uniform vec3 u_rt_moon_dir;
uniform mat4 u_merc_view_to_rel;
uniform vec2 u_merc_shadow_w;
uniform int u_merc_shadow_recv;
#include "shadow_atlas.glsl"

float rt_luma_merc(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// Direction unitaire sans NaN (voir shade.glsl : rt_safe_dir).
vec3 rt_safe_dir_merc(vec3 v) {
  float l = length(v);
  return l > 1e-6 ? v / l : vec3(0.0, 1.0, 0.0);
}

void main() {
#ifdef OG_FLIP_PROBE
  floor_probe_out = vec4(0.0);
  // lighting-flipped-faces-everywhere essai 3 : SONDE seulement. Le rendu merc est l'eclairage
  // d'origine, sans retournement (owner 25/09, « pas de repli »).
  vec3 gN = cross(dFdx(vtx_pos_view), dFdy(vtx_pos_view));
  float gNl = length(gN);
  gN = gNl > 1e-12 ? gN / gNl : vec3(0.0, 0.0, 1.0);
  vec3 Vv = normalize(-vtx_pos_view);
  if (dot(gN, Vv) < 0.0) gN = -gN;
  float mf_face = dot(gN, Vv);
  bool mf_flip = dot(vtx_nrm_view, gN) < 0.0;
#endif
  vec4 lit = vtx_color;

  // lighting-shadows essai 6 : reception de l'atlas d'ombre (voir le commentaire pres des
  // uniformes ci-dessus). `m_gN` est une normale d'ecran (comme le fallback tfrag3 sans
  // tangente) ; seule la part directionnelle est retiree, l'ambiante reste intacte.
  vec3 m_prel = vec3(0.0); vec3 m_gN = vec3(0.0, 1.0, 0.0); float m_kndl = 0.0;
  bool m_recv = u_pbr_shadow_on != 0 && u_merc_shadow_recv != 0;
  if (m_recv) {
    m_prel = (u_merc_view_to_rel * vec4(vtx_view, 1.0)).xyz;
    vec3 g = cross(dFdx(m_prel), dFdy(m_prel)); float g_len = length(g);
    m_gN = g_len > 1e-12 ? g / g_len : vec3(0.0, 1.0, 0.0);
    if (dot(m_gN, -m_prel) < 0.0) m_gN = -m_gN;
    vec3 Ls = rt_safe_dir_merc(u_rt_sun_dir);
    vec3 Lm = rt_safe_dir_merc(u_rt_moon_dir);
    float sun_ndl = clamp(dot(m_gN, Ls), 0.0, 1.0), moon_ndl = clamp(dot(m_gN, Lm), 0.0, 1.0);
    float key_ndl = (u_shadow_key == 0) ? sun_ndl : moon_ndl;
    float sec_ndl = (u_shadow_key == 0) ? moon_ndl : sun_ndl;
    m_kndl = key_ndl;
    float key = mix(1.0, rt_key_vis(m_prel, m_gN, key_ndl), u_shadow_strength);
    float sec = mix(1.0, rt_sec_vis(m_prel, m_gN, sec_ndl), u_shadow_strength);
    float wsum = u_merc_shadow_w.x + u_merc_shadow_w.y;
    float vis = wsum > 1e-4 ? (u_merc_shadow_w.x * key + u_merc_shadow_w.y * sec) / wsum : 1.0;
    lit.rgb -= vtx_color_dir.rgb * (1.0 - vis);
  }

  if (gfx_hack_no_tex == 0) {
    vec4 T0 = texture(tex_T0, vtx_st);
    // all merc is tcc=rgba and modulate
    if (decal_enable == 0) {
      color = lit * T0 * 2.0;
    } else {
      color = T0;
    }
    color.a *= 2.0;
  } else {
    color.rgb = lit.rgb;

    if (decal_enable == 0) {
      color.a = lit.a * 2.0;
    } else {
      color.a = 1.0;
    }
  }

  if (light_dir1_fade_en.w > 0.0) {
    color.a = light_dir0_fade.w;
  } else if (light_dir1_fade_en.w < 0.0) {
    color.a *= light_dir0_fade.w;
  }


  if (ignore_alpha == 0 && color.w < 0.128) {
    discard;
  }

#ifdef OG_FLIP_PROBE
  // lighting-flipped-faces-everywhere : merc n'a pas de terme d'eclairage recharge (ON == OFF, le
  // rendu EST l'origine). x = origine / cote VU (L_v) : population « vue de dos », publiee, non jugee.
  if (u_floor_probe >= 2) {
    vec3 T = (gfx_hack_no_tex == 0) ? texture(tex_T0, vtx_st).rgb : vec3(0.5);
    vec4 L_v = mf_flip ? vtx_color_twin : vtx_color;
    float fc_on;
    float fc_v;
    if (decal_enable != 0) {
      fc_on = rt_luma_merc(T);
      fc_v = rt_luma_merc(T);
    } else {
      fc_on = rt_luma_merc(lit.rgb * T * 2.0);
      fc_v = rt_luma_merc(L_v.rgb * T * 2.0);
    }
    // y = cosinus d'incidence de la FACE (0 = rasante, silhouette ; 1 = de face) : une normale
    // interpolee qui passe derriere la vue sur une silhouette n'est pas une face a l'envers.
    floor_probe_out = vec4(fc_on / max(fc_v, 1e-4), mf_face, fc_v,
                           1.0 + (mf_flip ? 1.0 : 0.0) + 2.0 * (gl_FrontFacing ? 1.0 : 0.0) +
                               4.0 * float(u_floor_probe));
  }
#endif

  // lighting-shadows essai 6 : sonde de preuve, meme mecanisme que le decor — magenta/bleu/cyan/vert
  // (voir rt_shadow_proof_color, shadow_atlas.glsl), restreinte aux draws qui recoivent l'atlas.
  if (u_shadow_proof != 0 && u_merc_shadow_recv != 0) {
    color.rgb = (u_pbr_shadow_on == 0) ? vec3(0.0, 1.0, 0.0)
                                       : rt_shadow_proof_color(m_prel, m_gN, m_kndl, color.a).rgb;
  }

   color.xyz = mix(color.xyz, fog_color.rgb, clamp(fog_color.a * fog, 0.0, 1.0));
  // ===== ROUND 22 COVERAGE TAG (see tfrag3.frag for the rationale) =====
  // merc2 = magenta. No PBR/displacement path here yet, so mode 31 reads 0.0 by construction —
  // that is exactly the quantity being measured. color.a is NEVER touched and this sits after the
  // alpha discard and the fog mix, so the discard is unchanged and the tag arrives unblended.
  if (u_pbr_debug == 30) {
    color.rgb = vec3(1.0, 0.0, 1.0);
  } else if (u_pbr_debug >= 31 && u_pbr_debug <= 34) {
    // ROUND 24: 31 = displacement tag, 32 = maps-bearing DENOMINATOR mask, 33 = dead-zone
    // diagnostic. This program never carries PBR material maps, so it is black in all three —
    // otherwise its scene colour would be counted as mask/diagnostic signal.
    color.rgb = vec3(0.0);
  }
  // Alpha is a blend weight, even when RGB has floating-point HDR headroom.
  // Keep the original alpha tests above, then match the normalized target range.
  color.a = clamp(color.a, 0.0, 1.0);
}
