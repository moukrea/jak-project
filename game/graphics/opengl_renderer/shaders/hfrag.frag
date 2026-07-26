#version 410 core

out vec4 color;

in vec4 fragment_color;
in vec2 tex_coord;
in float fogginess;
uniform sampler2D tex_T0;
uniform vec4 fog_color;

uniform int gfx_hack_no_tex;

// ROUND 22 PER-PIXEL SCREEN-COVERAGE INSTRUMENTATION (owner defect A step 1). Shared PBR debug
// selector (android prop debug.opengoal.pbr.debug), pushed by pbr_push_debug_tag() in
// background_common.cpp. Mode 30 = program tag, 31 = displacement tag. This shader has no PBR
// block, so the uniform is declared plainly. If a program is ever linked without it,
// glGetUniformLocation returns -1 and glUniform1i(-1, ...) is a documented no-op.
uniform int u_pbr_debug;


void main() {
  if (gfx_hack_no_tex == 0) {
    vec4 T0 = texture(tex_T0, tex_coord);
    color = fragment_color * T0 * 2.0;
  } else {
    color = fragment_color;
  }

   color.rgb = mix(color.rgb, fog_color.rgb, clamp(fogginess * fog_color.a, 0.0, 1.0));
  // ===== ROUND 22 COVERAGE TAG (see tfrag3.frag for the rationale) =====
  // hfrag = orange. No PBR/displacement path here yet, so mode 31 reads 0.0 by construction —
  // that is exactly the quantity being measured. color.a is NEVER touched (this shader has no
  // alpha discard of its own); the tag sits after the fog mix so it arrives unblended.
  if (u_pbr_debug == 30) {
    color.rgb = vec3(1.0, 0.5, 0.0);
  } else if (u_pbr_debug >= 31 && u_pbr_debug <= 34) {
    // ROUND 24: 31 = displacement tag, 32 = maps-bearing DENOMINATOR mask, 33 = dead-zone
    // diagnostic. This program never carries PBR material maps, so it is black in all three —
    // otherwise its scene colour would be counted as mask/diagnostic signal.
    color.rgb = vec3(0.0);
  }
}
