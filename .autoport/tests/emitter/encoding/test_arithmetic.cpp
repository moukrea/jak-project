// Encoding tests for integer ALU helpers in IGenARM64.cpp.
//
// Each expected encoding is derived from the ARM ARMv8-A ISA reference
// independently of IGenARM64.cpp's source — that's what makes these tests
// real: if a helper silently emits an x86 opcode (the A6 make_function_from_c
// bug), or drops an operand (the A6 (void)off; helper class), or overflows
// imm12 into a NOP (the A5 sym-mem bug), the expected encoding won't match.

#include "test_helpers.h"

namespace {

// ADD Xd, Xn, Xm — shifted register form, shift=LSL #0, imm6=0.
//   sf=1 | 00 01011 shift(00) 0 Rm 000000 Rn Rd  → base 0x8B000000
constexpr uint32_t expect_add_xxx(uint32_t rd, uint32_t rn, uint32_t rm) {
    return 0x8B000000u | (rm << 16) | (rn << 5) | rd;
}
constexpr uint32_t expect_sub_xxx(uint32_t rd, uint32_t rn, uint32_t rm) {
    return 0xCB000000u | (rm << 16) | (rn << 5) | rd;
}
constexpr uint32_t expect_and_xxx(uint32_t rd, uint32_t rn, uint32_t rm) {
    return 0x8A000000u | (rm << 16) | (rn << 5) | rd;
}
constexpr uint32_t expect_orr_xxx(uint32_t rd, uint32_t rn, uint32_t rm) {
    return 0xAA000000u | (rm << 16) | (rn << 5) | rd;
}
constexpr uint32_t expect_eor_xxx(uint32_t rd, uint32_t rn, uint32_t rm) {
    return 0xCA000000u | (rm << 16) | (rn << 5) | rd;
}
// MVN Xd, Xm = ORN Xd, XZR, Xm — base 0xAA2003E0 with Rn=31.
constexpr uint32_t expect_mvn_xx(uint32_t rd, uint32_t rm) {
    return 0xAA2003E0u | (rm << 16) | rd;
}
// CMP Xn, Xm = SUBS XZR, Xn, Xm — base 0xEB00001F with Rd=31.
constexpr uint32_t expect_cmp_xx(uint32_t rn, uint32_t rm) {
    return 0xEB00001Fu | (rm << 16) | (rn << 5);
}
// MUL Xd, Xn, Xm = MADD Xd, Xn, Xm, XZR — base 0x9B007C00.
constexpr uint32_t expect_mul_xxx(uint32_t rd, uint32_t rn, uint32_t rm) {
    return 0x9B007C00u | (rm << 16) | (rn << 5) | rd;
}
// SXTW Xd, Wn = SBFM Xd, Xn, #0, #31 — base 0x93407C00.
constexpr uint32_t expect_sxtw_xw(uint32_t rd, uint32_t rn) {
    return 0x93407C00u | (rn << 5) | rd;
}
// ADD Xd, Xn, #imm12 — base 0x91000000.
constexpr uint32_t expect_add_imm12(uint32_t rd, uint32_t rn, uint32_t imm12) {
    return 0x91000000u | ((imm12 & 0xfffu) << 10) | (rn << 5) | rd;
}
constexpr uint32_t expect_sub_imm12(uint32_t rd, uint32_t rn, uint32_t imm12) {
    return 0xD1000000u | ((imm12 & 0xfffu) << 10) | (rn << 5) | rd;
}

}  // namespace

// ---- emit_add_gpr64_gpr64 — basic shifted-register ADD ----
TEST_CASE("emit_add_gpr64_gpr64 canonical X0 X1") {
    EXPECT_ENC(add_gpr64_gpr64(X0, X1), expect_add_xxx(0, 0, 1));
}
TEST_CASE("emit_add_gpr64_gpr64 distinct regs X3 X5") {
    EXPECT_ENC(add_gpr64_gpr64(X3, X5), expect_add_xxx(3, 3, 5));
}
TEST_CASE("emit_add_gpr64_gpr64 high reg X18 X14") {
    EXPECT_ENC(add_gpr64_gpr64(X18, X14), expect_add_xxx(18, 18, 14));
}

