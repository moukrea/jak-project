#pragma once
// perf-codegen-arm64-scalar test — the HISTORICAL ("legacy") sequences goalc
// emitted for float->int, integer divide and vector swizzle/pshuf BEFORE the
// perf-codegen-arm64-scalar item, reproduced verbatim from commit
// ff7b7ba1e0 (HEAD at the time this test was written):
//   - float->int:  git show ff7b7ba1e0:goalc/compiler/IR.cpp,
//                  IR_FloatToInt::do_codegen_arm64
//   - int divide:  same file, IR_IntegerMath::do_codegen_arm64,
//                  IDIV_32/IMOD_32 and UDIV_32/UMOD_32 cases
//   - swizzle:     git show ff7b7ba1e0:goalc/emitter/IGenARM64.cpp,
//                  swizzle_vf (general path, non-identity non-broadcast)
//   - pshuf:       same file, pshuf_hw_half (general path)
//
// These functions call the same public IGenARM64.h helpers the legacy IR.cpp
// call site used, plus the same emitter-internal (non-header-declared)
// helpers, forward-declared here exactly like goalc/compiler/IR.cpp:39-50
// forward-declares float_to_int32_x86 / int_div_x for the NEW sequences.
// This file writes nothing under goalc/ or IGenARM64.*: it only calls into
// the real, already-linked IGenARM64.cpp translation unit.

#include <cstdint>
#include <vector>

#include "goalc/emitter/IGenARM64.h"
#include "goalc/emitter/Register.h"

namespace emitter {
namespace IGen {
namespace ARM64 {
// A17 IDIV/UDIV preserve-X8 spill helpers (IGenARM64.cpp, emitter-internal).
InstructionARM64 idiv_spill_sub_sp_16();
InstructionARM64 idiv_spill_str_x8_sp_0();
InstructionARM64 idiv_spill_ldr_x8_sp_0();
InstructionARM64 idiv_spill_add_sp_16();
// F1c modulo remainder helper (IGenARM64.cpp, emitter-internal).
InstructionARM64 imod_msub_gpr(Register dst, Register quotient, Register divisor,
                                Register dividend);
}  // namespace ARM64
}  // namespace IGen
}  // namespace emitter

