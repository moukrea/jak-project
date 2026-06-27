#pragma once

#include "goalc/emitter/Instruction.h"
#include "goalc/emitter/Register.h"

namespace emitter {
namespace IGen {
namespace ARM64 {
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   MOVES
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
/*!
 * Move data from src to dst. Moves all 64-bits of the GPR.
 */
InstructionARM64 mov_gpr64_gpr64(Register dst, Register src);

/*!
 * Move a 64-bit constant into a register.
 */
InstructionARM64 mov_gpr64_u64(Register dst, uint64_t val);

/*!
 * Move a 32-bit constant into a register. Zeros the upper 32 bits.
 */
InstructionARM64 mov_gpr64_u32(Register dst, uint64_t val);

/*!
 * Move a signed 32-bit constant into a register. Sign extends for the upper 32 bits.
 * When possible prefer mov_gpr64_u32. (use this only for negative values...)
 * This is always bigger than mov_gpr64_u32, but smaller than a mov_gpr_u64.
 */
InstructionARM64 mov_gpr64_s32(Register dst, int64_t val);

/*!
 * Move 32-bits of xmm to 32 bits of gpr (no sign extension).
 */
InstructionARM64 movd_gpr32_xmm32(Register dst, Register src);

/*!
 * Move 32-bits of gpr to 32-bits of xmm (no sign extension)
 */
InstructionARM64 movd_xmm32_gpr32(Register dst, Register src);

/*!
 * Move 64-bits of xmm to 64 bits of gpr (no sign extension).
 */
InstructionARM64 movq_gpr64_xmm64(Register dst, Register src);

/*!
 * Move 64-bits of gpr to 64-bits of xmm (no sign extension)
 */
InstructionARM64 movq_xmm64_gpr64(Register dst, Register src);

/*!
 * Move 32-bits between xmm's
 */
InstructionARM64 mov_xmm32_xmm32(Register dst, Register src);

/*!
 * A25 — Move 64-bits between two FPSIMD D-form registers (FMOV Dd, Dn).
 * Provided for completeness alongside movq_gpr64_xmm64 (FMOV Xd, Dn) and
 * movq_xmm64_gpr64 (FMOV Dd, Xn). The GOAL FLOAT class is single-precision
 * so IR_RegSet's FLOAT-FLOAT path uses the 32-bit fmov_s_reg
 * (mov_xmm32_xmm32) instead; this helper is callable by future codegen
 * that needs a full 64-bit FPR move.
 */
InstructionARM64 fmov_d_d(Register dst, Register src);

// todo - GPR64 -> XMM64 (zext)
// todo - XMM -> GPR64

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   GOAL Loads and Stores
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

/*!
 * movsx dst, BYTE PTR [addr1 + addr2]
 * addr1 and addr2 have to be different registers.
 * Cannot use rsp.
 */
InstructionARM64 load8s_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2);

InstructionARM64 store8_gpr64_gpr64_plus_gpr64(Register addr1, Register addr2, Register value);

InstructionARM64 load8s_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                       Register addr1,
                                                       Register addr2,
                                                       s64 offset);

InstructionARM64 store8_gpr64_gpr64_plus_gpr64_plus_s8(Register addr1,
                                                       Register addr2,
                                                       Register value,
                                                       s64 offset);

InstructionARM64 load8s_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset);

InstructionARM64 store8_gpr64_gpr64_plus_gpr64_plus_s32(Register addr1,
                                                        Register addr2,
                                                        Register value,
                                                        s64 offset);

/*!
 * movzx dst, BYTE PTR [addr1 + addr2]
 * addr1 and addr2 have to be different registers.
 * Cannot use rsp.
 */
InstructionARM64 load8u_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2);

InstructionARM64 load8u_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                       Register addr1,
                                                       Register addr2,
                                                       s64 offset);

InstructionARM64 load8u_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset);

/*!
 * movsx dst, WORD PTR [addr1 + addr2]
 * addr1 and addr2 have to be different registers.
 * Cannot use rsp.
 */
InstructionARM64 load16s_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2);

InstructionARM64 store16_gpr64_gpr64_plus_gpr64(Register addr1, Register addr2, Register value);

InstructionARM64 store16_gpr64_gpr64_plus_gpr64_plus_s8(Register addr1,
                                                        Register addr2,
                                                        Register value,
                                                        s64 offset);

