#pragma once

// Grecharged-mesh-consolidation (owner 2026-07-24): EXHAUSTIVE, MEASURED mesh consolidation.
//
// The owner's requirement is not "fix a seam", it is "TOUT COUVRIR SANS OUBLIS" — cover every mesh of
// the game with no omissions, and be able to PROVE it with numbers. Two distinct defects were named:
//
//   (1) SOUDURES OUBLIEES (forgotten welds) — adjacent triangles whose shared edge was never welded.
//       They read as SEE-THROUGH SLITS once tessellation displaces the two sides differently, and as
//       broken shading everywhere else. "J'en ai vu plein d'autres" => coverage was incomplete.
//   (2) EFFET COUTURE (seam lines) — a visible line along chunk boundaries, present at relief 0 AND 3,
//       on grass AND sand, i.e. INDEPENDENT of the normal map. Suspects: a NORMAL discontinuity or a
//       BAKED VERTEX COLOUR discontinuity across the boundary (per-chunk baked lighting).
//
// THE NO-OMISSIONS METRIC (the point of this header): a "forgotten weld" is objectively
//   *** a COINCIDENT-BUT-UNSHARED EDGE ***
// = an edge used by exactly one triangle (an OPEN edge, by raw vertex identity) whose two endpoints
// coincide, within epsilon, with the endpoints of ANOTHER open edge belonging to a different triangle
// (possibly in a different chunk/bucket/tree/system). Geometrically it IS the same edge; topologically
// the two triangles do not share it. Every such edge is a seam that SHOULD be welded and is not.
// Counting them per level, per system, BEFORE and AFTER the consolidation is the coverage proof.
//
// The residual after the fix is deliberately NOT tautological. The pass reports:
//   - open_by_group   : edges still used once AFTER mapping endpoints through the weld groups. These are
//                       genuine open boundaries (level border, holes, backfaces) OR missed welds.
//   - missed_welds    : the subset of those that STILL have a geometric twin at a WIDER epsilon with a
//                       compatible face orientation, i.e. an edge the weld tolerance failed to reach.
//                       This is the honest residual. TARGET ~0. The pass drives it down itself with a
//                       BOUNDARY-ONLY WIDE RE-WELD (safe: it can only stitch edges that are already
//                       open, it can never merge interior detail), iterated until it converges.

#include <string>
#include <vector>

#include "common/common_types.h"

namespace tfrag3 {

struct Level;

// One geometry system's topology audit. "raw" = by vertex index (what the GPU actually shares),
// "group" = after mapping every vertex through the position weld map (what the surface actually is).
struct MeshAuditSystem {
  u64 trees = 0;
  u64 verts = 0;
  u64 verts_referenced = 0;
  u64 tris = 0;
  u64 edges_raw = 0;               // distinct edges by raw vertex id
  u64 open_raw = 0;                // raw edges used by exactly one triangle
  u64 coincident_unshared = 0;     // *** THE FORGOTTEN WELDS *** open_raw edges with a geometric twin
  u64 coincident_unshared_pairs = 0;  // twin PAIRS (combinations), the owner's "each pair is one weld"
  u64 open_by_group = 0;           // edges still open after the weld map: true boundary OR missed weld
  u64 missed_welds = 0;            // open_by_group edges that STILL have a wide-epsilon twin => OMISSION
  u64 seam_verts = 0;              // verts this system may not displace (only tfrag is tessellated)
};

// Discontinuity histogram over the welded vertex groups. Buckets are cumulative-exclusive.
struct MeshDeltaHist {
  u64 bucket[5] = {0, 0, 0, 0, 0};  // normals: <1, <5, <15, <45, >=45 deg | colour: <2,<8,<24,<64,>=64
  double sum = 0;
  double max = 0;
  u64 n = 0;
  double mean() const { return n ? sum / (double)n : 0.0; }
};

struct MeshAuditReport {
  std::string level_name;
  std::string game_name;

  MeshAuditSystem tfrag, tie, shrub, total;

  // ---- weld map ----
  u64 groups = 0;                // distinct welded position groups
  u64 groups_coincident = 0;     // groups with >=2 REFERENCED members (the seam population)
  u64 groups_multitree = 0;      // groups spanning >=2 trees/chunks  == the chunk seams
  u64 groups_multisystem = 0;    // groups spanning >=2 systems       == tfrag<->tie junctions
  u64 wide_reweld_rounds = 0;    // boundary-only wide re-weld iterations performed
  u64 wide_reweld_unions = 0;    // vertex unions made by those rounds (welds the 3 cm pass had missed)

