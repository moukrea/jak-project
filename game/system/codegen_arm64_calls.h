#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>

namespace codegen_arm64 {
struct CallStats {
  uint32_t calls = 0;
  uint32_t max_instructions = 0;
  uint32_t reduced_calls = 0;
  bool complete = false;
};

// Inspect a normal GOAL function through its return. Unknown call sequences
// fail closed, including emit-time tracing; they cannot certify the two-word target.
inline CallStats inspect_calls(const uint32_t* words, size_t count) {
  CallStats result;
  for (size_t i = 0; i < count; ++i) {
    if (words[i] == 0xd65f03c0u) {
      result.complete = result.calls != 0;
      return result;
    }
    if ((words[i] & 0xfffffc1fu) != 0xd63f0000u) {
      continue;
    }
    const auto reg = (words[i] >> 5) & 31u;
    size_t begin = i;
    while (begin && (words[begin - 1] & 0xffff83e0u) == 0xa9bf03e0u) {
      --begin;
    }
    const size_t pairs = i - begin;
    if (!begin || words[begin - 1] != (0x8b0f0000u | (reg << 5) | reg) ||
        pairs > 3 || i + pairs >= count) {
      return result;
    }
    for (size_t p = 0; p < pairs; ++p) {
      if (words[i + 1 + p] != (0xa8c10000u | (words[i - 1 - p] & 0x7fffu))) {
        return result;
      }
    }
    const uint32_t instructions = 2 + 2 * pairs;
    ++result.calls;
    result.reduced_calls += instructions < 8;
    result.max_instructions = std::max(result.max_instructions, instructions);
  }
  return result;
}
}  // namespace codegen_arm64
