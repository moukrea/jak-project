#include "MeshOrient.h"

// THE SHARED OUTWARD AUTHORITY. See MeshOrient.h for the cascade and the determinism contract.
//
// PROVENANCE. Every block below was MOVED — not re-derived — out of tools/tess_sign/main.cpp, which
// is where the cascade was written and validated. The pipeline (MeshConsolidate.cpp pass 11) and the
// grader (tess_sign) now both call this one function, so the two can no longer drift apart. The
// numbers, the thresholds, the tie-breaks and the iteration orders are the ones that were there.

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstring>
#include <limits>
#include <map>
#include <thread>
#include <unordered_map>

namespace tfrag3 {

const char* mesh_orient_tier_name(u8 tier) {
  switch (tier) {
    case kOrientVolx:
      return "VOLX";
    case kOrientRayf:
      return "RAYF";
    case kOrientColl:
      return "COLL";
    case kOrientEsc:
      return "ESC";
    case kOrientVolxOpen:
      return "VOLOPEN";
    default:
      return "UNDECIDED";
  }
}

const char* mesh_orient_shell_tier_name(u8 tier) {
  switch (tier) {
    case kOrientShellVol:
      return "VOL";
    case kOrientShellEsc:
      return "ESC";
    case kOrientShellRayf:
      return "RAYF";
    case kOrientShellVolOpen:
      return "VOLOPEN";
    default:
      return "UNDECIDED";
  }
}

// =================================================================================================
// THE PACKED-NORMAL FEASIBILITY SEARCH (round 33). See MeshOrient.h for why it lives here.
// =================================================================================================
u32 mesh_pack_nor(const math::Vector3f& n) {
  auto sat = [](float f) -> u32 {
    int v = (int)std::lround(f * 511.f);
    v = std::max(-511, std::min(511, v));
    return (u32)v & 0x3ffu;
  };
  return sat(n.x()) | (sat(n.y()) << 10) | (sat(n.z()) << 20);
}

math::Vector3f mesh_unpack_nor(u32 p) {
  auto sx = [](u32 v) -> int {
    int x = (int)(v & 0x3ffu);
    return (x & 0x200) ? x - 0x400 : x;
  };
  math::Vector3f n((float)sx(p), (float)sx(p >> 10), (float)sx(p >> 20));
  float l = n.length();
  return l > 1e-6f ? n * (1.f / l) : math::Vector3f(0.f, 0.f, 0.f);
}

bool mesh_best_packed_normal(const std::vector<math::Vector3f>& in_outs, float eps, u32* out_packed) {
  if (in_outs.empty()) {
    return false;
  }
  // ---- 0. CANONICALISE THE INPUT ORDER. The two callers reach the same vertex through different
  //         iteration structures (the pipeline walks a vertex->face CSR, the grader walks a
  //         group->corner CSR), so they hand the same geometric constraint set in different orders.
  //         The Chebyshev iteration below is order-sensitive in float, so an un-canonicalised input
  //         could give the two callers different answers on a razor-edge cone — and the guarantee
  //         this function exists to provide is precisely that they cannot differ. Sorting by the
  //         packed bit pattern (and dropping exact duplicates, which are common: a flat fan hands
  //         the same direction many times) makes the whole function a pure function of the SET.
  std::vector<math::Vector3f> outs;
  {
    //         The representative kept for a key is the UNPACKED one, not whichever float vector
    //         happened to hash to it first: that makes `outs` a pure function of the key SET rather
    //         than of the caller's iteration order. The quantisation error it introduces is ~2e-6 in
    //         dot (10 bits over a unit vector), three orders of magnitude under the 1e-3 margin.
    std::vector<u32> keys;
    keys.reserve(in_outs.size());
    for (const auto& u : in_outs) {
      const u32 k = mesh_pack_nor(u);
      if (k != 0) {
        keys.push_back(k);
      }
    }
    std::sort(keys.begin(), keys.end());
    keys.erase(std::unique(keys.begin(), keys.end()), keys.end());
    outs.reserve(keys.size());
    for (u32 k : keys) {
      const math::Vector3f n = mesh_unpack_nor(k);
      if (n.length() > 1e-6f) {
        outs.push_back(n);
      }
    }
  }
  if (outs.empty()) {
    return false;
  }
  // worst-case dot of a candidate against every incident outward direction.
  auto worst_of = [&](const math::Vector3f& n) {
    float w = 2.f;
    for (const auto& u : outs) {
      w = std::min(w, n.dot(u));
    }
    return w;
  };
  // ---- 1. the CHEBYSHEV CENTRE of the incident outwards, by Badoiu-Clarkson: start at the mean,
  //         then step a shrinking fraction of the way towards the current WORST constraint. This is
  //         the direction furthest from the boundary of the cone they span, so if ANY unit vector
  //         satisfies the constraints with margin, this one does.
  math::Vector3f acc(0.f, 0.f, 0.f);
  for (const auto& u : outs) {
    acc += u;
  }
  const float al = acc.length();
  if (!(al > 1e-6f)) {
    return false;  // the outwards cancel exactly: no centre exists, in float OR in 10 bits
  }
  math::Vector3f nb = acc * (1.f / al);
  for (int it = 0; it < 256; it++) {
    float w = 2.f;
    int worst_j = -1;
    for (size_t j = 0; j < outs.size(); j++) {
      const float d = nb.dot(outs[j]);
      if (d < w) {
        w = d;
        worst_j = (int)j;
      }
    }
    if (w > eps || worst_j < 0) {
      break;
    }
    const math::Vector3f step = nb + (outs[worst_j] - nb) * (1.f / (float)(it + 2));
    const float sl = step.length();
    if (!(sl > 1e-6f)) {
      break;
    }
    nb = step * (1.f / sl);
  }
  // ---- 2. the answer has to be REPRESENTABLE. The float centre is not the deliverable: three
  //         signed 10-bit fields are. Quantise, and if the quantised value has fallen out of the
  //         cone (which happens when the cone is only a few quantisation steps wide), search the
  //         5x5x5 lattice neighbourhood around it. The neighbourhood is walked in a FIXED order and
  //         strictly-greater is required to replace the incumbent, so the answer is deterministic.
  auto sat10 = [](int v) -> int { return std::max(-511, std::min(511, v)); };
  auto enc = [&](int x, int y, int z) -> u32 {
    return ((u32)sat10(x) & 0x3ffu) | (((u32)sat10(y) & 0x3ffu) << 10) |
           (((u32)sat10(z) & 0x3ffu) << 20);
  };
  const int cx = sat10((int)std::lround(nb.x() * 511.f));
  const int cy = sat10((int)std::lround(nb.y() * 511.f));
  const int cz = sat10((int)std::lround(nb.z() * 511.f));
  u32 best_packed = 0;
  float best_w = -2.f;
  auto consider = [&](u32 p) {
    const math::Vector3f n = mesh_unpack_nor(p);
    if (n.length() <= 1e-6f) {
      return;
    }
    const float w = worst_of(n);
    if (w > best_w) {
      best_w = w;
      best_packed = p;
    }
  };
  for (int dz = -2; dz <= 2; dz++) {
    for (int dy = -2; dy <= 2; dy++) {
      for (int dx = -2; dx <= 2; dx++) {
        consider(enc(cx + dx, cy + dy, cz + dz));
      }
    }
  }
  // ---- 3. last resort: the incident outwards THEMSELVES, quantised. On a vertex whose cone is one
  //         quantisation step wide the centre may be unrepresentable while one of the constraint
  //         directions is not, and a normal equal to one incident outward still has a positive dot
  //         with it (1.0) and, if the cone is that narrow, with all the others too.
  if (!(best_w > eps)) {
    for (const auto& u : outs) {
      consider(mesh_pack_nor(u));
    }
  }
  if (best_w > eps) {
    if (out_packed) {
      *out_packed = best_packed;
    }
    return true;
  }
  return false;
}

size_t MeshPosKeyHash::operator()(const MeshPosKey& k) const {
  u64 h = 1469598103934665603ull;
  for (u32 w : {k.x, k.y, k.z}) {
    for (int b = 0; b < 4; b++) {
      h ^= (u64)((w >> (8 * b)) & 0xffu);
      h *= 1099511628211ull;
    }
  }
  return (size_t)h;
}

MeshPosKey mesh_pos_key(float x, float y, float z) {
  auto bits = [](float f) -> u32 {
    if (f == 0.f) {
      f = 0.f;  // collapse -0.0f onto +0.0f
    }
    u32 u;
    std::memcpy(&u, &f, 4);
    return u;
  };
  return MeshPosKey{bits(x), bits(y), bits(z)};
}

namespace {

// ===============================================================================================
// SMALL MATH (double throughout: world coordinates run to ~1e6 game units and the signed volume is
// a triple product of them, so float cancels the answer away)
// ===============================================================================================
struct V3 {
  double x = 0, y = 0, z = 0;
};
inline V3 operator+(const V3& a, const V3& b) {
  return V3{a.x + b.x, a.y + b.y, a.z + b.z};
}
inline V3 operator-(const V3& a, const V3& b) {
  return V3{a.x - b.x, a.y - b.y, a.z - b.z};
}
inline V3 operator*(const V3& a, double s) {
  return V3{a.x * s, a.y * s, a.z * s};
}
inline double dot(const V3& a, const V3& b) {
  return a.x * b.x + a.y * b.y + a.z * b.z;
}
inline V3 cross(const V3& a, const V3& b) {
  return V3{a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}
inline double len(const V3& a) {
  return std::sqrt(dot(a, a));
}
inline V3 normalized(const V3& a) {
  const double l = len(a);
  return l > 0 ? a * (1.0 / l) : V3{0, 0, 0};
}

// Duff/Frisvad BRANCHLESS orthonormal basis (Duff et al., JCGT 6(1), 2017). (b1, b2, n) is
// orthonormal and every component is a pure arithmetic function of n — copysign is not a branch — so
// the RAYF direction set built from it is a pure function of the face's own geometric normal. No
// RNG, no clock, no address- or order-dependence anywhere.
inline void branchless_onb(const V3& n, V3* b1, V3* b2) {
  const double sg = std::copysign(1.0, n.z);
  const double a = -1.0 / (sg + n.z);
  const double b = n.x * n.y * a;
  *b1 = V3{1.0 + sg * n.x * n.x * a, sg * b, -sg * n.x};
  *b2 = V3{b, sg + n.y * n.y * a, -n.y};
}

// ---- union-find over faces (shells) ------------------------------------------------------------
struct DSU {
  std::vector<u32> p;
  void init(size_t n) {
    p.resize(n);
    for (size_t i = 0; i < n; i++) {
      p[i] = (u32)i;
    }
  }
  u32 find(u32 a) {
    while (p[a] != a) {
      p[a] = p[p[a]];
      a = p[a];
    }
    return a;
  }
  void unite(u32 a, u32 b) {
    a = find(a);
    b = find(b);
    if (a == b) {
      return;
    }
    // always attach to the LOWER root: deterministic representative.
    if (a < b) {
      p[b] = a;
    } else {
      p[a] = b;
    }
  }
};

// ---- a BVH over the whole face list, for the ray tiers -----------------------------------------
struct Bvh {
  struct Node {
    double lo[3] = {0, 0, 0};
    double hi[3] = {0, 0, 0};
    u32 left = 0;  // LEFT child index (interior) or 0
    // ROUND 31 CORRECTNESS FIX. This used to be absent and both traversals pushed `left` and
    // `left + 1`. That identity only holds when the LEFT child is a LEAF (build_rec emits the left
    // subtree in full before it starts the right one, so with an interior left child `left + 1` is
    // the left child's OWN left child and the entire right subtree is never visited). The effect was
    // not subtle: with most of the level unreachable from the root, almost every occlusion query
    // answered "nothing there", so TIER RAYF measured K escapes on BOTH sides of every face,
    // diff == 0 < kOrientRayfMinMargin, and the PRIMARY outward authority voted on 0 faces. Storing
    // the right child explicitly is the whole fix.
    u32 right = 0;  // RIGHT child index (interior) or 0
    u32 first = 0;  // first entry in `order` (leaf)
    u32 count = 0;  // 0 = interior
  };
  std::vector<Node> nodes;
  std::vector<u32> order;

  void build(const std::vector<std::array<u32, 3>>& faces, const std::vector<V3>& verts) {
    const size_t n = faces.size();
    order.resize(n);
    std::vector<double> cen(n * 3);
    std::vector<double> flo(n * 3), fhi(n * 3);
    for (size_t f = 0; f < n; f++) {
      order[f] = (u32)f;
      double lo[3] = {1e300, 1e300, 1e300}, hi[3] = {-1e300, -1e300, -1e300};
      for (int e = 0; e < 3; e++) {
        const auto& p = verts[faces[f][e]];
        const double q[3] = {p.x, p.y, p.z};
        for (int k = 0; k < 3; k++) {
          lo[k] = std::min(lo[k], q[k]);
          hi[k] = std::max(hi[k], q[k]);
        }
      }
      for (int k = 0; k < 3; k++) {
        flo[f * 3 + k] = lo[k];
        fhi[f * 3 + k] = hi[k];
        cen[f * 3 + k] = 0.5 * (lo[k] + hi[k]);
      }
    }
    nodes.clear();
    nodes.reserve(std::max<size_t>(1, 2 * n / 4 + 2));
    if (n == 0) {
      nodes.emplace_back();
      return;
    }
    build_rec(0, (u32)n, flo, fhi, cen);
  }

  // Visit every face whose AABB the ray may cross. `visit(face)` is called once per candidate.
  template <typename F>
  void traverse(const double o[3], const double d[3], double tmax, F&& visit) const {
    if (nodes.empty()) {
      return;
    }
    double inv[3];
    for (int k = 0; k < 3; k++) {
      inv[k] = (d[k] != 0.0) ? 1.0 / d[k] : 1e300;
    }
    u32 stack[128];
    int sp = 0;
    stack[sp++] = 0;
    while (sp > 0) {
      const Node& nd = nodes[stack[--sp]];
      if (!slab(nd, o, inv, tmax)) {
        continue;
      }
      if (nd.count) {
        for (u32 i = 0; i < nd.count; i++) {
          visit(order[nd.first + i]);
        }
      } else {
        if (sp + 2 <= 128) {
          stack[sp++] = nd.left;
          stack[sp++] = nd.right;
        }
      }
    }
  }

  // OCCLUSION query: stops at the FIRST face for which test(face) is true. `test` must be a pure
  // function of (ray, face) so the answer cannot depend on the visit order.
  template <typename F>
  bool any_hit(const double o[3], const double d[3], double tmax, F&& test) const {
    if (nodes.empty()) {
      return false;
    }
    double inv[3];
    for (int k = 0; k < 3; k++) {
      inv[k] = (d[k] != 0.0) ? 1.0 / d[k] : 1e300;
    }
    u32 stack[128];
    int sp = 0;
    stack[sp++] = 0;
    while (sp > 0) {
      const Node& nd = nodes[stack[--sp]];
      if (!slab(nd, o, inv, tmax)) {
        continue;
      }
      if (nd.count) {
        for (u32 i = 0; i < nd.count; i++) {
          if (test(order[nd.first + i])) {
            return true;
          }
        }
      } else {
        if (sp + 2 <= 128) {
          stack[sp++] = nd.left;
          stack[sp++] = nd.right;
        }
      }
    }
    return false;
  }

 private:
  static bool slab(const Node& nd, const double o[3], const double inv[3], double tmax) {
    double t0 = 0.0, t1 = tmax;
    for (int k = 0; k < 3; k++) {
      double a = (nd.lo[k] - o[k]) * inv[k];
      double b = (nd.hi[k] - o[k]) * inv[k];
      if (a > b) {
        std::swap(a, b);
      }
      t0 = std::max(t0, a);
      t1 = std::min(t1, b);
      if (t0 > t1) {
        return false;
      }
    }
    return true;
  }
  u32 build_rec(u32 first,
                u32 count,
                const std::vector<double>& flo,
                const std::vector<double>& fhi,
                const std::vector<double>& cen) {
    const u32 me = (u32)nodes.size();
    nodes.emplace_back();
    Node nd;
    for (int k = 0; k < 3; k++) {
      nd.lo[k] = 1e300;
      nd.hi[k] = -1e300;
    }
    for (u32 i = 0; i < count; i++) {
      const u32 f = order[first + i];
      for (int k = 0; k < 3; k++) {
        nd.lo[k] = std::min(nd.lo[k], flo[(size_t)f * 3 + k]);
        nd.hi[k] = std::max(nd.hi[k], fhi[(size_t)f * 3 + k]);
      }
    }
    if (count <= 8) {
      nd.first = first;
      nd.count = count;
      nodes[me] = nd;
      return me;
    }
    int axis = 0;
    double best = -1;
    for (int k = 0; k < 3; k++) {
      const double ext = nd.hi[k] - nd.lo[k];
      if (ext > best) {
        best = ext;
        axis = k;
      }
    }
    const u32 mid = count / 2;
    std::nth_element(order.begin() + first, order.begin() + first + mid,
                     order.begin() + first + count, [&](u32 a, u32 b) {
                       const double ca = cen[(size_t)a * 3 + axis];
                       const double cb = cen[(size_t)b * 3 + axis];
                       return ca < cb || (ca == cb && a < b);  // total order => deterministic
                     });
    nd.count = 0;
    nodes[me] = nd;
    const u32 l = build_rec(first, mid, flo, fhi, cen);
    const u32 r = build_rec(first + mid, count - mid, flo, fhi, cen);
    nodes[me].left = l;
    nodes[me].right = r;
    return me;
  }
};

// Moller-Trumbore in double:
//   +1 clean forward hit (t written), 0 clean miss, -1 AMBIGUOUS (throw the whole ray away).
int ray_tri(const double o[3],
            const double d[3],
            const V3& v0,
            const V3& v1,
            const V3& v2,
            double* out_t) {
  const double e1[3] = {v1.x - v0.x, v1.y - v0.y, v1.z - v0.z};
  const double e2[3] = {v2.x - v0.x, v2.y - v0.y, v2.z - v0.z};
  const double pv[3] = {d[1] * e2[2] - d[2] * e2[1], d[2] * e2[0] - d[0] * e2[2],
                        d[0] * e2[1] - d[1] * e2[0]};
  const double det = e1[0] * pv[0] + e1[1] * pv[1] + e1[2] * pv[2];
  if (!(std::abs(det) > 1e-12)) {
    return 0;  // ray parallel to the plane: it skims, it does not cross
  }
  const double inv = 1.0 / det;
  const double tv[3] = {o[0] - v0.x, o[1] - v0.y, o[2] - v0.z};
  const double bu = (tv[0] * pv[0] + tv[1] * pv[1] + tv[2] * pv[2]) * inv;
  const double qv[3] = {tv[1] * e1[2] - tv[2] * e1[1], tv[2] * e1[0] - tv[0] * e1[2],
                        tv[0] * e1[1] - tv[1] * e1[0]};
  const double bv = (d[0] * qv[0] + d[1] * qv[1] + d[2] * qv[2]) * inv;
  const double bw = 1.0 - bu - bv;
  if (bu < -kOrientRayEdgeEps || bv < -kOrientRayEdgeEps || bw < -kOrientRayEdgeEps) {
    return 0;
  }
  if (bu < kOrientRayEdgeEps || bv < kOrientRayEdgeEps || bw < kOrientRayEdgeEps) {
    return -1;  // within 1e-6 of an edge/vertex: the crossing count is not trustworthy
  }
  const double tt = (e2[0] * qv[0] + e2[1] * qv[1] + e2[2] * qv[2]) * inv;
  if (tt < -kOrientRayEdgeEps) {
    return 0;  // strictly behind the ray origin
  }
  if (tt < kOrientRayEdgeEps) {
    return -1;  // the probe point sits ON this triangle
  }
  if (out_t) {
    *out_t = tt;
  }
  return 1;
}

// TIER RAYF's OCCLUSION test: does this triangle block the ray somewhere in (tmin, tmax]? Unlike
// ray_tri() above it does NOT need a trustworthy crossing COUNT (RAYF counts nothing, it only asks
// "is there anything there"), so an edge-grazing hit is ACCEPTED as a hit instead of poisoning the
// ray. That bias is one-directional and therefore safe: it can only ever turn an escape into a
// non-escape, never invent an escape, and it applies identically to both sides of the face.
inline bool ray_tri_occl(const double o[3],
                         const double d[3],
                         const V3& v0,
                         const V3& v1,
                         const V3& v2,
                         double tmin,
                         double tmax) {
  const double e1[3] = {v1.x - v0.x, v1.y - v0.y, v1.z - v0.z};
  const double e2[3] = {v2.x - v0.x, v2.y - v0.y, v2.z - v0.z};
  const double pv[3] = {d[1] * e2[2] - d[2] * e2[1], d[2] * e2[0] - d[0] * e2[2],
                        d[0] * e2[1] - d[1] * e2[0]};
  const double det = e1[0] * pv[0] + e1[1] * pv[1] + e1[2] * pv[2];
  if (!(std::abs(det) > 1e-12)) {
    return false;  // parallel to the plane: it skims, it does not block
  }
  const double inv = 1.0 / det;
  const double tv[3] = {o[0] - v0.x, o[1] - v0.y, o[2] - v0.z};
  const double bu = (tv[0] * pv[0] + tv[1] * pv[1] + tv[2] * pv[2]) * inv;
  const double qv[3] = {tv[1] * e1[2] - tv[2] * e1[1], tv[2] * e1[0] - tv[0] * e1[2],
                        tv[0] * e1[1] - tv[1] * e1[0]};
  const double bv = (d[0] * qv[0] + d[1] * qv[1] + d[2] * qv[2]) * inv;
  const double bw = 1.0 - bu - bv;
  if (bu < -kOrientRayfOcclEps || bv < -kOrientRayfOcclEps || bw < -kOrientRayfOcclEps) {
    return false;
  }
  const double tt = (e2[0] * qv[0] + e2[1] * qv[1] + e2[2] * qv[2]) * inv;
  return tt > tmin && tt <= tmax;
}

// ---- the COLLISION authority: a 1 m spatial hash over a (position, normal) point cloud ---------
// The walkable side of the world is the side the collision normal points to, so a rendered face
// whose normal opposes it is inward-facing. It only ever answers where a collision sample is within
// 1.5 m; everywhere else it has no authority and says so.
struct CollisionAuthority {
  std::unordered_map<u64, std::vector<u32>> cells;
  const std::vector<math::Vector3f>* pos = nullptr;
  const std::vector<math::Vector3f>* nor = nullptr;
  double cell = 4096.0;
  double accept2 = (1.5 * 4096.0) * (1.5 * 4096.0);

  static u64 key(s64 x, s64 y, s64 z) {
    // any injective-enough mixing; only used as a hash bucket, the distance test is exact.
    u64 h = 1469598103934665603ull;
    for (s64 v : {x, y, z}) {
      h ^= (u64)v;
      h *= 1099511628211ull;
    }
    return h;
  }
  void build(const std::vector<math::Vector3f>& p,
             const std::vector<math::Vector3f>& n,
             double units_per_m) {
    pos = &p;
    nor = &n;
    cell = 1.0 * units_per_m;
    accept2 = (1.5 * units_per_m) * (1.5 * units_per_m);
    cells.reserve(p.size() / 4 + 1);
    for (u32 i = 0; i < p.size(); i++) {
      cells[key((s64)std::floor(p[i].x() / cell), (s64)std::floor(p[i].y() / cell),
                (s64)std::floor(p[i].z() / cell))]
          .push_back(i);
    }
  }
  // false = no collision sample within 1.5 m (no authority here)
  bool nearest_normal(const V3& p, V3* out) const {
    if (!pos || pos->empty()) {
      return false;
    }
    const s64 cx = (s64)std::floor(p.x / cell);
    const s64 cy = (s64)std::floor(p.y / cell);
    const s64 cz = (s64)std::floor(p.z / cell);
    double best = accept2;
    int best_i = -1;
    for (int dz = -1; dz <= 1; dz++) {
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          auto it = cells.find(key(cx + dx, cy + dy, cz + dz));
          if (it == cells.end()) {
            continue;
          }
          for (u32 ci : it->second) {
            const auto& cv = (*pos)[ci];
            const V3 dd{cv.x() - p.x, cv.y() - p.y, cv.z() - p.z};
            const double d2 = dot(dd, dd);
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
    const auto& cn = (*nor)[best_i];
    V3 n{(double)cn.x(), (double)cn.y(), (double)cn.z()};
    const double l = len(n);
    if (!(l > 1e-6)) {
      return false;
    }
    *out = n * (1.0 / l);
    return true;
  }
};

}  // namespace

MeshOrientResult mesh_orient_faces(const MeshOrientInput& in) {
  const auto t_all = std::chrono::steady_clock::now();
  MeshOrientResult r;
  if (!in.positions || !in.faces || in.faces->empty()) {
    return r;
  }
  const std::vector<std::array<u32, 3>>& faces = *in.faces;
  const size_t F = faces.size();
  const double units_per_m = (double)in.units_per_m;
  const int rayf_k = std::max(1, std::min(256, in.rays_per_hemi));

  // Positions in double, once. Every geometric test below reads this and nothing else, so the
  // caller's storage layout cannot leak into a verdict.
  std::vector<V3> gv;
  gv.reserve(in.positions->size());
  for (const auto& p : *in.positions) {
    gv.push_back(V3{(double)p.x(), (double)p.y(), (double)p.z()});
  }

  // The CANDIDATE population: the faces the caller needs a verdict for. RAYF runs over exactly this
  // set and the per-shell tiers only speak for a shell that owns one.
  std::vector<u8> is_cand(F, 1);
  if (in.face_is_candidate) {
    for (size_t f = 0; f < F && f < in.face_is_candidate->size(); f++) {
      is_cand[f] = (*in.face_is_candidate)[f];
    }
    if (in.face_is_candidate->size() < F) {
      for (size_t f = in.face_is_candidate->size(); f < F; f++) {
        is_cand[f] = 0;
      }
    }
  }

  // ---------------------------------------------------------------------------------------------
  // WELD GROUPS (exact float triple) + the edge table + SHELLS.
  // ---------------------------------------------------------------------------------------------
  std::vector<u32>& vert_group = r.vert_group;
  vert_group.assign(gv.size(), UINT32_MAX);
  u32 n_groups = 0;
  {
    std::unordered_map<MeshPosKey, u32, MeshPosKeyHash> pos_to_group;
    pos_to_group.reserve(gv.size() * 2);
    for (const auto& f : faces) {
      for (int e = 0; e < 3; e++) {
        const u32 vi = f[e];
        if (vert_group[vi] != UINT32_MAX) {
          continue;
        }
        const auto& p = (*in.positions)[vi];
        const auto k = mesh_pos_key(p.x(), p.y(), p.z());
        auto it = pos_to_group.find(k);
        if (it == pos_to_group.end()) {
          pos_to_group.emplace(k, n_groups);
          vert_group[vi] = n_groups++;
        } else {
          vert_group[vi] = it->second;
        }
      }
    }
  }
  r.weld_groups = n_groups;
  std::vector<std::array<u32, 3>> fwg(F);
  for (size_t f = 0; f < F; f++) {
    for (int e = 0; e < 3; e++) {
      fwg[f][e] = vert_group[faces[f][e]];
    }
  }

  // Edge table: undirected weld-group pair -> the faces on it, with the traversal direction.
  struct EdgeRef {
    u32 face;
    s8 dir;  // +1 = the face traverses lo->hi, -1 = hi->lo
  };
  std::unordered_map<u64, std::vector<EdgeRef>> edges;
  edges.reserve(F * 2);
  auto edge_key = [](u32 a, u32 b) -> u64 {
    return a < b ? ((u64)a << 32) | (u64)b : ((u64)b << 32) | (u64)a;
  };
  for (u32 f = 0; f < F; f++) {
    for (int e = 0; e < 3; e++) {
      const u32 a = fwg[f][e];
      const u32 b = fwg[f][(e + 1) % 3];
      if (a == b) {
        continue;  // a weld-collapsed edge is not an edge
      }
      edges[edge_key(a, b)].push_back(EdgeRef{f, (s8)(a < b ? 1 : -1)});
    }
  }
  r.edge_count = edges.size();

  // A weld group touched by an edge used by exactly ONE face sits on an OPEN boundary. Published
  // because the caller's seam attribution needs the same edge table and must not build a second one.
  r.group_has_open_edge.assign(n_groups, 0);
  for (const auto& kv : edges) {
    if (kv.second.size() != 1) {
      continue;
    }
    const u32 ga = (u32)(kv.first >> 32), gb = (u32)(kv.first & 0xffffffffu);
    if (ga < n_groups) {
      r.group_has_open_edge[ga] = 1;
    }
    if (gb < n_groups) {
      r.group_has_open_edge[gb] = 1;
    }
  }

  // SHELL = connected component of faces where adjacency is "shares at least TWO weld groups",
  // i.e. shares an EDGE. (Union-find; the chain within one edge's face list is enough to connect
  // them all, and it keeps the pass linear on the rare 3+-incident edges.)
  DSU dsu;
  dsu.init(F);
  for (const auto& kv : edges) {
    for (size_t i = 1; i < kv.second.size(); i++) {
      dsu.unite(kv.second[0].face, kv.second[i].face);
    }
  }
  std::vector<u32>& shell_of = r.shell_of;
  shell_of.assign(F, 0);
  std::map<u32, u32> root_to_shell;  // ordered => shell ids are deterministic
  for (u32 f = 0; f < F; f++) {
    root_to_shell.emplace(dsu.find(f), 0);
  }
  {
    u32 next = 0;
    for (auto& kv : root_to_shell) {
      kv.second = next++;
    }
  }
  for (u32 f = 0; f < F; f++) {
    shell_of[f] = root_to_shell[dsu.find(f)];
  }
  const u32 n_shells = (u32)root_to_shell.size();
  r.shell_count = n_shells;

  // per-shell face lists, ascending face index (determinism)
  std::vector<std::vector<u32>> shell_faces(n_shells);
  r.shell_has_candidate.assign(n_shells, 0);
  for (u32 f = 0; f < F; f++) {
    shell_faces[shell_of[f]].push_back(f);
    if (is_cand[f]) {
      r.shell_has_candidate[shell_of[f]] = 1;
      r.candidate_faces++;
    }
  }
  r.shell_face_count.assign(n_shells, 0);
  for (u32 s = 0; s < n_shells; s++) {
    r.shell_face_count[s] = (u32)shell_faces[s].size();
  }
  r.shell_closed.assign(n_shells, 0);
  r.shell_open_edges.assign(n_shells, 0);
  r.shell_nonmanifold_edges.assign(n_shells, 0);
  r.shell_vol_sign.assign(n_shells, 0);
  r.shell_v6_over_l3.assign(n_shells, 0.0);
  r.shell_vecarea.assign(n_shells, 0.0);
  r.shell_vol_robust.assign(n_shells, 0.0);
  r.shell_winding_conflicts.assign(n_shells, 0);
  r.shell_coll_sign.assign(n_shells, 0);
  r.shell_coll_speaks.assign(n_shells, 0);
  r.shell_esc_ratio.assign(n_shells, 0.0);
  r.shell_gsign.assign(n_shells, 0);
  r.shell_tier.assign(n_shells, (u8)kOrientShellUndecided);
  r.shell_rayf_voted.assign(n_shells, 0);
  r.shell_rayf_agree.assign(n_shells, 0);
  r.shell_rayf_disagree.assign(n_shells, 0);

  // ---------------------------------------------------------------------------------------------
  // GEOMETRY HELPERS. cross(p1-p0, p2-p0): length == 2*area, direction == the STORED winding's
  // geometric normal.
  // ---------------------------------------------------------------------------------------------
  auto pos = [&](u32 vi) { return gv[vi]; };
  auto face_cross = [&](u32 f) {
    const V3 p0 = pos(faces[f][0]), p1 = pos(faces[f][1]), p2 = pos(faces[f][2]);
    return cross(p1 - p0, p2 - p0);
  };
  auto face_centroid = [&](u32 f) {
    const V3 p0 = pos(faces[f][0]), p1 = pos(faces[f][1]), p2 = pos(faces[f][2]);
    return (p0 + p1 + p2) * (1.0 / 3.0);
  };

  // (a) RELATIVE WINDING by BFS over the shell's edge adjacency. Computed for EVERY shell, not just
  // the ones owning a candidate: a caller's crease/seam attribution has to cluster the faces
  // incident to a weld group, and those faces can belong to a shell owning no candidate at all.
  // This cannot change any verdict — the tiers below still only read rel[] on candidate shells.
  //
  // ROUND 34 — TWO PHASES, BECAUSE THE WINDING RULE IS NOT DEFINED EVERYWHERE.
  //
  // "Consistently wound neighbours traverse the shared edge in OPPOSITE directions" is a theorem
  // about a TRUE MANIFOLD edge — one shared by exactly two faces. On an edge shared by three or more
  // (stacked coplanar sheets, a decimated LOD copy chained onto the full-res mesh) it states a
  // relation that does not exist, and a single BFS propagates that fabrication into the rest of the
  // shell, which is what the shell_winding_conflicts counter is measuring. MeshConsolidate.cpp's
  // ManifoldLink (see build_group_edges there) already draws this distinction; the flood fill here
  // did not, so it is drawn now:
  //
  //   PHASE 1 (TRUSTED) propagates ONLY across edges whose face list has exactly two entries. Every
  //           relation it asserts is a theorem.
  //   PHASE 2 (GUESS)   reaches whatever phase 1 could not, across ANY edge — exactly the old
  //           behaviour — seeded preferentially from faces phase 1 already decided, so a guessed
  //           region is hung off the trusted frame rather than off an arbitrary new one.
  //
  // COVERAGE IS PRESERVED EXACTLY. Phase 2's relaxation is the old relaxation and its seeding falls
  // back to "lowest unassigned face index, rel = 1" (the old per-shell seed convention), so every
  // face that used to end up with rel != 0 still does. This is not an abstention mechanism: it
  // changes WHICH sign a face gets, never WHETHER it gets one.
  //
  // DETERMINISM. Both phases walk shell_faces[s], which is in ascending face index; the per-face
  // relaxation walks the face's own three edges in a fixed order and then that edge's face list in
  // insertion order (which is itself ascending in face index). Nothing reads the unordered_map's
  // traversal order.
  std::vector<s8>& rel = r.rel;
  rel.assign(F, 0);
  {
    std::vector<u32> queue;
    // one BFS relaxation step, factored so the two phases cannot drift apart. `trusted_only` is the
    // ONLY difference between them. Returns how many faces it newly assigned.
    auto flood = [&](bool trusted_only) -> u64 {
      u64 assigned = 0;
      for (size_t qi = 0; qi < queue.size(); qi++) {
        const u32 f = queue[qi];
        for (int e = 0; e < 3; e++) {
          const u32 a = fwg[f][e], b = fwg[f][(e + 1) % 3];
          if (a == b) {
            continue;
          }
          auto it = edges.find(edge_key(a, b));
          if (it == edges.end()) {
            continue;
          }
          if (trusted_only && it->second.size() != 2) {
            continue;  // the winding rule has nothing to say about this edge
          }
          s8 my_dir = (s8)(a < b ? 1 : -1);
          for (const auto& er : it->second) {
            if (er.face == f || rel[er.face] != 0) {
              continue;
            }
            // consistently wound <=> they traverse the shared pair in OPPOSITE order
            const bool consistent = (er.dir != my_dir);
            rel[er.face] = (s8)(rel[f] * (consistent ? 1 : -1));
            queue.push_back(er.face);
            assigned++;
          }
        }
      }
      return assigned;
    };
    for (u32 s = 0; s < n_shells; s++) {
      // ---- PHASE 1: the trusted frame, from the shell's usual seed. ----
      queue.clear();
      const u32 seed = shell_faces[s].front();
      rel[seed] = 1;
      queue.push_back(seed);
      r.faces_rel_trusted++;  // the seed IS the shell's frame of reference
      r.faces_rel_trusted += flood(true);

      // ---- PHASE 2: reach the remnant, across any edge. ----
      // Seed from the faces phase 1 decided that touch an unassigned face, in ascending face index,
      // so a guessed region inherits the trusted frame instead of starting a new one. The seed set is
      // snapshotted from the post-phase-1 state before any of it is relaxed.
      queue.clear();
      bool any_unassigned = false;
      for (u32 f : shell_faces[s]) {
        if (rel[f] == 0) {
          any_unassigned = true;
          break;
        }
      }
      if (!any_unassigned) {
        continue;
      }
      for (u32 f : shell_faces[s]) {
        if (rel[f] == 0) {
          continue;
        }
        bool touches_unassigned = false;
        for (int e = 0; e < 3 && !touches_unassigned; e++) {
          const u32 a = fwg[f][e], b = fwg[f][(e + 1) % 3];
          if (a == b) {
            continue;
          }
          auto it = edges.find(edge_key(a, b));
          if (it == edges.end()) {
            continue;
          }
          for (const auto& er : it->second) {
            if (er.face != f && rel[er.face] == 0) {
              touches_unassigned = true;
              break;
            }
          }
        }
        if (touches_unassigned) {
          queue.push_back(f);
        }
      }
      r.faces_rel_guessed += flood(false);
      // Anything still unassigned is a remnant phase 1 never touched at all and that no assigned face
      // is adjacent to. Give it the old per-shell seed treatment — lowest face index, rel = 1 — so
      // coverage is identical to the single-phase fill's.
      for (u32 f : shell_faces[s]) {
        if (rel[f] != 0) {
          continue;
        }
        queue.clear();
        rel[f] = 1;
        queue.push_back(f);
        r.faces_rel_guessed++;
        r.faces_rel_guessed += flood(false);
      }
    }
  }
  // winding_conflicts: edges whose two (rel-corrected) traversals are NOT opposite. Counted once per
  // edge, after the BFS, so it is a property of the shell and not of the visit order.
  // In the SAME walk: open_edges — the edges NOT used by exactly two of the shell's faces. Every face
  // on an edge belongs to the same shell by construction (the shell IS the edge-connected component),
  // so an edge is charged to exactly one shell.
  for (const auto& kv : edges) {
    const auto& lst = kv.second;
    bool conflict = false;
    for (size_t i = 1; i < lst.size() && !conflict; i++) {
      const u32 fa = lst[i - 1].face, fb = lst[i].face;
      if (rel[fa] == 0 || rel[fb] == 0) {
        continue;
      }
      if ((int)lst[i - 1].dir * (int)rel[fa] == (int)lst[i].dir * (int)rel[fb]) {
        conflict = true;
      }
    }
    if (lst.empty()) {
      continue;
    }
    if (conflict) {
      r.shell_winding_conflicts[shell_of[lst[0].face]]++;
    }
    if (lst.size() != 2) {
      r.shell_open_edges[shell_of[lst[0].face]]++;
    }
    // ROUND 34: the 3+-face half of that count, kept separately. shell_open_edges is untouched.
    if (lst.size() >= 3) {
      r.shell_nonmanifold_edges[shell_of[lst[0].face]]++;
    }
  }
  for (u32 s = 0; s < n_shells; s++) {
    r.shell_closed[s] = (r.shell_open_edges[s] == 0) ? 1 : 0;
    if (r.shell_closed[s]) {
      r.shells_closed++;
    } else {
      r.shells_open++;
    }
  }

  // (b) THE SIGNED VOLUME, per shell. It is a FALLBACK by rank — it only ever decides a face the
  // per-face RAYF tier abstained on, and only where the shell is CLOSED (tier VOLX) — but the
  // quantity is computed everywhere because the rayf_vs_vol diagnostic needs it everywhere.
  for (u32 s = 0; s < n_shells; s++) {
    if (!r.shell_has_candidate[s]) {
      continue;
    }
    V3 lo{1e300, 1e300, 1e300}, hi{-1e300, -1e300, -1e300};
    for (u32 f : shell_faces[s]) {
      for (int e = 0; e < 3; e++) {
        const V3 p = pos(faces[f][e]);
        lo = V3{std::min(lo.x, p.x), std::min(lo.y, p.y), std::min(lo.z, p.z)};
        hi = V3{std::max(hi.x, p.x), std::max(hi.y, p.y), std::max(hi.z, p.z)};
      }
    }
    const V3 c = (lo + hi) * 0.5;
    // L = the MAX BBOX EXTENT.
    const double L = std::max(std::max(hi.x - lo.x, hi.y - lo.y), hi.z - lo.z);
    double v6 = 0;
    // ROUND 34: S, the shell's VECTOR AREA in its own winding frame, accumulated over the SAME faces
    // in the SAME order and with the SAME rel[] correction as the volume sum — the two must be in
    // ONE frame or the identity below does not hold. 6V about any origin c is
    //     6V(c) = 6V(0) - c . S,
    // because every term of det[p0-c, p1-c, p2-c] containing two copies of c vanishes and the
    // remaining c-terms collect into -c . (p0 x p1 + p1 x p2 + p2 x p0) = -c . cross(p1-p0, p2-p0).
    // Hence |S| is exactly what says how much a change of origin can move the volume. S == 0 on a
    // closed shell (the vector area of a closed surface vanishes), which is WHY the closed case is
    // origin-free.
    V3 svec{0, 0, 0};
    for (u32 f : shell_faces[s]) {
      const u32 i0 = faces[f][0];
      const u32 i1 = rel[f] < 0 ? faces[f][2] : faces[f][1];
      const u32 i2 = rel[f] < 0 ? faces[f][1] : faces[f][2];
      // Translate by the bbox CENTRE: world coordinates are 4096/m, so a raw triple product runs to
      // ~1e15 and the enclosed volume is lost to cancellation.
      const V3 a = pos(i0) - c, b = pos(i1) - c, d = pos(i2) - c;
      v6 += dot(a, cross(b, d));
      svec = svec + cross(b - a, d - a);  // c cancels in the differences; same rel[] frame as v6
    }
    const double sarea = len(svec);
    r.shell_vecarea[s] = sarea;
    // The margin the open-shell gate tests: the worst-case origin shift inside the bbox moves 6V by
    // at most |S| * L, so the SIGN of 6V survives any such shift iff this ratio exceeds
    // kOrientVolOpenRobust. Infinity when |S| * L == 0: no shift can change the sign at all.
    r.shell_vol_robust[s] = (sarea * L > 0.0) ? (std::abs(v6) / (sarea * L))
                                              : std::numeric_limits<double>::infinity();
    r.shell_v6_over_l3[s] = (L > 0.0) ? (v6 / (L * L * L)) : 0.0;
    if (L > 0.0 && std::abs(v6) > kOrientVolEps * L * L * L) {
      r.shell_gsign[s] = (s8)(v6 > 0 ? 1 : -1);
      r.shell_vol_sign[s] = r.shell_gsign[s];
      r.shell_tier[s] = (u8)kOrientShellVol;
    }
  }

  // Sampled faces for TIER ESC: up to 64 of the shell's LARGEST faces, chosen deterministically
  // (descending |cross|, ties broken on the LOWER face index).
  auto sample_faces = [&](u32 s) {
    std::vector<std::pair<double, u32>> byarea;
    byarea.reserve(shell_faces[s].size());
    for (u32 f : shell_faces[s]) {
      const double a = len(face_cross(f));
      if (a > 1e-6) {
        byarea.emplace_back(a, f);
      }
    }
    std::sort(byarea.begin(), byarea.end(), [](const auto& x, const auto& y) {
      if (x.first != y.first) {
        return x.first > y.first;
      }
      return x.second < y.second;
    });
    if (byarea.size() > (size_t)kOrientMaxSampleFaces) {
      byarea.resize(kOrientMaxSampleFaces);
    }
    return byarea;
  };

  // ONE accelerator over the WHOLE face list, built once, deterministically (nth_element on a TOTAL
  // order, so no address- or input-order dependence), used by BOTH ray tiers.
  Bvh bvh;
  {
    const auto t0 = std::chrono::steady_clock::now();
    bvh.build(faces, gv);
    r.bvh_nodes = (u32)bvh.nodes.size();
    r.bvh_seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
  }

  // ===============================================================================================
  // (c) TIER RAYF — THE PRIMARY GROUND TRUTH. PER FACE, NO PROPAGATION, NO GLOBAL ORIENTATION.
  //
  // "Lancer de rayon sortant": the visible side of a surface is the side that has OPEN SPACE on it.
  // For each face, take its own stored winding's geometric normal gn, put one probe 0.02 m along +gn
  // and one 0.02 m along -gn, and fire K rays from each into the corresponding hemisphere. A ray
  // ESCAPES when it finds nothing within 200 m. The side that escapes more is the outward side.
  //
  // Why this outranks the per-shell volume on an OPEN shell: (1) there, the cone volume about the
  // bbox centre is ORIGIN-DEPENDENT, so it is not even well defined; (2) a shell verdict has to be
  // carried to each face through the relative-winding BFS, and ONE bad link in that BFS (a fabricated
  // adjacency across an edge incident to 3+ faces, a mirrored copy, a decimated LOD triangle chained
  // onto the full-res mesh) flips a whole sub-tree of faces and poisons the shell. RAYF has neither
  // failure mode.
  //
  // The fixed K-point hemisphere spiral, in the local frame of gn, is cosine-ish stratified: the
  // i-th ray takes the stratum u = (i+0.5)/K of the projected-area measure, so sin(theta) = sqrt(u)
  // and cos(theta) = sqrt(1-u), and the azimuth advances by the golden angle. The MINUS-side set is
  // the EXACT MIRROR of the plus-side set (same tangential part, z negated), so the two hemispheres
  // are sampled symmetrically and esc_plus / esc_minus cannot be biased against each other by the
  // choice of frame.
  // ===============================================================================================
  std::vector<s8>& rayf_vote = r.rayf_vote;
  rayf_vote.assign(F, 0);
  r.rayf_margin.assign(F, 0);
  r.rayf_escapes_plus.assign(F, 0);
  r.rayf_escapes_minus.assign(F, 0);
  std::vector<u8>& rayf_plus = r.rayf_escapes_plus;
  std::vector<u8>& rayf_minus = r.rayf_escapes_minus;
  {
    // the candidate faces, ascending, so the work partition is a pure function of the face list
    std::vector<u32> rayf_faces;
    rayf_faces.reserve(r.candidate_faces);
    for (u32 f = 0; f < F; f++) {
      if (is_cand[f]) {
        rayf_faces.push_back(f);
      }
    }
    const double probe = kOrientRayfProbeM * units_per_m;  // 0.02 m
    const double tmax = kOrientRayfMaxM * units_per_m;     // 200 m
    const double tmin = kOrientRayfTMinM * units_per_m;    // 0.001 m
    const auto t0 = std::chrono::steady_clock::now();
    std::atomic<u64> next_chunk{0};
    const u64 chunk = 256;
    const u64 n_chunks = (rayf_faces.size() + chunk - 1) / chunk;
    // ONE FACE = ONE INDEPENDENT PROBLEM, and every input of that problem is either a compile-time
    // constant or a pure function of the face's own normal, so the result written into rayf_vote[f]
    // is identical whatever thread computes it and whatever order the chunks are claimed in. The
    // parallelism cannot move a single bit of the verdict.
    auto worker = [&]() {
      for (;;) {
        const u64 c = next_chunk.fetch_add(1);
        if (c >= n_chunks) {
          return;
        }
        const u64 clo = c * chunk;
        const u64 chi = std::min<u64>(clo + chunk, rayf_faces.size());
        for (u64 ii = clo; ii < chi; ii++) {
          const u32 f = rayf_faces[ii];
          const V3 gn = normalized(face_cross(f));
          if (len(gn) < 0.5) {
            continue;  // degenerate face: no normal, no vote
          }
          const V3 cen = face_centroid(f);
          V3 t1, t2;
          branchless_onb(gn, &t1, &t2);
          int esc[2] = {0, 0};
          for (int side = 0; side < 2; side++) {
            const double sgn = side == 0 ? 1.0 : -1.0;
            const V3 p = cen + gn * (sgn * probe);
            const double o[3] = {p.x, p.y, p.z};
            for (int i = 0; i < rayf_k; i++) {
              // the fixed spiral: stratum u of the projected-area measure, golden-angle azimuth
              const double u = ((double)i + 0.5) / (double)rayf_k;
              const double rr = std::sqrt(u);
              const double zz = std::sqrt(std::max(0.0, 1.0 - u));
              const double phi = 2.0 * 3.14159265358979323846 * kOrientGoldenConj * (double)i;
              const double cp = std::cos(phi), sp2 = std::sin(phi);
              // the MINUS set is the exact mirror of the PLUS set: same tangential part, z negated
              const V3 dirv = normalized(t1 * (rr * cp) + t2 * (rr * sp2) + gn * (sgn * zz));
              const double d[3] = {dirv.x, dirv.y, dirv.z};
              const bool blocked = bvh.any_hit(o, d, tmax, [&](u32 cand) {
                if (cand == f) {
                  return false;  // never the source face itself
                }
                return ray_tri_occl(o, d, pos(faces[cand][0]), pos(faces[cand][1]),
                                    pos(faces[cand][2]), tmin, tmax);
              });
              if (!blocked) {
                esc[side]++;
              }
            }
          }
          rayf_plus[f] = (u8)esc[0];
          rayf_minus[f] = (u8)esc[1];
          const int diff = esc[0] - esc[1];
          r.rayf_margin[f] = (s16)diff;
          if (std::abs(diff) >= kOrientRayfMinMargin) {
            rayf_vote[f] = (s8)(diff > 0 ? 1 : -1);
          }
        }
      }
    };
    const unsigned nthreads = in.threads > 0 ? (unsigned)in.threads
                                             : std::max(1u, std::thread::hardware_concurrency());
    r.threads_used = nthreads;
    std::vector<std::thread> pool;
    for (unsigned t = 1; t < nthreads; t++) {
      pool.emplace_back(worker);
    }
    worker();
    for (auto& th : pool) {
      th.join();
    }
    r.rayf_seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    // SATURATION DISCLOSURE. A tier that abstains can abstain for two OPPOSITE reasons, and the
    // difference is the difference between "the geometry is genuinely symmetric here" and "the
    // occlusion query is broken". esc==0 on both sides means every ray was blocked; esc==K on both
    // sides means none was. Both give diff==0 and both used to print the single word "abstained",
    // which is how a dead BVH traversal survived a whole round unnoticed.
    u64 plus_sum = 0, minus_sum = 0;
    for (u32 f : rayf_faces) {
      if (rayf_vote[f] != 0) {
        r.rayf_voted++;
      }
      plus_sum += rayf_plus[f];
      minus_sum += rayf_minus[f];
      if (rayf_plus[f] == 0 && rayf_minus[f] == 0) {
        r.rayf_sat_all_blocked++;
      } else if (rayf_plus[f] == (u8)rayf_k && rayf_minus[f] == (u8)rayf_k) {
        r.rayf_sat_all_open++;
      }
    }
    r.rayf_mean_escapes_plus =
        rayf_faces.empty() ? 0.0 : (double)plus_sum / (double)rayf_faces.size();
    r.rayf_mean_escapes_minus =
        rayf_faces.empty() ? 0.0 : (double)minus_sum / (double)rayf_faces.size();
  }

  // (d) TIER ESC — ESCAPE-DISTANCE ASYMMETRY against the WHOLE BVH. The LAST resort: it only has to
  // speak for a shell that still owns a candidate face RAYF abstained on.
  for (u32 s = 0; s < n_shells; s++) {
    if (!r.shell_has_candidate[s] || r.shell_gsign[s] != 0) {
      continue;
    }
    bool needs_fallback = false;
    for (u32 f : shell_faces[s]) {
      if (is_cand[f] && rayf_vote[f] == 0) {
        needs_fallback = true;
        break;
      }
    }
    if (!needs_fallback) {
      continue;
    }
    const auto sampled = sample_faces(s);
    if (sampled.empty()) {
      continue;
    }
    const double cap = kOrientEscMaxM * units_per_m;
    double sum_plus = 0, sum_minus = 0;
    u32 n = 0;
    for (const auto& sf : sampled) {
      const u32 f = sf.second;
      const V3 gn = normalized(face_cross(f));
      const V3 dir_out = gn * (double)rel[f];
      const V3 cen = face_centroid(f);
      for (int side = 0; side < 2; side++) {
        const V3 dd = side == 0 ? dir_out : dir_out * -1.0;
        const V3 p = cen + dd * (kOrientProbeEpsM * units_per_m);
        const double o[3] = {p.x, p.y, p.z};
        const double d[3] = {dd.x, dd.y, dd.z};
        double best = cap;
        bvh.traverse(o, d, cap, [&](u32 cand) {
          if (cand == f) {
            return;
          }
          double t = 0;
          if (ray_tri(o, d, pos(faces[cand][0]), pos(faces[cand][1]), pos(faces[cand][2]), &t) ==
              1) {
            if (t < best) {
              best = t;
            }
          }
        });
        if (side == 0) {
          sum_plus += best;
        } else {
          sum_minus += best;
        }
      }
      n++;
    }
    if (!n) {
      continue;
    }
    const double mp = sum_plus / (double)n, mm = sum_minus / (double)n;
    const double hi2 = std::max(mp, mm), lo2 = std::min(mp, mm);
    r.shell_esc_ratio[s] = lo2 > 0 ? hi2 / lo2 : (hi2 > 0 ? 1e9 : 1.0);
    if (r.shell_esc_ratio[s] >= kOrientEscMargin) {
      r.shell_gsign[s] = (s8)((mp > mm) ? 1 : -1);
      r.shell_tier[s] = (u8)kOrientShellEsc;
    }
  }

  // ===============================================================================================
  // (e) THE COLLISION AUTHORITY — a DECISION TIER, the THIRD one, below VOLX and RAYF.
  //
  // WHY IT MAY DECIDE AT ALL, given that the round-29 defect came from this very authority. Round 29
  // did not show that collision normals are worthless; it showed that they were let to OUTRANK an
  // exact signed volume through a vacuous competence gate. Here they outrank NOTHING: they are
  // consulted only on a face that the exact volume test could not reach (open shell) and that the
  // escape-ray test abstained on. On that residue the alternative is not a better authority, it is
  // no authority at all. A competence-filtered collision verdict is strictly more information than
  // silence, and it is placed where it can never displace a stronger one.
  // ===============================================================================================
  CollisionAuthority coll;
  const bool have_coll = in.coll_vertices && in.coll_normals && !in.coll_vertices->empty() &&
                         in.coll_vertices->size() == in.coll_normals->size();
  if (have_coll) {
    coll.build(*in.coll_vertices, *in.coll_normals, units_per_m);
  }
  for (u32 s = 0; s < n_shells; s++) {
    if (!r.shell_has_candidate[s]) {
      continue;
    }
    double agree_coll = 0, coll_area = 0;
    bool any_coll = false;
    for (u32 f : shell_faces[s]) {
      const V3 nraw = face_cross(f) * (double)rel[f];
      const double area = len(nraw);
      if (!(area > 1e-6)) {
        continue;
      }
      const V3 n = nraw * (1.0 / area);
      if (have_coll) {
        V3 cn;
        if (coll.nearest_normal(face_centroid(f), &cn)) {
          const double d = dot(n, cn);
          if (std::abs(d) > kOrientCollParallelMin) {  // round-29 per-face competence filter
            any_coll = true;
            agree_coll += area * d;
            coll_area += area;
          }
        }
      }
    }
    const double coll_conf = coll_area > 0.0 ? (agree_coll / coll_area) : 0.0;
    r.shell_coll_speaks[s] =
        (any_coll && std::abs(coll_conf) > kOrientCollConfMin) ? (u8)1 : (u8)0;
    r.shell_coll_sign[s] = r.shell_coll_speaks[s] ? (s8)(agree_coll > 0 ? 1 : -1) : (s8)0;
  }

  // ===============================================================================================
  // (f) THE PER-FACE OUTWARD DIRECTION AND ITS TIER — EXACTNESS FIRST, THEN RAYS, THEN COLLISION.
  //
  //        VOLX (exact volume on a CLOSED shell)
  //     -> RAYF (the per-face escape-ray vote)
  //     -> COLL (the competence-filtered collision verdict, carried by rel[])
  //     -> ESC  (the shell escape-distance asymmetry, last resort)
  //     -> UNDECIDED (face_sign stays 0)
  //
  // WHY EXACTNESS OUTRANKS SAMPLING. On a CLOSED shell the signed volume is not an estimate: the
  // divergence theorem makes sum_f rel[f]*dot(a,cross(b,c)) the enclosed volume EXACTLY, so its sign
  // settles inside-vs-outside with no free parameter, no origin dependence (a closed surface's cone
  // volume is origin-invariant) and no sampling error. The escape-ray test is, by construction, a
  // FINITE SAMPLE of K directions per hemisphere: it answers "which side has more open space", which
  // is only a PROXY for "which side is outside", and the proxy is measurably wrong on small props
  // half-buried in the terrain around them. Where the exact criterion is available it must win;
  // where it is not (an open shell), the sample is all there is.
  // ===============================================================================================
  r.face_sign.assign(F, 0);
  r.face_tier.assign(F, (u8)kOrientUndecided);
  r.face_rayf_vs_vol_conflict.assign(F, 0);
  // (a) THE DIAGNOSTIC CONFLICT MARK, recorded BEFORE any decision and changing none of them.
  for (u32 f = 0; f < F; f++) {
    const u32 s = shell_of[f];
    const int vol_here =
        (r.shell_vol_sign[s] != 0 && rel[f] != 0) ? (int)r.shell_vol_sign[s] * (int)rel[f] : 0;
    const int rayf_here = (int)rayf_vote[f];
    if (rayf_here != 0 && vol_here != 0 && rayf_here != vol_here) {
      r.face_rayf_vs_vol_conflict[f] = 1;
      r.rayf_vs_vol_conflict_faces++;
    }
  }
  // (b) THE SHELL BALLOT. Each face expresses its escape-ray MARGIN in the shell's own frame by
  //     multiplying by rel[f], and the margins are summed. Weighting by the margin rather than by
  //     the +-1 vote is the whole point: a face with 13 escapes on one side and 0 on the other is
  //     thirteen times as sure as a face at 7/6, and the half-buried props that made the per-face
  //     tier noisy are exactly the low-margin ones. Summation order is face id, so the double is
  //     accumulated identically on every run and every thread count (this loop is serial anyway).
  //     Faces the flood fill never reached (rel == 0) cannot express anything in the shell frame
  //     and are simply absent from the ballot.
  // The accumulator is an INTEGER on purpose. rayf_margin is a small signed count and rel is +-1, so
  // the sum is exact and — this is the point — INDEPENDENT OF SUMMATION ORDER. The offline grader
  // walks the same faces in a different order (it gathers per draw, the pipeline per tree), and a
  // double accumulator would let the two disagree on a shell whose ballot is near zero. Then the
  // pipeline would enforce one outward and the instrument would grade another, which is the exact
  // class of bug this round exists to remove.
  // ROUND 34 MEASURED AND REJECTED: weighting this ballot by face AREA instead of by face COUNT.
  // The reasoning was that area is exactly additive under subdivision where a count is multiplied by
  // four, so an area-weighted ballot would be an integral over the SURFACE and invariant to how that
  // surface happens to be triangulated. The reasoning is sound and the result was still WORSE, on
  // every arm measured on village1 (A_sign un-subdivided 99.9471% -> 99.9245%, subdivided 91.8395%
  // -> 91.5150%, subdivided with the T-junction bypass off 94.5391% -> 93.7914%). The ballot
  // weighting is therefore NOT what makes this authority sample-dependent; RAYF casts its rays from
  // face CENTROIDS, and subdivision moves every centroid, so the per-face margins themselves change.
  // Reweighting a set of votes cannot repair votes that were taken at different places. Left as a
  // count so the code matches what is actually measured to be best; do not "fix" it again without
  // re-running the three arms above.
  std::vector<s64> shell_ballot_i(n_shells, 0);
  std::vector<u64> shell_ballot_faces(n_shells, 0);
  for (u32 f = 0; f < F; f++) {
    if (!is_cand[f] || rel[f] == 0 || rayf_vote[f] == 0) {
      continue;
    }
    shell_ballot_i[shell_of[f]] += (s64)r.rayf_margin[f] * (s64)rel[f];
    shell_ballot_faces[shell_of[f]]++;
  }
  std::vector<double> shell_ballot(n_shells, 0.0);
  for (u32 s = 0; s < n_shells; s++) {
    shell_ballot[s] = (double)shell_ballot_i[s];  // published as a double for the report only
  }
  // (c) THE SHELL VERDICT — one per shell: VOLX (exact) then VOLOPEN (exact where the origin cannot
  //     change its sign) then RAYF (aggregated) then ESC.
  std::vector<s8> shell_sign(n_shells, 0);
  std::vector<u8> shell_verdict_tier(n_shells, (u8)kOrientShellUndecided);
  for (u32 s = 0; s < n_shells; s++) {
    if (r.shell_closed[s] && r.shell_vol_sign[s] != 0) {
      shell_sign[s] = r.shell_vol_sign[s];
      shell_verdict_tier[s] = (u8)kOrientShellVol;
      r.shells_volx++;
    } else if (r.shell_vol_sign[s] != 0 &&
               r.shell_vol_robust[s] > kOrientVolOpenRobust) {
      // ROUND 34 — VOLOPEN. The shell is OPEN, so the cone volume about the bbox centre is in
      // general origin-DEPENDENT and round 33 was right to refuse it as such. But the dependence is
      // LINEAR and bounded: 6V(c) = 6V(0) - c . S, so no origin inside the bbox can move 6V by more
      // than about |S| * L. Where |6V| exceeds that bound the SIGN is the same for EVERY admissible
      // origin, which makes it a well-defined quantity again and an exact verdict, not a sample.
      // The gate is the bound itself (kOrientVolOpenRobust == 1.0), and it degenerates to round 33's
      // closed-shell rule when S == 0. It sits BELOW closed VOLX and ABOVE RAYF because it is exact
      // where it speaks, but it speaks under a hypothesis (origin inside the bbox) that the closed
      // case does not need.
      shell_sign[s] = r.shell_vol_sign[s];
      shell_verdict_tier[s] = (u8)kOrientShellVolOpen;
      r.shells_volopen++;
    } else if (shell_ballot_i[s] != 0) {
      shell_sign[s] = (s8)(shell_ballot_i[s] > 0 ? 1 : -1);
      shell_verdict_tier[s] = (u8)kOrientShellRayf;
      r.shells_rayf++;
    } else if (r.shell_gsign[s] != 0 && r.shell_tier[s] == (u8)kOrientShellEsc) {
      // the shell escape-DISTANCE asymmetry. The shell TIER test matters: shell_gsign is also set by
      // the (non-deciding, on an open shell meaningless) volume test, and a verdict of that
      // provenance must not be allowed back in through this door.
      shell_sign[s] = r.shell_gsign[s];
      shell_verdict_tier[s] = (u8)kOrientShellEsc;
      r.shells_esc++;
    } else {
      r.shells_undecided++;
    }
  }
  // (d) DISTRIBUTE. This is the step that makes the field COHERENT: every face of a shell is
  //     oriented by the same verdict, carried to it by the exact topological relative winding. Two
  //     faces sharing an edge can no longer be handed opposite outwards, so a vertex they share can
  //     no longer be unsatisfiable because of a disagreement the authority invented.
  for (u32 f = 0; f < F; f++) {
    const u32 s = shell_of[f];
    if (rel[f] == 0) {
      r.faces_no_rel++;
      r.faces_undecided++;
      continue;  // face_sign stays 0
    }
    if (shell_sign[s] == 0) {
      r.faces_undecided++;
      continue;
    }
    r.face_sign[f] = (s8)((int)shell_sign[s] * (int)rel[f]);
    switch (shell_verdict_tier[s]) {
      case kOrientShellVol:
        r.face_tier[f] = (u8)kOrientVolx;
        r.faces_volx++;
        break;
      case kOrientShellVolOpen:
        r.face_tier[f] = (u8)kOrientVolxOpen;
        r.faces_volopen++;
        break;
      case kOrientShellRayf:
        r.face_tier[f] = (u8)kOrientRayf;
        r.faces_rayf++;
        break;
      default:
        r.face_tier[f] = (u8)kOrientEsc;
        r.faces_esc++;
        break;
    }
  }
  // r.shell_gsign / r.shell_tier are left as the SHELL-LEVEL FALLBACK diagnostics they always were.
  // The verdict actually used is published separately so a report can state which tier oriented a
  // shell without having to re-derive it.
  r.shell_verdict_sign = shell_sign;
  r.shell_verdict_tier = shell_verdict_tier;
  r.shell_ballot = shell_ballot;
  r.shell_ballot_faces = shell_ballot_faces;

  // rayf_vs_vol — the two INDEPENDENT geometric criteria, scored against each other PER SHELL over
  // the shell's own candidate faces. They agree on face f iff rayf_vote[f] == vol_sign * rel[f], i.e.
  // iff they hand that face the same outward direction. When the signed-volume test never spoke for
  // the shell (an open shell, or |V6| under the threshold) the comparison is reported as vol-silent
  // rather than being silently scored as agreement. DIAGNOSTIC ONLY: it suppresses no verdict.
  for (u32 f = 0; f < F; f++) {
    if (!is_cand[f] || rayf_vote[f] == 0) {
      continue;
    }
    const u32 s = shell_of[f];
    r.shell_rayf_voted[s]++;
    if (r.shell_vol_sign[s] == 0 || rel[f] == 0) {
      continue;
    }
    if ((int)rayf_vote[f] == (int)r.shell_vol_sign[s] * (int)rel[f]) {
      r.shell_rayf_agree[s]++;
      r.rayf_vs_vol_agree++;
    } else {
      r.shell_rayf_disagree[s]++;
      r.rayf_vs_vol_disagree++;
    }
  }

  r.seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t_all).count();
  return r;
}

}  // namespace tfrag3
