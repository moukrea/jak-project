// Encoding tests for branch/jump helpers in IGenARM64.cpp.
//
// Catches:
// - bug class where a branch placeholder reverts to NOP (silent stub)
// - bug class where the conditional bits don't encode the right cond code
// - the A6 call_r64 multi-word callee-save sequence (must stp/blr/ldp seven words)

#include "test_helpers.h"

namespace {

// B #imm26 placeholder — base 0x14000000 (imm=0).
constexpr uint32_t expect_b_uncond = 0x14000000u;
// B.cond #imm19 placeholder — base 0x54000000 | cond.
constexpr uint32_t expect_bcond(uint32_t cond) { return 0x54000000u | (cond & 0xfu); }
// BL #imm26 placeholder — base 0x94000000.
constexpr uint32_t expect_bl = 0x94000000u;
// BLR Xn — base 0xD63F0000 | Rn<<5.
constexpr uint32_t expect_blr(uint32_t rn) { return 0xD63F0000u | (rn << 5); }
// BR Xn — base 0xD61F0000 | Rn<<5.
constexpr uint32_t expect_br(uint32_t rn) { return 0xD61F0000u | (rn << 5); }
// CBZ Xt — base 0xB4000000 | Rt.
constexpr uint32_t expect_cbz(uint32_t rt) { return 0xB4000000u | rt; }
// CBNZ Xt — base 0xB5000000 | Rt.
constexpr uint32_t expect_cbnz(uint32_t rt) { return 0xB5000000u | rt; }
// RET — fixed 0xD65F03C0 (uses X30 as link reg).
constexpr uint32_t expect_ret = 0xD65F03C0u;
// NOP — fixed 0xD503201F.
constexpr uint32_t expect_nop = 0xD503201Fu;

// A6/A19 call_r64 multi-word sequence (caller-side callee-saved preservation).
// Words (verified by aarch64-linux-android28-clang -c in IGenARM64.cpp):
//   stp x3, x5,   [sp, #-16]!
//   stp x10, x11, [sp, #-16]!
//   stp x12, x23, [sp, #-16]!   ; A19: was `str x23` = 0xF81F0FF7
//   blr Xn
//   ldp x12, x23, [sp], #16     ; A19: was `ldr x23` = 0xF84107F7
//   ldp x10, x11, [sp], #16
//   ldp x3, x5,   [sp], #16
constexpr uint32_t kStpX3X5Push   = 0xA9BF17E3u;
constexpr uint32_t kStpX10X11Push = 0xA9BF2FEAu;
constexpr uint32_t kStpX12X23Push = 0xA9BF5FECu;
constexpr uint32_t kLdpX12X23Pop  = 0xA8C15FECu;
constexpr uint32_t kLdpX10X11Pop  = 0xA8C12FEAu;
constexpr uint32_t kLdpX3X5Pop    = 0xA8C117E3u;

}  // namespace

// ---- emit_b_uncond_placeholder / b_cond_placeholder ----
TEST_CASE("emit_b_uncond_placeholder is 0x14000000") {
    EXPECT_ENC(b_uncond_placeholder(), expect_b_uncond);
}
TEST_CASE("emit_b_cond_placeholder EQ is 0x54000000") {
    EXPECT_ENC(b_cond_placeholder(0), expect_bcond(0));
}
TEST_CASE("emit_b_cond_placeholder NE is 0x54000001") {
    EXPECT_ENC(b_cond_placeholder(1), expect_bcond(1));
}

// ---- The 11 conditional jump aliases ----
TEST_CASE("emit_je_32 → b.cond EQ") {
    EXPECT_ENC(je_32(), expect_bcond(0x0));
}
TEST_CASE("emit_jne_32 → b.cond NE") {
    EXPECT_ENC(jne_32(), expect_bcond(0x1));
}
TEST_CASE("emit_jle_32 → b.cond LE") {
    EXPECT_ENC(jle_32(), expect_bcond(0xD));
}
TEST_CASE("emit_jge_32 → b.cond GE") {
    EXPECT_ENC(jge_32(), expect_bcond(0xA));
}
TEST_CASE("emit_jl_32 → b.cond LT") {
    EXPECT_ENC(jl_32(), expect_bcond(0xB));
}
TEST_CASE("emit_jg_32 → b.cond GT") {
    EXPECT_ENC(jg_32(), expect_bcond(0xC));
}
TEST_CASE("emit_jbe_32 → b.cond LS") {
    EXPECT_ENC(jbe_32(), expect_bcond(0x9));
}
TEST_CASE("emit_jae_32 → b.cond CS") {
    EXPECT_ENC(jae_32(), expect_bcond(0x2));
}
TEST_CASE("emit_jb_32 → b.cond CC") {
    EXPECT_ENC(jb_32(), expect_bcond(0x3));
}
TEST_CASE("emit_ja_32 → b.cond HI") {
    EXPECT_ENC(ja_32(), expect_bcond(0x8));
}
TEST_CASE("emit_jmp_32 → b uncond") {
    EXPECT_ENC(jmp_32(), expect_b_uncond);
}

