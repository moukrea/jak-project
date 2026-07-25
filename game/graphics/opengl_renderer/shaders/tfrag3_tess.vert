#version 410 core

// REOPEN #3 TESSELLATION displacement — pass-through vertex stage.
// This is the vertex program of the TFRAG3_TESS pipeline (tfrag3_tess.vert -> tfrag3.tesc ->
// tfrag3.tese -> tfrag3.frag). It does NO camera transform: it forwards the per-vertex data the
// tessellation-control/evaluation stages need, in WORLD space (pre-camera). The tess-evaluation
// stage (tfrag3.tese) reproduces tfrag3.vert's EXACT camera transform + fog + scissor adjust after
// barycentric interpolation and displacement, and emits the varyings the (unchanged) tfrag3.frag
// consumes: fragment_color, tex_coord, fogginess, v_fringe_rel, v_world, v_normal.

layout (location = 0) in vec3 position_in;
layout (location = 1) in vec3 tex_coord_in;
layout (location = 2) in int time_of_day_index;
layout (location = 3) in vec3 normal_in;
// REOPEN#7: per-vertex tangent threaded through tess so the TES can emit v_tangent for tfrag3.frag.
layout (location = 5) in vec4 tangent_in;
// Grecharged-mesh-consolidation: per-vertex SEAM WEIGHT, normalized u16 (1 = displace normally,
// 0 = do not displace). mesh_consolidate() zeroes it on every vertex sitting on a boundary whose two
// sides CANNOT displace identically — a material boundary (the height map is bound per DRAW, so the
// other side may have none), a tfrag<->tie junction (tie is never tessellated), a genuine open
// boundary, or a hard crease (the two sides carry different normals). Barycentric interpolation then
// drives the displacement to EXACTLY zero along such a shared edge from both sides, which is what
// closes the owner's see-through slits. Interior vertices are 1, so the relief is untouched.
layout (location = 6) in float seam_w_in;

// Same TOD LUT as tfrag3.vert — sampled here (vertex stage) exactly like the non-tess path so the
// per-vertex color is identical; the TES interpolates it barycentrically.
uniform sampler2D tex_T10;
uniform int decal;

// Pass-through varyings to the tessellation-control stage. Distinct tv_* names so they never
// collide with the frag's in-varyings (which are re-emitted by the TES under their real names).
out vec3 tv_world;    // world-space position (game units), pre-camera
out vec3 tv_texcoord; // raw tex coord (xyz to match tfrag3 tex_coord)
out vec3 tv_normal;   // world-space smooth normal
out vec4 tv_color;    // TOD LUT color (already x2 + decal handling)
out vec4 tv_tangent;  // REOPEN#7 per-vertex tangent (xyz world, w handedness)
out float tv_seam;    // Grecharged-mesh-consolidation seam weight (1 = displace, 0 = do not)

void main() {
  tv_world = position_in;
  tv_texcoord = tex_coord_in;
  tv_normal = normal_in;
  tv_tangent = tangent_in;
  tv_seam = seam_w_in;

  // time of day lookup — identical to tfrag3.vert
  vec4 c = texelFetch(tex_T10, ivec2(time_of_day_index, 0), 0);
  c *= 2.0;
  c.a *= 2.0;
  if (decal == 1) {
    c.xyz = vec3(1.0, 1.0, 1.0);
  }
  tv_color = c;
}
