#pragma once

// Grecharged-pbr-realtime-fusion, round #19 (supervisor device measurement 2026-07-25):
// OFFLINE-DETERMINISTIC PRE-SUBDIVISION of the large tfrag ground triangles.
//
// THE MEASUREMENT THAT FORCED THIS. On the Redmi, at the owner's vantage, on the GROUND band:
//     tessellation vs displacement-OFF : mean 0.77/255, 4.6% of pixels
//     parallax     vs displacement-OFF : mean 2.27/255, 14.5% of pixels
// i.e. the hardware tessellator moves the ground LESS than the parallax it was supposed to replace.
//
// WHY, exactly. The round-#18 control shader picks a level from the WORLD-SPACE EDGE LENGTH against a
// target segment size: level = edge_len_m / seg_target_m, clamped to GL_MAX_TESS_GEN_LEVEL (64 here).
// A tfrag ground patch near the camera has a mean edge of 3.05 m and a p90 of 4.64 m. So:
//   - at the shipped 6 cm target, a 4.64 m edge asks for level 77 and is CLIPPED to 64 -> 7.2 cm/segment;
//   - to reach the ~2.5 cm segment that a 5 cm height feature needs (Nyquist, v/feature >= 2), a 3 m
//     edge would need level 120 and a 4.64 m edge level 186. Both are ~2-3x above what the hardware
//     can generate from ONE patch, on ANY GPU (the GLES/GL floor and the common ceiling are both 64).
// No shader-side tuning can cross that: the ceiling is per-patch, so the only way to raise the density
// is to hand the tessellator SMALLER PATCHES. That is standard practice (mesh prep + hardware tess);
// nobody feeds a 20 m triangle to a tessellator and expects centimetre displacement out of it.
//
// WHAT THIS DOES. Recursive 1-to-4 midpoint subdivision of every tessellation-eligible tfrag triangle
// whose longest edge exceeds `max_edge_m`, with GREEN CLOSURE (a triangle with 1 or 2 over-length edges
// is split into 2 or 3 triangles instead of 4) so the result is CONFORMAL — no T-vertices, no cracks.
//
// WHY IT CANNOT REOPEN THE OWNER-VALIDATED MESH CONSOLIDATION. The split decision for an edge is a pure
// function of that edge's two endpoint POSITIONS (is it longer than the threshold?), and the midpoint is
// the exact average of those two positions. Two triangles that share an edge -- in the same draw, in
// different draws, in different trees/chunks, welded or merely coincident -- therefore take the SAME
// decision and place the midpoint at the SAME position, with no shared state and no communication. The
// consolidation runs FIRST, so coincident endpoints are already bit-identical (position snap) and carry
// identical smooth normals and seam weights; averaging identical inputs yields identical midpoints. A
// welded seam stays welded, and a seam that could not displace still cannot (seam weight interpolates
// linearly, so a pinned boundary stays pinned exactly).
//
// COST MODEL, and why this is NOT baked into the .meshweld sidecar. The sidecar carries per-vertex
// DELTAS against a fixed vertex numbering; a subdivision changes the numbering, so persisting it means
// persisting the whole new vertex array plus the whole new index buffer -- measured at ~13 MB per level
// uncompressed for village1, ~300 MB for jak1 alone. The owner deleted a 36 MB probe grid for being a
// "gouffre"; a 300 MB asset would be ten times worse. The subdivision is instead recomputed at load,
// which is legitimate BECAUSE it is a pure O(triangles) function of positions with no topology search:
// the expensive part of the consolidation (the union-find weld over 2.5 M edges, 45.8 s live) stays
// precomputed in the sidecar, and this pass is a linear expansion measured in the low hundreds of ms.
// The two are ordered consolidation-then-subdivision precisely so the sidecar's fingerprint (per-tree
// vertex and index counts) is evaluated on the ORIGINAL geometry and keeps validating unchanged.

#include <functional>
#include <string>

#include "common/common_types.h"

