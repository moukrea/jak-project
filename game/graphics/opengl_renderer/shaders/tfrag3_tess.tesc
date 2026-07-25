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
// PBR POLISH — OWNER PLAYTEST #18 ("la tessellation manque de relief EN PARTICULIER AU SOL"):
// the TARGET SIZE, in METRES, of one generated segment in the near field. The level law below is
// driven by it (see tess_seg_target_m). C++-side default 0.06 m, live-tunable with
// debug.opengoal.pbr.tessseg / OG_PBR_TESSSEG so the density can be dialled per device class with
// no rebuild — larger = coarser = cheaper. <= 0 falls back to the compiled default.
uniform float u_pbr_tess_seg;
// The same bisect word tfrag3.frag/.tese declare (already pushed on this program by
// first_tfrag_draw_setup). Bit 16777216 = revert to the legacy DISTANCE-ONLY level law, so the
// world-space-edge-length law below is a live same-vantage A/B with one setprop.
uniform int u_pbr_bisect;
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

// ===============================================================================================
// PBR POLISH — OWNER PLAYTEST #18: "la tessellation manque toujours de relief EN PARTICULIER AU SOL".
//
// ROOT CAUSE: every law shipped so far was a function of DISTANCE ALONE (the #17 one being
// level = clamp(128/dist_m, 1, cap)). But the quantity that decides whether surface relief is
// resolvable is not the level, it is the SEGMENT SIZE that level produces — (patch edge / level) —
// and that also depends on the patch's SIZE, which a distance-only law cannot see. tfrag GROUND
// patches are substantially bigger than wall patches, so they came out coarser at the same
// distance. Measured on village1 at the owner's own vantage
// (tools/tess_audit --cam-m -111.98 43.96 204.99, cap 64): GROUND patches within 5 m have MEAN edge
// 3.05 m / p90 4.64 m against 2.11 m / 3.45 m for WALL. Under the old law the ground therefore got
// generated vertices 9.68 cm apart (p90 15.5 cm) and degraded to 13.14 cm at 5-10 m and 25.14 cm at
// 10-20 m — 2-5x coarser than the cm-scale features in the height maps, and 2-3x coarser than the
// walls the owner was NOT complaining about. That is why the GROUND specifically still read flat.
//
// THE FIX is the industry-standard WORLD-SPACE EDGE-LENGTH law: ask each edge how many segments it
// needs to hit a TARGET SEGMENT SIZE. A huge ground edge is then subdivided far more than a small
// wall edge at the same distance, and the generated vertex density becomes a property of the WORLD
// rather than of the authoring. Measured effect on the GROUND at that vantage (tess_audit, cap 64):
// mean segment 0-5 m 9.68 -> 5.60 cm, 5-10 m 13.14 -> 8.59 cm, 10-20 m 25.14 -> 16.06 cm; the p90
// tightens harder still (15.49 -> 6.74, 23.94 -> 10.50, 45.80 -> 19.82 cm) because the law now
// targets the segment size directly instead of hoping a distance heuristic lands on it.
//
// PERF BUDGET — the owner's "+ perf budget", three parts:
//   (a) DISTANCE LOD: the target segment size grows linearly with distance past TESS_SEG_D0_M, so
//       the near field gets the budget and the middle distance is not subdivided below a pixel.
//   (b) AMPLITUDE-MATCHED DENSITY FADE: tfrag3_tess.tese fades the displacement amplitude to
//       EXACTLY zero between 20 and 30 m, so vertices generated there are displaced by nothing.
//       The level now fades on the SAME curve, removing that pure waste (measured: 221,200 of the
//       2,146,176 whole-level generated triangles at cap 64 sat in the 20-30 m band).
//   (c) the two live knobs: the driver-clamped ceiling u_pbr_tess_max and u_pbr_tess_seg itself.
//
// SEAM-SAFE, by the same argument as before and still exactly: the level of an edge is a function of
// that edge's two ENDPOINTS ONLY (its length and its midpoint distance) — never of the third vertex,
// never of the patch. mesh_consolidate() has made those two endpoints bit-identical for the two
// patches sharing the edge, length(b-a) == length(a-b) exactly (negation and squaring are exact in
// IEEE) and 0.5*(a+b) == 0.5*(b+a) exactly (float addition is commutative), so both patches still
// compute the SAME level for the shared edge and it still cannot tear.
// ===============================================================================================
#define TESS_SEG_NEAR_M 0.06  // compiled default target segment size (u_pbr_tess_seg overrides)
#define TESS_SEG_D0_M 5.0     // full near-field density out to here, then LOD
#define TESS_SEG_FAR_M 0.60   // ceiling on the target (the 30 m far gate ends tess anyway)
#define TESS_FADE_LO_M 20.0   // MUST match tfrag3_tess.tese's displacement amplitude fade
#define TESS_FADE_HI_M 30.0
#define TESS_K 128.0          // legacy distance-only law, bisect bit 16777216 only

// Target segment size in metres at camera distance d. Pure function of d => seam-safe.
// MUST stay identical to tfrag3_tess.tese's copy (the tese derives its height-map band-limit from
// it, and that band-limit has to be bit-identical on both sides of a welded seam).
float tess_seg_target_m(float d) {
  float near_m = TESS_SEG_NEAR_M;
#ifdef OG_PBR
  if (u_pbr_tess_seg > 0.0) {
    near_m = u_pbr_tess_seg;
  }
#endif
  return clamp(near_m * max(d, TESS_SEG_D0_M) * (1.0 / TESS_SEG_D0_M), near_m,
               max(TESS_SEG_FAR_M, near_m));
}

float edge_level(vec3 a, vec3 b) {
  float d = cam_dist_m(0.5 * (a + b));
#ifdef OG_PBR
  float cap = max(u_pbr_tess_max, 1.0);
  if ((u_pbr_bisect & 16777216) != 0) {
    return clamp(TESS_K / max(d, 0.5), 1.0, cap);  // legacy distance-only law (live A/B)
  }
#else
  float cap = 12.0;
#endif
  // world-space edge length (game units -> metres) over the target segment size.
  float lvl = (length(b - a) * (1.0 / 4096.0)) / tess_seg_target_m(d);
  // (b) density fades with the displacement amplitude it exists to carry.
  lvl = mix(1.0, lvl, 1.0 - smoothstep(TESS_FADE_LO_M, TESS_FADE_HI_M, d));
  return clamp(lvl, 1.0, cap);
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