  // ---- (2a) NORMAL discontinuity across a welded group ----
  MeshDeltaHist nrm_before, nrm_after;
  // The metric that must actually reach ~0. A CREASE group (a hard edge — a wall meeting a floor)
  // legitimately keeps two different normals, so the all-groups histogram above can never be zero
  // and is not a pass/fail number. Restricted to the SMOOTH groups — the continuous surfaces where
  // a normal step IS the visible seam — the delta must collapse to zero. Both are measured over the
  // same group set so the before/after comparison is like-for-like.
  MeshDeltaHist nrm_smooth_before, nrm_smooth_after;
  u64 groups_crease_after = 0;         // groups legitimately kept as >1 crease cluster (hard edges)
  u64 groups_smooth_split_after = 0;   // single-cluster groups STILL carrying a normal delta -> MUST be 0

  // ---- (2b) BAKED COLOUR discontinuity across a welded group (the couture's prime suspect) ----
  MeshDeltaHist col_before, col_after;
  u64 col_groups_blended = 0;
  u64 col_palette_entries_added = 0;
  u64 col_skipped_cap = 0;             // groups skipped because a tree palette hit the 8192 cap

  // ---- position snap (makes coincident verts BIT-IDENTICAL: tess edge factors then match exactly) ----
  u64 pos_snapped = 0;
  double pos_snap_max_m = 0;

  // ---- normal ORIENTATION (flood-fill over the welded topology + collision authority) ----
  u64 orient_components = 0;
  u64 orient_faces_flipped = 0;
  u64 orient_comps_collision_decided = 0;
  // ROUND 29: components where a collision normal EXISTED but failed the competence/confidence
  // test, so the geometric cascade decided instead of floor-normal noise. Before round 29 every
  // one of these was silently collision-decided.
  u64 orient_comps_collision_incompetent = 0;
  // ROUND 29 — AUTHORITY-FREE CORRECTNESS. The signed volume of a closed component is exact, so it
  // is the ground truth against which an AUTHORITY can be scored. These count, over components
  // where TIER A is confident, how often each collision rule contradicts it. _raw is the
  // pre-round-29 unfiltered rule, _filtered is the round-29 competence-filtered one; the drop
  // between them is the measured improvement, and it needs no collision mesh to be trusted.
  u64 orient_comps_volume_confident = 0;
  u64 orient_comps_collraw_vs_volume_conflict = 0;
  u64 orient_comps_collfiltered_vs_volume_conflict = 0;
  u64 orient_faces_authority = 0;      // faces the collision mesh can actually speak for (denominator)
  u64 orient_faces_inward_after = 0;   // of those, faces still clearly opposed to it -> the residual

  // ---- round-28 SECOND ORIENTATION AUTHORITY (deterministic, purely geometric) ----
  // Until round 28 a component the collision mesh could not reach simply KEPT the orientation it
  // arrived with (the consensus of the AUTHORED vertex normals). That is not an authority at all:
  // if the authored normals are inverted the component stays inverted, and an inverted vertex
  // normal inverts the TESSELLATION displacement (the tese displaces along N) while leaving
  // PARALLAX correct (the POM tangent frame is invariant under N -> -N once w flips, which pass 7b
  // already does). These five counters make that silent population visible and say, per component,
  // WHICH tier of the geometric cascade actually decided it:
  //   TIER A  signed volume (divergence theorem)  -> orient_comps_volume_decided
  //   TIER B  outward ray cast (parity, majority) -> orient_comps_raycast_decided
  //   TIER C  abstain, keep the authored consensus -> orient_comps_undecided
  // volume_decided + raycast_decided + undecided == comps_no_authority, always.
  u64 orient_comps_no_authority = 0;   // components the collision mesh cannot speak for
  u64 orient_faces_no_authority = 0;   // total faces living in those components
  u64 orient_comps_volume_decided = 0;   // TIER A decided the sign
  u64 orient_comps_raycast_decided = 0;  // TIER B decided the sign
  u64 orient_comps_undecided = 0;        // TIER C: nothing could judge -> authored consensus kept

