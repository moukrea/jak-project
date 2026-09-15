// CPU-only regression tests of real census/publication code; never writes proof.txt.
#include <cassert>
#include <cstdint>
#include <cstdio>

#include "game/graphics/opengl_renderer/soft_draw_census.h"
#include "game/system/autoport_proof.h"
#include "third-party/glad/include/glad/glad.h"

uint64_t value(const char* key) {
  uint64_t result = UINT64_MAX;
  assert(autoport_proof::read_uint(key, result));
  return result;
}

struct ReferenceCounts {
  uint64_t draws = 0, vertices = 0, triangles = 0;
};

// Scalar primitive assembly, independent of the production window/group scans.
ReferenceCounts reference(const uint32_t* indices, size_t first, size_t count,
                          unsigned topology, uint64_t instances) {
  ReferenceCounts result;
  if (!count || !instances)
    return result;
  result.draws = 1;
  uint32_t primitive[3] = {};
  size_t filled = 0;
  for (size_t i = first; i < first + count; ++i) {
    if (indices[i] == UINT32_MAX) {
      filled = 0;
      continue;
    }
    ++result.vertices;
    if (topology == GL_POINTS)
      continue;
    primitive[filled++] = indices[i];
    if (filled == 3) {
      if (primitive[0] != primitive[1] && primitive[1] != primitive[2] &&
          primitive[0] != primitive[2])
        ++result.triangles;
      if (topology == GL_TRIANGLES) {
        filled = 0;
      } else {
        primitive[0] = primitive[1];
        primitive[1] = primitive[2];
        filled = 2;
      }
    }
  }
  result.vertices *= instances;
  result.triangles *= instances;
  return result;
}

void exhaustive_small_streams() {
  constexpr uint32_t alphabet[] = {0, 1, 2, UINT32_MAX};
  constexpr unsigned topologies[] = {GL_TRIANGLES, GL_TRIANGLE_STRIP, GL_POINTS};
  constexpr uint64_t instance_counts[] = {0, 1, 3};
  uint32_t stream[7] = {};
  size_t stream_count = 1;
  uint64_t cases = 0;
  for (size_t length = 0; length <= 7; ++length, stream_count *= 4) {
    for (unsigned topology : topologies) {
      ReferenceCounts expected;
      for (size_t encoding = 0; encoding < stream_count; ++encoding) {
        size_t digits = encoding;
        for (size_t i = 0; i < length; ++i, digits /= 4)
          stream[i] = alphabet[digits % 4];
        for (size_t first = 0; first <= length; ++first) {
          for (size_t count = 0; count <= length - first; ++count) {
            for (uint64_t instances : instance_counts) {
              const auto sample = reference(stream, first, count, topology, instances);
              expected.draws += sample.draws;
              expected.vertices += sample.vertices;
              expected.triangles += sample.triangles;
              soft_draw_census::record("tfrag", stream, length, first, count, topology, instances);
              ++cases;
            }
          }
        }
      }
      // Publish once per length/topology, not once per exhaustive case.
      soft_draw_census::frame_end(0);
      assert(value("soft_draw_tfrag_draws") == expected.draws);
      assert(value("soft_draw_tfrag_vertices_submitted") == expected.vertices);
      assert(value("soft_draw_tfrag_triangles_submitted") == expected.triangles);
      assert(value("soft_draw_tfrag_unmeasured_draws") == 0);
    }
  }
  std::printf("draw_census_test exhaustive: %llu cases, lengths 0..7, all subranges, "
              "3 topologies, instances 0/1/3 passed\n", (unsigned long long)cases);
}

int main() {
  const uint32_t strip[] = {0, 1, 2, 2, 3, UINT32_MAX, 4, 5, 6, 7};
  soft_draw_census::record("tfrag", strip, 10, 0, 10, GL_TRIANGLE_STRIP, 2);
  soft_draw_census::frame_end(0);
  if (!autoport_proof::armed_for("soft-baseline")) {
    assert(soft_draw_census::summary().frames == 0);
    assert(!autoport_proof::has_key("soft_draw_frame"));
    autoport_proof::flush();
    puts("draw_census_test off: no counters or frame publications");
    return 0;
  }
  assert(value("soft_draw_tfrag_vertices_submitted") == 18);
  assert(value("soft_draw_tfrag_triangles_submitted") == 6);
  assert(value("soft_draw_tfrag_draws") == 1);
  assert(value("soft_draw_frame") == 1);
  assert(autoport_proof::has_key("soft_draw_frame_snapshot"));
  assert(value("soft_draw_gaps") == 0);
  // Two actual passes contribute twice; restart and repeated indices do not
  // manufacture triangles. Data before/after the submitted range is ignored.
  const uint32_t triangles[] = {999, 0, 1, 2, 2, 2, 3, 999};
  for (int pass = 0; pass < 2; ++pass)
    soft_draw_census::record("tie", triangles, 8, 1, 6, GL_TRIANGLES);
  soft_draw_census::frame_end(0);
  assert(value("soft_draw_tfrag_vertices_submitted") == 0);
  assert(value("soft_draw_tie_vertices_submitted") == 12);
  assert(value("soft_draw_tie_triangles_submitted") == 2);
  assert(value("soft_draw_tie_draws") == 2);
  assert(value("soft_draw_frame") == 2);
  // Invalid range fails closed, with no out-of-bounds read or silent green.
  soft_draw_census::record("tie", triangles, 8, 7, 2, GL_TRIANGLES);
  soft_draw_census::frame_end(0);
  assert(value("soft_draw_gaps") > 0);
  assert(value("soft_draw_tie_unmeasured_draws") == 1);
  exhaustive_small_streams();
  // The FEATURE line must retain this item's count when another instrument fires.
  autoport_proof::note_hit_for("unrelated-test-instrument", 1000);
  autoport_proof::flush();
  puts("draw_census_test on: restart, degeneracy, instances, passes, reset, bounds passed");
}