InstructionARM64 store16_gpr64_gpr64_plus_gpr64_plus_s32(Register addr1,
                                                         Register addr2,
                                                         Register value,
                                                         s64 offset);

InstructionARM64 load16s_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset);

InstructionARM64 load16s_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                         Register addr1,
                                                         Register addr2,
                                                         s64 offset);

/*!
 * movzx dst, WORD PTR [addr1 + addr2]
 * addr1 and addr2 have to be different registers.
 * Cannot use rsp.
 */
InstructionARM64 load16u_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2);

InstructionARM64 load16u_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset);

InstructionARM64 load16u_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                         Register addr1,
                                                         Register addr2,
                                                         s64 offset);

/*!
 * movsxd dst, DWORD PTR [addr1 + addr2]
 * addr1 and addr2 have to be different registers.
 * Cannot use rsp.
 */
InstructionARM64 load32s_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2);

InstructionARM64 store32_gpr64_gpr64_plus_gpr64(Register addr1, Register addr2, Register value);

InstructionARM64 load32s_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset);

InstructionARM64 store32_gpr64_gpr64_plus_gpr64_plus_s8(Register addr1,
                                                        Register addr2,
                                                        Register value,
                                                        s64 offset);

InstructionARM64 load32s_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                         Register addr1,
                                                         Register addr2,
                                                         s64 offset);

InstructionARM64 store32_gpr64_gpr64_plus_gpr64_plus_s32(Register addr1,
                                                         Register addr2,
                                                         Register value,
                                                         s64 offset);

/*!
 * movzxd dst, DWORD PTR [addr1 + addr2]
 * addr1 and addr2 have to be different registers.
 * Cannot use rsp.
 */
InstructionARM64 load32u_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2);

InstructionARM64 load32u_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset);

InstructionARM64 load32u_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                         Register addr1,
                                                         Register addr2,
                                                         s64 offset);

/*!
 * mov dst, QWORD PTR [addr1 + addr2]
 * addr1 and addr2 have to be different registers.
 * Cannot use rsp.
 */
InstructionARM64 load64_gpr64_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2);

InstructionARM64 store64_gpr64_gpr64_plus_gpr64(Register addr1, Register addr2, Register value);

InstructionARM64 load64_gpr64_gpr64_plus_gpr64_plus_s8(Register dst,
                                                       Register addr1,
                                                       Register addr2,
                                                       s64 offset);

InstructionARM64 store64_gpr64_gpr64_plus_gpr64_plus_s8(Register addr1,
                                                        Register addr2,
                                                        Register value,
                                                        s64 offset);

InstructionARM64 load64_gpr64_gpr64_plus_gpr64_plus_s32(Register dst,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset);

InstructionARM64 store64_gpr64_gpr64_plus_gpr64_plus_s32(Register addr1,
                                                         Register addr2,
                                                         Register value,
                                                         s64 offset);

InstructionARM64 store_goal_vf(Register addr, Register value, Register off, s64 offset);

InstructionARM64 store_goal_gpr(Register addr, Register value, Register off, int offset, int size);

InstructionARM64 load_goal_xmm128(Register dst, Register addr, Register off, int offset);

/*!
 * Load memory at addr + offset, where addr is a GOAL pointer and off is the offset register.
 * This will pick the appropriate fancy addressing mode instruction.
 */
InstructionARM64 load_goal_gpr(Register dst,
                               Register addr,
                               Register off,
                               int offset,
                               int size,
                               bool sign_extend);

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   LOADS n' STORES - XMM32
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
InstructionARM64 store32_xmm32_gpr64_plus_gpr64(Register addr1, Register addr2, Register xmm_value);

InstructionARM64 load32_xmm32_gpr64_plus_gpr64(Register simd_dest, Register addr1, Register addr2);

InstructionARM64 store32_xmm32_gpr64_plus_gpr64_plus_s8(Register addr1,
                                                        Register addr2,
                                                        Register xmm_value,
                                                        s64 offset);

InstructionARM64 load32_xmm32_gpr64_plus_gpr64_plus_s8(Register simd_dest,
                                                       Register addr1,
                                                       Register addr2,
                                                       s64 offset);

InstructionARM64 store32_xmm32_gpr64_plus_gpr64_plus_s32(Register addr1,
                                                         Register addr2,
                                                         Register xmm_value,
                                                         s64 offset);

