#version 410 core

layout (location = 0) in vec3 position_in;
layout (location = 1) in vec3 tex_coord_in;
layout (location = 2) in int time_of_day_index;
#ifdef OG_PBR
// Grecharged-directional-ambient ROOT-CAUSE FIX: real authored per-vertex TIE normal (world space),
// bound at location 3 by Tie3.cpp (same VAO as the base pass). Feeds the realtime-lighting smooth-
// normal path instead of the flat per-face screen-derivative normal.
layout (location = 3) in vec3 normal_in;
// Grecharged-pbr-realtime-fusion ROUND 22: the per-vertex MikkTSpace tangent (xyz = world tangent,
// w = handedness) was ALREADY bound at attribute location 5 on the TIE VAO (Tie3.cpp binds the
// tangent_buffer there for the whole tree, and the wind pass draws from that same VAO) — this
// shader simply never declared it, which is why the wind foliage had no tangent frame and hence no
// PBR material path. Declaring it costs nothing when PBR is off; an unbound location 5 reads
// (0,0,0,1), which the fused chunk detects as degenerate and answers with the CONTINUOUS
// normal-derived basis (never a screen-space derivative frame).
layout (location = 5) in vec4 tangent_in;
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
// Grecharged-foliage-wind2: FROND FLUTTER. Round 1 only sheared the whole instance matrix, so a
// palm translated rigidly and the owner read the scene as dead ("aucune feuille qui bouge"). Leaves
// look alive when they DEFORM, which needs a per-vertex term — this one.
// position_in here is PROTOTYPE-LOCAL (Tie3::render_tree_wind supplies the per-instance matrix in
// `camera`; TieTree::unpack leaves wind vertices untransformed), so length(position_in.xz) is a
// vertex's horizontal reach from the trunk axis. Displacing by a FRACTION of that reach means:
// exactly zero on the trunk, largest at the frond tips, and no per-prototype size data needed —
// the term is invariant to prototype units and to instance scale.
// u_fw_amp == 0.0 => toggle OFF => the block below is skipped and the stock vertex path runs.
uniform float u_fw_amp;    // flutter amplitude, as a fraction of a vertex's own reach (0 = off)
uniform float u_fw_time;   // breeze clock, seconds (frozen while the game's wind is paused)
uniform float u_fw_phase;  // per-instance phase, set with `camera` for each instance group
#ifdef OG_PBR
uniform vec4 cam_trans;
// Grecharged-lightprobes PLAYTEST#1 #4: the LOCAL probe SH is evaluated PER-PIXEL in the fragment
// shader (see tie_wind.frag rt_probe_sh) from the interpolated v_world — the old per-vertex eval
// showed the ~4 m probe-cell pattern and shimmered under tfrag/tie LOD vertex morphing.
#endif

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

void main() {
  // Grecharged-foliage-wind2: frond flutter (see the uniform block above). Only the projected
  // position uses the fluttered vertex; v_world / v_fringe_rel below stay on the authored position
  // so nothing in the PBR/probe path shifts with the breeze.
  vec3 lpos = position_in;
  if (u_fw_amp > 0.0) {
    float reach = length(position_in.xz);   // 0 on the trunk axis, max at the frond tips
    // The flutter's lever arm. `reach` alone was not safe: the offline prototype census
    // (tie-census.txt) shows jak1 wind prototypes whose geometry spreads far from their OWN
    // origin — palm-01.mb reaches 23.00 m — so `reach * amp` alone would have flung vertices
    // ~3 m sideways instead of fluttering a frond. Two bounded weights fix that:
    //   * the reach is capped at 4 m, which is a real palm frond and clamps only the outliers;
    //   * hw ramps in with height above the prototype's own base (both palm protos have
    //     ylo = 0.0, so position_in.y IS that height), so roots hold still and only the crown
    //     flutters.
    // hw also fails SAFE: a prototype whose geometry hangs BELOW its origin (jak1's
    // vil1-fish-01.mb, ylo = -32192) gets hw = 0 and no flutter at all, which keeps this term
    // out of geometry it was never designed for. Peak displacement is therefore bounded at
    // 4 m * u_fw_amp regardless of what the level data contains.
    float hw = clamp(position_in.y / (8.0 * 4096.0), 0.0, 1.0);
    float lever = min(reach, 4.0 * 4096.0) * hw;
    float ph = u_fw_phase;
    // two incommensurate rates: a ~0.37 Hz frond bend plus a ~0.59 Hz ripple. The reach term inside
    // the phase makes the wave travel OUT along a frond instead of moving it as a rigid stick.
    float f1 = sin(u_fw_time * 2.30 + ph + reach * 0.00035);
    float f2 = sin(u_fw_time * 3.71 + ph * 1.7 + 2.1);
    float bend = u_fw_amp * (0.70 * f1 + 0.30 * f2);
    float cross = u_fw_amp * 0.55 * sin(u_fw_time * 2.93 + ph * 1.3 + 1.1);
    lpos.x += lever * bend;
    lpos.z += lever * cross;
    // tips dip slightly as they bend (a frond swept sideways also droops) — keeps the crown from
    // reading as a flat disc spinning in place. Always <= 0 so leaves never pop upward.
    lpos.y -= lever * u_fw_amp * 0.35 * (0.5 + 0.5 * f1);
  }
  vec4 transformed = -camera[3];
  transformed -= camera[0] * lpos.x;
  transformed -= camera[1] * lpos.y;
  transformed -= camera[2] * lpos.z;
#ifdef OG_PBR
  v_fringe_rel = (position_in - cam_trans.xyz) * (1.0 / 4096.0);
  v_world = position_in;                 // Grecharged-lightprobes: world pos for PER-PIXEL probe lookup
  v_normal = normal_in;  // world-space authored TIE normal (wind sways position; base normal is fine)
  v_tangent = tangent_in;  // ROUND 22: continuous per-vertex tangent for the fused PBR TBN
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