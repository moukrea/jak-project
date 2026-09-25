// perf-codegen-arm64-regs — host counter.
//
// Reads, on stdin, one line of lowercase hex per function (each function's arm64
// machine code, little-endian 32-bit words, no separators). Decodes every line
// with the SAME header the engine scans on the device
// (game/system/codegen_arm64_regs.h), sums the hits across every line, and
// prints one summary. verify.py feeds this the MAIN-segment functions of the
// matched objects that belong to ENGINE.CGO/GAME.CGO, so its output is what a
// host build of the same matcher would find in the exact bytes the device is
// running — the census hook compares it against what the device scan itself
// reports.
#include <cstdint>
#include <cstdio>
#include <iostream>
#include <string>
#include <vector>

#include "game/system/codegen_arm64_regs.h"

namespace {
int hexval(char c) {
  if (c >= '0' && c <= '9') {
    return c - '0';
  }
  if (c >= 'a' && c <= 'f') {
    return c - 'a' + 10;
  }
  if (c >= 'A' && c <= 'F') {
    return c - 'A' + 10;
  }
  return -1;
}
}  // namespace

int main() {
  uint64_t gpr_new = 0, v_new = 0, x18 = 0;
  std::string line;
  while (std::getline(std::cin, line)) {
    std::vector<uint8_t> bytes;
    int hi = -1;
    for (char c : line) {
      int v = hexval(c);
      if (v < 0) {
        continue;
      }
      if (hi < 0) {
        hi = v;
      } else {
        bytes.push_back(static_cast<uint8_t>((hi << 4) | v));
        hi = -1;
      }
    }
    if (bytes.empty()) {
      continue;
    }
    std::vector<uint32_t> words(bytes.size() / 4);
    for (size_t i = 0; i < words.size(); ++i) {
      words[i] = static_cast<uint32_t>(bytes[i * 4]) |
                 (static_cast<uint32_t>(bytes[i * 4 + 1]) << 8) |
                 (static_cast<uint32_t>(bytes[i * 4 + 2]) << 16) |
                 (static_cast<uint32_t>(bytes[i * 4 + 3]) << 24);
    }
    const auto stats = codegen_arm64::inspect_regs(words.data(), words.size());
    gpr_new += stats.gpr_new;
    v_new += stats.v_new;
    x18 += stats.x18;
  }
  std::printf("gpr_new=%llu v_new=%llu x18=%llu\n", (unsigned long long)gpr_new,
              (unsigned long long)v_new, (unsigned long long)x18);
  return 0;
}