InstructionARM64 lea_reg_plus_off32(Register dest, Register base, s64 offset);

InstructionARM64 lea_reg_plus_off8(Register dest, Register base, s64 offset);

InstructionARM64 lea_reg_plus_off(Register dest, Register base, s64 offset);

InstructionARM64 store32_xmm32_gpr64_plus_s32(Register base, Register xmm_value, s64 offset);

InstructionARM64 store32_xmm32_gpr64_plus_s8(Register base, Register xmm_value, s64 offset);

InstructionARM64 load32_xmm32_gpr64_plus_gpr64_plus_s32(Register simd_dest,
                                                        Register addr1,
                                                        Register addr2,
                                                        s64 offset);

InstructionARM64 load32_xmm32_gpr64_plus_s32(Register simd_dest, Register base, s64 offset);

InstructionARM64 load32_xmm32_gpr64_plus_s8(Register simd_dest, Register base, s64 offset);

InstructionARM64 load_goal_xmm32(Register simd_dest, Register addr, Register off, s64 offset);

InstructionARM64 store_goal_xmm32(Register addr, Register xmm_value, Register off, s64 offset);

InstructionARM64 store_reg_offset_xmm32(Register base, Register xmm_value, s64 offset);

InstructionARM64 load_reg_offset_xmm32(Register simd_dest, Register base, s64 offset);

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   LOADS n' STORES - XMM128
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

/*!
 * Store a 128-bit xmm into an address stored in a register, no offset
 */
InstructionARM64 store128_gpr64_simd128(Register gpr_addr, Register xmm_value);

InstructionARM64 store128_gpr64_simd128_s32(Register gpr_addr, Register xmm_value, s64 offset);

InstructionARM64 store128_gpr64_simd128_s8(Register gpr_addr, Register xmm_value, s64 offset);

InstructionARM64 load128_simd128_gpr64(Register simd_dest, Register gpr_addr);

InstructionARM64 load128_simd128_gpr64_s32(Register simd_dest, Register gpr_addr, s64 offset);

InstructionARM64 load128_simd128_gpr64_s8(Register simd_dest, Register gpr_addr, s64 offset);

InstructionARM64 load128_xmm128_reg_offset(Register simd_dest, Register base, s64 offset);

InstructionARM64 store128_xmm128_reg_offset(Register base, Register xmm_val, s64 offset);

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   RIP loads and stores
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

InstructionARM64 load64_rip_s32(Register dest, s64 offset);

InstructionARM64 load32s_rip_s32(Register dest, s64 offset);

InstructionARM64 load32u_rip_s32(Register dest, s64 offset);

InstructionARM64 load16u_rip_s32(Register dest, s64 offset);

InstructionARM64 load16s_rip_s32(Register dest, s64 offset);

InstructionARM64 load8u_rip_s32(Register dest, s64 offset);

InstructionARM64 load8s_rip_s32(Register dest, s64 offset);

InstructionARM64 static_load(Register dest, s64 offset, int size, bool sign_extend);

InstructionARM64 store64_rip_s32(Register src, s64 offset);

InstructionARM64 store32_rip_s32(Register src, s64 offset);

InstructionARM64 store16_rip_s32(Register src, s64 offset);

InstructionARM64 store8_rip_s32(Register src, s64 offset);

InstructionARM64 static_store(Register value, s64 offset, int size);

InstructionARM64 static_addr(Register dst, s64 offset);

InstructionARM64 static_load_xmm32(Register simd_dest, s64 offset);

InstructionARM64 static_store_xmm32(Register xmm_value, s64 offset);

// TODO, special load/stores of 128 bit values.

// TODO, consider specialized stack loads and stores?
InstructionARM64 load64_gpr64_plus_s32(Register dst_reg, int32_t offset, Register src_reg);

/*!
 * Store 64-bits from gpr into memory located at 64-bit reg + 32-bit signed offset.
 */
InstructionARM64 store64_gpr64_plus_s32(Register addr, int32_t offset, Register value);

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   FUNCTION STUFF
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
/*!
 * Function return. Pops the 64-bit return address (real) off the stack and jumps to it.
 */
InstructionARM64 ret();

/*!
 * Instruction to push gpr (64-bits) onto the stack
 */
InstructionARM64 push_gpr64(Register reg);

/*!
 * Instruction to pop 64 bit gpr from the stack
 */
InstructionARM64 pop_gpr64(Register reg);