  // ---- round-31 PER-FACE GEOMETRIC OUTWARD VOTE (kMeshBitGeomOrient) ----
  // Rounds 22/28/29 all reasoned about the orientation rule without ever measuring the OUTPUT SIGN
  // per face. Round 31 does: for every face, escape rays are cast from both sides of it and the side
  // that escapes to open air is the OUTWARD side. That vote is then the FIRST authority, ahead of the
  // signed volume, the ray parity and (crucially) the walkable collision mesh — "the walkable side is
  // the outward side" is meaningless for a roof, a vertical wall or a face under a cornice, which is
  // exactly the population the owner reports as displacing the wrong way (sage-hut ground floor: 0.00%
  // correctly-signed vertices, upper floor 58.24%).
  u64 orient_faces_geom_voted = 0;      // faces where the escape counts differed by >= 2 (vote != 0)
  u64 orient_faces_geom_abstained = 0;  // faces where they did not (vote == 0) -> no geometric opinion
  // Faces the PER-FACE repair had to flip AFTER their component had already been decided as a
  // block: the population a component-level authority structurally cannot reach.
  u64 orient_faces_geom_repaired = 0;
  // ROUND 31 second half: components settled by the EXACT signed volume of a closed shell, the
  // subset of those where the sampled escape-ray vote wanted the opposite, and the OPEN components
  // where the two independent criteria contradict each other and neither is believed.
  u64 orient_comps_closed_volume_decided = 0;
  u64 orient_comps_geom_overruled_by_volume = 0;
  u64 orient_comps_criteria_conflict = 0;
  // Vertices where the max-min-dot smoothing-cluster choice landed on a DIFFERENT cluster than the
  // legacy largest-incident-face rule would have picked.
  u64 orient_vertex_cluster_rechosen = 0;
  u64 orient_comps_geom_decided = 0;    // components whose global sign the per-face vote decided
  // Where the vote and an older authority both speak and DISAGREE. The collision number is the
  // measure of how much floor-normal authority this round takes away; the volume number is the
  // honest cross-check on the vote itself (both are exact where they speak, so they should agree).
  u64 orient_comps_geom_vs_collision_conflict = 0;
  u64 orient_comps_geom_vs_volume_conflict = 0;
  double orient_geom_pass_ms = 0;  // wall clock of the whole per-face ray pass (it is the expensive one)

  // ---- round-22 AUTHORITY-FREE POLARITY CENSUS ----
  // The collision residual above can only speak where a collision mesh exists AND is near-parallel to
  // the rendered face (|dot| > 0.35), so it is blind on walls, on interiors, and on every level with a
  // thin collision mesh. This second metric needs no authority at all: for two consistently-wound
  // triangles sharing an edge, the shared edge is traversed in OPPOSITE directions, therefore
  //     fsign[f] * fsign[nb] == (same_dir ? -1 : +1)
  // must hold for every manifold-adjacent pair that is not a coincident duplicate. It is defined on
  // all 448 levels. _before is the SAME statistic evaluated on the AUTHORED winding as it arrives
  // (all signs +1), which is the honest baseline the pass has to improve on; _after is the final one.
  // _after is NOT zero by construction: the flood fill only guarantees the relation on the edges of
  // its spanning forest, so every CLOSING edge (and every non-manifold junction the run-chaining
  // links up) is an independent test the pass can still fail. That is what makes it a real residual.
  u64 orient_pairs_total = 0;                 // non-duplicate manifold-adjacent pairs examined
  u64 orient_pairs_inconsistent_before = 0;   // violations of the rule under the authored winding
  u64 orient_pairs_inconsistent_after = 0;    // violations under the final fsign — the residual
  // The SAME population, split by how much the link can be trusted. A TRUE-manifold pair sits on a
  // welded edge with exactly two incident faces: the winding relation is DEFINED there, so an
  // inconsistency is an outright defect. A WEAK pair is a link the run-chaining fabricated across an
  // edge with 3+ incident faces (stacked coplanar sheets, a decimated LOD triangle chained onto the
  // full-res mesh): the relation is not defined there, so an inconsistency may be unavoidable rather
  // than wrong. true + weak == total, always — the split never shrinks the denominator.
  u64 orient_pairs_true_manifold = 0;
  u64 orient_pairs_true_inconsistent_before = 0;
  u64 orient_pairs_true_inconsistent_after = 0;
  u64 orient_pairs_weak = 0;
  u64 orient_pairs_weak_inconsistent_before = 0;
  u64 orient_pairs_weak_inconsistent_after = 0;
  // Vertices whose consolidated normal ended up OPPOSED to the pre-consolidation one. The tangent
  // handedness w was computed at unpack time against the OLD normal, so bitangent = cross(N,T)*w
  // silently flips with N unless w flips too — a stale w inverts the tangent-space view vector and
  // makes the POM march dig in where it should pop out.
  u64 orient_tangent_w_flipped = 0;

