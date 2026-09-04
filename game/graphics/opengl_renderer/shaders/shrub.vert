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
// foliage-wind (owner 2026-09-03) : la brise des buissons est le MEME chunk, la MEME loi et le MEME
// attribut 7 que le TIE statique (tie_sway.glsl). L'ancienne LUT par `color_index` (tex_T18) est
// retiree : elle supposait « une entree de palette par instance » et faisait glisser un buisson
// entier quand l'hypothese tombait. Le poids arrive tout cuit par sommet, ancre sur SON instance.
// Inerte (retourne son entree) quand u_tie_sway_amp vaut 0 : `first_tfrag_draw_setup` l'y met a
// chaque activation du programme, Shrub.cpp le releve juste apres si l'option est allumee.
#include "tie_sway.glsl"
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
  // foliage-wind : balancement par la loi partagee ; inerte quand u_tie_sway_amp vaut 0.
  vec3 wpos = tie_sway_apply(position_in, tie_sway_in);
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