// ---- emit_sub_gpr64_gpr64 — basic shifted-register SUB ----
TEST_CASE("emit_sub_gpr64_gpr64 canonical X3 X5") {
    EXPECT_ENC(sub_gpr64_gpr64(X3, X5), expect_sub_xxx(3, 3, 5));
}
TEST_CASE("emit_sub_gpr64_gpr64 X10 X11") {
    EXPECT_ENC(sub_gpr64_gpr64(X10, X11), expect_sub_xxx(10, 10, 11));
}

// ---- emit_and_gpr64_gpr64 / emit_or_gpr64_gpr64 / emit_xor_gpr64_gpr64 ----
TEST_CASE("emit_and_gpr64_gpr64 X3 X5") {
    EXPECT_ENC(and_gpr64_gpr64(X3, X5), expect_and_xxx(3, 3, 5));
}
TEST_CASE("emit_or_gpr64_gpr64 X3 X5") {
    EXPECT_ENC(or_gpr64_gpr64(X3, X5), expect_orr_xxx(3, 3, 5));
}
TEST_CASE("emit_xor_gpr64_gpr64 X3 X5") {
    EXPECT_ENC(xor_gpr64_gpr64(X3, X5), expect_eor_xxx(3, 3, 5));
}

// ---- emit_not_gpr64 ----
TEST_CASE("emit_not_gpr64 X3") {
    EXPECT_ENC(not_gpr64(X3), expect_mvn_xx(3, 3));
}
TEST_CASE("emit_not_gpr64 X7") {
    EXPECT_ENC(not_gpr64(X7), expect_mvn_xx(7, 7));
}

// ---- emit_cmp_gpr64_gpr64 — encodes as SUBS XZR ----
TEST_CASE("emit_cmp_gpr64_gpr64 X3 X5") {
    EXPECT_ENC(cmp_gpr64_gpr64(X3, X5), expect_cmp_xx(3, 5));
}
TEST_CASE("emit_cmp_gpr64_gpr64 X0 X8") {
    EXPECT_ENC(cmp_gpr64_gpr64(X0, X8), expect_cmp_xx(0, 8));
}

// ---- emit_imul_gpr64_gpr64 + emit_imul_gpr32_gpr32 → MADD with XZR ----
TEST_CASE("emit_imul_gpr64_gpr64 X3 X5") {
    EXPECT_ENC(imul_gpr64_gpr64(X3, X5), expect_mul_xxx(3, 3, 5));
}
TEST_CASE("emit_imul_gpr32_gpr32 X3 X5") {
    EXPECT_ENC(imul_gpr32_gpr32(X3, X5), expect_mul_xxx(3, 3, 5));
}

// ---- emit_movsx_r64_r32 → SXTW Xd, Wn ----
TEST_CASE("emit_movsx_r64_r32 X3 X5") {
    EXPECT_ENC(movsx_r64_r32(X3, X5), expect_sxtw_xw(3, 5));
}

// ---- emit_add_gpr64_imm / emit_add_gpr64_imm8s / emit_add_gpr64_imm32s ----
// All three converge to ADD Xn, Xn, #imm12 for positive imm fitting in 12 bits.
TEST_CASE("emit_add_gpr64_imm small positive X3 +16") {
    EXPECT_ENC(add_gpr64_imm(X3, 16), expect_add_imm12(3, 3, 16));
}
TEST_CASE("emit_add_gpr64_imm8s small positive X4 +8") {
    EXPECT_ENC(add_gpr64_imm8s(X4, 8), expect_add_imm12(4, 4, 8));
}
TEST_CASE("emit_add_gpr64_imm32s small positive X5 +128") {
    EXPECT_ENC(add_gpr64_imm32s(X5, 128), expect_add_imm12(5, 5, 128));
}

