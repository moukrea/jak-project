#pragma once

#include <cstddef>
#include <cstdint>

// perf-codegen-arm64-regs — recognise, in LINKED GOAL code, references to the arm64
// hardware registers X19-X28 and V3-V15. Before this item goalc never opened those
// registers as temporaries, so ANY hit on the device proves the new CGO — built by
// the goalc change this item's other half makes — is the one that is actually
// linked. The engine scans the global heap (where ENGINE and GAME code live) once
// the game has run 600 frames; the same matcher is run by
// .autoport/tests/codegen_regs on the goalc-emitted code, so it cannot drift.
namespace codegen_arm64 {
struct RegsStats {
  uint64_t gpr_new = 0;  // hit on a new GPR (x19..x28) in a counted pattern
  uint64_t v_new = 0;    // hit on a new V register (v3..v15) in a counted pattern
  uint64_t x18 = 0;      // hit on x18/w18 (platform register, never usable)
};

namespace regs_detail {
inline bool in_gpr_new(uint32_t r) {
  return r >= 19 && r <= 28;
}
inline bool in_v_new(uint32_t r) {
  return r >= 3 && r <= 15;
}
}  // namespace regs_detail

inline RegsStats inspect_regs(const uint32_t* w, size_t n) {
  using namespace regs_detail;
  RegsStats s;
  for (size_t i = 0; i < n; ++i) {
    const uint32_t a = w[i];
    const uint32_t d = a & 31u;
    const uint32_t rn = (a >> 5) & 31u;
    const uint32_t rm = (a >> 16) & 31u;
    const uint32_t t = a & 31u;

    auto tally_gpr = [&](uint32_t r) {
      if (in_gpr_new(r)) {
        ++s.gpr_new;
      }
      if (r == 18u) {
        ++s.x18;
      }
    };
    auto tally_v = [&](uint32_t r) {
      if (in_v_new(r)) {
        ++s.v_new;
      }
    };

    // GPR: MOV Xd, Xm == ORR Xd, XZR, Xm
    if ((a & 0xFFE0FFE0u) == 0xAA0003E0u) {
      tally_gpr(d);
      tally_gpr(rm);
      continue;
    }
    // GPR: LDR/STR X unsigned imm
    if ((a & 0xFFC00000u) == 0xF9400000u || (a & 0xFFC00000u) == 0xF9000000u) {
      tally_gpr(t);
      tally_gpr(rn);
      continue;
    }
    // GPR: LDR/STR W unsigned imm
    if ((a & 0xFFC00000u) == 0xB9400000u || (a & 0xFFC00000u) == 0xB9000000u) {
      tally_gpr(t);
      tally_gpr(rn);
      continue;
    }
    // GPR: ADD/SUB X shifted reg
    if ((a & 0xFF200000u) == 0x8B000000u || (a & 0xFF200000u) == 0xCB000000u) {
      tally_gpr(d);
      tally_gpr(rn);
      tally_gpr(rm);
      continue;
    }
    // V: ORR Vd.16B, Vn.16B, Vn.16B (MOV)
    if ((a & 0xFFE0FC00u) == 0x4EA01C00u && rm == rn) {
      tally_v(d);
      tally_v(rn);
      continue;
    }
    // V: LDR/STR Q unsigned imm (t is a V register, n is a GPR)
    if ((a & 0xFFC00000u) == 0x3DC00000u || (a & 0xFFC00000u) == 0x3D800000u) {
      tally_v(t);
      continue;
    }
    // V: LDR/STR S unsigned imm
    if ((a & 0xFFC00000u) == 0xBD400000u || (a & 0xFFC00000u) == 0xBD000000u) {
      tally_v(t);
      continue;
    }
    // V: FADD/FSUB/FMUL S scalar
    if ((a & 0xFFE0FC00u) == 0x1E202800u || (a & 0xFFE0FC00u) == 0x1E203800u ||
        (a & 0xFFE0FC00u) == 0x1E200800u) {
      tally_v(d);
      tally_v(rn);
      tally_v(rm);
      continue;
    }
    // V: FADD.4S/FSUB.4S/FMUL.4S
    if ((a & 0xFFE0FC00u) == 0x4E20D400u || (a & 0xFFE0FC00u) == 0x4EA0D400u ||
        (a & 0xFFE0FC00u) == 0x6E20DC00u) {
      tally_v(d);
      tally_v(rn);
      tally_v(rm);
      continue;
    }
  }
  return s;
}
}  // namespace codegen_arm64
