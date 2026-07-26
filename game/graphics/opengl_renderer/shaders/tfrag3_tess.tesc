#version 410 core

// REOPEN #3 TESSELLATION displacement — tessellation CONTROL stage.
// Triangle patches (the flat triangle-list index stream TFragment.cpp builds for GL_PATCHES).
// Emits a per-edge tessellation level driven by the edge-midpoint camera distance, in the SAME
// camera-relative meters convention tfrag3.vert uses for v_fringe_rel:
//     v_fringe_rel = (position_in - cam_trans.xyz) / 4096.0
// so distances here match u_rt_shadow_range (~150 = far). Near geometry is subdivided (up to
// u_pbr_tess_max, C++ default 64), far geometry passes through at level 1. The whole patch passes
// through (level 1) when it is beyond 30 m OR the displacement mode is not Tessellation
// (u_pbr_displacement != 2).

layout (vertices = 3) out;

uniform vec4 cam_trans;
#ifdef OG_PBR
uniform int u_pbr_displacement;  // 0 Off, 1 Parallax, 2 Tessellation
// PBR POLISH (owner playtest #17: "la tessellation manque de détail et ne donne pas vraiment de
// profondeur"). Ceiling of the level law below, C++-side default 64, overridable live with
// debug.opengoal.pbr.tessmax / OG_PBR_TESSMAX, and clamped to the driver's actual
// GL_MAX_TESS_GEN_LEVEL before it is pushed — so a driver that allows less can never be asked
// for more, and the owner's Honor can be dialled independently of the low-end test device.
uniform float u_pbr_tess_max;
// PBR POLISH — OWNER PLAYTEST #18 ("la tessellation manque de relief EN PARTICULIER AU SOL"):
// the TARGET SIZE, in METRES, of one generated segment in the near field. The level law below is
// driven by it (see tess_seg_target_m). C++-side default 0.025 m, live-tunable with
// debug.opengoal.pbr.tessseg / OG_PBR_TESSSEG so the density can be dialled per device class with
// no rebuild — larger = coarser = cheaper. <= 0 falls back to the compiled default.
uniform float u_pbr_tess_seg;
// The same bisect word tfrag3.frag/.tese declare (already pushed on this program by
// first_tfrag_draw_setup). Bit 16777216 = revert to the legacy DISTANCE-ONLY level law, so the
// world-space-edge-length law below is a live same-vantage A/B with one setprop.
uniform int u_pbr_bisect;
// ===== ROUND 28 — THE DENSITY LAW CAN FINALLY SEE HOW BIG THE FEATURES ARE =====================
// Until now this stage knew NEITHER of these two, while tfrag3_tess.tese used BOTH to size the
// displacement AMPLITUDE. Density was feature-blind while amplitude was not, and that single
// asymmetry is the round-27 root cause: the law targeted a fixed segment size in METRES, so a
// material whose features are 4 cm across and one whose features are 185 cm across were sampled at
// the same spacing — the first ~2x under Nyquist (aliasing, i.e. the owner's rounded/inverted
// checker squares) and the second ~37x over it (triangles spent on detail no one can see).
//   u_pbr_height_lambda : the height map's characteristic feature wavelength, in TILES, MEASURED at
//                         load time from the map itself (LoaderStages.cpp:measure_height_lambda_tiles).
//   u_pbr_uv_per_m      : this draw's authored UV density, tiles per world metre, MEASURED from the
//                         index buffer (background_common.cpp:measure_uv_density_tfrag).
// Nothing below is tabulated per material and nothing has to be: both numbers are measured, so the
// 200th map the owner drops in is handled on exactly the same code path as the 7 that exist today.
// Both are already pushed on the TFRAG3_TESS program object per draw (PbrDrawBinder::set) — uniforms
// are program-scope, not stage-scope, so consuming them here needs no new C++ at all.
uniform float u_pbr_height_lambda;
uniform float u_pbr_uv_per_m;
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
// COMPILED FALLBACK ONLY: C++ always pushes u_pbr_tess_seg (default 0.025 m), so this value is
// dead on every shipping path. Round 27's arithmetic was done against it by mistake — the shipped
// near-field target is 2.5 cm, not 6 cm.
#define TESS_SEG_NEAR_M 0.06
#define TESS_SEG_D0_M 5.0     // full near-field density out to here, then LOD
#define TESS_SEG_FAR_M 0.60   // ceiling on the target (the 30 m far gate ends tess anyway)
// ROUND 24 — THE DISTANCE LOD WAS THE LARGEST NAMED DEAD ZONE. Measured at the owner's vantage
// with the round-24 effect metric: of the maps-bearing pixels that did NOT change when displacement
// was switched off, 77% sat beyond 30 m (mean 34.8 m) — i.e. the dead zone was this fade and the
// 30 m whole-patch gate below, exactly the "cap d'amplitude dépendant de la distance" the round-24
// mandate lists as a prime suspect. The gate existed only because the amplitude fade zeroed the
// displacement past 30 m, so subdividing there bought nothing; it is NOT a cost argument, because
// the segment-size law already collapses far levels on its own (target segment grows as d^1.5, so
// a pre-subdivided 1.6 m edge at 40 m asks for level ~3, ~9 triangles, against 400-2100 in the
// near field). MEASURED with tools/tess_audit at the owner's vantage: moving the fade from 20-30 m
// to 45-70 m costs +4.9% generated triangles level-wide (4,379,212 -> 4,592,604).
#define TESS_FADE_LO_M 40.0   // MUST match tfrag3_tess.tese's displacement amplitude fade
#define TESS_FADE_HI_M 60.0
#define TESS_K 128.0          // legacy distance-only law, bisect bit 16777216 only
// ROUND #19: the LOD ramp past D0 is SUPERLINEAR. With the pre-subdivided ground the near-field
// target drops to ~2.5 cm, and a LINEAR ramp then holds the 10-20 m band at ~6 cm -- still
// sub-Nyquist for a 5 cm feature, so it buys no relief, while generating more triangles than the
// entire near field does. Apparent feature size falls as 1/d and so does what the height mip can
// carry, so the target is allowed to grow faster than distance. Measured at the owner's vantage,
// exponent 1.5 cuts the 5-20 m generated-triangle count ~3x and leaves the <5 m band untouched.
// Compile-time on purpose: it MUST be the same number in the .tesc and the .tese, and it is not a
// knob the player has any use for (the tier knob is u_pbr_tess_seg).
#define TESS_SEG_EXP 1.5

