#pragma once

// SHARED OUTWARD-ORIENTATION AUTHORITY.
//
// WHY THIS FILE EXISTS. Two pieces of code used to decide, INDEPENDENTLY, which side of a rendered
// face is "outward": the mesh pipeline (common/custom_data/MeshConsolidate.cpp, pass 6) and the
// offline grader (tools/tess_sign/main.cpp). They disagreed on ~25% of vertices, and a grading
// instrument whose notion of outward is not the pipeline's own measures the gap between the two
// instruments instead of the defect. This file is the ONE implementation both of them now call.
//
// WHAT IT COMPUTES. Per face, a sign relative to that face's STORED winding:
//
//     outward(f) = face_sign[f] * normalize(cross(p1 - p0, p2 - p0))
//
// decided by a five-step cascade, in this order and no other:
//
//   VOLX  the shell is CLOSED (every edge used by exactly two of its faces), so the divergence
//         theorem makes the signed volume's sign the ground truth: no free parameter, no origin
//         dependence, no sampling error. EXACT beats SAMPLED, so it is first.
//   RAYF  the PER-FACE escape-ray vote ("lancer de rayon sortant"): the visible side of a surface
//         is the side that has OPEN SPACE on it. Nothing is propagated and nothing is global — a
//         face decides alone, from its own geometry and the level around it.
//   COLL  the shell's competence-filtered COLLISION verdict, carried to the face by the relative
//         winding. Consulted ONLY where the exact volume cannot apply and the rays abstained; it
//         outranks nothing, so the round-29 defect (collision noise outranking an exact volume)
//         cannot recur.
//   ESC   the shell's escape-DISTANCE asymmetry, the last resort before abstaining.
//   UNDECIDED  face_sign stays 0. The caller decides what to do with an unoriented face; this
//         function never invents a verdict it does not have.
//
// There is deliberately NO open-shell volume tier (on an open shell the cone volume about the bbox
// centre is ORIGIN-DEPENDENT, hence not a well-defined quantity, let alone a verdict) and NO
// RAYF-vs-VOL conflict exclusion (that threw away a verdict on the strength of a criterion with no
// standing). Both quantities are still COMPUTED and REPORTED as diagnostics.
//
// DETERMINISM IS PART OF THE CONTRACT. The result is bit-reproducible run to run and independent of
// the thread count: median-split BVH with a TOTAL order on ties, explicit traversal stack with an
// explicit right child, std::map for shell-id assignment, chunked work-stealing where one face is
// one independent problem whose every input is either a compile-time constant or a pure function of
// that face's own normal. No RNG, no clock, no address dependence.
//
// UNITS. Everything is in GAME UNITS. `units_per_m` states the conversion (4096 for jak1/2/3) and
// every metre-denominated constant below is multiplied by it at use.

#include <array>
#include <vector>

#include "common/common_types.h"
#include "common/math/Vector.h"

namespace tfrag3 {

// ---- the metre-denominated tuning constants, published so a caller can cite them in a report ----
constexpr double kOrientVolEps = 1e-3;         // VOLX: |V6| > kOrientVolEps * L^3
constexpr double kOrientRayEdgeEps = 1e-6;     // Moller-Trumbore ambiguity margin
constexpr double kOrientProbeEpsM = 0.01;      // ESC probe offset, metres
constexpr int kOrientMaxSampleFaces = 64;      // ESC sampled faces per shell
constexpr double kOrientEscMargin = 1.25;      // ESC needs the winner 25% ahead
constexpr double kOrientEscMaxM = 60.0;        // ESC free-distance cap, metres
constexpr double kOrientCollParallelMin = 0.35;  // round-29 per-face competence filter
constexpr double kOrientCollConfMin = 0.15;      // round-29 per-shell confidence filter
constexpr double kOrientRayfProbeM = 0.02;     // RAYF probe offset either side of the face, metres
constexpr double kOrientRayfMaxM = 200.0;      // a RAYF ray ESCAPES with no hit within this
constexpr double kOrientRayfTMinM = 0.001;     // RAYF hits closer than this are ignored
constexpr int kOrientRayfKDefault = 13;        // RAYF rays per hemisphere
constexpr int kOrientRayfMinMargin = 2;        // |esc_plus - esc_minus| below this => abstain
constexpr double kOrientRayfOcclEps = 1e-9;    // an edge-grazing hit COUNTS as a hit
constexpr double kOrientGoldenConj = 0.6180339887498948482;

// ---- the exact-float-triple weld key ----------------------------------------------------------
// mesh_consolidate()'s position snap has made coincident positions BIT-IDENTICAL, so exact equality
// is the right test for "the same point". -0.0f is canonicalised to +0.0f so bitwise equality means
// float equality. Published because a caller that has to test membership of a position set (a seam
// attribution, say) must use the SAME notion of "same position" the weld grouping used.
struct MeshPosKey {
  u32 x, y, z;
  bool operator==(const MeshPosKey& o) const { return x == o.x && y == o.y && z == o.z; }
};
struct MeshPosKeyHash {
  size_t operator()(const MeshPosKey& k) const;
};
MeshPosKey mesh_pos_key(float x, float y, float z);

// The input is intentionally caller-agnostic: flat position / index arrays, nothing from
// tfrag3::Level. The collision authority is a point cloud of (position, normal) pairs, which is
// exactly what CollisionMesh::Vertex carries; the caller flattens it.
struct MeshOrientInput {
  const std::vector<math::Vector3f>* positions = nullptr;   // per global vertex, GAME UNITS
  const std::vector<std::array<u32, 3>>* faces = nullptr;   // global vertex ids, STORED winding
  // Optional. A "candidate" face is one the caller actually needs a verdict for: RAYF is run over
  // exactly this population and the per-shell tiers only speak for shells owning one. null = every
  // face is a candidate.
  const std::vector<u8>* face_is_candidate = nullptr;
  // Optional collision authority. Both must be non-null and the same length to be used.
  const std::vector<math::Vector3f>* coll_vertices = nullptr;  // positions, GAME UNITS
  const std::vector<math::Vector3f>* coll_normals = nullptr;   // need not be unit length
  float units_per_m = 4096.f;
  int rays_per_hemi = kOrientRayfKDefault;
  int threads = 0;  // 0 = std::thread::hardware_concurrency()
};

enum MeshOrientTier : u8 {
  kOrientVolx = 0,
  kOrientRayf = 1,
  kOrientColl = 2,
  kOrientEsc = 3,
  kOrientUndecided = 4,
};
const char* mesh_orient_tier_name(u8 tier);

// Which SHELL-level tier produced shell_gsign. This is NOT the per-face tier above: the shell
// verdict is a fallback the per-face cascade may or may not consult.
enum MeshOrientShellTier : u8 {
  kOrientShellUndecided = 0,
  kOrientShellVol = 1,
  kOrientShellEsc = 2,
};
const char* mesh_orient_shell_tier_name(u8 tier);

struct MeshOrientResult {
  // ---- THE VERDICT ----
  std::vector<s8> face_sign;  // +1 / -1 relative to the STORED winding; 0 = UNDECIDED
  std::vector<u8> face_tier;  // MeshOrientTier

