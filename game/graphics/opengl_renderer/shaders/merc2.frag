#version 410 core

#ifdef OG_FLIP_PROBE
layout(location = 0) out vec4 color;
uniform int u_floor_probe;
layout(location = 4) out vec4 floor_probe_out;
#else
out vec4 color;
#endif
in vec4 vtx_color;
in vec4 vtx_color_twin;
in vec3 vtx_nrm_view;
in vec3 vtx_pos_view;
in vec2 vtx_st;
in float fog;

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

float rt_luma_merc(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void main() {
#ifdef OG_FLIP_PROBE
  floor_probe_out = vec4(0.0);
#endif
  // lighting-flipped-faces-everywhere : eclaire la face reellement VUE (comme le decor dans
  // shade.glsl), sauf sur les silhouettes rasantes ou la normale interpolee n'est pas fiable.
  // mf_face proche de 0 = silhouette : on garde alors l'eclairage d'origine.
  vec3 gN = cross(dFdx(vtx_pos_view), dFdy(vtx_pos_view));
  float gNl = length(gN);
  gN = gNl > 1e-12 ? gN / gNl : vec3(0.0, 0.0, 1.0);
  vec3 Vv = normalize(-vtx_pos_view);
  if (dot(gN, Vv) < 0.0) gN = -gN;
  float mf_face = dot(gN, Vv);
  bool mf_flip = dot(vtx_nrm_view, gN) < 0.0;
  // Seule la COULEUR change de cote : l'alpha reste celui d'origine (transparences intactes).
  vec4 lit = vec4(((mf_flip && mf_face >= 0.25) ? vtx_color_twin : vtx_color).rgb, vtx_color.a);

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
  // lighting-flipped-faces-everywhere : merc n'a pas de terme d'eclairage rechargE separe (pas
  // d'OFF distinct dans la meme image) ; la REFERENCE est le cote VU (L_v).
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