// ---- emit_bl_placeholder / blr_reg / br_reg / jmp_r64 ----
TEST_CASE("emit_bl_placeholder is 0x94000000") {
    EXPECT_ENC(bl_placeholder(), expect_bl);
}
TEST_CASE("emit_blr_reg X8") {
    EXPECT_ENC(blr_reg(X8), expect_blr(8));
}
TEST_CASE("emit_blr_reg X12") {
    EXPECT_ENC(blr_reg(X12), expect_blr(12));
}
TEST_CASE("emit_br_reg X8") {
    EXPECT_ENC(br_reg(X8), expect_br(8));
}
TEST_CASE("emit_jmp_r64 same as br_reg") {
    EXPECT_ENC(jmp_r64(X12), expect_br(12));
}

// ---- emit_cbz_x_placeholder / cbnz_x_placeholder ----
TEST_CASE("emit_cbz_x_placeholder X3") {
    EXPECT_ENC(cbz_x_placeholder(X3), expect_cbz(3));
}
TEST_CASE("emit_cbnz_x_placeholder X3") {
    EXPECT_ENC(cbnz_x_placeholder(X3), expect_cbnz(3));
}

// ---- emit_ret / nop / null / nop_vf / wait_vf ----
TEST_CASE("emit_ret encodes 0xD65F03C0") {
    EXPECT_ENC(ret(), expect_ret);
}
TEST_CASE("emit_nop encodes ARM64 NOP") {
    EXPECT_ENC(nop(), expect_nop);
}
TEST_CASE("emit_null encodes ARM64 NOP placeholder") {
    EXPECT_ENC(null(), expect_nop);
}
TEST_CASE("emit_nop_vf encodes ARM64 NOP") {
    EXPECT_ENC(nop_vf(), expect_nop);
}
TEST_CASE("emit_wait_vf encodes ARM64 NOP") {
    EXPECT_ENC(wait_vf(), expect_nop);
}

// ---- emit_call_r64 — the A6/A19 multi-word callee-save sequence ----
TEST_CASE("emit_call_r64 X12 emits seven-word sequence (A19: X12 now in save set)") {
    auto e = call_r64(X12);
    // Primary word: STP x3, x5, [sp, #-16]!
    EXPECT_ENC(call_r64(X12), kStpX3X5Push);
    // Six extra words: STP x10/x11 ; STP x12/x23 ; BLR X12 ; LDP x12/x23 ; LDP x10/x11 ; LDP x3/x5
    // A19: word 1 was kStrX23Push, word 3 was kLdrX23Pop. Now both pair X12 with X23.
    EXPECT_EXTRA_WORDS(call_r64(X12), 6);
    EXPECT_EXTRA_AT(call_r64(X12), 0, kStpX10X11Push);
    EXPECT_EXTRA_AT(call_r64(X12), 1, kStpX12X23Push);
    EXPECT_EXTRA_AT(call_r64(X12), 2, expect_blr(12));
    EXPECT_EXTRA_AT(call_r64(X12), 3, kLdpX12X23Pop);
    EXPECT_EXTRA_AT(call_r64(X12), 4, kLdpX10X11Pop);
    EXPECT_EXTRA_AT(call_r64(X12), 5, kLdpX3X5Pop);
}
TEST_CASE("emit_call_r64 X9 changes only BLR target") {
    EXPECT_EXTRA_AT(call_r64(X9), 2, expect_blr(9));
    EXPECT_EXTRA_AT(call_r64(X9), 0, kStpX10X11Push);  // unchanged
    EXPECT_EXTRA_AT(call_r64(X9), 5, kLdpX3X5Pop);     // unchanged
}

// ---- emit_push_gpr64 / emit_pop_gpr64 — pre-/post-indexed [SP, #-16]! ----
TEST_CASE("emit_push_gpr64 X3 — STR X3, [SP, #-16]!") {
    // From IGenARM64.cpp: Base(0b1111100000000000000011, 22) | Imm9(-16) | Rn(SP=31) | Rt(reg)
    // → 0xF8000000 | 0xC00 | ((-16 & 0x1FF) << 12) | (31 << 5) | 3
    // -16 & 0x1FF = 0x1F0, shifted by 12 = 0x1F0000
    constexpr uint32_t expect = 0xF8000C00u | 0x1F0000u | (31u << 5) | 3u;
    EXPECT_ENC(push_gpr64(X3), expect);
}
TEST_CASE("emit_pop_gpr64 X3 — LDR X3, [SP], #16") {
    // Base(0b1111100001000000000001, 22) | Imm9(16) | Rn(SP=31) | Rt(reg)
    constexpr uint32_t expect = 0xF8400400u | (16u << 12) | (31u << 5) | 3u;
    EXPECT_ENC(pop_gpr64(X3), expect);
}

// ---- emit_adr_placeholder / emit_adrp_placeholder ----
TEST_CASE("emit_adr_placeholder X3") {
    // ADR base 0x10000000.
    EXPECT_ENC(adr_placeholder(X3), 0x10000000u | 3u);
}
TEST_CASE("emit_adrp_placeholder X3") {
    // ADRP base 0x90000000.
    EXPECT_ENC(adrp_placeholder(X3), 0x90000000u | 3u);
}

// ---- emit_ldr_x_literal_placeholder ----
TEST_CASE("emit_ldr_x_literal_placeholder X3") {
    // LDR Xt, =literal base 0x58000000.
    EXPECT_ENC(ldr_x_literal_placeholder(X3), 0x58000000u | 3u);
}
