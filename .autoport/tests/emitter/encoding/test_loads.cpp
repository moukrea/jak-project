// Encoding tests for GOAL load helpers in IGenARM64.cpp.
//
// load_goal_gpr / load_goal_xmm32 / load_goal_xmm128 emit the A6 paired
// "ADD X16, addr, off ; LDR Wt, [X16, #imm]" sequence — the original
// pre-A6 helper class silently dropped `off`, which manifested as the
// display.gc NULL fn-pointer BLR on device. These tests assert the
// paired emission shape AND each instruction word.

#include "test_helpers.h"

namespace {

// ADD X16, Xaddr, Xoff — base 0x8B000000.
constexpr uint32_t expect_add_x16(uint32_t addr, uint32_t off) {
    return 0x8B000000u | (off << 16) | (addr << 5) | 16u;
}
// LDR Wt, [X16, #imm12] — base 0xB9400000, imm12 scaled by 4.
constexpr uint32_t expect_ldr_w_x16(uint32_t rt, uint32_t imm_bytes) {
    uint32_t imm12 = (imm_bytes >> 2) & 0xfffu;
    return 0xB9400000u | (imm12 << 10) | (16u << 5) | rt;
}
// LDR Xt, [X16, #imm12] — base 0xF9400000, imm12 scaled by 8.
constexpr uint32_t expect_ldr_x_x16(uint32_t rt, uint32_t imm_bytes) {
    uint32_t imm12 = (imm_bytes >> 3) & 0xfffu;
    return 0xF9400000u | (imm12 << 10) | (16u << 5) | rt;
}
// LDR Qt, [X16, #imm12] — base 0x3DC00000, imm12 scaled by 16.
constexpr uint32_t expect_ldr_q_x16(uint32_t rt, uint32_t imm_bytes) {
    uint32_t imm12 = (imm_bytes >> 4) & 0xfffu;
    return 0x3DC00000u | (imm12 << 10) | (16u << 5) | rt;
}
// LDR St (32-bit FPSIMD), [X16, #imm12] — base 0xBD400000, imm12 scaled by 4.
constexpr uint32_t expect_ldr_s_x16(uint32_t rt, uint32_t imm_bytes) {
    uint32_t imm12 = (imm_bytes >> 2) & 0xfffu;
    return 0xBD400000u | (imm12 << 10) | (16u << 5) | rt;
}
// LDRSB Xt, [Xn, #imm12] — base 0x39800000.
constexpr uint32_t expect_ldrsb_x(uint32_t rt, uint32_t base, uint32_t imm) {
    return 0x39800000u | ((imm & 0xfffu) << 10) | (base << 5) | rt;
}
// LDRB Wt, [Xn, #imm12] — base 0x39400000.
constexpr uint32_t expect_ldrb_w(uint32_t rt, uint32_t base, uint32_t imm) {
    return 0x39400000u | ((imm & 0xfffu) << 10) | (base << 5) | rt;
}
// LDRSH Xt, [Xn, #imm12] — base 0x79800000.
constexpr uint32_t expect_ldrsh_x(uint32_t rt, uint32_t base, uint32_t imm12_h) {
    return 0x79800000u | ((imm12_h & 0xfffu) << 10) | (base << 5) | rt;
}
// LDR Xt, [Xn, #imm12] — base 0xF9400000, imm12 scaled by 8.
constexpr uint32_t expect_ldr_x(uint32_t rt, uint32_t base, uint32_t imm_bytes) {
    uint32_t imm12 = (imm_bytes >> 3) & 0xfffu;
    return 0xF9400000u | (imm12 << 10) | (base << 5) | rt;
}
// LDUR Wt, [Xn, #simm9] — base 0xB8400000.
constexpr uint32_t expect_ldur_w(uint32_t rt, uint32_t base, int simm9) {
    uint32_t imm = static_cast<uint32_t>(simm9) & 0x1FFu;
    return 0xB8400000u | (imm << 12) | (base << 5) | rt;
}

}  // namespace

