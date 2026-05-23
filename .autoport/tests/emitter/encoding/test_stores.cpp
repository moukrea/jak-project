// Encoding tests for GOAL store helpers in IGenARM64.cpp.
//
// store_goal_gpr / store_goal_vf emit the same A6 paired
// "ADD X16, addr, off ; STR Wt, [X16, #imm]" sequence as the loads.

#include "test_helpers.h"

namespace {

// ADD X16, Xaddr, Xoff — base 0x8B000000.
constexpr uint32_t expect_add_x16(uint32_t addr, uint32_t off) {
    return 0x8B000000u | (off << 16) | (addr << 5) | 16u;
}
// STR Wt, [X16, #imm12] — base 0xB9000000, imm12 scaled by 4.
constexpr uint32_t expect_str_w_x16(uint32_t rt, uint32_t imm_bytes) {
    uint32_t imm12 = (imm_bytes >> 2) & 0xfffu;
    return 0xB9000000u | (imm12 << 10) | (16u << 5) | rt;
}
// STR Xt, [X16, #imm12] — base 0xF9000000, imm12 scaled by 8.
constexpr uint32_t expect_str_x_x16(uint32_t rt, uint32_t imm_bytes) {
    uint32_t imm12 = (imm_bytes >> 3) & 0xfffu;
    return 0xF9000000u | (imm12 << 10) | (16u << 5) | rt;
}
// STR Qt, [X16, #imm12] — base 0x3D800000, imm12 scaled by 16.
constexpr uint32_t expect_str_q_x16(uint32_t rt, uint32_t imm_bytes) {
    uint32_t imm12 = (imm_bytes >> 4) & 0xfffu;
    return 0x3D800000u | (imm12 << 10) | (16u << 5) | rt;
}
// STR Xt, [Xn, #imm12] — base 0xF9000000.
constexpr uint32_t expect_str_x(uint32_t rt, uint32_t base, uint32_t imm_bytes) {
    uint32_t imm12 = (imm_bytes >> 3) & 0xfffu;
    return 0xF9000000u | (imm12 << 10) | (base << 5) | rt;
}
// STRB Wt, [Xn, #imm12] — base 0x39000000.
constexpr uint32_t expect_strb_w(uint32_t rt, uint32_t base, uint32_t imm) {
    return 0x39000000u | ((imm & 0xfffu) << 10) | (base << 5) | rt;
}
// STRH Wt, [Xn, #imm12] — base 0x79000000.
constexpr uint32_t expect_strh_w(uint32_t rt, uint32_t base, uint32_t imm12_h) {
    return 0x79000000u | ((imm12_h & 0xfffu) << 10) | (base << 5) | rt;
}

}  // namespace

// ---- emit_store_goal_gpr — 4-byte, off-register paired with X16 ----
// store_goal_gpr(addr, value, off, offset, size).
TEST_CASE("emit_store_goal_gpr 4-byte off=X9 offset=0") {
    EXPECT_ENC(store_goal_gpr(X5, X3, X9, 0, 4), expect_add_x16(5, 9));
    EXPECT_EXTRA_WORDS(store_goal_gpr(X5, X3, X9, 0, 4), 1);
    EXPECT_EXTRA_AT(store_goal_gpr(X5, X3, X9, 0, 4), 0, expect_str_w_x16(3, 0));
}
TEST_CASE("emit_store_goal_gpr 4-byte offset=64") {
    EXPECT_EXTRA_AT(store_goal_gpr(X5, X3, X9, 64, 4), 0, expect_str_w_x16(3, 64));
}
TEST_CASE("emit_store_goal_gpr 8-byte offset=0") {
    EXPECT_EXTRA_AT(store_goal_gpr(X5, X3, X9, 0, 8), 0, expect_str_x_x16(3, 0));
}

// ---- emit_store_goal_vf — 16-byte, off-register paired with X16 ----
TEST_CASE("emit_store_goal_vf Q0 X5 X9 offset=0") {
    EXPECT_ENC(store_goal_vf(X5, Q0, X9, 0), expect_add_x16(5, 9));
    EXPECT_EXTRA_AT(store_goal_vf(X5, Q0, X9, 0), 0, expect_str_q_x16(0, 0));
}
TEST_CASE("emit_store_goal_vf Q4 X5 X9 offset=32") {
    EXPECT_EXTRA_AT(store_goal_vf(X5, Q4, X9, 32), 0, expect_str_q_x16(4, 32));
}

// ---- emit_store_goal_xmm32 ----
TEST_CASE("emit_store_goal_xmm32 Q0 X5 X9 offset=0") {
    // Shape: ADD X16, X5, X9 ; STR St, [X16, #0]
    EXPECT_ENC(store_goal_xmm32(X5, Q0, X9, 0), expect_add_x16(5, 9));
    EXPECT_EXTRA_WORDS(store_goal_xmm32(X5, Q0, X9, 0), 1);
}

