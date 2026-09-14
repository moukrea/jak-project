#pragma once

#include <cstddef>
#include <cstdlib>
#include <cstdint>
#include <string>
#include <type_traits>
#include <vector>

// Exogenous input tape only. Native integrators, geometry and GPU outputs must never
// be passed here. Pre-anchor events are retained, not silently discarded/reset.
namespace shrub_proof_inputs {
bool enabled();
[[noreturn]] void invalid_input(const char* reason);
void exchange(const char* channel, void* data, size_t bytes);
// Stable source key, independent of render count. Record duplicates must be byte-identical;
// replay reuses the same input. Native state/integrators remain owned by the caller.
void exchange_key(const char* channel, uint64_t key, void* data, size_t bytes);
template <typename T> T value(const char* channel, T input) {
  static_assert(std::is_trivially_copyable<T>::value, "input must be bytes");
  exchange(channel, &input, sizeof(input));
  return input;
}
template <typename T> void vector(const char* channel, std::vector<T>& input) {
  static_assert(std::is_trivially_copyable<T>::value, "input must be bytes");
  if (!enabled()) return;
  uint64_t count = value((std::string(channel) + "/count").c_str(), uint64_t(input.size()));
  // Corrupt tapes must never cause an unbounded allocation.
  if (count > 1048576) invalid_input("vector count exceeds limit");
  input.resize(count);
  exchange(channel, input.data(), input.size() * sizeof(T));
}
}  // namespace shrub_proof_inputs
