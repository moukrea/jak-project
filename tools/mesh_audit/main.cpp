// Grecharged-mesh-consolidation: OFFLINE whole-game mesh audit CLI (desktop only).
//
// Loads every level .fr3 of a game, runs the LEGACY/shipped global weld first (so the numbers
// describe the BEFORE state the owner currently sees on device), then runs the exhaustive
// mesh_consolidate() pass and records its MeshAuditReport.
//
// The point is the NO-OMISSIONS METRIC: coincident-but-unshared edges (forgotten welds) counted
// per level, per system, BEFORE and AFTER, plus the honest residual missed_welds_remaining.
//
// Usage: mesh_audit [--game jak1|jak2|jak3] [--fr3-dir DIR] [--level NAME] [--out PATH]
//                   [--csv PATH] [--limit N] [--bake] [--verify-bake]
//
// Read-only on the .fr3 files: nothing is ever written back to disk except the report + csv, and
// (with --bake) the per-level <level>.meshweld precompute sidecars next to the .fr3 files.

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <unordered_map>
#include <vector>

#include "common/custom_data/MeshConsolidate.h"
#include "common/custom_data/normal_pack.h"
#include "common/custom_data/Tfrag3Data.h"
#include "common/util/FileUtil.h"
#include "common/util/Serializer.h"
#include "common/util/compress.h"

#include "fmt/format.h"

// NOTE: FileUtil.h already defines `namespace fs = ghc::filesystem`; reuse it.

static void usage() {
  fmt::print(
      "Usage: mesh_audit [--game jak1|jak2|jak3] [--fr3-dir DIR] [--level NAME] [--out PATH]\n"
      "                  [--csv PATH] [--limit N] [--bake] [--verify-bake]\n"
      "  --game NAME    jak1 (default) | jak2 | jak3\n"
      "  --fr3-dir DIR  fr3 directory (default: <repo>/out/<game>/fr3)\n"
      "  --level NAME   audit only this level (default: every *.fr3, sorted)\n"
      "  --out PATH     report path (default: <repo>/.autoport/reports/\n"
      "                 Grecharged-mesh-consolidation/mesh_audit_<game>.txt)\n"
      "  --csv PATH     csv path (default: same dir, mesh_audit_<game>.csv)\n"
      "  --limit N      audit at most N levels (smoke runs)\n"
      "  --bake         also write the precompute sidecar <fr3-dir>/<level>.meshweld\n"
      "  --geom-orient  bake with the geometric outward-escape orientation vote (wrong for\n"
      "                 terrain/interiors, see ROUND 32; default is OFF, collision-first)\n"
      "  --no-geom-orient  accepted, no-op (this is the default now)\n"
      "  --check-orient DIR  offline: apply DIR/<level>.meshweld (the recharged pack's fr3/) and\n"
      "                 count decor triangles whose STORED normal opposes the coplanar collision\n"
      "  --verify-bake  round-trip self-test: re-load the fr3, apply the sidecar, and compare it\n"
      "                 field-by-field against the live pass (requires --bake)\n");
}

namespace {

// Everything we keep about a level once its (huge) tfrag3::Level has been freed.
struct LevelResult {
  std::string level;
  tfrag3::MeshAuditReport rep;
};

struct LevelFailure {
  std::string level;
  std::string what;
};

// The exact load+unpack sequence Loader.cpp performs, plus the legacy/shipped global weld. Used for
// BOTH the audited level and the fresh --verify-bake copy so the two start from identical geometry.
void load_level_fr3(const fs::path& fr3_path, tfrag3::Level& lev) {
  auto data = file_util::read_binary_file(fr3_path);
  auto decomp = compression::decompress_zstd(data.data(), data.size());
  Serializer ser(decomp.data(), decomp.size());
  lev.serialize(ser);
  // The packed fr3 leaves tree.unpacked.{vertices,indices} empty until unpack() runs
  // (mirror of Loader.cpp) — the audit reads exactly those arrays.
  for (auto& tie_tree : lev.tie_trees) {
    for (auto& tree : tie_tree) {
      tree.unpack();
    }
  }
  for (auto& t_tree : lev.tfrag_trees) {
    for (auto& tree : t_tree) {
      tree.unpack();
    }
  }
  for (auto& shrub_tree : lev.shrub_trees) {
    shrub_tree.unpack();
  }

  // The legacy/shipped pass FIRST: this is what the device does today, so the audit's
  // "before" numbers are the state the owner is actually looking at.
  tfrag3::reconstruct_level_global_weld(lev);
}

// ---- --verify-bake: flat view of every renderable tree, in gather_level()'s traversal order ----
constexpr int kCmpTfrag = 0, kCmpTie = 1, kCmpShrub = 2;
constexpr const char* kCmpSysName[3] = {"tfrag", "tie", "shrub"};

struct CmpTree {
  int system = 0;
  const void* verts = nullptr;
  size_t count = 0;
  const tfrag3::PackedTimeOfDay* colors = nullptr;
};

struct CmpVert {
  float x = 0, y = 0, z = 0;
  u32 nor = 0;
  u16 color_index = 0;
  u16 seam_w = 0;
};

void collect_cmp_trees(const tfrag3::Level& lev, std::vector<CmpTree>& out) {
  for (const auto& geom : lev.tfrag_trees) {
    for (const auto& t : geom) {
      out.push_back({kCmpTfrag, t.unpacked.vertices.data(), t.unpacked.vertices.size(), &t.colors});
    }
  }
  for (const auto& geom : lev.tie_trees) {
    for (const auto& t : geom) {
      out.push_back({kCmpTie, t.unpacked.vertices.data(), t.unpacked.vertices.size(), &t.colors});
    }
  }
  for (const auto& t : lev.shrub_trees) {
    out.push_back({kCmpShrub, t.unpacked.vertices.data(), t.unpacked.vertices.size(),
                   &t.time_of_day_colors});
  }
}

CmpVert cmp_vert(const CmpTree& t, size_t i) {
  CmpVert o;
  if (t.system == kCmpShrub) {
    const auto& v = ((const tfrag3::ShrubGpuVertex*)t.verts)[i];
    o.x = v.x;
    o.y = v.y;
    o.z = v.z;
    o.nor = v.nor;
    o.color_index = v.color_index;
    o.seam_w = v.seam_w;
  } else {
    const auto& v = ((const tfrag3::PreloadedVertex*)t.verts)[i];
    o.x = v.x;
    o.y = v.y;
    o.z = v.z;
    o.nor = v.nor;
    o.color_index = v.color_index;
    o.seam_w = v.seam_w;
  }
  return o;
}

std::string fbits(float f) {
  u32 b;
  std::memcpy(&b, &f, 4);
  return fmt::format("{:.9g}/0x{:08x}", f, b);
}

// Compares the sidecar-applied level against the live-pass level over the SAME traversal order.
// Prints at most `max_report` mismatch lines; returns the number of mismatches found.
u64 verify_bake_compare(const std::string& level_name,
                        const tfrag3::Level& live,
                        const tfrag3::Level& baked,
                        int max_report) {
  std::vector<CmpTree> a, b;
  collect_cmp_trees(live, a);
  collect_cmp_trees(baked, b);
  u64 bad = 0;
  auto report = [&](const std::string& what, s64 tree, s64 vert, const std::string& lhs,
                    const std::string& rhs) {
    bad++;
    if ((int)bad <= max_report) {
      fmt::print("VERIFY-BAKE {}: MISMATCH {} at {}/{} ({} vs {})\n", level_name, what, tree, vert,
                 lhs, rhs);
    }
  };
  if (a.size() != b.size()) {
    report("tree_count", -1, -1, fmt::format("{}", (u64)a.size()), fmt::format("{}", (u64)b.size()));
    return bad;
  }
  for (size_t ti = 0; ti < a.size() && (int)bad < max_report; ti++) {
    const char* sys = kCmpSysName[a[ti].system];
    if (a[ti].system != b[ti].system) {
      report("system", (s64)ti, -1, kCmpSysName[a[ti].system], kCmpSysName[b[ti].system]);
      continue;
    }
    if (a[ti].count != b[ti].count) {
      report(fmt::format("{}.vert_count", sys), (s64)ti, -1, fmt::format("{}", (u64)a[ti].count),
             fmt::format("{}", (u64)b[ti].count));
      continue;
    }
    for (size_t vi = 0; vi < a[ti].count && (int)bad < max_report; vi++) {
      const CmpVert va = cmp_vert(a[ti], vi);
      const CmpVert vb = cmp_vert(b[ti], vi);
      if (std::memcmp(&va.x, &vb.x, sizeof(float))) {
        report(fmt::format("{}.x", sys), (s64)ti, (s64)vi, fbits(va.x), fbits(vb.x));
      }
      if (std::memcmp(&va.y, &vb.y, sizeof(float))) {
        report(fmt::format("{}.y", sys), (s64)ti, (s64)vi, fbits(va.y), fbits(vb.y));
      }
      if (std::memcmp(&va.z, &vb.z, sizeof(float))) {
        report(fmt::format("{}.z", sys), (s64)ti, (s64)vi, fbits(va.z), fbits(vb.z));
      }
      if (va.nor != vb.nor) {
        report(fmt::format("{}.nor", sys), (s64)ti, (s64)vi, fmt::format("0x{:08x}", va.nor),
               fmt::format("0x{:08x}", vb.nor));
      }
      if (va.color_index != vb.color_index) {
        report(fmt::format("{}.color_index", sys), (s64)ti, (s64)vi,
               fmt::format("{}", va.color_index), fmt::format("{}", vb.color_index));
      }
      if (va.seam_w != vb.seam_w) {
        report(fmt::format("{}.seam_w", sys), (s64)ti, (s64)vi, fmt::format("{}", va.seam_w),
               fmt::format("{}", vb.seam_w));
      }
    }
    if ((int)bad >= max_report) {
      break;
    }
    const auto* ca = a[ti].colors;
    const auto* cb = b[ti].colors;
    if (!ca || !cb) {
      continue;
    }
    if (ca->color_count != cb->color_count) {
      report(fmt::format("{}.colors.color_count", sys), (s64)ti, -1,
             fmt::format("{}", ca->color_count), fmt::format("{}", cb->color_count));
    }
    if (ca->data.size() != cb->data.size()) {
      report(fmt::format("{}.colors.data_size", sys), (s64)ti, -1,
             fmt::format("{}", (u64)ca->data.size()), fmt::format("{}", (u64)cb->data.size()));
    } else if (!ca->data.empty() &&
               std::memcmp(ca->data.data(), cb->data.data(), ca->data.size())) {
      // name the first differing byte so the failure is actionable
      size_t off = 0;
      while (off < ca->data.size() && ca->data[off] == cb->data[off]) {
        off++;
      }
      report(fmt::format("{}.colors.data", sys), (s64)ti, (s64)off,
             fmt::format("0x{:02x}", ca->data[off]), fmt::format("0x{:02x}", cb->data[off]));
    }
  }
  return bad;
}

}  // namespace

