#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

// Pure CPU diagnostic; does not infer physical contacts or produce a global verdict.
namespace ao_contact_profile {
enum class Surface : uint8_t { unknown, wall, roof };
constexpr int kMaxBandPixels = 8;
constexpr int kBrightDifference = 4;  // Strictly greater than 4/255, in byte units.

struct Image {
  int width = 0;
  int height = 0;
  // All supplied arrays have at least size elements, in row-major order.
  size_t size = 0;
  const uint8_t* ao = nullptr;  // Larger values are brighter.
  const float* depth = nullptr;  // PS2 reverse-Z: finite (1e-9, 1]; <=1e-9 is sky.
  const Surface* surface = nullptr;
  // Caller qualification of a physical contact, from independent geometry evidence.
  // Nonzero at p qualifies p--(p+right/down). Null means no qualified edges.
  // Screen adjacency alone is NEVER sufficient. Last column/row flags are ignored.
  const uint8_t* qualified_right = nullptr;
  const uint8_t* qualified_down = nullptr;
  // Stable geometry identity, independent of wall/roof class. Zero is unknown.
  // Null preserves contact counts but permits no valid measurements. The caller
  // must distinguish separate surface instances that share the same class.
  const uint64_t* identity = nullptr;
};

struct Result {
  bool input_valid = false;
  bool measured = false;  // At least one side has a valid interior comparison.
  size_t adjacent_wall_roof_edges = 0;
  size_t contacts = 0;  // Qualified adjacent wall/roof edges, including missing depth.
  size_t valid_contacts = 0;  // At least one comparable side.
  size_t missing_contacts = 0;  // Neither side comparable (includes censored profiles).
  size_t valid_sides = 0;
  size_t missing_sides = 0;  // No usable contact/interior sample.
  size_t censored_sides = 0;  // Interior exists, but no AO contrast in bounded window.
  size_t depth_discontinuities = 0;  // Across qualified edge, never an exclusion.
  size_t band_pixels = 0;  // Sum of widths per contact side, NOT unique image pixels.
  int max_width = 0;
};

namespace detail {
inline bool usable_depth(float z) { return std::isfinite(z) && z > 1e-9f && z <= 1.f; }
enum class State { missing, censored, valid };
struct Side {
  State state = State::missing;
  int width = 0;
};

inline Side side(const Image& image, int x, int y, int dx, int dy) {
  const size_t start = size_t(y) * size_t(image.width) + size_t(x);
  if (!usable_depth(image.depth[start]) || !image.identity || !image.identity[start]) return {};
  const Surface surface = image.surface[start];
  const uint64_t identity = image.identity[start];
  std::array<int, kMaxBandPixels + 1> values{};
  int count = 0;
  // Up to eight band pixels AND the following interior reference (offset 8).
  // Stop immediately at image bounds, sky, missing depth, or changed identity.
  for (int step = 0; step <= kMaxBandPixels; ++step) {
    const int64_t px = int64_t(x) + int64_t(dx) * step;
    const int64_t py = int64_t(y) + int64_t(dy) * step;
    if (px < 0 || py < 0 || px >= image.width || py >= image.height) break;
    const size_t p = size_t(py) * size_t(image.width) + size_t(px);
    if (image.surface[p] != surface || image.identity[p] != identity ||
        !usable_depth(image.depth[p])) break;
    values[count++] = image.ao[p];
  }
  if (count < 2) return {};
  // The darkest interior sample is a same-surface reference. A flat profile is
  // censored, not evidence of zero-width band. A darker contact is measurable zero.
  int reference = 1;
  bool contrast = false;
  for (int i = 1; i < count; ++i) {
    if (values[i] < values[reference]) reference = i;
    contrast = contrast || values[i] != values[0];
  }
  if (!contrast) return {State::censored, 0};
  int width = 0;
  while (width < reference && values[width] - values[reference] > kBrightDifference) {
    ++width;
  }
  return {State::valid, width};
}
}  // namespace detail

// depth_jump is the caller's discontinuity tolerance in normalized depth units;
// it must be finite and nonnegative. This does not change the AO band threshold.
// Each side walks away from the edge along its screen normal, independently.
// Widths are contiguous bright pixels from the contact relative to the darkest
// interior sample on THAT side. This bounded statistic does not establish world
// distance, surface continuity beyond caller identities, or artifact causality.
inline Result analyze(const Image& image, float depth_jump) {
  Result result;
  if (image.width <= 0 || image.height <= 0 || !image.ao || !image.depth ||
      !image.surface || !std::isfinite(depth_jump) || depth_jump < 0.f) return result;
  const size_t width = size_t(image.width);
  const size_t height = size_t(image.height);
  if (height > std::numeric_limits<size_t>::max() / width || image.size < width * height)
    return result;
  result.input_valid = true;
  const auto edge = [&](int x, int y, int dx, int dy, const uint8_t* qualified) {
    const size_t p = size_t(y) * width + size_t(x);
    const size_t q = size_t(y + dy) * width + size_t(x + dx);
    const Surface a = image.surface[p], b = image.surface[q];
    if (!((a == Surface::wall && b == Surface::roof) ||
          (a == Surface::roof && b == Surface::wall))) return;
    ++result.adjacent_wall_roof_edges;
    if (!qualified || !qualified[p]) return;
    ++result.contacts;
    if (detail::usable_depth(image.depth[p]) && detail::usable_depth(image.depth[q]) &&
        std::abs(image.depth[p] - image.depth[q]) > depth_jump)
      ++result.depth_discontinuities;
    // Both endpoints must exist to support an edge comparison. In particular,
    // valid samples on one side cannot rescue a sky/NaN endpoint on the other.
    if (!detail::usable_depth(image.depth[p]) || !detail::usable_depth(image.depth[q]) ||
        !image.identity || !image.identity[p] || !image.identity[q]) {
      result.missing_sides += 2;
      ++result.missing_contacts;
      return;
    }
    const std::array<detail::Side, 2> sides = {
        detail::side(image, x, y, -dx, -dy), detail::side(image, x + dx, y + dy, dx, dy)};
    bool valid = false;
    for (const auto& side : sides) {
      if (side.state == detail::State::missing) ++result.missing_sides;
      else if (side.state == detail::State::censored) ++result.censored_sides;
      else {
        valid = true;
        ++result.valid_sides;
        result.band_pixels += size_t(side.width);
        result.max_width = std::max(result.max_width, side.width);
      }
    }
    if (valid) ++result.valid_contacts;
    else ++result.missing_contacts;
  };
  for (int y = 0; y < image.height; ++y) {
    for (int x = 0; x < image.width; ++x) {
      if (x + 1 < image.width) edge(x, y, 1, 0, image.qualified_right);
      if (y + 1 < image.height) edge(x, y, 0, 1, image.qualified_down);
    }
  }
  result.measured = result.valid_sides != 0;
  return result;
}
}  // namespace ao_contact_profile
