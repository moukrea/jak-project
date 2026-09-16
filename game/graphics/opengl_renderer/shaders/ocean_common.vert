#version 410 core

layout (location = 0) in vec3 position_in;
layout (location = 1) in vec4 rgba_in;
layout (location = 2) in vec3 tex_coord_in;
layout (location = 3) in uint fog_in;

out vec4 fragment_color;
out vec3 tex_coord;
out float fog;

uniform int bucket;

#include "ocean_common_pos.glsl"

void main() {
  gl_Position = ocean_common_clip(position_in);
  fragment_color = vec4(rgba_in.rgb, rgba_in.a * 2.0);
  tex_coord = tex_coord_in;
  fog = float(255u - fog_in);
  
  if (bucket == 0) {
    fragment_color.rgb *= 2.0;
  } else if (bucket == 1 || bucket == 3) {
    fragment_color *= 2.0;
  } else if (bucket == 4) {
    fragment_color.a = 0.0;
  }
}