// ================================================================================================
// --check-orient DIR — lighting-flipped-faces-everywhere (owner 25/09 : « un truc qu'on fait sur
// les assets du jeu directement »). HORS LIGNE, sans lancer le jeu : pour chaque niveau extrait de
// l'ISO (le .fr3, intact), applique le compagnon <niveau>.meshweld trouve dans DIR (le fr3/ du pack
// d'assets recharges) exactement comme Loader.cpp, puis compte les triangles du decor (tfrag, TIE
// statique, shrub) dont la normale STOCKEE par sommet s'oppose a la surface de collision COPLANAIRE
// (la cote marchable / visible du monde). La meme mesure sur l'asset d'origine (avant compagnon)
// est publiee a cote : c'est le temoin que l'instrument voit le defaut.
// Un triangle sans collision coplanaire n'a pas d'autorite : il est compte `unjudged`, jamais juge.
// ================================================================================================
struct OrientCount {
  u64 tris = 0, no_normal = 0, judged = 0, reversed = 0;
};

// Triangles de collision ranges par cellules de 2 m sur leur boite englobante.
struct CollTriGrid {
  struct Tri {
    math::Vector3f a, b, c;  // sommets
    math::Vector3f gn;       // normale geometrique unitaire (sens de l'enroulement)
    math::Vector3f n;        // normale STOCKEE de la collision, unitaire : l'autorite
  };
  std::vector<Tri> tris;
  std::unordered_map<u64, std::vector<u32>> cells;
  float cell = 2.f * 4096.f;
  static u64 key(s64 x, s64 y, s64 z) {
    return ((u64)(x & 0x1fffff) << 42) | ((u64)(y & 0x1fffff) << 21) | (u64)(z & 0x1fffff);
  }
  void build(const tfrag3::CollisionMesh& m) {
    for (size_t i = 0; i + 2 < m.vertices.size(); i += 3) {
      const auto& v0 = m.vertices[i];
      const auto& v1 = m.vertices[i + 1];
      const auto& v2 = m.vertices[i + 2];
      Tri t;
      t.a = math::Vector3f(v0.x, v0.y, v0.z);
      t.b = math::Vector3f(v1.x, v1.y, v1.z);
      t.c = math::Vector3f(v2.x, v2.y, v2.z);
      math::Vector3f g = (t.b - t.a).cross(t.c - t.a);
      const float gl = g.length();
      math::Vector3f n((float)v0.nx + v1.nx + v2.nx, (float)v0.ny + v1.ny + v2.ny,
                       (float)v0.nz + v1.nz + v2.nz);
      const float nl = n.length();
      if (!(gl > 1e-3f) || !(nl > 1e-6f)) {
        continue;
      }
      t.gn = g * (1.f / gl);
      t.n = n * (1.f / nl);
      if (std::abs(t.n.dot(t.gn)) < 0.9f) {
        continue;  // normale stockee hors du plan du triangle : pas une autorite fiable
      }
      const u32 id = (u32)tris.size();
      tris.push_back(t);
      s64 lo[3], hi[3];
      for (int k = 0; k < 3; k++) {
        const float mn = std::min({t.a[k], t.b[k], t.c[k]});
        const float mx = std::max({t.a[k], t.b[k], t.c[k]});
        lo[k] = (s64)std::floor(mn / cell);
        hi[k] = (s64)std::floor(mx / cell);
      }
      for (s64 x = lo[0]; x <= hi[0]; x++)
        for (s64 y = lo[1]; y <= hi[1]; y++)
          for (s64 z = lo[2]; z <= hi[2]; z++)
            cells[key(x, y, z)].push_back(id);
    }
  }
  // Autorite d'un triangle rendu : une collision COPLANAIRE (normales a moins de ~25 degres au
  // signe pres, centre a moins de 0,15 m du plan) dont l'aire contient le centre projete (0,1 m de
  // marge). La plus proche en distance au plan l'emporte.
  bool authority(const math::Vector3f& c, const math::Vector3f& gu, math::Vector3f* out) const {
    const auto it = cells.find(key((s64)std::floor(c.x() / cell), (s64)std::floor(c.y() / cell),
                                   (s64)std::floor(c.z() / cell)));
    if (it == cells.end()) {
      return false;
    }
    const float plane_tol = 0.15f * 4096.f, edge_tol = 0.10f * 4096.f;
    float best = plane_tol;
    bool found = false;
    bool opposed = false;  // une autre collision acceptee dit le contraire
    math::Vector3f best_n;
    std::vector<math::Vector3f> accepted;
    for (u32 id : it->second) {
      const Tri& t = tris[id];
      if (std::abs(gu.dot(t.gn)) < 0.9f) {
        continue;
      }
      const float d = (c - t.a).dot(t.gn);
      if (std::abs(d) >= plane_tol) {
        continue;
      }
      const math::Vector3f p = c - t.gn * d;
      const math::Vector3f* v[3] = {&t.a, &t.b, &t.c};
      bool inside = true;
      for (int e = 0; e < 3 && inside; e++) {
        const math::Vector3f edge = *v[(e + 1) % 3] - *v[e];
        math::Vector3f in = t.gn.cross(edge);
        const float il = in.length();
        if (!(il > 1e-6f)) {
          inside = false;
          break;
        }
        in = in * (1.f / il);
        inside = (p - *v[e]).dot(in) >= -edge_tol;
      }
      if (!inside) {
        continue;
      }
      accepted.push_back(t.n);
      if (std::abs(d) < best || !found) {
        best = std::abs(d);
        best_n = t.n;
        found = true;
      }
    }
    if (!found) {
      return false;
    }
    for (const auto& n : accepted) {
      opposed = opposed || n.dot(best_n) < 0.f;
    }
    // Collision a double face (les deux cotes d'une paroi mince sont marchables / heurtables) :
    // l'autorite ne sait pas quel cote est vu, elle s'abstient.
    if (opposed) {
      return false;
    }
    *out = best_n;
    return true;
  }
};

