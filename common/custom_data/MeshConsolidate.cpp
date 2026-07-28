#include "MeshConsolidate.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <numeric>
#include <thread>
#include <unordered_map>

#include "Tfrag3Data.h"

#include "common/log/log.h"
#include "common/util/FileUtil.h"
#include "common/util/compress.h"
#include "common/util/md5.h"

#include "fmt/format.h"

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace tfrag3 {
namespace {

constexpr float kUnitsPerMeter = 4096.f;
constexpr int kSysTfrag = 0;
constexpr int kSysTie = 1;
constexpr int kSysShrub = 2;
constexpr u32 kNoTex = 0xffffffffu;
constexpr int kPaletteCount = 8;
constexpr u32 kMaxPaletteColors = 8192;  // == TFragment/Tie3/Shrub::TIME_OF_DAY_COLOR_COUNT

// ---------------------------------------------------------------------------------------------
// small helpers
// ---------------------------------------------------------------------------------------------

u32 pack_nor(const math::Vector3f& n) {
  auto sat = [](float f) -> u32 {
    int v = (int)std::lround(f * 511.f);
    v = std::max(-511, std::min(511, v));
    return (u32)v & 0x3ffu;
  };
  return sat(n.x()) | (sat(n.y()) << 10) | (sat(n.z()) << 20);
}

math::Vector3f unpack_nor(u32 p) {
  auto sx = [](u32 v) -> int {
    int x = (int)(v & 0x3ffu);
    return (x & 0x200) ? x - 0x400 : x;
  };
  math::Vector3f n((float)sx(p), (float)sx(p >> 10), (float)sx(p >> 20));
  float l = n.length();
  return l > 1e-6f ? n * (1.f / l) : math::Vector3f(0.f, 0.f, 0.f);
}

u64 cell_key(s64 cx, s64 cy, s64 cz) {
  return ((u64)(u32)(cx & 0x1FFFFF) << 42) | ((u64)(u32)(cy & 0x1FFFFF) << 21) |
         (u64)(u32)(cz & 0x1FFFFF);
}

// undirected edge key over two 32-bit ids (vertex ids or group ids)
u64 edge_key(u32 a, u32 b) {
  return a < b ? (((u64)a << 32) | b) : (((u64)b << 32) | a);
}

float deg_between(const math::Vector3f& a, const math::Vector3f& b) {
  float d = a.dot(b);
  d = std::max(-1.f, std::min(1.f, d));
  return std::acos(d) * 180.f / 3.14159265358979f;
}

void hist_add_deg(MeshDeltaHist& h, double v) {
  h.n++;
  h.sum += v;
  h.max = std::max(h.max, v);
  if (v < 1.0) {
    h.bucket[0]++;
  } else if (v < 5.0) {
    h.bucket[1]++;
  } else if (v < 15.0) {
    h.bucket[2]++;
  } else if (v < 45.0) {
    h.bucket[3]++;
  } else {
    h.bucket[4]++;
  }
}

void hist_add_col(MeshDeltaHist& h, double v) {
  h.n++;
  h.sum += v;
  h.max = std::max(h.max, v);
  if (v < 2.0) {
    h.bucket[0]++;
  } else if (v < 8.0) {
    h.bucket[1]++;
  } else if (v < 24.0) {
    h.bucket[2]++;
  } else if (v < 64.0) {
    h.bucket[3]++;
  } else {
    h.bucket[4]++;
  }
}

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

// ---------------------------------------------------------------------------------------------
// vertex layout abstraction: tfrag/tie use PreloadedVertex, shrub uses ShrubGpuVertex. Both are 32
// bytes with position at offset 0; everything else is reached through these per-system offsets so a
// single global pass can cover all three systems without a second copy of the algorithm.
// ---------------------------------------------------------------------------------------------
struct VLayout {
  u32 nor_off, cidx_off, seam_off, st_off;
};
const VLayout kLayoutPreloaded = {
    (u32)offsetof(PreloadedVertex, nor), (u32)offsetof(PreloadedVertex, color_index),
    (u32)offsetof(PreloadedVertex, seam_w), (u32)offsetof(PreloadedVertex, s)};
const VLayout kLayoutShrub = {
    (u32)offsetof(ShrubGpuVertex, nor), (u32)offsetof(ShrubGpuVertex, color_index),
    (u32)offsetof(ShrubGpuVertex, seam_w), (u32)offsetof(ShrubGpuVertex, s)};

struct GTree {
  int system = 0;
  u32 gbase = 0;
  u32 gcount = 0;
  const std::vector<u32>* indices = nullptr;
  bool use_strips = true;
  PackedTimeOfDay* colors = nullptr;
  const VLayout* layout = nullptr;
  // round-22: the per-vertex MikkTSpace tangent array of this tree (TfragTree/TieTree::unpacked
  // .tangents). It lives OUTSIDE the vertex struct, so it cannot be reached through VLayout. Shrub
  // has no tangent array at all, so this stays null there. Only ever used when its size matches
  // gcount — a tree whose tangents were not reconstructed must be left alone, not indexed into.
  std::vector<math::Vector4f>* tangents = nullptr;
};

// ---------------------------------------------------------------------------------------------
// union-find (path halving, union by index — deterministic: always attach to the LOWER root, so the
// group representative is reproducible run-to-run and device-vs-offline)
// ---------------------------------------------------------------------------------------------
struct UnionFind {
  std::vector<u32> p;
  // Per-ROOT axis-aligned bounds of the group. A weld is a TRANSITIVE relation, so a naive union-find
  // over "within epsilon" chains: A~B, B~C, C~D ... can drag vertices arbitrarily far apart into one
  // group (measured on village1: a 3 cm tolerance produced groups 27 cm across, which then snapped
  // real geometry 27 cm out of place, made most edges non-manifold, and shredded the face-adjacency
  // graph). Capping the group's DIAMETER is what makes an exhaustive weld safe: a group may never
  // grow bigger than the tolerance it was welded at.
  std::vector<math::Vector3f> lo, hi;
  explicit UnionFind(const std::vector<math::Vector3f>& gp) : p(gp.size()), lo(gp), hi(gp) {
    std::iota(p.begin(), p.end(), 0u);
  }
  u32 find(u32 x) {
    while (p[x] != x) {
      p[x] = p[p[x]];
      x = p[x];
    }
    return x;
  }
  bool unite(u32 a, u32 b, float diameter_cap) {
    a = find(a);
    b = find(b);
    if (a == b) {
      return false;
    }
    math::Vector3f nlo(std::min(lo[a].x(), lo[b].x()), std::min(lo[a].y(), lo[b].y()),
                       std::min(lo[a].z(), lo[b].z()));
    math::Vector3f nhi(std::max(hi[a].x(), hi[b].x()), std::max(hi[a].y(), hi[b].y()),
                       std::max(hi[a].z(), hi[b].z()));
    if ((nhi - nlo).length() > diameter_cap) {
      return false;  // would over-grow the group: refuse, so a chain cannot smear the mesh
    }
    // always attach to the LOWER root: deterministic representative, device == offline
    const u32 keep = a < b ? a : b;
    const u32 drop = a < b ? b : a;
    p[drop] = keep;
    lo[keep] = nlo;
    hi[keep] = nhi;
    return true;
  }
};

// Walk every triangle of an index buffer, honouring the strip / plain-list convention used by the
// unpackers (UINT32_MAX primitive restart, alternating winding inside a strip).
template <typename F>
void for_each_tri(const std::vector<u32>& idx, bool use_strips, F&& emit) {
  if (use_strips) {
    u32 a = UINT32_MAX, b = UINT32_MAX, k = 0;
    for (u32 vi : idx) {
      if (vi == UINT32_MAX) {
        a = b = UINT32_MAX;
        k = 0;
        continue;
      }
      if (a != UINT32_MAX && b != UINT32_MAX) {
        if ((k & 1) != 0) {
          emit(b, a, vi);
        } else {
          emit(a, b, vi);
        }
      }
      a = b;
      b = vi;
      k++;
    }
  } else {
    for (size_t t = 0; t + 2 < idx.size(); t += 3) {
      if (idx[t] == UINT32_MAX || idx[t + 1] == UINT32_MAX || idx[t + 2] == UINT32_MAX) {
        continue;
      }
      emit(idx[t], idx[t + 1], idx[t + 2]);
    }
  }
}

// A collision-mesh lookup used as the ORIENTATION AUTHORITY: the walkable side of the world is the
// side the collision normal points to, so a rendered face whose normal opposes it is inward-facing.
struct CollisionAuthority {
  std::unordered_map<u64, std::vector<u32>> cells;
  const std::vector<CollisionMesh::Vertex>* verts = nullptr;
  float cell = 1.0f * kUnitsPerMeter;
  float accept2 = (1.5f * kUnitsPerMeter) * (1.5f * kUnitsPerMeter);

  void build(const CollisionMesh& mesh) {
    verts = &mesh.vertices;
    cells.reserve(mesh.vertices.size() / 4 + 1);
    for (u32 i = 0; i < mesh.vertices.size(); i++) {
      const auto& v = mesh.vertices[i];
      cells[cell_key((s64)std::floor(v.x / cell), (s64)std::floor(v.y / cell),
                     (s64)std::floor(v.z / cell))]
          .push_back(i);
    }
  }

  // returns false if no collision vertex is within 1.5 m (no authority here)
  bool nearest_normal(const math::Vector3f& p, math::Vector3f* out) const {
    if (!verts || verts->empty()) {
      return false;
    }
    const s64 cx = (s64)std::floor(p.x() / cell);
    const s64 cy = (s64)std::floor(p.y() / cell);
    const s64 cz = (s64)std::floor(p.z() / cell);
    float best = accept2;
    int best_i = -1;
    for (int dz = -1; dz <= 1; dz++) {
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          auto it = cells.find(cell_key(cx + dx, cy + dy, cz + dz));
          if (it == cells.end()) {
            continue;
          }
          for (u32 ci : it->second) {
            const auto& cv = (*verts)[ci];
            math::Vector3f d(cv.x - p.x(), cv.y - p.y(), cv.z - p.z());
            float d2 = d.dot(d);
            if (d2 < best) {
              best = d2;
              best_i = (int)ci;
            }
          }
        }
      }
    }
    if (best_i < 0) {
      return false;
    }
    const auto& cv = (*verts)[best_i];
    math::Vector3f n((float)cv.nx, (float)cv.ny, (float)cv.nz);
    float l = n.length();
    if (!(l > 1e-6f)) {
      return false;
    }
    *out = n * (1.f / l);
    return true;
  }
};

// Gather every renderable vertex of every system into one flat, DETERMINISTIC global list. Both the
// consolidation pass and the precompute sidecar walk the level through this one function, so the
// global vertex numbering the sidecar stores is guaranteed to mean the same thing when it is applied.
void gather_level(Level& lev,
                  bool do_shrub,
                  std::vector<GTree>& trees,
                  std::vector<u8*>& gvert,
                  std::vector<u32>* gtree,
                  std::vector<math::Vector3f>* gp) {
  auto add_tree = [&](int system, void* vdata, size_t vcount, size_t vstride,
                      const std::vector<u32>* indices, bool strips, PackedTimeOfDay* colors,
                      const VLayout* layout, std::vector<math::Vector4f>* tangents) {
    if (vcount == 0 || !indices) {
      return;
    }
    GTree t;
    t.system = system;
    t.gbase = (u32)gvert.size();
    t.gcount = (u32)vcount;
    t.indices = indices;
    t.use_strips = strips;
    t.colors = colors;
    t.layout = layout;
    t.tangents = tangents;
    trees.push_back(t);
    const u32 tid = (u32)trees.size() - 1;
    u8* base = (u8*)vdata;
    for (size_t i = 0; i < vcount; i++) {
      u8* v = base + i * vstride;
      gvert.push_back(v);
      if (gtree) {
        gtree->push_back(tid);
      }
      if (gp) {
        gp->emplace_back(((float*)v)[0], ((float*)v)[1], ((float*)v)[2]);
      }
    }
  };
  for (auto& geom : lev.tfrag_trees) {
    for (auto& t : geom) {
      add_tree(kSysTfrag, t.unpacked.vertices.data(), t.unpacked.vertices.size(),
               sizeof(PreloadedVertex), &t.unpacked.indices, t.use_strips, &t.colors,
               &kLayoutPreloaded, &t.unpacked.tangents);
    }
  }
  for (auto& geom : lev.tie_trees) {
    for (auto& t : geom) {
      add_tree(kSysTie, t.unpacked.vertices.data(), t.unpacked.vertices.size(),
               sizeof(PreloadedVertex), &t.unpacked.indices, t.use_strips, &t.colors,
               &kLayoutPreloaded, &t.unpacked.tangents);
    }
  }
  if (do_shrub) {
    for (auto& t : lev.shrub_trees) {
      add_tree(kSysShrub, t.unpacked.vertices.data(), t.unpacked.vertices.size(),
               sizeof(ShrubGpuVertex), &t.indices, true, &t.time_of_day_colors, &kLayoutShrub,
               /*tangents=*/nullptr);  // shrub has no tangent array
    }
  }
}

// tiny little-endian byte-stream helpers for the sidecar
struct BW {
  std::vector<u8> d;
  void raw(const void* p, size_t n) {
    const u8* b = (const u8*)p;
    d.insert(d.end(), b, b + n);
  }
  void u32v(u32 v) { raw(&v, 4); }
  void u64v(u64 v) { raw(&v, 8); }
  void u8v(u8 v) { d.push_back(v); }
};
struct BR {
  const u8* p;
  const u8* end;
  bool ok = true;
  bool raw(void* out, size_t n) {
    if (!ok || (size_t)(end - p) < n) {
      ok = false;
      return false;
    }
    std::memcpy(out, p, n);
    p += n;
    return true;
  }
  u32 u32v() {
    u32 v = 0;
    raw(&v, 4);
    return v;
  }
  u64 u64v() {
    u64 v = 0;
    raw(&v, 8);
    return v;
  }
  u8 u8v() {
    u8 v = 0;
    raw(&v, 1);
    return v;
  }
};

constexpr u32 kBakeMagic = 0x4E4F434Du;  // 'MCON'
// v2 (round 22): the orientation rule changed, so every nor[] in a v1 sidecar is a stale answer.
// v3 (round 28): the orientation rule changed AGAIN — a component the collision mesh cannot reach
//   is now decided by the geometric SECOND AUTHORITY (signed volume / outward ray parity) instead
//   of silently keeping its authored winding, so every nor[] in a v1 OR v2 sidecar is stale too.
// v4 (round 29): the orientation rule changed a THIRD time -- the collision authority now has to
//   pass a competence filter (|n.dot(collision_normal)| > 0.35) and an area-weighted confidence
//   test before it may outrank the geometric cascade, so every nor[] in a v1/v2/v3 sidecar is a
//   stale answer for every component that used to be decided by orthogonal floor-normal noise.
// v5 (round 31): the orientation rule changed a FOURTH time -- the PRECEDENCE itself moved. A
//   PER-FACE GEOMETRIC OUTWARD VOTE (escape rays cast from both sides of every face, see
//   kMeshBitGeomOrient) is now the FIRST authority, ahead of the signed volume, ahead of the ray
//   parity and ahead of the walkable COLLISION MESH, which is demoted to last resort. So every
//   nor[] in a v1/v2/v3/v4 sidecar is a stale answer for every component the collision mesh used to
//   claim while pointing the wrong way -- the sage-hut ground-floor wall and the roof over it.
//   THE BUMP IS THE DELIVERY: the sidecar fingerprint is COUNTS-only (tree/vert/index/colour
//   counts), so it still matches an fr3 whose normals were re-baked, and without a version bump
//   every device would blit the OLD normals back over the fix and the whole round would ship as a
//   no-op. That has already cost this project two rounds; do not remove this.
// mesh_consolidate_apply_bake() rejects a version mismatch and the caller falls back to the live
// pass, so the 26 baked jak1 levels cannot silently keep the old (inverted) normals.
// v6 (round 31, second half): the orientation rule gained a PER-FACE RESIDUAL REPAIR on top of the
//   per-component decision, and -- the part that actually changes every sidecar -- tools/mesh_audit
//   now sets kMeshBitGeomOrient for the bake BY DEFAULT. v5 was written by a bake that never once
//   ran the geometric vote (no script in the tree set OG_MESH_BITS), so a v5 sidecar is a
//   collision-first answer wearing a round-31 version number. Bump so it cannot be mistaken for one.
constexpr u32 kBakeVersion = 6;

// Structural fingerprint: if the fr3 is rebuilt with different geometry, the sidecar must be
// rejected rather than silently smeared over the wrong vertices. ONE function writes the layout and
// ONE reads it, both over the same TreeFp form, so the writer and the checker cannot drift apart.
std::vector<MeshBakeData::TreeFp> fingerprint_of(const std::vector<GTree>& trees) {
  std::vector<MeshBakeData::TreeFp> fp;
  fp.reserve(trees.size());
  for (const auto& t : trees) {
    fp.push_back({(u8)t.system, t.gcount, (u32)t.indices->size(),
                  t.colors ? t.colors->color_count : 0});
  }
  return fp;
}

void write_fingerprint(BW& w,
                       const std::string& name,
                       const std::vector<MeshBakeData::TreeFp>& fp,
                       u64 n) {
  w.u32v((u32)name.size());
  w.raw(name.data(), name.size());
  w.u32v((u32)fp.size());
  for (const auto& t : fp) {
    w.u8v(t.system);
    w.u32v(t.vert_count);
    w.u32v(t.index_count);
    w.u32v(t.orig_color_count);
  }
  w.u64v(n);
}

bool check_fingerprint(BR& r,
                       const std::string& name,
                       const std::vector<MeshBakeData::TreeFp>& fp,
                       u64 n) {
  const u32 nl = r.u32v();
  if (!r.ok || nl != name.size()) {
    return false;
  }
  std::string got(nl, '\0');
  if (!r.raw(got.data(), nl) || got != name) {
    return false;
  }
  if (r.u32v() != fp.size()) {
    return false;
  }
  for (const auto& t : fp) {
    if (r.u8v() != t.system || r.u32v() != t.vert_count || r.u32v() != t.index_count ||
        r.u32v() != t.orig_color_count) {
      return false;
    }
  }
  return r.ok && r.u64v() == n;
}

}  // namespace

// ---------------------------------------------------------------------------------------------

MeshConsolidateConfig mesh_consolidate_config_from_env() {
  MeshConsolidateConfig cfg;
  auto f = [](const std::string& s, float def) {
    if (s.empty()) {
      return def;
    }
    try {
      return std::stof(s);
    } catch (...) {
      return def;
    }
  };
  auto u = [](const std::string& s, u32 def) {
    if (s.empty()) {
      return def;
    }
    try {
      return (u32)std::stoul(s);
    } catch (...) {
      return def;
    }
  };
  cfg.weld_m = f(get_setting("debug.opengoal.mesh.weld_m", "OG_MESH_WELD_M"), cfg.weld_m);
  cfg.wide_scale = f(get_setting("debug.opengoal.mesh.wide", "OG_MESH_WIDE"), cfg.wide_scale);
  cfg.crease_deg = f(get_setting("debug.opengoal.mesh.crease", "OG_MESH_CREASE"), cfg.crease_deg);
  cfg.col_blend_threshold =
      u(get_setting("debug.opengoal.mesh.colthr", "OG_MESH_COLTHR"), cfg.col_blend_threshold);
  cfg.bits = u(get_setting("debug.opengoal.mesh.bits", "OG_MESH_BITS"), cfg.bits);
  cfg.weld_m = std::max(0.001f, std::min(1.0f, cfg.weld_m));
  cfg.wide_scale = std::max(1.0f, std::min(32.0f, cfg.wide_scale));
  cfg.crease_deg = std::max(1.0f, std::min(179.0f, cfg.crease_deg));
  return cfg;
}

