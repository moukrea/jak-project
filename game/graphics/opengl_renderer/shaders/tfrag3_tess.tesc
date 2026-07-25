#version 410 core

// REOPEN #3 TESSELLATION displacement — tessellation CONTROL stage.
// Triangle patches (the flat triangle-list index stream TFragment.cpp builds for GL_PATCHES).
// Emits a per-edge tessellation level driven by the edge-midpoint camera distance, in the SAME
// camera-relative meters convention tfrag3.vert uses for v_fringe_rel:
//     v_fringe_rel = (position_in - cam_trans.xyz) / 4096.0
// so distances here match u_rt_shadow_range (~150 = far). Near geometry is subdivided (up to 12),
// far geometry passes through at level 1. The whole patch passes through (level 1) when it is
// beyond 30 m OR the displacement mode is not Tessellation (u_pbr_displacement != 2).

layout (vertices = 3) out;

uniform vec4 cam_trans;
#ifdef OG_PBR
uniform int u_pbr_displacement;  // 0 Off, 1 Parallax, 2 Tessellation
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

// per-edge level from the edge MIDPOINT distance: 12 near (<= 8 m) -> 1 far (>= 30 m).
float edge_level(vec3 a, vec3 b) {
  float d = cam_dist_m(0.5 * (a + b));
  return mix(12.0, 1.0, clamp((d - 8.0) / 22.0, 0.0, 1.0));
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
