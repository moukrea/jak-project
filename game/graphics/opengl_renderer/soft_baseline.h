#pragma once

#include <array>
#include <cstdint>

namespace soft_baseline {
struct TileCost {
  int side = 0;
  int iterations = 0;
  double upload_completion_ms = 0;
  double raster_completion_ms = 0;
  bool measured = false;
};
struct TileBenchmark {
  bool attempted = false;
  bool r16_supported = false;
  std::array<TileCost, 2> tiles{};
  // One missing term for each unmeasured size. Never substitutes R16F for R16.
  uint64_t gaps = 2;
};
// Render thread, current context, outside an active GL query/transform feedback operation.
// Runs only once and only for the armed soft-baseline item. Uses private GL objects,
// restores modified bindings/state, publishes raw metrics but no feature hits or overall gate.
// Timings include CPU submission and glFinish completion; they are NOT GPU timer queries.
const TileBenchmark& measure_tiles_once();
}  // namespace soft_baseline