namespace tfrag3 {

struct Level;
struct Texture;

struct SubdivConfig {
  // Longest-edge threshold, in metres. A triangle is refined until every edge is <= this.
  // 1.6 m is chosen against the tessellation ceiling: 1.6 m / 64 = 2.5 cm, so a patch at the threshold
  // can still be driven to the 2.5 cm segment that a 5 cm height feature needs WITHOUT being clipped.
  // It is also deliberately just above half the 3.05 m mean ground edge, so the typical ground patch
  // needs ONE round (4 triangles) rather than two (16) -- the cost cliff is at the power of two.
  float max_edge_m = 1.6f;
  // Refinement rounds.
  //
  // Gprecompute-deterministic-bake (owner 2026-08-26, MEASURED on the test device, same scene
  // lvl=title, same build, only this number changed):
  //     max_rounds = 3 (the old default) : 7 700 915 tris/frame, 82,8 ms, rendered at 768x432
  //     max_rounds = 1                   :    65 318 tris/frame, 8,1-17,9 ms, at 1920x1080
  // A two-digit geometry multiplier was being applied to EVERY target with nobody asking for it,
  // and the frame budget it ate was paid back by the renderer dropping the resolution. The owner:
  // « je vois pas pourquoi la subdivision serait la solution [...] ca devrait etre une option
  // ajustable et pas un truc qui se fait automatiquement ».
  //
  // So the SHIPPED DEFAULT IS 1: one round still halves a 3.05 m mean ground edge to ~1.5 m, which
  // is the threshold the tessellator needs to stop clipping at GL_MAX_TESS_GEN_LEVEL — i.e. it keeps
  // the reason the pass exists — without the 4x/16x rounds on top. 2 and 3 remain reachable, but
  // only because someone CHOSE them (menu setting, or the debug prop/env override below).
  // 3 covers a 12.8 m edge; beyond that the patch is far enough that the shader's own 20-30 m
  // density fade has already taken the level back to 1.
  int max_rounds = 1;
  // Hard ceiling on growth, as a multiple of the level's original tfrag triangle count. A level that
  // would blow past it stops refining and says so in the stats rather than eating the frame budget.
  float budget_mult = 12.0f;
  // Skip triangles all of whose corners are seam-pinned (seam weight 0): they can never displace, so
  // subdividing them buys nothing. ~60% of village1's referenced tfrag verts are pinned.
  // SUPERVISOR 2026-07-28, round 34 measurement: this bypass skips split() entirely, so a neighbour
  // bisects a shared edge and the bypassed triangle does not -> a T-JUNCTION. That breaks
  // edge-manifoldness, drops the shell out of the exact signed-volume tier, and costs orientation
  // correctness: village1 correctly-signed vertices 93.30% with the bypass ON vs 96.99% with it OFF,
  // and with it OFF the post-subdivision topology is IDENTICAL to the pre-subdivision one. The
  // triangles it "saves" cannot displace anyway, so the only thing the bypass bought was the
  // T-junctions. Default flipped to false; OG_MESH_SUBDIV_SKIP_PINNED=1 restores the old behaviour.
  bool skip_pinned = false;
  // Bound the pass to surfaces that actually have a displacement SOURCE. A draw whose material
  // ships no <tex>_height.png can never be displaced by any tessellation level, so refining it is
  // pure cost — and on village1's near ground that is 62-77% of the surface (measured, round #18).
  // Requires the caller to supply the predicate; with no predicate every draw is eligible.
  bool require_height_map = true;
  // Restrict to one tfrag geom LOD (-1 = all three). TFragment draws exactly one geom at a time
  // (Gfx::g_global_settings.lod_tfrag), so refining the other two only costs memory and load time.
  int only_geom = -1;
  // -1 = not set by prop/env; the caller's feature gate decides. >= 0 overrides it (0 = force off).
  float forced_max_edge_m = -1.f;
  // Gprecompute-deterministic-bake: -1 = the prop/env said nothing about the ROUND COUNT, so the
  // caller's user setting (Gfx::g_global_settings.recharged_mesh_subdiv_rounds) owns it. >= 0 means
  // debug.opengoal.mesh.subdivrounds / OG_MESH_SUBDIV_ROUNDS was set and wins, for A/B work.
  int forced_max_rounds = -1;

  // --------------------------------------------------------------------------------------------
  // TIE. DEFAULT OFF, and this default is a measurement, not caution.
  //
  // TIE geometry is NEVER handed to the tessellator. Tie3.cpp binds only TFRAG3 / ETIE_BASE /
  // TIE_WIND; there is no glPatchParameteri and no GL_PATCHES anywhere in Tie3.cpp, so no TIE draw
  // can ever enter a tessellation control/evaluation stage. A device coverage dump says the same
  // thing from the other end: `renderer=tie pbr_height=10 disp_tess=0 disp_pom=10` -- ten TIE draws
  // carry a height map, zero of them are tessellated, all ten are displaced by PARALLAX OCCLUSION
  // MAPPING instead. POM is a per-PIXEL raymarch in the fragment shader: its quality is a function
  // of screen resolution and step count, NOT of triangle density. Subdividing a TIE wall therefore
  // buys exactly zero pixels of extra relief while costing vertices, index memory and load time.
  //
  // The pass exists anyway so that the day Tie3 gains a tessellation program, feeding it patches
  // small enough to matter is a one-flag change (`include_tie = true`) rather than a new round.
  bool include_tie = false;
  // Restrict the TIE pass to one TIE geom LOD (-1 = all four). Tie3 draws exactly one geom at a
  // time (Gfx::g_global_settings.lod_tie), so refining the other three only costs memory and time.
  int only_geom_tie = -1;
};

struct SubdivStats {
  bool ran = false;
  u64 trees_seen = 0;
  u64 trees_subdivided = 0;
  u64 tris_before = 0;
  u64 tris_after = 0;
  u64 verts_before = 0;
  u64 verts_after = 0;
  u64 midpoints_created = 0;
  u64 midpoints_shared = 0;  // cache hits: the second triangle of a shared edge costs no new vertex
  u64 split_1edge = 0;       // green closure, 1 marked edge -> 2 triangles
  u64 split_2edge = 0;       // green closure, 2 marked edges -> 3 triangles
  u64 split_3edge = 0;       // red, 1-to-4
  u64 skipped_pinned = 0;
  u64 draws_eligible = 0;
  u64 draws_no_height = 0;  // skipped: the material has no <tex>_height.png, so nothing to displace
  u64 tris_no_height = 0;
  u64 budget_stops = 0;
  // MUST be 0: the renderer asserts that draws tile the index buffer contiguously and in order.
  u64 invariant_failures = 0;
  u64 col_exact = 0;      // midpoint colour: both parents identical
  u64 col_reused = 0;     // midpoint colour: the tree palette already held the blend
  u64 col_appended = 0;   // midpoint colour: appended a new palette entry
  u64 col_capped = 0;     // midpoint colour: palette full, fell back to the nearer parent
  double col_resid_sum = 0;  // per-channel residual of the colour actually used vs the true average
  double col_resid_max = 0;
  u64 col_resid_n = 0;
  // edge-length census over the tessellation-eligible triangles, before and after
  u64 edges_before = 0, edges_after = 0;
  double edge_sum_before_m = 0, edge_sum_after_m = 0;
  double edge_max_before_m = 0, edge_max_after_m = 0;
  u64 edges_over_before = 0, edges_over_after = 0;  // over max_edge_m == what the ceiling would clip
  double elapsed_ms = 0;

