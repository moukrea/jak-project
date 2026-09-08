#version 410 core

out vec4 out_color;

uniform sampler2D framebuffer_tex;

flat in vec4 fragment_color;
in vec2 tex_coord;

void main() {
  vec4 color = fragment_color;

  // correct color
  color *= 2.0;

  // correct texture coordinates
  vec2 texture_coords = vec2(tex_coord.x, (1.0f - tex_coord.y) - (1.0 - (SCISSOR_HEIGHT / 512.0)) / 2.0);

  // sample framebuffer texture
  out_color = color * texture(framebuffer_tex, texture_coords);
  // Alpha is a blend weight, even when RGB has floating-point HDR headroom.
  // Keep the original alpha tests above, then match the normalized target range.
  out_color.a = clamp(out_color.a, 0.0, 1.0);
}
