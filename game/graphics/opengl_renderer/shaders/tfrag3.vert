#version 410 core

layout (location = 0) in vec3 position_in;
layout (location = 1) in vec3 tex_coord_in;
layout (location = 2) in int time_of_day_index;
// Grecharged-directional-ambient ROOT-CAUSE FIX: smooth per-vertex WORLD normal, reconstructed at
// load (angle/area-weighted, position-welded) into the 2-10-10-10 nor attribute. Replaces the flat
// per-face screen-derivative normal so curved geometry regains relief in shadow. Inert unless the
// realtime-lighting frag path reads v_normal (stock path ignores it => byte-identical).
layout (location = 3) in vec3 normal_in;

uniform vec4 hvdf_offset;
uniform vec4 cam_trans;
uniform mat4 pc_camera;
uniform mat4 camera;
uniform float fog_constant;
uniform float fog_min;
uniform float fog_max;
// A36: Wx1 2D LUT instead of 1D — GLES has no sampler1D/glTexImage1D (the
// arm64 device BLR'd into the NULL glTexImage1D loader slot). texelFetch on
// a Wx1 sampler2D is texel-exact on desktop GL too; TFragment.cpp uploads
// the time-of-day colors as GL_TEXTURE_2D (W,1) to match.
uniform sampler2D tex_T10; // note, sampled in the vertex shader on purpose.
uniform int decal;

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

out vec4 fragment_color;
out vec3 tex_coord;
out float fogginess;
out vec3 v_normal;  // Grecharged-directional-ambient: smooth per-vertex world normal (root-cause fix)
// Grecharged-grass-overhang2: camera-relative world pos in METERS (mediump-safe on GLES — GOAL units
// would overflow half-float range). The frag derives camera distance + face steepness from it for
// the grass-fringe near-fade. Costless when u_fringe_fade.x == 0 (stock path).
out vec3 v_fringe_rel;
// Grecharged-lightprobes: absolute world position (GOAL game units, 4096 = 1 m) for sampling the
// LOCAL probe grid by world position. tfrag verts are already world-space. Costless when probes off.
out vec3 v_world;
// Grecharged-lightprobes: PER-VERTEX local probe ambient (irradiance) + grid coverage; interpolated
// to the fragment. Costless when probes off (u_rt_probe_on == 0 => w stays 0 => analytic fallback).
out vec3 v_probe_amb;
out float v_probe_w;

void main() {
  // old system:
  // - load vf12
  // - itof0 vf12
  // - multiply with camera matrix (add trans)
  // - let Q = fogx / vf12.w
  // - xyz *= Q
  // - xyzw += hvdf_offset
  // - clip w.
  // - ftoi4 vf12
  // use in gs.
  // gs is 12.4 fixed point, set up with 2048.0 as the center.

  // the itof0 is done in the preprocessing step.  now we have floats.


  // Step 3, the camera transform
  vec3 vert = position_in - cam_trans.xyz;
  v_fringe_rel = vert * (1.0 / 4096.0);  // Grecharged-grass-overhang2: meters, for the fringe fade
  v_world = position_in;                 // Grecharged-lightprobes: world pos (game units) for probe lookup
  // Grecharged-lightprobes: evaluate the LOCAL probe irradiance here (per-vertex), interpolate to frags.
  v_probe_w = 0.0;
  v_probe_amb = vec3(0.0);
  if (u_rt_probe_on != 0) {
    v_probe_amb = rt_probe_sh(position_in, normal_in, v_probe_w);
  }
  v_normal = normal_in;  // world-space smooth normal (tfrag verts are already in world space)
  vec4 transformed = -pc_camera[3];
  transformed.w = 0.0;
  transformed -= pc_camera[0] * vert.x;
  transformed -= pc_camera[1] * vert.y;
  transformed -= pc_camera[2] * vert.z;

  // do fog!
  fogginess = 255.0 - clamp(-transformed.w + hvdf_offset.w, fog_min, fog_max);

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