// ===== ROUND 28 CONSTANTS =====================================================================
// TESS_SEG_PER_FEATURE: how many generated segments one height FEATURE gets. Nyquist (2) is only
// enough to not MISS the feature; reproducing the flat top of a STEP takes several samples inside
// the square plus samples either side of the discontinuity, so the target is 8.
#define TESS_SEG_PER_FEATURE 8.0
// The feature-derived target is BOUNDED relative to the near-field knob u_pbr_tess_seg (C++ 0.025 m)
// so this law can never run away in either direction: at most 2x finer than the shipped target
// (that is the triangle budget) and at most 4x coarser (that is the quality floor). Both bounds are
// relative to the knob, so raising u_pbr_tess_seg still scales the whole tier as before.
#define TESS_SEG_FEAT_MIN 0.5
#define TESS_SEG_FEAT_MAX 4.0
// ===== ROUND 28 — NEVER GENERATE VERTICES FOR A FIELD THEY CANNOT CARRY ========================
// Once the BEST spacing this edge can achieve (its length over the level ceiling) is still coarser
// than the material's feature wavelength, the extra levels buy exactly nothing: tfrag3_tess.tese
// band-limits the height to the vertex spacing, so those vertices are displaced by ~the field's
// local mean. Worse, before the band-limit was made cap-aware they were displaced by ALIASED
// samples, which is antiphase — the roof where "le noir sort plus que le blanc". So below
// TESS_SPF_RELEASE achievable segments per feature the level eases back to 1 and the POM tier
// carries that scale instead (at the SAME amplitude — see the amplitude proof in the .tese).
// This is what pays for the near-field density above: the mid-distance bands were generating
// millions of triangles to displace them by nothing.
#define TESS_SPF_RELEASE 1.5
#define TESS_SPF_KEEP 2.5

