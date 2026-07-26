#version 410 core


out vec4 color;
in vec2 tex_coord;

uniform float alpha_reject;
uniform float color_mult;
uniform vec4 fog_color;
in float fog;
in vec4 fragment_color;

flat in uvec2 tex_info;

uniform int gfx_hack_no_tex;

// ROUND 22 PER-PIXEL SCREEN-COVERAGE INSTRUMENTATION (owner defect A step 1). Shared PBR debug
// selector (android prop debug.opengoal.pbr.debug), pushed by pbr_push_debug_tag() in
// background_common.cpp. Mode 30 = program tag, 31 = displacement tag. This shader has no PBR
// block, so the uniform is declared plainly. If a program is ever linked without it,
// glGetUniformLocation returns -1 and glUniform1i(-1, ...) is a documented no-op.
uniform int u_pbr_debug;
uniform uint warp_sample_mode;

uniform sampler2D tex_T0;

vec4 sample_tex(vec2 coord, uint unit) {
  return texture(tex_T0, coord);
}

void main() {
  // 0x1 is tcc
  // 0x2 is decal
  // 0x4 is fog

  if (warp_sample_mode == 1u || gfx_hack_no_tex == 0) {
    vec4 T0 = sample_tex(tex_coord.xy, tex_info.x);
    if ((tex_info.y & 1u) == 0u) {
      if ((tex_info.y & 2u) == 0u) {
        // modulate + no tcc
        color.rgb = fragment_color.rgb * T0.rgb;
        color.a = fragment_color.a;
      } else {
        // decal + no tcc
        color.rgb = T0.rgb * 0.5;
        color.a = fragment_color.a;
      }
    } else {
      if ((tex_info.y & 2u) == 0u) {
        // modulate + tcc
        color = fragment_color * T0;
      } else {
        // decal + tcc
        color.rgb = T0.rgb * 0.5;
        color.a = T0.a;
      }
    }
    color *= 2.0;
  } else {
    if ((tex_info.y & 1u) == 0u) {
      if ((tex_info.y & 2u) == 0u) {
        // modulate + no tcc
        color.rgb = fragment_color.rgb;
        color.a = fragment_color.a * 2.0;
      } else {
        // decal + no tcc
        color.rgb = vec3(1);
        color.a = fragment_color.a * 2.0;
      }
    } else {
      if ((tex_info.y & 2u) == 0u) {
        // modulate + tcc
        color = fragment_color;
      } else {
        // decal + tcc
        color.rgb = vec3(0.5);
        color.a = 1.0;
      }
    }
  }
  color.rgb *= color_mult;

  if (color.a < alpha_reject) {
    discard;
  }
  if ((tex_info.y & 4u) != 0u) {
    color.xyz = mix(color.xyz, fog_color.rgb, clamp(fog_color.a * fog, 0.0, 1.0));
  }
  // ===== ROUND 22 COVERAGE TAG (see tfrag3.frag for the rationale) =====
  // generic = violet. No PBR/displacement path here yet, so mode 31 reads 0.0 by construction —
  // that is exactly the quantity being measured. color.a is NEVER touched and this sits after the
  // alpha discard and the fog mix, so the discard is unchanged and the tag arrives unblended.
  if (u_pbr_debug == 30) {
    color.rgb = vec3(0.5, 0.0, 1.0);
  } else if (u_pbr_debug >= 31 && u_pbr_debug <= 33) {
    // ROUND 24: 31 = displacement tag, 32 = maps-bearing DENOMINATOR mask, 33 = dead-zone
    // diagnostic. This program never carries PBR material maps, so it is black in all three —
    // otherwise its scene colour would be counted as mask/diagnostic signal.
    color.rgb = vec3(0.0);
  }
}