  // ---- TIE-only counters (always 0 for tfrag) -------------------------------------------------
  // (H1) `use_strips` is SHARED with the wind draws: Tie3.cpp:216 derives tree.draw_mode from it and
  // the wind glDrawElements at Tie3.cpp:1627 uses that SAME draw_mode, while
  // instanced_wind_draws[].vertex_index_stream is a UINT32_MAX-restart-delimited STRIP stream. The
  // pass flips use_strips to false, so every wind stream of a subdivided tree must be rewritten as a
  // flat triangle list or all the wind foliage renders as garbage triangles.
  u64 wind_streams_converted = 0;  // InstancedStripDraws rewritten strip -> list
  u64 wind_tris_converted = 0;     // triangles in those rewritten streams
  // (H2) Vertices referenced by BOTH static_draws and instanced_wind_draws. MUST be 0. Wind vertices
  // live in PROTO-LOCAL space (TieTree::unpack leaves matrix_idx == -1 groups untransformed), so a
  // WORLD-space edge threshold is meaningless on them and moving one would corrupt the wind draw.
  // The pass only walks static_draws, so this is a proof obligation, not a filter -- but if a tree
  // ever does share a vertex, it is skipped entirely rather than silently corrupted.
  u64 tie_wind_static_shared_verts = 0;
  u64 trees_skipped_wind_shared = 0;

  double mean_edge_before_m() const { return edges_before ? edge_sum_before_m / edges_before : 0.0; }
  double mean_edge_after_m() const { return edges_after ? edge_sum_after_m / edges_after : 0.0; }
  double col_resid_mean() const { return col_resid_n ? col_resid_sum / col_resid_n : 0.0; }
};

// Prop `debug.opengoal.mesh.subdiv` (Android) / env `OG_MESH_SUBDIV` (desktop): the threshold in
// metres, "0" to force the pass off. Absent => forced_max_edge_m stays -1 and the caller's gate wins.
// Prop `debug.opengoal.mesh.subdivtie` / env `OG_MESH_SUBDIV_TIE`: "1"/"true" turns the TIE pass on,
// "0" forces it off. Absent => include_tie keeps its (off) default.
SubdivConfig mesh_subdiv_config_from_env();

// THE PASS. Runs AFTER the mesh consolidation (weld + orientation + smooth normals + seam weights),
// on the unpacked tfrag trees only -- tie and shrub are never handed to the tessellator. Mutates
// unpacked.vertices / unpacked.indices / unpacked.tangents, rewrites every draw's index range and
// vis-group counts in place, and converts the tree to a plain triangle list (use_strips = false).
// `tex_has_height` answers "does this texture ship a height map?" for one of lev.textures. Pass an
// empty function to treat every draw as displaceable (the offline tools do that when they have no
// texture index to consult).
// `out_tie` receives the SEPARATE statistics of the TIE pass (see SubdivConfig::include_tie); it is
// only written when cfg.include_tie is set. The TIE pass runs after the tfrag pass, on its OWN
// triangle budget and its own emitted/budget-hit counters, so it cannot perturb the tfrag result in
// any way -- with include_tie off the tfrag output is byte-for-byte what it was before TIE existed.
void mesh_presubdivide_level(Level& lev,
                             const SubdivConfig& cfg,
                             SubdivStats* out,
                             const std::function<bool(const Texture&)>& tex_has_height = {},
                             SubdivStats* out_tie = nullptr);

std::string format_subdiv_stats(const SubdivStats& s,
                                const SubdivConfig& cfg,
                                const char* system_label = "tfrag");

}  // namespace tfrag3
