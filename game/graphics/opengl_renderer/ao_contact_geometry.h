#pragma once

#include <cstdio>
#include <cstring>
#include <limits>
#include <set>
#include <string>
#include <unistd.h>

#include "common/custom_data/Tfrag3Data.h"
#include "common/custom_data/FoliageWindLaw.h"
#include "common/util/FileUtil.h"
#include "game/graphics/opengl_renderer/ao_contact_archive.h"
#include "game/graphics/refset_file.h"

// Diagnostic data only. No vertex/index/prototype is changed or kept alive by this export.
// Original index provenance must precede looking up the welded index: the latter can belong
// to a different instance. The pair (export hash, LOD, tree, draw, stream offset) names a
// primitive; prototype names and original matrix-group identities qualify its vertices.
namespace ao_contact_geometry {
struct SourceVertex {
  int32_t matrix = -2;  // -1 is a local wind prototype, not a static world instance.
  uint32_t group = UINT32_MAX, vertex = UINT32_MAX;
};

inline bool provenance(const tfrag3::TieTree& tree, std::vector<SourceVertex>& result) {
  result.clear();
  if (tree.unpacked.vertices.size() > 4u * 1024u * 1024u) return false;
  result.reserve(tree.unpacked.vertices.size());
  const auto& packed = tree.packed_vertices;
  for (size_t gi = 0; gi < packed.matrix_groups.size(); ++gi) {
    const auto& g = packed.matrix_groups[gi];
    if (gi > UINT32_MAX || g.end_vert < g.start_vert ||
        g.end_vert > packed.vertices.size() || g.matrix_idx < -1 ||
        (g.matrix_idx >= 0 && size_t(g.matrix_idx) >= packed.matrices.size()) ||
        size_t(g.end_vert - g.start_vert) > tree.unpacked.vertices.size() - result.size()) {
      result.clear();
      return false;
    }
    for (uint32_t v = g.start_vert; v < g.end_vert; ++v)
      result.push_back({g.matrix_idx, uint32_t(gi), v});
  }
  return result.size() == tree.unpacked.vertices.size();
}

struct Index {
  uint32_t original, effective, group, prototype;
};

inline bool indices(const tfrag3::TieTree& tree, const tfrag3::StripDraw& draw,
                    std::vector<Index>& result) {
  result.clear();
  const size_t base = draw.unpacked.idx_of_first_idx_in_full_buffer;
  if (base > tree.unpacked.indices.size()) return false;
  size_t count = draw.plain_indices.size();
  for (const auto& run : draw.runs) {
    if (size_t(run.vertex0) + run.length > tree.unpacked.vertices.size() ||
        size_t(run.length) + 1 > std::numeric_limits<size_t>::max() - count) return false;
    count += size_t(run.length) + 1;
  }
  if (count > tree.unpacked.indices.size() - base || count > 8u * 1024u * 1024u) return false;
  result.reserve(count);
  auto append = [&](uint32_t original) {
    const uint32_t effective = tree.unpacked.indices[base + result.size()];
    if ((original == UINT32_MAX) != (effective == UINT32_MAX) ||
        (original != UINT32_MAX &&
         (original >= tree.unpacked.vertices.size() || effective >= tree.unpacked.vertices.size())))
      return false;
    result.push_back({original, effective, UINT32_MAX, UINT32_MAX});
    return true;
  };
  for (const auto& run : draw.runs) {
    for (uint32_t i = 0; i < run.length; ++i)
      if (!append(run.vertex0 + i)) return false;
    if (!append(UINT32_MAX)) return false;
  }
  for (uint32_t i : draw.plain_indices) if (!append(i)) return false;
  size_t offset = 0;
  for (size_t gi = 0; gi < draw.vis_groups.size(); ++gi) {
    const auto& g = draw.vis_groups[gi];
    if (gi > UINT32_MAX || g.num_inds > result.size() - offset ||
        g.tie_proto_idx >= tree.proto_names.size()) return false;
    const size_t end = offset + g.num_inds;
    if (tree.use_strips) {
      if (end < result.size() && end > 0 && result[end - 1].original != UINT32_MAX)
        return false;
    } else if (g.num_inds % 3 != 0) return false;
    for (size_t i = offset; i < offset + g.num_inds; ++i) {
      result[i].group = uint32_t(gi);
      result[i].prototype = g.tie_proto_idx;
    }
    offset += g.num_inds;
  }
  return offset == result.size();
}

// Native little-endian scalar stream on both supported proof architectures, no struct padding.
// Header: 8-byte AOHUTG01, u32 endian tag 0x01020304, u32 geo, u32 tree, u32 strips,
// u64 vertex count, u64 draw count, u64 proto count, u32 sway stride, then level string.
// Then u32 category-boundary count and u32 draw boundaries, followed by prototypes.
// Strings = u64 bytes + UTF-8. No claim of a source FR3 fingerprint is made.
// Protos then vertices: xyzst(f32*5), packed normal(u32), original matrix(i32),
// group/source vertex(u32*2), SwayRecord(u8*stride). Draws: mode(u32), texture(i32),
// u64 index count, then original/effective/visgroup/prototype(u32*4) per stream entry.
// Restart is UINT32_MAX. Primitive identity is stream offset, respecting strip parity.
// This contains loaded geometry, NOT a claim of visibility, physical contact or alpha survival.
inline void archive_impl(const tfrag3::Level& level, int geo, size_t tree_index) {
  if (!ao_contact_archive::requested() ||
      level.level_name != "village1") return;
  static std::set<std::pair<int, size_t>> attempted;
  const std::string prefix = "ao_hut_geometry_" + std::to_string(geo) + "_" + std::to_string(tree_index);
  if (!attempted.emplace(geo, tree_index).second) {
    // A second load cannot silently reuse identities from the first one.
    autoport_proof::publish((prefix + "_reload_untracked").c_str(), 1);
    return;
  }
  const auto& tree = level.tie_trees.at(geo).at(tree_index);
  std::vector<SourceVertex> sources;
  bool ok = !tree.unpacked.vertices.empty() && provenance(tree, sources) &&
            tree.unpacked.sway.size() == tree.unpacked.vertices.size() * foliage_law::kSwayRecordBytes;
  std::vector<Index> stream;
  for (const auto& draw : tree.static_draws) ok = indices(tree, draw, stream) && ok;
  autoport_proof::publish((prefix + "_provenance_valid").c_str(), ok);
  if (!ok) return;
  const auto& directory = ao_contact_archive::directory();
  if (directory.empty()) { autoport_proof::publish((prefix + "_io_error").c_str(), 1); return; }
  const std::string path = directory + "/geometry-" + std::to_string(geo) + "-" +
                           std::to_string(tree_index) + ".bin";
  FILE* f = std::fopen(path.c_str(), "wbx");
  if (!f) { autoport_proof::publish((prefix + "_io_error").c_str(), 1); return; }
  auto write = [&](const void* p, size_t n) { if (ok && n) ok = std::fwrite(p, 1, n, f) == n; };
  auto u32 = [&](uint32_t v) { write(&v, sizeof(v)); };
  auto u64 = [&](uint64_t v) { write(&v, sizeof(v)); };
  write("AOHUTG01", 8); u32(0x01020304); u32(geo); u32(tree_index); u32(tree.use_strips);
  u64(tree.unpacked.vertices.size()); u64(tree.static_draws.size()); u64(tree.proto_names.size());
  u32(foliage_law::kSwayRecordBytes); u64(level.level_name.size());
  write(level.level_name.data(), level.level_name.size());
  u32(tree.category_draw_indices.size());
  for (uint32_t boundary : tree.category_draw_indices) u32(boundary);
  for (const auto& name : tree.proto_names) { u64(name.size()); write(name.data(), name.size()); }
  for (size_t i = 0; i < tree.unpacked.vertices.size(); ++i) {
    const auto& v = tree.unpacked.vertices[i];
    const float coords[] = {v.x, v.y, v.z, v.s, v.t};
    write(coords, sizeof(coords)); u32(v.nor); u32(uint32_t(sources[i].matrix));
    u32(sources[i].group); u32(sources[i].vertex);
    write(&tree.unpacked.sway[i * foliage_law::kSwayRecordBytes], foliage_law::kSwayRecordBytes);
  }
  std::string draw_offsets;
  size_t draw_number = 0;
  for (const auto& draw : tree.static_draws) {
    size_t count = 0;
    for (const auto& group : draw.vis_groups) count += group.num_inds;
    draw_offsets += "geo=" + std::to_string(geo) + " tree=" + std::to_string(tree_index) +
        " draw=" + std::to_string(draw_number++) + " first=" +
        std::to_string(draw.unpacked.idx_of_first_idx_in_full_buffer) + " count=" +
        std::to_string(count) + "\n";
  }
  ok = ao_contact_archive::write_exclusive(directory + "/tie-draw-offsets-" +
      std::to_string(geo) + "-" + std::to_string(tree_index) + ".txt",
      draw_offsets.data(), draw_offsets.size()) && ok;
  for (const auto& draw : tree.static_draws) {
    if (!indices(tree, draw, stream)) { ok = false; break; }
    u32(draw.mode.as_int()); u32(uint32_t(draw.tree_tex_id)); u64(stream.size());
    for (const auto& idx : stream) {
      u32(idx.original); u32(idx.effective); u32(idx.group); u32(idx.prototype);
    }
  }
  if (std::fflush(f) != 0 || std::ferror(f)) ok = false;
  if (std::fclose(f) != 0) ok = false;
  if (!ok) std::remove(path.c_str());
  const auto hash = ok ? refset_file::hash_file(path) : 0;
  autoport_proof::publish((prefix + "_io_error").c_str(), !hash);
  autoport_proof::publish((prefix + "_hash").c_str(), hash);
  if (hash) autoport_proof::publish_text((prefix + "_path").c_str(), path.c_str());
}
inline void archive(const tfrag3::Level& level, int geo, size_t tree_index) {
  try {
    archive_impl(level, geo, tree_index);
  } catch (const std::exception&) {
    autoport_proof::publish("ao_hut_geometry_exception", 1);
  }
}

// TFRAG: AOHUTF01, endian/geo/source-tree/kind/strips(u32), vertex/draw counts(u64),
// level string. Vertices xyzst(f32*5), normal(u32). Draws mode(u32), texture(i32),
// full-EBO first/count(u64), then effective vertex indices(u32). No transform/sway.
inline void archive_tfrag_impl(const tfrag3::Level& level, int geo, size_t tree_index) {
  if (!ao_contact_archive::requested() || level.level_name != "village1") return;
  const std::string prefix = "ao_hut_tfrag_geometry_" + std::to_string(geo) + "_" + std::to_string(tree_index);
  static std::set<std::pair<int, size_t>> attempted;
  if (!attempted.emplace(geo, tree_index).second) {
    autoport_proof::publish((prefix + "_reload_untracked").c_str(), 1);
    return;
  }
  const auto& tree = level.tfrag_trees.at(geo).at(tree_index);
  bool ok = !tree.unpacked.vertices.empty() && tree.unpacked.vertices.size() <= 4u * 1024u * 1024u;
  for (const auto& draw : tree.draws) {
    size_t count = 0;
    for (const auto& group : draw.vis_groups) count += group.num_inds;
    const size_t first = draw.unpacked.idx_of_first_idx_in_full_buffer;
    ok = ok && first <= tree.unpacked.indices.size() && count <= tree.unpacked.indices.size() - first &&
         count <= 8u * 1024u * 1024u;
  }
  autoport_proof::publish((prefix + "_provenance_valid").c_str(), ok);
  if (!ok) return;
  const auto& directory = ao_contact_archive::directory();
  const auto path = directory + "/geometry-tfrag-" + std::to_string(geo) + "-" + std::to_string(tree_index) + ".bin";
  FILE* f = directory.empty() ? nullptr : std::fopen(path.c_str(), "wbx");
  if (!f) { autoport_proof::publish((prefix + "_io_error").c_str(), 1); return; }
  auto write = [&](const void* p, size_t n) { if (ok && n) ok = std::fwrite(p, 1, n, f) == n; };
  auto u32 = [&](uint32_t v) { write(&v, sizeof(v)); };
  auto u64 = [&](uint64_t v) { write(&v, sizeof(v)); };
  write("AOHUTF01", 8); u32(0x01020304); u32(geo); u32(tree_index); u32(uint32_t(tree.kind)); u32(tree.use_strips);
  u64(tree.unpacked.vertices.size()); u64(tree.draws.size());
  u64(level.level_name.size()); write(level.level_name.data(), level.level_name.size());
  for (const auto& v : tree.unpacked.vertices) {
    const float coords[] = {v.x, v.y, v.z, v.s, v.t};
    write(coords, sizeof(coords)); u32(v.nor);
  }
  for (const auto& draw : tree.draws) {
    size_t count = 0;
    for (const auto& group : draw.vis_groups) count += group.num_inds;
    const size_t first = draw.unpacked.idx_of_first_idx_in_full_buffer;
    u32(draw.mode.as_int()); u32(uint32_t(draw.tree_tex_id)); u64(first); u64(count);
    for (size_t i = first; i < first + count; ++i) {
      const auto index = tree.unpacked.indices[i];
      if (index != UINT32_MAX && index >= tree.unpacked.vertices.size()) ok = false;
      u32(index);
    }
  }
  if (std::fflush(f) != 0 || std::ferror(f)) ok = false;
  if (std::fclose(f) != 0) ok = false;
  if (!ok) std::remove(path.c_str());
  const auto hash = ok ? refset_file::hash_file(path) : 0;
  autoport_proof::publish((prefix + "_io_error").c_str(), !hash);
  autoport_proof::publish((prefix + "_hash").c_str(), hash);
  if (hash) autoport_proof::publish_text((prefix + "_path").c_str(), path.c_str());
}
inline void archive_tfrag(const tfrag3::Level& level, int geo, size_t tree_index) {
  try { archive_tfrag_impl(level, geo, tree_index); }
  catch (const std::exception&) { autoport_proof::publish("ao_hut_tfrag_geometry_exception", 1); }
}
}  // namespace ao_contact_geometry
