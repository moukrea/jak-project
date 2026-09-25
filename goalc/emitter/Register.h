#pragma once

/*!
 * @file Register.h
 * Representation of an x86-64 Register.
 */

#include <array>
#include <string>
#include <vector>

#include "common/common_types.h"
#include "common/goal_constants.h"
#include "common/util/Assert.h"

#include "goalc/emitter/InstructionSet.h"

namespace emitter {

enum class HWRegKind : u8 { GPR, XMM, INVALID };
HWRegKind reg_class_to_hw(RegClass reg_class);
std::string to_string(HWRegKind kind);

constexpr int GPR_SIZE = 8;
constexpr int XMM_SIZE = 16;

// registers by name
enum X86_REG : s8 {
  RAX,  // return, temp
  RCX,  // arg 3, temp
  RDX,  // arg 2, temp
  RBX,  // saved

  RSP,  // stack pointer (special)
  RBP,  // saved
  RSI,  // arg 1, temp
  RDI,  // arg 0, temp

  R8,   // arg 4, temp
  R9,   // arg 5, temp
  R10,  // arg 6, saved (arg in GOAL only)
  R11,  // arg 7, saved (arg in GOAL only)
  R12,  // saved
  R13,  // pp (special!)
  R14,  // st (special!)
  R15,  // offset (special!)
  XMM0,
  XMM1,
  XMM2,
  XMM3,
  XMM4,
  XMM5,
  XMM6,
  XMM7,
  XMM8,   // saved
  XMM9,   // saved
  XMM10,  // saved
  XMM11,  // saved
  XMM12,  // saved
  XMM13,  // saved
  XMM14,  // saved
  XMM15,  // saved
};

enum ARM64_REG : s8 {
  X0,  // arg 0, caller-saved RDI
  X1,  // arg 1, caller-saved RSI
  X2,  // arg 2, caller-saved RDX
  X3,  // arg 3, caller-saved RCX
  X4,  // arg 4, caller-saved R8
  X5,  // arg 5, caller-saved R9
  X6,  // arg 6, caller-saved R10
  X7,  // arg 7, caller-saved R11

  X8,  // return, temp, not saved (RAX)

  X9,   // temp, not-saved
  X10,  // temp, not-saved
  X11,  // temp, not-saved
  X12,  // temp, not-saved
  X13,  // temp, not-saved
  X14,  // temp, not-saved
  X15,  // temp, not-saved
  X16,  // temp, not-saved
  X17,  // temp, not-saved
  X18,  // temp, not-saved

  x19,  // saved TODO purpose?, R12
  x20,  // pp, R13
  x21,  // st, R14
  x22,  // offset, TODO purpose?, R15
  X23,  // unused, callee saved
  X24,  // unused, callee saved
  X25,  // unused, callee saved
  X26,  // unused, callee saved
  X27,  // unused, callee saved
  X28,  // unused, callee saved
  X29,  // callee saved, FP - don't use it
  X30,  // LR - don't use it

  SP,  // stack pointer