  // ---- seam-consistent displacement (the tessellation slits) ----
  u64 seam_verts = 0;
  u64 seam_verts_material = 0;   // group spans >=2 textures (one side may have no height map)
  u64 seam_verts_system = 0;     // group spans tfrag<->tie (tie is never tessellated)
  u64 seam_verts_open = 0;       // group sits on a genuine open boundary
  u64 seam_verts_crease = 0;     // group is a hard edge: the two sides cannot displace along one normal

  // ---- UV frame coherence (kept from the previous phase, still reported) ----
  u64 uv_pairs = 0;
  u64 uv_pairs_over30 = 0;
  u64 uv_incoherent_groups = 0;
  u64 uv_groups = 0;

  // ---- round-28 UV DETERMINANT / TANGENT-HANDEDNESS CENSUS (measurement only) ----
  // det = du1*dv2 - du2*dv1 over each triangle's UVs. det < 0 == a MIRRORED chart: the authored UV
  // frame is left-handed there, so the tangent basis flips sign across the chart boundary. The
  // tangent reconstruction in common/custom_data/TFrag3Data.cpp:2072 derives w from an ACCUMULATED
  // bitangent (`handed = (N.cross(T).dot(bit_acc[i]) < 0) ? -1 : 1`); on a vertex touched by both a
  // positive-det and a negative-det triangle the two contributions CANCEL, so w there is the sign
  // of numerical noise — a parallax-only inversion that no orientation pass can see.
  u64 uv_tris_total = 0;
  u64 uv_tris_mirrored = 0;             // det < 0
  u64 uv_tris_degenerate = 0;           // |det| <= 1e-12 (no usable UV frame at all)
  u64 uv_verts_handedness_split = 0;    // verts touched by BOTH signs == chart-mirror boundary

