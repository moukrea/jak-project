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
  // The FEATURE line must retain this item's count when another instrument fires.
  autoport_proof::note_hit_for("unrelated-test-instrument", 1000);
  autoport_proof::flush();
  puts("draw_census_test on: restart, degeneracy, instances, passes, reset, bounds passed");
}