// ---- emit_store8/16/32/64_gpr64_gpr64_plus_gpr64 family ----
TEST_CASE("emit_store8_gpr64_gpr64_plus_gpr64 X5 X3") {
    EXPECT_ENC(store8_gpr64_gpr64_plus_gpr64(X5, X9, X3), expect_strb_w(3, 5, 0));
}
TEST_CASE("emit_store8_gpr64_gpr64_plus_gpr64_plus_s8 +16") {
    EXPECT_ENC(store8_gpr64_gpr64_plus_gpr64_plus_s8(X5, X9, X3, 16),
               expect_strb_w(3, 5, 16));
}
TEST_CASE("emit_store8_gpr64_gpr64_plus_gpr64_plus_s32 +128") {
    EXPECT_ENC(store8_gpr64_gpr64_plus_gpr64_plus_s32(X5, X9, X3, 128),
               expect_strb_w(3, 5, 128));
}
TEST_CASE("emit_store16_gpr64_gpr64_plus_gpr64 X5 X3") {
    EXPECT_ENC(store16_gpr64_gpr64_plus_gpr64(X5, X9, X3), expect_strh_w(3, 5, 0));
}

// ---- emit_store64_gpr64_plus_s32 — stack-slot store with RSP→SP rewrite ----
TEST_CASE("emit_store64_gpr64_plus_s32 X3 to X5 +32") {
    EXPECT_ENC(store64_gpr64_plus_s32(X5, 32, X3), expect_str_x(3, 5, 32));
}
TEST_CASE("emit_store64_gpr64_plus_s32 to RSP(4) → SP base") {
    EXPECT_ENC(store64_gpr64_plus_s32(Register(4), 64, X3), expect_str_x(3, 31, 64));
}

// ---- emit_store32_xmm32_gpr64_plus_* family ----
TEST_CASE("emit_store32_xmm32_gpr64_plus_gpr64 X5 Q0") {
    EXPECT_ARM64_SHAPED(store32_xmm32_gpr64_plus_gpr64(X5, X9, Q0));
}
TEST_CASE("emit_store32_xmm32_gpr64_plus_gpr64_plus_s8 X5 Q0 +16") {
    EXPECT_ARM64_SHAPED(store32_xmm32_gpr64_plus_gpr64_plus_s8(X5, X9, Q0, 16));
}
TEST_CASE("emit_store32_xmm32_gpr64_plus_gpr64_plus_s32 X5 Q0 +64") {
    EXPECT_ARM64_SHAPED(store32_xmm32_gpr64_plus_gpr64_plus_s32(X5, X9, Q0, 64));
}
TEST_CASE("emit_store32_xmm32_gpr64_plus_s32 X5 Q0 +64") {
    EXPECT_ARM64_SHAPED(store32_xmm32_gpr64_plus_s32(X5, Q0, 64));
}
TEST_CASE("emit_store32_xmm32_gpr64_plus_s8 X5 Q0 +16") {
    EXPECT_ARM64_SHAPED(store32_xmm32_gpr64_plus_s8(X5, Q0, 16));
}

// ---- emit_store_reg_offset_xmm32 ----
TEST_CASE("emit_store_reg_offset_xmm32 X5 Q0 +32") {
    EXPECT_ARM64_SHAPED(store_reg_offset_xmm32(X5, Q0, 32));
}

// ---- emit_storevf_* family ----
TEST_CASE("emit_storevf_gpr64_plus_gpr64 Q0 X5") {
    EXPECT_ARM64_SHAPED(storevf_gpr64_plus_gpr64(Q0, X5, X9));
}
TEST_CASE("emit_storevf_gpr64_plus_gpr64_plus_s8 Q0 X5 +16") {
    EXPECT_ARM64_SHAPED(storevf_gpr64_plus_gpr64_plus_s8(Q0, X5, X9, 16));
}
TEST_CASE("emit_storevf_gpr64_plus_gpr64_plus_s32 Q0 X5 +64") {
    EXPECT_ARM64_SHAPED(storevf_gpr64_plus_gpr64_plus_s32(Q0, X5, X9, 64));
}

// ---- emit_store128_simd128_* family ----
TEST_CASE("emit_store128_gpr64_simd128 X5 Q0") {
    EXPECT_ARM64_SHAPED(store128_gpr64_simd128(X5, Q0));
}
TEST_CASE("emit_store128_gpr64_simd128_s8 X5 Q0 +16") {
    EXPECT_ARM64_SHAPED(store128_gpr64_simd128_s8(X5, Q0, 16));
}
TEST_CASE("emit_store128_gpr64_simd128_s32 X5 Q0 +64") {
    EXPECT_ARM64_SHAPED(store128_gpr64_simd128_s32(X5, Q0, 64));
}
TEST_CASE("emit_store128_xmm128_reg_offset X5 Q0 +32") {
    EXPECT_ARM64_SHAPED(store128_xmm128_reg_offset(X5, Q0, 32));
}

