#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <mutex>
#include <optional>
#include <utility>
#include <vector>

// A reconstruction witness, not an exhaustive snapshot. Payloads must already
// have portable byte representations (no native pointers or padding).
namespace refset_state {
struct Receipt {
  uint64_t bootstrap_fp = 0;
  bool replay_verified = false;
  bool actors_sweep = false;
};
struct Sample {
  int64_t lf = -1;
  std::vector<uint8_t> bytes;
};
namespace detail {
inline std::mutex mutex;
inline Receipt receipt;
inline std::array<std::optional<Sample>, 8> samples;
inline size_t next = 0;
// The GOAL producer stages records privately; readers see only completed samples.
inline thread_local std::optional<Sample> pending;
inline thread_local size_t records = 0;
inline void length(std::vector<uint8_t>& out, uint64_t n) {
  for (unsigned i = 0; i < 8; ++i) out.push_back(uint8_t(n >> (i * 8)));
}
}  // namespace detail

inline bool enabled() {
  const char* value = std::getenv("OG_REFSET_QUALIFY_STATE");
  return value && std::strcmp(value, "1") == 0;
}

inline void bootstrap(uint64_t fp, bool verified, const char* boundary) {
  std::lock_guard<std::mutex> lock(detail::mutex);
  detail::receipt = {fp, verified,
                     boundary && std::strcmp(boundary, "actors-sweep-identities-compared") == 0};
  detail::samples = {};
  detail::next = 0;
}

inline Receipt receipt() {
  std::lock_guard<std::mutex> lock(detail::mutex);
  return detail::receipt;
}

inline void begin(int64_t lf) {
  // Magic and explicit little-endian version 1, then records consisting of
  // tag length u64 LE, tag bytes, payload length u64 LE, payload bytes.
  detail::pending = Sample{lf, {'O', 'G', 'S', 'T', 'A', 'T', 'E', 0, 1, 0, 0, 0}};
  detail::records = 0;
}

inline void record(const char* tag, const void* data, size_t size) {
  if (!detail::pending) return;
  if (!tag || (size && !data)) {
    detail::pending.reset();
    return;
  }
  auto& out = detail::pending->bytes;
  const size_t tag_size = std::strlen(tag);
  detail::length(out, tag_size);
  out.insert(out.end(), tag, tag + tag_size);
  detail::length(out, size);
  if (size) {
    const auto* bytes = static_cast<const uint8_t*>(data);
    out.insert(out.end(), bytes, bytes + size);
  }
  ++detail::records;
}

inline void end() {
  if (detail::pending && detail::records) {
    std::lock_guard<std::mutex> lock(detail::mutex);
    detail::samples[detail::next] = std::move(detail::pending);
    detail::next = (detail::next + 1) % detail::samples.size();
  }
  detail::pending.reset();
}

inline std::optional<Sample> snapshot(int64_t lf) {
  std::lock_guard<std::mutex> lock(detail::mutex);
  std::optional<Sample> result;
  // Visit newest insertions first, including when duplicate logic frames occur.
  for (size_t i = 0; i < detail::samples.size(); ++i) {
    const auto& sample = detail::samples[(detail::next + 7 - i) % 8];
    if (sample && !sample->bytes.empty() &&
        (sample->lf == lf ||
         (lf != std::numeric_limits<int64_t>::min() && sample->lf == lf - 1)) &&
        (!result || sample->lf > result->lf)) {
      result = sample;
    }
  }
  return result;
}
}  // namespace refset_state
