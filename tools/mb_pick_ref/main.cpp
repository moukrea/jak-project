// Grecharged-mesh-browser V2.3: mb_pick_ref — CPU brute-force REFERENCE for the mesh-browser
// reticle pick (desktop only, offline).
//
// The runtime pick (render thread, game/graphics/opengl_renderer/background/MeshBrowserGizmos.cpp
// mb_pick::raytest + the GOAL-side resolution in game/kernel/jak1/kmachine.cpp) finds the globally
// nearest ray-triangle hit over a level's rendered geometry and resolves it to a mesh_index row.
// This tool recomputes the expected answer from the SAME data files (the level .fr3 +
// mesh_index_<level>.txt) for a list of rays, so a harness can compare device picks against it.
//
// INDEPENDENCE: this is a deliberate re-implementation. It does NOT link or call any game/ code.
// The strip/list decode (walk_tris) and the tolerances are duplicated ON PURPOSE with identical
// semantics so results are comparable; the intersection math itself is written independently.
//
// Usage:
//   mb_pick_ref --fr3 LEVEL.fr3 --index mesh_index_<level>.txt --rays rays.txt
// rays.txt: one ray per line `ox oy oz dx dy dz` (origin GOAL units, dir normalized here),
// '#' lines skipped. Output per ray i (0-based):
//   REF i=<i> row=<row> t=<t GOAL units> tex=<texid> tri=<ordinal> hit=<x,y,z>
//   REF i=<i> none                                    (no triangle within 500*4096 GOAL units)
//   REF i=<i> unresolved tex=... t=... tri=... hit=...  (hit, but no index row of that sys+tex)

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <limits>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>

#include "common/custom_data/Tfrag3Data.h"
#include "common/util/FileUtil.h"
#include "common/util/Serializer.h"
#include "common/util/compress.h"

#include "fmt/format.h"

