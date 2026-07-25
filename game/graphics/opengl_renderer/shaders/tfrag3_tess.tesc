#version 410 core

// REOPEN #3 TESSELLATION displacement — tessellation CONTROL stage.
// Triangle patches (the flat triangle-list index stream TFragment.cpp builds for GL_PATCHES).
// Emits a per-edge tessellation level driven by the edge-midpoint camera distance, in the SAME
// camera-relative meters convention tfrag3.vert uses for v_fringe_rel:
//     v_fringe_rel = (position_in - cam_trans.xyz) / 4096.0
// so distances here match u_rt_shadow_range (~150 = far). Near geometry is subdivided (up to
// u_pbr_tess_max, default 32), far geometry passes through at level 1. The whole patch passes
// through (level 1) when it is beyond 30 m OR the displacement mode is not Tessellation
// (u_pbr_displacement != 2).

layout (vertices = 3) out;

uniform vec4 cam_trans;
#ifdef OG_PBR
uniform int u_pbr_displacement;  // 0 Off, 1 Parallax, 2 Tessellation
// PBR POLISH (owner playtest #17: "la tessellation manque de détail et ne donne pas vraiment de
// profondeur"). Ceiling of the level law below, C++-side default 32, overridable live with
// debug.opengoal.pbr.tessmax / OG_PBR_TESSMAX, and clamped to the driver's actual
// GL_MAX_TESS_GEN_LEVEL before it is pushed — so a driver that allows less can never be asked
// for more, and the owner's Honor can be dialled independently of the low-end test device.
uniform float u_pbr_tess_max;
#endif

in vec3 tv_world[];
in vec3 tv_texcoord[];
in vec3 tv_normal[];
in vec4 tv_color[];
in vec4 tv_tangent[];
in float tv_seam[];

out vec3 tc_world[];
out vec3 tc_texcoord[];
out vec3 tc_normal[];
out vec4 tc_color[];
out vec4 tc_tangent[];
out float tc_seam[];

// camera-relative distance in meters (same units as v_fringe_rel / u_rt_shadow_range).
float cam_dist_m(vec3 wp) {
  return length((wp - cam_trans.xyz) * (1.0 / 4096.0));
}

// PBR POLISH — OWNER PLAYTEST #17: "la tessellation manque de détail".
// The shipped law was a LINEAR ramp from level 12 at 8 m down to 1 at 30 m. Two things were wrong
// with it. (a) The ceiling of 12 is simply low: measured on village1's real geometry (median tfrag
// patch edge 2.18 m, tools/tess_audit), level 12 puts the generated vertices ~18 cm apart, which
// cannot resolve surface relief. (b) A linear ramp spends most of its budget in the MIDDLE
// distance, where perspective has already shrunk the detail below a pixel, and starves the near
// field, which is the only place relief is visible at all.
// This is the standard screen-space-constant-detail law instead: level ~ 1/distance, so a patch
// subtends roughly the same number of generated triangles on screen wherever it is. TESS_K sets
// that density (128 => level 32 at 4 m, 16 at 8 m, 8 at 16 m, 4 at 32 m), the ceiling is the
// driver-clamped u_pbr_tess_max, and the near field gets the budget the middle distance no longer
// wastes. Measured on village1 at a mid-level vantage: mean achieved inner level within 10 m goes
// 11.72 -> 19.54, generated triangles there 176,869 -> 497,789.
// SEAM-SAFE, unchanged: the level of an edge is still a function of that edge's MIDPOINT only, so
// the two patches sharing a welded edge still compute the SAME level for it and still subdivide it
// identically — the shared edge cannot tear.
#define TESS_K 128.0
float edge_level(vec3 a, vec3 b) {
  float d = cam_dist_m(0.5 * (a + b));
#ifdef OG_PBR
  float cap = max(u_pbr_tess_max, 1.0);
#else
  float cap = 12.0;
#endif
  return clamp(TESS_K / max(d, 0.5), 1.0, cap);
}

void main() {
  // pass-through the per-vertex attributes unchanged.
  tc_world[gl_InvocationID] = tv_world[gl_InvocationID];
  tc_texcoord[gl_InvocationID] = tv_texcoord[gl_InvocationID];
  tc_normal[gl_InvocationID] = tv_normal[gl_InvocationID];
  tc_color[gl_InvocationID] = tv_color[gl_InvocationID];
  tc_tangent[gl_InvocationID] = tv_tangent[gl_InvocationID];
  tc_seam[gl_InvocationID] = tv_seam[gl_InvocationID];

  if (gl_InvocationID == 0) {
    bool tess_on = true;
#ifdef OG_PBR
    tess_on = (u_pbr_displacement == 2);
#endif
    // whole-patch far gate: min corner distance beyond 30 m => passthrough.
    // DELIBERATELY NOT WIDENED with the level raise above: tfrag3_tess.tese fades the displacement
    // amplitude to EXACTLY ZERO between 20 m and 30 m, so any patch tessellated past 30 m is
    // subdivided only to be displaced by nothing. Measured on village1, moving this gate to 40 m
    // would have generated 99,450 extra triangles for zero pixels of difference; the whole budget
    // increase belongs in the near field, where the fade is 1.0.
    float dmin = min(min(cam_dist_m(tv_world[0]), cam_dist_m(tv_world[1])),
                     cam_dist_m(tv_world[2]));
    if (!tess_on || dmin > 30.0) {
      gl_TessLevelOuter[0] = 1.0;
      gl_TessLevelOuter[1] = 1.0;
      gl_TessLevelOuter[2] = 1.0;
      gl_TessLevelInner[0] = 1.0;
    } else {
      // OpenGL triangle convention: outer level i opposes vertex i, i.e. it is the level of the
      // edge between the OTHER two vertices. Edge opposite vertex 0 = (v1,v2), etc.
      float l0 = edge_level(tv_world[1], tv_world[2]);
      float l1 = edge_level(tv_world[2], tv_world[0]);
      float l2 = edge_level(tv_world[0], tv_world[1]);
      gl_TessLevelOuter[0] = l0;
      gl_TessLevelOuter[1] = l1;
      gl_TessLevelOuter[2] = l2;
      gl_TessLevelInner[0] = max(max(l0, l1), l2);
    }
  }
}