template <typename V>
void check_orient_tree(const std::vector<V>& verts,
                       const std::vector<u32>& idx,
                       bool use_strips,
                       const CollTriGrid& grid,
                       OrientCount& oc) {
  auto emit = [&](u32 i0, u32 i1, u32 i2) {
    if (i0 >= verts.size() || i1 >= verts.size() || i2 >= verts.size()) {
      return;
    }
    const V& a = verts[i0];
    const V& b = verts[i1];
    const V& c = verts[i2];
    const math::Vector3f pa(a.x, a.y, a.z), pb(b.x, b.y, b.z), pc(c.x, c.y, c.z);
    math::Vector3f g = (pb - pa).cross(pc - pa);
    const float gl = g.length();
    if (!(gl > 1e-3f)) {
      return;  // triangle degenere (raccord de bande) : pas une surface
    }
    oc.tris++;
    const math::Vector3f ns = tfrag3::unpack_gl_normal_2_10_10_10(a.nor) +
                              tfrag3::unpack_gl_normal_2_10_10_10(b.nor) +
                              tfrag3::unpack_gl_normal_2_10_10_10(c.nor);
    if (!(ns.length() > 1e-3f)) {
      oc.no_normal++;
      return;
    }
    math::Vector3f cn;
    if (!grid.authority((pa + pb + pc) * (1.f / 3.f), g * (1.f / gl), &cn)) {
      return;
    }
    oc.judged++;
    if (ns.dot(cn) < 0.f) {
      oc.reversed++;
    }
  };
  if (use_strips) {
    u32 x = UINT32_MAX, y = UINT32_MAX, k = 0;
    for (u32 vi : idx) {
      if (vi == UINT32_MAX) {
        x = y = UINT32_MAX;
        k = 0;
        continue;
      }
      if (x != UINT32_MAX && y != UINT32_MAX) {
        if ((k & 1) != 0) {
          emit(y, x, vi);
        } else {
          emit(x, y, vi);
        }
      }
      x = y;
      y = vi;
      k++;
    }
  } else {
    for (size_t t = 0; t + 2 < idx.size(); t += 3) {
      if (idx[t] != UINT32_MAX && idx[t + 1] != UINT32_MAX && idx[t + 2] != UINT32_MAX) {
        emit(idx[t], idx[t + 1], idx[t + 2]);
      }
    }
  }
}

// famille 0 = tfrag, 1 = TIE statique (le chemin vent n'est pas dans unpacked.indices), 2 = shrub
void check_orient_level(const tfrag3::Level& lev, const CollTriGrid& grid, OrientCount fam[3]) {
  for (const auto& geom : lev.tfrag_trees) {
    for (const auto& t : geom) {
      check_orient_tree(t.unpacked.vertices, t.unpacked.indices, t.use_strips, grid, fam[0]);
    }
  }
  for (const auto& geom : lev.tie_trees) {
    for (const auto& t : geom) {
      check_orient_tree(t.unpacked.vertices, t.unpacked.indices, t.use_strips, grid, fam[1]);
    }
  }
  for (const auto& t : lev.shrub_trees) {
    check_orient_tree(t.unpacked.vertices, t.indices, true, grid, fam[2]);
  }
}

// ================================================================================================
// --bake : ORIENTATION PAR LA COLLISION, ecrite UNE FOIS dans le compagnon (owner 25/09).
// Apres la passe de consolidation, la normale STOCKEE de chaque surface du decor est tournee du cote
// de la collision coplanaire (meme autorite que --check-orient) :
//   1. par COMPOSANTE (sommets relies par les triangles d'un arbre) : le vote, pondere par l'aire,
//      des triangles qui ont une autorite ; une composante majoritairement a l'envers est
//      retournee EN ENTIER, y compris ses triangles sans autorite (meme surface lissee) ;
//   2. par SOMMET : un sommet encore majoritairement oppose a l'autorite de ses triangles est
//      retourne (composante melee, souvent une soudure entre deux surfaces).
// Negation exacte du 2-10-10-10 : chaque composante 10 bits signee change de signe (plage +-511).
// ================================================================================================
inline u32 negate_packed_normal(u32 p) {
  u32 out = p & 0xc0000000u;
  for (int k = 0; k < 3; k++) {
    u32 v = (p >> (10 * k)) & 0x3ffu;
    int iv = (v & 0x200u) ? (int)v - 1024 : (int)v;
    out |= ((u32)(-iv) & 0x3ffu) << (10 * k);
  }
  return out;
}

struct OrientFix {
  u64 comps_flipped = 0, verts_flipped_comp = 0, verts_flipped_vertex = 0, verts_reset = 0,
      verts_zeroed = 0, rounds = 0;
};