void mesh_consolidate(Level& lev,
                      const MeshConsolidateConfig& cfg,
                      MeshAuditReport* out,
                      MeshBakeData* bake) {
  const auto t_start = std::chrono::steady_clock::now();
  MeshAuditReport rep;
  rep.level_name = lev.level_name;

  const float weld_cell = cfg.weld_m * kUnitsPerMeter;
  const float weld_tol2 = weld_cell * weld_cell;
  const float wide_cell = weld_cell * cfg.wide_scale;
  const float wide_tol2 = wide_cell * wide_cell;
  const float crease_cos = std::cos(cfg.crease_deg * 3.14159265358979f / 180.f);
  const bool do_shrub = (cfg.bits & kMeshBitNoShrub) == 0;

  // =============================================================================================
  // 0. GATHER every renderable vertex of every system into one global list.
  // =============================================================================================
  std::vector<GTree> trees;
  std::vector<math::Vector3f> gp;
  std::vector<u32> gtree;
  std::vector<u8*> gvert;
  gather_level(lev, do_shrub, trees, gvert, &gtree, &gp);
  for (const auto& t : trees) {
    (t.system == kSysTfrag ? rep.tfrag : (t.system == kSysTie ? rep.tie : rep.shrub)).trees++;
  }
  // snapshot the structural fingerprint + the ORIGINAL palette sizes before anything mutates them
  std::vector<u32> orig_color_count(trees.size(), 0);
  for (size_t t = 0; t < trees.size(); t++) {
    orig_color_count[t] = trees[t].colors ? trees[t].colors->color_count : 0;
    if (bake) {
      bake->tree_fp.push_back({(u8)trees[t].system, trees[t].gcount,
                               (u32)trees[t].indices->size(), orig_color_count[t]});
    }
  }

  const size_t N = gp.size();
  if (N == 0 || trees.empty()) {
    if (out) {
      *out = rep;
    }
    return;
  }

  auto sys_of = [&](size_t i) { return trees[gtree[i]].system; };
  auto nor_ptr = [&](size_t i) -> u32* {
    return (u32*)(gvert[i] + trees[gtree[i]].layout->nor_off);
  };
  auto cidx_ptr = [&](size_t i) -> u16* {
    return (u16*)(gvert[i] + trees[gtree[i]].layout->cidx_off);
  };
  auto seam_ptr = [&](size_t i) -> u16* {
    return (u16*)(gvert[i] + trees[gtree[i]].layout->seam_off);
  };
  // round-22: the tangent lives in a PARALLEL array, not in the vertex struct. Returns null for a
  // system/tree with no tangents (shrub, or a tree whose reconstruction was skipped).
  auto tangent_ptr = [&](size_t i) -> math::Vector4f* {
    const GTree& t = trees[gtree[i]];
    if (!t.tangents || t.tangents->size() != (size_t)t.gcount) {
      return nullptr;
    }
    return t.tangents->data() + (i - t.gbase);
  };
  auto sys_audit = [&](int s) -> MeshAuditSystem& {
    return s == kSysTfrag ? rep.tfrag : (s == kSysTie ? rep.tie : rep.shrub);
  };

  for (size_t i = 0; i < N; i++) {
    sys_audit(sys_of(i)).verts++;
  }

  // =============================================================================================
  // 1. FACES. One flat global triangle list (global vertex ids) across every tree of every system.
  // =============================================================================================
  std::vector<std::array<u32, 3>> faces;
  std::vector<u8> referenced(N, 0);
  {
    size_t est = 0;
    for (const auto& t : trees) {
      est += t.indices->size();
    }
    faces.reserve(est / 2 + 16);
  }
  std::vector<u32> face_sys;
  for (const auto& t : trees) {
    const u32 gb = t.gbase;
    const u32 gc = t.gcount;
    for_each_tri(*t.indices, t.use_strips, [&](u32 a, u32 b, u32 c) {
      if (a >= gc || b >= gc || c >= gc || a == b || b == c || a == c) {
        return;  // degenerate or out-of-range (defensive: never trust an authored index stream)
      }
      const u32 ga = gb + a, gbb = gb + b, gcc = gb + c;
      const math::Vector3f e0 = gp[gbb] - gp[ga];
      const math::Vector3f e1 = gp[gcc] - gp[ga];
      const math::Vector3f n = e0.cross(e1);
      if (!(n.length() > 1e-3f)) {
        return;  // zero-area
      }
      faces.push_back({ga, gbb, gcc});
      face_sys.push_back((u32)t.system);
      referenced[ga] = referenced[gbb] = referenced[gcc] = 1;
    });
  }
  const size_t F = faces.size();
  for (size_t f = 0; f < F; f++) {
    sys_audit((int)face_sys[f]).tris++;
  }
  for (size_t i = 0; i < N; i++) {
    if (referenced[i]) {
      sys_audit(sys_of(i)).verts_referenced++;
    }
  }
  if (F == 0) {
    if (out) {
      *out = rep;
    }
    return;
  }

  auto face_normal = [&](size_t f) {
    const auto& t = faces[f];
    return (gp[t[1]] - gp[t[0]]).cross(gp[t[2]] - gp[t[0]]);
  };

  // =============================================================================================
  // 2. PER-VERTEX MATERIAL. Which texture(s) a vertex is drawn with — needed for the seam rule: a
  //    boundary between a draw whose texture HAS a height map and one that does not can never
  //    displace consistently, so displacement must fade to zero there.
  // =============================================================================================
  std::vector<u32> gtex(N, kNoTex);
  std::vector<u8> gtex_multi(N, 0);
  {
    auto mark = [&](u32 gvi, u32 tex) {
      if (gtex[gvi] == kNoTex) {
        gtex[gvi] = tex;
      } else if (gtex[gvi] != tex) {
        gtex_multi[gvi] = 1;
      }
    };
    u32 tid = 0;
    auto mark_strip_draws = [&](const std::vector<StripDraw>& draws, u32 gbase, u32 gcount) {
      for (const auto& d : draws) {
        const u32 tex = (u32)d.tree_tex_id;
        for (const auto& r : d.runs) {
          for (u32 k = 0; k < r.length; k++) {
            const u32 li = r.vertex0 + k;
            if (li < gcount) {
              mark(gbase + li, tex);
            }
          }
        }
        for (u32 li : d.plain_indices) {
          if (li != UINT32_MAX && li < gcount) {
            mark(gbase + li, tex);
          }
        }
      }
    };
    for (auto& geom : lev.tfrag_trees) {
      for (auto& t : geom) {
        if (t.unpacked.vertices.empty()) {
          continue;
        }
        mark_strip_draws(t.draws, trees[tid].gbase, trees[tid].gcount);
        tid++;
      }
    }
    for (auto& geom : lev.tie_trees) {
      for (auto& t : geom) {
        if (t.unpacked.vertices.empty()) {
          continue;
        }
        mark_strip_draws(t.static_draws, trees[tid].gbase, trees[tid].gcount);
        for (const auto& d : t.instanced_wind_draws) {
          for (u32 li : d.vertex_index_stream) {
            if (li != UINT32_MAX && li < trees[tid].gcount) {
              mark(trees[tid].gbase + li, (u32)d.tree_tex_id);
            }
          }
        }
        tid++;
      }
    }
    if (do_shrub) {
      for (auto& t : lev.shrub_trees) {
        if (t.unpacked.vertices.empty()) {
          continue;
        }
        for (const auto& d : t.static_draws) {
          for (u32 k = 0; k < d.num_indices; k++) {
            const size_t ii = d.first_index_index + k;
            if (ii >= t.indices.size()) {
              break;
            }
            const u32 li = t.indices[ii];
            if (li != UINT32_MAX && li < trees[tid].gcount) {
              mark(trees[tid].gbase + li, d.tree_tex_id);
            }
          }
        }
        tid++;
      }
    }
  }

  // =============================================================================================
  // 3. THE WELD. Union-find over a 3 cm spatial hash, across every tree / bucket / system.
  //
  //    The pass this replaces used FIRST-HIT grouping: a vertex adopted the first neighbour's group
  //    and never merged two existing groups, so a chain of near-coincident vertices could end up in
  //    several distinct groups — an under-weld, i.e. exactly a "forgotten weld". Union-find merges
  //    transitively and is order-independent, which is the first structural fix of this phase.
  // =============================================================================================
  UnionFind uf(gp);
  const float weld_diam_cap = weld_cell * 2.f;
  const float wide_diam_cap = wide_cell * 2.f;
  {
    std::unordered_map<u64, std::vector<u32>> cells;
    cells.reserve(N / 2 + 1);
    for (size_t i = 0; i < N; i++) {
      const math::Vector3f& pi = gp[i];
      const s64 cx = (s64)std::floor(pi.x() / weld_cell);
      const s64 cy = (s64)std::floor(pi.y() / weld_cell);
      const s64 cz = (s64)std::floor(pi.z() / weld_cell);
      for (int dz = -1; dz <= 1; dz++) {
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            auto it = cells.find(cell_key(cx + dx, cy + dy, cz + dz));
            if (it == cells.end()) {
              continue;
            }
            for (u32 j : it->second) {
              const math::Vector3f d = gp[j] - pi;
              if (d.dot(d) <= weld_tol2) {
                uf.unite((u32)i, j, weld_diam_cap);
              }
            }
          }
        }
      }
      cells[cell_key(cx, cy, cz)].push_back((u32)i);
    }
  }

  std::vector<u32> group(N, 0);
  u32 num_groups = 0;
  auto renumber_groups = [&]() {
    std::unordered_map<u32, u32> remap;
    remap.reserve(N / 2 + 1);
    num_groups = 0;
    for (size_t i = 0; i < N; i++) {
      const u32 r = uf.find((u32)i);
      auto it = remap.find(r);
      if (it == remap.end()) {
        remap.emplace(r, num_groups);
        group[i] = num_groups++;
      } else {
        group[i] = it->second;
      }
    }
  };
  renumber_groups();

  // ---------------------------------------------------------------------------------------------
  // 3b. RAW OPEN EDGES + THE FORGOTTEN-WELD COUNT.
  //     open_raw          : edges the GPU does not share (used by exactly one triangle, by index)
  //     coincident_unshared: those whose two endpoints coincide with another open edge's endpoints
  //                          == the owner's "soudures oubliees". THIS is the no-omissions metric.
  // ---------------------------------------------------------------------------------------------
  std::vector<u64> open_raw_keys;  // packed (lo<<32)|hi of GLOBAL vertex ids, decodable
  {
    std::vector<u64> rk;
    rk.reserve(F * 3);
    for (size_t f = 0; f < F; f++) {
      const auto& t = faces[f];
      rk.push_back(edge_key(t[0], t[1]));
      rk.push_back(edge_key(t[1], t[2]));
      rk.push_back(edge_key(t[2], t[0]));
    }
    std::sort(rk.begin(), rk.end());
    size_t i = 0;
    while (i < rk.size()) {
      size_t j = i + 1;
      while (j < rk.size() && rk[j] == rk[i]) {
        j++;
      }
      const u32 a = (u32)(rk[i] >> 32);
      auto& sa = sys_audit(sys_of(a));
      sa.edges_raw++;
      if (j - i == 1) {
        sa.open_raw++;
        open_raw_keys.push_back(rk[i]);
      }
      i = j;
    }
  }

  // ---------------------------------------------------------------------------------------------
  // 3c. GROUP EDGES. The same edges, but with both endpoints mapped through the weld map: this is
  //     the topology of the SURFACE rather than of the index buffer. An edge still used once here
  //     is either a genuine open boundary or a weld the tolerance failed to reach.
  //     The low bit of the stored face id is the edge's traversal DIRECTION, which the orientation
  //     flood-fill needs to decide whether two neighbouring faces wind consistently.
  // ---------------------------------------------------------------------------------------------
  std::vector<std::pair<u64, u32>> ge;  // (group edge key, (face<<1)|dir)
  std::vector<u8> group_open;
  // round-22: an adjacency link now carries WHETHER IT IS TRUSTWORTHY. The topological winding rule
  // ("consistently wound neighbours traverse the shared edge in opposite directions") is only DEFINED
  // on a TRUE MANIFOLD edge — one the welded topology says is shared by exactly two faces. The
  // run-chaining below deliberately fabricates links across edges incident to 3+ faces (stacked
  // coplanar sheets, a decimated LOD triangle chained onto the full-res mesh); on those the rule
  // states a relation that does not exist, and the flood fill propagates it. Tagging the link lets
  // the flood fill trust the certain ones first and only guess where it must.
  struct ManifoldLink {
    u32 a, b;           // (face<<1)|dir, as before
    u8 true_manifold;   // the welded edge had EXACTLY two incident faces
  };
  std::vector<ManifoldLink> manifold_adj;
  std::vector<u64> open_grp_edges;  // group edge keys used exactly once
  // ROUND 31 — per FACE: does this face own an edge that no other face shares? A component none of
  // whose faces owns one is CLOSED, and only on a closed component is the signed volume EXACT.
  std::vector<u8> face_open_edge;

  // round-22: a face's identity as a SURFACE — its three corners mapped through the weld map and
  // sorted. Two faces with the same triple are coincident duplicate copies of one triangle.
  // Returns false if the triple is degenerate (two corners welded together), in which case the face
  // cannot be identified this way and must not be treated as anyone's duplicate.
  auto face_group_triple = [&](u32 f, std::array<u32, 3>* out) {
    std::array<u32, 3> g3 = {group[faces[f][0]], group[faces[f][1]], group[faces[f][2]]};
    std::sort(g3.begin(), g3.end());
    *out = g3;
    return g3[0] != g3[1] && g3[1] != g3[2];
  };

  auto build_group_edges = [&]() {
    // Re-derived from scratch on every rebuild (the wide re-weld calls this a second time), so a
    // vertex that stopped being on a boundary does not keep a stale open-edge mark.
    face_open_edge.assign(F, 0);
    ge.clear();
    ge.reserve(F * 3);
    for (size_t f = 0; f < F; f++) {
      const auto& t = faces[f];
      for (int e = 0; e < 3; e++) {
        const u32 ga = group[t[e]];
        const u32 gb = group[t[(e + 1) % 3]];
        if (ga == gb) {
          continue;  // the weld collapsed this edge (a sliver) — it cannot be a boundary
        }
        ge.emplace_back(edge_key(ga, gb), ((u32)f << 1) | (ga < gb ? 0u : 1u));
      }
    }
    std::sort(ge.begin(), ge.end(),
              [](const std::pair<u64, u32>& a, const std::pair<u64, u32>& b) {
                return a.first != b.first ? a.first < b.first : a.second < b.second;
              });
    group_open.assign(num_groups, 0);
    manifold_adj.clear();
    open_grp_edges.clear();
    size_t i = 0;
    while (i < ge.size()) {
      size_t j = i + 1;
      while (j < ge.size() && ge[j].first == ge[i].first) {
        j++;
      }
      const size_t n = j - i;
      if (n == 1) {
        open_grp_edges.push_back(ge[i].first);
        group_open[(u32)(ge[i].first >> 32)] = 1;
        group_open[(u32)(ge[i].first & 0xffffffffu)] = 1;
        if (face_open_edge.size() == F) {
          face_open_edge[ge[i].second >> 1] = 1;
        }
      } else if (n >= 2) {
        // NOT just n==2. Because the level ships ~5 coincident copies of most positions, ONE
        // physical edge shows up as several raw edges that all map to the SAME group key — runs of
        // 4, 6, 10 are the norm and a strict two-faces-only manifold test finds almost no adjacency
        // at all (measured: 1.08M "components" for 1.35M faces, which made the orientation pass
        // meaningless and mislabelled 85% of groups as creases). CHAIN the run instead: n-1 links is
        // enough to connect the whole run, and stays linear. Capped so a pathological run cannot
        // dominate.
        // round-22: which of those chain links may the TOPOLOGICAL winding rule speak for? Only a
        // genuine two-faces-share-an-edge adjacency. The naive test "the run has length 2" is far too
        // strict HERE precisely because of the coincident copies described above: measured on
        // village1 it tagged only 10.7% of pairs as trustworthy, dumped the other 89.3% on the
        // geometric rule and drove the residual from 48876 to 234829.
        // The run length must therefore be counted in DISTINCT TRIANGLES, not in entries: a run of 10
        // that is 2 triangles x 5 copies IS a manifold edge. So the edge is manifold iff its entries
        // carry exactly two distinct weld-group triples, and then a link is trustworthy iff it joins
        // the two DIFFERENT ones (a link between two copies of one triangle is a duplicate, which the
        // flood fill must resolve geometrically).
        const size_t lim = std::min(n, (size_t)17);
        std::array<u32, 3> tri_a{}, tri_b{};
        bool have_a = false, have_b = false, run_ok = true;
        for (size_t k = i; k < j && run_ok; k++) {
          std::array<u32, 3> t3{};
          if (!face_group_triple(ge[k].second >> 1, &t3)) {
            run_ok = false;  // a degenerate face: this edge cannot be classified
            break;
          }
          if (!have_a) {
            tri_a = t3;
            have_a = true;
          } else if (t3 == tri_a) {
            // another copy of the first triangle
          } else if (!have_b) {
            tri_b = t3;
            have_b = true;
          } else if (t3 != tri_b) {
            run_ok = false;  // a third distinct triangle: genuinely non-manifold
          }
        }
        const bool two_manifold = run_ok && have_a && have_b;
        for (size_t k = i + 1; k < i + lim; k++) {
          u8 is_true = 0;
          if (two_manifold) {
            std::array<u32, 3> t0{}, t1{};
            face_group_triple(ge[k - 1].second >> 1, &t0);
            face_group_triple(ge[k].second >> 1, &t1);
            is_true = (t0 != t1) ? (u8)1 : (u8)0;
          }
          manifold_adj.push_back({ge[k - 1].second, ge[k].second, is_true});
        }
      }
      i = j;
    }
  };
  build_group_edges();

  // coincident-but-unshared, measured against the weld map: an open RAW edge whose group edge is
  // used by two or more DIFFERENT triangles is geometrically the same edge on both sides.
  {
    std::vector<u64> og;
    og.reserve(open_raw_keys.size());
    for (u64 k : open_raw_keys) {
      const u32 a = (u32)(k >> 32);
      const u32 b = (u32)(k & 0xffffffffu);
      const u64 gk = edge_key(group[a], group[b]);
      auto lo = std::lower_bound(ge.begin(), ge.end(), gk,
                                 [](const std::pair<u64, u32>& e, u64 v) { return e.first < v; });
      auto hi = std::upper_bound(ge.begin(), ge.end(), gk,
                                 [](u64 v, const std::pair<u64, u32>& e) { return v < e.first; });
      if (hi - lo >= 2) {
        sys_audit(sys_of(a)).coincident_unshared++;
        og.push_back(gk);
      }
    }
    std::sort(og.begin(), og.end());
    size_t i = 0;
    while (i < og.size()) {
      size_t j = i + 1;
      while (j < og.size() && og[j] == og[i]) {
        j++;
      }
      const u64 n = (u64)(j - i);
      sys_audit(sys_of((u32)(og[i] >> 32))).coincident_unshared_pairs += n * (n - 1) / 2;
      i = j;
    }
  }

  // ---------------------------------------------------------------------------------------------
  // 3d. RESIDUAL DETECTOR + BOUNDARY-ONLY WIDE RE-WELD.
  //     A "missed weld" is an edge that is STILL open after the weld map but has a geometric twin
  //     within a wider tolerance whose face agrees in orientation. The re-weld unites exactly those
  //     twins' endpoints — it can only ever stitch geometry that is already open, so it can never
  //     merge interior detail or collapse a genuine crease. Iterated until it converges; whatever
  //     survives is reported as the honest omission count.
  // ---------------------------------------------------------------------------------------------
  auto find_open_twins = [&](std::vector<std::pair<u64, u64>>* twins_out) -> u64 {
    // one representative vertex + one incident face per open group edge
    struct OE {
      u32 ga, gb;
      u32 va, vb;
      math::Vector3f n;
    };
    std::vector<OE> oes;
    oes.reserve(open_grp_edges.size());
    {
      // map group -> a representative vertex id (first member wins; deterministic)
      std::unordered_map<u64, u32> gk_to_face;
      gk_to_face.reserve(open_grp_edges.size() * 2);
      for (size_t i = 0; i < ge.size();) {
        size_t j = i + 1;
        while (j < ge.size() && ge[j].first == ge[i].first) {
          j++;
        }
        if (j - i == 1) {
          gk_to_face.emplace(ge[i].first, ge[i].second >> 1);
        }
        i = j;
      }
      std::vector<u32> grep_(num_groups, UINT32_MAX);
      for (size_t i = 0; i < N; i++) {
        if (referenced[i] && grep_[group[i]] == UINT32_MAX) {
          grep_[group[i]] = (u32)i;
        }
      }
      for (u64 k : open_grp_edges) {
        OE o;
        o.ga = (u32)(k >> 32);
        o.gb = (u32)(k & 0xffffffffu);
        o.va = grep_[o.ga];
        o.vb = grep_[o.gb];
        if (o.va == UINT32_MAX || o.vb == UINT32_MAX) {
          continue;
        }
        auto it = gk_to_face.find(k);
        if (it == gk_to_face.end()) {
          continue;
        }
        math::Vector3f n = face_normal(it->second);
        float l = n.length();
        o.n = l > 1e-6f ? n * (1.f / l) : math::Vector3f(0.f, 1.f, 0.f);
        oes.push_back(o);
      }
    }
    // spatial hash on the edge midpoint at the WIDE cell size
    std::unordered_map<u64, std::vector<u32>> mid_cells;
    mid_cells.reserve(oes.size() * 2 + 1);
    std::vector<math::Vector3f> mids(oes.size());
    for (size_t i = 0; i < oes.size(); i++) {
      mids[i] = (gp[oes[i].va] + gp[oes[i].vb]) * 0.5f;
      mid_cells[cell_key((s64)std::floor(mids[i].x() / wide_cell),
                         (s64)std::floor(mids[i].y() / wide_cell),
                         (s64)std::floor(mids[i].z() / wide_cell))]
          .push_back((u32)i);
    }
    u64 hits = 0;
    std::vector<u8> has_twin(oes.size(), 0);
    for (size_t i = 0; i < oes.size(); i++) {
      const s64 cx = (s64)std::floor(mids[i].x() / wide_cell);
      const s64 cy = (s64)std::floor(mids[i].y() / wide_cell);
      const s64 cz = (s64)std::floor(mids[i].z() / wide_cell);
      for (int dz = -1; dz <= 1; dz++) {
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            auto it = mid_cells.find(cell_key(cx + dx, cy + dy, cz + dz));
            if (it == mid_cells.end()) {
              continue;
            }
            for (u32 j : it->second) {
              if (j <= i) {
                continue;
              }
              // must be a DIFFERENT surface patch, not the same edge
              if (oes[i].ga == oes[j].ga && oes[i].gb == oes[j].gb) {
                continue;
              }
              if (oes[i].n.dot(oes[j].n) < cfg.wide_face_cos) {
                continue;  // the two sides face different ways: a real boundary, not a missed weld
              }
              const math::Vector3f& ai = gp[oes[i].va];
              const math::Vector3f& bi = gp[oes[i].vb];
              const math::Vector3f& aj = gp[oes[j].va];
              const math::Vector3f& bj = gp[oes[j].vb];
              const float d_aa = (ai - aj).dot(ai - aj);
              const float d_bb = (bi - bj).dot(bi - bj);
              const float d_ab = (ai - bj).dot(ai - bj);
              const float d_ba = (bi - aj).dot(bi - aj);
              bool straight = d_aa <= wide_tol2 && d_bb <= wide_tol2;
              bool crossed = d_ab <= wide_tol2 && d_ba <= wide_tol2;
              if (!straight && !crossed) {
                continue;
              }
              has_twin[i] = has_twin[j] = 1;
              if (twins_out) {
                if (straight) {
                  twins_out->emplace_back(((u64)oes[i].va << 32) | oes[j].va,
                                          ((u64)oes[i].vb << 32) | oes[j].vb);
                } else {
                  twins_out->emplace_back(((u64)oes[i].va << 32) | oes[j].vb,
                                          ((u64)oes[i].vb << 32) | oes[j].va);
                }
              }
            }
          }
        }
      }
    }
    for (size_t i = 0; i < oes.size(); i++) {
      hits += has_twin[i];
    }
    return hits;
  };

  if ((cfg.bits & kMeshBitNoWide) == 0) {
    for (int round = 0; round < cfg.wide_rounds; round++) {
      std::vector<std::pair<u64, u64>> twins;
      const u64 found = find_open_twins(&twins);
      if (found == 0 || twins.empty()) {
        break;
      }
      u64 unions = 0;
      for (const auto& tw : twins) {
        unions += uf.unite((u32)(tw.first >> 32), (u32)(tw.first & 0xffffffffu), wide_diam_cap);
        unions += uf.unite((u32)(tw.second >> 32), (u32)(tw.second & 0xffffffffu), wide_diam_cap);
      }
      rep.wide_reweld_rounds++;
      rep.wide_reweld_unions += unions;
      if (unions == 0) {
        break;
      }
      renumber_groups();
      build_group_edges();
    }
  }

  // final open/residual accounting, against the FINAL weld map
  {
    // attribute open_by_group per system via the owning face
    size_t i = 0;
    while (i < ge.size()) {
      size_t j = i + 1;
      while (j < ge.size() && ge[j].first == ge[i].first) {
        j++;
      }
      if (j - i == 1) {
        sys_audit((int)face_sys[ge[i].second >> 1]).open_by_group++;
      }
      i = j;
    }
  }
  const u64 residual_twins = find_open_twins(nullptr);
  rep.total.missed_welds = residual_twins;

  rep.groups = num_groups;

  // =============================================================================================
  // 4. GROUP MEMBERSHIP (CSR) + group classification.
  // =============================================================================================
  std::vector<u32> goff(num_groups + 1, 0);
  std::vector<u32> gflat(N);
  {
    std::vector<u32> gcount(num_groups, 0);
    for (size_t i = 0; i < N; i++) {
      gcount[group[i]]++;
    }
    for (u32 g = 0; g < num_groups; g++) {
      goff[g + 1] = goff[g] + gcount[g];
    }
    std::vector<u32> cursor(goff.begin(), goff.end() - 1);
    for (size_t i = 0; i < N; i++) {
      gflat[cursor[group[i]]++] = (u32)i;
    }
  }
  std::vector<u8> group_multitree(num_groups, 0);
  std::vector<u8> group_multisystem(num_groups, 0);
  std::vector<u8> group_multitex(num_groups, 0);
  std::vector<u8> group_refcount2(num_groups, 0);
  for (u32 g = 0; g < num_groups; g++) {
    u32 t0 = UINT32_MAX, s0 = UINT32_MAX, x0 = kNoTex, refs = 0;
    for (u32 k = goff[g]; k < goff[g + 1]; k++) {
      const u32 i = gflat[k];
      if (!referenced[i]) {
        continue;
      }
      refs++;
      if (t0 == UINT32_MAX) {
        t0 = gtree[i];
      } else if (gtree[i] != t0) {
        group_multitree[g] = 1;
      }
      const u32 s = (u32)sys_of(i);
      if (s0 == UINT32_MAX) {
        s0 = s;
      } else if (s != s0) {
        group_multisystem[g] = 1;
      }
      if (gtex_multi[i]) {
        group_multitex[g] = 1;
      }
      if (gtex[i] != kNoTex) {
        if (x0 == kNoTex) {
          x0 = gtex[i];
        } else if (gtex[i] != x0) {
          group_multitex[g] = 1;
        }
      }
    }
    if (refs >= 2) {
      group_refcount2[g] = 1;
      rep.groups_coincident++;
    }
    rep.groups_multitree += group_multitree[g];
    rep.groups_multisystem += group_multisystem[g];
  }

  // ---- BEFORE metrics over the coincident groups (normals as the previous passes left them) ----
  // `src` selects which normal array to measure (nullptr = the live vertex data). `smooth_only`
  // restricts the population to groups the crease classifier called SMOOTH — see the header.
  const std::vector<u8>* crease_filter = nullptr;
  auto measure_normal_delta = [&](MeshDeltaHist& h, const std::vector<u32>* src, bool smooth_only) {
    h = MeshDeltaHist();
    for (u32 g = 0; g < num_groups; g++) {
      if (!group_refcount2[g]) {
        continue;
      }
      if (smooth_only && crease_filter && (*crease_filter)[g]) {
        continue;
      }
      double worst = 0;
      math::Vector3f first(0, 0, 0);
      bool have_first = false;
      for (u32 k = goff[g]; k < goff[g + 1]; k++) {
        const u32 i = gflat[k];
        if (!referenced[i]) {
          continue;
        }
        const math::Vector3f n = unpack_nor(src ? (*src)[i] : *nor_ptr(i));
        if (!(n.length() > 1e-6f)) {
          continue;
        }
        if (!have_first) {
          first = n;
          have_first = true;
        } else {
          worst = std::max(worst, (double)deg_between(first, n));
        }
      }
      if (have_first) {
        hist_add_deg(h, worst);
      }
    }
  };

  // decode a vertex's baked colour: 8 palettes x 4 channels straight out of its OWN tree's palette.
  auto read_colour = [&](size_t i, u8* dst /*32*/) -> bool {
    const PackedTimeOfDay* pal = trees[gtree[i]].colors;
    if (!pal || pal->color_count == 0) {
      return false;
    }
    const u32 ci = *cidx_ptr(i);
    if (ci >= pal->color_count) {
      return false;
    }
    const size_t need = ((size_t)(ci / 4) + 1) * 128;
    if (pal->data.size() < need) {
      return false;
    }
    for (int p = 0; p < kPaletteCount; p++) {
      for (int c = 0; c < 4; c++) {
        dst[p * 4 + c] = pal->read((int)ci, p, c);
      }
    }
    return true;
  };

  auto measure_colour_delta = [&](MeshDeltaHist& h) {
    h = MeshDeltaHist();
    u8 first[32], cur[32];
    for (u32 g = 0; g < num_groups; g++) {
      if (!group_refcount2[g]) {
        continue;
      }
      bool have_first = false;
      double worst = 0;
      for (u32 k = goff[g]; k < goff[g + 1]; k++) {
        const u32 i = gflat[k];
        if (!referenced[i] || !read_colour(i, cur)) {
          continue;
        }
        if (!have_first) {
          std::memcpy(first, cur, 32);
          have_first = true;
        } else {
          for (int b = 0; b < 32; b++) {
            worst = std::max(worst, (double)std::abs((int)cur[b] - (int)first[b]));
          }
        }
      }
      if (have_first) {
        hist_add_col(h, worst);
      }
    }
  };

  // snapshot the incoming normals so the smooth-only BEFORE/AFTER can be compared over the SAME
  // group set once the crease classification exists (it needs the oriented faces from step 6)
  std::vector<u32> nor_before(N, 0);
  for (size_t i = 0; i < N; i++) {
    nor_before[i] = *nor_ptr(i);
  }
  measure_normal_delta(rep.nrm_before, nullptr, false);
  measure_colour_delta(rep.col_before);

  // =============================================================================================
  // 5. POSITION SNAP. Coincident members take the group's mean position, so they become BIT-
  //    IDENTICAL. That is what makes the tessellation control shader compute the SAME edge factor
  //    on both sides of a shared edge (it keys off the edge midpoint), and it removes the sub-
  //    millimetre gaps that survive any amount of normal smoothing.
  // =============================================================================================
  if ((cfg.bits & kMeshBitNoPosSnap) == 0) {
    for (u32 g = 0; g < num_groups; g++) {
      if (goff[g + 1] - goff[g] < 2) {
        continue;
      }
      double sx = 0, sy = 0, sz = 0;
      u32 n = 0;
      for (u32 k = goff[g]; k < goff[g + 1]; k++) {
        const u32 i = gflat[k];
        sx += gp[i].x();
        sy += gp[i].y();
        sz += gp[i].z();
        n++;
      }
      if (n < 2) {
        continue;
      }
      const math::Vector3f mean((float)(sx / n), (float)(sy / n), (float)(sz / n));
      for (u32 k = goff[g]; k < goff[g + 1]; k++) {
        const u32 i = gflat[k];
        const float d = (gp[i] - mean).length();
        if (d > 0.f) {
          rep.pos_snapped++;
          rep.pos_snap_max_m = std::max(rep.pos_snap_max_m, (double)(d / kUnitsPerMeter));
          if (bake) {
            bake->pos_idx.push_back(i);
            bake->pos_val.push_back(mean.x());
            bake->pos_val.push_back(mean.y());
            bake->pos_val.push_back(mean.z());
          }
        }
        gp[i] = mean;
        float* pv = (float*)gvert[i];
        pv[0] = mean.x();
        pv[1] = mean.y();
        pv[2] = mean.z();
      }
    }
  }

  // ---------------------------------------------------------------------------------------------
  // 6-pre. COINCIDENT-DUPLICATE TEST (round 22). The level ships several exact copies of most
  //   triangles. Two copies of the SAME triangle traverse their shared edge the SAME way and yet
  //   must keep the SAME normal — the one case where the consistent-winding rule is wrong. That case
  //   is IDENTITY, not geometry: two faces are duplicates iff their three corners land on the same
  //   three WELD GROUPS. Testing it exactly (instead of by a normal-agreement angle, which round 21
  //   did) is what stops a genuine sharp fold from being mistaken for a duplicate.
  //   Degenerate faces (two corners welded into one group) can never be a meaningful duplicate of
  //   anything, so they are excluded rather than matching everything with the same collapsed triple.
  //   Materialised from the SAME face_group_triple() the manifold tagging uses, over the FINAL weld
  //   map, so the two cannot drift apart.
  // ---------------------------------------------------------------------------------------------
  std::vector<std::array<u32, 3>> fgrp(F);
  std::vector<u8> fgrp_ok(F, 0);
  for (size_t f = 0; f < F; f++) {
    std::array<u32, 3> g3{};
    face_group_triple((u32)f, &g3);
    fgrp[f] = g3;
    fgrp_ok[f] = (g3[0] != g3[1] && g3[1] != g3[2]) ? (u8)1 : (u8)0;
  }
  auto faces_are_duplicate = [&](u32 a, u32 b) {
    return fgrp_ok[a] != 0 && fgrp_ok[b] != 0 && fgrp[a] == fgrp[b];
  };

  // =============================================================================================
  // 6. ORIENTATION. Flood-fill a consistent winding sign over the welded topology, then decide which
  //    way "outward" is for each connected component.
  //
  //    ROUND 31 — THE PRECEDENCE MOVED. With kMeshBitGeomOrient set, a PER-FACE GEOMETRIC OUTWARD
  //    VOTE (escape rays from both sides of every face) is the FIRST authority and the walkable
  //    COLLISION MESH is DEMOTED to last resort, because "the walkable side is the outward side" is
  //    meaningless for a roof, a vertical wall or a face under a cornice. With the bit clear the
  //    order below is unchanged, bit for bit. The two paragraphs that follow describe that legacy
  //    order, which is still what a device without a baked sidecar runs.
  //
  //    FIRST AUTHORITY: the walkable COLLISION MESH. It is the ground truth wherever it reaches.
  //
  //    SECOND AUTHORITY (round 28): where the collision mesh is SILENT, a deterministic, purely
  //    GEOMETRIC cascade (signed volume, then outward ray parity) decides instead. Before round 28
  //    such a component simply kept the orientation it arrived with — the consensus of the AUTHORED
  //    vertex normals — which is not an authority at all: if the authored normals were inverted the
  //    component stayed inverted. An inverted vertex normal inverts the TESSELLATION displacement
  //    (the tese displaces along N) while leaving PARALLAX correct (the POM tangent frame is
  //    invariant under N -> -N once w flips, which pass 7b below already does), which is exactly the
  //    owner's report: roof, cliff cornice and part of the sage-hut wall inverted in tessellation
  //    but correct in parallax.
  // =============================================================================================
  std::vector<s8> fsign(F, 0);
  if ((cfg.bits & kMeshBitNoOrient) != 0) {
    fsign.assign(F, 1);  // A/B killswitch: raw authored winding, no flood-fill, no authority
  } else {
    // CSR adjacency from the manifold group edges.
    // round-22 slot layout: (neighbour_face << 2) | (same_dir << 1) | is_true_manifold
    std::vector<u32> acnt(F + 1, 0);
    for (const auto& a : manifold_adj) {
      acnt[a.a >> 1]++;
      acnt[a.b >> 1]++;
    }
    std::vector<u32> aoff(F + 1, 0);
    for (size_t f = 0; f < F; f++) {
      aoff[f + 1] = aoff[f] + acnt[f];
    }
    std::vector<u32> aflat(aoff[F]);
    {
      std::vector<u32> cur(aoff.begin(), aoff.end() - 1);
      for (const auto& a : manifold_adj) {
        const u32 fa = a.a >> 1, fb = a.b >> 1;
        const u32 same_dir = ((a.a & 1u) == (a.b & 1u)) ? 1u : 0u;
        const u32 tag = (same_dir << 1) | (u32)a.true_manifold;
        aflat[cur[fa]++] = (fb << 2) | tag;
        aflat[cur[fb]++] = (fa << 2) | tag;
      }
    }
    // round-22 TWO-TIER FRONTIER. `strong` holds signed faces still to be expanded; `weak_pending`
    // holds (source face, aflat slot) for every link whose sign relation is a GUESS. The strong
    // frontier is drained completely before a single weak attachment is made, and after each weak
    // attachment we go straight back to the strong frontier — so a face is only ever attached
    // geometrically if no chain of trustworthy manifold edges could reach it first.
    std::vector<u32> strong;
    std::vector<u64> weak_pending;
    std::vector<u32> comp_faces;
    CollisionAuthority coll;
    if (!lev.collision.vertices.empty()) {
      coll.build(lev.collision);
    }

    // -------------------------------------------------------------------------------------------
    // round-28 SECOND ORIENTATION AUTHORITY — machinery.
    //
    // DETERMINISM IS A HARD REQUIREMENT here. Every loop that feeds a decision below walks the
    // component's faces in ASCENDING FACE-INDEX order (comp_faces is sorted once, before any of
    // them run), never in flood-fill / DFS-stack order; no std::unordered_* iteration reaches any
    // of these decisions; every accumulation is in double. Two runs over the same fr3 therefore
    // produce byte-identical output.
    // -------------------------------------------------------------------------------------------
    constexpr double kVolEps = 1e-3;      // TIER A speaks only when |V6| > kVolEps * L^3
    constexpr double kRayEdgeEps = 1e-6;  // barycentric margin: closer than this to an edge = ambiguous
    const double kProbeEps = 0.01 * (double)kUnitsPerMeter;  // TIER B probe sits 1 cm off the face
    // ROUND 29 — the collision authority must prove it is COMPETENT before it may outrank geometry.
    // Identical criterion to the residual metric at the bottom of pass 6 ("a near-perpendicular
    // comparison carries no information"): the collision plane must be within ~70 deg of the rendered
    // face for its normal to say anything about which side of THAT face is outside.
    constexpr float kCollParallelMin = 0.35f;
    // ...and the surviving readings must AGREE. This is the area-weighted MEAN agreement, so it is
    // scale-free -- unlike the old `|agree_coll| > 1e-3` test on a raw sum in game units (4096/m),
    // which one square metre of face cleared by nine orders of magnitude and which therefore let
    // orthogonal noise decide 18007 of village1's 25530 components.
    constexpr double kCollConfMin = 0.15;
    // THREE fixed, hard-coded, non-axis-aligned, mutually distinct unit directions (pairwise dots
    // 0.040 / -0.294 / -0.374, so they are well spread and cannot all graze the same edge). A
    // single ray that grazes an edge must never decide alone, hence the majority vote.
    static const double kRayDir[3][3] = {
        {0.577376394449, 0.325086709102, 0.748969379013},
        {0.811042441923, -0.447113141060, -0.377226717625},
        {-0.267296955505, 0.801790867654, -0.534493912149},
    };
    // Moller-Trumbore in double. Winding is irrelevant to a parity count, so the fsign correction
    // is deliberately NOT applied here. Returns:
    //   +1 clean forward hit, 0 clean miss, -1 AMBIGUOUS -> the caller throws the whole ray away.
    auto ray_tri = [&](const double* o, const double* d, u32 f) -> int {
      const auto& tf = faces[f];
      const double v0[3] = {(double)gp[tf[0]].x(), (double)gp[tf[0]].y(), (double)gp[tf[0]].z()};
      const double v1[3] = {(double)gp[tf[1]].x(), (double)gp[tf[1]].y(), (double)gp[tf[1]].z()};
      const double v2[3] = {(double)gp[tf[2]].x(), (double)gp[tf[2]].y(), (double)gp[tf[2]].z()};
      const double e1[3] = {v1[0] - v0[0], v1[1] - v0[1], v1[2] - v0[2]};
      const double e2[3] = {v2[0] - v0[0], v2[1] - v0[1], v2[2] - v0[2]};
      const double pv[3] = {d[1] * e2[2] - d[2] * e2[1], d[2] * e2[0] - d[0] * e2[2],
                            d[0] * e2[1] - d[1] * e2[0]};
      const double det = e1[0] * pv[0] + e1[1] * pv[1] + e1[2] * pv[2];
      if (!(std::abs(det) > 1e-12)) {
        return 0;  // ray parallel to the triangle's plane: it skims, it does not cross
      }
      const double inv = 1.0 / det;
      const double tv[3] = {o[0] - v0[0], o[1] - v0[1], o[2] - v0[2]};
      const double bu = (tv[0] * pv[0] + tv[1] * pv[1] + tv[2] * pv[2]) * inv;
      const double qv[3] = {tv[1] * e1[2] - tv[2] * e1[1], tv[2] * e1[0] - tv[0] * e1[2],
                            tv[0] * e1[1] - tv[1] * e1[0]};
      const double bv = (d[0] * qv[0] + d[1] * qv[1] + d[2] * qv[2]) * inv;
      const double bw = 1.0 - bu - bv;
      if (bu < -kRayEdgeEps || bv < -kRayEdgeEps || bw < -kRayEdgeEps) {
        return 0;  // clearly outside the triangle
      }
      if (bu < kRayEdgeEps || bv < kRayEdgeEps || bw < kRayEdgeEps) {
        return -1;  // within 1e-6 of an edge/vertex: the crossing count is not trustworthy
      }
      const double tt = (e2[0] * qv[0] + e2[1] * qv[1] + e2[2] * qv[2]) * inv;
      if (tt < -kRayEdgeEps) {
        return 0;  // strictly behind the ray origin
      }
      if (tt < kRayEdgeEps) {
        return -1;  // the probe point sits ON this triangle: inside/outside is undefined
      }
      return 1;
    };

    // ROUND 29 A/B killswitch, captured once outside the component loop.
    const bool coll_raw = (cfg.bits & kMeshBitCollRaw) != 0;

    // ---- TIER A: SIGNED VOLUME (divergence theorem), hoisted -------------------------------------
    // ROUND 29: this used to live inline inside the "collision is silent" branch, so it could only
    // ever judge the components the collision mesh did NOT claim. It is now a lambda run for EVERY
    // component, because the signed volume of a CLOSED shell is exact ground truth and therefore the
    // only authority-free yardstick available to score the collision rule itself (see
    // orient_comps_collraw_vs_volume_conflict). The maths, the thresholds and the fsign-corrected
    // winding are UNCHANGED — it is the same code, moved — so the decision it feeds is bit-identical.
    //
    // Over the component's faces, in the fsign-corrected winding order,
    //     V6 += dot(p0, cross(p1, p2))      (V = V6/6)
    // A CLOSED shell wound outward has V > 0. Only meaningful when the component really is closed
    // enough for the number to mean something, so it is required to clear kVolEps * L^3 (L = the
    // component bbox diagonal) and to have at least 4 faces.
    // Returns +1 = already outward (keep), -1 = inward (flip), 0 = abstain.
    auto signed_volume_verdict = [&]() -> int {
      if (comp_faces.size() < 4) {
        return 0;
      }
      math::Vector3f blo = gp[faces[comp_faces[0]][0]], bhi = blo;
      for (u32 f : comp_faces) {
        for (int e = 0; e < 3; e++) {
          const math::Vector3f& p = gp[faces[f][e]];
          blo = math::Vector3f(std::min(blo.x(), p.x()), std::min(blo.y(), p.y()),
                               std::min(blo.z(), p.z()));
          bhi = math::Vector3f(std::max(bhi.x(), p.x()), std::max(bhi.y(), p.y()),
                               std::max(bhi.z(), p.z()));
        }
      }
      // Translate EVERY position by the bbox CENTRE before the triple product. This is essential,
      // not cosmetic: these are world coordinates in game units of 4096/m, so a raw p0 . (p1 x p2)
      // runs to ~1e15 and the (far smaller) enclosed volume is lost entirely to cancellation.
      // Accumulated in double throughout.
      const double ox = 0.5 * ((double)blo.x() + (double)bhi.x());
      const double oy = 0.5 * ((double)blo.y() + (double)bhi.y());
      const double oz = 0.5 * ((double)blo.z() + (double)bhi.z());
      const double dgx = (double)bhi.x() - (double)blo.x();
      const double dgy = (double)bhi.y() - (double)blo.y();
      const double dgz = (double)bhi.z() - (double)blo.z();
      const double L = std::sqrt(dgx * dgx + dgy * dgy + dgz * dgz);
      double v6 = 0;
      for (u32 f : comp_faces) {
        const auto& tf = faces[f];
        const u32 i0 = tf[0];
        const u32 i1 = fsign[f] < 0 ? tf[2] : tf[1];
        const u32 i2 = fsign[f] < 0 ? tf[1] : tf[2];
        const double ax = (double)gp[i0].x() - ox, ay = (double)gp[i0].y() - oy,
                     az = (double)gp[i0].z() - oz;
        const double bx = (double)gp[i1].x() - ox, by = (double)gp[i1].y() - oy,
                     bz = (double)gp[i1].z() - oz;
        const double cx = (double)gp[i2].x() - ox, cy = (double)gp[i2].y() - oy,
                     cz = (double)gp[i2].z() - oz;
        v6 += ax * (by * cz - bz * cy) + ay * (bz * cx - bx * cz) + az * (bx * cy - by * cx);
      }
      if (L > 0.0 && std::abs(v6) > kVolEps * L * L * L) {
        return v6 > 0 ? 1 : -1;
      }
      return 0;
    };

    // =============================================================================================
    // ROUND 31 — THE PER-FACE GEOMETRIC OUTWARD VOTE (kMeshBitGeomOrient).
    //
    // WHY. The tessellation displaces along the baked vertex normal with `(h - 0.5) * amp`, amp > 0
    // always, so a wrong displacement SIGN is a wrong NORMAL ORIENTATION and nothing else. Rounds
    // 22/28/29 each changed the orientation RULE while measuring only proxies (winding-pair parity,
    // collision agreement, conflict counts) — never the output sign of a face against a purely
    // geometric outward reference. Measured this round with an offline CPU port of the tessellation
    // shaders: the sage hut's GROUND FLOOR is at 0.00% correctly-signed vertices while the UPPER
    // FLOOR is at 58.24%, and on every ground-floor shell the baked normals AND the collision
    // authority both disagree with the geometric outward direction. So the reference itself is what
    // was missing.
    //
    // WHAT. For each face, sit just off its front and back side and ask which side can SEE OPEN AIR:
    // fire K stratified escape rays from `c + 0.02m*gn` about +gn and K from `c - 0.02m*gn` about
    // -gn; a ray escapes if it hits no face within 200 m. The side that escapes more is outside.
    // This needs no collision mesh, no closed shell and no authored normal — it is a property of the
    // rendered geometry alone, defined on a roof, on a vertical wall and under a cornice alike.
    //
    // DETERMINISM. No RNG anywhere: the direction set is a fixed stratified table rotated into the
    // face's own frame by a branchless Duff/Frisvad basis, so it is a pure function of gn. The grid
    // is a dense CSR built in ascending face order, its cell size is a pure function of the level
    // bbox and face count, and the escape test is a boolean OR over the candidate faces, which makes
    // it independent of traversal order. Two runs over one fr3 produce identical votes.
    //
    // COST. This is the expensive pass (2*K rays for every face of every system), which is why the
    // bit is default-OFF and documented as offline-only in the header.
    // =============================================================================================
    const bool geom_orient = (cfg.bits & kMeshBitGeomOrient) != 0;
    // K rays per side. 13 is the spec'd start; a lower K only widens the abstain band, it never
    // biases the sign, because the vote is a DIFFERENCE of escape counts.
    constexpr int kGeomRays = 13;
    constexpr double kGeomHitEps = 0.001 * (double)kUnitsPerMeter;  // ignore hits nearer than 1 mm
    constexpr double kGeomRayMax = 200.0 * (double)kUnitsPerMeter;  // no hit within 200 m == escaped
    constexpr double kGeomProbeEps = 0.02 * (double)kUnitsPerMeter;  // probe sits 2 cm off the face
    constexpr double kGeomConfMin = 0.15;  // area-weighted mean agreement needed to SPEAK
    // Escape-count difference a SINGLE face must show before it is allowed to contradict the
    // orientation its whole component was given. Higher than the 2 needed to join the vote.
    constexpr int kGeomRepairMargin = 4;
    std::vector<s8> gvote(geom_orient ? F : (size_t)0, 0);
    // The raw escape-count DIFFERENCE per face, kept alongside the sign for the residual repair.
    std::vector<s8> gmargin(geom_orient ? F : (size_t)0, 0);
    if (geom_orient) {
      const auto geom_t0 = std::chrono::steady_clock::now();

      // ---- the accelerator: a dense uniform grid, CSR, over EVERY face of EVERY system ----------
      double glo[3] = {0, 0, 0}, ghi[3] = {0, 0, 0};
      {
        const math::Vector3f& p0 = gp[faces[0][0]];
        for (int a = 0; a < 3; a++) {
          glo[a] = ghi[a] = (double)p0[a];
        }
        for (size_t f = 0; f < F; f++) {
          for (int e = 0; e < 3; e++) {
            const math::Vector3f& p = gp[faces[f][e]];
            for (int a = 0; a < 3; a++) {
              glo[a] = std::min(glo[a], (double)p[a]);
              ghi[a] = std::max(ghi[a], (double)p[a]);
            }
          }
        }
      }
      // Memory ceilings, not tuning knobs: they bound the offline pass on a level whose bbox is huge
      // (jak2's city) or whose triangles are huge (sky/water quads spanning hundreds of metres). The
      // cell size only ever GROWS from 1 m, in powers of two, and only as a function of the geometry,
      // so it is reproducible.
      constexpr u64 kMaxGridCells = 8000000;
      constexpr u64 kMaxGridItems = 24000000;
      double gcell = 1.0 * (double)kUnitsPerMeter;  // ~1 m cells
      s64 gdim[3] = {1, 1, 1};
      std::vector<u32> gcell_off;
      std::vector<u32> gcell_items;
      auto face_cells = [&](size_t f, s64* lo, s64* hi) {
        const auto& t = faces[f];
        for (int a = 0; a < 3; a++) {
          const double p0 = (double)gp[t[0]][a], p1 = (double)gp[t[1]][a], p2 = (double)gp[t[2]][a];
          const double mn = std::min(p0, std::min(p1, p2));
          const double mx = std::max(p0, std::max(p1, p2));
          lo[a] = (s64)std::floor((mn - glo[a]) / gcell);
          hi[a] = (s64)std::floor((mx - glo[a]) / gcell);
          lo[a] = std::max<s64>(0, std::min<s64>(gdim[a] - 1, lo[a]));
          hi[a] = std::max<s64>(0, std::min<s64>(gdim[a] - 1, hi[a]));
        }
      };
      for (;;) {
        for (int a = 0; a < 3; a++) {
          gdim[a] = (s64)std::floor((ghi[a] - glo[a]) / gcell) + 1;
        }
        const u64 ncell = (u64)gdim[0] * (u64)gdim[1] * (u64)gdim[2];
        if (ncell > kMaxGridCells) {
          gcell *= 2.0;
          continue;
        }
        gcell_off.assign(ncell + 1, 0);
        u64 total = 0;
        s64 lo[3], hi[3];
        for (size_t f = 0; f < F; f++) {
          face_cells(f, lo, hi);
          total += (u64)(hi[0] - lo[0] + 1) * (u64)(hi[1] - lo[1] + 1) * (u64)(hi[2] - lo[2] + 1);
          if (total > kMaxGridItems) {
            break;
          }
          for (s64 x = lo[0]; x <= hi[0]; x++) {
            for (s64 y = lo[1]; y <= hi[1]; y++) {
              const u64 row = ((u64)x * (u64)gdim[1] + (u64)y) * (u64)gdim[2];
              for (s64 z = lo[2]; z <= hi[2]; z++) {
                gcell_off[row + (u64)z + 1]++;
              }
            }
          }
        }
        if (total > kMaxGridItems) {
          gcell *= 2.0;
          continue;
        }
        for (u64 c = 0; c < ncell; c++) {
          gcell_off[c + 1] += gcell_off[c];
        }
        gcell_items.assign(gcell_off[ncell], 0);
        std::vector<u32> cur(gcell_off.begin(), gcell_off.end() - 1);
        for (size_t f = 0; f < F; f++) {  // ascending face order => deterministic cell contents
          face_cells(f, lo, hi);
          for (s64 x = lo[0]; x <= hi[0]; x++) {
            for (s64 y = lo[1]; y <= hi[1]; y++) {
              const u64 row = ((u64)x * (u64)gdim[1] + (u64)y) * (u64)gdim[2];
              for (s64 z = lo[2]; z <= hi[2]; z++) {
                gcell_items[cur[row + (u64)z]++] = (u32)f;
              }
            }
          }
        }
        break;
      }
      lg::info("[mesh-consolidate] geom-orient grid: cell={:.3f}m dim={}x{}x{} items={} faces={}",
               gcell / (double)kUnitsPerMeter, gdim[0], gdim[1], gdim[2], (u64)gcell_items.size(),
               (u64)F);

      // Non-culling Moller-Trumbore in double, returning the ray parameter. Both sides count: this
      // is a visibility question, not a parity count, so winding is irrelevant here.
      auto ray_tri_t = [&](const double* o, const double* d, u32 f, double* t_out) -> bool {
        const auto& tf = faces[f];
        const double v0[3] = {(double)gp[tf[0]].x(), (double)gp[tf[0]].y(), (double)gp[tf[0]].z()};
        const double v1[3] = {(double)gp[tf[1]].x(), (double)gp[tf[1]].y(), (double)gp[tf[1]].z()};
        const double v2[3] = {(double)gp[tf[2]].x(), (double)gp[tf[2]].y(), (double)gp[tf[2]].z()};
        const double e1[3] = {v1[0] - v0[0], v1[1] - v0[1], v1[2] - v0[2]};
        const double e2[3] = {v2[0] - v0[0], v2[1] - v0[1], v2[2] - v0[2]};
        const double pv[3] = {d[1] * e2[2] - d[2] * e2[1], d[2] * e2[0] - d[0] * e2[2],
                              d[0] * e2[1] - d[1] * e2[0]};
        const double det = e1[0] * pv[0] + e1[1] * pv[1] + e1[2] * pv[2];
        if (!(std::abs(det) > 1e-12)) {
          return false;  // ray parallel to the plane: it skims, it does not block
        }
        const double inv = 1.0 / det;
        const double tv[3] = {o[0] - v0[0], o[1] - v0[1], o[2] - v0[2]};
        const double bu = (tv[0] * pv[0] + tv[1] * pv[1] + tv[2] * pv[2]) * inv;
        if (bu < 0.0 || bu > 1.0) {
          return false;
        }
        const double qv[3] = {tv[1] * e1[2] - tv[2] * e1[1], tv[2] * e1[0] - tv[0] * e1[2],
                              tv[0] * e1[1] - tv[1] * e1[0]};
        const double bv = (d[0] * qv[0] + d[1] * qv[1] + d[2] * qv[2]) * inv;
        if (bv < 0.0 || bu + bv > 1.0) {
          return false;
        }
        *t_out = (e2[0] * qv[0] + e2[1] * qv[1] + e2[2] * qv[2]) * inv;
        return true;
      };

      // ==========================================================================================
      // ROUND 31 — A BVH, NOT THE DENSE DDA GRID. The grid is correct but it cannot be made fine
      // enough here: it is a DENSE 3-D array, so its cell size is forced up by the level's BOUNDING
      // BOX rather than by its geometry. Measured on village1, the ceiling drove it to 32 m cells
      // (460x14x228) and the vote took 3272 s of 8-thread wall clock — 55 minutes for ONE level, i.e.
      // about a day for the 26, which is the concrete reason this authority had never been run on
      // real data. A median-split BVH over the same faces answers the same query in ~13 us per ray
      // against ~750 us, because it adapts to where the triangles actually are. Same question, same
      // determinism (median split with a total order on ties, boolean OR over candidates), same
      // answer — only the acceleration structure changes.
      // ==========================================================================================
      struct BvhNode {
        double lo[3] = {0, 0, 0};
        double hi[3] = {0, 0, 0};
        u32 left = 0, right = 0, first = 0, count = 0;
      };
      std::vector<BvhNode> bnodes;
      std::vector<u32> border(F);
      {
        std::vector<double> flo(F * 3), fhi(F * 3), fcen(F * 3);
        for (size_t f = 0; f < F; f++) {
          border[f] = (u32)f;
          const auto& t = faces[f];
          for (int a = 0; a < 3; a++) {
            const double p0 = (double)gp[t[0]][a], p1 = (double)gp[t[1]][a], p2 = (double)gp[t[2]][a];
            flo[f * 3 + a] = std::min(p0, std::min(p1, p2));
            fhi[f * 3 + a] = std::max(p0, std::max(p1, p2));
            fcen[f * 3 + a] = 0.5 * (flo[f * 3 + a] + fhi[f * 3 + a]);
          }
        }
        bnodes.reserve(2 * (F / 4 + 2));
        // explicit stack, so a deep tree cannot blow the C stack on a pathological level
        struct Job {
          u32 first, count, me;
        };
        std::vector<Job> jobs;
        bnodes.emplace_back();
        jobs.push_back({0, (u32)F, 0});
        while (!jobs.empty()) {
          const Job jb = jobs.back();
          jobs.pop_back();
          BvhNode nd;
          for (int a = 0; a < 3; a++) {
            nd.lo[a] = 1e300;
            nd.hi[a] = -1e300;
          }
          for (u32 i2 = 0; i2 < jb.count; i2++) {
            const u32 f = border[jb.first + i2];
            for (int a = 0; a < 3; a++) {
              nd.lo[a] = std::min(nd.lo[a], flo[(size_t)f * 3 + a]);
              nd.hi[a] = std::max(nd.hi[a], fhi[(size_t)f * 3 + a]);
            }
          }
          if (jb.count <= 8) {
            nd.first = jb.first;
            nd.count = jb.count;
            bnodes[jb.me] = nd;
            continue;
          }
          int axis = 0;
          double best = -1;
          for (int a = 0; a < 3; a++) {
            const double ext = nd.hi[a] - nd.lo[a];
            if (ext > best) {
              best = ext;
              axis = a;
            }
          }
          const u32 mid = jb.count / 2;
          std::nth_element(border.begin() + jb.first, border.begin() + jb.first + mid,
                           border.begin() + jb.first + jb.count, [&](u32 a, u32 b) {
                             const double ca = fcen[(size_t)a * 3 + axis];
                             const double cb = fcen[(size_t)b * 3 + axis];
                             return ca < cb || (ca == cb && a < b);  // total order => deterministic
                           });
          nd.count = 0;
          nd.left = (u32)bnodes.size();
          bnodes.emplace_back();
          nd.right = (u32)bnodes.size();
          bnodes.emplace_back();
          bnodes[jb.me] = nd;
          jobs.push_back({jb.first, mid, nd.left});
          jobs.push_back({jb.first + mid, jb.count - mid, nd.right});
        }
      }
      auto bvh_slab = [](const BvhNode& nd, const double* o, const double* inv, double tmax) {
        double t0 = 0.0, t1 = tmax;
        for (int a = 0; a < 3; a++) {
          double x = (nd.lo[a] - o[a]) * inv[a];
          double y = (nd.hi[a] - o[a]) * inv[a];
          if (x > y) {
            std::swap(x, y);
          }
          t0 = std::max(t0, x);
          t1 = std::min(t1, y);
          if (t0 > t1) {
            return false;
          }
        }
        return true;
      };
      // Returns true if NOTHING is hit within 200 m. Any hit at all ends the walk, so the answer
      // does not depend on the order faces are visited in.
      auto ray_escapes = [&](const double* o, const double* d, u32 src) -> bool {
        if (bnodes.empty()) {
          return true;
        }
        double inv[3];
        for (int a = 0; a < 3; a++) {
          inv[a] = (d[a] != 0.0) ? 1.0 / d[a] : 1e300;
        }
        u32 stack[192];
        int sp = 0;
        stack[sp++] = 0;
        while (sp > 0) {
          const BvhNode& nd = bnodes[stack[--sp]];
          if (!bvh_slab(nd, o, inv, kGeomRayMax)) {
            continue;
          }
          if (nd.count) {
            for (u32 i2 = 0; i2 < nd.count; i2++) {
              const u32 f = border[nd.first + i2];
              if (f == src) {
                continue;  // the source face itself never blocks its own probe
              }
              double t = 0;
              if (ray_tri_t(o, d, f, &t) && t > kGeomHitEps && t <= kGeomRayMax) {
                return false;
              }
            }
          } else if (sp + 2 <= 192) {
            stack[sp++] = nd.left;
            stack[sp++] = nd.right;
          }
        }
        return true;
      };

      // The fixed stratified hemisphere table, in a local frame whose +z is the axis. z is stratified
      // uniformly over (0,1] and the azimuth is the van der Corput radical inverse in base 2, so the
      // K directions are well spread and contain no random state at all.
      double hemi[kGeomRays][3];
      for (int k = 0; k < kGeomRays; k++) {
        const double z = ((double)k + 0.5) / (double)kGeomRays;
        const double r = std::sqrt(std::max(0.0, 1.0 - z * z));
        double vdc = 0.0, den = 0.5;
        for (u32 vb = (u32)k + 1u; vb; vb >>= 1, den *= 0.5) {
          if (vb & 1u) {
            vdc += den;
          }
        }
        const double phi = 2.0 * 3.14159265358979323846 * vdc;
        hemi[k][0] = r * std::cos(phi);
        hemi[k][1] = r * std::sin(phi);
        hemi[k][2] = z;
      }

      // ROUND 31 — PARALLEL, AND STILL BIT-FOR-BIT DETERMINISTIC. One face is one independent
      // problem: every input is a compile-time constant or a pure function of that face's own
      // geometry, ray_escapes() is a boolean OR over candidates (order-independent), and each
      // iteration writes only gvote[f] / gmargin[f]. So which thread computes a face, and in what
      // order the chunks are claimed, cannot move a single bit of the verdict. The two counters
      // that WERE order-dependent (voted / abstained) are accumulated per-thread and summed after
      // the join. This is not an optimisation for its own sake: single-threaded, this pass took 70
      // minutes on village1 alone — about 30 hours to bake the 26 levels — which is why the bit had
      // never once been run on real data despite shipping in the previous round.
      auto geom_vote_one_face = [&](size_t f, u64* loc_voted, u64* loc_abstained) {
        const math::Vector3f nrf = face_normal(f);
        const double len = std::sqrt((double)nrf.x() * (double)nrf.x() +
                                     (double)nrf.y() * (double)nrf.y() +
                                     (double)nrf.z() * (double)nrf.z());
        if (!(len > 1e-9)) {
          (*loc_abstained)++;
          return;  // cannot happen: pass 1 drops zero-area faces
        }
        // gn is the face's own geometric normal from its STORED winding.
        const double gn[3] = {(double)nrf.x() / len, (double)nrf.y() / len, (double)nrf.z() / len};
        // Duff et al. 2017 "Building an Orthonormal Basis, Revisited": branchless, and a pure
        // function of gn, so the direction set never depends on anything but the face itself.
        const double sg = std::copysign(1.0, gn[2]);
        const double na = -1.0 / (sg + gn[2]);
        const double nb = gn[0] * gn[1] * na;
        const double b1[3] = {1.0 + sg * gn[0] * gn[0] * na, sg * nb, -sg * gn[0]};
        const double b2[3] = {nb, sg + gn[1] * gn[1] * na, -gn[1]};
        const auto& tf = faces[f];
        const double cen[3] = {
            ((double)gp[tf[0]].x() + (double)gp[tf[1]].x() + (double)gp[tf[2]].x()) / 3.0,
            ((double)gp[tf[0]].y() + (double)gp[tf[1]].y() + (double)gp[tf[2]].y()) / 3.0,
            ((double)gp[tf[0]].z() + (double)gp[tf[1]].z() + (double)gp[tf[2]].z()) / 3.0};
        int esc_plus = 0, esc_minus = 0;
        for (int side = 0; side < 2; side++) {
          const double s = side == 0 ? 1.0 : -1.0;
          const double o[3] = {cen[0] + gn[0] * kGeomProbeEps * s,
                               cen[1] + gn[1] * kGeomProbeEps * s,
                               cen[2] + gn[2] * kGeomProbeEps * s};
          for (int k = 0; k < kGeomRays; k++) {
            const double d[3] = {b1[0] * hemi[k][0] + b2[0] * hemi[k][1] + gn[0] * hemi[k][2] * s,
                                 b1[1] * hemi[k][0] + b2[1] * hemi[k][1] + gn[1] * hemi[k][2] * s,
                                 b1[2] * hemi[k][0] + b2[2] * hemi[k][1] + gn[2] * hemi[k][2] * s};
            if (ray_escapes(o, d, (u32)f)) {
              if (side == 0) {
                esc_plus++;
              } else {
                esc_minus++;
              }
            }
          }
        }
        // The MARGIN is kept, not just its sign. The component arbitration only needs the sign, but
        // the per-face residual repair below has to be able to demand a STRONGER claim before it
        // contradicts the component consensus, and a bare +1/-1 cannot express that.
        const int diff = esc_plus - esc_minus;
        gmargin[f] = (s8)std::max(-127, std::min(127, diff));
        if (diff >= 2) {
          gvote[f] = 1;
          (*loc_voted)++;
        } else if (-diff >= 2) {
          gvote[f] = -1;
          (*loc_voted)++;
        } else {
          (*loc_abstained)++;
        }
      };

      {
        std::atomic<u64> next_chunk{0};
        std::atomic<u64> n_voted{0}, n_abstained{0};
        const u64 kChunk = 256;
        const u64 n_chunks = (F + kChunk - 1) / kChunk;
        auto geom_worker = [&]() {
          u64 loc_voted = 0, loc_abstained = 0;
          for (;;) {
            const u64 ci = next_chunk.fetch_add(1);
            if (ci >= n_chunks) {
              break;
            }
            const size_t f_lo = (size_t)(ci * kChunk);
            const size_t f_hi = std::min<size_t>(f_lo + (size_t)kChunk, F);
            for (size_t f = f_lo; f < f_hi; f++) {
              geom_vote_one_face(f, &loc_voted, &loc_abstained);
            }
          }
          n_voted += loc_voted;
          n_abstained += loc_abstained;
        };
        const unsigned nthreads = std::max(1u, std::thread::hardware_concurrency());
        std::vector<std::thread> pool;
        for (unsigned t = 1; t < nthreads; t++) {
          pool.emplace_back(geom_worker);
        }
        geom_worker();
        for (auto& th : pool) {
          th.join();
        }
        rep.orient_faces_geom_voted += n_voted.load();
        rep.orient_faces_geom_abstained += n_abstained.load();
      }
      rep.orient_geom_pass_ms =
          std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - geom_t0)
              .count();
      lg::info("[mesh-consolidate] geom-orient votes: voted={} abstained={} rays_per_face={} {:.1f}ms",
               rep.orient_faces_geom_voted, rep.orient_faces_geom_abstained, 2 * kGeomRays,
               rep.orient_geom_pass_ms);
    }

    // The round-28 geometric cascade (TIER A signed volume, then TIER B outward ray parity), lifted
    // into one lambda so that the round-31 precedence change can call it from a DIFFERENT position in
    // the order without a second copy of the code. `vv` is the already-computed signed-volume
    // verdict. Returns +1 keep / -1 flip / 0 abstain, and bumps the tier counters.
    auto geometric_cascade = [&](int vv) -> int {
      // ---- TIER A: SIGNED VOLUME (divergence theorem) -------------------------------------
      // ROUND 29: the computation moved OUT of here into the signed_volume_verdict() lambda above
      // (it now also has to run for the collision-decided components, to score the collision rule
      // against it). Identical maths, identical thresholds, identical winding — this site just
      // consumes the result, so the decision is bit-identical to round 28.
      if (vv != 0) {
        rep.orient_comps_volume_decided++;
        return vv;
      }
      // ---- TIER B: OUTWARD RAY CAST (parity) ----------------------------------------------
      // For the open shells TIER A cannot judge. Deterministically pick the LARGEST-AREA face
      // (tie broken on the LOWEST face index — comp_faces is ascending and the comparison is
      // strict, so the first maximum found IS the lowest index). Probe from just off its front
      // side and count crossings with the component's own faces: EVEN => the probe is outside
      // the shell => the normal already points outward => keep. ODD => flip.
      u32 seed_face = UINT32_MAX;
      float best_area = 0.f;
      for (u32 f : comp_faces) {
        const float a = face_normal(f).length();
        if (a > best_area) {
          best_area = a;
          seed_face = f;
        }
      }
      if (seed_face == UINT32_MAX || !(best_area > 1e-6f)) {
        return 0;
      }
      const auto& tf = faces[seed_face];
      const math::Vector3f nrm = face_normal(seed_face) * ((float)fsign[seed_face] / best_area);
      const math::Vector3f cen = (gp[tf[0]] + gp[tf[1]] + gp[tf[2]]) * (1.f / 3.f);
      const double q[3] = {(double)cen.x() + (double)nrm.x() * kProbeEps,
                           (double)cen.y() + (double)nrm.y() * kProbeEps,
                           (double)cen.z() + (double)nrm.z() * kProbeEps};
      int n_even = 0, n_odd = 0;
      for (int r = 0; r < 3; r++) {
        u32 crossings = 0;
        bool clean = true;
        for (u32 f : comp_faces) {
          const int hit = ray_tri(q, kRayDir[r], f);
          if (hit < 0) {
            clean = false;  // grazed an edge/vertex: this ray decides nothing
            break;
          }
          crossings += (u32)hit;
        }
        if (!clean) {
          continue;
        }
        if ((crossings & 1u) != 0) {
          n_odd++;
        } else {
          n_even++;
        }
      }
      // fewer than two clean rays, or a 1-1 split, is not a majority: abstain.
      if (n_even + n_odd >= 2 && n_even != n_odd) {
        rep.orient_comps_raycast_decided++;
        return n_even > n_odd ? 1 : -1;
      }
      return 0;
    };

    for (size_t seed = 0; seed < F; seed++) {
      if (fsign[seed] != 0) {
        continue;
      }
      rep.orient_components++;
      fsign[seed] = 1;
      strong.clear();
      weak_pending.clear();
      comp_faces.clear();
      strong.push_back((u32)seed);
      // Relative orientation of two faces meeting on a welded edge (round 22 — THE POLARITY FIX).
      //
      // STRONG (a TRUE manifold edge, and not two copies of the same triangle) = the TOPOLOGICAL
      // rule: two consistently-wound triangles traverse their shared edge in OPPOSITE directions, so
      // same traversal direction => opposite winding. Exact at ANY dihedral angle, sharp folds
      // included — but only DEFINED when the edge really is shared by exactly those two faces.
      //
      // The rule this replaces preferred a GEOMETRIC test whenever the two face normals were not
      // near-perpendicular: rel = sign(dot) as soon as |cos| > 0.2. For a genuine convex crease of
      // dihedral angle phi the cosine between the two face normals is -cos(phi), so ANY fold sharper
      // than ~78 deg landed in that branch with a negative cosine and FLIPPED a correctly-wound
      // neighbour; the flood fill then carried that inversion across the whole sub-surface beyond the
      // fold. That is the owner's round-22 defect C: with one shared checkerboard height map, white
      // squares protrude on one surface and black squares on another, because
      // `world += N * (h - 0.5) * amp` runs with N pointing INTO the surface.
      //
      // WEAK (a coincident duplicate, or a link fabricated by the run-chaining across an edge with
      // 3+ incident faces) = the GEOMETRIC rule, because the winding relation is undefined there:
      // two copies of one triangle traverse the shared edge the SAME way yet must keep the same
      // normal, and a chained link between two unrelated sheets states nothing at all. Applying the
      // topological rule to those was what regressed jungleb and swamp in the first round-22 attempt.
      //
      // A weak attachment is only ever made once NO strong edge can extend the component, so the
      // guess can never pre-empt a certainty.
      size_t weak_cursor = 0;
      for (;;) {
        if (!strong.empty()) {
          const u32 f = strong.back();
          strong.pop_back();
          comp_faces.push_back(f);
          for (u32 k = aoff[f]; k < aoff[f + 1]; k++) {
            const u32 nb = aflat[k] >> 2;
            if (fsign[nb] != 0) {
              continue;
            }
            if ((aflat[k] & 1u) != 0 && !faces_are_duplicate(f, nb)) {
              const bool same_dir = (aflat[k] & 2u) != 0;
              fsign[nb] = (s8)(fsign[f] * (same_dir ? (s8)-1 : (s8)1));
              strong.push_back(nb);
            } else {
              weak_pending.push_back(((u64)f << 32) | (u64)k);
            }
          }
          continue;
        }
        // strong frontier exhausted: make ONE weak attachment, then go back to the strong frontier
        bool attached = false;
        while (weak_cursor < weak_pending.size()) {
          const u64 w = weak_pending[weak_cursor++];
          const u32 f = (u32)(w >> 32);
          const u32 k = (u32)(w & 0xffffffffu);
          const u32 nb = aflat[k] >> 2;
          if (fsign[nb] != 0) {
            continue;  // a strong path reached it in the meantime — the certainty wins
          }
          const bool same_dir = (aflat[k] & 2u) != 0;
          s8 rel = same_dir ? (s8)-1 : (s8)1;  // no usable area: fall back to the topological rule
          const math::Vector3f na = face_normal(f);
          const math::Vector3f nbv = face_normal(nb);
          const float la = na.length(), lb = nbv.length();
          if (la > 1e-6f && lb > 1e-6f) {
            rel = (na.dot(nbv) >= 0.f) ? (s8)1 : (s8)-1;
          }
          fsign[nb] = (s8)(fsign[f] * rel);
          strong.push_back(nb);
          attached = true;
          break;
        }
        if (!attached) {
          break;  // component complete
        }
      }
      // decide the component's global sign.
      // round-28 DETERMINISM: sort the component's faces into ASCENDING FACE-INDEX order ONCE, here,
      // before anything reads them. Every statistic below — the collision/authored agreement sums,
      // the TIER A signed volume, the TIER B largest-area seed face and its ray parities — then
      // accumulates in that one fixed order instead of the flood fill's DFS-stack order.
      std::sort(comp_faces.begin(), comp_faces.end());
      double agree_coll = 0, agree_prev = 0;
      bool any_coll = false;
      double coll_area = 0;        // area of the faces the collision mesh is COMPETENT for
      bool coll_present = false;   // a collision normal existed at all (competent or not)
      // ROUND 29 — the PRE-round-29 (unfiltered) collision verdict, computed ALONGSIDE the filtered
      // one on every component so the two rules can be scored against the same ground truth in ONE
      // run. These feed COUNTERS ONLY and never reach a decision.
      double agree_coll_raw = 0;
      bool any_coll_raw = false;
      // ROUND 31 — the per-face geometric outward vote, accumulated in EXACTLY the shape of the
      // agree_coll / coll_area pair above so the two authorities are directly comparable.
      double agree_geom = 0, geom_area = 0;
      for (u32 f : comp_faces) {
        const math::Vector3f nraw = face_normal(f) * (float)fsign[f];
        const float area = nraw.length();
        if (!(area > 1e-6f)) {
          continue;
        }
        const math::Vector3f n = nraw * (1.f / area);
        const auto& t = faces[f];
        const math::Vector3f centre = (gp[t[0]] + gp[t[1]] + gp[t[2]]) * (1.f / 3.f);
        // ROUND 31. The face's geometric OUTWARD direction is gvote[f] * gn(f), and the component's
        // CURRENT relative orientation of that face is fsign[f] * gn(f) (that is literally what pass
        // 7 consumes: `nr = face_normal(f) * fsign[f]`). Their dot product is therefore
        //     gvote[f] * fsign[f] * |gn|^2 == gvote[f] * fsign[f].
        // NOTE ON THE SPEC: the third factor sgn(dot(gn(f), face_normal(f))) is identically +1,
        // because gn(f) IS normalize(face_normal(f)) — same vector, positive scale. It is left out
        // rather than multiplied in as a no-op. agree_geom > 0 thus means "the component's current
        // orientation already points the geometric-outward way", area-weighted, matching agree_coll.
        if (geom_orient && gvote[f] != 0) {
          agree_geom += (double)area * (double)gvote[f] * (double)fsign[f];
          geom_area += (double)area;
        }
        math::Vector3f cn;
        if (coll.nearest_normal(centre, &cn)) {
          coll_present = true;
          const float d = n.dot(cn);
          // Measurement-only: the unfiltered sum, exactly as the pre-round-29 rule built it.
          any_coll_raw = true;
          agree_coll_raw += (double)area * d;
          // ROUND 29 COMPETENCE FILTER — see kCollParallelMin. Skipping the near-perpendicular
          // readings is what hands roofs, vertical walls and under-cornice faces to the exact
          // geometric cascade instead of to floor-normal noise.
          if (coll_raw || std::abs(d) > kCollParallelMin) {
            any_coll = true;
            agree_coll += (double)area * d;
            coll_area += (double)area;
          }
        }
        for (int e = 0; e < 3; e++) {
          const math::Vector3f pn = unpack_nor(*nor_ptr(t[e]));
          if (pn.length() > 1e-6f) {
            agree_prev += (double)area * n.dot(pn);
          }
        }
      }
      // Scale-free confidence: the area-weighted MEAN agreement over the competent readings only.
      const double coll_conf = coll_area > 0.0 ? (agree_coll / coll_area) : 0.0;
      const bool coll_speaks = coll_raw ? (any_coll && std::abs(agree_coll) > 1e-3)
                                        : (any_coll && std::abs(coll_conf) > kCollConfMin);
      if (coll_present && !coll_speaks) {
        rep.orient_comps_collision_incompetent++;
      }

      // ==========================================================================================
      // ROUND 29 — AUTHORITY-FREE SCORING (pure measurement, changes no decision).
      // The two metrics that already existed cannot judge this change: "faces still inward vs
      // collision" is measured AGAINST the collision authority (circular), and the polarity census
      // tests fsign[f]*fsign[nb] relations fixed by the flood fill, which a per-component GLOBAL
      // flip cannot alter. The signed volume of a closed component IS exact, so score both
      // collision rules against it wherever it is confident.
      // ==========================================================================================
      const int vol_verdict = signed_volume_verdict();
      if (vol_verdict != 0) {
        rep.orient_comps_volume_confident++;
        const int raw_verdict = (any_coll_raw && std::abs(agree_coll_raw) > 1e-3)
                                    ? (agree_coll_raw > 0 ? 1 : -1)
                                    : 0;
        if (raw_verdict != 0 && raw_verdict != vol_verdict) {
          rep.orient_comps_collraw_vs_volume_conflict++;
        }
        const int filtered_verdict = coll_speaks ? (agree_coll > 0 ? 1 : -1) : 0;
        if (filtered_verdict != 0 && filtered_verdict != vol_verdict) {
          rep.orient_comps_collfiltered_vs_volume_conflict++;
        }
      }

      // ROUND 31 — does the per-face geometric vote SPEAK for this component? Same scale-free shape
      // as coll_conf: the area-weighted MEAN agreement over the faces that actually voted.
      const double geom_conf = geom_area > 0.0 ? (agree_geom / geom_area) : 0.0;
      const bool geom_speaks = geom_orient && geom_area > 0.0 && std::abs(geom_conf) > kGeomConfMin;
      if (geom_speaks) {
        const int geom_verdict = agree_geom > 0 ? 1 : -1;
        if (coll_speaks && geom_verdict != (agree_coll > 0 ? 1 : -1)) {
          rep.orient_comps_geom_vs_collision_conflict++;
        }
        if (vol_verdict != 0 && geom_verdict != vol_verdict) {
          rep.orient_comps_geom_vs_volume_conflict++;
        }
      }
      if (!coll_speaks) {
        // The collision mesh cannot speak for this component. That is a property of the collision
        // DATA, not of the precedence order, so it is counted identically in both orders below.
        // CAVEAT on the round-28 invariant: volume_decided + raycast_decided + undecided ==
        // comps_no_authority holds in the LEGACY order only. With kMeshBitGeomOrient the geometric
        // tiers also get to decide components the collision mesh DID reach, so they can exceed it.
        rep.orient_comps_no_authority++;
        rep.orient_faces_no_authority += (u64)comp_faces.size();
      }

      // ==========================================================================================
      // THE ARBITRATION.
      //
      // ROUND 31 PRECEDENCE (kMeshBitGeomOrient set) — outward is defined by an OUTWARD RAY or by
      // the SIGNED VOLUME, never by the collision mesh:
      //   1. the per-face geometric outward vote   (exact where it speaks, defined everywhere)
      //   2. the signed volume of a closed shell   (exact where it speaks)
      //   3. TIER B outward ray parity
      //   4. the walkable collision mesh           (DEMOTED to last resort)
      //   5. the authored consensus                (abstain)
      // The demotion is the point of the round: "the walkable side is the outward side" is
      // MEANINGLESS for a roof, for a vertical wall and for a face under a cornice — it is only ever
      // a statement about a floor. That is precisely the population the owner reports as displacing
      // the wrong way (the sage hut's ground-floor wall and the roof over it), and round 29 already
      // measured the collision rule contradicting the exact signed volume on thousands of
      // components. Competence-filtering it was not enough; it must not outrank exact geometry.
      //
      // LEGACY PRECEDENCE (bit clear) — collision, then volume, then ray, then consensus. This is
      // the pre-round-31 behaviour BIT FOR BIT: same order, same thresholds, same lambdas, and
      // geom_speaks is unconditionally false, so a live device load with no sidecar behaves exactly
      // as it does today and no A/B baseline moves under our feet.
      // ==========================================================================================
      // ==========================================================================================
      // ROUND 31, SECOND HALF — EXACTNESS OUTRANKS SAMPLING, AND A CONTRADICTION ABSTAINS.
      //
      // The first half of this round put the per-face escape-ray vote AHEAD of the signed volume.
      // Measuring the result with the offline CPU port of the two tessellation stages showed that
      // was the wrong way round: the meshes the grade condemned were overwhelmingly the ones whose
      // `rayf_vs_vol` column read DISAGREE — i.e. the two INDEPENDENT geometric criteria contradict
      // each other there, and the cascade was believing the sampled one anyway.
      //
      // On a CLOSED component the signed volume is not an estimate. The divergence theorem makes its
      // sign the enclosed-volume sign EXACTLY: no sampling, no free parameter, no origin dependence.
      // The escape ray is a finite sample of 2*13 directions answering "which side has more open
      // space", which is only a PROXY for "which side is outside" — and it is measurably wrong on
      // small props half-buried in terrain, where both sides are blocked and two rays decide the
      // margin. village1 is full of exactly those (the little TIE beach rocks are the level's whole
      // 0%-graded population). So: closed + confident volume wins outright.
      //
      // And where BOTH criteria speak and DISAGREE, neither is trusted: the component keeps the
      // authored consensus and is COUNTED as undecided, rather than being handed a coin flip. The
      // offline test applies the identical rule, so a face this pass refuses to orient is a face the
      // test refuses to grade — the two cannot drift apart and report a fake 100%.
      // ==========================================================================================
      bool comp_closed = true;
      if (face_open_edge.size() == F) {
        for (u32 f : comp_faces) {
          if (face_open_edge[f]) {
            comp_closed = false;
            break;
          }
        }
      } else {
        comp_closed = false;
      }
      const int geom_verdict_c = geom_speaks ? (agree_geom > 0 ? 1 : -1) : 0;
      if (comp_closed && vol_verdict != 0) {
        rep.orient_comps_closed_volume_decided++;
        if (geom_verdict_c != 0 && geom_verdict_c != vol_verdict) {
          rep.orient_comps_geom_overruled_by_volume++;
        }
      }

      double agree = agree_prev;
      if (comp_closed && vol_verdict != 0) {
        // TIER VOLX — exact, and it needs no ray at all.
        agree = (double)vol_verdict;
      } else if (geom_orient && geom_verdict_c != 0 && vol_verdict != 0 &&
                 geom_verdict_c != vol_verdict) {
        // The two independent criteria contradict on an OPEN component. No verdict.
        rep.orient_comps_criteria_conflict++;
        rep.orient_comps_undecided++;
        agree = agree_prev;
      } else if (geom_orient) {
        if (geom_speaks) {
          rep.orient_comps_geom_decided++;
          agree = agree_geom;
        } else {
          const int decided = geometric_cascade(vol_verdict);  // TIER A volume, then TIER B parity
          if (decided != 0) {
            agree = (double)decided;
          } else if (coll_speaks) {
            rep.orient_comps_collision_decided++;
            agree = agree_coll;
          } else {
            rep.orient_comps_undecided++;
            agree = agree_prev;
          }
        }
      } else if (coll_speaks) {
        // FIRST AUTHORITY: the walkable collision mesh reaches this component and has an opinion.
        rep.orient_comps_collision_decided++;
        agree = agree_coll;
      } else {
        // =======================================================================================
        // SECOND AUTHORITY (round 28). The collision mesh is SILENT here. Before round 28 the code
        // fell straight back to agree_prev — the authored vertex normals — i.e. the component kept
        // whatever orientation it arrived with, inverted or not. Run a deterministic, purely
        // geometric cascade instead, and record which tier decided.
        // =======================================================================================
        const int decided = geometric_cascade(vol_verdict);
        // ---- TIER C: ABSTAIN -----------------------------------------------------------------
        // Neither tier could judge. Keep the previous behaviour (the authored consensus) but COUNT
        // it: this component's orientation is still undecided, and the report says so.
        if (decided != 0) {
          agree = (double)decided;
        } else {
          rep.orient_comps_undecided++;
          agree = agree_prev;
        }
      }
      if (agree < 0) {
        for (u32 f : comp_faces) {
          fsign[f] = (s8)-fsign[f];
          rep.orient_faces_flipped++;
        }
      }

      // ==========================================================================================
      // ROUND 31 — THE PER-FACE RESIDUAL REPAIR, and why a component-level decision cannot be the
      // whole answer.
      //
      // Everything above flips a component AS A BLOCK. That is correct only if the component's
      // internal winding is already consistent, and it is not always: the flood fill drains the
      // STRONG (true-manifold) frontier first but then allows ONE WEAK attachment, decided by
      // sign(dot(na, nbv)) — a geometric guess. On a component that is not a closed shell (a
      // terrain sheet, a fence, a cornice, a roof plane welded to a wall at a T-junction) that
      // guess can be wrong, and no amount of flipping the whole component afterwards can repair a
      // face that disagrees with its own neighbours. Those faces stay inverted through pass 7, hand
      // an inverted normal to the tessellator, and the displacement runs backwards on them — the
      // owner's "le noir ressort plus que le blanc" on a surface whose neighbours are correct.
      //
      // So after the block decision, ask each face its OWN question again and repair the residual.
      // The bar is deliberately higher than the bar to vote: contradicting the component consensus
      // is a stronger claim than joining it, so a repair needs kGeomRepairMargin escapes of
      // difference (4 of 13) where a vote needs 2. This is a GENERAL rule keyed on nothing but the
      // face's own geometry — no material, no mesh and no level name appears in it.
      // ==========================================================================================
      // The repair is a SAMPLED criterion, so it may not overrule the exact one either: on a closed
      // component whose volume spoke, the volume has already settled every face and a ray margin,
      // however large, is still a proxy. Repair is for the geometry the volume cannot judge.
      if (geom_orient && !(comp_closed && vol_verdict != 0)) {
        for (u32 f : comp_faces) {
          if (gvote[f] == 0 || std::abs((int)gmargin[f]) < kGeomRepairMargin) {
            continue;
          }
          // gvote[f] is the outward sign of the face's STORED winding; fsign[f] is the orientation
          // the component decided for it. They must agree.
          if ((int)gvote[f] != (int)fsign[f]) {
            fsign[f] = (s8)gvote[f];
            rep.orient_faces_geom_repaired++;
          }
        }
      }
    }
    // residual: faces whose final normal still opposes the collision authority
    if (!lev.collision.vertices.empty()) {
      for (size_t f = 0; f < F; f++) {
        const math::Vector3f nraw = face_normal(f) * (float)fsign[f];
        const float area = nraw.length();
        if (!(area > 1e-6f)) {
          continue;
        }
        const math::Vector3f n = nraw * (1.f / area);
        const auto& t = faces[f];
        const math::Vector3f centre = (gp[t[0]] + gp[t[1]] + gp[t[2]]) * (1.f / 3.f);
        math::Vector3f cn;
        // Only count where the authority actually SPEAKS. The collision mesh covers walkable
        // surfaces, so a wall's nearest collision normal is usually the floor's up-vector: a
        // near-perpendicular comparison carries no information and counting it would inflate the
        // residual with noise. Require a clearly OPPOSED reading.
        if (coll.nearest_normal(centre, &cn)) {
          const float d = n.dot(cn);
          if (std::abs(d) > 0.35f) {
            rep.orient_faces_authority++;
            if (d < 0.f) {
              rep.orient_faces_inward_after++;
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------------------------------------
  // 6b. AUTHORITY-FREE POLARITY CENSUS (round 22). The collision residual above is only defined
  //     where a collision mesh exists AND reads near-parallel to the rendered face, so it is blind
  //     on walls, interiors and thin-collision levels — exactly where the owner sees the polarity
  //     flip. This one needs no authority: for every manifold-adjacent, non-duplicate face pair,
  //     consistent winding REQUIRES fsign[f] * fsign[nb] == (same_dir ? -1 : +1).
  //     _before evaluates it on the AUTHORED winding as it arrives (all signs +1, so the product is
  //     +1 and the pair is inconsistent exactly when it is traversed in the same direction), which
  //     is the real incoming defect count; _after evaluates the final signs. Runs outside the
  //     killswitch branch so the kMeshBitNoOrient A/B reports a number too (there before == after).
  //
  //     The pair POPULATION is identical before and after and identical across rule changes — every
  //     non-duplicate manifold_adj link is counted, weak ones included, so the denominator can never
  //     be quietly improved. The TRUE-manifold / WEAK split below is an extra breakdown over that
  //     same population (true + weak == total, by construction): an inconsistency on a true-manifold
  //     pair is an outright defect, while one on a fabricated non-manifold link may be unavoidable.
  // ---------------------------------------------------------------------------------------------
  for (const auto& a : manifold_adj) {
    const u32 fa = a.a >> 1, fb = a.b >> 1;
    if (fa == fb || faces_are_duplicate(fa, fb)) {
      continue;
    }
    const bool same_dir = ((a.a & 1u) == (a.b & 1u));
    const s8 want = same_dir ? (s8)-1 : (s8)1;
    // authored winding: fsign is +1 everywhere, so the product is +1 and the pair is inconsistent
    // exactly when the rule wants -1
    const bool bad_before = (want != (s8)1);
    const bool bad_after = ((s8)(fsign[fa] * fsign[fb]) != want);
    rep.orient_pairs_total++;
    rep.orient_pairs_inconsistent_before += bad_before ? 1 : 0;
    rep.orient_pairs_inconsistent_after += bad_after ? 1 : 0;
    if (a.true_manifold) {
      rep.orient_pairs_true_manifold++;
      rep.orient_pairs_true_inconsistent_before += bad_before ? 1 : 0;
      rep.orient_pairs_true_inconsistent_after += bad_after ? 1 : 0;
    } else {
      rep.orient_pairs_weak++;
      rep.orient_pairs_weak_inconsistent_before += bad_before ? 1 : 0;
      rep.orient_pairs_weak_inconsistent_after += bad_after ? 1 : 0;
    }
  }

  // =============================================================================================
  // 7. NORMALS. Rebuild every coincident vertex's normal from FACE GEOMETRY over the welded
  //    topology, crease-clustered so genuine hard edges stay crisp, and give every member of a
  //    cluster the SAME normal. Deriving from geometry (not from the incoming packed normal) makes
  //    this idempotent: running it after the existing per-tree/global passes cannot compound their
  //    smoothing, it simply supersedes it with the ground truth over a strictly larger weld map.
  // =============================================================================================
  std::vector<u8> group_crease(num_groups, 0);
  if ((cfg.bits & kMeshBitNoNormal) == 0) {
    // CSR: group -> incident (face, corner-vertex) pairs
    std::vector<u32> icnt(num_groups + 1, 0);
    for (size_t f = 0; f < F; f++) {
      for (int e = 0; e < 3; e++) {
        icnt[group[faces[f][e]]]++;
      }
    }
    std::vector<u32> ioff(num_groups + 1, 0);
    for (u32 g = 0; g < num_groups; g++) {
      ioff[g + 1] = ioff[g] + icnt[g];
    }
    std::vector<u64> iflat(ioff[num_groups]);  // (face<<2)|corner
    {
      std::vector<u32> cur(ioff.begin(), ioff.end() - 1);
      for (size_t f = 0; f < F; f++) {
        for (int e = 0; e < 3; e++) {
          iflat[cur[group[faces[f][e]]]++] = ((u64)f << 2) | (u64)e;
        }
      }
    }
    // Scratch hoisted OUT of the group loop: a level has ~10^6 groups, so a per-group allocation
    // (or worse, a per-group hash map) would dominate the whole pass.
    std::vector<math::Vector3f> cacc, cunit;
    std::vector<u32> cpacked;
    std::vector<std::pair<float, u32>> order;  // (area, iflat slot)
    std::vector<int> kcluster;
    std::vector<float> vbest(N, -1.f);  // per-vertex largest incident face area seen so far
    for (u32 g = 0; g < num_groups; g++) {
      const u32 i0 = ioff[g], i1 = ioff[g + 1];
      if (i0 == i1) {
        continue;
      }
      cacc.clear();
      cunit.clear();
      // cluster the incident faces by crease angle; the largest face establishes each cluster
      order.clear();
      order.reserve(i1 - i0);
      for (u32 k = i0; k < i1; k++) {
        const u32 f = (u32)(iflat[k] >> 2);
        const math::Vector3f nr = face_normal(f) * (float)fsign[f];
        order.emplace_back(nr.length(), k);
      }
      std::sort(order.begin(), order.end(),
                [](const std::pair<float, u32>& a, const std::pair<float, u32>& b) {
                  return a.first != b.first ? a.first > b.first : a.second < b.second;
                });
      kcluster.assign(i1 - i0, -1);
      for (const auto& od : order) {
        if (!(od.first > 1e-6f)) {
          continue;
        }
        const u32 k = od.second;
        const u32 f = (u32)(iflat[k] >> 2);
        const math::Vector3f nr = face_normal(f) * (float)fsign[f];
        const math::Vector3f un = nr * (1.f / od.first);
        int found = -1;
        for (size_t c = 0; c < cunit.size(); c++) {
          if (un.dot(cunit[c]) >= crease_cos) {
            found = (int)c;
            break;
          }
        }
        if (found < 0) {
          found = (int)cunit.size();
          cunit.push_back(un);
          cacc.push_back(nr);
        } else {
          cacc[found] += nr;
        }
        kcluster[k - i0] = found;
      }
      if (cunit.empty()) {
        continue;
      }
      if (cunit.size() >= 2) {
        group_crease[g] = 1;
        rep.groups_crease_after++;
      }
      cpacked.assign(cacc.size(), 0);
      for (size_t c = 0; c < cacc.size(); c++) {
        const float l = cacc[c].length();
        const math::Vector3f nn = l > 1e-6f ? cacc[c] * (1.f / l) : cunit[c];
        cpacked[c] = pack_nor(nn);
      }
      // ==========================================================================================
      // Every corner takes its cluster's shared normal. A vertex whose corners fall in SEVERAL
      // clusters has to pick one, and the classic rule is "the cluster of the largest incident
      // face". That rule is wrong for displacement, and measurably so.
      //
      // The tessellator moves the vertex along THIS normal for EVERY patch that references it
      // (tfrag3_tess.tese:421 `world += N * disp`). A box-edge vertex shared by a big top face and a
      // small side face gets the top face's normal under the largest-face rule; the side patch then
      // displaces along a direction ~90 degrees from its own outward, so dot(N, outward) sits at or
      // below zero and half of its checker squares move the wrong way. The vertex normal is not just
      // a shading quantity here — it is the displacement axis of every face that uses it.
      //
      // So choose, among the clusters this vertex actually touches, the one whose normal has the
      // best WORST-CASE agreement with the vertex's own incident faces: maximise
      // min_j dot(cluster_normal, unit_face_normal_j). Ties go to the lowest cluster index, and
      // clusters were created in descending area order, so on a tie this reduces EXACTLY to the old
      // largest-face rule — the change only bites where one cluster is strictly better for every
      // face the vertex belongs to, which is the case it was getting wrong. Shading is unaffected
      // wherever a vertex sits in a single cluster, i.e. everywhere except hard edges.
      // ==========================================================================================
      // The max-min search is cubic in the group's incidence count. Groups are small (a handful of
      // corners), but a pathological weld could produce a large one, so above a cap fall back to the
      // legacy largest-face rule rather than let one group dominate the pass. Measured on village1
      // the cap is never reached; it is a guard, not a behaviour.
      const bool maxmin_ok = (i1 - i0) <= 32;
      for (u32 k = i0; k < i1; k++) {
        const int c = kcluster[k - i0];
        if (c < 0) {
          continue;
        }
        const u32 f = (u32)(iflat[k] >> 2);
        const u32 e = (u32)(iflat[k] & 3);
        const u32 gvi = faces[f][e];
        if (!maxmin_ok) {
          const float area = face_normal(f).length();
          if (area > vbest[gvi]) {
            vbest[gvi] = area;
            *nor_ptr(gvi) = cpacked[c];
          }
          continue;
        }
        if (vbest[gvi] >= 0.f) {
          continue;  // already decided by the max-min pass below
        }
        // Gather this vertex's incident (cluster, unit face normal) pairs within the group.
        int best_c = -1;
        double best_score = -2.0;
        for (u32 k2 = i0; k2 < i1; k2++) {
          const int c2 = kcluster[k2 - i0];
          if (c2 < 0) {
            continue;
          }
          const u32 f2 = (u32)(iflat[k2] >> 2);
          if (faces[f2][(u32)(iflat[k2] & 3)] != gvi) {
            continue;
          }
          const math::Vector3f cn = unpack_nor(cpacked[c2]);
          double score = 2.0;
          for (u32 k3 = i0; k3 < i1; k3++) {
            const int c3 = kcluster[k3 - i0];
            if (c3 < 0) {
              continue;
            }
            const u32 f3 = (u32)(iflat[k3] >> 2);
            if (faces[f3][(u32)(iflat[k3] & 3)] != gvi) {
              continue;
            }
            const math::Vector3f nr3 = face_normal(f3) * (float)fsign[f3];
            const float l3 = nr3.length();
            if (!(l3 > 1e-6f)) {
              continue;
            }
            score = std::min(score, (double)cn.dot(nr3 * (1.f / l3)));
          }
          // strictly-better only, so equal scores keep the FIRST (= largest-area) cluster
          if (score > best_score + 1e-9) {
            best_score = score;
            best_c = c2;
          }
        }
        if (best_c >= 0) {
          vbest[gvi] = 0.f;  // decided
          *nor_ptr(gvi) = cpacked[best_c];
          if (best_c != c) {
            rep.orient_vertex_cluster_rechosen++;
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------------------------------------
  // 7b. TANGENT HANDEDNESS FOLLOWS THE CORRECTED NORMAL (round 22, the parallax half of defect C).
  //     reconstruct_tfrag_tangents() computes tangents[i].w at UNPACK time, from the normal the
  //     vertex had then: w = sign(dot(cross(N_old, T), B)). The shader rebuilds the bitangent as
  //     cross(N, T) * w, so when the orientation pass above inverts N the bitangent silently flips
  //     with it unless w flips too. A stale w inverts the V axis of the tangent frame, which inverts
  //     the tangent-space view vector the POM march walks along => the parallax digs in where it
  //     should pop out. Decided on the FINAL normal (the pass-7 loop can write a vertex several
  //     times, largest-incident-face wins), against the pre-consolidation snapshot.
  //
  // ===== ROUND 31: FLIPPING THE SIGN WAS NEVER ENOUGH. RE-DERIVE THE WHOLE FRAME. ================
  // The rule above only acts when the new normal is INVERTED (dot < 0). But pass 7 does not merely
  // invert normals, it REBUILDS them: welded across chunks, crease-clustered, area-averaged. A
  // vertex whose normal was ROTATED into a different smoothing cluster — not inverted — kept a w
  // computed against a frame that no longer exists, and w is only meaningful relative to the N the
  // shader pairs it with (B = cross(N,T)*w, pbr_fused.glsl:12-29). That population is large and the
  // pipeline has been MEASURING it for several rounds without writing anything back:
  //   [tan-frame] level=village1 pairs=1264479 handedness_mismatch=342860   (27.1%)
  // and the offline CPU port of the two tiers puts the same number on the parallax grade directly:
  // on beach, 27.85% of graded face corners had dot(B, dPdv) < 0, i.e. the POM march inverted in V
  // while the tessellation tier — which uses N alone and never touches w — stayed correct. That is
  // precisely the owner's "le mur du rez-de-chaussée est inversé EN PARALLAX mais pas en
  // tessellation": one axis, one cause, and it is this one.
  // So do not patch the sign. Re-run the SAME Lengyel accumulation that produced the tangents in the
  // first place, now against the FINAL normals, so (T, w) is right by construction rather than
  // right-if-nothing-moved. The old flip is subsumed: an inverted normal is just the extreme case.
  {
    const u64 retan = retangent_level_from_final_normals(lev);
    rep.orient_tangent_w_flipped += retan;
    lg::info("[mesh-consolidate] level={} retangent from final normals: {} vertex frames rewritten",
             lev.level_name, retan);
  }

  measure_normal_delta(rep.nrm_after, nullptr, false);
  crease_filter = &group_crease;
  measure_normal_delta(rep.nrm_smooth_before, &nor_before, true);
  measure_normal_delta(rep.nrm_smooth_after, nullptr, true);
  for (u32 g = 0; g < num_groups; g++) {
    if (group_refcount2[g] && !group_crease[g]) {
      // a single-cluster (smooth) group must end with ONE shared normal — any residual delta here
      // is a real bug in the pass, so it is reported rather than hidden.
      u32 first = 0;
      bool have = false, split = false;
      for (u32 k = goff[g]; k < goff[g + 1]; k++) {
        const u32 i = gflat[k];
        if (!referenced[i] || *nor_ptr(i) == 0) {
          continue;
        }
        if (!have) {
          first = *nor_ptr(i);
          have = true;
        } else if (*nor_ptr(i) != first) {
          split = true;
        }
      }
      if (split) {
        rep.groups_smooth_split_after++;
      }
    }
  }

  // =============================================================================================
  // 8. THE COUTURE: BAKED-COLOUR BLEND. The baked lighting is a per-tree time-of-day PALETTE indexed
  //    per vertex, so two chunks meeting at a seam can carry visibly different baked colour for the
  //    same physical point — a lighting STEP that is completely independent of the normal map, which
  //    is exactly the seam the owner still sees at relief 0. Fix: average the group's colour over
  //    all 8 palettes x 4 channels, append that colour to each member tree's palette (deduplicated,
  //    quad-aligned so the SIMD interpolator covers it) and repoint the member's index.
  // =============================================================================================
  if ((cfg.bits & kMeshBitNoColour) == 0) {
    // Per tree: a lookup from a QUANTIZED 32-byte colour to a palette index, PRE-POPULATED with the
    // palette's existing entries. Most blended averages land on a colour the palette already holds,
    // so the overwhelming majority of groups cost zero new entries — which matters because the
    // renderer's time-of-day LUT is hard-capped at 8192 colours per tree and a naive append-always
    // scheme exhausted it (measured: 15030 groups skipped on village1 alone).
    // Two-level nearest-neighbour lookup: a COARSE quantized bucket narrows the candidates, then the
    // true per-channel distance decides. Exact-match-only reuse is far too strict on a continuously
    // varying baked palette (measured: 13100 of the 14439 groups that needed a blend were skipped
    // because their tree's palette had already exhausted its 8192 entries).
    constexpr int kBucketQ = 24;
    const u32 reuse_tol = std::max(2u, cfg.col_blend_threshold / 2);
    auto bucket_key = [](const u8* c) {
      char q[32];
      for (int b = 0; b < 32; b++) {
        q[b] = (char)(u8)(c[b] / kBucketQ);
      }
      return std::string(q, 32);
    };
    struct PalCache {
      std::unordered_map<std::string, std::vector<u32>> buckets;
      std::vector<std::array<u8, 32>> colours;  // parallel to palette index
      bool built = false;
    };
    std::unordered_map<PackedTimeOfDay*, PalCache> pal_cache;
    auto cache_for = [&](PackedTimeOfDay* pal) -> PalCache& {
      PalCache& pc = pal_cache[pal];
      if (!pc.built) {
        pc.built = true;
        pc.colours.resize(pal->color_count);
        for (u32 ci = 0; ci < pal->color_count; ci++) {
          const size_t need = ((size_t)(ci / 4) + 1) * 128;
          if (pal->data.size() < need) {
            pc.colours.resize(ci);
            break;
          }
          for (int p = 0; p < kPaletteCount; p++) {
            for (int c = 0; c < 4; c++) {
              pc.colours[ci][p * 4 + c] = pal->read((int)ci, p, c);
            }
          }
          pc.buckets[bucket_key(pc.colours[ci].data())].push_back(ci);
        }
      }
      return pc;
    };
    // find an existing palette colour within reuse_tol of `want`, else -1
    auto find_reusable = [&](PalCache& pc, const u8* want) -> int {
      auto it = pc.buckets.find(bucket_key(want));
      if (it == pc.buckets.end()) {
        return -1;
      }
      int best = -1;
      u32 best_d = reuse_tol + 1;
      for (u32 ci : it->second) {
        u32 d = 0;
        for (int b = 0; b < 32 && d <= reuse_tol; b++) {
          d = std::max(d, (u32)std::abs((int)pc.colours[ci][b] - (int)want[b]));
        }
        if (d <= reuse_tol && d < best_d) {
          best_d = d;
          best = (int)ci;
        }
      }
      return best;
    };
    u8 cur[32];
    double acc[32];
    for (u32 g = 0; g < num_groups; g++) {
      if (!group_refcount2[g]) {
        continue;
      }
      // measure the group's spread first; only blend where there is a real step
      u8 lo[32], hi[32];
      bool have = false;
      u32 n = 0;
      for (int b = 0; b < 32; b++) {
        acc[b] = 0;
      }
      for (u32 k = goff[g]; k < goff[g + 1]; k++) {
        const u32 i = gflat[k];
        if (!referenced[i] || !read_colour(i, cur)) {
          continue;
        }
        if (!have) {
          std::memcpy(lo, cur, 32);
          std::memcpy(hi, cur, 32);
          have = true;
        } else {
          for (int b = 0; b < 32; b++) {
            lo[b] = std::min(lo[b], cur[b]);
            hi[b] = std::max(hi[b], cur[b]);
          }
        }
        for (int b = 0; b < 32; b++) {
          acc[b] += cur[b];
        }
        n++;
      }
      if (!have || n < 2) {
        continue;
      }
      u32 spread = 0;
      for (int b = 0; b < 32; b++) {
        spread = std::max(spread, (u32)(hi[b] - lo[b]));
      }
      if (spread < cfg.col_blend_threshold) {
        continue;
      }
      u8 avg[32];
      for (int b = 0; b < 32; b++) {
        avg[b] = (u8)std::lround(acc[b] / (double)n);
      }
      bool blended_any = false;
      for (u32 k = goff[g]; k < goff[g + 1]; k++) {
        const u32 i = gflat[k];
        if (!referenced[i]) {
          continue;
        }
        PackedTimeOfDay* pal = trees[gtree[i]].colors;
        if (!pal || pal->color_count == 0) {
          continue;
        }
        PalCache& pc = cache_for(pal);
        const int reuse = find_reusable(pc, avg);
        u32 new_idx;
        if (reuse >= 0) {
          new_idx = (u32)reuse;  // the palette already holds this colour: zero cost
        } else {
          if (pal->color_count + 1 > kMaxPaletteColors) {
            rep.col_skipped_cap++;
            continue;
          }
          new_idx = pal->color_count;
          const size_t need = ((size_t)(new_idx / 4) + 1) * 128;
          if (pal->data.size() < need) {
            pal->data.resize(need, 0);
          }
          for (int p = 0; p < kPaletteCount; p++) {
            for (int c = 0; c < 4; c++) {
              pal->read((int)new_idx, p, c) = avg[p * 4 + c];
            }
          }
          pal->color_count = new_idx + 1;
          if (pc.colours.size() <= new_idx) {
            pc.colours.resize(new_idx + 1);
          }
          std::memcpy(pc.colours[new_idx].data(), avg, 32);
          pc.buckets[bucket_key(avg)].push_back(new_idx);
          rep.col_palette_entries_added++;
        }
        *cidx_ptr(i) = (u16)new_idx;
        if (bake) {
          bake->cidx_idx.push_back(i);
          bake->cidx_val.push_back((u16)new_idx);
        }
        blended_any = true;
      }
      if (blended_any) {
        rep.col_groups_blended++;
      }
    }
    // The SIMD time-of-day interpolator walks WHOLE quads (color_count / 4), so a palette that ends
    // mid-quad would silently drop its last colours. Round every palette we touched up to a quad.
    for (auto& kv : pal_cache) {
      PackedTimeOfDay* pal = kv.first;
      const u32 rounded = ((pal->color_count + 3) / 4) * 4;
      const size_t need = ((size_t)rounded / 4) * 128;
      if (pal->data.size() < need) {
        pal->data.resize(need, 0);
      }
      pal->color_count = std::min(rounded, kMaxPaletteColors);
    }
  }

  measure_colour_delta(rep.col_after);

  // =============================================================================================
  // 9. SEAM WEIGHTS (the see-through tessellation slits). A vertex may only be displaced when BOTH
  //    sides of every edge it touches will displace identically. That is false at:
  //      - a MATERIAL boundary  (the height map is bound PER DRAW; the other side may have none)
  //      - a tfrag<->tie junction (tie is never tessellated at all)
  //      - a genuine OPEN boundary (nothing on the other side to match)
  //      - a hard CREASE group  (the two sides carry different normals, so they displace apart)
  //    Everywhere else the world-space height lookup in the evaluation shader guarantees both sides
  //    sample the same height, so the relief is preserved at full strength.
  // =============================================================================================
  if ((cfg.bits & kMeshBitNoSeam) == 0) {
    for (u32 g = 0; g < num_groups; g++) {
      bool material = group_multitex[g];
      bool system = group_multisystem[g];
      bool open = g < group_open.size() && group_open[g] != 0;
      bool crease = group_crease[g] != 0 && group_refcount2[g];
      const bool seam = material || system || open || crease;
      for (u32 k = goff[g]; k < goff[g + 1]; k++) {
        const u32 i = gflat[k];
        if (sys_of(i) == kSysShrub) {
          *seam_ptr(i) = 0;  // shrub is never tessellated; keep it explicitly un-displaced
          sys_audit(kSysShrub).seam_verts++;
          continue;
        }
        *seam_ptr(i) = seam ? 0 : 0xffff;
        if (seam) {
          sys_audit(sys_of(i)).seam_verts++;
        }
      }
      if (seam) {
        const u32 members = goff[g + 1] - goff[g];
        rep.seam_verts += members;
        if (material) {
          rep.seam_verts_material += members;
        }
        if (system) {
          rep.seam_verts_system += members;
        }
        if (open) {
          rep.seam_verts_open += members;
        }
        if (crease) {
          rep.seam_verts_crease += members;
        }
      }
    }
  }

  // =============================================================================================
  // 10. UV FRAME COHERENCE (carried over from the previous phase — still a useful seam signal).
  // =============================================================================================
  for (u32 g = 0; g < num_groups; g++) {
    if (!group_refcount2[g] || !group_multitree[g]) {
      continue;
    }
    rep.uv_groups++;
    bool have = false;
    float s0 = 0, t0 = 0;
    bool incoherent = false;
    for (u32 k = goff[g]; k < goff[g + 1]; k++) {
      const u32 i = gflat[k];
      if (!referenced[i]) {
        continue;
      }
      const float* st = (const float*)(gvert[i] + trees[gtree[i]].layout->st_off);
      if (!have) {
        s0 = st[0];
        t0 = st[1];
        have = true;
      } else {
        rep.uv_pairs++;
        const float ds = std::abs(st[0] - s0), dt = std::abs(st[1] - t0);
        if (ds > 0.05f || dt > 0.05f) {
          rep.uv_pairs_over30++;
          incoherent = true;
        }
      }
    }
    if (incoherent) {
      rep.uv_incoherent_groups++;
    }
  }

  // =============================================================================================
  // 10b. UV DETERMINANT / TANGENT-HANDEDNESS CENSUS (round 28). MEASUREMENT ONLY — this block reads
  //      the mesh and writes nothing but counters.
  //
  //      The block above compares raw s/t COORDINATES across a welded group; it says nothing about
  //      the HANDEDNESS of the UV frame. That is a separate defect axis. For each triangle,
  //          det = du1*dv2 - du2*dv1
  //      is negative exactly where the authored chart is MIRRORED, and the tangent basis is
  //      left-handed there. reconstruct_tfrag_tangents() (common/custom_data/TFrag3Data.cpp:2072)
  //      derives the stored handedness as `(N.cross(T).dot(bit_acc[i]) < 0) ? -1 : 1` from a
  //      bitangent ACCUMULATED over every incident triangle — so on a vertex touched by both a
  //      positive-det and a negative-det triangle the two contributions CANCEL and w is decided by
  //      numerical noise. Those vertices are a parallax-only inversion the orientation pass above
  //      cannot see (it only ever moves N, and 7b keeps w consistent with N). Counting them is how
  //      we find out whether that axis is live at all.
  // =============================================================================================
  {
    std::vector<u8> uv_pos(N, 0), uv_neg(N, 0);
    for (size_t f = 0; f < F; f++) {
      const auto& t = faces[f];
      const float* st0 = (const float*)(gvert[t[0]] + trees[gtree[t[0]]].layout->st_off);
      const float* st1 = (const float*)(gvert[t[1]] + trees[gtree[t[1]]].layout->st_off);
      const float* st2 = (const float*)(gvert[t[2]] + trees[gtree[t[2]]].layout->st_off);
      const double du1 = (double)st1[0] - (double)st0[0];
      const double dv1 = (double)st1[1] - (double)st0[1];
      const double du2 = (double)st2[0] - (double)st0[0];
      const double dv2 = (double)st2[1] - (double)st0[1];
      const double det = du1 * dv2 - du2 * dv1;
      rep.uv_tris_total++;
      if (std::abs(det) <= 1e-12) {
        rep.uv_tris_degenerate++;
        continue;  // no usable UV frame: it belongs to neither handedness
      }
      if (det < 0) {
        rep.uv_tris_mirrored++;
        uv_neg[t[0]] = uv_neg[t[1]] = uv_neg[t[2]] = 1;
      } else {
        uv_pos[t[0]] = uv_pos[t[1]] = uv_pos[t[2]] = 1;
      }
    }
    for (size_t i = 0; i < N; i++) {
      if (uv_pos[i] && uv_neg[i]) {
        rep.uv_verts_handedness_split++;
      }
    }
  }

  // ---- totals ----
  auto accum = [](MeshAuditSystem& tot, const MeshAuditSystem& s) {
    tot.trees += s.trees;
    tot.verts += s.verts;
    tot.verts_referenced += s.verts_referenced;
    tot.tris += s.tris;
    tot.edges_raw += s.edges_raw;
    tot.open_raw += s.open_raw;
    tot.coincident_unshared += s.coincident_unshared;
    tot.coincident_unshared_pairs += s.coincident_unshared_pairs;
    tot.open_by_group += s.open_by_group;
    tot.seam_verts += s.seam_verts;
  };
  accum(rep.total, rep.tfrag);
  accum(rep.total, rep.tie);
  accum(rep.total, rep.shrub);

  // ---- capture the precompute sidecar payload ----
  if (bake) {
    bake->num_verts = N;
    bake->nor.resize(N);
    bake->seam_bits.assign((N + 7) / 8, 0);
    for (size_t i = 0; i < N; i++) {
      bake->nor[i] = *nor_ptr(i);
      if (*seam_ptr(i) != 0) {
        bake->seam_bits[i >> 3] |= (u8)(1u << (i & 7));
      }
    }
    for (size_t t = 0; t < trees.size(); t++) {
      PackedTimeOfDay* pal = trees[t].colors;
      if (!pal || pal->color_count == orig_color_count[t]) {
        continue;  // untouched palette: nothing to store
      }
      MeshBakeData::PalDelta d;
      d.tree = (u32)t;
      d.new_color_count = pal->color_count;
      // the appended colours start at the quad the ORIGINAL count ended in — appending can rewrite
      // the unused slots of that partial quad, so the tail must start there, not at the next quad
      d.tail_off = (orig_color_count[t] / 4) * 128;
      if (pal->data.size() > d.tail_off) {
        d.tail.assign(pal->data.begin() + d.tail_off, pal->data.end());
      }
      bake->pal.push_back(std::move(d));
    }
  }

  rep.elapsed_ms =
      std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t_start).count();
  rep.ran = true;
  if (out) {
    *out = rep;
  }
}

// ---------------------------------------------------------------------------------------------
// reporting
// ---------------------------------------------------------------------------------------------

static std::string sysline(const char* name, const MeshAuditSystem& s) {
  return fmt::format(
      "  {:<6} trees={:<4} verts={:<9} ref={:<9} tris={:<9} edges={:<9} open_raw={:<8} "
      "COINCIDENT_UNSHARED={:<8} pairs={:<8} open_by_group={}\n",
      name, s.trees, s.verts, s.verts_referenced, s.tris, s.edges_raw, s.open_raw,
      s.coincident_unshared, s.coincident_unshared_pairs, s.open_by_group);
}

static std::string histline(const char* name, const MeshDeltaHist& h, const char* unit) {
  return fmt::format("  {:<22} n={:<8} mean={:<8.3f} max={:<8.3f} hist[{} {} {} {} {}] ({})\n", name,
                     h.n, h.mean(), h.max, h.bucket[0], h.bucket[1], h.bucket[2], h.bucket[3],
                     h.bucket[4], unit);
}

std::string format_mesh_audit(const MeshAuditReport& r, const MeshConsolidateConfig& cfg) {
  std::string o;
  o += fmt::format("===== MESH AUDIT level={} game={} =====\n", r.level_name,
                   r.game_name.empty() ? "?" : r.game_name);
  if (!r.ran) {
    o += "  (no renderable geometry)\n";
    return o;
  }
  o += fmt::format("  cfg weld={:.3f}m wide={:.3f}m crease={:.1f}deg colthr={} bits={}\n",
                   cfg.weld_m, cfg.weld_m * cfg.wide_scale, cfg.crease_deg, cfg.col_blend_threshold,
                   cfg.bits);
  o += "-- TOPOLOGY (per system; COINCIDENT_UNSHARED = the forgotten welds) --\n";
  o += sysline("tfrag", r.tfrag);
  o += sysline("tie", r.tie);
  o += sysline("shrub", r.shrub);
  o += sysline("TOTAL", r.total);
  o += fmt::format(
      "-- WELD -- groups={} coincident_groups={} multitree={} multisystem={} "
      "wide_reweld_rounds={} wide_reweld_unions={}\n",
      r.groups, r.groups_coincident, r.groups_multitree, r.groups_multisystem,
      r.wide_reweld_rounds, r.wide_reweld_unions);
  o += fmt::format(
      "-- RESIDUAL OMISSIONS -- open edge pairs still unshared after the exhaustive weld: "
      "MISSED_WELDS_REMAINING={} (of {} coincident-but-unshared edges before) --\n",
      r.total.missed_welds, r.total.coincident_unshared);
  o += "-- NORMAL DISCONTINUITY across welded groups (degrees) --\n";
  o += histline("normal delta BEFORE", r.nrm_before, "<1 <5 <15 <45 >=45 deg");
  o += histline("normal delta AFTER", r.nrm_after, "<1 <5 <15 <45 >=45 deg");
  o += histline("SMOOTH-only BEFORE", r.nrm_smooth_before, "<1 <5 <15 <45 >=45 deg");
  o += histline("SMOOTH-only AFTER", r.nrm_smooth_after, "<1 <5 <15 <45 >=45 deg");
  o += fmt::format("  crease groups kept sharp={}  smooth groups STILL split (must be 0)={}\n",
                   r.groups_crease_after, r.groups_smooth_split_after);
  o += "-- BAKED COLOUR DISCONTINUITY across welded groups (0-255 per channel) --\n";
  o += histline("baked colour BEFORE", r.col_before, "<2 <8 <24 <64 >=64");
  o += histline("baked colour AFTER", r.col_after, "<2 <8 <24 <64 >=64");
  o += fmt::format("  groups blended={} palette entries added={} skipped(cap)={}\n",
                   r.col_groups_blended, r.col_palette_entries_added, r.col_skipped_cap);
  o += fmt::format("-- POSITION SNAP -- verts moved={} max move={:.5f} m (coincident verts are now "
                   "bit-identical: tess edge factors match)\n",
                   r.pos_snapped, r.pos_snap_max_m);
  o += fmt::format(
      "-- ORIENTATION -- components={} faces flipped={} collision-decided components={} "
      "faces the collision mesh can judge={} faces still inward vs collision={}"
      " collision-incompetent components={}\n",
      r.orient_components, r.orient_faces_flipped, r.orient_comps_collision_decided,
      r.orient_faces_authority, r.orient_faces_inward_after,
      r.orient_comps_collision_incompetent);
  o += fmt::format(
      "-- ORIENTATION SECOND AUTHORITY (geometric, deterministic) -- "
      "orient_comps_no_authority={} orient_faces_no_authority={} "
      "orient_comps_volume_decided={} orient_comps_raycast_decided={} "
      "orient_comps_undecided={}\n",
      r.orient_comps_no_authority, r.orient_faces_no_authority, r.orient_comps_volume_decided,
      r.orient_comps_raycast_decided, r.orient_comps_undecided);
  o += fmt::format(
      "-- ORIENTATION AUTHORITY SCORED AGAINST SIGNED VOLUME (round 29) -- volume_confident={} "
      "collraw_conflicts={} collfiltered_conflicts={}\n",
      r.orient_comps_volume_confident, r.orient_comps_collraw_vs_volume_conflict,
      r.orient_comps_collfiltered_vs_volume_conflict);
  // ONE physical line (a validator greps it line-wise): the round-31 per-face geometric outward vote.
  o += fmt::format(
      "-- ORIENTATION GEOMETRIC OUTWARD VOTE (round 31, kMeshBitGeomOrient=512) -- "
      "orient_faces_geom_voted={} orient_faces_geom_abstained={} orient_comps_geom_decided={} "
      "orient_comps_geom_vs_collision_conflict={} orient_comps_geom_vs_volume_conflict={} "
      "orient_faces_geom_repaired={} orient_comps_closed_volume_decided={} "
      "orient_comps_geom_overruled_by_volume={} orient_comps_criteria_conflict={} "
      "orient_geom_pass_ms={:.1f}\n",
      r.orient_faces_geom_voted, r.orient_faces_geom_abstained, r.orient_comps_geom_decided,
      r.orient_comps_geom_vs_collision_conflict, r.orient_comps_geom_vs_volume_conflict,
      r.orient_faces_geom_repaired, r.orient_comps_closed_volume_decided,
      r.orient_comps_geom_overruled_by_volume, r.orient_comps_criteria_conflict,
      r.orient_geom_pass_ms);
  o += fmt::format(
      "-- ORIENTATION POLARITY (authority-free, every level) -- manifold non-duplicate pairs={} "
      "orient_pairs_inconsistent_before={} orient_pairs_inconsistent_after={} "
      "orient_tangent_w_flipped={}\n",
      r.orient_pairs_total, r.orient_pairs_inconsistent_before, r.orient_pairs_inconsistent_after,
      r.orient_tangent_w_flipped);
  o += fmt::format(
      "-- ORIENTATION POLARITY BY PAIR CLASS -- true_manifold pairs={} before={} after={} | "
      "weak(chained/non-manifold) pairs={} before={} after={}\n",
      r.orient_pairs_true_manifold, r.orient_pairs_true_inconsistent_before,
      r.orient_pairs_true_inconsistent_after, r.orient_pairs_weak,
      r.orient_pairs_weak_inconsistent_before, r.orient_pairs_weak_inconsistent_after);
  o += fmt::format(
      "-- SEAM per system (only tfrag is ever tessellated) -- tfrag={} of {} referenced, tie={}, "
      "shrub={}\n",
      r.tfrag.seam_verts, r.tfrag.verts_referenced, r.tie.seam_verts, r.shrub.seam_verts);
  o += fmt::format(
      "-- SEAM-CONSISTENT DISPLACEMENT -- seam verts={} (material={} system={} open={} crease={}); "
      "coincident verts sample an IDENTICAL world-space height and displace along an IDENTICAL "
      "normal, seam verts do not displace at all\n",
      r.seam_verts, r.seam_verts_material, r.seam_verts_system, r.seam_verts_open,
      r.seam_verts_crease);
  o += fmt::format("-- UV FRAME -- cross-chunk groups={} pairs={} incoherent pairs={} "
                   "incoherent groups={}\n",
                   r.uv_groups, r.uv_pairs, r.uv_pairs_over30, r.uv_incoherent_groups);
  o += fmt::format(
      "-- UV DETERMINANT (tangent handedness census, round 28) -- uv_tris_total={} "
      "uv_tris_mirrored={} uv_tris_degenerate={} uv_verts_handedness_split={}\n",
      r.uv_tris_total, r.uv_tris_mirrored, r.uv_tris_degenerate, r.uv_verts_handedness_split);
  o += fmt::format("-- elapsed {:.1f} ms --\n", r.elapsed_ms);
  return o;
}

// ---------------------------------------------------------------------------------------------
// PRECOMPUTE SIDECAR
//
// The consolidation is deterministic and depends only on the level's geometry, so it never needs to
// run twice. Baking it costs 45 s ONCE on a desktop and turns into a ~0.2 s upload at load time on
// the phone — which matters a lot, because measured on the Redmi the live pass added 45.8 s to
// village1's load (67 s total unpack). A level that HAS a sidecar skips the live pass entirely; a
// level that does not (a mod, an un-baked game) still gets the full live pass, so nothing is lost.
//
// Stored SPARSELY: normals and seam bits are dense (they change nearly everywhere), but positions
// and colour indices are stored as index/value pairs (a few hundred and a few tens of thousands of
// entries respectively, out of ~1.9M vertices), and palettes carry only their appended tail. Then
// the whole thing is zstd'd. That keeps village1 to a few MB rather than the ~40 MB a dense dump
// would need.
// ---------------------------------------------------------------------------------------------

std::string mesh_consolidate_bake_name(const std::string& level_name) {
  return level_name + ".meshweld";
}

std::vector<u8> mesh_consolidate_bake_serialize(const std::string& level_name,
                                                const MeshBakeData& b) {
  BW w;
  w.u32v(kBakeMagic);
  w.u32v(kBakeVersion);
  write_fingerprint(w, level_name, b.tree_fp, b.num_verts);

  w.u32v((u32)b.nor.size());
  w.raw(b.nor.data(), b.nor.size() * sizeof(u32));
  w.u32v((u32)b.seam_bits.size());
  w.raw(b.seam_bits.data(), b.seam_bits.size());

  w.u32v((u32)b.pos_idx.size());
  w.raw(b.pos_idx.data(), b.pos_idx.size() * sizeof(u32));
  w.raw(b.pos_val.data(), b.pos_val.size() * sizeof(float));

  w.u32v((u32)b.cidx_idx.size());
  w.raw(b.cidx_idx.data(), b.cidx_idx.size() * sizeof(u32));
  w.raw(b.cidx_val.data(), b.cidx_val.size() * sizeof(u16));

  w.u32v((u32)b.pal.size());
  for (const auto& p : b.pal) {
    w.u32v(p.tree);
    w.u32v(p.new_color_count);
    w.u32v(p.tail_off);
    w.u32v((u32)p.tail.size());
    w.raw(p.tail.data(), p.tail.size());
  }
  return compression::compress_zstd(w.d.data(), w.d.size());
}

bool mesh_consolidate_bake_write(const std::string& level_name,
                                 const MeshBakeData& b,
                                 const std::string& path) {
  try {
    const auto blob = mesh_consolidate_bake_serialize(level_name, b);
    file_util::write_binary_file(path, (void*)blob.data(), blob.size());
    return true;
  } catch (const std::exception& e) {
    lg::warn("[mesh-consolidate] bake write failed for {}: {}", path, e.what());
    return false;
  }
}

bool mesh_consolidate_apply_bake(Level& lev, const std::string& path, bool do_shrub) {
  std::vector<u8> raw;
  // Round 30 (delivery): the fingerprint of the bytes THIS PROCESS READ, so `md5sum` on the host can
  // prove which of the two copies (packaged vs external) actually reached the renderer. Two rounds of
  // geometry corrections were reported as "changed nothing" while nothing in any log named the file.
  std::string comp_md5 = "-";
  u64 comp_bytes = 0;
  try {
    if (!file_util::file_exists(path)) {
      return false;
    }
    auto comp = file_util::read_binary_file(path);
    comp_bytes = (u64)comp.size();
    comp_md5 = md5::hex(comp.data(), comp.size());
    raw = compression::decompress_zstd(comp.data(), comp.size());
  } catch (const std::exception& e) {
    lg::warn("[mesh-consolidate] sidecar {} (bytes={} md5={}) unreadable: {}", path, comp_bytes,
             comp_md5, e.what());
    return false;
  }
  BR r{raw.data(), raw.data() + raw.size()};
  // Read both header words into locals: short-circuiting the comparison used to hide WHICH of the two
  // was wrong, and a version mismatch is the exact failure mode that silently blits stale normals back.
  const u32 got_magic = r.u32v();
  const u32 got_version = r.u32v();
  if (got_magic != kBakeMagic || got_version != kBakeVersion) {
    lg::warn("[mesh-consolidate] sidecar {} (bytes={} md5={}) has the wrong magic/version "
             "(magic=0x{:08x} want 0x{:08x}, version={} want {}) — ignoring, the live pass will run "
             "instead",
             path, comp_bytes, comp_md5, got_magic, kBakeMagic, got_version, kBakeVersion);
    return false;
  }
  std::vector<GTree> trees;
  std::vector<u8*> gvert;
  std::vector<u32> gtree;
  gather_level(lev, do_shrub, trees, gvert, &gtree, nullptr);
  const u64 N = gvert.size();
  if (N == 0) {
    return false;
  }
  if (!check_fingerprint(r, lev.level_name, fingerprint_of(trees), N)) {
    lg::warn("[mesh-consolidate] sidecar {} (bytes={} md5={}) does not match this fr3 (rebuilt "
             "geometry?) — running the live pass instead",
             path, comp_bytes, comp_md5);
    return false;
  }
  // dense normals
  const u32 nor_n = r.u32v();
  if (!r.ok || nor_n != N) {
    return false;
  }
  // round-22: the sidecar path must do the same tangent-handedness correction pass 7b does in the
  // live pass, otherwise a baked level gets the corrected normals but keeps the stale w (the POM
  // march would then dig in where it should pop out on every vertex the orientation pass inverted).
  // Nothing new is stored for this: the OLD normal is still in the vertex when the new one lands, so
  // the flip is derivable at apply time — the file format is unchanged.
  // ROUND 31: the flip is no longer derived here at all. w is only meaningful relative to the N it
  // is paired with, and the sidecar rewrites N wholesale, so after the normals land the whole
  // tangent frame is re-derived from them with the same rule the live pass now uses. The two paths
  // must agree bit for bit or a baked level and a live-consolidated one would shade differently —
  // which is exactly the class of bug this phase has been chasing. Nothing new is stored: the
  // tangents are a pure function of (positions, uvs, indices, final normals), all of which the
  // sidecar has already restored by the time this runs. File format unchanged.
  u64 tan_flips = 0;
  for (u64 i = 0; i < N; i++) {
    const u32 v = r.u32v();
    u32* np = (u32*)(gvert[i] + trees[gtree[i]].layout->nor_off);
    *np = v;
  }
  // dense seam bits
  const u32 bits_n = r.u32v();
  if (!r.ok || bits_n != (N + 7) / 8) {
    return false;
  }
  {
    std::vector<u8> bits(bits_n);
    if (!r.raw(bits.data(), bits_n)) {
      return false;
    }
    for (u64 i = 0; i < N; i++) {
      *(u16*)(gvert[i] + trees[gtree[i]].layout->seam_off) =
          (bits[i >> 3] & (1u << (i & 7))) ? 0xffff : 0;
    }
  }
  // sparse positions
  {
    const u32 n = r.u32v();
    std::vector<u32> idx(n);
    std::vector<float> val(n * 3);
    if (!r.raw(idx.data(), n * sizeof(u32)) || !r.raw(val.data(), n * 3 * sizeof(float))) {
      return false;
    }
    for (u32 k = 0; k < n; k++) {
      if (idx[k] >= N) {
        return false;
      }
      float* pv = (float*)gvert[idx[k]];
      pv[0] = val[k * 3 + 0];
      pv[1] = val[k * 3 + 1];
      pv[2] = val[k * 3 + 2];
    }
  }
  // sparse colour indices
  {
    const u32 n = r.u32v();
    std::vector<u32> idx(n);
    std::vector<u16> val(n);
    if (!r.raw(idx.data(), n * sizeof(u32)) || !r.raw(val.data(), n * sizeof(u16))) {
      return false;
    }
    for (u32 k = 0; k < n; k++) {
      if (idx[k] >= N) {
        return false;
      }
      *(u16*)(gvert[idx[k]] + trees[gtree[idx[k]]].layout->cidx_off) = val[k];
    }
  }
  // palette tails (the colours the blend appended)
  {
    const u32 n = r.u32v();
    for (u32 k = 0; k < n; k++) {
      const u32 tree = r.u32v();
      const u32 new_count = r.u32v();
      const u32 tail_off = r.u32v();
      const u32 tail_len = r.u32v();
      std::vector<u8> tail(tail_len);
      if (!r.raw(tail.data(), tail_len) || tree >= trees.size() || !trees[tree].colors) {
        return false;
      }
      PackedTimeOfDay* pal = trees[tree].colors;
      if (pal->data.size() < (size_t)tail_off + tail_len) {
        pal->data.resize((size_t)tail_off + tail_len, 0);
      }
      std::memcpy(pal->data.data() + tail_off, tail.data(), tail_len);
      pal->color_count = new_count;
    }
  }
  if (!r.ok) {
    return false;
  }
  // ROUND 31 — re-derive the tangent frames LAST, once every input they depend on is restored:
  // the sparse POSITION patch above moves welded vertices, so doing this any earlier would build
  // the frames from pre-snap geometry and the baked path would disagree with the live one.
  tan_flips = retangent_level_from_final_normals(lev);
  lg::info("[mesh-consolidate] level={} loaded PRECOMPUTED sidecar ({} verts, tangent_w_flipped={}) "
           "— live pass skipped",
           lev.level_name, N, tan_flips);
  // Round 30 (delivery): name the file and fingerprint it on the SUCCESS path too, and mirror it into
  // the asset-route journal — the owner's phone shows no logcat, so files/asset_route.txt is the only
  // place the pair "which copy was opened" + "what its bytes hash to" can be read back off-device.
  const std::string opened = fmt::format(
      "[mesh-consolidate] level={} OPENED {} bytes={} md5={} bake_version={} -> APPLIED "
      "(verts={} tangent_w_flipped={})\n",
      lev.level_name, path, comp_bytes, comp_md5, kBakeVersion, N, tan_flips);
  file_util::asset_route_journal(opened);
  lg::info("{}", opened);
  return true;
}

void mesh_audit_append_file(const std::string& text) {
  try {
    const auto path = file_util::get_jak_project_dir() / "mesh_audit.txt";
    std::string existing;
    try {
      existing = file_util::read_text_file(path);
    } catch (...) {
      existing.clear();
    }
    if (existing.size() > 4u * 1024u * 1024u) {
      existing.clear();  // a long session must not fill the device
    }
    file_util::write_text_file(path, existing + text);
  } catch (const std::exception& e) {
    lg::warn("[mesh-consolidate] could not write mesh_audit.txt: {}", e.what());
  }
}

std::string mesh_audit_csv_header() {
  return "game,level,tfrag_tris,tie_tris,shrub_tris,total_tris,open_raw,coincident_unshared,"
         "coincident_unshared_pairs,open_by_group,missed_welds_remaining,groups,wide_rounds,"
         "wide_unions,nrm_smooth_max_before,nrm_smooth_max_after,nrm_smooth_mean_before,"
         "nrm_smooth_mean_after,nrm_max_before,nrm_max_after,nrm_mean_before,nrm_mean_after,col_max_before,"
         "col_max_after,col_mean_before,col_mean_after,col_groups_blended,pos_snapped,"
         "orient_flipped,orient_inward_after,seam_verts,"
         // round-22 columns APPENDED so every previously written csv stays readable
         "orient_pairs_total,orient_pairs_inconsistent_before,orient_pairs_inconsistent_after,"
         "orient_tangent_w_flipped,"
         // round-22 refinement: the same population split by pair class (true + weak == total)
         "orient_pairs_true,orient_pairs_true_before,orient_pairs_true_after,"
         "orient_pairs_weak,orient_pairs_weak_before,orient_pairs_weak_after,"
         // round-28: the SECOND (geometric) orientation authority + the UV determinant census.
         // Appended, again, so every previously written csv stays readable.
         "orient_comps_no_authority,orient_faces_no_authority,orient_comps_volume_decided,"
         "orient_comps_raycast_decided,orient_comps_undecided,"
         "uv_tris_total,uv_tris_mirrored,uv_tris_degenerate,uv_verts_handedness_split,"
         // round-29: components where a collision normal existed but was not COMPETENT to judge,
         // plus the authority-free scoring of both collision rules against the signed volume.
         "orient_comps_collision_incompetent,orient_comps_volume_confident,"
         "orient_comps_collraw_vs_volume_conflict,orient_comps_collfiltered_vs_volume_conflict,"
         // round-31: the per-face geometric outward vote (kMeshBitGeomOrient) and the two conflicts
         // it exposes. Appended, again, so every previously written csv stays readable.
         "orient_faces_geom_voted,orient_faces_geom_abstained,orient_comps_geom_decided,"
         "orient_comps_geom_vs_collision_conflict,orient_comps_geom_vs_volume_conflict,"
         "orient_geom_pass_ms\n";
}

std::string mesh_audit_csv_row(const MeshAuditReport& r) {
  return fmt::format(
      "{},{},{},{},{},{},{},{},{},{},{},{},{},{},{:.3f},{:.3f},{:.3f},{:.3f},"
      "{:.3f},{:.3f},{:.3f},{:.3f},{:.1f},{:.1f},{:.2f},"
      "{:.2f},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},"
      "{},{},{},{},{},{},{},{},{},{},{},{},{},"
      "{},{},{},{},{},{:.1f}\n",
      r.game_name, r.level_name, r.tfrag.tris, r.tie.tris, r.shrub.tris, r.total.tris,
      r.total.open_raw, r.total.coincident_unshared, r.total.coincident_unshared_pairs,
      r.total.open_by_group, r.total.missed_welds, r.groups, r.wide_reweld_rounds,
      r.wide_reweld_unions, r.nrm_smooth_before.max, r.nrm_smooth_after.max,
      r.nrm_smooth_before.mean(), r.nrm_smooth_after.mean(),
      r.nrm_before.max, r.nrm_after.max, r.nrm_before.mean(),
      r.nrm_after.mean(), r.col_before.max, r.col_after.max, r.col_before.mean(),
      r.col_after.mean(), r.col_groups_blended, r.pos_snapped, r.orient_faces_flipped,
      r.orient_faces_inward_after, r.seam_verts, r.orient_pairs_total,
      r.orient_pairs_inconsistent_before, r.orient_pairs_inconsistent_after,
      r.orient_tangent_w_flipped, r.orient_pairs_true_manifold,
      r.orient_pairs_true_inconsistent_before, r.orient_pairs_true_inconsistent_after,
      r.orient_pairs_weak, r.orient_pairs_weak_inconsistent_before,
      r.orient_pairs_weak_inconsistent_after, r.orient_comps_no_authority,
      r.orient_faces_no_authority, r.orient_comps_volume_decided, r.orient_comps_raycast_decided,
      r.orient_comps_undecided, r.uv_tris_total, r.uv_tris_mirrored, r.uv_tris_degenerate,
      r.uv_verts_handedness_split, r.orient_comps_collision_incompetent,
      r.orient_comps_volume_confident, r.orient_comps_collraw_vs_volume_conflict,
      r.orient_comps_collfiltered_vs_volume_conflict, r.orient_faces_geom_voted,
      r.orient_faces_geom_abstained, r.orient_comps_geom_decided,
      r.orient_comps_geom_vs_collision_conflict, r.orient_comps_geom_vs_volume_conflict,
      r.orient_geom_pass_ms);
}

}  // namespace tfrag3