// ---- emit_sub_gpr64_imm / emit_sub_gpr64_imm8s / emit_sub_gpr64_imm32s ----
TEST_CASE("emit_sub_gpr64_imm small positive X3 +16") {
    EXPECT_ENC(sub_gpr64_imm(X3, 16), expect_sub_imm12(3, 3, 16));
}
TEST_CASE("emit_sub_gpr64_imm8s small positive X4 +8") {
    EXPECT_ENC(sub_gpr64_imm8s(X4, 8), expect_sub_imm12(4, 4, 8));
}
TEST_CASE("emit_sub_gpr64_imm32s small positive X5 +128") {
    EXPECT_ENC(sub_gpr64_imm32s(X5, 128), expect_sub_imm12(5, 5, 128));
}

// Negative imm flips operation: add of -N → sub of +N, sub of -N → add of +N.
TEST_CASE("emit_add_gpr64_imm negative flips to SUB") {
    EXPECT_ENC(add_gpr64_imm(X3, -16), expect_sub_imm12(3, 3, 16));
}
TEST_CASE("emit_sub_gpr64_imm negative flips to ADD") {
    EXPECT_ENC(sub_gpr64_imm(X3, -16), expect_add_imm12(3, 3, 16));
}

// ---- emit_cdq → ASR X9, X8, #63 (sign-fill X9 from X8's high bit) ----
TEST_CASE("emit_cdq encodes as ASR X9 X8 63") {
    // ASR Xd, Xn, #imm = SBFM Xd, Xn, #imm, #63 — base 0x9340FC00.
    constexpr uint32_t expect = 0x9340FC00u | (63u << 16) | (8u << 5) | 9u;
    EXPECT_ENC(cdq(), expect);
}

// ---- emit_mov_gpr64_gpr64 — the A6-paired X14→GOAL-offset fixup ----
// Regular case: src != X14 → single ORR (mov).
TEST_CASE("emit_mov_gpr64_gpr64 normal X3 X5 (no pairing)") {
    // ORR Xd, XZR, Xm = MOV Xd, Xm — base 0xAA000000 with Rn=31.
    constexpr uint32_t expect = 0xAA000000u | (5u << 16) | (31u << 5) | 3u;
    EXPECT_ENC(mov_gpr64_gpr64(X3, X5), expect);
    EXPECT_EXTRA_WORDS(mov_gpr64_gpr64(X3, X5), 0);
}
TEST_CASE("emit_mov_gpr64_gpr64 X14 source emits paired SUB X15 fixup") {
    // dst=X3, src=X14. First word: ORR X3, XZR, X14.
    // Second word: SUB X3, X3, X15 — base 0xCB000000.
    constexpr uint32_t expect_mov = 0xAA000000u | (14u << 16) | (31u << 5) | 3u;
    constexpr uint32_t expect_sub = 0xCB000000u | (15u << 16) | (3u << 5) | 3u;
    EXPECT_ENC(mov_gpr64_gpr64(X3, X14), expect_mov);
    EXPECT_EXTRA_WORDS(mov_gpr64_gpr64(X3, X14), 1);
    EXPECT_EXTRA_AT(mov_gpr64_gpr64(X3, X14), 0, expect_sub);
}

// ---- emit_lea_reg_plus_off — same X14 fixup applies on positive offsets ----
TEST_CASE("emit_lea_reg_plus_off normal X3 X5 +32 (no pairing)") {
    EXPECT_ENC(lea_reg_plus_off(X3, X5, 32), expect_add_imm12(3, 5, 32));
    EXPECT_EXTRA_WORDS(lea_reg_plus_off(X3, X5, 32), 0);
}
TEST_CASE("emit_lea_reg_plus_off X14 base emits paired SUB X15") {
    constexpr uint32_t expect_add = expect_add_imm12(3, 14, 32);
    constexpr uint32_t expect_sub = 0xCB000000u | (15u << 16) | (3u << 5) | 3u;
    EXPECT_ENC(lea_reg_plus_off(X3, X14, 32), expect_add);
    EXPECT_EXTRA_WORDS(lea_reg_plus_off(X3, X14, 32), 1);
    EXPECT_EXTRA_AT(lea_reg_plus_off(X3, X14, 32), 0, expect_sub);
}
TEST_CASE("emit_lea_reg_plus_off32 same as lea_reg_plus_off X4 X6 +64") {
    EXPECT_ENC(lea_reg_plus_off32(X4, X6, 64), expect_add_imm12(4, 6, 64));
}
TEST_CASE("emit_lea_reg_plus_off8 same as lea_reg_plus_off X4 X6 +16") {
    EXPECT_ENC(lea_reg_plus_off8(X4, X6, 16), expect_add_imm12(4, 6, 16));
}

