#include "soft_draw_census.h"

#include <array>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <string>

#include "game/system/autoport_proof.h"

#include "third-party/glad/include/glad/glad.h"

namespace soft_draw_census {
namespace {
struct Counts {
  const char* name;
  uint64_t draws = 0, vertices = 0, triangles = 0, missing = 0;
};
std::array<Counts, 19> counts{{{"tfrag"},
                               {"tie"},
                               {"shrub"},
                               {"merc"},
                               {"generic"},
                               {"grass"},
                               {"ocean"},
                               {"debug"},
                               {"instrument"},
                               {"sprite"},
                               {"glow"},
                               {"shadow"},
                               {"direct"},
                               {"sky"},
                               {"eyes"},
                               {"texture_animator"},
                               {"ocean_texture"},
                               {"postprocess"},
                               {"hfrag"}}};
Summary totals;
uint64_t count_cpu_ns = 0;
using Clock = std::chrono::steady_clock;
struct CountTimer {
  Clock::time_point start = Clock::now();
  ~CountTimer() {
    count_cpu_ns +=
        std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now() - start).count();
  }
};
Counts& get(const char* name) {
  for (auto& c : counts)
    if (!std::strcmp(c.name, name))
      return c;
  return counts.back();
}
}  // namespace
bool active() {
  static const bool on =
      autoport_proof::feature_is("soft-baseline") && autoport_proof::armed_for("soft-baseline");
  return on;
}
void missing(const char* system, size_t count) {
  if (!active() || !count)
    return;
  ++get(system).missing;
  ++totals.coverage_gaps;
}
void record(const char* system,
            const uint32_t* indices,
            size_t available,
            size_t first,
            size_t count,
            unsigned topology,
            uint64_t instances) {
  if (!active() || !count || !instances)
    return;
  CountTimer timer;
  auto& c = get(system);
  ++c.draws;
  if (!indices || first > available || count > available - first ||
      (topology != GL_TRIANGLES && topology != GL_TRIANGLE_STRIP && topology != GL_POINTS)) {
    missing(system, count);
    return;
  }
  uint64_t vertices = 0, triangles = 0;
  const uint32_t* submitted = indices + first;
  if (topology == GL_TRIANGLE_STRIP) {
    for (size_t i = 0; i < count; ++i)
      vertices += submitted[i] != UINT32_MAX;
    // Every strip triangle is a consecutive window; a restart invalidates
    // every window crossing it without carrying assembly state between iterations.
    for (size_t i = 2; i < count; ++i) {
      const uint32_t a = submitted[i - 2], b = submitted[i - 1], c = submitted[i];
      triangles += (a != UINT32_MAX) & (b != UINT32_MAX) & (c != UINT32_MAX) &
                   (a != b) & (a != c) & (b != c);
    }
  } else if (topology == GL_TRIANGLES) {
    size_t i = 0;
    while (count - i >= 3) {
      const uint32_t a = submitted[i], b = submitted[i + 1], c = submitted[i + 2];
      // Resume assembly immediately after the first restart in this group.
      if (a == UINT32_MAX) {
        ++i;
      } else if (b == UINT32_MAX) {
        ++vertices;
        i += 2;
      } else {
        vertices += 2 + (c != UINT32_MAX);
        triangles += (c != UINT32_MAX) & (a != b) & (a != c) & (b != c);
        i += 3;
      }
    }
    for (; i < count; ++i)
      vertices += submitted[i] != UINT32_MAX;
  } else {
    for (size_t i = 0; i < count; ++i)
      vertices += submitted[i] != UINT32_MAX;
  }
  c.vertices += vertices * instances;
  c.triangles += triangles * instances;
}
void record_arrays(const char* system, size_t count, unsigned topology, uint64_t instances) {
  if (!active() || !count || !instances)
    return;
  CountTimer timer;
  auto& c = get(system);
  ++c.draws;
  c.vertices += count * instances;
  if (topology == GL_TRIANGLES)
    c.triangles += count / 3 * instances;
  else if (topology == GL_TRIANGLE_STRIP || topology == GL_TRIANGLE_FAN)
    c.triangles += (count > 2 ? count - 2 : 0) * instances;
  else if (topology != GL_POINTS)
    missing(system, count);
}
void frame_end(uint64_t frame) {
  if (!active())
    return;
  const auto publish_start = Clock::now();
  ++totals.frames;
  // frame_tick() can flush from the GOAL thread between two scalar publications.
  // This single value carries a complete render-frame snapshot under one lock.
  std::string snapshot = std::to_string(frame ? frame : totals.frames);
  snapshot.reserve(2048);
  bool world = false;
  for (size_t i = 0; i < counts.size(); ++i) {
    auto& c = counts[i];
    if (i < 7 && c.triangles)
      world = true;
    char row[160];
    std::snprintf(row, sizeof(row), ";%s:%llu,%llu,%llu,%llu", c.name, (unsigned long long)c.draws,
                  (unsigned long long)c.vertices, (unsigned long long)c.triangles,
                  (unsigned long long)c.missing);
    snapshot += row;
    char key[112];
    auto emit = [&](const char* suffix, uint64_t value) {
      std::snprintf(key, sizeof(key), "soft_draw_%s_%s", c.name, suffix);
      autoport_proof::publish(key, value);
    };
    emit("draws", c.draws);
    emit("vertices_submitted", c.vertices);
    emit("triangles_submitted", c.triangles);
    emit("unmeasured_draws", c.missing);
    if (c.draws)
      totals.measurements += 3;
    c.draws = c.vertices = c.triangles = c.missing = 0;
  }
  if (world)
    ++totals.world_frames;
  autoport_proof::publish_text("soft_draw_frame_snapshot", snapshot.c_str());
  autoport_proof::publish_text("soft_draw_snapshot_schema",
                               "frame;system:draws,vertex_references,triangles,unmeasured_draws");
  autoport_proof::publish("soft_draw_count_cpu_ns_frame", count_cpu_ns);
  count_cpu_ns = 0;
  autoport_proof::publish("soft_draw_frame", frame ? frame : totals.frames);
  autoport_proof::publish("soft_draw_gaps", totals.coverage_gaps + (totals.world_frames == 0));
  autoport_proof::note_hit_for("soft-baseline", 3 * counts.size() + 1);
  autoport_proof::publish("soft_draw_world_frames", totals.world_frames);
  autoport_proof::publish("soft_draw_coverage_gaps", totals.coverage_gaps);
  autoport_proof::publish_text("soft_draw_vertex_definition",
                               "submitted_references_excluding_restart_not_unique");
  autoport_proof::publish_text("soft_draw_triangle_definition",
                               "distinct_indices_not_postshader_area_multipasses_included");
  autoport_proof::publish_text(
      "soft_draw_scope",
      "tfrag_tie_shrub_merc_generic_grass_ocean_sprite_glow_shadow_direct_sky_eyes_texture_"
      "animator_ocean_texture_postprocess_debug_instrument");
  autoport_proof::publish_text("soft_draw_uncovered_systems",
                               "hfrag_counts_missing_at_draw_Jak3_only");
  autoport_proof::publish(
      "soft_draw_publish_cpu_ns_frame",
      std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now() - publish_start).count());
}
Summary summary() {
  return totals;
}
}  // namespace soft_draw_census