// ---- emit_load_goal_gpr — 4-byte unsigned, off-register paired with X16 ----
// load_goal_gpr(dst, addr, off, offset, size, sign_extend)
// size=4, sign_extend=false → LDR Wt, [X16, #offset].
TEST_CASE("emit_load_goal_gpr 4-byte unsigned off=X9 offset=0") {
    auto enc = load_goal_gpr(X3, X5, X9, 0, 4, false);
    EXPECT_ENC(load_goal_gpr(X3, X5, X9, 0, 4, false), expect_add_x16(5, 9));
    EXPECT_EXTRA_WORDS(load_goal_gpr(X3, X5, X9, 0, 4, false), 1);
    EXPECT_EXTRA_AT(load_goal_gpr(X3, X5, X9, 0, 4, false), 0, expect_ldr_w_x16(3, 0));
}
TEST_CASE("emit_load_goal_gpr 4-byte aligned offset=64") {
    EXPECT_ENC(load_goal_gpr(X3, X5, X9, 64, 4, false), expect_add_x16(5, 9));
    EXPECT_EXTRA_AT(load_goal_gpr(X3, X5, X9, 64, 4, false), 0, expect_ldr_w_x16(3, 64));
}
TEST_CASE("emit_load_goal_gpr 4-byte negative offset → LDUR fallback") {
    // offset=-4 doesn't fit positive imm12; falls back to LDUR Wt, [X16, #-4].
    EXPECT_ENC(load_goal_gpr(X3, X5, X9, -4, 4, false), expect_add_x16(5, 9));
    EXPECT_EXTRA_AT(load_goal_gpr(X3, X5, X9, -4, 4, false), 0, expect_ldur_w(3, 16, -4));
}
TEST_CASE("emit_load_goal_gpr 8-byte offset=0") {
    EXPECT_EXTRA_AT(load_goal_gpr(X3, X5, X9, 0, 8, false), 0, expect_ldr_x_x16(3, 0));
}

// ---- emit_load_goal_xmm128 ----
TEST_CASE("emit_load_goal_xmm128 Q0 X5 X9 offset=0") {
    EXPECT_ENC(load_goal_xmm128(Q0, X5, X9, 0), expect_add_x16(5, 9));
    EXPECT_EXTRA_WORDS(load_goal_xmm128(Q0, X5, X9, 0), 1);
    EXPECT_EXTRA_AT(load_goal_xmm128(Q0, X5, X9, 0), 0, expect_ldr_q_x16(0, 0));
}
TEST_CASE("emit_load_goal_xmm128 Q4 offset=32") {
    EXPECT_EXTRA_AT(load_goal_xmm128(Q4, X5, X9, 32), 0, expect_ldr_q_x16(4, 32));
}

// ---- emit_load_goal_xmm32 ----
TEST_CASE("emit_load_goal_xmm32 Q0 X5 X9 offset=0") {
    EXPECT_ENC(load_goal_xmm32(Q0, X5, X9, 0), expect_add_x16(5, 9));
    EXPECT_EXTRA_AT(load_goal_xmm32(Q0, X5, X9, 0), 0, expect_ldr_s_x16(0, 0));
}

// ---- emit_load8s_gpr64_gpr64_plus_gpr64 family ----
// These collapse to a single LDRSB/LDRB (the (void)addr2 path); A6 work
// retained their original "ignore off" shape for non-GOAL-pointer-deref
// callers since these IRs only use addr+offset on x86 SIB.
TEST_CASE("emit_load8s_gpr64_gpr64_plus_gpr64 X3 X5") {
    EXPECT_ENC(load8s_gpr64_gpr64_plus_gpr64(X3, X5, X9), expect_ldrsb_x(3, 5, 0));
}
TEST_CASE("emit_load8u_gpr64_gpr64_plus_gpr64 X3 X5") {
    EXPECT_ENC(load8u_gpr64_gpr64_plus_gpr64(X3, X5, X9), expect_ldrb_w(3, 5, 0));
}
TEST_CASE("emit_load16s_gpr64_gpr64_plus_gpr64 X3 X5") {
    // imm12 for halfword is bytes>>1; offset=0 → imm12=0.
    EXPECT_ENC(load16s_gpr64_gpr64_plus_gpr64(X3, X5, X9), expect_ldrsh_x(3, 5, 0));
}

