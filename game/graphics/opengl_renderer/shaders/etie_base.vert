#version 410 core

layout (location = 0) in vec3 position_in;
layout (location = 1) in vec3 tex_coord_in;
layout (location = 2) in int time_of_day_index;
#ifdef OG_PBR
// Grecharged-directional-ambient ROOT-CAUSE FIX: real authored per-vertex TIE normal (world space),
// already packed into the 2-10-10-10 nor attribute and bound at location 3 by Tie3.cpp. Feeds the
// realtime-lighting smooth-normal path instead of the flat per-face screen-derivative normal.
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

out vec4 fragment_color;
out vec3 tex_coord;
out float fogginess;
#ifdef OG_PBR
out vec3 v_fringe_rel;
// Grecharged-lightprobes: absolute world position (GOAL game units) for probe lookup.
out vec3 v_world;
out vec3 v_probe_amb;
out float v_probe_w;
out vec3 v_normal;  // Grecharged-directional-ambient: smooth per-vertex world normal (root-cause fix)
#endif

// etie stuff
uniform vec4 persp0;
uniform vec4 persp1;
uniform mat4 cam_no_persp;
#ifdef OG_PBR
uniform vec4 cam_trans;
// Grecharged-lightprobes: LOCAL probe grid, evaluated PER-VERTEX (SH ambient is low-frequency, so a
// per-vertex eval + interpolation is visually equivalent to per-pixel but ~100x cheaper on Adreno).
uniform int u_rt_probe_on;
uniform int u_rt_probe_quality;
uniform vec3 u_rt_probe_origin;
uniform float u_rt_probe_inv_cell;
uniform vec3 u_rt_probe_dims;
uniform float u_rt_probe_range;
uniform sampler3D u_rt_probe_dc;
uniform sampler3D u_rt_probe_l1a;
uniform sampler3D u_rt_probe_l1b;
uniform sampler3D u_rt_probe_l1c;
vec3 rt_probe_sh(vec3 wp, vec3 N, out float w) {
  vec3 uvw = (wp - u_rt_probe_origin) * u_rt_probe_inv_cell / u_rt_probe_dims;
  if (any(lessThan(uvw, vec3(0.0))) || any(greaterThan(uvw, vec3(1.0)))) { w = 0.0; return vec3(0.0); }
  vec4 dc = texture(u_rt_probe_dc, uvw);
  w = dc.a;
  if (w < 0.02) return vec3(0.0);
  float R = u_rt_probe_range;
  vec3 amb = (dc.rgb * R) * 0.282095;
  if (u_rt_probe_quality >= 1) {
    vec3 c1 = (texture(u_rt_probe_l1a, uvw).rgb - 0.5) * R;
    vec3 c2 = (texture(u_rt_probe_l1b, uvw).rgb - 0.5) * R;
    vec3 c3 = (texture(u_rt_probe_l1c, uvw).rgb - 0.5) * R;
    amb += c1 * (0.488603 * N.y) + c2 * (0.488603 * N.z) + c3 * (0.488603 * N.x);
  }
  return max(amb, vec3(0.0));
}
#endif

void main() {
  float fog1 = camera[3].w + camera[0].w * position_in.x + camera[1].w * position_in.y + camera[2].w * position_in.z;
  fogginess = 255.0 - clamp(fog1 + hvdf_offset.w, fog_min, fog_max);
  vec4 vf17 = cam_no_persp[3];
  vf17 += cam_no_persp[0] * position_in.x;
  vf17 += cam_no_persp[1] * position_in.y;
  vf17 += cam_no_persp[2] * position_in.z;
#ifdef OG_PBR
  v_fringe_rel = (position_in - cam_trans.xyz) * (1.0 / 4096.0);
  v_world = position_in;                 // Grecharged-lightprobes: world pos for probe lookup
  v_probe_w = 0.0;
  v_probe_amb = vec3(0.0);
  if (u_rt_probe_on != 0) {
    v_probe_amb = rt_probe_sh(position_in, normal_in, v_probe_w);
  }
  v_normal = normal_in;  // world-space authored TIE normal (already rotated by the instance matrix)
#endif
  vec4 p_proj = vec4(persp1.x * vf17.x, persp1.y * vf17.y, persp1.z, persp1.w);
  p_proj += persp0 * vf17.z;

  float pQ = 1.f / p_proj.w;
  vec4 transformed = p_proj * pQ;
  transformed.w = p_proj.w;

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



  if (decal == 1) {
    fragment_color = vec4(1.0, 1.0, 1.0, 1.0);
  } else {
    // time of day lookup
    fragment_color = texelFetch(tex_T10, ivec2(time_of_day_index, 0), 0);
    // color adjustment
    fragment_color *= 2.0;
    fragment_color.a *= 2.0;
  }

  tex_coord = tex_coord_in;
}
