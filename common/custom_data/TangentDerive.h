#pragma once

// Gprecompute-deterministic-bake (owner 2026-08-26, verbatim): « tout ce qu'on peut pre-computer
// devrait l'etre au lieu de prendre du temps CPU/GPU c'est debile. Ca profitera a tout materiel ! »
//
// THE PER-VERTEX TANGENT DERIVATION, MOVED OUT OF THE LOAD PATH.
//
// reconstruct_tfrag_tangents() used to be a file-static of TFrag3Data.cpp called from
// TfragTree::unpack() and TieTree::unpack(), i.e. once per tree on every level load on every
// machine, for a result that is entirely determined by the fr3's own bytes (positions + UVs from
// packed_vertices, topology from draws + use_strips, index-ordered float accumulation). It lives
// here now so that:
//   - the LOAD path (TFrag3Data.cpp) has no way to call it — it only expands TfragTree/TieTree
//     ::baked_tangents, which the fr3 already carries;
//   - the OFFLINE fr3 extractor calls bake_deterministic_tangents() once, at build time;
//   - mesh_consolidate() can still RE-derive against the normals it just rewrote
//     (retangent_level_from_final_normals), which is a genuinely different input.
// Keeping the SYMBOL NAME unchanged is deliberate: the phase gate greps for it inside
// common/custom_data/TFrag3Data.cpp and game/graphics/opengl_renderer/loader/, so re-introducing a
// load-time reconstruction anywhere in those two places still fails the gate instead of passing
// vacuously on a renamed function.

#include <vector>

#include "common/common_types.h"
#include "common/custom_data/Tfrag3Data.h"
#include "common/math/Vector.h"

namespace tfrag3 {

// Per-vertex tangent from mesh positions + UVs (Lengyel/MikkTSpace accumulation), orthonormalized
// against the reconstructed smooth normal (Gram-Schmidt), handedness in .w. Deterministic
// (index-ordered float accumulation) so an offline bake yields identical bytes to a live run.
// Walks triangle STRIPS with UINT32_MAX primitive restart, matching the render index stream.
void reconstruct_tfrag_tangents(const std::vector<PreloadedVertex>& verts,
                                const std::vector<u32>& indices,
                                bool use_strips,
                                std::vector<math::Vector4f>& out_tangents);

// What the derivation saw, cumulative over this process. TFrag3Data.cpp's pbr_tan_diag.txt writer
// reads it so the existing [pbr_tan_diag] / [world_frame_rot] blocks keep reporting real numbers.
struct TangentDeriveDiag {
  u64 total_verts = 0;
  u64 uv_tangent = 0;
  u64 backfilled = 0;
  u64 ground_verts = 0;
  u64 ground_would_fallback = 0;
  u64 trees = 0;
  // world-frame-vs-UV-frame rotation census (measurement only, see the definition)
  u64 wframe_verts = 0;
  u64 wframe_hist[6] = {0, 0, 0, 0, 0, 0};
  u64 wframe_over90 = 0;
  u64 wframe_rot_sum_milli = 0;
};
TangentDeriveDiag tangent_derive_diag();

struct TangentBakeStats {
  u64 tfrag_trees = 0;
  u64 tie_trees = 0;
  u64 verts = 0;         // vertices given a baked tangent
  u64 bytes_baked = 0;   // 4 per vertex — what the fr3 grows by
  u64 bytes_avoided = 0; // 16 per vertex — what the load used to produce from scratch
  double elapsed_ms = 0;
};

// OFFLINE ONLY (fr3 extractor). Unpacks every tfrag/tie tree exactly as the loader will, derives the
// tangents, packs them into <tree>.baked_tangents, and releases the unpacked working arrays so the
// extractor's peak memory does not grow. Must be called immediately before Level::serialize().
void bake_deterministic_tangents(Level& lev, TangentBakeStats* out = nullptr);

}  // namespace tfrag3
