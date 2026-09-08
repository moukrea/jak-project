#version 410 core

out vec4 color;

flat in vec4 fragment_color;
in vec3 tex_coord;
flat in uvec2 tex_info;

uniform sampler2D tex_T0;
uniform float alpha_min;
uniform float alpha_max;

void main() {
  vec4 T0 = texture(tex_T0, tex_coord.xy);
  if (tex_info.y == 0u) {
    T0.w = 1.0;
  }
  color = fragment_color * T0;

  if (color.a < alpha_min || color.a > alpha_max) {
    discard;
  }
  // Legacy texture modulation supplies normalized source colors. RGBA8 used
  // to bound these before blending; floating targets must preserve that source
  // range explicitly. The destination and additive accumulation remain HDR.
  color.rgb = clamp(color.rgb, 0.0, 1.0);
  // Alpha is a blend weight, even when RGB has floating-point HDR headroom.
  // Keep the original alpha tests above, then match the normalized target range.
  color.a = clamp(color.a, 0.0, 1.0);
}