// ---- emit_load8s_gpr64_gpr64_plus_gpr64_plus_s8/s32 ----
TEST_CASE("emit_load8s_gpr64_gpr64_plus_gpr64_plus_s8 offset=16") {
    EXPECT_ENC(load8s_gpr64_gpr64_plus_gpr64_plus_s8(X3, X5, X9, 16),
               expect_ldrsb_x(3, 5, 16));
}
TEST_CASE("emit_load8s_gpr64_gpr64_plus_gpr64_plus_s32 offset=128") {
    EXPECT_ENC(load8s_gpr64_gpr64_plus_gpr64_plus_s32(X3, X5, X9, 128),
               expect_ldrsb_x(3, 5, 128));
}
TEST_CASE("emit_load8u_gpr64_gpr64_plus_gpr64_plus_s8 offset=16") {
    EXPECT_ENC(load8u_gpr64_gpr64_plus_gpr64_plus_s8(X3, X5, X9, 16),
               expect_ldrb_w(3, 5, 16));
}
TEST_CASE("emit_load8u_gpr64_gpr64_plus_gpr64_plus_s32 offset=128") {
    EXPECT_ENC(load8u_gpr64_gpr64_plus_gpr64_plus_s32(X3, X5, X9, 128),
               expect_ldrb_w(3, 5, 128));
}

// ---- emit_load64_gpr64_plus_s32 — stack-slot access (RSP→SP rewrite) ----
TEST_CASE("emit_load64_gpr64_plus_s32 X3 from X5 +32") {
    EXPECT_ENC(load64_gpr64_plus_s32(X3, 32, X5), expect_ldr_x(3, 5, 32));
}
TEST_CASE("emit_load64_gpr64_plus_s32 X3 from RSP(=4) +64 → SP base") {
    // src_reg.id() == 4 (x86 RSP) → base rewritten to id 31 (SP).
    EXPECT_ENC(load64_gpr64_plus_s32(X3, 64, Register(4)), expect_ldr_x(3, 31, 64));
}

// ---- emit_load16s/16u/32s/32u (RIP-relative wrappers) ----
// These collapse to LDR* with base=Rt and offset=imm — only encoding shape
// matters for the tests; the real linker patches the disp.
TEST_CASE("emit_load16s_rip_s32 X3 +32") {
    // LDRSH Xt, [Xt, #imm12_halfword] — addr1==dst by helper convention.
    // Our wrapper returns ldrsh_x_imm(dst, dst, offset) shape.
    EXPECT_ARM64_SHAPED(load16s_rip_s32(X3, 32));
}
TEST_CASE("emit_load16u_rip_s32 X3 +32") {
    EXPECT_ARM64_SHAPED(load16u_rip_s32(X3, 32));
}
TEST_CASE("emit_load32s_rip_s32 X3 +32") {
    EXPECT_ARM64_SHAPED(load32s_rip_s32(X3, 32));
}
TEST_CASE("emit_load32u_rip_s32 X3 +32") {
    EXPECT_ARM64_SHAPED(load32u_rip_s32(X3, 32));
}
TEST_CASE("emit_load64_rip_s32 X3 +32") {
    EXPECT_ARM64_SHAPED(load64_rip_s32(X3, 32));
}
TEST_CASE("emit_load8s_rip_s32 X3 +32") {
    EXPECT_ARM64_SHAPED(load8s_rip_s32(X3, 32));
}
TEST_CASE("emit_load8u_rip_s32 X3 +32") {
    EXPECT_ARM64_SHAPED(load8u_rip_s32(X3, 32));
}

