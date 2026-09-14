#include <cassert>
#include <cstdio>
#include <vector>

#include "common/dma/dma_copy.h"

// Standalone regression test: link dma_copy.cpp and the existing libcommon.
// Covers relocated references, cross-chunk payloads and rejection after a good copy.
int main() {
  constexpr u32 chunk = FixedChunkDmaCopier::chunk_size;
  std::vector<u8> memory(16 * chunk);
  auto tag = [&](u32 at, DmaTag::Kind kind, u32 addr, u16 qwc) {
    const u64 value = (u64(addr) << 32) | (u64(kind) << 28) | qwc;
    memcpy(memory.data() + at, &value, sizeof(value));
  };
  const u32 start = 5 * chunk, sub = 9 * chunk, payload = 12 * chunk - 16;
  for (u32 i = 0; i < 64; i++) {
    memory[payload + i] = u8(i * 17);
  }
  tag(start, DmaTag::Kind::CALL, sub, 0);
  tag(sub, DmaTag::Kind::REF, payload, 4);
  tag(sub + 16, DmaTag::Kind::RET, 0, 0);
  tag(start + 16, DmaTag::Kind::NEXT, 7 * chunk, 0);
  tag(7 * chunk, DmaTag::Kind::END, 0, 1);
  memory[7 * chunk + 16] = 0xa5;

  FixedChunkDmaCopier legacy(memory.size()), checked(memory.size());
  const auto& expected = legacy.run(memory.data(), start);
  DmaCopyError error;
  u32 observed = 0;
  assert(checked.try_run(
      memory.data(), start, error,
      [&](const DmaFollower&, const DmaTag&, u32 step) { assert(step == ++observed); }));
  const auto& actual = checked.get_last_result();
  assert(observed == 5 && actual.stats.num_tags == 5);
  assert(actual.stats.num_data_bytes == 80);
  assert(actual.stats.num_copied_bytes == 5 * chunk);
  assert(actual.data == expected.data && actual.start_offset == expected.start_offset);
  assert(flatten_dma(DmaFollower(memory.data(), start)) ==
         flatten_dma(DmaFollower(actual.data.data(), actual.start_offset)));
  const auto saved = actual;
  const auto* saved_ptr = actual.data.data();
  auto unchanged = [&] {
    assert(actual.data.data() == saved_ptr && actual.data == saved.data);
    assert(actual.start_offset == saved.start_offset);
    assert(actual.stats.num_tags == saved.stats.num_tags);
    assert(actual.stats.num_copied_bytes == saved.stats.num_copied_bytes);
    assert(actual.stats.sync_time_ms == saved.stats.sync_time_ms);
  };

  // Partial planning must never destroy the buffer that the GL thread will re-present.
  tag(sub, DmaTag::Kind::NEXT, 16, 0);
  assert(!checked.try_run(memory.data(), start, error));
  assert(error.low_tag && error.steps == 2 && error.tag_offset == sub);
  unchanged();
  tag(sub, DmaTag::Kind::NEXT, sub, 0);
  assert(!checked.try_run(memory.data(), start, error));
  assert(!error.low_tag && !error.out_of_bounds && error.steps == 400000);
  unchanged();
  tag(sub, DmaTag::Kind::REF, memory.size() - 16, 2);
  assert(!checked.try_run(memory.data(), start, error));
  assert(error.out_of_bounds);
  unchanged();
  assert(!checked.try_run(memory.data(), memory.size() - 8, error));
  assert(error.out_of_bounds);
  unchanged();

  tag(sub, DmaTag::Kind::REF, payload, 4);
  assert(checked.try_run(memory.data(), start, error));
  assert(!error.low_tag && !error.out_of_bounds && error.steps == 0);
  assert(actual.data == saved.data);
  std::puts("dma_copy_tests=passed cases=6 tags=5 payload_bytes=80 copied_bytes=655360");
}