#ifdef OG_PBR
// The material's characteristic height-map feature wavelength, in METRES. Both inputs are measured
// (see the uniform block); the clamps are only sanity rails on a missing/garbage map, and the
// identity defaults the C++ pushes when a draw has no material (lambda 0.25 tiles, 0.5 tiles/m)
// land on 0.5 m, i.e. a coarse target — the safe direction for a draw that will not be displaced.
float tess_lambda_world_m() {
  return clamp(u_pbr_height_lambda, 0.002, 1.0) / max(u_pbr_uv_per_m, 1e-3);
}
#endif

// Target segment size in metres at camera distance d. Pure function of d AND OF PER-DRAW UNIFORMS,
// never of the patch => still seam-safe (see edge_level).
// MUST stay identical to tfrag3_tess.tese's copy (the tese derives its height-map band-limit from
// it, and that band-limit has to be bit-identical on both sides of a welded seam).
float tess_seg_target_m(float d) {
  float near_m = TESS_SEG_NEAR_M;
#ifdef OG_PBR
  if (u_pbr_tess_seg > 0.0) {
    near_m = u_pbr_tess_seg;
  }
  // ROUND 28: the near-field target is now SEGMENTS PER FEATURE, bounded by the budget rails.
  // Bisect bit 1 = the round-27 feature-blind absolute target back, for a one-setprop A/B.
  if ((u_pbr_bisect & 1) == 0) {
    near_m = clamp(tess_lambda_world_m() * (1.0 / TESS_SEG_PER_FEATURE),
                   near_m * TESS_SEG_FEAT_MIN, near_m * TESS_SEG_FEAT_MAX);
  }
#endif
  return clamp(near_m * pow(max(d, TESS_SEG_D0_M) * (1.0 / TESS_SEG_D0_M), TESS_SEG_EXP), near_m,
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
  float len_m = length(b - a) * (1.0 / 4096.0);
  float lvl = len_m / tess_seg_target_m(d);
  // (b) density fades with the displacement amplitude it exists to carry.
  lvl = mix(1.0, lvl, 1.0 - smoothstep(TESS_FADE_LO_M, TESS_FADE_HI_M, d));
  lvl = clamp(lvl, 1.0, cap);
#ifdef OG_PBR
  // ROUND 28 RELEASE RAMP — see the TESS_SPF_RELEASE block. spf is the segments-per-feature this
  // edge ACTUALLY achieves after the ceiling and the distance fade have had their say; below the
  // release threshold the geometry provably cannot carry the field, so the level eases back to 1
  // and tfrag3.frag's POM tier picks the scale up at the identical amplitude.
  // STILL SEAM-SAFE, by exactly the argument above and unchanged by this round: len_m, d, lvl and
  // therefore spf are functions of THIS EDGE'S TWO ENDPOINTS ONLY (plus per-draw uniforms, equal on
  // both patches of a shared edge) — never of the third vertex and never of the patch. Negation and
  // squaring are exact in IEEE so length(b-a) == length(a-b), and float addition is commutative so
  // 0.5*(a+b) == 0.5*(b+a): the two patches sharing an edge still compute the same level, bit for
  // bit, and it still cannot tear.
  if ((u_pbr_bisect & 1) == 0) {
    float spf = tess_lambda_world_m() * lvl / max(len_m, 1e-6);
    lvl = mix(1.0, lvl, smoothstep(TESS_SPF_RELEASE, TESS_SPF_KEEP, spf));
  }
#endif
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
    if (!tess_on || dmin > TESS_FADE_HI_M) {
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