/*!
 * Call a function stored in a 64-bit gpr
 */
InstructionARM64 call_r64(Register reg_);

/*!
 * Jump to an x86-64 address stored in a 64-bit gpr.
 */
InstructionARM64 jmp_r64(Register reg_);

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   INTEGER MATH
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
InstructionARM64 sub_gpr64_imm8s(Register reg, int64_t imm);

InstructionARM64 sub_gpr64_imm32s(Register reg, int64_t imm);

InstructionARM64 add_gpr64_imm8s(Register reg, int64_t v);

InstructionARM64 add_gpr64_imm32s(Register reg, int64_t v);

InstructionARM64 add_gpr64_imm(Register reg, int64_t imm);

InstructionARM64 sub_gpr64_imm(Register reg, int64_t imm);

InstructionARM64 add_gpr64_gpr64(Register dst, Register src);

InstructionARM64 sub_gpr64_gpr64(Register dst, Register src);

/*!
 * Multiply gprs (32-bit, signed).
 * (Note - probably worth doing imul on gpr64's to implement the EE's unsigned multiply)
 */
InstructionARM64 imul_gpr32_gpr32(Register dst, Register src);

/*!
 * Multiply gprs (64-bit, signed).
 * DANGER - this treats all operands as 64-bit. This is not like the EE.
 */
InstructionARM64 imul_gpr64_gpr64(Register dst, Register src);

/*!
 * Divide (idiv, 32 bit)
 */
InstructionARM64 idiv_gpr32(Register reg);

InstructionARM64 unsigned_div_gpr32(Register reg);

/*!
 * Convert doubleword to quadword for division.
 */
InstructionARM64 cdq();

/*!
 * Move from gpr32 to gpr64, with sign extension.
 * Needed for multiplication/divsion madness.
 */
InstructionARM64 movsx_r64_r32(Register dst, Register src);

/*!
 * Compare gpr64.  This sets the flags for the jumps.
 * todo UNTESTED
 */
InstructionARM64 cmp_gpr64_gpr64(Register a, Register b);

// AArch64-only helpers (phase 24 minimum-viable backend).
//
// movz/movk in shift-of-16 increments — IR_LoadConstant64 emits a movz
// at lsl=0 followed by up to three movks (at 16/32/48) to materialise a
// full 64-bit immediate one ARM64 instruction at a time.
InstructionARM64 movz_gpr64_imm16_lsl(Register dst, uint16_t imm, int shift_div16);
InstructionARM64 movk_gpr64_imm16_lsl(Register dst, uint16_t imm, int shift_div16);

// Placeholder branches for the jump-link patcher. Both encode a zero
// displacement; ObjectGenerator::handle_temp_jump_links fills in the
// imm26/imm19 field once function layout is known.
InstructionARM64 b_uncond_placeholder();
InstructionARM64 b_cond_placeholder(int cond);

// Branch-with-Link placeholder used by IR_FunctionCall on arm64. The
// imm26 field is patched once the callee's address is known.
InstructionARM64 bl_placeholder();

// Page-aligned address materialisation used for symbol-table / static-data
// addressing. ADRP writes a 4KB-aligned PC-relative address into Xd; an
// ADD imm12 follows to add the low-12 within the page. The placeholder
// emits ADRP with imm21=0 — the relocation fixup adds the right value.
InstructionARM64 adrp_placeholder(Register dst);
// Compact form when the target is known to be < 1MB away from PC.
InstructionARM64 adr_placeholder(Register dst);

// PC-relative literal load (LDR Xt, =literal). imm19 patched by the
// ObjectGenerator's literal-pool fix-up.
InstructionARM64 ldr_x_literal_placeholder(Register dst);

// Branch (no link) to register, used by IR_JumpReg.
InstructionARM64 br_reg(Register reg);
// Branch-with-link to register (already aliased through call_r64()), exposed
// for tests / direct calls.
InstructionARM64 blr_reg(Register reg);

// Compare-and-branch placeholders for the asm-level IR forms.
InstructionARM64 cbz_x_placeholder(Register r);
InstructionARM64 cbnz_x_placeholder(Register r);