namespace cgsc_legacy {

inline std::vector<uint32_t> words_of(const emitter::InstructionARM64& i) {
  std::vector<uint32_t> w;
  w.push_back(i.encoding);
  for (auto e : i.extra_words) {
    w.push_back(e);
  }
  return w;
}

inline void append(std::vector<uint32_t>& out, const emitter::InstructionARM64& i) {
  auto w = words_of(i);
  out.insert(out.end(), w.begin(), w.end());
}

// IR_FloatToInt::do_codegen_arm64 @ ff7b7ba1e0 — 9 words.
inline std::vector<uint32_t> legacy_float_to_int32(emitter::Register dst, emitter::Register src) {
  namespace A = emitter::IGen::ARM64;
  emitter::Register x16(emitter::XMM0);  // physical X16 scratch
  emitter::Register x17(emitter::XMM1);  // physical X17 scratch
  std::vector<uint32_t> out;
  append(out, A::float_to_int32(dst, src));              // FCVTZS Wd, Ssrc
  append(out, A::movz_gpr64_imm16_lsl(x16, 0x8000, 1));   // X16 = INT_MIN
  append(out, A::movz_gpr64_imm16_lsl(x17, 0xffff, 0));   // X17 = 0x0000ffff
  append(out, A::movk_gpr64_imm16_lsl(x17, 0x7fff, 1));   // X17 = INT_MAX
  append(out, A::cmp_gpr64_gpr64(dst, x17));              // Wd == INT_MAX ?
  append(out, A::csel(dst, x16, dst, A::ARM_COND_EQ));    // yes -> INT_MIN
  append(out, A::cmp_flt_flt(src, src));                  // NaN check
  append(out, A::csel(dst, x16, dst, A::ARM_COND_VS));    // NaN -> INT_MIN
  append(out, A::movsx_r64_r32(dst, dst));                // SXTW Xd, Wd
  return out;
}

// IR_IntegerMath::do_codegen_arm64 @ ff7b7ba1e0, IDIV_32/IMOD_32 and
// UDIV_32/UMOD_32 cases, dst==X8 fast path and general (spill) path,
// including the arg==X8 sub-case. is_signed selects idiv_gpr32/SDIV vs
// unsigned_div_gpr32/UDIV; is_mod selects the MSUB remainder tail.
inline std::vector<uint32_t> legacy_int_div(emitter::Register dst, emitter::Register arg,
                                            bool is_signed, bool is_mod) {
  namespace A = emitter::IGen::ARM64;
  emitter::Register x16(16);
  std::vector<uint32_t> out;
  // A26 divide-by-zero trap, unconditionally prepended, same as legacy IR.cpp.
  append(out, A::cbnz_x_imm(arg, 8));
  append(out, A::udf_imm16(0xBEEF));

  auto do_div = [&](emitter::Register r) {
    if (is_signed) {
      append(out, A::idiv_gpr32(r));
    } else {
      append(out, A::unsigned_div_gpr32(r));
    }
  };

  if (dst.id() == 8) {
    if (is_mod) {
      append(out, A::mov_gpr64_gpr64(x16, dst));
      do_div(arg);
      append(out, A::imod_msub_gpr(dst, emitter::Register(8), arg, x16));
    } else {
      do_div(arg);
    }
  } else {
    emitter::Register divisor_reg = arg;
    if (arg.id() == 8) {
      append(out, A::mov_gpr64_gpr64(x16, arg));
      divisor_reg = x16;
    }
    append(out, A::idiv_spill_sub_sp_16());
    append(out, A::idiv_spill_str_x8_sp_0());
    append(out, A::mov_gpr64_gpr64(emitter::Register(8), dst));
    do_div(divisor_reg);
    if (is_mod) {
      append(out, A::imod_msub_gpr(dst, emitter::Register(8), divisor_reg, dst));
    } else {
      append(out, A::mov_gpr64_gpr64(dst, emitter::Register(8)));
    }
    append(out, A::idiv_spill_ldr_x8_sp_0());
    append(out, A::idiv_spill_add_sp_16());
  }
  return out;
}

static inline uint32_t reg5(emitter::Register r) {
  return static_cast<uint32_t>(r.id()) & 31u;
}

// IGenARM64.cpp::swizzle_vf @ ff7b7ba1e0, general (non-identity,
// non-broadcast) path only — the only path exercised by imm 0x09/0x12.
// ORR V0 <- src ; INS Vd.S[0..3] <- V0.S[sel[t]], unconditionally 4 INS.
inline std::vector<uint32_t> legacy_swizzle(emitter::Register dst, emitter::Register src,
                                            uint8_t imm) {
  const uint8_t sel[4] = {static_cast<uint8_t>(imm & 3), static_cast<uint8_t>((imm >> 2) & 3),
                          static_cast<uint8_t>((imm >> 4) & 3),
                          static_cast<uint8_t>((imm >> 6) & 3)};
  const uint32_t rd = reg5(dst);
  const uint32_t rn = reg5(src);
  std::vector<uint32_t> out;
  out.push_back(0x4EA01C00u | (rn << 16) | (rn << 5) | 0u);  // ORR V0,Vn,Vn
  for (uint32_t t = 0; t < 4; t++) {
    const uint32_t s = sel[t];
    out.push_back(0x6E000400u | (((t << 3) | 4u) << 16) | ((s << 2) << 11) | (0u << 5) | rd);
  }
  return out;
}

// IGenARM64.cpp::pshuf_hw_half @ ff7b7ba1e0, general path: ORR V0<-src ; ORR
// dst<-src (skipped when dst==src) ; 4x INS Vd.H[t]<-V0.H[s].
inline std::vector<uint32_t> legacy_pshuf(emitter::Register dst, emitter::Register src,
                                          uint8_t imm, int half_base) {
  const uint32_t rd = reg5(dst);
  const uint32_t rn = reg5(src);
  std::vector<uint32_t> out;
  out.push_back(0x4EA01C00u | (rn << 16) | (rn << 5) | 0u);  // ORR V0,Vn,Vn
  if (rd != rn) {
    out.push_back(0x4EA01C00u | (rn << 16) | (rn << 5) | rd);  // ORR Vd,Vn,Vn
  }
  for (int i = 0; i < 4; i++) {
    const uint32_t t = static_cast<uint32_t>(half_base + i);
    const uint32_t s = static_cast<uint32_t>(half_base + ((imm >> (2 * i)) & 3));
    out.push_back(0x6E000400u | (((t << 2) | 2u) << 16) | ((s << 1) << 11) | (0u << 5) | rd);
  }
  return out;
}

}  // namespace cgsc_legacy
