#include "goalc/emitter/IGenARM64.h"

#include <cstdio>
#include <cstdlib>
#include <vector>

int main() {
  using namespace emitter;
  using namespace emitter::IGen::ARM64;
  const bool trace = std::getenv("OG_BLR_TARGET_TRACE_EMIT") != nullptr;
  std::vector<uint32_t> expected = {0xA9BF17E3u, 0xA9BF2FEAu, 0xA9BF5FECu};
  const std::vector<uint32_t> trace_words = {
      0xCB0F0191u, 0xD2A0E010u, 0xEB10023Fu, 0x54000043u, 0x00001EECu};
  if (trace) {
    expected.insert(expected.end(), trace_words.begin(), trace_words.end());
  }
  expected.insert(expected.end(), {0xD63F0180u, 0xA8C15FECu, 0xA8C12FEAu, 0xA8C117E3u});
  int defects = 0;
  for (auto emitted : {call_r64(Register(X12))}) {
    auto actual = emitted.extra_words;
    actual.insert(actual.begin(), emitted.encoding);
    defects += actual != expected;
  }
  expected[2] = 0xA9BF7FECu;
  expected[trace ? 9 : 4] = 0xA8C17FECu;
  auto full = call_r64(Register(X12), kCallSavedGprMask);
  auto full_words = full.extra_words;
  full_words.insert(full_words.begin(), full.encoding);
  defects += full_words != expected;
  expected.clear();
  if (trace) {
    expected.insert(expected.end(), trace_words.begin(), trace_words.end());
  }
  expected.push_back(0xD63F0180u);
  auto sparse = call_r64(Register(X12), 0);
  auto actual = sparse.extra_words;
  actual.insert(actual.begin(), sparse.encoding);
  defects += actual != expected;
  std::printf("call_trace=%d checked_sequences=3 encoding_defects=%d minimum_call_instructions=%zu\n",
              trace, defects, actual.size() + 1);
  return defects != 0;
}