  // ---- the topology the verdict was derived from ----
  std::vector<u32> shell_of;      // per face
  std::vector<s8> rel;            // per face, relative winding inside its shell (0 = unvisited)
  std::vector<u32> vert_group;    // per input position: exact-float-triple weld group, or
                                  // UINT32_MAX for a position no face references
  std::vector<u8> group_has_open_edge;  // per weld group: touched by an edge used by exactly ONE face
  u32 weld_groups = 0;
  u64 edge_count = 0;             // distinct undirected weld-group pairs
  u32 shell_count = 0;

  // ---- per shell ----
  std::vector<u8> shell_closed;        // every edge used by EXACTLY TWO of the shell's faces
  std::vector<u32> shell_open_edges;   // the edges that are not
  std::vector<s8> shell_vol_sign;      // the SIGNED-VOLUME verdict alone, 0 = it stayed silent
  std::vector<double> shell_v6_over_l3;
  std::vector<u64> shell_winding_conflicts;
  std::vector<s8> shell_coll_sign;     // 0 = the collision authority is not competent here
  std::vector<u8> shell_coll_speaks;
  std::vector<double> shell_esc_ratio;
  std::vector<s8> shell_gsign;         // the SHELL-level fallback verdict (VOL or ESC)
  std::vector<u8> shell_tier;          // MeshOrientShellTier, which one produced shell_gsign
  std::vector<u8> shell_has_candidate;
  std::vector<u32> shell_face_count;
  // rayf scored against the signed volume, per shell, over the shell's own CANDIDATE faces. They
  // agree on face f iff rayf_vote[f] == shell_vol_sign * rel[f]. DIAGNOSTIC ONLY: it suppresses no
  // verdict.
  std::vector<u64> shell_rayf_voted;
  std::vector<u64> shell_rayf_agree;
  std::vector<u64> shell_rayf_disagree;

  // ---- per face, before the cascade (diagnostic) ----
  std::vector<s8> rayf_vote;      // the escape-ray vote alone, 0 = it abstained
  std::vector<u8> rayf_escapes_plus;   // escapes on the +gn side (0..rays_per_hemi)
  std::vector<u8> rayf_escapes_minus;
  std::vector<u8> face_rayf_vs_vol_conflict;  // RAYF and VOL hand this face OPPOSITE directions

  // ---- counters ----
  u64 faces_volx = 0, faces_rayf = 0, faces_coll = 0, faces_esc = 0, faces_undecided = 0;
  u64 candidate_faces = 0;
  u64 rayf_voted = 0;             // candidate faces with a non-zero vote
  u64 rayf_sat_all_blocked = 0;   // ... 0 escapes on BOTH sides (every ray blocked)
  u64 rayf_sat_all_open = 0;      // ... K escapes on BOTH sides (no ray blocked)
  double rayf_mean_escapes_plus = 0.0;
  double rayf_mean_escapes_minus = 0.0;
  u64 rayf_vs_vol_agree = 0;      // over candidate faces, level-wide. DIAGNOSTIC ONLY.
  u64 rayf_vs_vol_disagree = 0;
  u64 rayf_vs_vol_conflict_faces = 0;  // the per-face cascade's conflict mark, level-wide
  u64 shells_closed = 0, shells_open = 0;
  u32 bvh_nodes = 0;
  unsigned threads_used = 1;
  double bvh_seconds = 0.0;
  double rayf_seconds = 0.0;
  double seconds = 0.0;           // the whole call
};

// THE one outward authority. Deterministic; safe to call from any thread (it spawns its own).
MeshOrientResult mesh_orient_faces(const MeshOrientInput& in);

}  // namespace tfrag3