namespace {

// ---------------------------------------------------------------------------------------------
// fr3 loading — mirrors tools/tess_sign/main.cpp load_level_fr3 (and the game's Loader.cpp):
// read file -> zstd decompress -> Serializer -> lev.serialize(ser) -> unpack() every tree so
// tree.unpacked.{vertices,indices} are populated.
// ---------------------------------------------------------------------------------------------
void load_level_fr3(const std::string& fr3_path, tfrag3::Level& lev) {
  auto data = file_util::read_binary_file(fr3_path);
  auto decomp = compression::decompress_zstd(data.data(), data.size());
  Serializer ser(decomp.data(), decomp.size());
  lev.serialize(ser);
  for (auto& t_tree : lev.tfrag_trees) {
    for (auto& tree : t_tree) {
      tree.unpack();
    }
  }
  for (auto& tie_tree : lev.tie_trees) {
    for (auto& tree : tie_tree) {
      tree.unpack();
    }
  }
}

// ---------------------------------------------------------------------------------------------
// walk_tris — IDENTICAL semantics to the file-scope walk_tris at the top of
// MeshBrowserGizmos.cpp (itself matching tess_sign): UINT32_MAX restarts a strip, odd-step
// winding flip emits (b, a, vi), degenerate and out-of-range triangles are dropped, and an index
// range past the end of the buffer emits nothing.
// ---------------------------------------------------------------------------------------------
template <typename F>
void walk_tris(const std::vector<u32>& idx,
               u32 first,
               u64 count,
               bool strips,
               size_t vcount,
               F&& emit_cb) {
  auto emit = [&](u32 a, u32 b, u32 c) {
    if (a == b || b == c || a == c) {
      return;  // degenerate (strip stitch)
    }
    if (a >= vcount || b >= vcount || c >= vcount) {
      return;  // out of bounds — defensive
    }
    emit_cb(a, b, c);
  };
  if ((u64)first + count > (u64)idx.size()) {
    return;
  }
  if (strips) {
    u32 a = UINT32_MAX, b = UINT32_MAX, k = 0;
    for (u64 j = 0; j < count; j++) {
      const u32 vi = idx[first + j];
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
    for (u64 j = 0; j + 2 < count; j += 3) {
      const u32 t0 = idx[first + j], t1 = idx[first + j + 1], t2 = idx[first + j + 2];
      if (t0 == UINT32_MAX || t1 == UINT32_MAX || t2 == UINT32_MAX) {
        continue;
      }
      emit(t0, t1, t2);
    }
  }
}

// ---------------------------------------------------------------------------------------------
// Ray-triangle: Moller-Trumbore in FLOAT precision, SAME tolerances as the runtime ray_tri
// (det eps 1e-12, u/v slack -1e-4 .. 1.0001, t >= 0, backfaces count). Independent
// implementation on a local Vec3 — no game code, no common math types.
// ---------------------------------------------------------------------------------------------
struct Vec3 {
  float x, y, z;
};
inline Vec3 sub(const Vec3& a, const Vec3& b) {
  return {a.x - b.x, a.y - b.y, a.z - b.z};
}
inline Vec3 cross(const Vec3& a, const Vec3& b) {
  return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}
inline float dot(const Vec3& a, const Vec3& b) {
  return a.x * b.x + a.y * b.y + a.z * b.z;
}

// Returns t >= 0 along the (unit) ray, or a negative value on miss.
float ray_tri(const Vec3& o, const Vec3& d, const Vec3& p0, const Vec3& p1, const Vec3& p2) {
  const Vec3 e1 = sub(p1, p0);
  const Vec3 e2 = sub(p2, p0);
  const Vec3 pv = cross(d, e2);
  const float det = dot(e1, pv);
  if (std::fabs(det) < 1e-12f) {
    return -1.f;
  }
  const float inv = 1.f / det;
  const Vec3 tv = sub(o, p0);
  const float u = dot(tv, pv) * inv;
  if (u < -1e-4f || u > 1.0001f) {
    return -1.f;
  }
  const Vec3 qv = cross(tv, e1);
  const float v = dot(d, qv) * inv;
  if (v < -1e-4f || u + v > 1.0001f) {
    return -1.f;
  }
  const float t = dot(e2, qv) * inv;
  return t >= 0.f ? t : -1.f;
}

// ---------------------------------------------------------------------------------------------
// mesh_index parsing — mirrors game/kernel/jak1/kmachine.cpp mb_load_level_index (~:1352):
// header `MESHIDX <ver> <name> <count>`, rows
// `<idx> <system> <tex_id> <shell> <graded> <a_sign_x100> <b_disp_x100> <cx cy cz> <lo> <hi>
//  <material>` — coordinates in METRES. Unparseable rows are skipped, like the runtime.
// ---------------------------------------------------------------------------------------------
struct MeshIndexRow {
  int system = 0;
  int tex_id = 0;
  int shell = 0;
  int graded = 0;
  int a_sign_x100 = -1;
  int b_disp_x100 = -1;
  float cx = 0, cy = 0, cz = 0;
  float lox = 0, loy = 0, loz = 0;
  float hix = 0, hiy = 0, hiz = 0;
  std::string material;
};

bool load_mesh_index(const std::string& path, std::vector<MeshIndexRow>& rows) {
  std::ifstream in(path);
  if (!in) {
    return false;
  }
  std::string header;
  if (!std::getline(in, header)) {
    return false;
  }
  {
    std::istringstream hs(header);
    std::string magic, lname;
    int ver = 0;
    long count = 0;
    hs >> magic >> ver >> lname >> count;
    if (magic != "MESHIDX") {
      return false;
    }
  }
  std::string line;
  while (std::getline(in, line)) {
    if (line.empty()) {
      continue;
    }
    std::istringstream ls(line);
    MeshIndexRow r;
    int idx = 0;
    if (!(ls >> idx >> r.system >> r.tex_id >> r.shell >> r.graded >> r.a_sign_x100 >>
          r.b_disp_x100 >> r.cx >> r.cy >> r.cz >> r.lox >> r.loy >> r.loz >> r.hix >> r.hiy >>
          r.hiz)) {
      continue;
    }
    std::getline(ls, r.material);
    while (!r.material.empty() && (r.material.front() == ' ' || r.material.front() == '\t')) {
      r.material.erase(r.material.begin());
    }
    if (r.material.empty()) {
      r.material = "?";
    }
    rows.push_back(std::move(r));
  }
  return true;
}

// ---------------------------------------------------------------------------------------------
// The full-level sweep. Same fixed iteration order as the runtime:
//   system 0 = TFRAG: lev.tfrag_trees[0], skip INVALID trees, tree.draws in order;
//   system 1 = TIE:   lev.tie_trees[0], tree.static_draws in order (never instanced_wind_draws).
// Per draw: verts = tree.unpacked.vertices, indices = tree.unpacked.indices, first =
// draw.unpacked.idx_of_first_idx_in_full_buffer, count = sum vis_groups[i].num_inds, strip mode
// = tree.use_strips. Draws with tree_tex_id < 0 never participate in a pick (the runtime only
// ever tests draws matched to an index row's tex_id, which is >= 0) — skipped here too.
//
// BROWSABLE filter (manager follow-up, matches the runtime exactly): the mesh_index only holds
// displaceable materials — the runtime skips entirely any draw whose (system, tree_tex_id) has
// no index row for that system. `browsable` is the set of distinct (system, tex_id) pairs from
// the parsed index; non-indexed geometry never wins nor is even a candidate.
//
// TRIANGLE ORDINAL: one counter per (system, texid), incremented on EVERY emitted triangle of a
// draw with that tree_tex_id, across the fixed tree->draw order. The reported `tri` is the
// winning triangle's ordinal within its (system, texid) population.
// ---------------------------------------------------------------------------------------------
constexpr float kMaxDist = 500.f * 4096.f;  // GOAL units

struct BestHit {
  bool valid = false;
  float t = std::numeric_limits<float>::max();
  int system = -1;
  u32 tex = 0;
  u64 tri = 0;  // ordinal within (system, tex)
};

BestHit sweep(const tfrag3::Level& lev,
              const Vec3& o,
              const Vec3& d,
              const std::set<std::pair<int, u32>>& browsable) {
  BestHit best;
  std::map<std::pair<int, u32>, u64> ordinals;

  auto do_draw = [&](int system, const std::vector<tfrag3::PreloadedVertex>& verts,
                     const std::vector<u32>& indices, u32 first, u64 count, bool strips,
                     u32 texid) {
    u64& ord = ordinals[{system, texid}];
    walk_tris(indices, first, count, strips, verts.size(), [&](u32 a, u32 b, u32 c) {
      const u64 my_ord = ord++;
      const auto& v0 = verts[a];
      const auto& v1 = verts[b];
      const auto& v2 = verts[c];
      const float t = ray_tri(o, d, {v0.x, v0.y, v0.z}, {v1.x, v1.y, v1.z}, {v2.x, v2.y, v2.z});
      // global min-t with strict < : first-encountered wins ties.
      if (t >= 0.f && t <= kMaxDist && t < best.t) {
        best.valid = true;
        best.t = t;
        best.system = system;
        best.tex = texid;
        best.tri = my_ord;
      }
    });
  };

  // system 0 = TFRAG
  for (const auto& tree : lev.tfrag_trees[0]) {
    if (tree.kind == tfrag3::TFragmentTreeKind::INVALID) {
      continue;
    }
    const auto& verts = tree.unpacked.vertices;
    for (const auto& draw : tree.draws) {
      if (draw.tree_tex_id < 0 || !browsable.count({0, (u32)draw.tree_tex_id})) {
        continue;
      }
      u64 count = 0;
      for (const auto& g : draw.vis_groups) {
        count += g.num_inds;
      }
      do_draw(0, verts, tree.unpacked.indices, draw.unpacked.idx_of_first_idx_in_full_buffer,
              count, tree.use_strips, (u32)draw.tree_tex_id);
    }
  }
  // system 1 = TIE (static_draws only)
  for (const auto& tree : lev.tie_trees[0]) {
    const auto& verts = tree.unpacked.vertices;
    for (const auto& draw : tree.static_draws) {
      if (draw.tree_tex_id < 0 || !browsable.count({1, (u32)draw.tree_tex_id})) {
        continue;
      }
      u64 count = 0;
      for (const auto& g : draw.vis_groups) {
        count += g.num_inds;
      }
      do_draw(1, verts, tree.unpacked.indices, draw.unpacked.idx_of_first_idx_in_full_buffer,
              count, tree.use_strips, (u32)draw.tree_tex_id);
    }
  }
  return best;
}

// ---------------------------------------------------------------------------------------------
// Row resolution, identical to the runtime convention: hm = hit / 4096 (metres). Candidates =
// rows with system==sys && tex_id==tex AND containment with 0.5 m slack on all axes; pick the
// SMALLEST AABB volume, tie -> lowest row index. If none contain: nearest centroid among the
// system+tex rows. If no such rows at all: unresolved.
// ---------------------------------------------------------------------------------------------
int resolve_row(const std::vector<MeshIndexRow>& rows, int sys, u32 tex, const Vec3& hit_goal) {
  const float hx = hit_goal.x / 4096.f;
  const float hy = hit_goal.y / 4096.f;
  const float hz = hit_goal.z / 4096.f;
  constexpr float kSlack = 0.5f;  // metres

  int best_row = -1;
  float best_vol = std::numeric_limits<float>::max();
  for (int i = 0; i < (int)rows.size(); i++) {
    const auto& r = rows[(size_t)i];
    if (r.system != sys || r.tex_id != (int)tex) {
      continue;
    }
    if (hx < r.lox - kSlack || hx > r.hix + kSlack ||  //
        hy < r.loy - kSlack || hy > r.hiy + kSlack ||  //
        hz < r.loz - kSlack || hz > r.hiz + kSlack) {
      continue;
    }
    const float vol = (r.hix - r.lox) * (r.hiy - r.loy) * (r.hiz - r.loz);
    if (vol < best_vol) {  // strict < : ties keep the lowest row index
      best_vol = vol;
      best_row = i;
    }
  }
  if (best_row >= 0) {
    return best_row;
  }
  // fallback: nearest centroid among system+tex rows
  float best_d2 = std::numeric_limits<float>::max();
  for (int i = 0; i < (int)rows.size(); i++) {
    const auto& r = rows[(size_t)i];
    if (r.system != sys || r.tex_id != (int)tex) {
      continue;
    }
    const float dx = r.cx - hx, dy = r.cy - hy, dz = r.cz - hz;
    const float d2 = dx * dx + dy * dy + dz * dz;
    if (d2 < best_d2) {  // strict < : ties keep the lowest row index
      best_d2 = d2;
      best_row = i;
    }
  }
  return best_row;  // -1 when no row of this (system, tex) exists
}

void usage() {
  fmt::print(
      "Usage: mb_pick_ref --fr3 LEVEL.fr3 --index mesh_index_<level>.txt --rays rays.txt\n"
      "rays.txt: `ox oy oz dx dy dz` per line (GOAL units; dir normalized), '#' skipped.\n");
}

}  // namespace

int main(int argc, char** argv) {
  std::string fr3_path, index_path, rays_path;
  for (int i = 1; i < argc; i++) {
    const std::string a = argv[i];
    auto need_val = [&](const char* flag) -> std::string {
      if (i + 1 >= argc) {
        fmt::print("error: {} needs a value\n", flag);
        std::exit(2);
      }
      return argv[++i];
    };
    if (a == "--fr3") {
      fr3_path = need_val("--fr3");
    } else if (a == "--index") {
      index_path = need_val("--index");
    } else if (a == "--rays") {
      rays_path = need_val("--rays");
    } else {
      fmt::print("error: unknown arg '{}'\n", a);
      usage();
      return 2;
    }
  }
  if (fr3_path.empty() || index_path.empty() || rays_path.empty()) {
    usage();
    return 2;
  }

  // tree.unpack() side paths (meshweld/orient logging) resolve the project dir — same init as
  // tess_sign.
  if (!file_util::setup_project_path({})) {
    fmt::print("error: could not resolve the jak-project directory.\n");
    return 1;
  }

  std::vector<MeshIndexRow> rows;
  if (!load_mesh_index(index_path, rows)) {
    fmt::print("error: could not load index '{}'\n", index_path);
    return 1;
  }

  std::ifstream rin(rays_path);
  if (!rin) {
    fmt::print("error: could not open rays file '{}'\n", rays_path);
    return 1;
  }

  // BROWSABLE set: distinct (system, tex_id) pairs present in the index. The sweep tests only
  // draws in this set — same restriction as the runtime.
  std::set<std::pair<int, u32>> browsable;
  for (const auto& r : rows) {
    if (r.tex_id >= 0) {
      browsable.insert({r.system, (u32)r.tex_id});
    }
  }

  tfrag3::Level lev;
  load_level_fr3(fr3_path, lev);
  fmt::print("# mb_pick_ref level={} index_rows={} browsable_texids={}\n", lev.level_name,
             rows.size(), browsable.size());

  std::string line;
  int ray_i = 0;
  while (std::getline(rin, line)) {
    // skip blanks and comments
    size_t p = line.find_first_not_of(" \t\r");
    if (p == std::string::npos || line[p] == '#') {
      continue;
    }
    std::istringstream ls(line);
    Vec3 o{}, d{};
    if (!(ls >> o.x >> o.y >> o.z >> d.x >> d.y >> d.z)) {
      fmt::print("REF i={} none\n", ray_i);  // unparseable ray still consumes an index
      ray_i++;
      continue;
    }
    const float len = std::sqrt(d.x * d.x + d.y * d.y + d.z * d.z);
    if (len < 1e-12f) {
      fmt::print("REF i={} none\n", ray_i);
      ray_i++;
      continue;
    }
    d.x /= len;
    d.y /= len;
    d.z /= len;

    const BestHit best = sweep(lev, o, d, browsable);
    if (!best.valid) {
      fmt::print("REF i={} none\n", ray_i);
      ray_i++;
      continue;
    }
    const Vec3 hit{o.x + best.t * d.x, o.y + best.t * d.y, o.z + best.t * d.z};
    const int row = resolve_row(rows, best.system, best.tex, hit);
    if (row < 0) {
      // defensive only: a winning texid is browsable, so >=1 row of its (system, tex) exists and
      // nearest-centroid always resolves — this branch should never fire.
      fmt::print("REF i={} unresolved tex={} t={:.9g} tri={} hit={:.9g},{:.9g},{:.9g}\n", ray_i,
                 best.tex, best.t, best.tri, hit.x, hit.y, hit.z);
    } else {
      fmt::print("REF i={} row={} t={:.9g} tex={} tri={} hit={:.9g},{:.9g},{:.9g}\n", ray_i, row,
                 best.t, best.tex, best.tri, hit.x, hit.y, hit.z);
    }
    ray_i++;
  }
  return 0;
}
