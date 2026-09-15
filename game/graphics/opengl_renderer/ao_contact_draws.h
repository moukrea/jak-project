#pragma once

#include <cstdio>
#include <algorithm>
#include <numeric>
#include <array>
#include <set>
#include <vector>
#include "common/custom_data/Tfrag3Data.h"
#include "game/graphics/opengl_renderer/ao_contact_archive.h"
#include "game/graphics/opengl_renderer/ao_static_probe.h"
#include "game/graphics/opengl_renderer/frame_ubo.h"

namespace ao_contact_draws {
inline bool active(const std::string& level) {
  return level == "village1" && ao_contact_archive::requested() &&
         ao_static_probe::logic_frame() == 1400;
}
inline size_t full_count(const std::vector<tfrag3::StripDraw>& draws) {
  size_t count = 0;
  for (const auto& d : draws) {
    size_t end = d.unpacked.idx_of_first_idx_in_full_buffer;
    for (const auto& g : d.vis_groups) end += g.num_inds;
    count = std::max(count, end);
  }
  return count;
}
// Reuse the production compactor with offset identities instead of vertex indices.
// Its returned draw ranges must equal production; otherwise no provenance is accepted.
template <typename Compact>
inline void compact(std::vector<u32>& out, size_t count,
                    const std::vector<std::pair<int, int>>& expected, size_t used,
                    Compact run) {
  std::vector<u32> source(count);
  std::iota(source.begin(), source.end(), 0u);
  out.resize(count);
  std::vector<std::pair<int, int>> ranges(expected.size());
  const size_t actual = run(ranges.data(), out.data(), source.data());
  if (actual != used || ranges != expected) {
    out.clear();
    autoport_proof::publish("ao_hut_draw_compaction_mismatch", 1);
  } else {
    out.resize(actual);
  }
}
// draws.txt joins each actual submission to its state and to draws-indices.bin.
// Binary payload = interleaved effective vertex index / ORIGINAL full-EBO offset (u32).
// Offsets include primitive restarts and preserve strip parity; no welded-index inference.
// draw_end is exclusive and may include culled draws in a merged submission.
inline void record(const std::string& level, const char* family, const char* pass,
                   uint64_t frame, int geo, size_t tree, size_t draw_begin, size_t draw_end,
                   GLuint vertex_buffer, GLenum mode, size_t first, size_t count,
                   const u32* indices, size_t available, const std::vector<u32>* source = nullptr, uint32_t probe_id = 0) {
  if (!active(level) || count == 0) return;
  static uint64_t sequence = 0, errors = 0, bytes = 0;
  static FILE* manifest = nullptr;
  static FILE* payload = nullptr;
  static bool attempted = false;
  if (!attempted) {
    attempted = true;
    const auto& dir = ao_contact_archive::directory();
    if (!dir.empty()) {
      manifest = std::fopen((dir + "/draws.txt").c_str(), "wx");
      payload = std::fopen((dir + "/draws-indices.bin").c_str(), "wbx");
    }
  }
  if (sequence >= 32768 || count > 8u * 1024u * 1024u ||
      bytes > 256u * 1024u * 1024u || count * 2 * sizeof(u32) > 256u * 1024u * 1024u - bytes) {
    autoport_proof::publish("ao_hut_draw_archive_overflow", 1);
    return;
  }
  bool ok = manifest && payload && indices && first <= available && count <= available - first &&
            (!source || (first <= source->size() && count <= source->size() - first));
  if (!ok) {
    autoport_proof::publish("ao_hut_draw_archive_errors", ++errors);
    return;
  }
  GLint viewport[4]{}, program = 0, ebo = 0, vao = 0, fbo = 0, depth_func = 0;
  GLboolean depth_write = GL_FALSE;
  GLint bound_vertex_buffer = 0;
  glGetIntegerv(GL_VIEWPORT, viewport);
  glGetVertexAttribiv(0, GL_VERTEX_ATTRIB_ARRAY_BUFFER_BINDING, &bound_vertex_buffer);
  ok = GLuint(bound_vertex_buffer) == vertex_buffer && ok;
  glGetIntegerv(GL_CURRENT_PROGRAM, &program);
  glGetIntegerv(GL_ELEMENT_ARRAY_BUFFER_BINDING, &ebo);
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &vao);
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &fbo);
  glGetIntegerv(GL_DEPTH_FUNC, &depth_func);
  glGetBooleanv(GL_DEPTH_WRITEMASK, &depth_write);
  const uint64_t ubo = frame_ubo::contact_bound_hash();
  auto scalar = [&](const char* name, float missing) {
    const GLint loc = glGetUniformLocation(program, name);
    float value = missing;
    if (loc >= 0) glGetUniformfv(program, loc, &value);
    return value;
  };
  const float contact_on = scalar("u_tie_contact_on", 0.f);
  const float sway_amp = scalar("u_tie_sway_amp", 0.f);
  const float pre_etie = scalar("u_pre_etie", -1.f);
  const bool etie = pre_etie >= 0 ? pre_etie != 0 : glGetUniformLocation(program, "cam_no_persp") >= 0;
  const GLint matrix_loc = glGetUniformLocation(program, "pc_camera");
  const GLint trans_loc = glGetUniformLocation(program, "cam_trans");
  uint64_t projection_hash = 0;
  if (matrix_loc >= 0 && trans_loc >= 0) {
    std::array<float, 20> projection{};
    glGetUniformfv(program, matrix_loc, projection.data());
    glGetUniformfv(program, trans_loc, projection.data() + 16);
    projection_hash = ao_contact_archive::hash(projection.data(), sizeof(projection));
    static std::set<uint64_t> archived;
    if (archived.insert(projection_hash).second) {
      const auto path = ao_contact_archive::directory() + "/projection-" + std::to_string(projection_hash) + ".bin";
      ok = ao_contact_archive::write_exclusive(path, projection.data(), sizeof(projection)) && ok;
    }
  }
  std::vector<u32> pairs(count * 2);
  for (size_t i = 0; i < count; ++i) {
    pairs[2 * i] = indices[first + i];
    pairs[2 * i + 1] = source ? (*source)[first + i] : u32(first + i);
  }
  const bool payload_ok = std::fwrite(pairs.data(), sizeof(u32) * 2, count, payload) == count &&
       std::fflush(payload) == 0;
  ok = ok && payload_ok;
  const int wrote = std::fprintf(manifest,
      "seq=%llu family=%s pass=%s level=%s render_frame=%llu geo=%d tree=%zu draw_begin=%zu "
      "draw_end=%zu first=%zu count=%zu mode=%u vbo=%u ebo=%d vao=%d program=%d fbo=%d "
      "viewport=%d,%d,%d,%d depth_func=%d depth_write=%u ubo_hash=%llu payload_offset=%llu "
      "payload_hash=%llu payload_ok=%u contact_on=%.9g sway_amp=%.9g pre_etie=%.9g "
      "projection_kind=%s projection_hash=%llu probe_id=%u\n",
      (unsigned long long)sequence++, family, pass, level.c_str(), (unsigned long long)frame,
      geo, tree, draw_begin, draw_end, first, count, mode, vertex_buffer, ebo, vao, program, fbo,
      viewport[0], viewport[1], viewport[2], viewport[3], depth_func, unsigned(depth_write),
      (unsigned long long)ubo, (unsigned long long)bytes,
      (unsigned long long)ao_contact_archive::hash(pairs.data(), pairs.size() * sizeof(u32)), unsigned(ok),
      double(contact_on), double(sway_amp), double(pre_etie), etie ? "etie" : "pc_camera",
      (unsigned long long)projection_hash, probe_id);
  ok = wrote > 0 && std::fflush(manifest) == 0 && ok;
  bytes += pairs.size() * sizeof(u32);
  errors += !ok || (!ubo && !projection_hash);
  autoport_proof::publish("ao_hut_draw_archive_errors", errors);
  autoport_proof::publish("ao_hut_draw_archive_count", sequence);
}
}  // namespace ao_contact_draws