// A26 — Compare-and-branch-non-zero with explicit byte offset
// (CBNZ Xt, #imm). Used by IR_IntegerMath's arm64 IDIV/UDIV divide-by-zero
// trap to skip the immediately-following UDF when the divisor is non-zero.
// `offset_bytes` must be a multiple of 4; the trap path always passes 8
// (skip the next 4-byte UDF instruction). Range fits in the signed 19-bit
// imm19 field after dividing by 4 (±1 MB), more than enough for the +8
// jump-over-trap pattern.
InstructionARM64 cbnz_x_imm(Register r, int offset_bytes);

// A26 — Permanently Undefined instruction with a 16-bit tag
// (UDF #imm16). Encoded as `imm16 & 0xFFFF` in the low 16 bits with the
// top 16 bits zero. Used by the IR_IntegerMath divide-by-zero trap with
// tag 0xBEEF, decoded by linux_arm64_main.cpp's SIGILL handler as the
// BREAK-MACRO-TRAP signature. Distinct from A23/A24's 0x1EC0..0x1EFF
// tracer-tag ranges.
InstructionARM64 udf_imm16(uint16_t imm16);

// AArch64 condition codes used with b_cond_placeholder.
enum ArmCond : int {
  ARM_COND_EQ = 0x0,
  ARM_COND_NE = 0x1,
  ARM_COND_CS = 0x2,
  ARM_COND_CC = 0x3,
  ARM_COND_MI = 0x4,
  ARM_COND_PL = 0x5,
  ARM_COND_VS = 0x6,
  ARM_COND_VC = 0x7,
  ARM_COND_HI = 0x8,
  ARM_COND_LS = 0x9,
  ARM_COND_GE = 0xA,
  ARM_COND_LT = 0xB,
  ARM_COND_GT = 0xC,
  ARM_COND_LE = 0xD,
};

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   BIT STUFF
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

/*!
 * Or of two gprs
 */
InstructionARM64 or_gpr64_gpr64(Register dst, Register src);

/*!
 * And of two gprs
 */
InstructionARM64 and_gpr64_gpr64(Register dst, Register src);

/*!
 * Xor of two gprs
 */
InstructionARM64 xor_gpr64_gpr64(Register dst, Register src);

/*!
 * Bitwise not a gpr
 */
InstructionARM64 not_gpr64(Register reg);

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   SHIFTS
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

/*!
 * Shift 64-bit gpr left by CL register
 */
InstructionARM64 shl_gpr64_cl(Register reg);

/*!
 * Shift 64-bit gpr right (logical) by CL register
 */
InstructionARM64 shr_gpr64_cl(Register reg);

/*!
 * Shift 64-bit gpr right (arithmetic) by CL register
 */
InstructionARM64 sar_gpr64_cl(Register reg);

/*!
 * Shift 64-ptr left (logical) by the constant shift amount "sa".
 */
InstructionARM64 shl_gpr64_u8(Register reg, uint8_t sa);

/*!
 * Shift 64-ptr right (logical) by the constant shift amount "sa".
 */
InstructionARM64 shr_gpr64_u8(Register reg, uint8_t sa);

/*!
 * Shift 64-ptr right (arithmetic) by the constant shift amount "sa".
 */
InstructionARM64 sar_gpr64_u8(Register reg, uint8_t sa);

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   CONTROL FLOW
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

/*!
 * Jump, 32-bit constant offset.  The offset is by default 0 and must be patched later.
 */
InstructionARM64 jmp_32();

/*!
 * Jump if equal.
 */
InstructionARM64 je_32();

/*!
 * Jump not equal.
 */
InstructionARM64 jne_32();

/*!
 * Jump less than or equal.
 */
InstructionARM64 jle_32();

/*!
 * Jump greater than or equal.
 */
InstructionARM64 jge_32();

/*!
 * Jump less than
 */
InstructionARM64 jl_32();

/*!
 * Jump greater than
 */
InstructionARM64 jg_32();

/*!
 * Jump below or equal
 */
InstructionARM64 jbe_32();

/*!
 * Jump above or equal
 */
InstructionARM64 jae_32();

/*!
 * Jump below
 */
InstructionARM64 jb_32();

/*!
 * Jump above
 */
InstructionARM64 ja_32();

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   FLOAT MATH
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

/*!
 * Compare two floats and set flag register for jump (ucomiss)
 */
InstructionARM64 cmp_flt_flt(Register a, Register b);

InstructionARM64 sqrts_xmm(Register dst, Register src);

/*!
 * Multiply two floats in xmm's
 */
InstructionARM64 mulss_xmm_xmm(Register dst, Register src);

