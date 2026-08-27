#include "common/custom_data/TangentDerive.h"

#include <atomic>
#include <chrono>
#include <cmath>
#include <mutex>

#include "common/custom_data/normal_pack.h"
#include "common/log/log.h"

namespace tfrag3 {

namespace {
// Gpbr-fusion / PBR POLISH (owner playtest #16, defect 1: "displacement in the WRONG DIRECTION in
// places on the SAME texture") — MEASUREMENT ONLY. How far is the OLD world-derived normal-map frame
// (the shader's stable_frame(), built from the smooth NORMAL alone, UVs ignored) rotated away from
// the AUTHORED UV tangent frame at each vertex? Past 90 deg the relief is lit from the opposite side
// => bumps read as pits. Only verts carrying a REAL UV-derived tangent are measurable.
// These moved here with the derivation itself: they count what the DERIVATION saw, so they belong
// wherever the derivation runs (offline bake, or mesh_consolidate's re-derivation).
std::atomic<u64> g_wframe_verts{0};
std::atomic<u64> g_wframe_h0{0};
std::atomic<u64> g_wframe_h1{0};
std::atomic<u64> g_wframe_h2{0};
std::atomic<u64> g_wframe_h3{0};
std::atomic<u64> g_wframe_h4{0};
std::atomic<u64> g_wframe_h5{0};
std::atomic<u64> g_wframe_over90{0};
std::atomic<u64> g_wframe_rot_sum_milli{0};

// REOPEN#9 tangent-fallback coverage, accumulated across the trees this process derived.
std::mutex g_tan_diag_mtx;
struct TanDiag {
  u64 total_verts = 0;
  u64 uv_tangent = 0;
  u64 backfilled = 0;
  u64 ground_verts = 0;
  u64 ground_would_fallback = 0;
  u64 trees = 0;
} g_tan_diag;
}  // namespace

TangentDeriveDiag tangent_derive_diag() {
  TangentDeriveDiag d;
  {
    std::lock_guard<std::mutex> lk(g_tan_diag_mtx);
    d.total_verts = g_tan_diag.total_verts;
    d.uv_tangent = g_tan_diag.uv_tangent;
    d.backfilled = g_tan_diag.backfilled;
    d.ground_verts = g_tan_diag.ground_verts;
    d.ground_would_fallback = g_tan_diag.ground_would_fallback;
    d.trees = g_tan_diag.trees;
  }
  d.wframe_verts = g_wframe_verts.load();
  d.wframe_hist[0] = g_wframe_h0.load();
  d.wframe_hist[1] = g_wframe_h1.load();
  d.wframe_hist[2] = g_wframe_h2.load();
  d.wframe_hist[3] = g_wframe_h3.load();
  d.wframe_hist[4] = g_wframe_h4.load();
  d.wframe_hist[5] = g_wframe_h5.load();
  d.wframe_over90 = g_wframe_over90.load();
  d.wframe_rot_sum_milli = g_wframe_rot_sum_milli.load();
  return d;
}

// Grecharged-pbr-realtime-fusion REOPEN#7 FOUNDATION FIX — per-vertex MikkTSpace-style tangents.
// tfrag/tie meshes ship NO vertex tangents, so the PBR shader used to rebuild a TBN frame per
// fragment from screen-space derivatives (dFdx/dFdy of position+UV). Those derivatives are
// DISCONTINUOUS across triangle edges and UV seams => the normal-mapped relief was incoherent and,
// scaled up, the discontinuities became the owner's hard-contrast CRACKS. Here we compute a proper
// per-vertex tangent from the mesh positions+UVs (Lengyel/MikkTSpace accumulation), orthonormalize
// it against the reconstructed smooth normal (Gram-Schmidt) and store handedness in .w. The shader
// interpolates this continuous tangent => continuous TBN => no cracks + coherent surface-locked
// relief. Deterministic (index-ordered float accumulation) so an offline bake yields identical
// bytes. Walks triangle STRIPS with UINT32_MAX primitive restart, matching the render index stream.
void reconstruct_tfrag_tangents(const std::vector<PreloadedVertex>& verts,
                                       const std::vector<u32>& indices,
                                       bool use_strips,
                                       std::vector<math::Vector4f>& out_tangents) {
  const size_t n = verts.size();
  out_tangents.assign(n, math::Vector4f(0.f, 0.f, 0.f, 0.f));
  if (n == 0) {
    return;
  }
  std::vector<math::Vector3f> tan_acc(n, math::Vector3f::zero());
  std::vector<math::Vector3f> bit_acc(n, math::Vector3f::zero());

  u32 dbg_tris_used = 0, dbg_tris_skip_uv = 0;
  auto add_tri = [&](u32 i0, u32 i1, u32 i2) {
    const auto& v0 = verts[i0];
    const auto& v1 = verts[i1];
    const auto& v2 = verts[i2];
    math::Vector3f p0(v0.x, v0.y, v0.z), p1(v1.x, v1.y, v1.z), p2(v2.x, v2.y, v2.z);
    math::Vector3f e1 = p1 - p0, e2 = p2 - p0;
    float du1 = v1.s - v0.s, dv1 = v1.t - v0.t;
    float du2 = v2.s - v0.s, dv2 = v2.t - v0.t;
    float det = du1 * dv2 - du2 * dv1;
    if (!(std::fabs(det) > 1e-12f)) {
      dbg_tris_skip_uv++;
      return;  // degenerate UV parameterization: no reliable tangent
    }
    dbg_tris_used++;
    float r = 1.f / det;
    // Lengyel: T points along +U, B along +V in world space (winding-independent).
    math::Vector3f T = (e1 * dv2 - e2 * dv1) * r;
    math::Vector3f B = (e2 * du1 - e1 * du2) * r;
    tan_acc[i0] += T;
    tan_acc[i1] += T;
    tan_acc[i2] += T;
    bit_acc[i0] += B;
    bit_acc[i1] += B;
    bit_acc[i2] += B;
  };

  if (use_strips) {
    // Triangle strips with UINT32_MAX primitive restart; the UV-derived tangent direction does not
    // depend on the strip winding parity, so we accumulate every non-restart triple directly.
    u32 a = UINT32_MAX, b = UINT32_MAX;
    for (u32 vi : indices) {
      if (vi == UINT32_MAX) {
        a = b = UINT32_MAX;
        continue;
      }
      if (a != UINT32_MAX && b != UINT32_MAX && a != b && b != vi && a != vi) {
        add_tri(a, b, vi);
      }
      a = b;
      b = vi;
    }
  } else {
    for (size_t t = 0; t + 2 < indices.size(); t += 3) {
      if (indices[t] == UINT32_MAX || indices[t + 1] == UINT32_MAX || indices[t + 2] == UINT32_MAX) {
        continue;
      }
      add_tri(indices[t], indices[t + 1], indices[t + 2]);
    }
  }

  u32 valid = 0, dbg_no_norm = 0, dbg_no_tan = 0, dbg_gs_kill = 0;
  u32 g_verts = 0, g_backfill = 0;  // REOPEN#9 ground (N.y>0.7) fallback-coverage proof
  // PBR POLISH (owner playtest #16, defect 1) world-frame-vs-UV-frame rotation, accumulated in locals
  // (no atomics inside the hot loop) and folded into the global counters once, below.
  u64 wf_verts = 0, wf_over90 = 0, wf_rot_sum_milli = 0;
  u64 wf_hist[6] = {0, 0, 0, 0, 0, 0};
  for (size_t i = 0; i < n; i++) {
    math::Vector3f N = unpack_gl_normal_2_10_10_10(verts[i].nor);
    float Nl = N.length();
    bool ground = Nl > 0.5f && (N.y() / Nl) > 0.7f;  // ground-facing (N may be ~0 for no_norm)
    if (ground) {
      g_verts++;
    }
    math::Vector3f T = tan_acc[i];
    // REOPEN#9 (owner playtest #9): the OLD code wrote (0,0,0,0) here, which made the shader fall to the
    // screen-space-derivative TBN (per-triangle-constant => the hard triangular FACETS scaling with
    // relief). Instead ALWAYS write a NON-DEGENERATE, unit tangent so the shader keeps its continuous
    // per-vertex-tangent path. Degenerate verts get a continuous Duff/Frisvad basis from the smooth
    // normal (an arbitrary but continuous direction — continuity is what kills the facets).
    if (Nl < 0.5f) {
      // No usable smooth normal (the base shading normal is itself degenerate at this vert). Write a
      // stable constant tangent so v_tangent is never zero. w=+1.
      dbg_no_norm++;
      math::Vector3f tb = duff_tangent_from_normal(math::Vector3f(0.f, 1.f, 0.f));
      out_tangents[i] = math::Vector4f(tb.x(), tb.y(), tb.z(), 1.f);
      continue;
    }
    if (T.length() < 1e-9f) {
      // Degenerate/mirrored UVs: no reliable UV tangent. Backfill a continuous Frisvad basis from N.
      dbg_no_tan++;
      if (ground) {
        g_backfill++;
      }
      math::Vector3f tb = duff_tangent_from_normal(N * (1.f / Nl));
      out_tangents[i] = math::Vector4f(tb.x(), tb.y(), tb.z(), 1.f);
      continue;
    }
    // Gram-Schmidt: remove the normal component, renormalize.
    //
    // Gprecompute-deterministic-bake (2026-08-27) — NORMALISE FIRST, AND THE GUARD BELOW IS
    // RELATIVE. `tan_acc[i]` is a SUM over every incident face, so its magnitude is the scale of the
    // level's world units, not 1: on village2 and sunken it reaches values where the roundoff of the
    // subtraction alone clears an ABSOLUTE 1e-6 threshold. When the accumulated tangent is nearly
    // parallel to N, what survives the subtraction is then pure float cancellation noise, and
    // normalising noise gives a direction that is NOT perpendicular to N at all — measured, on the
    // shipped data: 519 vertices of sunken and 12 of village2 came out with dot(N,T) = +/-1.000000,
    // i.e. the "tangent" WAS the normal. The bake's round-trip control is what surfaced them (it
    // cannot store a tangent that is not in the normal's plane), but the defect is older than the
    // bake and every one of those vertices shipped with a meaningless tangent frame.
    // Normalising first makes the test scale-free without changing a single well-conditioned
    // vertex: (T - N(N.T)) / |T - N(N.T)| is invariant under T -> cT for c > 0. 1e-3 on a unit
    // vector means the UV tangent sits within 0.057 deg of the normal — four orders of magnitude
    // above the float noise floor, and far below any angle a real UV parameterisation produces.
    T = T * (1.f / T.length());
    T = T - N * N.dot(T);
    float tl = T.length();
    if (tl < 1e-3f) {
      // UV tangent collapsed onto the normal: backfill a continuous Frisvad basis from N.
      dbg_gs_kill++;
      if (ground) {
        g_backfill++;
      }
      math::Vector3f tb = duff_tangent_from_normal(N * (1.f / Nl));
      out_tangents[i] = math::Vector4f(tb.x(), tb.y(), tb.z(), 1.f);
      continue;
    }
    T = T * (1.f / tl);
    float handed = (N.cross(T).dot(bit_acc[i]) < 0.f) ? -1.f : 1.f;
    out_tangents[i] = math::Vector4f(T.x(), T.y(), T.z(), handed);
    valid++;
    // ---- PBR POLISH (owner playtest #16, defect 1) — MEASUREMENT ONLY, writes no mesh data --------
    // T is the AUTHORED UV tangent, already Gram-Schmidt'd against N and normalized (tl = the pre-
    // normalize length, so tl is the "|t - n*dot(n,t)|" guard). Compare it against the frame the OLD
    // shader path builds from the normal alone (stable_frame()): the angle between the two, measured in
    // the plane of N, is how far the normal map's relief is rotated from what the artist authored. Past
    // 90 deg the relief is lit from the opposite side and bumps read as pits.
    if (tl >= 1e-4f) {
      const math::Vector3f Nu = N * (1.f / Nl);  // n = normalize(smooth normal)
      // stable_frame() reproduced EXACTLY as tfrag3.frag has it:
      const math::Vector3f R1(0.3113f, 0.1504f, 0.9382f), R2(0.9382f, 0.3113f, 0.1504f);
      const math::Vector3f tt = Nu.cross(R1);
      const float wl = tt.length();
      math::Vector3f tw;
      bool tw_ok = true;
      if (wl > 0.02f) {
        tw = tt * (1.f / wl);
      } else {
        const math::Vector3f t2 = Nu.cross(R2);
        const float w2 = t2.length();
        if (w2 > 1e-12f) {
          tw = t2 * (1.f / w2);
        } else {
          tw_ok = false;  // both skew axes collinear with N: unmeasurable, skip
        }
      }
      if (tw_ok) {
        // signed rotation of tw away from T, measured in the plane of N
        const float cs = T.dot(tw);
        const float sn = T.cross(tw).dot(Nu);
        const float deg = std::fabs(std::atan2(sn, cs)) * 57.29577951308232f;  // 0..180
        wf_verts++;
        wf_hist[deg < 5.f     ? 0
                : deg < 15.f  ? 1
                : deg < 45.f  ? 2
                : deg < 90.f  ? 3
                : deg < 135.f ? 4
                              : 5]++;
        if (deg > 90.f) {
          wf_over90++;
        }
        wf_rot_sum_milli += (u64)(deg * 1000.f);
      }
    }
  }
  // REOPEN#7 device-truth: one line per tree so the on-device logcat PROVES the per-vertex tangent
  // basis is computed + uploaded (the continuous-TBN foundation). valid == vertices with a real
  // tangent (the rest fall back to the derivative frame). Mirrors the [gda-crease] normal log.
  lg::info(
      "[gpbrf-tangent] verts={} valid={} ({:.1f}%) no_norm={} no_tan={} gs_kill={} tris_used={} "
      "tris_skip_uv={} strips={}",
      n, valid, n ? (100.f * (float)valid / (float)n) : 0.f, dbg_no_norm, dbg_no_tan, dbg_gs_kill,
      dbg_tris_used, dbg_tris_skip_uv, use_strips ? 1 : 0);
  // REOPEN#9 (owner playtest #9): the facets = the shader falling to the screen-derivative TBN where
  // v_tangent is degenerate. This line + the pbr_tan_diag.txt file PROVE the coverage on the GROUND
  // (N.y>0.7 — the grass the owner looks at): would_fallback = degenerate ground verts BEFORE the
  // backfill; every one is now backfilled with a continuous Duff/Frisvad tangent, so the shader
  // per-vertex-tangent coverage on the ground is 100% and the screen-derivative fallback fraction is 0.
  lg::info("[tan-fallback] ground_verts={} would_fallback={} ({:.2f}%) => backfilled, post_fix=0",
           g_verts, g_backfill, g_verts ? (100.f * (float)g_backfill / (float)g_verts) : 0.f);
  // PBR POLISH (owner playtest #16, defect 1) — fold this tree's world-frame-vs-UV-frame rotation
  // measurement into the process-wide counters that tangent_derive_diag() publishes (the
  // pbr_tan_diag.txt writer in TFrag3Data.cpp reads them from there).
  g_wframe_verts += wf_verts;
  g_wframe_h0 += wf_hist[0];
  g_wframe_h1 += wf_hist[1];
  g_wframe_h2 += wf_hist[2];
  g_wframe_h3 += wf_hist[3];
  g_wframe_h4 += wf_hist[4];
  g_wframe_h5 += wf_hist[5];
  g_wframe_over90 += wf_over90;
  g_wframe_rot_sum_milli += wf_rot_sum_milli;
  {
    std::lock_guard<std::mutex> lk(g_tan_diag_mtx);
    g_tan_diag.total_verts += n;
    g_tan_diag.uv_tangent += valid;
    g_tan_diag.backfilled += (u64)dbg_no_norm + dbg_no_tan + dbg_gs_kill;
    g_tan_diag.ground_verts += g_verts;
    g_tan_diag.ground_would_fallback += g_backfill;
    g_tan_diag.trees += 1;
  }
}

// ROUND 31 — RE-DERIVE EVERY PER-VERTEX TANGENT FRAME FROM THE VERTEX NORMALS AS THEY STAND NOW.
// Declared in Tfrag3Data.h; defined here because it re-runs the derivation above, against the
// normals mesh_consolidate() has just rewritten. That is a DIFFERENT input from the fr3's own bytes
// (it depends on the consolidation, which is itself gated on PBR and on the .meshweld sidecar), so
// it is NOT a candidate for the fr3 bake and stays a live pass on the PBR path.
u64 retangent_level_from_final_normals(Level& lev) {
  u64 changed = 0;
  auto redo = [&](std::vector<PreloadedVertex>& verts, const std::vector<u32>& indices,
                  bool use_strips, std::vector<math::Vector4f>& tangents) {
    if (verts.empty() || tangents.size() != verts.size()) {
      return;  // no tangent stream on this tree (shrub): nothing to re-derive
    }
    std::vector<math::Vector4f> before = tangents;
    reconstruct_tfrag_tangents(verts, indices, use_strips, tangents);
    for (size_t i = 0; i < tangents.size(); i++) {
      const auto& a = before[i];
      const auto& b = tangents[i];
      if (a.x() != b.x() || a.y() != b.y() || a.z() != b.z() || a.w() != b.w()) {
        changed++;
      }
    }
  };
  for (auto& t : lev.tfrag_trees) {
    for (auto& tree : t) {
      redo(tree.unpacked.vertices, tree.unpacked.indices, tree.use_strips, tree.unpacked.tangents);
    }
  }
  for (auto& t : lev.tie_trees) {
    for (auto& tree : t) {
      redo(tree.unpacked.vertices, tree.unpacked.indices, tree.use_strips, tree.unpacked.tangents);
    }
  }
  return changed;
}

// ================================================================================================
// THE OFFLINE BAKE. Runs in the fr3 extractor, once per level, immediately before serialization.
//
// It reproduces the loader's chain EXACTLY — TfragTree/TieTree::unpack() builds the vertices from
// the packed cluster data, the index buffer from the draws, fuses the index buffer (the weld) and
// reconstructs the smooth normals — and then derives the tangents from that. The loader repeats the
// first four steps (they are cheap and produce arrays it needs anyway) and skips the fifth, which is
// the expensive one: a full pass over every triangle accumulating a per-vertex frame.
//
// KNOWN CONDITION. fuse_tree_indices() and the smooth-normal pass honour the debug A/B toggle
// `debug.opengoal.mesh.weld` / OG_MESH_WELD; the bake is taken with that toggle in its DEFAULT (on)
// state. Forcing it off at runtime therefore renders an unfused index buffer against tangents
// derived on the fused one. That is a debug bisect switch, not a user setting, and the discrepancy
// is named here rather than hidden.
// ================================================================================================
void bake_deterministic_tangents(Level& lev, TangentBakeStats* out) {
  const auto t0 = std::chrono::high_resolution_clock::now();
  const TangentDeriveDiag d0 = tangent_derive_diag();  // per-LEVEL deltas, not process totals
  TangentBakeStats st;
  set_tangent_bake_in_progress(true);
  // ROUND-TRIP CONTROL. The encoding drops the tangent onto an angle in the plane of the vertex
  // normal, so it is only faithful if T really is perpendicular to N (the derivation Gram-Schmidts
  // it) and if both sides build the same basis from the same quantised normal. Rather than assert
  // that, MEASURE it here, on every vertex of every level, and publish the worst case: decode what
  // was just encoded and compare it against the float tangent it came from.
  double worst_deg = 0.0;
  u64 handed_bad = 0;
  u64 over_bound = 0;                 // vertices past one quantisation step
  u32 worst_nor = 0;                  // and everything needed to reproduce the worst one by hand
  math::Vector4f worst_src{}, worst_back{};

  auto do_tree = [&](auto& tree, u64* tree_counter) {
    tree.unpack();  // vertices + indices + fuse + smooth normals — exactly what the loader will do
    reconstruct_tfrag_tangents(tree.unpacked.vertices, tree.unpacked.indices, tree.use_strips,
                               tree.unpacked.tangents);
    const size_t n = tree.unpacked.tangents.size();
    tree.baked_tangents.resize(n);
    for (size_t i = 0; i < n; i++) {
      const u32 nor = tree.unpacked.vertices[i].nor;
      const auto& src = tree.unpacked.tangents[i];
      tree.baked_tangents[i] = pack_tangent_angle16(nor, src);
      const auto back = unpack_tangent_angle16(nor, tree.baked_tangents[i]);
      const math::Vector3f a(src.x(), src.y(), src.z());
      const math::Vector3f b(back.x(), back.y(), back.z());
      const float la = a.length(), lb = b.length();
      if (la > 1e-6f && lb > 1e-6f) {
        // atan2(|a x b|, a.b), NOT acos(a.b/|a||b|). Near zero angle acos is ill-conditioned: an
        // error eps in its argument comes out as sqrt(2 eps) in the angle, so float dot products
        // give it a NOISE FLOOR around 0.03 deg — measured, and it read as a 0.028-0.077 deg
        // encoding defect on the first run of this control before the estimator was fixed. The
        // cross-product form stays conditioned all the way to 0.
        const double deg =
            std::atan2((double)a.cross(b).length(), (double)a.dot(b)) * 57.29577951308232;
        if (deg > 0.0056) {
          over_bound++;
        }
        if (deg > worst_deg) {
          worst_deg = deg;
          worst_nor = nor;
          worst_src = src;
          worst_back = back;
        }
      }
      if ((src.w() < 0.f) != (back.w() < 0.f)) {
        handed_bad++;
      }
    }
    st.verts += (u64)n;
    st.bytes_baked += (u64)n * sizeof(u16);
    st.bytes_avoided += (u64)n * sizeof(math::Vector4f);
    (*tree_counter)++;
    // Release the working arrays: they are rebuilt at load and would otherwise multiply the
    // extractor's peak RSS by the size of the whole unpacked level.
    std::vector<PreloadedVertex>().swap(tree.unpacked.vertices);
    std::vector<u32>().swap(tree.unpacked.indices);
    std::vector<math::Vector4f>().swap(tree.unpacked.tangents);
  };

  for (auto& geo : lev.tfrag_trees) {
    for (auto& tree : geo) {
      do_tree(tree, &st.tfrag_trees);
    }
  }
  for (auto& geo : lev.tie_trees) {
    for (auto& tree : geo) {
      do_tree(tree, &st.tie_trees);
    }
  }

  set_tangent_bake_in_progress(false);
  st.elapsed_ms = std::chrono::duration<double, std::milli>(
                      std::chrono::high_resolution_clock::now() - t0)
                      .count();
  const auto d1 = tangent_derive_diag();
  lg::info(
      "[tangent-bake] level={} tfrag_trees={} tie_trees={} verts={} baked={:.2f}MB "
      "(replaces {:.2f}MB re-derived at every load) uv_tangent={} backfilled={} "
      "roundtrip_worst={:.4f}deg over_bound={} handedness_lost={} {:.0f}ms",
      lev.level_name, st.tfrag_trees, st.tie_trees, st.verts, st.bytes_baked / 1048576.0,
      st.bytes_avoided / 1048576.0, d1.uv_tangent - d0.uv_tangent, d1.backfilled - d0.backfilled,
      worst_deg, over_bound, handed_bad, st.elapsed_ms);
  if (handed_bad || worst_deg > 0.02) {
    lg::warn(
        "[tangent-bake] level={} THE ENCODING IS NOT FAITHFUL: worst round-trip {:.4f} deg (bound "
        "is one 15-bit angle step, 0.011 deg) and {} vertices lost their handedness. A tangent that "
        "is not perpendicular to its vertex normal cannot be stored as an angle in that normal's "
        "plane — do not ship this fr3. over_bound={} of {} verts; worst vertex nor=0x{:08x} "
        "N=({:.6f},{:.6f},{:.6f}) src=({:.6f},{:.6f},{:.6f},{:+.0f}) "
        "back=({:.6f},{:.6f},{:.6f},{:+.0f}) dot(N,src)={:.6f}",
        lev.level_name, worst_deg, handed_bad, over_bound, st.verts, worst_nor,
        unpack_gl_normal_2_10_10_10(worst_nor).x(), unpack_gl_normal_2_10_10_10(worst_nor).y(),
        unpack_gl_normal_2_10_10_10(worst_nor).z(), worst_src.x(), worst_src.y(), worst_src.z(),
        worst_src.w(), worst_back.x(), worst_back.y(), worst_back.z(), worst_back.w(),
        unpack_gl_normal_2_10_10_10(worst_nor).dot(
            math::Vector3f(worst_src.x(), worst_src.y(), worst_src.z())));
  }
  if (out) {
    *out = st;
  }
}

}  // namespace tfrag3
