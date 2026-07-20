#version 410 core

layout (location = 0) in vec3 position_in;
layout (location = 1) in vec3 tex_coord_in;
layout (location = 2) in int time_of_day_index;
#ifdef OG_PBR
// Grecharged-directional-ambient ROOT-CAUSE FIX: real authored per-vertex TIE normal (world space),
// bound at location 3 by Tie3.cpp (same VAO as the base pass). Feeds the realtime-lighting smooth-
// normal path instead of the flat per-face screen-derivative normal.
layout (location = 3) in vec3 normal_in;
#endif

uniform vec4 hvdf_offset;
uniform mat4 camera;
uniform float fog_constant;
uniform float fog_min;
uniform float fog_max;
// A36: Wx1 2D LUT instead of 1D — Tie3.cpp uploads the time-of-day colors as a
// Wx1 GL_TEXTURE_2D (shared with the TFRAG3 path). texelFetch(ivec2(i,0)) is
// texel-exact on desktop GL and required on GLES (no sampler1D).
uniform sampler2D tex_T10; // note, sampled in the vertex shader on purpose.
uniform int decal;
#ifdef OG_PBR
uniform vec4 cam_trans;
#endif

out vec4 fragment_color;
out vec3 tex_coord;
out float fogginess;
#ifdef OG_PBR
out vec3 v_fringe_rel;
out vec3 v_normal;  // Grecharged-directional-ambient: smooth per-vertex world normal (root-cause fix)
#endif

void main() {
  vec4 transformed = -camera[3];
  transformed -= camera[0] * position_in.x;
  transformed -= camera[1] * position_in.y;
  transformed -= camera[2] * position_in.z;
#ifdef OG_PBR
  v_fringe_rel = (position_in - cam_trans.xyz) * (1.0 / 4096.0);
  v_normal = normal_in;  // world-space authored TIE normal (wind sways position; base normal is fine)
#endif
  float Q = fog_constant / transformed.w;

  fogginess = 255.0 - clamp(-transformed.w + hvdf_offset.w, fog_min, fog_max);

  // perspective divide!
  transformed.xyz *= Q;
  // offset
  transformed.xyz += hvdf_offset.xyz;
  // correct xy offset
  transformed.xy -= (2048.);
  // correct z scale
  transformed.z /= (8388608.0);
  transformed.z -= 1.0;
  // correct xy scale
  transformed.x /= (256.0);
  transformed.y /= -(128.0);
  // hack
  transformed.xyz *= transformed.w;
  // scissoring area adjust
  transformed.y *= SCISSOR_ADJUST * HEIGHT_SCALE;
  gl_Position = transformed;

  // time of day lookup
  fragment_color = texelFetch(tex_T10, ivec2(time_of_day_index, 0), 0);
  // color adjustment
  fragment_color *= 2.0;
  fragment_color.a *= 2.0;

  if (decal == 1) {
    // tfrag/tie always use TCC=RGB, so even with decal, alpha comes from fragment.
    fragment_color.xyz = vec3(1.0, 1.0, 1.0);
  }

  tex_coord = tex_coord_in;
}