  // quadword registers, equivalent to XMMs
  // the convention in arm64 is the callee preserves all Q values
  // at the same time though, the caller should not depend on this convention!
  Q0 = 0,
  Q1,
  Q2,
  Q3,
  Q4,
  Q5,
  Q6,
  Q7,
  Q8,
  Q9,
  Q10,
  Q11,
  Q12,
  Q13,
  Q14,
  Q15
};

// perf-codegen-arm64-regs — additional arm64-only GOAL temporaries.
// These ids/helpers are defined unconditionally (IGenARM64.cpp, which is
// compiled into both the x86 and arm64 goalc binaries, calls arm64_hw_reg
// unconditionally even though its callers only run on the arm64 backend).
// x86-model ids 32..41 map to hw X19..X28, ids 51..63 map to hw V3..V15.
// ids 42..50 are placeholders (never allocated, `special = true`) so the
// two ranges stay contiguous in the Info table without aliasing hw regs.
enum ARM64_EXTRA_REG : s8 {
  AX19 = 32,
  AX20,
  AX21,
  AX22,
  AX23,
  AX24,
  AX25,
  AX26,
  AX27,
  AX28 = 41,
  ARM64_UNUSED_42 = 42,
  ARM64_UNUSED_43,
  ARM64_UNUSED_44,
  ARM64_UNUSED_45,
  ARM64_UNUSED_46,
  ARM64_UNUSED_47,
  ARM64_UNUSED_48,
  ARM64_UNUSED_49,
  ARM64_UNUSED_50 = 50,
  AV3 = 51,
  AV4,
  AV5,
  AV6,
  AV7,
  AV8,
  AV9,
  AV10,
  AV11,
  AV12,
  AV13,
  AV14,
  AV15 = 63,
};

// perf-codegen-arm64-regs — id -> hw register number, and id -> bank test,
// for the extended arm64 register file (ids 32..41 = X19..X28,
// ids 51..63 = V3..V15). Falls back to the classic `id & 0x1f` mapping for
// every id in 0..31 (unchanged from before this item).
inline uint32_t arm64_hw_reg(int id) {
  if (id >= 32 && id <= 41) {
    return static_cast<uint32_t>(id - 13);  // X19..X28
  }
  if (id >= 51 && id <= 63) {
    return static_cast<uint32_t>(id - 48);  // V3..V15
  }
  return static_cast<uint32_t>(id) & 0x1fu;
}

inline bool arm64_fp_bank(int id) {
  return (id >= 0) && ((id & 16) != 0);
}

class Register {
 public:
  Register() = default;

  // intentionally not explicit so we can use X86_REGs in place of Registers
  Register(int id) : m_id(id) {}

  bool is_128bit_simd(emitter::InstructionSet instr_set) const {
    if (instr_set == emitter::InstructionSet::X86) {
      return m_id >= XMM0 && m_id <= XMM15;
    } else if (instr_set == emitter::InstructionSet::ARM64) {
      // A33: register ids are x86-model THROUGHOUT goalc (gRegInfo is the x86
      // register file on every backend); the AArch64 bank split happens only
      // at encode time (id & 0x1f → X0-X15 for ids 0-15, V16-V31 for 16-31).
      // The old `Q0..Q15` check aliased X0..X15 (Q0 = 0 in ARM64_REG), which
      // INVERTED the test for every x86-model id and mis-classed every
      // function call's args/returns (GPR args became INT_128, 128-bit args
      // became GPR_64 pinned to XMM ids → X16+ clobbers).
      // perf-codegen-arm64-regs: extended with the V3..V15 temp bank
      // (ids 51..63); arm64_fp_bank keeps the ids<32 answer unchanged.
#ifdef GOALC_BACKEND_ARM64
      return arm64_fp_bank(m_id);
#else
      return m_id >= XMM0 && m_id <= XMM15;
#endif
    } else {
      ASSERT_MSG(false, "is_128bit_simd: instruction set not supported");
    }
  }

  bool is_xmm(emitter::InstructionSet instr_set) const {
    if (instr_set == emitter::InstructionSet::X86) {
      return m_id >= XMM0 && m_id <= XMM15;
    } else if (instr_set == emitter::InstructionSet::ARM64) {
      return false;
    } else {
      ASSERT_MSG(false, "is_xmm: instruction set not supported");
    }
  }

  bool is_gpr(emitter::InstructionSet instr_set) const {
    if (instr_set == emitter::InstructionSet::X86) {
      return m_id >= RAX && m_id <= R15;
    } else if (instr_set == emitter::InstructionSet::ARM64) {
      // perf-codegen-arm64-regs: ids 32..41 (X19..X28) are also GPRs.
#ifdef GOALC_BACKEND_ARM64
      return (m_id >= X0 && m_id <= X30) || m_id == SP || (m_id >= AX19 && m_id <= AX28);
#else
      return (m_id >= X0 && m_id <= X30) || m_id == SP;
#endif
    } else {
      ASSERT_MSG(false, "is_gpr: instruction set not supported");
    }
  }

  int hw_id(emitter::InstructionSet instr_set) const {
    // ARM64 does not require the concept of a hw_id
    if (instr_set != emitter::InstructionSet::X86) {
      ASSERT_MSG(false, "hw_id is only applicable for x86");
    }
    if (is_xmm(instr_set)) {
      return m_id - XMM0;
    } else if (is_gpr(instr_set)) {
      return m_id - RAX;
    } else {
      ASSERT(false);
    }
    return 0xff;
  }

