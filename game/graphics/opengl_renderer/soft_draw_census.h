#pragma once
#include <cstddef>
#include <cstdint>

namespace soft_draw_census {
struct Summary {
  uint64_t frames = 0;
  uint64_t world_frames = 0;
  uint64_t coverage_gaps = 0;
  uint64_t measurements = 0;
};
bool active();
// Counts submitted index references (not unique vertices), excluding UINT32_MAX restart.
// Triangle degeneracy means repeated indices, not post-shader zero area. Multipasses count again.
void record(const char* system,
            const uint32_t* indices,
            size_t available,
            size_t first,
            size_t count,
            unsigned topology,
            uint64_t instances = 1);
void record_arrays(const char* system, size_t count, unsigned topology, uint64_t instances = 1);
void missing(const char* system, size_t count);
void frame_end(uint64_t frame);
Summary summary();
}  // namespace soft_draw_census
