#version 410 core

layout (location = 0) in vec3 position_in;
layout (location = 1) in vec3 tex_coord_in;
layout (location = 2) in int time_of_day_index;
#ifdef OG_PBR
// Grecharged-directional-ambient ROOT-CAUSE FIX: real authored per-vertex TIE normal (world space),
// already packed into the 2-10-10-10 nor attribute and bound at location 3 by Tie3.cpp. Feeds the
// realtime-lighting smooth-normal path instead of the flat per-face screen-derivative normal.
layout (location = 3) in vec3 normal_in;
// Grecharged-pbr-realtime-fusion ROUND 22: the per-vertex MikkTSpace tangent (xyz = world tangent,
// w = handedness) was ALREADY bound at attribute location 5 on the TIE VAO (Tie3.cpp binds the
// tangent_buffer there for the whole tree, and the envmap base pass draws from that same VAO) —
// this shader simply never declared it, which is why envmapped TIE had no tangent frame and hence
// no PBR material path. Declaring it costs nothing when PBR is off; an unbound location 5 reads
// (0,0,0,1), which the fused chunk detects as degenerate and answers with the CONTINUOUS
// normal-derived basis (never a screen-space derivative frame).
layout (location = 5) in vec4 tangent_in;
#endif
// Grecharged-foliage-wind3 (defaut D2) : le balancement du TIE statique, meme chunk que
// tfrag3.vert et etie.vert — les trois doivent deplacer un sommet DE FACON IDENTIQUE, sinon la
// passe de base et la passe additive de reflet du meme objet se decolleraient.
#include "tie_sway.glsl"

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
out vec3 v_normal;  // Grecharged-directional-ambient: smooth per-vertex world normal (root-cause fix)
// ROUND 22: per-vertex tangent -> the continuous PBR TBN in the fragment (mirrors tfrag3.vert).
out vec4 v_tangent;
#endif

// etie stuff
uniform vec4 persp0;
uniform vec4 persp1;
uniform mat4 cam_no_persp;
#ifdef OG_PBR
uniform vec4 cam_trans;
// Grecharged-lightprobes PLAYTEST#1 #4: the LOCAL probe SH is evaluated PER-PIXEL in the fragment
// shader (see etie_base.frag rt_probe_sh) from the interpolated v_world — the old per-vertex eval
// showed the ~4 m probe-cell pattern and shimmered under tfrag/tie LOD vertex morphing.
#endif

void main() {
  // Grecharged-foliage-wind3 : inerte (retourne son entree) quand u_tie_sway_amp vaut 0.
  vec3 position_sway = tie_sway_apply(position_in, tie_sway_in);
  float fog1 = camera[3].w + camera[0].w * position_sway.x + camera[1].w * position_sway.y + camera[2].w * position_sway.z;
  fogginess = 255.0 - clamp(fog1 + hvdf_offset.w, fog_min, fog_max);
  vec4 vf17 = cam_no_persp[3];
  vf17 += cam_no_persp[0] * position_sway.x;
  vf17 += cam_no_persp[1] * position_sway.y;
  vf17 += cam_no_persp[2] * position_sway.z;
#ifdef OG_PBR
  v_fringe_rel = (position_sway - cam_trans.xyz) * (1.0 / 4096.0);
  v_world = position_sway;               // Grecharged-lightprobes: world pos for PER-PIXEL probe lookup
  v_normal = normal_in;  // world-space authored TIE normal (already rotated by the instance matrix)
  v_tangent = tangent_in;  // ROUND 22: continuous per-vertex tangent for the fused PBR TBN
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
