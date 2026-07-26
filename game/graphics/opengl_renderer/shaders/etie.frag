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

// ROUND 22 PER-PIXEL SCREEN-COVERAGE INSTRUMENTATION (owner defect A step 1). Shared PBR debug
// selector (android prop debug.opengoal.pbr.debug), pushed by first_tfrag_draw_setup() for
// ShaderId::ETIE (Tie3::envmap_second_pass_draw). Mode 30 = program tag, 31 = displacement tag.
// This shader has no PBR block, so the uniform is declared plainly. If a program is ever linked
// without it, glGetUniformLocation returns -1 and glUniform1i(-1, ...) is a documented no-op.
uniform int u_pbr_debug;

void main() {
  // ROUND 23 coverage census: this is the envmap SECOND pass, drawn BLENDED over the etie_base
  // draw that already painted its program tag. Blending a second colour over that tag would push
  // the pixel away from every reference colour and it would be counted UNCLASSIFIED — silently
  // under-reporting etie_base. In the tag modes the pass simply stands down and lets the base
  // pass's tag through unmodified.
  if (u_pbr_debug >= 30 && u_pbr_debug <= 33) { discard; }
  if (gfx_hack_no_tex == 0) {
    //vec4 T0 = texture(tex_T0, tex_coord);
    vec4 T0 = texture(tex_T0, tex_coord.xy);
    color = fragment_color * T0;
  } else {
    color = fragment_color/2.0;
  }

  if (color.a < alpha_min || color.a > alpha_max) {
    discard;
  }

  color.rgb = mix(color.rgb, fog_color.rgb, clamp(fogginess * fog_color.a, 0.0, 1.0));
}
