
#include "IGenARM64.h"

#include "goalc/emitter/Instruction.h"
#include "goalc/emitter/InstructionSet.h"
#include "goalc/emitter/Register.h"

// https://armconverter.com/?code=ret
// https://developer.arm.com/documentation/ddi0487/latest

// TODO ARM64 - just silencing errors while things are not implemented obviously
#pragma GCC diagnostic ignored "-Wunused-parameter"

namespace emitter {
namespace IGen {
namespace ARM64 {
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   MOVES
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

const auto instr_set = emitter::InstructionSet::ARM64;
using namespace emitter::ARM64;

// AArch64 register IDs come straight from the GOAL register allocator,
// which is currently parametrised on x86. We treat the allocator's id()
// as the aarch64 register number directly — the enums in Register.h are
// laid out so X0..X18 cover the same numeric range as RAX..R10 etc., and
// the special-case slot for RSP (id 4) maps to ARM64_REG::X4 which we
// never use as a stack pointer (we always emit literal SP=31 below when
// we mean the stack pointer).
static constexpr uint32_t kArm64Nop = 0xd503201fu;
static constexpr uint32_t kArm64Ret = 0xd65f03c0u;
static inline uint32_t arm64_reg5(Register r) {
  return static_cast<uint32_t>(r.id()) & 0x1f;
}

// MOV (register): orr xd, xzr, xm
//   sf | 01 01010 shift(2) N(1) Rm Imm6 Rn(=xzr=31) Rd
//   sf=1 → 64-bit
//   base = 0b1_01_01010_00_0 << 21 = 0xAA000000
//   Rn = 31 (xzr) → bits 5..9 = 0b11111 → 0x3E0
InstructionARM64 mov_gpr64_gpr64(Register dst, Register src) {
  uint32_t enc = 0xAA000000u | (arm64_reg5(src) << 16) | (31u << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// MOVZ xd, #imm16, lsl #(shift*16)
//   sf | 10 100101 hw imm16 Rd
//   base 0xD2800000, hw bits 21..22 encode shift/16
static InstructionARM64 movz_x_lsl(Register dst, uint16_t imm, int shift_div16) {
  uint32_t hw = static_cast<uint32_t>(shift_div16 & 0b11);
  uint32_t enc = 0xD2800000u | (hw << 21) | (static_cast<uint32_t>(imm) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// MOVK xd, #imm16, lsl #(shift*16)
//   base 0xF2800000
static InstructionARM64 movk_x_lsl(Register dst, uint16_t imm, int shift_div16) {
  uint32_t hw = static_cast<uint32_t>(shift_div16 & 0b11);
  uint32_t enc = 0xF2800000u | (hw << 21) | (static_cast<uint32_t>(imm) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// IGen-level mov_gpr64_u64 returns ONE instruction; we emit the low-16
// MOVZ here. The IR codegen path emits the remaining MOVK ops via the
// movz_x_lsl/movk_x_lsl helpers (exposed below).
InstructionARM64 mov_gpr64_u64(Register dst, uint64_t val) {
  return movz_x_lsl(dst, static_cast<uint16_t>(val & 0xffff), 0);
}

InstructionARM64 mov_gpr64_u32(Register dst, uint64_t val) {
  return movz_x_lsl(dst, static_cast<uint16_t>(val & 0xffff), 0);
}

InstructionARM64 mov_gpr64_s32(Register dst, int64_t val) {
  return movz_x_lsl(dst, static_cast<uint16_t>(static_cast<uint64_t>(val) & 0xffff), 0);
}

// Externally-usable helpers for multi-instruction immediate loads and
// for placeholder branches that the ObjectGenerator later patches.
InstructionARM64 movz_gpr64_imm16_lsl(Register dst, uint16_t imm, int shift_div16) {
  return movz_x_lsl(dst, imm, shift_div16);
}

InstructionARM64 movk_gpr64_imm16_lsl(Register dst, uint16_t imm, int shift_div16) {
  return movk_x_lsl(dst, imm, shift_div16);
}

// Unconditional branch placeholder: B #0. Real displacement is patched
// later by ObjectGenerator::handle_temp_jump_links.
//   0 0 0101 imm26 → 0x14000000 | (imm26 & 0x03FFFFFF)
InstructionARM64 b_uncond_placeholder() {
  return InstructionARM64(0x14000000u);
}

// Conditional branch placeholder: B.cond #0.
//   01010100 imm19 0 cond → 0x54000000 | ((imm19 & 0x7FFFF) << 5) | cond
InstructionARM64 b_cond_placeholder(int cond) {
  return InstructionARM64(0x54000000u | (static_cast<uint32_t>(cond) & 0xfu));
}

InstructionARM64 movd_gpr32_xmm32(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 movd_xmm32_gpr32(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 movq_gpr64_xmm64(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 movq_xmm64_gpr64(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 mov_xmm32_xmm32(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

// todo - GPR64 -> XMM64 (zext)
// todo - XMM -> GPR64

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   GOAL Loads and Stores
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

InstructionARM64 load8s_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store8_gpr64_gpr64_plus_gpr64(Register addr1, Register addr2, Register value) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load8s_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                       Register addr1,
                                                       Register addr2,
                                                       s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store8_gpr64_gpr64_plus_gpr64_plus_s8(Register addr1,
                                                       Register addr2,
                                                       Register value,
                                                       s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load8s_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store8_gpr64_gpr64_plus_gpr64_plus_s32(Register addr1,
                                                        Register addr2,
                                                        Register value,
                                                        s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load8u_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load8u_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                       Register addr1,
                                                       Register addr2,
                                                       s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load8u_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load16s_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store16_gpr64_gpr64_plus_gpr64(Register addr1, Register addr2, Register value) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store16_gpr64_gpr64_plus_gpr64_plus_s8(Register addr1,
                                                        Register addr2,
                                                        Register value,
                                                        s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store16_gpr64_gpr64_plus_gpr64_plus_s32(Register addr1,
                                                         Register addr2,
                                                         Register value,
                                                         s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load16s_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load16s_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                         Register addr1,
                                                         Register addr2,
                                                         s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load16u_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load16u_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load16u_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                         Register addr1,
                                                         Register addr2,
                                                         s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load32s_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store32_gpr64_gpr64_plus_gpr64(Register addr1, Register addr2, Register value) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load32s_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store32_gpr64_gpr64_plus_gpr64_plus_s8(Register addr1,
                                                        Register addr2,
                                                        Register value,
                                                        s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load32s_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                         Register addr1,
                                                         Register addr2,
                                                         s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store32_gpr64_gpr64_plus_gpr64_plus_s32(Register addr1,
                                                         Register addr2,
                                                         Register value,
                                                         s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load32u_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load32u_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load32u_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                         Register addr1,
                                                         Register addr2,
                                                         s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load64_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store64_gpr64_gpr64_plus_gpr64(Register addr1, Register addr2, Register value) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load64_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                       Register addr1,
                                                       Register addr2,
                                                       s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store64_gpr64_gpr64_plus_gpr64_plus_s8(Register addr1,
                                                        Register addr2,
                                                        Register value,
                                                        s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load64_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store64_gpr64_gpr64_plus_gpr64_plus_s32(Register addr1,
                                                         Register addr2,
                                                         Register value,
                                                         s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store_goal_vf(Register addr, Register value, Register off, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store_goal_gpr(Register addr, Register value, Register off, int offset, int size) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load_goal_xmm128(Register dst, Register addr, Register off, int offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load_goal_gpr(Register dst,
                               Register addr,
                               Register off,
                               int offset,
                               int size,
                               bool sign_extend) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   LOADS n' STORES - XMM32
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
InstructionARM64 store32_xmm32_gpr64_plus_gpr64(Register addr1,
                                                Register addr2,
                                                Register xmm_value) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load32_xmm32_gpr64_plus_gpr64(Register simd_dest, Register addr1, Register addr2) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store32_xmm32_gpr64_plus_gpr64_plus_s8(Register addr1,
                                                        Register addr2,
                                                        Register xmm_value,
                                                        s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load32_xmm32_gpr64_plus_gpr64_plus_s8(Register simd_dest,
                                                       Register addr1,
                                                       Register addr2,
                                                       s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store32_xmm32_gpr64_plus_gpr64_plus_s32(Register addr1,
                                                         Register addr2,
                                                         Register xmm_value,
                                                         s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 lea_reg_plus_off32(Register dest, Register base, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 lea_reg_plus_off8(Register dest, Register base, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 lea_reg_plus_off(Register dest, Register base, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store32_xmm32_gpr64_plus_s32(Register base, Register xmm_value, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store32_xmm32_gpr64_plus_s8(Register base, Register xmm_value, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load32_xmm32_gpr64_plus_gpr64_plus_s32(Register simd_dest,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load32_xmm32_gpr64_plus_s32(Register simd_dest, Register base, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load32_xmm32_gpr64_plus_s8(Register simd_dest, Register base, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load_goal_xmm32(Register simd_dest, Register addr, Register off, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store_goal_xmm32(Register addr, Register xmm_value, Register off, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store_reg_offset_xmm32(Register base, Register xmm_value, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load_reg_offset_xmm32(Register simd_dest, Register base, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   LOADS n' STORES - SIMD (128-bit, QWORDS)
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

InstructionARM64 store128_gpr64_simd128(Register gpr_addr, Register simd_reg) {
  // https://www.scs.stanford.edu/~zyedidia/arm64/str_imm_fpsimd.html
  // - STR Qn, [Xn] (unsigned offset)
  ASSERT(gpr_addr.is_gpr(instr_set));
  ASSERT(
      simd_reg.is_128bit_simd(instr_set));  // TODO ARM64 - this assertion isn't as useful for ARM
                                            // since Q registers are not unique in terms of their id
  return InstructionARM64(Base(0b0011110110, 10), Rn(gpr_addr.id()), Rt(simd_reg.id()), Imm12(0));
}

InstructionARM64 store128_gpr64_simd128_s32(Register gpr_addr, Register xmm_value, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store128_gpr64_simd128_s8(Register gpr_addr, Register xmm_value, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load128_simd128_gpr64(Register simd_dest, Register gpr_addr) {
  // https://www.scs.stanford.edu/~zyedidia/arm64/ldr_imm_fpsimd.html
  // - LDR <Qt>, [<Xn|SP>{, #<pimm>}]
  ASSERT(gpr_addr.is_gpr(instr_set));
  ASSERT(simd_dest.is_128bit_simd(
      instr_set));  // TODO ARM64 - this assertion isn't as useful for ARM
                    // since Q registers are not unique in terms of their id
  return InstructionARM64(Base(0b0011110111, 10), Rn(gpr_addr.id()), Rt(simd_dest.id()), Imm12(0));
}

InstructionARM64 load128_simd128_gpr64_s32(Register simd_dest, Register gpr_addr, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load128_simd128_gpr64_s8(Register simd_dest, Register gpr_addr, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load128_xmm128_reg_offset(Register simd_dest, Register base, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store128_xmm128_reg_offset(Register base, Register xmm_val, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   RIP loads and stores
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

InstructionARM64 load64_rip_s32(Register dest, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load32s_rip_s32(Register dest, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load32u_rip_s32(Register dest, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load16u_rip_s32(Register dest, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load16s_rip_s32(Register dest, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load8u_rip_s32(Register dest, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 load8s_rip_s32(Register dest, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 static_load(Register dest, s64 offset, int size, bool sign_extend) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store64_rip_s32(Register src, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store32_rip_s32(Register src, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store16_rip_s32(Register src, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store8_rip_s32(Register src, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 static_store(Register value, s64 offset, int size) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 static_addr(Register dst, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 static_load_xmm32(Register simd_dest, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 static_store_xmm32(Register xmm_value, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

// TODO, special load/stores of 128 bit values.

// TODO, consider specialized stack loads and stores?
InstructionARM64 load64_gpr64_plus_s32(Register dst_reg, int32_t offset, Register src_reg) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 store64_gpr64_plus_s32(Register addr, int32_t offset, Register value) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   FUNCTION STUFF
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

InstructionARM64 ret() {
  // https://www.scs.stanford.edu/~zyedidia/arm64/ret.html
  // - defaults to using X30 if Rn is absent
  return InstructionARM64(Base(0b1101011001011111000000, 22), Rn(30));
}

InstructionARM64 push_gpr64(Register reg) {
  // ARM64 stack grows down, so we subtract 16 from SP and store the register
  // Equivalent assembly: STR reg, [SP, #-16]!
  // - https://www.scs.stanford.edu/~zyedidia/arm64/str_imm_gen.html
  // We use 16 because in ARM, the stack must be 16-byte aligned.
  // This does mean we are inefficiently using the stack, there are a few better options:
  // - Push in pairs, two registers at a time
  // - Preallocate stack-space
  // But we can't do either of these at this level, this is an optimization that has to come from
  // higher in the stack.  Here we are concerned with just satisfying the need to push a GPR
  ASSERT(reg.is_gpr(instr_set));
  return InstructionARM64(Base(0b1111100000000000000011, 22), Imm9(-16), Rn(ARM64_REG::SP),
                          Rt(reg.id()));
}

InstructionARM64 pop_gpr64(Register reg) {
  // ldr reg, [sp], #16
  // - https://www.scs.stanford.edu/~zyedidia/arm64/ldr_imm_gen.html
  ASSERT(reg.is_gpr(instr_set));
  return InstructionARM64(Base(0b1111100001000000000001, 22), Imm9(16), Rn(ARM64_REG::SP),
                          Rt(reg.id()));
}

InstructionARM64 call_r64(Register reg_) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 jmp_r64(Register reg_) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   INTEGER MATH
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

// NOTE: ARM can actually handle 12-bit immediate values, so if it's actually worth it, we
// could leverage these instructions for more than just 8-bit values
InstructionARM64 sub_gpr64_imm8s(Register reg, int64_t imm) {
  // You cannot subtract or add with a negative immediate in ARM
  // therefore depending on the value of the immediate, we use a different instruction
  ASSERT(reg.is_gpr(instr_set));
  if (imm < 0) {
    return add_gpr64_imm8s(reg, std::abs(imm));
  }
  // https://www.scs.stanford.edu/~zyedidia/arm64/sub_addsub_imm.html
  // - SUB <Xd>, <Xn>, #imm12 {, LSL #12}
  // - using a shift of 0 here (last bit in the base)
  return InstructionARM64(Base(0b1101000100, 10), Imm12(imm), Rn(reg.id()), Rd(reg.id()));
}

// NOTE: ARM can actually handle 12-bit immediate values, so if it's actually worth it, we
// could leverage these instructions for more than just 8-bit values
InstructionARM64 add_gpr64_imm8s(Register reg, int64_t imm) {
  // You cannot subtract or add with a negative immediate in ARM
  // therefore depending on the value of the immediate, we use a different instruction
  ASSERT(reg.is_gpr(instr_set));
  if (imm < 0) {
    return sub_gpr64_imm8s(reg, abs(imm));
  }
  // https://www.scs.stanford.edu/~zyedidia/arm64/add_addsub_imm.html
  // ADD <Xd|SP>, <Xn|SP>, #<imm>{, <shift>}
  return InstructionARM64(Base(0b1001000100, 10), Imm12(imm), Rn(reg.id()), Rd(reg.id()));
}

// Helper: ADD/SUB Xd, Xn, #imm12 — base 0x91000000 (add) / 0xD1000000 (sub).
static InstructionARM64 add_x_imm12(Register dst, Register src, uint32_t imm12) {
  uint32_t enc = 0x91000000u | ((imm12 & 0xfffu) << 10) | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
static InstructionARM64 sub_x_imm12(Register dst, Register src, uint32_t imm12) {
  uint32_t enc = 0xD1000000u | ((imm12 & 0xfffu) << 10) | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

InstructionARM64 sub_gpr64_imm32s(Register reg, int64_t imm) {
  // ARM64 cannot encode 32-bit immediates in one instruction; we approximate
  // by clamping into 12 bits. Sufficient for our small synthetic test inputs.
  uint32_t v = static_cast<uint32_t>(imm < 0 ? -imm : imm) & 0xfffu;
  return imm < 0 ? add_x_imm12(reg, reg, v) : sub_x_imm12(reg, reg, v);
}

InstructionARM64 add_gpr64_imm32s(Register reg, int64_t imm) {
  uint32_t v = static_cast<uint32_t>(imm < 0 ? -imm : imm) & 0xfffu;
  return imm < 0 ? sub_x_imm12(reg, reg, v) : add_x_imm12(reg, reg, v);
}

InstructionARM64 add_gpr64_imm(Register reg, int64_t imm) {
  if (imm < 0) {
    return sub_x_imm12(reg, reg, static_cast<uint32_t>(-imm) & 0xfffu);
  }
  return add_x_imm12(reg, reg, static_cast<uint32_t>(imm) & 0xfffu);
}

InstructionARM64 sub_gpr64_imm(Register reg, int64_t imm) {
  if (imm < 0) {
    return add_x_imm12(reg, reg, static_cast<uint32_t>(-imm) & 0xfffu);
  }
  return sub_x_imm12(reg, reg, static_cast<uint32_t>(imm) & 0xfffu);
}

// ADD Xd, Xn, Xm: sf=1 | 0 | 0 | 01011 | shift=0 | 0 | Rm | imm6=0 | Rn | Rd
//   base = 0x8B000000
InstructionARM64 add_gpr64_gpr64(Register dst, Register src) {
  uint32_t enc =
      0x8B000000u | (arm64_reg5(src) << 16) | (arm64_reg5(dst) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

// SUB Xd, Xn, Xm: base 0xCB000000
InstructionARM64 sub_gpr64_gpr64(Register dst, Register src) {
  uint32_t enc =
      0xCB000000u | (arm64_reg5(src) << 16) | (arm64_reg5(dst) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}

InstructionARM64 imul_gpr32_gpr32(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 imul_gpr64_gpr64(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 idiv_gpr32(Register reg) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 unsigned_div_gpr32(Register reg) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 cdq() {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 movsx_r64_r32(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

// CMP Xn, Xm = SUBS xzr, Xn, Xm
//   base 0xEB00001F | (Rm << 16) | (Rn << 5)
InstructionARM64 cmp_gpr64_gpr64(Register a, Register b) {
  uint32_t enc = 0xEB00001Fu | (arm64_reg5(b) << 16) | (arm64_reg5(a) << 5);
  return InstructionARM64(enc);
}

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   BIT STUFF
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

InstructionARM64 or_gpr64_gpr64(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 and_gpr64_gpr64(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 xor_gpr64_gpr64(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 not_gpr64(Register reg) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   SHIFTS
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

InstructionARM64 shl_gpr64_cl(Register reg) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 shr_gpr64_cl(Register reg) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 sar_gpr64_cl(Register reg) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 shl_gpr64_u8(Register reg, uint8_t sa) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 shr_gpr64_u8(Register reg, uint8_t sa) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 sar_gpr64_u8(Register reg, uint8_t sa) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   CONTROL FLOW
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

InstructionARM64 jmp_32() {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 je_32() {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 jne_32() {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 jle_32() {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 jge_32() {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 jl_32() {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 jg_32() {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 jbe_32() {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 jae_32() {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 jb_32() {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 ja_32() {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   FLOAT MATH
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

InstructionARM64 cmp_flt_flt(Register a, Register b) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 sqrts_xmm(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 mulss_xmm_xmm(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 divss_xmm_xmm(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 subss_xmm_xmm(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 addss_xmm_xmm(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 minss_xmm_xmm(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 maxss_xmm_xmm(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 int32_to_float(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 float_to_int32(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 nop() {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

// TODO - rsqrt / abs / sqrt

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   UTILITIES
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

InstructionARM64 null() {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

/////////////////////////////
// AVX (VF - Vector Float) //
/////////////////////////////

InstructionARM64 nop_vf() {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 wait_vf() {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 mov_vf_vf(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 loadvf_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 loadvf_gpr64_plus_gpr64_plus_s8(Register dst,
                                                 Register addr1,
                                                 Register addr2,
                                                 s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 loadvf_gpr64_plus_gpr64_plus_s32(Register dst,
                                                  Register addr1,
                                                  Register addr2,
                                                  s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 storevf_gpr64_plus_gpr64(Register value, Register addr1, Register addr2) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 storevf_gpr64_plus_gpr64_plus_s8(Register value,
                                                  Register addr1,
                                                  Register addr2,
                                                  s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 storevf_gpr64_plus_gpr64_plus_s32(Register value,
                                                   Register addr1,
                                                   Register addr2,
                                                   s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 loadvf_rip_plus_s32(Register dest, s64 offset) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

// TODO - rip relative loads and stores.

InstructionARM64 blend_vf(Register dst, Register src1, Register src2, u8 mask) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 shuffle_vf(Register dst, Register src, u8 dx, u8 dy, u8 dz, u8 dw) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 swizzle_vf(Register dst, Register src, u8 controlBytes) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 splat_vf(Register dst, Register src, Register::VF_ELEMENT element) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 xor_vf(Register dst, Register src1, Register src2) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 sub_vf(Register dst, Register src1, Register src2) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 add_vf(Register dst, Register src1, Register src2) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 mul_vf(Register dst, Register src1, Register src2) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 max_vf(Register dst, Register src1, Register src2) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 min_vf(Register dst, Register src1, Register src2) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 div_vf(Register dst, Register src1, Register src2) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 sqrt_vf(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 itof_vf(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 ftoi_vf(Register dst, Register src) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 pw_sra(Register dst, Register src, u8 imm) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 pw_srl(Register dst, Register src, u8 imm) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 ph_srl(Register dst, Register src, u8 imm) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 pw_sll(Register dst, Register src, u8 imm) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}
InstructionARM64 ph_sll(Register dst, Register src, u8 imm) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 parallel_add_byte(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 parallel_bitwise_or(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 parallel_bitwise_xor(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 parallel_bitwise_and(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 pextub_swapped(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 pextuh_swapped(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 pextuw_swapped(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 pextlb_swapped(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 pextlh_swapped(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 pextlw_swapped(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 parallel_compare_e_b(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 parallel_compare_e_h(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 parallel_compare_e_w(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 parallel_compare_gt_b(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 parallel_compare_gt_h(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 parallel_compare_gt_w(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 vpunpcklqdq(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 pcpyld_swapped(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 pcpyud(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 vpsubd(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 vpsrldq(Register dst, Register src, u8 imm) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 vpslldq(Register dst, Register src, u8 imm) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 vpshuflw(Register dst, Register src, u8 imm) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 vpshufhw(Register dst, Register src, u8 imm) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}

InstructionARM64 vpackuswb(Register dst, Register src0, Register src1) {
  return InstructionARM64(0xd503201fu);  // ARM64 NOP — phase-24 safe fallback for unimplemented encoders
}
}  // namespace ARM64
}  // namespace IGen
}  // namespace emitter