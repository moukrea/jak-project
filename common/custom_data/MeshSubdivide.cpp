#include "MeshSubdivide.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <string>
#include <unordered_map>
#include <vector>

#include "Tfrag3Data.h"

#include "common/log/log.h"

#include "fmt/format.h"

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace tfrag3 {
namespace {

constexpr float kUnitsPerMeter = 4096.f;
constexpr int kPaletteCount = 8;
constexpr u32 kMaxPaletteColors = 8192;  // == TFragment::TIME_OF_DAY_COLOR_COUNT

std::string get_setting(const char* android_prop, const char* env_name) {
#ifdef __ANDROID__
  char buf[PROP_VALUE_MAX] = {0};
  if (__system_property_get(android_prop, buf) > 0) {
    return std::string(buf);
  }
#else
  (void)android_prop;
#endif
  const char* e = std::getenv(env_name);
  return e ? std::string(e) : std::string();
}

// TFragment.cpp `tess_kind_eligible` — the tfrag kinds that may be drawn through the tessellation
// program. OWNER 2026-07-26 ("bah elle devrait pouvoir tourner partout !"): widened IDENTICALLY to
// the runtime test, because a kind the runtime tessellates but this filter skips gets no
// pre-subdivided geometry (coarse patches = another flavour of the owner's flat chunks). NORMAL,
// TRANS, DIRT, ICE, LOWRES, LOWRES_TRANS and WATER all qualify; only the INVALID sentinel is out.
bool tess_opaque_kind(TFragmentTreeKind kind) {
  return kind != TFragmentTreeKind::INVALID;
}

// The GL 2-10-10-10 packing the renderer binds at location 3. Identical maths to MeshConsolidate's,
// deliberately: a midpoint's normal must come out bit-identical to the one the other side of a chunk
// seam computes from the same two (already consolidated, therefore identical) parent normals.
u32 pack_nor(float x, float y, float z) {
  auto sat = [](float f) -> u32 {
    int v = (int)std::lround(f * 511.f);
    v = std::max(-511, std::min(511, v));
    return (u32)v & 0x3ffu;
  };
  return sat(x) | (sat(y) << 10) | (sat(z) << 20);
}

void unpack_nor(u32 p, float* out) {
  auto sx = [](u32 v) -> int {
    int x = (int)(v & 0x3ffu);
    return (x & 0x200) ? x - 0x400 : x;
  };
  out[0] = (float)sx(p);
  out[1] = (float)sx(p >> 10);
  out[2] = (float)sx(p >> 20);
}

u64 edge_key(u32 a, u32 b) {
  return a < b ? (((u64)a << 32) | b) : (((u64)b << 32) | a);
}

// ---------------------------------------------------------------------------------------------
// Baked time-of-day colour for a midpoint.
//
// The baked lighting is an INDEX into a per-tree palette, so a midpoint cannot simply "interpolate"
// it. Taking one parent's index would leave the vertex colour field continuous but kinked at every
// midpoint (the field would no longer be linear along a split edge), and on a 3 m ground triangle
// that kink is a visible brightness crease — precisely the class of defect this phase has spent
// fifteen rounds removing. So the true 8-palette average is computed and then resolved to an index:
// reuse an existing palette entry when one is close enough (the palette is a dense cloud of the
// level's baked colours, so this is the common case and costs nothing), else append, else — only if
// the tree's 8192-entry LUT is genuinely full — fall back to the nearer parent and record the
// residual so the report can state how much colour error was actually accepted.
// ---------------------------------------------------------------------------------------------
struct PalCache {
  std::unordered_map<std::string, std::vector<u32>> buckets;
  std::vector<std::array<u8, 32>> colours;
  std::unordered_map<u64, u16> blend_cache;  // (ca,cb) -> resolved index
  bool built = false;
};

constexpr int kBucketQ = 24;

std::string bucket_key(const u8* c) {
  char q[32];
  for (int b = 0; b < 32; b++) {
    q[b] = (char)(u8)(c[b] / kBucketQ);
  }
  return std::string(q, 32);
}

bool read_colour32(const PackedTimeOfDay& pal, u32 ci, u8* out) {
  if (ci >= pal.color_count) {
    return false;
  }
  const size_t need = ((size_t)(ci / 4) + 1) * 128;
  if (pal.data.size() < need) {
    return false;
  }
  for (int p = 0; p < kPaletteCount; p++) {
    for (int c = 0; c < 4; c++) {
      out[p * 4 + c] = pal.read((int)ci, p, c);
    }
  }
  return true;
}

void build_pal_cache(PalCache& pc, const PackedTimeOfDay& pal) {
  if (pc.built) {
    return;
  }
  pc.built = true;
  pc.colours.reserve(pal.color_count);
  u8 tmp[32];
  for (u32 ci = 0; ci < pal.color_count; ci++) {
    if (!read_colour32(pal, ci, tmp)) {
      break;
    }
    std::array<u8, 32> a{};
    std::memcpy(a.data(), tmp, 32);
    pc.colours.push_back(a);
    pc.buckets[bucket_key(tmp)].push_back(ci);
  }
}

// Closest palette entry to `want` within `tol` per channel, searching the coarse bucket and its
// neighbours out to `radius` buckets (a blend can land just across a bucket boundary from both
// parents, and when the palette is full and we MUST find something, a wider net is worth its cost).
int find_reusable(const PalCache& pc, const u8* want, u32 tol, int radius = 1) {
  int best = -1;
  u32 best_err = 0xffffffffu;
  u8 probe[32];
  const int span = 2 * radius + 1;
  for (int dq = 0; dq < span * span * span; dq++) {
    // perturb the three most significant channels of palette 0 by -radius..+radius buckets
    std::memcpy(probe, want, 32);
    int d0 = (dq % span) - radius, d1 = ((dq / span) % span) - radius,
        d2 = ((dq / (span * span)) % span) - radius;
    auto shift = [&](int idx, int d) {
      int v = (int)probe[idx] + d * kBucketQ;
      probe[idx] = (u8)std::max(0, std::min(255, v));
    };
    shift(0, d0);
    shift(1, d1);
    shift(2, d2);
    auto it = pc.buckets.find(bucket_key(probe));
    if (it == pc.buckets.end()) {
      continue;
    }
    for (u32 ci : it->second) {
      if (ci >= pc.colours.size()) {
        continue;
      }
      const u8* have = pc.colours[ci].data();
      u32 err = 0;
      bool ok = true;
      for (int b = 0; b < 32; b++) {
        const u32 d = (u32)std::abs((int)have[b] - (int)want[b]);
        if (d > tol) {
          ok = false;
          break;
        }
        err += d;
      }
      if (ok && err < best_err) {
        best_err = err;
        best = (int)ci;
      }
    }
  }
  return best;
}

// ---------------------------------------------------------------------------------------------
// ONE TREE'S REFINEMENT. Extracted verbatim from mesh_presubdivide_level()'s tfrag loop so the
// TIE pass can call the SAME code: same order of operations, same arithmetic, same stat
// increments, same palette handling, same invariant check, same `use_strips = false` at the end.
// `emitted_total` / `budget_hit` are the CALLER's running budget state, so one budget spans a
// whole system's trees exactly as it did before the extraction (and so the tfrag budget and the
// tie budget can be kept strictly separate).
//
// Why one helper is safe for both systems: the split decision for an edge is a pure function of
// its two endpoint POSITIONS and the midpoint is their exact average, with no shared state. That
// is what makes it correct across draw / tree / chunk boundaries in tfrag, and it is exactly what
// makes it correct for a TIE envmap proto, which ships TWO DISJOINT VERTEX COPIES of the same
// surface (extract_tie.cpp calls the strip handler twice: base draw + second "shiny" draw). The
// two copies never see each other, but they hold identical positions (the consolidation snapped
// them), so they mark the same edges, create midpoints at the same positions, and refine into
// topologically identical meshes. No special case is needed, and adding one would be wrong.
// ---------------------------------------------------------------------------------------------
struct TreeGeomRef {
  std::vector<PreloadedVertex>* verts;
  std::vector<u32>* indices;
  std::vector<math::Vector4f>* tangents;
  std::vector<StripDraw>* draws;
  PackedTimeOfDay* pal;
  bool* use_strips;
};

void subdivide_one_tree(const TreeGeomRef& tg,
                        const SubdivConfig& cfg,
                        SubdivStats& st,
                        const std::function<bool(const StripDraw&)>& draw_displaceable,
                        float thr_u2,
                        u64 budget_tris,
                        u64& emitted_total,
                        bool& budget_hit) {
  auto& V = *tg.verts;
  auto& TAN = *tg.tangents;
  const bool have_tan = TAN.size() == V.size();
  PackedTimeOfDay& pal = *tg.pal;
  PalCache pc;
  build_pal_cache(pc, pal);

  st.verts_before += V.size();

  const std::vector<u32> old_idx = std::move(*tg.indices);
  const bool strips = *tg.use_strips;
  std::vector<u32> new_idx;
  new_idx.reserve(old_idx.size() * 4);
  V.reserve(V.size() * 2);
  if (have_tan) {
    TAN.reserve(V.capacity());
  }

  std::unordered_map<u64, u32> mid_cache;
  mid_cache.reserve(old_idx.size());

  // ------------------------------------------------------------------------------------
  // midpoint of an EXISTING edge (a,b). Deterministic, and identical for the copy of this
  // edge that lives in another chunk: every input below is already bit-identical there.
  // ------------------------------------------------------------------------------------
  auto midpoint = [&](u32 a, u32 b) -> u32 {
    const u64 k = edge_key(a, b);
    auto it = mid_cache.find(k);
    if (it != mid_cache.end()) {
      st.midpoints_shared++;
      return it->second;
    }
    const PreloadedVertex va = V[a];
    const PreloadedVertex vb = V[b];
    PreloadedVertex m{};
    m.x = 0.5f * (va.x + vb.x);
    m.y = 0.5f * (va.y + vb.y);
    m.z = 0.5f * (va.z + vb.z);
    m.s = 0.5f * (va.s + vb.s);
    m.t = 0.5f * (va.t + vb.t);
    m.r = (u8)(((u32)va.r + vb.r) / 2);
    m.g = (u8)(((u32)va.g + vb.g) / 2);
    m.b = (u8)(((u32)va.b + vb.b) / 2);
    m.a = (u8)(((u32)va.a + vb.a) / 2);
    // seam weight: LINEAR, so a pinned boundary stays pinned and the field the tess-eval
    // interpolates is bit-for-bit the one it interpolated before the split.
    m.seam_w = (u16)(((u32)va.seam_w + vb.seam_w) / 2);
    // smooth normal
    float na[3], nb[3];
    unpack_nor(va.nor, na);
    unpack_nor(vb.nor, nb);
    float nx = na[0] + nb[0], ny = na[1] + nb[1], nz = na[2] + nb[2];
    const float len = std::sqrt(nx * nx + ny * ny + nz * nz);
    if (len > 1e-6f) {
      m.nor = pack_nor(nx / len, ny / len, nz / len);
    } else {
      m.nor = va.nor;
    }
    // baked colour
    m.color_index = va.color_index;
    if (va.color_index != vb.color_index) {
      const u64 ck = edge_key(va.color_index, vb.color_index);
      auto cit = pc.blend_cache.find(ck);
      if (cit != pc.blend_cache.end()) {
        m.color_index = cit->second;
      } else {
        u8 ca[32], cb[32], avg[32];
        if (read_colour32(pal, va.color_index, ca) && read_colour32(pal, vb.color_index, cb)) {
          for (int i = 0; i < 32; i++) {
            avg[i] = (u8)(((u32)ca[i] + cb[i] + 1) / 2);
          }
          u16 chosen;
          // 6/255 per channel == the consolidation's own "this is a visible step" threshold, so
          // reusing an entry this close cannot introduce a seam, and it keeps the 8192-entry LUT
          // from being exhausted by near-duplicates (which is what forces the lossy path below).
          const int reuse = find_reusable(pc, avg, 6);
          if (reuse >= 0) {
            chosen = (u16)reuse;
            st.col_reused++;
          } else if (pal.color_count + 1 <= kMaxPaletteColors) {
            const u32 ni = pal.color_count;
            const size_t need = ((size_t)(ni / 4) + 1) * 128;
            if (pal.data.size() < need) {
              pal.data.resize(need, 0);
            }
            for (int p = 0; p < kPaletteCount; p++) {
              for (int c = 0; c < 4; c++) {
                pal.read((int)ni, p, c) = avg[p * 4 + c];
              }
            }
            pal.color_count = ni + 1;
            std::array<u8, 32> arr{};
            std::memcpy(arr.data(), avg, 32);
            if (pc.colours.size() <= ni) {
              pc.colours.resize(ni + 1);
            }
            pc.colours[ni] = arr;
            pc.buckets[bucket_key(avg)].push_back(ni);
            chosen = (u16)ni;
            st.col_appended++;
          } else {
            // The tree's 8192-entry LUT is full. Do NOT fall back to a parent index: measured,
            // that costs up to 127/255 of colour error on a single midpoint, which is a bright
            // speck on the ground. Take the CLOSEST colour the palette already holds instead —
            // the palette is a dense sample of this tree's baked lighting, so the nearest entry
            // to an average of two of its own colours is very close to that average.
            const int near = find_reusable(pc, avg, 255, 2);
            if (near >= 0) {
              chosen = (u16)near;
            } else {
              u32 ea = 0, eb = 0;
              for (int i = 0; i < 32; i++) {
                ea += (u32)std::abs((int)ca[i] - (int)avg[i]);
                eb += (u32)std::abs((int)cb[i] - (int)avg[i]);
              }
              chosen = ea <= eb ? va.color_index : vb.color_index;
            }
            st.col_capped++;
          }
          // residual actually accepted, per channel
          u8 got[32];
          if (read_colour32(pal, chosen, got)) {
            double sum = 0;
            double mx = 0;
            for (int i = 0; i < 32; i++) {
              const double d = std::abs((int)got[i] - (int)avg[i]);
              sum += d;
              mx = std::max(mx, d);
            }
            st.col_resid_sum += sum / 32.0;
            st.col_resid_max = std::max(st.col_resid_max, mx);
            st.col_resid_n++;
          }
          pc.blend_cache[ck] = chosen;
          m.color_index = chosen;
        }
      }
    } else {
      st.col_exact++;
    }

    const u32 ni = (u32)V.size();
    V.push_back(m);
    if (have_tan) {
      const auto ta = TAN[a];
      const auto tb = TAN[b];
      math::Vector4f tm(ta.x() + tb.x(), ta.y() + tb.y(), ta.z() + tb.z(), ta.w());
      const float tl = std::sqrt(tm.x() * tm.x() + tm.y() * tm.y() + tm.z() * tm.z());
      if (tl > 1e-6f) {
        tm.x() /= tl;
        tm.y() /= tl;
        tm.z() /= tl;
      } else {
        tm = ta;
      }
      TAN.push_back(tm);
    }
    mid_cache[k] = ni;
    st.midpoints_created++;
    return ni;
  };

  auto elen2 = [&](u32 a, u32 b) -> float {
    const float dx = V[a].x - V[b].x, dy = V[a].y - V[b].y, dz = V[a].z - V[b].z;
    return dx * dx + dy * dy + dz * dz;
  };

  u64 group_tris = 0;
  auto emit = [&](u32 a, u32 b, u32 c) {
    new_idx.push_back(a);
    new_idx.push_back(b);
    new_idx.push_back(c);
    group_tris++;
    emitted_total++;
  };

  // Conformal refinement. The marked set is per-EDGE and derived only from that edge's two
  // endpoint positions, so both triangles sharing an edge mark it identically — with no shared
  // state, and across draw / tree / chunk boundaries just as well as inside one strip.
  std::function<void(u32, u32, u32, int)> split = [&](u32 a, u32 b, u32 c, int depth) {
    if (depth < cfg.max_rounds && emitted_total < budget_tris) {
      const bool m0 = elen2(b, c) > thr_u2;  // edge opposite a
      const bool m1 = elen2(c, a) > thr_u2;  // edge opposite b
      const bool m2 = elen2(a, b) > thr_u2;  // edge opposite c
      const int n = (int)m0 + (int)m1 + (int)m2;
      if (n == 3) {
        st.split_3edge++;
        const u32 ma = midpoint(b, c), mb = midpoint(c, a), mc = midpoint(a, b);
        split(a, mc, mb, depth + 1);
        split(mc, b, ma, depth + 1);
        split(mb, ma, c, depth + 1);
        split(mc, ma, mb, depth + 1);
        return;
      }
      if (n == 2) {
        st.split_2edge++;
        // rotate so the UNMARKED edge is (a,b), i.e. the two marked edges are (b,c) and (c,a)
        u32 A = a, B = b, C = c;
        if (!m0) {  // (b,c) unmarked -> rotate so it becomes (A,B)
          A = b;
          B = c;
          C = a;
        } else if (!m1) {  // (c,a) unmarked
          A = c;
          B = a;
          C = b;
        }
        const u32 mbc = midpoint(B, C);
        const u32 mca = midpoint(C, A);
        // pick the shorter interior diagonal for triangle quality (purely internal choice)
        if (elen2(A, mbc) <= elen2(B, mca)) {
          split(A, B, mbc, depth + 1);
          split(A, mbc, mca, depth + 1);
        } else {
          split(A, B, mca, depth + 1);
          split(B, mbc, mca, depth + 1);
        }
        split(mca, mbc, C, depth + 1);
        return;
      }
      if (n == 1) {
        st.split_1edge++;
        u32 A = a, B = b, C = c;
        if (m1) {  // marked edge is (c,a) -> rotate so the marked edge is (B,C)
          A = b;
          B = c;
          C = a;
        } else if (m2) {  // marked edge is (a,b)
          A = c;
          B = a;
          C = b;
        }
        const u32 m = midpoint(B, C);
        split(A, B, m, depth + 1);
        split(A, m, C, depth + 1);
        return;
      }
    } else if (depth < cfg.max_rounds) {
      budget_hit = true;
    }
    emit(a, b, c);
  };

  bool draw_splits = true;
  auto consider = [&](u32 t0i, u32 t1i, u32 t2i) {
    if (t0i >= V.size() || t1i >= V.size() || t2i >= V.size()) {
      return;
    }
    // edge census (before) — over EVERY tess-eligible triangle, refined or not, so the
    // "over-threshold after" number honestly includes what was deliberately left coarse.
    const float e0 = std::sqrt(elen2(t1i, t2i)) / kUnitsPerMeter;
    const float e1 = std::sqrt(elen2(t2i, t0i)) / kUnitsPerMeter;
    const float e2 = std::sqrt(elen2(t0i, t1i)) / kUnitsPerMeter;
    st.edges_before += 3;
    st.edge_sum_before_m += (double)e0 + e1 + e2;
    st.edge_max_before_m = std::max({st.edge_max_before_m, (double)e0, (double)e1, (double)e2});
    st.edges_over_before += (u64)(e0 > cfg.max_edge_m) + (u64)(e1 > cfg.max_edge_m) +
                            (u64)(e2 > cfg.max_edge_m);
    if (!draw_splits) {
      // material with no displacement source: de-strip it (the tree becomes a triangle list)
      // but do not refine it. Its boundary with a displaceable material is already seam-pinned
      // by the consolidation, so the T-vertices this leaves can never open.
      st.tris_no_height++;
      emit(t0i, t1i, t2i);
      return;
    }
    if (cfg.skip_pinned && V[t0i].seam_w == 0 && V[t1i].seam_w == 0 && V[t2i].seam_w == 0) {
      st.skipped_pinned++;
      emit(t0i, t1i, t2i);
      return;
    }
    split(t0i, t1i, t2i, 0);
  };

  for (auto& draw : *tg.draws) {
    draw_splits = draw_displaceable(draw);
    if (draw_splits) {
      st.draws_eligible++;
    } else {
      st.draws_no_height++;
    }
    const u32 old_first = draw.unpacked.idx_of_first_idx_in_full_buffer;
    draw.unpacked.idx_of_first_idx_in_full_buffer = (u32)new_idx.size();
    u32 run = 0;
    u64 draw_tris = 0;
    for (auto& grp : draw.vis_groups) {
      group_tris = 0;
      const u64 lo = (u64)old_first + run;
      const u64 hi = lo + grp.num_inds;
      if (hi <= old_idx.size()) {
        if (strips) {
          u32 sa = UINT32_MAX, sb = UINT32_MAX;
          int strip_pos = 0;
          for (u64 k = lo; k < hi; k++) {
            const u32 idx = old_idx[k];
            if (idx == UINT32_MAX) {
              sa = sb = UINT32_MAX;
              strip_pos = 0;
              continue;
            }
            if (strip_pos < 2) {
              if (strip_pos == 0) {
                sa = idx;
              } else {
                sb = idx;
              }
              strip_pos++;
            } else {
              const u32 sc = idx;
              u32 t0i, t1i, t2i;
              if ((strip_pos & 1) == 0) {
                t0i = sa;
                t1i = sb;
                t2i = sc;
              } else {
                t0i = sb;
                t1i = sa;
                t2i = sc;
              }
              if (t0i != t1i && t1i != t2i && t0i != t2i) {
                consider(t0i, t1i, t2i);
              }
              sa = sb;
              sb = sc;
              strip_pos++;
            }
          }
        } else {
          for (u64 k = lo; k + 2 < hi; k += 3) {
            const u32 t0i = old_idx[k], t1i = old_idx[k + 1], t2i = old_idx[k + 2];
            if (t0i == UINT32_MAX || t1i == UINT32_MAX || t2i == UINT32_MAX) {
              continue;
            }
            if (t0i != t1i && t1i != t2i && t0i != t2i) {
              consider(t0i, t1i, t2i);
            }
          }
        }
      }
      run += grp.num_inds;
      grp.num_inds = (u32)(group_tris * 3);
      grp.num_tris = (u32)group_tris;
      draw_tris += group_tris;
    }
    draw.num_triangles = (u32)draw_tris;
    st.tris_after += draw_tris;
  }

  // ------------------------------------------------------------------------------------
  // THE RENDERER'S INVARIANT, checked here rather than discovered as an ASSERT on device.
  // background_common.cpp::make_multidraws_from_vis_string() asserts that every draw's
  // idx_of_first_idx_in_full_buffer equals the running sum of all previous draws' vis-group
  // index counts — i.e. the draws must tile the index buffer contiguously, in order, with no
  // gaps. Every rewrite below has to preserve that or the game aborts on the first frame.
  // ------------------------------------------------------------------------------------
  {
    u64 running = 0;
    for (const auto& draw : *tg.draws) {
      if (draw.unpacked.idx_of_first_idx_in_full_buffer != running) {
        st.invariant_failures++;
      }
      for (const auto& grp : draw.vis_groups) {
        running += grp.num_inds;
        if (grp.num_inds != grp.num_tris * 3) {
          st.invariant_failures++;
        }
      }
    }
    if (running != new_idx.size()) {
      st.invariant_failures++;
    }
    for (u32 i : new_idx) {
      if (i >= V.size()) {
        st.invariant_failures++;
        break;
      }
    }
  }

  // edge census (after)
  for (size_t k = 0; k + 2 < new_idx.size(); k += 3) {
    const u32 t0i = new_idx[k], t1i = new_idx[k + 1], t2i = new_idx[k + 2];
    const float e0 = std::sqrt(elen2(t1i, t2i)) / kUnitsPerMeter;
    const float e1 = std::sqrt(elen2(t2i, t0i)) / kUnitsPerMeter;
    const float e2 = std::sqrt(elen2(t0i, t1i)) / kUnitsPerMeter;
    st.edges_after += 3;
    st.edge_sum_after_m += (double)e0 + e1 + e2;
    st.edge_max_after_m = std::max({st.edge_max_after_m, (double)e0, (double)e1, (double)e2});
    st.edges_over_after +=
        (u64)(e0 > cfg.max_edge_m) + (u64)(e1 > cfg.max_edge_m) + (u64)(e2 > cfg.max_edge_m);
  }

  // The SIMD time-of-day interpolator walks WHOLE quads (color_count / 4), so a palette that now
  // ends mid-quad would silently drop the colours we just appended (they would read as black).
  if (pal.color_count) {
    const u32 rounded = std::min(((pal.color_count + 3) / 4) * 4, kMaxPaletteColors);
    const size_t need = ((size_t)rounded / 4) * 128;
    if (pal.data.size() < need) {
      pal.data.resize(need, 0);
    }
    pal.color_count = rounded;
  }

  *tg.indices = std::move(new_idx);
  *tg.use_strips = false;
  st.verts_after += V.size();
  st.trees_subdivided++;
}

// ---------------------------------------------------------------------------------------------
// TIE HAZARD H2 — wind vertices are PROTO-LOCAL, not world space.
//
// TieTree::unpack (TFrag3Data.cpp) only multiplies a vertex by its instance matrix when the matrix
// group's matrix_idx >= 0. The wind path uses matrix_idx == -1 and leaves the vertex exactly as the
// proto authored it; the instance transform is applied per-frame on the GPU from
// wind_matrix_cache. Refining such a vertex against a WORLD-space edge threshold would be
// meaningless, and MOVING one (a midpoint carries a new index, but a fused index could alias) would
// corrupt a wind draw we never rewrote.
//
// This pass only ever walks static_draws, so the two vertex sets should be disjoint. But they are
// not disjoint BY CONSTRUCTION: TieTree::unpack runs fuse_tree_indices over the static index buffer
// only, and that fuse repoints a static index at whichever coincident attribute-identical vertex it
// elected representative — which could in principle be a vertex the wind stream also references. So
// measure it instead of assuming it. Returns the number of vertices referenced by BOTH sets.
// ---------------------------------------------------------------------------------------------
u64 count_wind_static_shared_verts(const TieTree& tree) {
  const size_t nv = tree.unpacked.vertices.size();
  if (!nv || tree.instanced_wind_draws.empty()) {
    return 0;
  }
  std::vector<u8> mark(nv, 0);  // bit0 = referenced by a static draw, bit1 = by a wind draw
  for (const auto& d : tree.static_draws) {
    u64 run = 0;
    const u64 base = d.unpacked.idx_of_first_idx_in_full_buffer;
    for (const auto& grp : d.vis_groups) {
      const u64 lo = base + run;
      const u64 hi = std::min<u64>(lo + grp.num_inds, tree.unpacked.indices.size());
      for (u64 k = lo; k < hi; k++) {
        const u32 i = tree.unpacked.indices[k];
        if (i != UINT32_MAX && i < nv) {
          mark[i] |= 1;
        }
      }
      run += grp.num_inds;
    }
  }
  u64 shared = 0;
  for (const auto& d : tree.instanced_wind_draws) {
    for (u32 i : d.vertex_index_stream) {
      if (i == UINT32_MAX || i >= nv || (mark[i] & 2)) {
        continue;  // already counted this wind vertex
      }
      mark[i] |= 2;
      if (mark[i] & 1) {
        shared++;
      }
    }
  }
  return shared;
}

// ---------------------------------------------------------------------------------------------
// TIE HAZARD H1 — `use_strips` is SHARED with the wind draws.
//
// Tie3.cpp:216 sets `lod_tree[t].draw_mode = tree.use_strips ? GL_TRIANGLE_STRIP : GL_TRIANGLES`,
// and the WIND draw call at Tie3.cpp:1627 passes that SAME `tree.draw_mode` to glDrawElements while
// indexing `instanced_wind_draws[].vertex_index_stream` — which extract_tie.cpp builds
// UNCONDITIONALLY as a UINT32_MAX-restart-delimited triangle STRIP (one restart per strip, pushed at
// extract_tie.cpp:2456). subdivide_one_tree() flips use_strips to false, so without this conversion
// every wind-animated plant in the level would be drawn as GL_TRIANGLES over a strip stream: garbage
// triangles plus a primitive-restart index read as a vertex index.
//
// `instance_groups[j].num` is the INDEX COUNT handed to glDrawElements (Tie3.cpp accumulates it as
// the element offset and passes it as `count`), NOT a triangle count, so it is rewritten to
// 3 * triangles. The stream is segmented sequentially by instance group, so each group is decoded
// from its own contiguous sub-range and the groups stay in order and contiguous — which is what the
// element-offset accumulation in Tie3.cpp requires. The per-draw prefix offsets
// (wind_vertex_index_offsets) are recomputed from the NEW stream sizes at Tie3 setup time
// (Tie3.cpp:294), and the GL upload in LoaderStages.cpp:819 likewise reads the new sizes, so both
// stay consistent for free.
//
// Winding parity and degenerate rejection are byte-for-byte the same rules subdivide_one_tree's own
// strip decoder uses: odd strip positions swap the first two indices, and any triangle with two
// equal indices is dropped.
// ---------------------------------------------------------------------------------------------
void convert_wind_strips_to_lists(TieTree& tree, SubdivStats& st) {
  for (auto& d : tree.instanced_wind_draws) {
    // The groups must tile the stream exactly, in order — Tie3.cpp walks them with a running
    // element offset, so a gap or an overhang would draw another instance's indices. Checked
    // before AND after the rewrite, into the same invariant_failures counter the static draws use.
    {
      u64 sum = 0;
      for (const auto& grp : d.instance_groups) {
        sum += grp.num;
      }
      if (sum != d.vertex_index_stream.size()) {
        st.invariant_failures++;
      }
    }
    std::vector<u32> out;
    out.reserve(d.vertex_index_stream.size() * 3);
    u64 off = 0;
    u64 draw_tris = 0;
    for (auto& grp : d.instance_groups) {
      const u64 lo = off;
      const u64 hi = std::min<u64>(lo + grp.num, d.vertex_index_stream.size());
      off += grp.num;  // advance on the OLD count before rewriting it
      u64 grp_tris = 0;
      u32 sa = UINT32_MAX, sb = UINT32_MAX;
      int strip_pos = 0;
      for (u64 k = lo; k < hi; k++) {
        const u32 idx = d.vertex_index_stream[k];
        if (idx == UINT32_MAX) {
          sa = sb = UINT32_MAX;
          strip_pos = 0;
          continue;
        }
        if (strip_pos < 2) {
          if (strip_pos == 0) {
            sa = idx;
          } else {
            sb = idx;
          }
          strip_pos++;
        } else {
          const u32 sc = idx;
          u32 t0i, t1i, t2i;
          if ((strip_pos & 1) == 0) {
            t0i = sa;
            t1i = sb;
            t2i = sc;
          } else {
            t0i = sb;
            t1i = sa;
            t2i = sc;
          }
          if (t0i != t1i && t1i != t2i && t0i != t2i) {
            out.push_back(t0i);
            out.push_back(t1i);
            out.push_back(t2i);
            grp_tris++;
          }
          sa = sb;
          sb = sc;
          strip_pos++;
        }
      }
      grp.num = (u32)(grp_tris * 3);
      draw_tris += grp_tris;
    }
    d.num_triangles = (u32)draw_tris;
    d.vertex_index_stream = std::move(out);
    {
      u64 sum = 0;
      for (const auto& grp : d.instance_groups) {
        sum += grp.num;
        if (grp.num % 3) {
          st.invariant_failures++;  // a GL_TRIANGLES count must be a multiple of 3
        }
      }
      if (sum != d.vertex_index_stream.size()) {
        st.invariant_failures++;
      }
    }
    st.wind_streams_converted++;
    st.wind_tris_converted += draw_tris;
  }
}

}  // namespace

SubdivConfig mesh_subdiv_config_from_env() {
  SubdivConfig cfg;
  const std::string s = get_setting("debug.opengoal.mesh.subdiv", "OG_MESH_SUBDIV");
  if (!s.empty()) {
    char* end = nullptr;
    const float v = std::strtof(s.c_str(), &end);
    if (end != s.c_str()) {
      cfg.forced_max_edge_m = v;
      if (v > 0.f) {
        cfg.max_edge_m = v;
      }
    }
  }
  const std::string r = get_setting("debug.opengoal.mesh.subdivrounds", "OG_MESH_SUBDIV_ROUNDS");
  if (!r.empty()) {
    const int v = std::atoi(r.c_str());
    if (v >= 0 && v <= 6) {
      cfg.max_rounds = v;
    }
  }
  // ROUND 34 A/B: the fully-pinned-triangle bypass is the ONLY per-triangle escape from the
  // conformal split() in the graded (--all-textures) configuration, and a per-triangle escape is
  // exactly what creates a T-junction: the neighbour bisects the shared edge, this triangle does
  // not. A T-junction breaks edge-manifoldness, which drops the shell out of the EXACT signed-volume
  // tier and into the ballot. This toggle exists so that consequence can be measured rather than
  // argued about; it changes no default.
  const std::string sp = get_setting("debug.opengoal.mesh.subdivskippinned", "OG_MESH_SUBDIV_SKIP_PINNED");
  if (!sp.empty()) {
    if (sp == "1" || sp == "true") {
      cfg.skip_pinned = true;
    } else if (sp == "0") {
      cfg.skip_pinned = false;
    }
  }
  // TIE pass: off by default (see SubdivConfig::include_tie for the measurement behind that).
  const std::string t = get_setting("debug.opengoal.mesh.subdivtie", "OG_MESH_SUBDIV_TIE");
  if (!t.empty()) {
    if (t == "1" || t == "true") {
      cfg.include_tie = true;
    } else if (t == "0") {
      cfg.include_tie = false;
    }
  }
  return cfg;
}

void mesh_presubdivide_level(Level& lev,
                             const SubdivConfig& cfg,
                             SubdivStats* out,
                             const std::function<bool(const Texture&)>& tex_has_height,
                             SubdivStats* out_tie) {
  const auto t0 = std::chrono::high_resolution_clock::now();
  SubdivStats st;
  st.ran = true;

  // Which textures can actually be displaced. Resolved ONCE per level: the predicate hits a
  // directory index, and a level has far fewer textures than draws.
  std::vector<char> tex_displaceable;
  const bool filter_by_height = cfg.require_height_map && (bool)tex_has_height;
  if (filter_by_height) {
    tex_displaceable.resize(lev.textures.size(), 0);
    for (size_t i = 0; i < lev.textures.size(); i++) {
      tex_displaceable[i] = tex_has_height(lev.textures[i]) ? 1 : 0;
    }
  }
  auto draw_displaceable = [&](const StripDraw& d) -> bool {
    if (!filter_by_height) {
      return true;
    }
    if (d.tree_tex_id < 0 || (size_t)d.tree_tex_id >= tex_displaceable.size()) {
      return false;  // animated slot: no static height map to displace with
    }
    return tex_displaceable[(size_t)d.tree_tex_id] != 0;
  };
  // Type-erased ONCE (not per tree): subdivide_one_tree takes it by const std::function&, and
  // converting the lambda at every call site would allocate a std::function per tree.
  const std::function<bool(const StripDraw&)> draw_displaceable_fn = draw_displaceable;

  const float thr_u = cfg.max_edge_m * kUnitsPerMeter;
  const float thr_u2 = thr_u * thr_u;

  // Level-wide triangle budget: counted over the eligible trees only, so a level made mostly of tie
  // geometry cannot borrow headroom it will never use.
  u64 eligible_tris_before = 0;
  for (int g = 0; g < (int)lev.tfrag_trees.size(); g++) {
    if (cfg.only_geom >= 0 && g != cfg.only_geom) {
      continue;
    }
    for (auto& tree : lev.tfrag_trees[g]) {
      if (!tess_opaque_kind(tree.kind) || tree.unpacked.vertices.empty()) {
        continue;
      }
      for (const auto& draw : tree.draws) {
        if (!draw_displaceable(draw)) {
          continue;
        }
        for (const auto& grp : draw.vis_groups) {
          eligible_tris_before += grp.num_tris;
        }
      }
    }
  }
  const u64 budget_tris =
      (u64)std::max(1.0, (double)eligible_tris_before * (double)std::max(1.f, cfg.budget_mult));
  u64 emitted_total = 0;
  bool budget_hit = false;

  for (int g = 0; g < (int)lev.tfrag_trees.size(); g++) {
    if (cfg.only_geom >= 0 && g != cfg.only_geom) {
      continue;
    }
    for (auto& tree : lev.tfrag_trees[g]) {
      st.trees_seen++;
      if (!tess_opaque_kind(tree.kind) || tree.unpacked.vertices.empty() ||
          tree.unpacked.indices.empty()) {
        continue;
      }

      const TreeGeomRef tg{&tree.unpacked.vertices, &tree.unpacked.indices,
                           &tree.unpacked.tangents, &tree.draws, &tree.colors,
                           &tree.use_strips};
      subdivide_one_tree(tg, cfg, st, draw_displaceable_fn, thr_u2, budget_tris, emitted_total,
                         budget_hit);
    }
  }

  st.tris_before = eligible_tris_before;
  st.budget_stops = budget_hit ? 1 : 0;
  st.elapsed_ms =
      std::chrono::duration<double, std::milli>(std::chrono::high_resolution_clock::now() - t0)
          .count();
  if (out) {
    *out = st;
  }

  // ==============================================================================================
  // TIE. OFF BY DEFAULT (SubdivConfig::include_tie documents exactly why: Tie3 has no tessellation
  // program, so TIE relief comes from per-pixel POM, which is resolution-bound and not
  // triangle-bound). Everything below is strictly additive: it runs AFTER the tfrag pass is fully
  // finished and *out has already been written, on its OWN stats object, its OWN triangle budget
  // and its OWN emitted/budget-hit counters, so the tfrag geometry above cannot be perturbed by one
  // byte whether this block runs or not.
  //
  // (H3) Envmap protos ship TWO DISJOINT VERTEX COPIES of the same surface (extract_tie.cpp calls
  // handle_draw_for_strip twice for an envmapped proto: the base draw and the "shiny" second draw,
  // each pushing its own packed vertices). No special case is needed and adding one would be wrong:
  // the split decision for an edge is a pure function of its two endpoint POSITIONS, and the
  // consolidation already snapped both copies to bit-identical positions, so the two copies mark the
  // same edges, place their midpoints at the same positions and refine into topologically identical
  // meshes without ever communicating. (Where TieTree::unpack's fuse actually merged the copies into
  // shared indices, the per-tree midpoint cache makes them literally the same vertex.)
  //
  // (H4) The renderer's draw-contiguity ASSERT applies to TIE too (Tie3.cpp:661 ->
  // background_common.cpp:2978 `ASSERT(sanity_check == iidx)` accumulating grp.num_inds).
  // subdivide_one_tree re-checks it into `invariant_failures`, which lands in the TIE stats below.
  // No draw is reordered, inserted or removed, so `category_draw_indices` — which slices
  // static_draws by position — stays valid: only index ranges and vis-group counts are rewritten in
  // place.
  // ==============================================================================================
  if (cfg.include_tie) {
    const auto t_tie0 = std::chrono::high_resolution_clock::now();
    SubdivStats tst;
    tst.ran = true;

    // TIE's own budget, counted over TIE-eligible triangles only.
    u64 tie_eligible_tris_before = 0;
    for (int g = 0; g < (int)lev.tie_trees.size(); g++) {
      if (cfg.only_geom_tie >= 0 && g != cfg.only_geom_tie) {
        continue;
      }
      for (auto& tree : lev.tie_trees[g]) {
        if (tree.unpacked.vertices.empty()) {
          continue;
        }
        for (const auto& draw : tree.static_draws) {
          if (!draw_displaceable(draw)) {
            continue;
          }
          for (const auto& grp : draw.vis_groups) {
            tie_eligible_tris_before += grp.num_tris;
          }
        }
      }
    }
    const u64 tie_budget_tris = (u64)std::max(
        1.0, (double)tie_eligible_tris_before * (double)std::max(1.f, cfg.budget_mult));
    u64 tie_emitted_total = 0;
    bool tie_budget_hit = false;

    for (int g = 0; g < (int)lev.tie_trees.size(); g++) {
      if (cfg.only_geom_tie >= 0 && g != cfg.only_geom_tie) {
        continue;
      }
      for (auto& tree : lev.tie_trees[g]) {
        tst.trees_seen++;
        if (tree.unpacked.vertices.empty() || tree.unpacked.indices.empty()) {
          continue;
        }
        // H2: proof obligation, checked BEFORE the rewrite while the index buffer is still the
        // original one. A tree that shares a vertex between a static draw and a wind draw is left
        // completely untouched rather than silently corrupted.
        const u64 shared = count_wind_static_shared_verts(tree);
        if (shared) {
          tst.tie_wind_static_shared_verts += shared;
          tst.trees_skipped_wind_shared++;
          continue;
        }
        // H1: only convert the wind streams if THIS pass is the thing that flips the flag. A tree
        // that already reported use_strips == false was already being drawn as GL_TRIANGLES, and
        // re-decoding its wind stream as a strip would be wrong.
        const bool was_strips = tree.use_strips;
        const TreeGeomRef tg{&tree.unpacked.vertices, &tree.unpacked.indices,
                             &tree.unpacked.tangents, &tree.static_draws,
                             &tree.colors,            &tree.use_strips};
        subdivide_one_tree(tg, cfg, tst, draw_displaceable_fn, thr_u2, tie_budget_tris,
                           tie_emitted_total, tie_budget_hit);
        if (was_strips && !tree.use_strips) {
          convert_wind_strips_to_lists(tree, tst);
        }
      }
    }

    tst.tris_before = tie_eligible_tris_before;
    tst.budget_stops = tie_budget_hit ? 1 : 0;
    tst.elapsed_ms =
        std::chrono::duration<double, std::milli>(std::chrono::high_resolution_clock::now() - t_tie0)
            .count();
    if (out_tie) {
      *out_tie = tst;
    }
  }
}

std::string format_subdiv_stats(const SubdivStats& s,
                                const SubdivConfig& cfg,
                                const char* system_label) {
  if (!s.ran) {
    return fmt::format("-- PRE-SUBDIVISION ({}) -- not run\n", system_label);
  }
  std::string extra;
  if (std::strcmp(system_label, "tfrag") != 0) {
    // TIE-only hazards, printed where the eye already is (see SubdivStats for the full rationale).
    extra = fmt::format(
        "   wind: streams converted strip->list={} ({} tris)  static/wind shared verts={} (must be "
        "0)  trees skipped for sharing={}\n",
        s.wind_streams_converted, s.wind_tris_converted, s.tie_wind_static_shared_verts,
        s.trees_skipped_wind_shared);
  }
  return fmt::format(
      "-- PRE-SUBDIVISION ({}, tess-eligible kinds) -- max_edge={:.2f}m rounds={} budget={:.0f}x "
      "skip_pinned={}\n"
      "   trees {}/{}  tris {} -> {} ({:.2f}x)  verts {} -> {} ({:.2f}x)  midpoints {} (+{} shared)\n"
      "   splits 1-edge={} 2-edge={} 3-edge(1-to-4)={}  pinned-skipped={}  budget_stop={} "
      "draw-contiguity invariant_failures={} (must be 0)\n"
      "   draws with a height map={}  without={} (their {} tris left coarse: nothing to displace)\n"
      "   edge len m: mean {:.3f} -> {:.3f}  max {:.2f} -> {:.2f}  over-threshold {} -> {}\n"
      "   midpoint colour: identical={} reused={} appended={} capped={} residual mean={:.2f} "
      "max={:.0f} (0-255/ch)\n"
      "   elapsed {:.1f} ms\n"
      "{}",
      system_label, cfg.max_edge_m, cfg.max_rounds, cfg.budget_mult, cfg.skip_pinned ? 1 : 0,
      s.trees_subdivided,
      s.trees_seen, s.tris_before, s.tris_after,
      s.tris_before ? (double)s.tris_after / s.tris_before : 0.0, s.verts_before, s.verts_after,
      s.verts_before ? (double)s.verts_after / s.verts_before : 0.0, s.midpoints_created,
      s.midpoints_shared, s.split_1edge, s.split_2edge, s.split_3edge, s.skipped_pinned,
      s.budget_stops, s.invariant_failures, s.draws_eligible, s.draws_no_height, s.tris_no_height,
      s.mean_edge_before_m(), s.mean_edge_after_m(), s.edge_max_before_m,
      s.edge_max_after_m, s.edges_over_before, s.edges_over_after, s.col_exact, s.col_reused,
      s.col_appended, s.col_capped, s.col_resid_mean(), s.col_resid_max, s.elapsed_ms, extra);
}

}  // namespace tfrag3