// ---- emit_lea_reg_plus_off negative offset → SUB imm12 ----
TEST_CASE("emit_lea_reg_plus_off negative offset → SUB") {
    EXPECT_ENC(lea_reg_plus_off(X3, X5, -32), expect_sub_imm12(3, 5, 32));
}

// ---- emit_shl/shr/sar _gpr64_u8 — UBFM/SBFM constant shifts ----
TEST_CASE("emit_shr_gpr64_u8 X3 by 4 — LSR imm = UBFM imm,#63") {
    // LSR Xd, Xn, #imm: UBFM Xd, Xn, #imm, #63 — base 0xD340FC00 | imm<<16.
    constexpr uint32_t expect = 0xD340FC00u | (4u << 16) | (3u << 5) | 3u;
    EXPECT_ENC(shr_gpr64_u8(X3, 4), expect);
}
TEST_CASE("emit_sar_gpr64_u8 X3 by 4 — ASR imm") {
    constexpr uint32_t expect = 0x9340FC00u | (4u << 16) | (3u << 5) | 3u;
    EXPECT_ENC(sar_gpr64_u8(X3, 4), expect);
}
TEST_CASE("emit_shl_gpr64_u8 X3 by 4 — LSL imm = UBFM #-imm,#63-imm") {
    // LSL Xd, Xn, #imm: UBFM Xd, Xn, #(64-imm)%64, #63-imm — base 0xD3400000.
    uint32_t immr = (64u - 4u) & 0x3fu;
    uint32_t imms = 63u - 4u;
    uint32_t expect = 0xD3400000u | (immr << 16) | (imms << 10) | (3u << 5) | 3u;
    EXPECT_ENC(shl_gpr64_u8(X3, 4), expect);
}
TEST_CASE("emit_shl_gpr64_cl X3 — LSLV via X1") {
    // LSLV Xd, Xn, Xm — base 0x9AC02000 | Rm<<16 | Rn<<5 | Rd; Xm=X1 by ABI.
    constexpr uint32_t expect = 0x9AC02000u | (1u << 16) | (3u << 5) | 3u;
    EXPECT_ENC(shl_gpr64_cl(X3), expect);
}
TEST_CASE("emit_shr_gpr64_cl X3 — LSRV via X1") {
    constexpr uint32_t expect = 0x9AC02400u | (1u << 16) | (3u << 5) | 3u;
    EXPECT_ENC(shr_gpr64_cl(X3), expect);
}
TEST_CASE("emit_sar_gpr64_cl X3 — ASRV via X1") {
    constexpr uint32_t expect = 0x9AC02800u | (1u << 16) | (3u << 5) | 3u;
    EXPECT_ENC(sar_gpr64_cl(X3), expect);
}

// ---- emit_idiv_gpr32 / emit_unsigned_div_gpr32 → SDIV/UDIV X8, X8, Xn ----
TEST_CASE("emit_idiv_gpr32 X5 — SDIV X8 X8 X5") {
    // SDIV: base 0x9AC00C00 | Rm<<16 | Rn<<5 | Rd. Rd=Rn=8 (X8 = RAX-equiv).
    constexpr uint32_t expect = 0x9AC00C00u | (5u << 16) | (8u << 5) | 8u;
    EXPECT_ENC(idiv_gpr32(X5), expect);
}
TEST_CASE("emit_unsigned_div_gpr32 X5 — UDIV X8 X8 X5") {
    constexpr uint32_t expect = 0x9AC00800u | (5u << 16) | (8u << 5) | 8u;
    EXPECT_ENC(unsigned_div_gpr32(X5), expect);
}