// ---- emit_storeN_rip_s32 family ----
TEST_CASE("emit_store8_rip_s32 X3 +32") {
    EXPECT_ARM64_SHAPED(store8_rip_s32(X3, 32));
}
TEST_CASE("emit_store16_rip_s32 X3 +32") {
    EXPECT_ARM64_SHAPED(store16_rip_s32(X3, 32));
}
TEST_CASE("emit_store32_rip_s32 X3 +32") {
    EXPECT_ARM64_SHAPED(store32_rip_s32(X3, 32));
}
TEST_CASE("emit_store64_rip_s32 X3 +32") {
    EXPECT_ARM64_SHAPED(store64_rip_s32(X3, 32));
}

// ---- emit_store16/32/64_gpr64_gpr64_plus_* (offsets) ----
TEST_CASE("emit_store16_gpr64_gpr64_plus_gpr64_plus_s8 X5 X3 +16") {
    EXPECT_ARM64_SHAPED(store16_gpr64_gpr64_plus_gpr64_plus_s8(X5, X9, X3, 16));
}
TEST_CASE("emit_store16_gpr64_gpr64_plus_gpr64_plus_s32 X5 X3 +128") {
    EXPECT_ARM64_SHAPED(store16_gpr64_gpr64_plus_gpr64_plus_s32(X5, X9, X3, 128));
}
TEST_CASE("emit_store32_gpr64_gpr64_plus_gpr64 X5 X3") {
    EXPECT_ARM64_SHAPED(store32_gpr64_gpr64_plus_gpr64(X5, X9, X3));
}
TEST_CASE("emit_store32_gpr64_gpr64_plus_gpr64_plus_s8 X5 X3 +16") {
    EXPECT_ARM64_SHAPED(store32_gpr64_gpr64_plus_gpr64_plus_s8(X5, X9, X3, 16));
}
TEST_CASE("emit_store32_gpr64_gpr64_plus_gpr64_plus_s32 X5 X3 +128") {
    EXPECT_ARM64_SHAPED(store32_gpr64_gpr64_plus_gpr64_plus_s32(X5, X9, X3, 128));
}
TEST_CASE("emit_store64_gpr64_gpr64_plus_gpr64 X5 X3") {
    EXPECT_ARM64_SHAPED(store64_gpr64_gpr64_plus_gpr64(X5, X9, X3));
}
TEST_CASE("emit_store64_gpr64_gpr64_plus_gpr64_plus_s8 X5 X3 +16") {
    EXPECT_ARM64_SHAPED(store64_gpr64_gpr64_plus_gpr64_plus_s8(X5, X9, X3, 16));
}
TEST_CASE("emit_store64_gpr64_gpr64_plus_gpr64_plus_s32 X5 X3 +128") {
    EXPECT_ARM64_SHAPED(store64_gpr64_gpr64_plus_gpr64_plus_s32(X5, X9, X3, 128));
}

// ---- emit_static_load / static_store / static_addr / static_load_xmm32 / static_store_xmm32 ----
TEST_CASE("emit_static_load X3 +32 size=4 unsigned") {
    EXPECT_ARM64_SHAPED(static_load(X3, 32, 4, false));
}
TEST_CASE("emit_static_load X3 +0 size=8 unsigned") {
    EXPECT_ARM64_SHAPED(static_load(X3, 0, 8, false));
}
TEST_CASE("emit_static_load X3 +0 size=1 signed") {
    EXPECT_ARM64_SHAPED(static_load(X3, 0, 1, true));
}
TEST_CASE("emit_static_load X3 +0 size=2 signed") {
    EXPECT_ARM64_SHAPED(static_load(X3, 0, 2, true));
}
TEST_CASE("emit_static_store X3 +32 size=4") {
    EXPECT_ARM64_SHAPED(static_store(X3, 32, 4));
}
TEST_CASE("emit_static_store X3 +0 size=1") {
    EXPECT_ARM64_SHAPED(static_store(X3, 0, 1));
}
TEST_CASE("emit_static_store X3 +0 size=2") {
    EXPECT_ARM64_SHAPED(static_store(X3, 0, 2));
}
TEST_CASE("emit_static_store X3 +0 size=8") {
    EXPECT_ARM64_SHAPED(static_store(X3, 0, 8));
}
TEST_CASE("emit_static_addr X3 +32") {
    // ADRP Xd, page placeholder — base 0x90000000.
    constexpr uint32_t expect = 0x90000000u | 3u;
    EXPECT_ENC(static_addr(X3, 32), expect);
}
TEST_CASE("emit_static_load_xmm32 Q0 +32") {
    // LDR S-literal — base 0x1C000000 | Rt
    constexpr uint32_t expect = 0x1C000000u | 0u;
    EXPECT_ENC(static_load_xmm32(Q0, 32), expect);
}
TEST_CASE("emit_static_store_xmm32 Q0 +32") {
    EXPECT_ARM64_SHAPED(static_store_xmm32(Q0, 32));
}
