#pragma once

#include <cstddef>
#include <cstdint>
#include <initializer_list>

// perf-codegen-arm64-scalar — recognise, in LINKED GOAL code, the arm64 sequences
// goalc emits for float->int, integer divide and vector swizzle, in their new
// form and in the form they replaced. The engine scans the global heap (where
// ENGINE and GAME code live) once the game runs: a legacy sequence still there
// means the CGO on the device is not the one this item built, and a family with
// no new sequence means the re-emission never reached the device. The same
// matcher is run by .autoport/tests/codegen_scalar on the sequences the emitter
// produces, so it cannot drift from goalc without that test going red.
namespace codegen_arm64 {
struct ScalarStats {
  uint64_t f2i_new = 0;    // FCVTZS X ; CMP X,W,SXTW ; FCCMP ; MOV X16,#INT_MIN ; CSEL
  uint64_t f2i_old = 0;    // FCVTZS W ; MOVZ X16,#0x8000,LSL#16 ...
  uint64_t div_total = 0;  // CBNZ Xm|Wm,.+8 ; UDF #0xBEEF (the A26 trap every divide starts with)
  uint64_t div_new = 0;  // CBNZ Wm ; UDF ; xDIV Wd,Wd,Wm ; SXTW | xDIV W16,Wd,Wm ; MSUB W ; SXTW
  uint64_t swz_cross_new = 0;  // EXT #4 + INS S[2]  |  EXT #12 + INS S[0] + INS S[3]
  uint64_t swz_old = 0;        // ORR V0,Vn,Vn ; INS Vd.S[0..3] <- V0 (all four lanes)
  uint64_t pshuf_old = 0;      // ORR V0,Vn,Vn ; [ORR Vd,Vn,Vn] ; INS Vd.H[t0..t0+3] <- V0
};

namespace scalar_detail {
inline bool is_ins_s(uint32_t w, uint32_t lane, uint32_t rd) {
  // INS Vd.S[lane], Vn.S[j] : 0x6E000400 | imm5<<16 | (j<<2)<<11 | Rn<<5 | Rd
  // Compared: opcode, imm5 (the lane), bits 15 and 10. Free: imm4 (source lane), Rn.
  return (w & 0xFFFF8400u) == (0x6E000400u | (((lane << 3) | 4u) << 16)) && (w & 31u) == rd;
}
inline bool is_ins_s_from_v0(uint32_t w, uint32_t lane, uint32_t rd) {
  return is_ins_s(w, lane, rd) && ((w >> 5) & 31u) == 0;
}
inline bool is_ins_h_from_v0(uint32_t w, uint32_t lane, uint32_t rd) {
  // INS Vd.H[lane], V0.H[s] : imm5 = (lane<<2)|2
  return (w & 0xFFFF8400u) == (0x6E000400u | (((lane << 2) | 2u) << 16)) &&
         (w & 31u) == rd && ((w >> 5) & 31u) == 0;
}
inline bool is_orr_v(uint32_t w, uint32_t* rn, uint32_t* rd) {
  // ORR Vd.16B, Vn.16B, Vn.16B (MOV)
  if ((w & 0xFFE0FC00u) != 0x4EA01C00u || ((w >> 16) & 31u) != ((w >> 5) & 31u)) {
    return false;
  }
  *rn = (w >> 5) & 31u;
  *rd = w & 31u;
  return true;
}
}  // namespace scalar_detail

inline ScalarStats inspect_scalar(const uint32_t* w, size_t n) {
  using namespace scalar_detail;
  ScalarStats s;
  for (size_t i = 0; i < n; ++i) {
    const uint32_t a = w[i];
    // float -> int
    if ((a & 0xFFFFFC00u) == 0x9E380000u && i + 4 < n) {
      const uint32_t d = a & 31u, sn = (a >> 5) & 31u;
      if (w[i + 1] == (0xEB20C01Fu | (d << 16) | (d << 5)) &&
          w[i + 2] == (0x1E200400u | (sn << 16) | (sn << 5)) && w[i + 3] == 0xB26183F0u &&
          w[i + 4] == (0x9A900000u | (d << 5) | d)) {
        ++s.f2i_new;
      }
    }
    if ((a & 0xFFFFFC00u) == 0x1E380000u && i + 1 < n && w[i + 1] == 0xD2B00010u) {
      ++s.f2i_old;
    }
    // integer divide
    // Only the 32-bit form (arm64-integer-division-matches-x86) is new: the 64-bit
    // one (CBNZ Xm ; xDIV X) renders another number than x86 once an operand
    // carries high bits, so a CGO still holding it counts as legacy.
    if ((a & 0x7FFFFFE0u) == 0x35000040u && i + 2 < n && w[i + 1] == 0x0000BEEFu) {
      ++s.div_total;
      const uint32_t m = a & 31u, q = w[i + 2];
      const bool is_div =
          (a >> 31) == 0 && (q & 0xFFE0F800u) == 0x1AC00800u && ((q >> 16) & 31u) == m;
      const uint32_t qd = q & 31u, qn = (q >> 5) & 31u;
      const auto sxtw = [](uint32_t r) { return 0x93407C00u | (r << 5) | r; };
      if (is_div && qd == qn && qd != 16u && i + 3 < n && w[i + 3] == sxtw(qd)) {
        ++s.div_new;
      } else if (is_div && qd == 16u && qn != 16u && i + 4 < n &&
                 w[i + 3] == (0x1B008000u | (m << 16) | (qn << 10) | (16u << 5) | qn) &&
                 w[i + 4] == sxtw(qn)) {
        ++s.div_new;
      }
    }
    // swizzle, cross-product patterns
    if ((a & 0xFFE0FC00u) == 0x6E002000u && ((a >> 16) & 31u) == ((a >> 5) & 31u) && i + 1 < n &&
        is_ins_s(w[i + 1], 2, a & 31u)) {
      ++s.swz_cross_new;
    }
    if ((a & 0xFFE0FC00u) == 0x6E006000u && ((a >> 16) & 31u) == ((a >> 5) & 31u) && i + 2 < n &&
        is_ins_s(w[i + 1], 0, a & 31u) && is_ins_s(w[i + 2], 3, a & 31u)) {
      ++s.swz_cross_new;
    }
    // legacy V0-staged swizzle / pshuf
    uint32_t rn = 0, rd = 0;
    if (is_orr_v(a, &rn, &rd) && rd == 0 && i + 4 < n) {
      const uint32_t vd = w[i + 1] & 31u;
      if (is_ins_s_from_v0(w[i + 1], 0, vd) && is_ins_s_from_v0(w[i + 2], 1, vd) &&
          is_ins_s_from_v0(w[i + 3], 2, vd) && is_ins_s_from_v0(w[i + 4], 3, vd)) {
        ++s.swz_old;
      }
      // The new emitter still stages through V0 when dst == src, but it never
      // copies src to dst as well, and never re-inserts a halfword in place: only
      // those two shapes are counted as legacy, the rest is byte-identical anyway.
      size_t j = i + 1;
      uint32_t rn2 = 0, rd2 = 0;
      const bool staged_copy = is_orr_v(w[j], &rn2, &rd2) && rn2 == rn && rd2 != 0;
      j += staged_copy;
      if (j + 3 < n) {
        const uint32_t hd = w[j] & 31u;
        for (uint32_t base : {0u, 4u}) {
          bool in_place = false, all = true;
          for (uint32_t k = 0; k < 4; k++) {
            all = all && is_ins_h_from_v0(w[j + k], base + k, hd);
            in_place = in_place || ((w[j + k] >> 12) & 7u) == base + k;
          }
          if (all && (staged_copy || in_place)) {
            ++s.pshuf_old;
          }
        }
      }
    }
  }
  return s;
}
}  // namespace codegen_arm64