template <typename V>
void orient_tree_by_collision(std::vector<V>& verts,
                              const std::vector<u32>& idx,
                              bool use_strips,
                              const CollTriGrid& grid,
                              OrientFix& fx) {
  const u32 n = (u32)verts.size();
  if (n == 0) {
    return;
  }
  struct Tri {
    u32 i[3];
    math::Vector3f cn;
    float area;
  };
  std::vector<Tri> judged;
  std::vector<u32> parent(n);
  for (u32 i = 0; i < n; i++) {
    parent[i] = i;
  }
  auto find = [&](u32 x) {
    while (parent[x] != x) {
      parent[x] = parent[parent[x]];
      x = parent[x];
    }
    return x;
  };
  auto emit = [&](u32 i0, u32 i1, u32 i2) {
    if (i0 >= n || i1 >= n || i2 >= n) {
      return;
    }
    const math::Vector3f pa(verts[i0].x, verts[i0].y, verts[i0].z);
    const math::Vector3f pb(verts[i1].x, verts[i1].y, verts[i1].z);
    const math::Vector3f pc(verts[i2].x, verts[i2].y, verts[i2].z);
    math::Vector3f g = (pb - pa).cross(pc - pa);
    const float gl = g.length();
    if (!(gl > 1e-3f)) {
      return;
    }
    parent[find(i0)] = find(i1);
    parent[find(i1)] = find(i2);
    math::Vector3f cn;
    if (grid.authority((pa + pb + pc) * (1.f / 3.f), g * (1.f / gl), &cn)) {
      judged.push_back({{i0, i1, i2}, cn, 0.5f * gl});
    }
  };
  if (use_strips) {
    u32 x = UINT32_MAX, y = UINT32_MAX, k = 0;
    for (u32 vi : idx) {
      if (vi == UINT32_MAX) {
        x = y = UINT32_MAX;
        k = 0;
        continue;
      }
      if (x != UINT32_MAX && y != UINT32_MAX) {
        if ((k & 1) != 0) {
          emit(y, x, vi);
        } else {
          emit(x, y, vi);
        }
      }
      x = y;
      y = vi;
      k++;
    }
  } else {
    for (size_t t = 0; t + 2 < idx.size(); t += 3) {
      if (idx[t] != UINT32_MAX && idx[t + 1] != UINT32_MAX && idx[t + 2] != UINT32_MAX) {
        emit(idx[t], idx[t + 1], idx[t + 2]);
      }
    }
  }
  if (judged.empty()) {
    return;
  }
  auto nrm = [&](u32 i) { return tfrag3::unpack_gl_normal_2_10_10_10(verts[i].nor); };
  // 1. composantes
  std::unordered_map<u32, double> cvote;
  for (const auto& t : judged) {
    const math::Vector3f ns = nrm(t.i[0]) + nrm(t.i[1]) + nrm(t.i[2]);
    const float d = ns.dot(t.cn);
    if (d != 0.f) {
      cvote[find(t.i[0])] += d > 0.f ? t.area : -t.area;
    }
  }
  std::unordered_map<u32, bool> cflip;
  for (const auto& [root, v] : cvote) {
    if (v < 0.0) {
      cflip[root] = true;
      fx.comps_flipped++;
    }
  }
  if (!cflip.empty()) {
    for (u32 i = 0; i < n; i++) {
      if (cflip.count(find(i)) && verts[i].nor != 0) {
        verts[i].nor = negate_packed_normal(verts[i].nor);
        fx.verts_flipped_comp++;
      }
    }
  }
  // 2. sommets
  std::unordered_map<u32, double> vvote;
  for (const auto& t : judged) {
    for (u32 i : t.i) {
      const float d = nrm(i).dot(t.cn);
      if (d != 0.f) {
        vvote[i] += d > 0.f ? t.area : -t.area;
      }
    }
  }
  for (const auto& [i, v] : vvote) {
    if (v < 0.0 && verts[i].nor != 0) {
      verts[i].nor = negate_packed_normal(verts[i].nor);
      fx.verts_flipped_vertex++;
    }
  }
  // 3. triangles encore a l'envers : leurs sommets sont partages avec des triangles que la
  //    collision oriente autrement (pli serre lisse d'un seul tenant). Un tel sommet recoit la
  //    moyenne, ponderee par l'aire, des normales de collision de SES triangles juges — si elle les
  //    satisfait tous ; sinon il garde la sienne et le triangle reste compte par --check-orient.
  std::unordered_map<u32, std::vector<u32>> incident;
  for (u32 k = 0; k < (u32)judged.size(); k++) {
    for (u32 i : judged[k].i) {
      incident[i].push_back(k);
    }
  }
  // Un sommet remis a zero peut laisser un voisin a l'envers : on repasse jusqu'a stabilite (un
  // sommet nul ne se rallume jamais, donc la boucle termine).
  for (int round = 0; round < 16; round++) {
  std::vector<u32> residual;
  for (u32 k = 0; k < (u32)judged.size(); k++) {
    const auto& t = judged[k];
    if ((nrm(t.i[0]) + nrm(t.i[1]) + nrm(t.i[2])).dot(t.cn) < 0.f) {
      residual.push_back(k);
    }
  }
  if (residual.empty()) {
    break;
  }
  fx.rounds = std::max(fx.rounds, (u64)round + 1);
  for (u32 k : residual) {
    for (u32 i : judged[k].i) {
      math::Vector3f m(0.f, 0.f, 0.f);
      for (u32 j : incident[i]) {
        m += judged[j].cn * judged[j].area;
      }
      const float ml = m.length();
      if (!(ml > 1e-6f)) {
        continue;
      }
      m = m * (1.f / ml);
      bool ok = true;
      for (u32 j : incident[i]) {
        ok = ok && m.dot(judged[j].cn) > 0.f;
      }
      if (ok) {
        const u32 packed = tfrag3::pack_gl_normal_2_10_10_10(m) | (verts[i].nor & 0xc0000000u);
        if (packed != verts[i].nor) {
          verts[i].nor = packed;
          fx.verts_reset++;
        }
      } else if ((verts[i].nor & 0x3fffffffu) != 0) {
        // 4. aucune normale ne satisfait ses triangles (deux cotes d'un pli a plat) : le sommet
        //    n'impose plus de cote, ses voisins decident (normale nulle, lue « sans normale »).
        verts[i].nor &= 0xc0000000u;
        fx.verts_zeroed++;
      }
    }
  }
  }
}

