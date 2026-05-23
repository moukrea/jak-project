// Encoding tests for the A6 sym-PTR resolution path.
//
// The A6 fix rewrites mov_gpr64_gpr64(dst, X14) into a PAIR of instructions:
// the original ORR (mov) + a SUB Xd, Xd, X15 to convert the X14-held HOST
// pointer into the GOAL OFFSET expected by C FFI helpers. Same fixup applies
// to lea_reg_plus_off when the base is X14.
//
// These tests pin the EXACT paired emission shape that satisfies both the
// HOST and GOAL semantics expected by the C FFI helpers (format_impl_jak1,
// jak1_finish, etc.).

#include "test_helpers.h"

namespace {

// ORR Xd, XZR, Xm → MOV Xd, Xm (aliased form) — base 0xAA000000 with Rn=31.
constexpr uint32_t expect_mov_orr(uint32_t rd, uint32_t rm) {
    return 0xAA000000u | (rm << 16) | (31u << 5) | rd;
}
// SUB Xd, Xn, Xm shifted-register — base 0xCB000000.
constexpr uint32_t expect_sub_xxx(uint32_t rd, uint32_t rn, uint32_t rm) {
    return 0xCB000000u | (rm << 16) | (rn << 5) | rd;
}
// ADD Xd, Xn, #imm12 — base 0x91000000.
constexpr uint32_t expect_add_imm12(uint32_t rd, uint32_t rn, uint32_t imm12) {
    return 0x91000000u | ((imm12 & 0xfffu) << 10) | (rn << 5) | rd;
}
// SUB Xd, Xn, #imm12 — base 0xD1000000.
constexpr uint32_t expect_sub_imm12(uint32_t rd, uint32_t rn, uint32_t imm12) {
    return 0xD1000000u | ((imm12 & 0xfffu) << 10) | (rn << 5) | rd;
}

}  // namespace

// ---- emit_mov_gpr64_gpr64 with X14 src → paired ORR + SUB X15 fixup ----
TEST_CASE("emit_mov_gpr64_gpr64 X3 X14 → ORR + SUB X3 X3 X15") {
    EXPECT_ENC(mov_gpr64_gpr64(X3, X14), expect_mov_orr(3, 14));
    EXPECT_EXTRA_WORDS(mov_gpr64_gpr64(X3, X14), 1);
    EXPECT_EXTRA_AT(mov_gpr64_gpr64(X3, X14), 0, expect_sub_xxx(3, 3, 15));
}
TEST_CASE("emit_mov_gpr64_gpr64 X8 X14 → ORR + SUB X8 X8 X15") {
    EXPECT_ENC(mov_gpr64_gpr64(X8, X14), expect_mov_orr(8, 14));
    EXPECT_EXTRA_AT(mov_gpr64_gpr64(X8, X14), 0, expect_sub_xxx(8, 8, 15));
}

// X14→X14 special case — no fixup (would be a no-op self-copy).
TEST_CASE("emit_mov_gpr64_gpr64 X14 X14 → unpaired (self-copy)") {
    EXPECT_EXTRA_WORDS(mov_gpr64_gpr64(X14, X14), 0);
    EXPECT_ENC(mov_gpr64_gpr64(X14, X14), expect_mov_orr(14, 14));
}

// Other sources — no fixup, just regular ORR.
TEST_CASE("emit_mov_gpr64_gpr64 X3 X5 → single ORR no fixup") {
    EXPECT_ENC(mov_gpr64_gpr64(X3, X5), expect_mov_orr(3, 5));
    EXPECT_EXTRA_WORDS(mov_gpr64_gpr64(X3, X5), 0);
}
TEST_CASE("emit_mov_gpr64_gpr64 X3 X15 → single ORR no fixup") {
    EXPECT_ENC(mov_gpr64_gpr64(X3, X15), expect_mov_orr(3, 15));
    EXPECT_EXTRA_WORDS(mov_gpr64_gpr64(X3, X15), 0);
}

// ---- emit_lea_reg_plus_off with X14 base → paired ADD + SUB X15 fixup ----
TEST_CASE("emit_lea_reg_plus_off X3 X14 +32 → ADD imm12 + SUB X3 X3 X15") {
    EXPECT_ENC(lea_reg_plus_off(X3, X14, 32), expect_add_imm12(3, 14, 32));
    EXPECT_EXTRA_WORDS(lea_reg_plus_off(X3, X14, 32), 1);
    EXPECT_EXTRA_AT(lea_reg_plus_off(X3, X14, 32), 0, expect_sub_xxx(3, 3, 15));
}
TEST_CASE("emit_lea_reg_plus_off X3 X14 -16 → SUB imm12 + SUB X3 X3 X15") {
    // Negative offset → sub_x_imm12 instead of add_x_imm12.
    EXPECT_ENC(lea_reg_plus_off(X3, X14, -16), expect_sub_imm12(3, 14, 16));
    EXPECT_EXTRA_AT(lea_reg_plus_off(X3, X14, -16), 0, expect_sub_xxx(3, 3, 15));
}

// X14→X14 self-LEA — no fixup.
TEST_CASE("emit_lea_reg_plus_off X14 X14 +32 → unpaired") {
    EXPECT_EXTRA_WORDS(lea_reg_plus_off(X14, X14, 32), 0);
}

// Other bases — no fixup, just regular ADD imm12.
TEST_CASE("emit_lea_reg_plus_off X3 X5 +32 → single ADD no fixup") {
    EXPECT_ENC(lea_reg_plus_off(X3, X5, 32), expect_add_imm12(3, 5, 32));
    EXPECT_EXTRA_WORDS(lea_reg_plus_off(X3, X5, 32), 0);
}
TEST_CASE("emit_lea_reg_plus_off32 X3 X15 +32 → single ADD no fixup") {
    EXPECT_ENC(lea_reg_plus_off32(X3, X15, 32), expect_add_imm12(3, 15, 32));
    EXPECT_EXTRA_WORDS(lea_reg_plus_off32(X3, X15, 32), 0);
}