// ---- emit_load32_xmm32_gpr64_* family ----
TEST_CASE("emit_load32_xmm32_gpr64_plus_gpr64 Q0 X5") {
    EXPECT_ARM64_SHAPED(load32_xmm32_gpr64_plus_gpr64(Q0, X5, X9));
}
TEST_CASE("emit_load32_xmm32_gpr64_plus_gpr64_plus_s8 Q0 X5 +16") {
    EXPECT_ARM64_SHAPED(load32_xmm32_gpr64_plus_gpr64_plus_s8(Q0, X5, X9, 16));
}
TEST_CASE("emit_load32_xmm32_gpr64_plus_gpr64_plus_s32 Q0 X5 +64") {
    EXPECT_ARM64_SHAPED(load32_xmm32_gpr64_plus_gpr64_plus_s32(Q0, X5, X9, 64));
}
TEST_CASE("emit_load32_xmm32_gpr64_plus_s32 Q0 X5 +64") {
    EXPECT_ARM64_SHAPED(load32_xmm32_gpr64_plus_s32(Q0, X5, 64));
}
TEST_CASE("emit_load32_xmm32_gpr64_plus_s8 Q0 X5 +16") {
    EXPECT_ARM64_SHAPED(load32_xmm32_gpr64_plus_s8(Q0, X5, 16));
}

// ---- emit_load128_xmm128_reg_offset ----
TEST_CASE("emit_load128_xmm128_reg_offset Q0 X5 +32") {
    EXPECT_ARM64_SHAPED(load128_xmm128_reg_offset(Q0, X5, 32));
}

// ---- emit_loadvf_* family (VF loads → LDR Q) ----
TEST_CASE("emit_loadvf_gpr64_plus_gpr64 Q0 X5") {
    EXPECT_ARM64_SHAPED(loadvf_gpr64_plus_gpr64(Q0, X5, X9));
}
TEST_CASE("emit_loadvf_gpr64_plus_gpr64_plus_s8 Q0 X5 +16") {
    EXPECT_ARM64_SHAPED(loadvf_gpr64_plus_gpr64_plus_s8(Q0, X5, X9, 16));
}
TEST_CASE("emit_loadvf_gpr64_plus_gpr64_plus_s32 Q0 X5 +64") {
    EXPECT_ARM64_SHAPED(loadvf_gpr64_plus_gpr64_plus_s32(Q0, X5, X9, 64));
}
TEST_CASE("emit_loadvf_rip_plus_s32 Q0 +64") {
    EXPECT_ARM64_SHAPED(loadvf_rip_plus_s32(Q0, 64));
}

// ---- emit_load128_simd128_* family ----
TEST_CASE("emit_load128_simd128_gpr64 Q0 X5") {
    EXPECT_ARM64_SHAPED(load128_simd128_gpr64(Q0, X5));
}
TEST_CASE("emit_load128_simd128_gpr64_s8 Q0 X5 +16") {
    EXPECT_ARM64_SHAPED(load128_simd128_gpr64_s8(Q0, X5, 16));
}
TEST_CASE("emit_load128_simd128_gpr64_s32 Q0 X5 +64") {
    EXPECT_ARM64_SHAPED(load128_simd128_gpr64_s32(Q0, X5, 64));
}

// ---- emit_load_reg_offset_xmm32 ----
TEST_CASE("emit_load_reg_offset_xmm32 Q0 X5 +32") {
    EXPECT_ARM64_SHAPED(load_reg_offset_xmm32(Q0, X5, 32));
}