// Oriente tout le niveau et recopie les normales dans le compagnon (ordre de gather_level :
// tfrag, TIE, shrub). Rend false si le compagnon n'a pas le nombre de sommets attendu.
bool orient_level_by_collision(tfrag3::Level& lev, tfrag3::MeshBakeData* bake, OrientFix& fx) {
  CollTriGrid grid;
  grid.build(lev.collision);
  for (auto& geom : lev.tfrag_trees) {
    for (auto& t : geom) {
      orient_tree_by_collision(t.unpacked.vertices, t.unpacked.indices, t.use_strips, grid, fx);
    }
  }
  for (auto& geom : lev.tie_trees) {
    for (auto& t : geom) {
      orient_tree_by_collision(t.unpacked.vertices, t.unpacked.indices, t.use_strips, grid, fx);
    }
  }
  for (auto& t : lev.shrub_trees) {
    orient_tree_by_collision(t.unpacked.vertices, t.indices, true, grid, fx);
  }
  if (!bake) {
    return true;
  }
  std::vector<u32> nor;
  nor.reserve(bake->nor.size());
  for (const auto& geom : lev.tfrag_trees) {
    for (const auto& t : geom) {
      for (const auto& v : t.unpacked.vertices) {
        nor.push_back(v.nor);
      }
    }
  }
  for (const auto& geom : lev.tie_trees) {
    for (const auto& t : geom) {
      for (const auto& v : t.unpacked.vertices) {
        nor.push_back(v.nor);
      }
    }
  }
  for (const auto& t : lev.shrub_trees) {
    for (const auto& v : t.unpacked.vertices) {
      nor.push_back(v.nor);
    }
  }
  if (nor.size() != bake->nor.size()) {
    fmt::print("ORIENT-BAKE error: {} sommets relus, {} dans le compagnon\n", nor.size(),
               bake->nor.size());
    return false;
  }
  bake->nor.swap(nor);
  return true;
}

int run_check_orient(const std::vector<fs::path>& fr3_files, const std::string& check_dir) {
  u64 levels = 0, applied = 0, missing = 0, refused = 0;
  OrientCount tot, tot_before;
  for (const auto& fr3_path : fr3_files) {
    const std::string level_name = fr3_path.stem().string();
    levels++;
    tfrag3::Level lev;
    load_level_fr3(fr3_path, lev);
    CollTriGrid grid;
    grid.build(lev.collision);
    OrientCount before[3], after[3];
    check_orient_level(lev, grid, before);
    const fs::path side = fs::path(check_dir) / tfrag3::mesh_consolidate_bake_name(level_name);
    std::string state = "applied";
    if (!fs::exists(side)) {
      state = "missing";
      missing++;
    } else if (!tfrag3::mesh_consolidate_apply_bake(lev, side.string(), /*do_shrub=*/true)) {
      state = "refused";
      refused++;
    } else {
      applied++;
      check_orient_level(lev, grid, after);
    }
    OrientCount lb, la;
    for (int f = 0; f < 3; f++) {
      lb.tris += before[f].tris;
      lb.no_normal += before[f].no_normal;
      lb.judged += before[f].judged;
      lb.reversed += before[f].reversed;
      la.tris += after[f].tris;
      la.no_normal += after[f].no_normal;
      la.judged += after[f].judged;
      la.reversed += after[f].reversed;
    }
    tot_before.tris += lb.tris;
    tot_before.judged += lb.judged;
    tot_before.reversed += lb.reversed;
    tot.tris += la.tris;
    tot.no_normal += la.no_normal;
    tot.judged += la.judged;
    tot.reversed += la.reversed;
    fmt::print(
        "CHECK-ORIENT level={} sidecar={} coll_tris={} tris={} judged={} no_normal={} "
        "reversed_before={} reversed={} tfrag={}/{} tie={}/{} shrub={}/{}\n",
        level_name, state, grid.tris.size(), la.tris, la.judged, la.no_normal, lb.reversed,
        la.reversed, after[0].reversed, after[0].judged, after[1].reversed, after[1].judged,
        after[2].reversed, after[2].judged);
    fflush(stdout);
  }
  fmt::print(
      "CHECK-ORIENT-TOTAL levels={} sidecars_applied={} levels_missing={} levels_refused={} "
      "tris={} judged={} unjudged={} no_normal={} judged_before={} reversed_before={} reversed={}\n",
      levels, applied, missing, refused, tot.tris, tot.judged, tot.tris - tot.judged - tot.no_normal,
      tot.no_normal, tot_before.judged, tot_before.reversed, tot.reversed);
  return 0;
}

