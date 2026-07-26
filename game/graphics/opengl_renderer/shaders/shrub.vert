#version 410 core

layout (location = 0) in vec3 position_in;
layout (location = 1) in vec3 tex_coord_in;
layout (location = 2) in vec3 rgba_base;
layout (location = 3) in int time_of_day_index;
// Grecharged-mesh-consolidation: shrub finally carries a real per-vertex smooth normal (2-10-10-10,
// same encoding tfrag/tie use). It used to have none, so shrub.frag synthesized one from
// screen-space derivatives = per-triangle flat. Bound by Shrub.cpp's VAO setup.
layout (location = 4) in vec4 shrub_normal;

uniform vec4 hvdf_offset;
uniform mat4 camera;
uniform float fog_constant;
uniform float fog_min;
uniform float fog_max;
uniform int decal;
uniform vec4 cam_trans;
uniform mat4 pc_camera;
// Grecharged-foliage-wind: light breeze sway for shrubs. u_wind_strength is the horizontal
// amplitude in world units (4096 = 1 m); 0 = OFF (branch below is skipped => byte-identical stock).
// tex_T18 is a Wx1 RGBA8 LUT indexed by time_of_day_index (constant per shrub instance —
// extract_shrub assigns one palette slot per instance): 16-bit packed (minY, height) of that
// plant, dequantized with u_wind_lut_base/_scale. Anchors each plant's own base (roots stay put)
// and normalizes sway by its own height so a small bush and a tall kelp both reach full sway at
// their crowns. u_time = seconds (monotonic), drives the gust. All set from Shrub.cpp render_tree.
uniform float u_time;
uniform float u_wind_strength;
uniform float u_wind_lut_base;
uniform float u_wind_lut_scale;
// ⚠ Grecharged-pbr-realtime-fusion ROUND 22 — MOVED FROM UNIT 11 TO UNIT 18. Shader.cpp binds
// every `tex_T<i>` uniform to texture unit i, and first_tfrag_draw_setup parks the PBR material
// maps (tex_PBR_N..tex_PBR_E) on units 11-17. Now that shrub.frag has the PBR path, unit 11 is the
// NORMAL MAP: leaving the wind LUT there would have made the vertex stage texelFetch the normal
// map (garbage sway) and/or made the fragment stage sample the LUT as a normal map. 18 is free
// (probe samplers 3-7, base 0, TOD 10, PBR 11-17, DirectRenderer starts at 20). Shrub.cpp binds
// the LUT texture to GL_TEXTURE18 to match.
uniform sampler2D tex_T18; // Wx1 RGBA8 wind-anchor LUT (same Wx1 pattern as tex_T10, unit 18)
// Wx1 2D LUT instead of 1D — GLES has no sampler1D/glTexImage1D (the arm64
// device BLR'd into the NULL glTexImage1D loader slot). texelFetch on a Wx1
// sampler2D is texel-exact on desktop GL too; Shrub.cpp uploads it as a Wx1
// GL_TEXTURE_2D. Matches tfrag3.vert/the TIE shaders.
uniform sampler2D tex_T10; // note, sampled in the vertex shader on purpose.
  // Grecharged-lightprobes PLAYTEST#1 #4: probe SH now evaluated PER-PIXEL in the fragment (see .frag).

out vec4 fragment_color;
out vec3 tex_coord;
out float fogginess;
#ifdef OG_PBR
out vec3 v_fringe_rel;
// Grecharged-mesh-consolidation: the real smooth normal, handed to the fragment stage.
out vec3 v_normal;
// Grecharged-lightprobes: absolute world position (GOAL game units) for probe lookup.
out vec3 v_world;
// REOPEN 2026-07-21: raw stored TOD LUT units (pre x4 / pre rgba_base) for the baked-detail ratio.
out vec3 v_todc;
#endif

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
  vec3 wpos = position_in;
  if (u_wind_strength > 0.0) {
    // per-plant base anchor + height from the LUT (16-bit packed; texelFetch returns 0..1 per
    // channel, wl.r*65280+wl.g*255 == hi_byte*256+lo_byte exactly in fp32).
    vec4 wl = texelFetch(tex_T18, ivec2(time_of_day_index, 0), 0);
    float plant_ymin = u_wind_lut_base + (wl.r * 65280.0 + wl.g * 255.0) * u_wind_lut_scale;
    float plant_h    = (wl.b * 65280.0 + wl.a * 255.0) * u_wind_lut_scale;
    // sway weight: 0 at the plant's own base, ->1 near its crown (85% of its height, floor 0.3 m),
    // grows quadratically so roots barely move and the top rustles.
    float span = max(plant_h * 0.85, 0.3 * 4096.0);
    float h = clamp((wpos.y - plant_ymin) / span, 0.0, 1.0);
    float hw = h * h;
    // one coherent gust travelling across the field (spatial phase) + gentle time drive; two slightly
    // decorrelated axes so the sway isn't a pure line. Frequencies tuned for a light breeze.
    float ph = (wpos.x + wpos.z) * 0.00028 + u_time * 1.5;
    wpos.x += sin(ph) * u_wind_strength * hw;
    wpos.z += cos(ph * 0.8 + 1.3) * u_wind_strength * hw * 0.7;
    // fine-scale shimmer so a larger plant deforms instead of translating rigidly (phase varies
    // across ~0.4 m within one plant); small fraction of the main amplitude.
    float ph2 = wpos.x * 0.004 + wpos.y * 0.003 + u_time * 3.1;
    wpos.x += sin(ph2) * u_wind_strength * hw * 0.25;
  }
  vec3 vert = wpos - cam_trans.xyz;
#ifdef OG_PBR
  v_fringe_rel = vert * (1.0 / 4096.0);
  v_normal = shrub_normal.xyz;           // Grecharged-mesh-consolidation: real per-vertex smooth normal
  v_world = position_in;                 // Grecharged-lightprobes: world pos for PER-PIXEL probe lookup
#endif
  vec4 transformed = -pc_camera[3];
  transformed -= pc_camera[0] * vert.x;
  transformed -= pc_camera[1] * vert.y;
  transformed -= pc_camera[2] * vert.z;

  // do fog!
  fogginess = 255.0 - clamp(-transformed.w + hvdf_offset.w, fog_min, fog_max);

  // scissoring area adjust
  transformed.y *= SCISSOR_ADJUST * HEIGHT_SCALE;
  gl_Position = transformed;

  // time of day lookup
  // start with the vertex color (only rgb, VIF filled in the 255.)
  fragment_color =  vec4(rgba_base, 1);
  // get the time of day multiplier
  vec4 tod_color = texelFetch(tex_T10, ivec2(time_of_day_index, 0), 0);
#ifdef OG_PBR
  v_todc = tod_color.rgb;  // raw stored LUT units (pre x4/pre rgba_base) for the baked-detail ratio
#endif
  // combine
  fragment_color *= tod_color * 4.0;

  if (decal == 1) {
    fragment_color.xyz = vec3(1.0, 1.0, 1.0);
  }

  tex_coord = tex_coord_in;
  tex_coord.xy /= 4096.0;
}
