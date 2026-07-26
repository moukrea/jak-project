#version 410 core

out vec4 color;
in vec4 vtx_color;
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

void main() {
  if (gfx_hack_no_tex == 0) {
    vec4 T0 = texture(tex_T0, vtx_st);
    // all merc is tcc=rgba and modulate
    if (decal_enable == 0) {
      color = vtx_color * T0 * 2.0;
    } else {
      color = T0;
    }
    color.a *= 2.0;
  } else {
    color.rgb = vtx_color.rgb;

    if (decal_enable == 0) {
      color.a = vtx_color.a * 2.0;
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
}