int main(int argc, char** argv) {
  std::string game = "jak1";
  std::string fr3_dir;
  std::string only_level;
  std::string out_path;
  std::string csv_path;
  int limit = -1;
  bool do_bake = false;
  bool verify_bake = false;
  bool geom_orient = false;
  std::string check_dir;

  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    auto need_val = [&](const char* name) -> std::string {
      if (i + 1 >= argc) {
        fmt::print("error: {} requires a value\n", name);
        usage();
        std::exit(2);
      }
      return argv[++i];
    };
    if (a == "--game") {
      game = need_val("--game");
    } else if (a == "--fr3-dir") {
      fr3_dir = need_val("--fr3-dir");
    } else if (a == "--level") {
      only_level = need_val("--level");
    } else if (a == "--out") {
      out_path = need_val("--out");
    } else if (a == "--csv") {
      csv_path = need_val("--csv");
    } else if (a == "--limit") {
      limit = std::stoi(need_val("--limit"));
    } else if (a == "--bake") {
      do_bake = true;
    } else if (a == "--no-geom-orient") {
      // no-op : c'est desormais le defaut (voir ROUND 32 plus bas).
    } else if (a == "--geom-orient") {
      geom_orient = true;
    } else if (a == "--check-orient") {
      check_dir = need_val("--check-orient");
    } else if (a == "--verify-bake") {
      verify_bake = true;
    } else if (a == "-h" || a == "--help") {
      usage();
      return 0;
    } else {
      fmt::print("error: unknown/unexpected argument '{}'\n", a);
      usage();
      return 2;
    }
  }

  if (game != "jak1" && game != "jak2" && game != "jak3") {
    fmt::print("error: --game must be jak1, jak2 or jak3 (got '{}')\n", game);
    return 2;
  }
  if (verify_bake && !do_bake) {
    fmt::print("error: --verify-bake round-trips the sidecar and therefore requires --bake\n");
    return 2;
  }

  // Resolve the repo so the default fr3 dir / report dir work from anywhere.
  bool have_project = file_util::setup_project_path({});
  if (fr3_dir.empty()) {
    if (!have_project) {
      fmt::print("error: could not resolve the jak-project directory; pass --fr3-dir.\n");
      return 1;
    }
    fr3_dir = (file_util::get_jak_project_dir() / "out" / game / "fr3").string();
  }
  if (out_path.empty() || csv_path.empty()) {
    if (!have_project) {
      fmt::print("error: could not resolve the jak-project directory; pass --out and --csv.\n");
      return 1;
    }
    const fs::path rep_dir =
        file_util::get_jak_project_dir() / ".autoport" / "reports" / "Grecharged-mesh-consolidation";
    file_util::create_dir_if_needed(rep_dir);
    if (out_path.empty()) {
      out_path = (rep_dir / fmt::format("mesh_audit_{}.txt", game)).string();
    }
    if (csv_path.empty()) {
      csv_path = (rep_dir / fmt::format("mesh_audit_{}.csv", game)).string();
    }
  }
  file_util::create_dir_if_needed_for_file(out_path);
  file_util::create_dir_if_needed_for_file(csv_path);

  if (!fs::exists(fr3_dir)) {
    fmt::print("error: fr3 dir not found: {}\n", fr3_dir);
    return 1;
  }

  // ---- enumerate the levels, sorted by filename so the sweep is deterministic ----
  std::vector<fs::path> fr3_files;
  if (!only_level.empty()) {
    fs::path p = fs::path(fr3_dir) / fmt::format("{}.fr3", only_level);
    if (!fs::exists(p)) {
      fmt::print("error: fr3 not found: {}\n", p.string());
      return 1;
    }
    fr3_files.push_back(p);
  } else {
    for (const auto& ent : fs::directory_iterator(fr3_dir)) {
      if (!ent.is_regular_file()) {
        continue;
      }
      if (ent.path().extension().string() == ".fr3") {
        fr3_files.push_back(ent.path());
      }
    }
    std::sort(fr3_files.begin(), fr3_files.end(),
              [](const fs::path& a, const fs::path& b) { return a.filename() < b.filename(); });
  }
  if (limit >= 0 && (int)fr3_files.size() > limit) {
    fr3_files.resize(limit);
  }

  if (fr3_files.empty()) {
    fmt::print("error: no .fr3 files found in {}\n", fr3_dir);
    return 1;
  }
  if (!check_dir.empty()) {
    return run_check_orient(fr3_files, check_dir);
  }

  auto cfg = tfrag3::mesh_consolidate_config_from_env();
  // ==============================================================================================
  // ROUND 32 — THE GEOMETRIC OUTWARD VOTE IS OFF BY DEFAULT (reverts ROUND 31).
  //
  // Census x86 25/09 (OG_FLIP_TOUR, training/beach/village3): the .meshweld baked WITH
  // kMeshBitGeomOrient forced leaves the stored tfrag normal facing away from the viewed face on
  // 887372/953716/759012 ppm of visible tfrag pixels; the live pass with default bits
  // (collision-first authority, no geometric escape vote) gives 98/41835/11301 ppm. The escape
  // vote picks "the side that sees open air", which is wrong for terrain (nothing under it: both
  // sides escape) and for interiors. The tessellation stage it was built for is deleted
  // (mesh-consolidate-without-consumer). --geom-orient re-enables it for A/B only.
  if (geom_orient) {
    cfg.bits |= tfrag3::kMeshBitGeomOrient;
  }

  fmt::print("[mesh_audit] game={} fr3_dir={} levels={} out={} csv={}\n", game, fr3_dir,
             (u64)fr3_files.size(), out_path, csv_path);
  fmt::print("[mesh_audit] cfg weld={:.3f}m wide={:.3f}m crease={:.1f}deg colthr={} bits={}\n",
             cfg.weld_m, cfg.weld_m * cfg.wide_scale, cfg.crease_deg, cfg.col_blend_threshold,
             cfg.bits);

  // Fresh report + csv for this run (then appended level by level, so a long sweep that dies
  // half-way still leaves everything it managed to audit on disk).
  std::ofstream out(out_path, std::ios::out | std::ios::trunc);
  if (!out) {
    fmt::print("error: cannot open out file '{}'\n", out_path);
    return 1;
  }
  std::ofstream csv(csv_path, std::ios::out | std::ios::trunc);
  if (!csv) {
    fmt::print("error: cannot open csv file '{}'\n", csv_path);
    return 1;
  }
  csv << tfrag3::mesh_audit_csv_header();
  csv.flush();

  out << fmt::format("##### MESH AUDIT SWEEP game={} fr3_dir={} levels={} #####\n", game, fr3_dir,
                     (u64)fr3_files.size());
  out << fmt::format("##### cfg weld={:.3f}m wide={:.3f}m crease={:.1f}deg colthr={} bits={}\n",
                     cfg.weld_m, cfg.weld_m * cfg.wide_scale, cfg.crease_deg,
                     cfg.col_blend_threshold, cfg.bits);
  out.flush();

  std::vector<LevelResult> results;
  std::vector<LevelFailure> failures;
  results.reserve(fr3_files.size());

  u64 bakes_written = 0, bake_total_bytes = 0;
  u64 verify_ok_levels = 0, verify_mismatch_levels = 0;
  // ROUND 29 — MIRRORED TIE INSTANCE CENSUS rollup accumulators.
  u64 sum_mirror_matrices = 0, sum_mirror_matrices_mir = 0;
  u64 sum_mirror_groups = 0, sum_mirror_groups_mir = 0;
  u64 sum_mirror_verts = 0, sum_mirror_verts_mir = 0;
  u64 sum_mirror_groups_mir_nor = 0;

  const int n_total = (int)fr3_files.size();
  for (int k = 0; k < n_total; ++k) {
    const fs::path& fr3_path = fr3_files[k];
    const std::string level_name = fr3_path.stem().string();

    tfrag3::MeshAuditReport rep;
    rep.level_name = level_name;
    rep.game_name = game;
    bool ok = false;
    std::string bake_note;  // appended to the per-level progress line
    // ROUND 29 — MIRRORED TIE INSTANCE CENSUS. Filled inside the level scope (the level is freed
    // before the report text is formatted), so it has to live out here.
    tfrag3::TieMirrorCensus mirror;

    try {
      // Scope the (hundreds of MB) level so it is freed before the next one loads.
      {
        tfrag3::Level lev;
        load_level_fr3(fr3_path, lev);

        tfrag3::MeshBakeData bake;
        tfrag3::mesh_consolidate(lev, cfg, &rep, do_bake ? &bake : nullptr);
        // Pure measurement, before the level is freed. Never modifies the level.
        mirror = tfrag3::tie_mirror_census(lev);
        rep.game_name = game;
        if (rep.level_name.empty()) {
          rep.level_name = level_name;
        }

        if (do_bake) {
          OrientFix fx;
          if (!orient_level_by_collision(lev, &bake, fx)) {
            throw std::runtime_error("orient_level_by_collision: gather order mismatch");
          }
          fmt::print("ORIENT-BAKE level={} comps_flipped={} verts_flipped_comp={} "
                     "verts_flipped_vertex={} verts_reset={} verts_zeroed={} rounds={}\n",
                     level_name, fx.comps_flipped, fx.verts_flipped_comp,
                     fx.verts_flipped_vertex, fx.verts_reset, fx.verts_zeroed, fx.rounds);
          const std::string bake_path =
              (fs::path(fr3_dir) / tfrag3::mesh_consolidate_bake_name(level_name)).string();
          u64 bake_bytes = 0;
          bool bake_ok = tfrag3::mesh_consolidate_bake_write(level_name, bake, bake_path);
          if (bake_ok) {
            std::error_code ec;
            const auto sz = fs::file_size(bake_path, ec);
            if (ec) {
              bake_ok = false;
            } else {
              bake_bytes = (u64)sz;
            }
          }
          if (bake_ok) {
            bakes_written++;
            bake_total_bytes += bake_bytes;
            bake_note += fmt::format(" bake={}", bake_bytes);
          } else {
            bake_note += " bake=FAILED";
          }

          if (verify_bake) {
            // THE ROUND-TRIP PROOF: a completely fresh copy of the same fr3, moved forward ONLY by
            // the sidecar, must equal the level the live pass just produced, field for field.
            u64 bad = 0;
            if (!bake_ok) {
              fmt::print("VERIFY-BAKE {}: MISMATCH bake_write_failed at -1/-1 (ok vs FAILED)\n",
                         level_name);
              bad = 1;
            } else {
              tfrag3::Level lev2;
              load_level_fr3(fr3_path, lev2);
              if (!tfrag3::mesh_consolidate_apply_bake(lev2, bake_path, /*do_shrub=*/true)) {
                fmt::print(
                    "VERIFY-BAKE {}: MISMATCH apply_bake_returned_false at -1/-1 (true vs false)\n",
                    level_name);
                bad = 1;
              } else {
                bad = verify_bake_compare(level_name, lev, lev2, 5);
              }
            }
            if (bad == 0) {
              verify_ok_levels++;
              fmt::print("VERIFY-BAKE {}: OK\n", level_name);
            } else {
              verify_mismatch_levels++;
            }
            fflush(stdout);
          }
        }
      }  // lev freed here
      ok = true;
    } catch (const std::exception& e) {
      failures.push_back({level_name, e.what()});
      fmt::print("[{}/{}] {} FAILED: {}\n", k + 1, n_total, level_name, e.what());
      out << fmt::format("===== MESH AUDIT level={} game={} FAILED: {} =====\n", level_name, game,
                         e.what());
      out.flush();
      continue;
    }

    if (ok) {
      out << tfrag3::format_mesh_audit(rep, cfg);
      // ROUND 29 — ONE physical line, alongside the other "-- SECTION --" lines. Kept here rather
      // than inside format_mesh_audit() because the census needs the LEVEL (already freed by then)
      // and not the report struct.
      out << fmt::format("-- TIE MIRRORED INSTANCES (round 29) -- matrices={} mirrored_matrices={} "
                         "groups={} mirrored_groups={} verts={} mirrored_verts={} "
                         "mirrored_groups_with_normals={}\n",
                         mirror.matrices, mirror.mirrored_matrices, mirror.groups,
                         mirror.mirrored_groups, mirror.verts, mirror.mirrored_verts,
                         mirror.mirrored_groups_with_normals);
      sum_mirror_matrices += mirror.matrices;
      sum_mirror_matrices_mir += mirror.mirrored_matrices;
      sum_mirror_groups += mirror.groups;
      sum_mirror_groups_mir += mirror.mirrored_groups;
      sum_mirror_verts += mirror.verts;
      sum_mirror_verts_mir += mirror.mirrored_verts;
      sum_mirror_groups_mir_nor += mirror.mirrored_groups_with_normals;
      out.flush();
      csv << tfrag3::mesh_audit_csv_row(rep);
      csv.flush();
      results.push_back({level_name, rep});

      fmt::print(
          "[{}/{}] {} tris={} coincident_unshared={} missed_welds_remaining={} nrm_max_after={:.3f} "
          "col_max_after={:.1f} pol_pairs={} pol_before={} pol_after={} true_after={} weak_after={} "
          "inward_after={} tanw={} noauth={} voldec={} raydec={} undec={} collincomp={} uvmir={} "
          "uvsplit={} elapsed={:.0f}ms{}\n",
          k + 1, n_total, level_name, rep.total.tris, rep.total.coincident_unshared,
          rep.total.missed_welds, rep.nrm_after.max, rep.col_after.max, rep.orient_pairs_total,
          rep.orient_pairs_inconsistent_before, rep.orient_pairs_inconsistent_after,
          rep.orient_pairs_true_inconsistent_after, rep.orient_pairs_weak_inconsistent_after,
          rep.orient_faces_inward_after, rep.orient_tangent_w_flipped,
          rep.orient_comps_no_authority, rep.orient_comps_volume_decided,
          rep.orient_comps_raycast_decided, rep.orient_comps_undecided,
          rep.orient_comps_collision_incompetent, rep.uv_tris_mirrored,
          rep.uv_verts_handedness_split, rep.elapsed_ms, bake_note);
      fflush(stdout);
    }
  }

  // ---------------------------------------------------------------------------------------------
  // ROLLUP. One physical line per fact (a validator greps this line-wise) — never wrap these.
  // ---------------------------------------------------------------------------------------------
  u64 sum_tris = 0, sum_open_raw = 0, sum_coincident = 0, sum_coincident_pairs = 0;
  u64 sum_open_by_group = 0, sum_missed = 0;
  double max_nrm_before = 0, max_nrm_after = 0, max_col_before = 0, max_col_after = 0;
  u64 levels_clean = 0;
  // round-22 authority-free polarity census
  u64 sum_pairs = 0, sum_pol_before = 0, sum_pol_after = 0, sum_tanw = 0;
  u64 sum_inward_after = 0, levels_pol_clean = 0, levels_inward_clean = 0;
  u64 sum_true = 0, sum_true_b = 0, sum_true_a = 0;
  u64 sum_weak = 0, sum_weak_b = 0, sum_weak_a = 0, levels_true_clean = 0;
  // round-28 second (geometric) orientation authority + UV determinant census
  u64 sum_comps = 0, sum_noauth = 0, sum_noauth_faces = 0;
  u64 sum_voldec = 0, sum_raydec = 0, sum_undec = 0;
  u64 sum_uv_tris = 0, sum_uv_mirrored = 0, sum_uv_degen = 0, sum_uv_split = 0;
  // round-29: components a collision normal reached but was NOT competent to judge
  u64 sum_collincomp = 0;
  for (const auto& r : results) {
    sum_collincomp += r.rep.orient_comps_collision_incompetent;
    sum_comps += r.rep.orient_components;
    sum_noauth += r.rep.orient_comps_no_authority;
    sum_noauth_faces += r.rep.orient_faces_no_authority;
    sum_voldec += r.rep.orient_comps_volume_decided;
    sum_raydec += r.rep.orient_comps_raycast_decided;
    sum_undec += r.rep.orient_comps_undecided;
    sum_uv_tris += r.rep.uv_tris_total;
    sum_uv_mirrored += r.rep.uv_tris_mirrored;
    sum_uv_degen += r.rep.uv_tris_degenerate;
    sum_uv_split += r.rep.uv_verts_handedness_split;
  }
  for (const auto& r : results) {
    sum_pairs += r.rep.orient_pairs_total;
    sum_pol_before += r.rep.orient_pairs_inconsistent_before;
    sum_pol_after += r.rep.orient_pairs_inconsistent_after;
    sum_tanw += r.rep.orient_tangent_w_flipped;
    sum_inward_after += r.rep.orient_faces_inward_after;
    sum_true += r.rep.orient_pairs_true_manifold;
    sum_true_b += r.rep.orient_pairs_true_inconsistent_before;
    sum_true_a += r.rep.orient_pairs_true_inconsistent_after;
    sum_weak += r.rep.orient_pairs_weak;
    sum_weak_b += r.rep.orient_pairs_weak_inconsistent_before;
    sum_weak_a += r.rep.orient_pairs_weak_inconsistent_after;
    if (r.rep.orient_pairs_inconsistent_after == 0) {
      levels_pol_clean++;
    }
    if (r.rep.orient_pairs_true_inconsistent_after == 0) {
      levels_true_clean++;
    }
    if (r.rep.orient_faces_inward_after == 0) {
      levels_inward_clean++;
    }
  }
  for (const auto& r : results) {
    sum_tris += r.rep.total.tris;
    sum_open_raw += r.rep.total.open_raw;
    sum_coincident += r.rep.total.coincident_unshared;
    sum_coincident_pairs += r.rep.total.coincident_unshared_pairs;
    sum_open_by_group += r.rep.total.open_by_group;
    sum_missed += r.rep.total.missed_welds;
    max_nrm_before = std::max(max_nrm_before, r.rep.nrm_before.max);
    max_nrm_after = std::max(max_nrm_after, r.rep.nrm_after.max);
    max_col_before = std::max(max_col_before, r.rep.col_before.max);
    max_col_after = std::max(max_col_after, r.rep.col_after.max);
    if (r.rep.total.missed_welds == 0) {
      levels_clean++;
    }
  }

  std::vector<const LevelResult*> worst;
  worst.reserve(results.size());
  for (const auto& r : results) {
    worst.push_back(&r);
  }
  std::sort(worst.begin(), worst.end(), [](const LevelResult* a, const LevelResult* b) {
    if (a->rep.total.missed_welds != b->rep.total.missed_welds) {
      return a->rep.total.missed_welds > b->rep.total.missed_welds;
    }
    return a->level < b->level;
  });

  std::string roll;
  roll += "##### MESH AUDIT ROLLUP #####\n";
  roll += fmt::format("LEVELS AUDITED: {}\n", (u64)results.size());
  roll += fmt::format("LEVELS FAILED: {}\n", (u64)failures.size());
  for (const auto& f : failures) {
    roll += fmt::format("FAILED LEVEL: {} : {}\n", f.level, f.what);
  }
  roll += fmt::format("TOTAL TRIS: {}\n", sum_tris);
  roll += fmt::format("TOTAL OPEN_RAW: {}\n", sum_open_raw);
  roll += fmt::format("TOTAL COINCIDENT_UNSHARED (BEFORE): {}\n", sum_coincident);
  roll += fmt::format("TOTAL COINCIDENT_UNSHARED_PAIRS: {}\n", sum_coincident_pairs);
  roll += fmt::format("TOTAL OPEN_BY_GROUP: {}\n", sum_open_by_group);
  roll += fmt::format("TOTAL MISSED_WELDS_REMAINING (AFTER): {}\n", sum_missed);
  roll += "WORST 10 LEVELS BY missed_welds_remaining:\n";
  for (size_t i = 0; i < worst.size() && i < 10; ++i) {
    roll += fmt::format("  {} missed={} of coincident_unshared={}\n", worst[i]->level,
                        worst[i]->rep.total.missed_welds, worst[i]->rep.total.coincident_unshared);
  }
  roll += fmt::format("MAX NRM DELTA BEFORE: {:.3f} deg\n", max_nrm_before);
  roll += fmt::format("MAX NRM DELTA AFTER: {:.3f} deg\n", max_nrm_after);
  roll += fmt::format("MAX COL DELTA BEFORE: {:.1f}\n", max_col_before);
  roll += fmt::format("MAX COL DELTA AFTER: {:.1f}\n", max_col_after);
  roll += fmt::format("PER-LEVEL COVERAGE: {}/{} levels audited, {} levels with "
                      "missed_welds_remaining == 0\n",
                      (u64)results.size(), (u64)fr3_files.size(), levels_clean);
  roll += fmt::format("TOTAL ORIENT_PAIRS: {}\n", sum_pairs);
  roll += fmt::format("TOTAL ORIENT_PAIRS_INCONSISTENT_BEFORE: {}\n", sum_pol_before);
  roll += fmt::format("TOTAL ORIENT_PAIRS_INCONSISTENT_AFTER: {}\n", sum_pol_after);
  roll += fmt::format("TOTAL ORIENT_TANGENT_W_FLIPPED: {}\n", sum_tanw);
  roll += fmt::format("TOTAL ORIENT_FACES_INWARD_AFTER: {}\n", sum_inward_after);
  roll += fmt::format("TOTAL ORIENT_PAIRS_TRUE_MANIFOLD: {} inconsistent_before={} "
                      "inconsistent_after={}\n",
                      sum_true, sum_true_b, sum_true_a);
  roll += fmt::format("TOTAL ORIENT_PAIRS_WEAK: {} inconsistent_before={} inconsistent_after={}\n",
                      sum_weak, sum_weak_b, sum_weak_a);
  roll += fmt::format("POLARITY COVERAGE: {}/{} levels with orient_pairs_inconsistent_after == 0, "
                      "{}/{} levels with orient_pairs_true_inconsistent_after == 0, "
                      "{}/{} levels with orient_faces_inward_after == 0\n",
                      levels_pol_clean, (u64)results.size(), levels_true_clean,
                      (u64)results.size(), levels_inward_clean, (u64)results.size());
  // ---- round-28: the SECOND (geometric) orientation authority, one physical line per fact ----
  roll += fmt::format("TOTAL ORIENT_COMPONENTS: {}\n", sum_comps);
  roll += fmt::format("TOTAL ORIENT_COMPS_NO_AUTHORITY: {}\n", sum_noauth);
  roll += fmt::format("TOTAL ORIENT_FACES_NO_AUTHORITY: {}\n", sum_noauth_faces);
  roll += fmt::format("TOTAL ORIENT_COMPS_VOLUME_DECIDED: {}\n", sum_voldec);
  roll += fmt::format("TOTAL ORIENT_COMPS_RAYCAST_DECIDED: {}\n", sum_raydec);
  roll += fmt::format("TOTAL ORIENT_COMPS_UNDECIDED: {} ORIENT_COLL_INCOMPETENT={}\n", sum_undec,
                      sum_collincomp);
  // ROUND 29 — MIRRORED TIE INSTANCE CENSUS, one physical line.
  roll += fmt::format("TIE_MIRROR_TOTAL matrices={} mirrored_matrices={} groups={} "
                      "mirrored_groups={} verts={} mirrored_verts={} "
                      "mirrored_groups_with_normals={}\n",
                      sum_mirror_matrices, sum_mirror_matrices_mir, sum_mirror_groups,
                      sum_mirror_groups_mir, sum_mirror_verts, sum_mirror_verts_mir,
                      sum_mirror_groups_mir_nor);
  roll += fmt::format("TOTAL UV_TRIS: {}\n", sum_uv_tris);
  roll += fmt::format("TOTAL UV_TRIS_MIRRORED: {}\n", sum_uv_mirrored);
  roll += fmt::format("TOTAL UV_TRIS_DEGENERATE: {}\n", sum_uv_degen);
  roll += fmt::format("TOTAL UV_VERTS_HANDEDNESS_SPLIT: {}\n", sum_uv_split);
  if (do_bake) {
    roll += fmt::format("BAKED SIDECARS: {} written, {} total\n", bakes_written, bake_total_bytes);
  }
  if (verify_bake) {
    roll += fmt::format("BAKE ROUND-TRIP: {} OK, {} MISMATCH\n", verify_ok_levels,
                        verify_mismatch_levels);
  }

  out << roll;
  out.flush();
  out.close();
  csv.close();

  fmt::print("\n{}", roll);
  fmt::print("[mesh_audit] wrote {}\n", out_path);
  fmt::print("[mesh_audit] wrote {}\n", csv_path);

  return results.empty() ? 1 : 0;
}