  int id() const { return m_id; }

  struct hash {
    auto operator()(const Register& x) const { return std::hash<u8>()(x.m_id); }
  };

  bool operator==(const Register& x) const { return m_id == x.m_id; }

  bool operator!=(const Register& x) const { return m_id != x.m_id; }

  std::string print() const;

  /*
    Our XMM Registers are 4 packed single-precision floating points
    In the order (from left->right a.k.a most significant to least significant):
    W | Z | Y | X
  */
  enum class VF_ELEMENT { X, Y, Z, W, NONE };

 private:
  s8 m_id = -1;
};

class RegisterInfo {
 public:
  static constexpr int N_ARGS = 8;
  // perf-codegen-arm64-regs: the arm64 backend gets 32 extra temporary ids
  // (X19..X28, V3..V15, plus a contiguous unused placeholder block) on top
  // of the classic x86-model 0..31 register file.
#ifdef GOALC_BACKEND_ARM64
  static constexpr int N_REGS = 64;
#else
  static constexpr int N_REGS = 32;
#endif
  static constexpr int N_SAVED_GPRS = 5;
  static constexpr int N_SAVED_XMMS = 8;
  static constexpr int N_TEMP_GPRS = 5;
  static constexpr int N_TEMP_XMMS = 8;

#ifndef GOALC_BACKEND_ARM64
  static_assert(N_REGS - 1 == XMM15, "bad register count");
#endif

  static RegisterInfo make_register_info();

  struct Info {
    bool saved = false;    // does the callee save it?
    bool special = false;  // is it a special GOAL register?
    std::string name;

    bool temp() const { return !saved && !special; }
  };

  const Info& get_info(Register r) const { return m_info.at(r.id()); }
  Register get_gpr_arg_reg(int id) const { return m_gpr_arg_regs.at(id); }
  Register get_xmm_arg_reg(int id) const { return m_xmm_arg_regs.at(id); }
  Register get_saved_gpr(int id) const { return m_saved_gprs.at(id); }
  Register get_saved_xmm(int id) const { return m_saved_xmms.at(id); }
  Register get_process_reg() const { return R13; }
  Register get_st_reg() const { return R14; }
  Register get_offset_reg() const { return R15; }
  Register get_gpr_ret_reg() const { return RAX; }
  Register get_xmm_ret_reg() const { return XMM0; }
  const std::vector<Register>& get_gpr_alloc_order() { return m_gpr_alloc_order; }
  const std::vector<Register>& get_xmm_alloc_order() { return m_xmm_alloc_order; }
  const std::vector<Register>& get_gpr_temp_alloc_order() { return m_gpr_temp_only_alloc_order; }
  const std::vector<Register>& get_xmm_temp_alloc_order() { return m_xmm_temp_only_alloc_order; }
  const std::vector<Register>& get_gpr_spill_alloc_order() { return m_gpr_spill_temp_alloc_order; }
  const std::vector<Register>& get_xmm_spill_alloc_order() { return m_xmm_spill_temp_alloc_order; }
  const std::array<Register, N_SAVED_XMMS + N_SAVED_GPRS>& get_all_saved() { return m_saved_all; }

 private:
  RegisterInfo() = default;
  std::array<Info, N_REGS> m_info;
  std::array<Register, N_ARGS> m_gpr_arg_regs;
  std::array<Register, N_ARGS> m_xmm_arg_regs;
  std::array<Register, N_SAVED_GPRS> m_saved_gprs;
  std::array<Register, N_SAVED_XMMS> m_saved_xmms;
  std::array<Register, N_SAVED_XMMS + N_SAVED_GPRS> m_saved_all;
  std::vector<Register> m_gpr_alloc_order;
  std::vector<Register> m_xmm_alloc_order;
  std::vector<Register> m_gpr_temp_only_alloc_order;
  std::vector<Register> m_xmm_temp_only_alloc_order;
  std::vector<Register> m_gpr_spill_temp_alloc_order;
  std::vector<Register> m_xmm_spill_temp_alloc_order;
};

extern RegisterInfo gRegInfo;

}  // namespace emitter