// ---- emit_load16s/u, load32s/u — gpr64_plus_gpr64 family non-RIP ----
TEST_CASE("emit_load16s_gpr64_gpr64_plus_gpr64_plus_s8 X3 X5 +8") {
    EXPECT_ARM64_SHAPED(load16s_gpr64_gpr64_plus_gpr64_plus_s8(X3, X5, X9, 8));
}
TEST_CASE("emit_load16s_gpr64_gpr64_plus_gpr64_plus_s32 X3 X5 +64") {
    EXPECT_ARM64_SHAPED(load16s_gpr64_gpr64_plus_gpr64_plus_s32(X3, X5, X9, 64));
}
TEST_CASE("emit_load16u_gpr64_gpr64_plus_gpr64 X3 X5") {
    EXPECT_ARM64_SHAPED(load16u_gpr64_gpr64_plus_gpr64(X3, X5, X9));
}
TEST_CASE("emit_load16u_gpr64_gpr64_plus_gpr64_plus_s8 X3 X5 +8") {
    EXPECT_ARM64_SHAPED(load16u_gpr64_gpr64_plus_gpr64_plus_s8(X3, X5, X9, 8));
}
TEST_CASE("emit_load16u_gpr64_gpr64_plus_gpr64_plus_s32 X3 X5 +64") {
    EXPECT_ARM64_SHAPED(load16u_gpr64_gpr64_plus_gpr64_plus_s32(X3, X5, X9, 64));
}
TEST_CASE("emit_load32s_gpr64_gpr64_plus_gpr64 X3 X5") {
    EXPECT_ARM64_SHAPED(load32s_gpr64_gpr64_plus_gpr64(X3, X5, X9));
}
TEST_CASE("emit_load32s_gpr64_gpr64_plus_gpr64_plus_s8 X3 X5 +8") {
    EXPECT_ARM64_SHAPED(load32s_gpr64_gpr64_plus_gpr64_plus_s8(X3, X5, X9, 8));
}
TEST_CASE("emit_load32s_gpr64_gpr64_plus_gpr64_plus_s32 X3 X5 +64") {
    EXPECT_ARM64_SHAPED(load32s_gpr64_gpr64_plus_gpr64_plus_s32(X3, X5, X9, 64));
}
TEST_CASE("emit_load32u_gpr64_gpr64_plus_gpr64 X3 X5") {
    EXPECT_ARM64_SHAPED(load32u_gpr64_gpr64_plus_gpr64(X3, X5, X9));
}
TEST_CASE("emit_load32u_gpr64_gpr64_plus_gpr64_plus_s8 X3 X5 +8") {
    EXPECT_ARM64_SHAPED(load32u_gpr64_gpr64_plus_gpr64_plus_s8(X3, X5, X9, 8));
}
TEST_CASE("emit_load32u_gpr64_gpr64_plus_gpr64_plus_s32 X3 X5 +64") {
    EXPECT_ARM64_SHAPED(load32u_gpr64_gpr64_plus_gpr64_plus_s32(X3, X5, X9, 64));
}
TEST_CASE("emit_load64_gpr64_gpr64_plus_gpr64 X3 X5") {
    EXPECT_ARM64_SHAPED(load64_gpr64_gpr64_plus_gpr64(X3, X5, X9));
}
TEST_CASE("emit_load64_gpr64_gpr64_plus_gpr64_plus_s8 X3 X5 +8") {
    EXPECT_ARM64_SHAPED(load64_gpr64_gpr64_plus_gpr64_plus_s8(X3, X5, X9, 8));
}
TEST_CASE("emit_load64_gpr64_gpr64_plus_gpr64_plus_s32 X3 X5 +64") {
    EXPECT_ARM64_SHAPED(load64_gpr64_gpr64_plus_gpr64_plus_s32(X3, X5, X9, 64));
}
TEST_CASE("emit_load8s_gpr64_gpr64_plus_gpr64_plus_s8 X3 X5 +8") {
    EXPECT_ARM64_SHAPED(load8s_gpr64_gpr64_plus_gpr64_plus_s8(X3, X5, X9, 8));
}
TEST_CASE("emit_load8s_gpr64_gpr64_plus_gpr64_plus_s32 X3 X5 +64") {
    EXPECT_ARM64_SHAPED(load8s_gpr64_gpr64_plus_gpr64_plus_s32(X3, X5, X9, 64));
}
