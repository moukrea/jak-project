#version 410 core

layout (location = 0) in vec3 position_in;
layout (location = 1) in vec3 tex_coord_in;
layout (location = 2) in int time_of_day_index;
// Grecharged-directional-ambient ROOT-CAUSE FIX: smooth per-vertex WORLD normal, reconstructed at
// load (angle/area-weighted, position-welded) into the 2-10-10-10 nor attribute. Replaces the flat
// per-face screen-derivative normal so curved geometry regains relief in shadow. Inert unless the
// realtime-lighting frag path reads v_normal (stock path ignores it => byte-identical).
layout (location = 3) in vec3 normal_in;
// Grecharged-pbr-realtime-fusion REOPEN#7 FOUNDATION FIX: per-vertex MikkTSpace tangent
// (xyz = world-space tangent, w = +/-1 handedness), reconstructed at load in TfragTree/TieTree
// ::unpack() and uploaded to attribute location 5 (free on both the tfrag and tie VAOs). Lets the
// PBR fragment build a CONTINUOUS TBN from an interpolated vertex tangent instead of screen-space
// derivatives (dFdx/dFdy), which were discontinuous at triangle edges/UV seams => incoherent relief
// + hard-contrast cracks at relief>0. Inert unless the PBR frag path reads v_tangent; an unbound
// location 5 reads the default (0,0,0,1), which the frag detects as degenerate => derivative fallback.
layout (location = 5) in vec4 tangent_in;
// Grecharged-foliage-wind3 (defaut D2) : le balancement du TIE statique. Ce shader sert AUSSI au
// terrain TFRAG et au shrub ; c'est `first_tfrag_draw_setup` qui remet `u_tie_sway_amp` a 0 pour
// tout le monde, et Tie3 qui le releve sur ses seules passes. Voir le chunk pour les deux verrous.
#include "tie_sway.glsl"

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

// Grecharged-lightprobes PLAYTEST#1 #4 (checkerboard): the LOCAL probe SH is now evaluated PER-PIXEL
// in the fragment shader (see tfrag3.frag rt_probe_sh) using the interpolated world position v_world.
// The old per-vertex eval + varying interpolation showed a visible ~4 m probe-cell facet pattern
// ("damier") on the flat ground; per-pixel 3D-texture sampling makes the grid blend seamless.

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
// Grecharged-pbr-realtime-fusion REOPEN#7: per-vertex tangent (xyz world tangent, w handedness) for
// the continuous PBR TBN. Interpolated across the triangle => no screen-derivative seams/cracks.
out vec4 v_tangent;
// ROUND 23: tfrag3.frag is shared with the TESSELLATED program, whose tess-eval writes the weight
// the displacement tier actually applied. This is the NON-tessellated program, so the weight is 0 —
// the varying only has to exist here for the fragment shader to link. u_pbr_tess_active is 0 for
// this program too, so the fragment gate is false either way.
out float v_tess_disp_w;

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
  // Grecharged-foliage-wind3 : balancement du TIE statique. Inerte (retourne son entree) des que
  // u_tie_sway_amp vaut 0 — ce qui est le cas de CHAQUE appelant sauf Tie3 avec l'option allumee.
  vec3 sway_pos = tie_sway_apply(position_in, tie_sway_in);
  vec3 vert = sway_pos - cam_trans.xyz;
  v_fringe_rel = vert * (1.0 / 4096.0);  // Grecharged-grass-overhang2: meters, for the fringe fade
  v_world = sway_pos;                    // Grecharged-lightprobes: world pos (game units) for PER-PIXEL probe lookup
  v_normal = normal_in;  // world-space smooth normal (tfrag verts are already in world space)
  v_tangent = tangent_in;  // REOPEN#7: per-vertex tangent -> continuous PBR TBN in the frag
  v_tess_disp_w = 0.0;     // ROUND 23: non-tessellated program => the tess tier displaced nothing
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