  double elapsed_ms = 0;
  bool ran = false;
};

struct MeshConsolidateConfig {
  // Primary weld tolerance. TIGHT on purpose (2 mm): a duplicated vertex at a chunk boundary is an
  // EXACT copy in the authored data, so a tight tolerance catches every one of them without the
  // transitive chaining a loose tolerance causes (measured: a 3 cm tolerance welded village1 down to
  // 4.9 verts per group and moved geometry up to 27 cm). Anything genuinely offset is then picked up
  // by the boundary-only wide pass below, which is guarded by an open-edge + face-orientation test
  // and therefore cannot chain.
  float weld_m = 0.002f;
  float wide_scale = 15.0f;    // boundary-only re-weld / residual-probe tolerance = wide_scale * weld_m
  int wide_rounds = 3;         // max boundary-only wide re-weld iterations
  float crease_deg = 60.0f;    // above this angle two incident faces are a genuine hard edge
  float wide_face_cos = 0.5f;  // twin faces must agree within 60 deg to count as the same surface
  u32 col_blend_threshold = 6; // per-channel baked-colour delta above which a group gets blended
  // killswitch bits (debug.opengoal.mesh.bits / OG_MESH_BITS) — each disables one fix for live A/B.
  //   1 = no position snap, 2 = no normal re-average, 4 = no orientation pass,
  //   8 = no baked-colour blend, 16 = no seam weights, 32 = exclude shrub, 64 = no wide re-weld,
  //   128 = ignore the precompute sidecar, 256 = pre-round-29 unfiltered collision authority,
  //   512 = ENABLE the round-31 per-face geometric outward vote (OFF by default: it is expensive)
  u32 bits = 0;
};

constexpr u32 kMeshBitNoPosSnap = 1;
constexpr u32 kMeshBitNoNormal = 2;
constexpr u32 kMeshBitNoOrient = 4;
constexpr u32 kMeshBitNoColour = 8;
constexpr u32 kMeshBitNoSeam = 16;
constexpr u32 kMeshBitNoShrub = 32;
constexpr u32 kMeshBitNoWide = 64;
constexpr u32 kMeshBitForceLive = 128;  // ignore any precompute sidecar and run the pass live
// ROUND 29 A/B: restore the pre-round-29 UNFILTERED collision authority (raw sum, 1e-3 gate) so the
// competence filter can be bisected on the same data with one debug bit.
constexpr u32 kMeshBitCollRaw = 256;
// ROUND 31 — the PER-FACE GEOMETRIC OUTWARD VOTE, and the precedence change that comes with it
// (geometry outranks the walkable collision mesh). Set it and the orientation pass casts 2*K escape
// rays PER FACE through a uniform-grid accelerator built over every face of every system.
//
// *** EXPENSIVE. This is an OFFLINE bit. *** It is meant for `tools/mesh_audit --bake` and for the
// offline verifier (tools/tess_sign / tools/tess_audit), NOT for a live device level load: village1
// alone is 1.35M faces, so the pass is minutes of CPU, not milliseconds. It is therefore DEFAULT OFF,
// and with it off the orientation pass keeps the pre-round-31 behaviour bit for bit — a device that
// loads a baked sidecar simply inherits the answer this bit computed on the desktop.
constexpr u32 kMeshBitGeomOrient = 512;

// Read the runtime config (Android props / desktop env), so the device and the offline tool agree.
MeshConsolidateConfig mesh_consolidate_config_from_env();

// Everything mesh_consolidate() changed about a level, in a form that can be written to disk and
// replayed. Normals and seam flags are dense because they change nearly everywhere; positions and
// colour indices are sparse because they barely change at all (measured on village1: 762 positions
// and ~30k colour indices out of 1.87M vertices).
struct MeshBakeData {
  struct TreeFp {
    u8 system = 0;
    u32 vert_count = 0;
    u32 index_count = 0;
    u32 orig_color_count = 0;
  };
  struct PalDelta {
    u32 tree = 0;
    u32 new_color_count = 0;
    u32 tail_off = 0;
    std::vector<u8> tail;
  };
  std::vector<TreeFp> tree_fp;
  u64 num_verts = 0;
  std::vector<u32> nor;
  std::vector<u8> seam_bits;
  std::vector<u32> pos_idx;
  std::vector<float> pos_val;  // 3 per pos_idx
  std::vector<u32> cidx_idx;
  std::vector<u16> cidx_val;
  std::vector<PalDelta> pal;
};

// THE PASS. Runs after every tree is unpacked. Mutates lev's unpacked vertex arrays (positions,
// normals, colour indices, seam weights) and may append entries to the per-tree colour palettes.
// Deterministic: identical input -> identical output, on device and offline.
// Pass a non-null `bake` to also capture the result for the precompute sidecar.
void mesh_consolidate(Level& lev,
                      const MeshConsolidateConfig& cfg,
                      MeshAuditReport* out,
                      MeshBakeData* bake = nullptr);

// ---- precompute sidecar ----
// Bake once offline (tools/mesh_audit --bake), load at level load, pay ~0. Measured on the Redmi the
// live pass adds 45.8 s to village1's load; the sidecar replaces that with a small file read. A
// level with no sidecar (a mod, an un-baked game) simply runs the live pass, so nothing is lost.
std::string mesh_consolidate_bake_name(const std::string& level_name);
bool mesh_consolidate_bake_write(const std::string& level_name,
                                 const MeshBakeData& b,
                                 const std::string& path);
// Returns false (and leaves the level untouched) if the file is absent, corrupt, or was baked from
// different geometry — the caller must then run the live pass.
bool mesh_consolidate_apply_bake(Level& lev, const std::string& path, bool do_shrub);

// Human/machine readable per-level block. The offline tool concatenates these for every level of
// every game; the device writes the current level's block to files/mesh_audit.txt.
std::string format_mesh_audit(const MeshAuditReport& r, const MeshConsolidateConfig& cfg);

// One-line CSV row (header via mesh_audit_csv_header()) so 448 levels stay greppable.
std::string mesh_audit_csv_header();
std::string mesh_audit_csv_row(const MeshAuditReport& r);

// Append a formatted block to <jak_project_dir>/mesh_audit.txt (= the app `files/` dir on Android,
// which is where the supervisor can pull it with run-as: the owner's Honor encrypts logcat).
// Truncates itself once it passes a few MB so a long play session cannot fill the device.
void mesh_audit_append_file(const std::string& text);

}  // namespace tfrag3