/*!
 * Divide two floats in xmm's
 */
InstructionARM64 divss_xmm_xmm(Register dst, Register src);

/*!
 * Subtract two floats in xmm's
 */
InstructionARM64 subss_xmm_xmm(Register dst, Register src);

/*!
 * Add two floats in xmm's
 */
InstructionARM64 addss_xmm_xmm(Register dst, Register src);

/*!
 * Floating point minimum.
 */
InstructionARM64 minss_xmm_xmm(Register dst, Register src);

/*!
 * Floating point maximum.
 */
InstructionARM64 maxss_xmm_xmm(Register dst, Register src);

/*!
 * Convert GPR int32 to XMM float (single precision)
 */
InstructionARM64 int32_to_float(Register dst, Register src);

/*!
 * Convert XMM float to GPR int32(single precision) (truncate)
 */
InstructionARM64 float_to_int32(Register dst, Register src);

// Gcollision-systemic — x86 cvttss2si/cvttps2dq saturation emulation helpers
// (arm64-only; used by IR_FloatToInt / IR_VFMath2Asm do_codegen_arm64 to fix up
// the +ovf/+Inf/NaN lanes FCVTZS saturates differently from x86).
InstructionARM64 csel(Register dst, Register n, Register m, uint32_t cond);
InstructionARM64 movi_4s_lsl24(Register dst, uint32_t imm8);
InstructionARM64 fcmgt_4s(Register dst, Register a, Register b);
InstructionARM64 bif_16b(Register dst, Register n, Register m);

InstructionARM64 nop();

// TODO - rsqrt / abs / sqrt

//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
//   UTILITIES
//;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

/*!
 * A "null" instruction.  This instruction does not generate any bytes
 * but can be referred to by a label.  Useful to insert in place of a real instruction
 * if the real instruction has been optimized out.
 */
InstructionARM64 null();

/////////////////////////////
// AVX (VF - Vector Float) //
/////////////////////////////

InstructionARM64 nop_vf();

InstructionARM64 wait_vf();

InstructionARM64 mov_vf_vf(Register dst, Register src);

InstructionARM64 loadvf_gpr64_plus_gpr64(Register dst, Register addr1, Register addr2);

InstructionARM64 loadvf_gpr64_plus_gpr64_plus_s8(Register dst,
                                                 Register addr1,
                                                 Register addr2,
                                                 s64 offset);

InstructionARM64 loadvf_gpr64_plus_gpr64_plus_s32(Register dst,
                                                  Register addr1,
                                                  Register addr2,
                                                  s64 offset);

InstructionARM64 storevf_gpr64_plus_gpr64(Register value, Register addr1, Register addr2);

InstructionARM64 storevf_gpr64_plus_gpr64_plus_s8(Register value,
                                                  Register addr1,
                                                  Register addr2,
                                                  s64 offset);

InstructionARM64 storevf_gpr64_plus_gpr64_plus_s32(Register value,
                                                   Register addr1,
                                                   Register addr2,
                                                   s64 offset);

InstructionARM64 loadvf_rip_plus_s32(Register dest, s64 offset);

// TODO - rip relative loads and stores.

InstructionARM64 blend_vf(Register dst, Register src1, Register src2, u8 mask);

InstructionARM64 shuffle_vf(Register dst, Register src, u8 dx, u8 dy, u8 dz, u8 dw);

/*
  Generic Swizzle (re-arrangment of packed FPs) operation, the control bytes are quite involved.
  Here's a brief run-down:
  - 8-bits / 4 groups of 2 bits
  - Right-to-left, each group is used to determine which element in `src` gets copied into
  `dst`'s element (W->X).
  - GROUP OPTIONS
  - 00b - Copy the least-significant element (X)
  - 01b - Copy the second element (from the right) (Y)
  - 10b - Copy the third element (from the right) (Z)
  - 11b - Copy the most significant element (W)
  Examples
  ; xmm1 = (1.5, 2.5, 3.5, 4.5) (W,Z,Y,X in x86 land)
  SHUFPS xmm1, xmm1, 0xff ; Copy the most significant element to all positions
  > (1.5, 1.5, 1.5, 1.5)
  SHUFPS xmm1, xmm1, 0x39 ; Rotate right
  > (4.5, 1.5, 2.5, 3.5)
  */
InstructionARM64 swizzle_vf(Register dst, Register src, u8 controlBytes);

