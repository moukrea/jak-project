#pragma once

#include "Instruction.h"

namespace emitter::arm64 {

// X16 is emitter scratch. Reuse it only across adjacent, verified GOAL accesses.
class Arm64GoalMemoryCache {
 public:
  void reset() { m_address_add = 0; }

  InstructionARM64 reuse(InstructionARM64 instruction, bool writes_address_reg) {
    const auto add = instruction.encoding;
    // ADD X16, Xn, X15 with Xn an allocatable GPR: X0-X15, or X19-X28 since
    // perf-codegen-arm64-regs (never X16/X17 themselves, never X18).
    const u32 rn = (add >> 5) & 31u;
    if (instruction.extra_words.size() != 1 || (add & ~0x3e0u) != 0x8b0f0010u ||
        !(rn < 16u || (rn >= 19u && rn <= 28u)) || !is_access(instruction.extra_words[0])) {
      reset();
      return instruction;
    }
    const bool reusable = m_address_add == add;
    m_address_add = writes_address_reg ? 0 : add;
    if (reusable) {
      return InstructionARM64(instruction.extra_words[0]);
    }
    return instruction;
  }

 private:
  static bool is_access(u32 word) {
    if (((word >> 5) & 31u) != 16u) {
      return false;
    }
    u32 opcode = word & 0xffc00000u;
    if ((word & 0x01000000u) == 0) {
      // Unscaled accesses must have neither writeback nor register offsets.
      if ((word & 0x00200c00u) != 0) {
        return false;
      }
      opcode |= 0x01000000u;
    }
    switch (opcode) {
      case 0x39000000u:  // STRB
      case 0x39400000u:  // LDRB
      case 0x39800000u:  // LDRSB X
      case 0x79000000u:  // STRH
      case 0x79400000u:  // LDRH
      case 0x79800000u:  // LDRSH X
      case 0xb9000000u:  // STR W
      case 0xb9400000u:  // LDR W
      case 0xb9800000u:  // LDRSW X
      case 0xf9000000u:  // STR X
      case 0xf9400000u:  // LDR X
      case 0xbd000000u:  // STR S
      case 0xbd400000u:  // LDR S
      case 0x3d800000u:  // STR Q
      case 0x3dc00000u:  // LDR Q
        return true;
      default:
        return false;
    }
  }

  u32 m_address_add = 0;
};

}  // namespace emitter::arm64