/*
  Splats a single element in 'src' to all elements in 'dst'
  For example (pseudocode):
  xmm1 = (1.5, 2.5, 3.5, 4.5)
  xmm2 = (1, 2, 3, 4)
  splat_vf(xmm1, xmm2, XMM_ELEMENT::X);
  xmm1 = (4, 4, 4, 4)
  */
InstructionARM64 splat_vf(Register dst, Register src, Register::VF_ELEMENT element);

InstructionARM64 xor_vf(Register dst, Register src1, Register src2);

InstructionARM64 sub_vf(Register dst, Register src1, Register src2);

InstructionARM64 add_vf(Register dst, Register src1, Register src2);

InstructionARM64 mul_vf(Register dst, Register src1, Register src2);

InstructionARM64 max_vf(Register dst, Register src1, Register src2);

InstructionARM64 min_vf(Register dst, Register src1, Register src2);

InstructionARM64 div_vf(Register dst, Register src1, Register src2);

InstructionARM64 sqrt_vf(Register dst, Register src);

InstructionARM64 itof_vf(Register dst, Register src);

InstructionARM64 ftoi_vf(Register dst, Register src);

InstructionARM64 pw_sra(Register dst, Register src, u8 imm);

InstructionARM64 pw_srl(Register dst, Register src, u8 imm);

InstructionARM64 ph_srl(Register dst, Register src, u8 imm);

InstructionARM64 pw_sll(Register dst, Register src, u8 imm);

InstructionARM64 ph_sll(Register dst, Register src, u8 imm);

InstructionARM64 parallel_add_byte(Register dst, Register src0, Register src1);

InstructionARM64 parallel_bitwise_or(Register dst, Register src0, Register src1);

InstructionARM64 parallel_bitwise_xor(Register dst, Register src0, Register src1);

InstructionARM64 parallel_bitwise_and(Register dst, Register src0, Register src1);

// Reminder - a word in MIPS = 32bits = a DWORD in x86
//     MIPS   ||   x86
// -----------------------
// byte       || byte
// halfword   || word
// word       || dword
// doubleword || quadword

// -- Unpack High Data Instructions
InstructionARM64 pextub_swapped(Register dst, Register src0, Register src1);

InstructionARM64 pextuh_swapped(Register dst, Register src0, Register src1);

InstructionARM64 pextuw_swapped(Register dst, Register src0, Register src1);

// -- Unpack Low Data Instructions
InstructionARM64 pextlb_swapped(Register dst, Register src0, Register src1);

InstructionARM64 pextlh_swapped(Register dst, Register src0, Register src1);

InstructionARM64 pextlw_swapped(Register dst, Register src0, Register src1);

// Equal to than comparison as 16 bytes (8 bits)
InstructionARM64 parallel_compare_e_b(Register dst, Register src0, Register src1);

// Equal to than comparison as 8 halfwords (16 bits)
InstructionARM64 parallel_compare_e_h(Register dst, Register src0, Register src1);

// Equal to than comparison as 4 words (32 bits)
InstructionARM64 parallel_compare_e_w(Register dst, Register src0, Register src1);

// Greater than comparison as 16 bytes (8 bits)
InstructionARM64 parallel_compare_gt_b(Register dst, Register src0, Register src1);

// Greater than comparison as 8 halfwords (16 bits)
InstructionARM64 parallel_compare_gt_h(Register dst, Register src0, Register src1);

// Greater than comparison as 4 words (32 bits)
InstructionARM64 parallel_compare_gt_w(Register dst, Register src0, Register src1);

InstructionARM64 vpunpcklqdq(Register dst, Register src0, Register src1);

InstructionARM64 pcpyld_swapped(Register dst, Register src0, Register src1);

InstructionARM64 pcpyud(Register dst, Register src0, Register src1);

InstructionARM64 vpsubd(Register dst, Register src0, Register src1);

InstructionARM64 vpsrldq(Register dst, Register src, u8 imm);

InstructionARM64 vpslldq(Register dst, Register src, u8 imm);

InstructionARM64 vpshuflw(Register dst, Register src, u8 imm);

InstructionARM64 vpshufhw(Register dst, Register src, u8 imm);

InstructionARM64 vpackuswb(Register dst, Register src0, Register src1);
}  // namespace ARM64
}  // namespace IGen
}  // namespace emitter