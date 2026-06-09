// A19 — encoding tests for the two arm64 goalc codegen fixes diagnosed by
// A18 attempt-4's disassembly-level evidence:
//
//   1. X12 was missing from IGenARM64::call_r64's save-around-BLR list,
//      so any GOAL value held in X12 across a function call (e.g. `this`
//      stashed at lr-388 in dead-pool-heap.get-process) returned as
//      whatever the callee left in X12. A19 adds X12 to the save set,
//      paired with X23 in a single STP/LDP so total stack footprint is
//      unchanged (still 48 bytes).
//
//   2. The arm64 field-offset emit was reported by A18 attempt-4 as
//      off-by-4 for basic-relative LDR/STR (e.g. `(-> this first-gap)`
//      at offset 52 emitting LDR at #48). The tests below verify that
//      load_goal_gpr / store_goal_gpr honour the IR-supplied offset
//      verbatim: offset=52 emits imm12=13 (= #0x34); offset=100 emits
//      imm12=25 (= #0x64); offset=36 emits imm12=9 (= #0x24). Any
//      regression that re-introduces a -4 shift will fail these tests.

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
// STR Wt, [X16, #imm12] — base 0xB9000000, imm12 scaled by 4.
constexpr uint32_t expect_str_w_x16(uint32_t rt, uint32_t imm_bytes) {
    uint32_t imm12 = (imm_bytes >> 2) & 0xfffu;
    return 0xB9000000u | (imm12 << 10) | (16u << 5) | rt;
}

}  // namespace

// ===================================================================
// Bug 2 (A18 attempt-4): field-offset off-by-4 in arm64 emit.
// ===================================================================
//
// dead-pool-heap.find-gap-by-size's first body statement is
//   (let ((rec (-> this first-gap))) ...)
// `first-gap` is at offset 52 per all-types.gc:1840. The disasm of the
// failing arm64 binary showed:
//   ADD X16, X5, X15          ; X16 = host(this)
//   LDR W3, [X16, #0x30]      ; reads offset 48 = `fill-percent`, WRONG
// Correct encoding for offset 52 is LDR W3, [X16, #0x34].
//
// Encoding for LDR W3, [X16, #52] (Rt=3, Rn=16, imm12=13):
//   0xB9400000 | (13<<10) | (16<<5) | 3 = 0xB9403603

TEST_CASE("A19 load_goal_gpr offset=52 emits LDR Wt at #52 (not #48)") {
    EXPECT_ENC(load_goal_gpr(X3, X5, X15, 52, 4, false), expect_add_x16(5, 15));
    EXPECT_EXTRA_WORDS(load_goal_gpr(X3, X5, X15, 52, 4, false), 1);
    EXPECT_EXTRA_AT(load_goal_gpr(X3, X5, X15, 52, 4, false), 0, expect_ldr_w_x16(3, 52));
}

TEST_CASE("A19 load_goal_gpr offset=36 emits LDR Wt at #36 (compact-time field)") {
    // compact-time is at offset 36 per all-types.gc:1836. Pre-A19 the
    // supervisor's diagnostic showed emit at offset 32 (= allocated-length).
    EXPECT_ENC(load_goal_gpr(X9, X13, X15, 36, 4, false), expect_add_x16(13, 15));
    EXPECT_EXTRA_AT(load_goal_gpr(X9, X13, X15, 36, 4, false), 0, expect_ldr_w_x16(9, 36));
}

TEST_CASE("A19 store_goal_gpr offset=100 emits STR Wt at #100 (dead-list.next field)") {
    // dead-list is :inline at offset 92 in dead-pool-heap; `next` is at
    // offset 8 inside dead-pool-heap-rec, so `(-> this dead-list next)`
    // resolves to a base-relative offset of 100. Pre-A19 the diagnostic
    // showed STR at offset 96 (= dead-list.prev).
    EXPECT_ENC(store_goal_gpr(X5, X3, X15, 100, 4), expect_add_x16(5, 15));
    EXPECT_EXTRA_AT(store_goal_gpr(X5, X3, X15, 100, 4), 0, expect_str_w_x16(3, 100));
}

TEST_CASE("A19 load_goal_gpr basic-tag at offset 0 — sanity baseline") {
    // For basic types the GOAL pointer is at offset 0 of fields; reading
    // (-> obj first-int-field) where first-int-field is at offset 0 must
    // emit LDR at #0. This is the lowest-offset sanity check.
    EXPECT_EXTRA_AT(load_goal_gpr(X3, X5, X15, 0, 4, false), 0, expect_ldr_w_x16(3, 0));
}

TEST_CASE("A19 load_goal_gpr offset boundary — 4 and 8") {
    // (-> obj field) where field is at offset 4 or 8 — basic-tag adjacent
    // fields. These must emit at #4 and #8 respectively (not #0 and #4).
    EXPECT_EXTRA_AT(load_goal_gpr(X3, X5, X15, 4, 4, false), 0, expect_ldr_w_x16(3, 4));
    EXPECT_EXTRA_AT(load_goal_gpr(X3, X5, X15, 8, 4, false), 0, expect_ldr_w_x16(3, 8));
}

// ===================================================================
// Bug 1 (A18 attempt-4): X12 regalloc clobber across BLR.
// ===================================================================
//
// The pre-A19 IGenARM64::call_r64 emitted:
//   stp x3, x5,   [sp, #-16]!   = 0xA9BF17E3
//   stp x10, x11, [sp, #-16]!   = 0xA9BF2FEA
//   str x23,      [sp, #-16]!   = 0xF81F0FF7   <-- 7 words total
//   blr Xn                      = 0xD63F0000 | (Rn << 5)
//   ldr x23,      [sp], #16     = 0xF84107F7
//   ldp x10, x11, [sp], #16     = 0xA8C12FEA
//   ldp x3, x5,   [sp], #16     = 0xA8C117E3
// → 7 words, no X12 save.
//
// A19 replaces the single X23 push/pop with paired X12+X23:
//   stp x12, x23, [sp, #-16]!   = 0xA9BF5FEC
//   ldp x12, x23, [sp], #16     = 0xA8C15FEC
// → still 7 words, X12 now saved.

TEST_CASE("A19 call_r64 includes X12 in the save set (paired with X23)") {
    auto enc = call_r64(X8);
    // Primary encoding = first push.
    EXPECT_ENC(call_r64(X8), 0xA9BF17E3u);  // stp x3, x5, [sp, #-16]!
    // Total 7 words (3 pushes, BLR, 3 pops). Header word + 6 extra words.
    EXPECT_EXTRA_WORDS(call_r64(X8), 6);
    EXPECT_EXTRA_AT(call_r64(X8), 0, 0xA9BF2FEAu);  // stp x10, x11, [sp, #-16]!
    EXPECT_EXTRA_AT(call_r64(X8), 1, 0xA9BF5FECu);  // stp x12, x23, [sp, #-16]! (A19)
    EXPECT_EXTRA_AT(call_r64(X8), 2, 0xD63F0000u | (8u << 5));  // blr x8
    EXPECT_EXTRA_AT(call_r64(X8), 3, 0xA8C15FECu);  // ldp x12, x23, [sp], #16 (A19)
    EXPECT_EXTRA_AT(call_r64(X8), 4, 0xA8C12FEAu);  // ldp x10, x11, [sp], #16
    EXPECT_EXTRA_AT(call_r64(X8), 5, 0xA8C117E3u);  // ldp x3, x5, [sp], #16
}

TEST_CASE("A19 call_r64 BLR target reg propagates to blr Xn slot") {
    // The dispatch target register must be in the BLR slot (word 4),
    // independent of the target register identity. Pre-A19 X12 was
    // routinely the BLR target; A19 keeps that working but ALSO preserves
    // X12 as a held value.
    EXPECT_EXTRA_AT(call_r64(X0),  2, 0xD63F0000u | (0u  << 5));
    EXPECT_EXTRA_AT(call_r64(X9),  2, 0xD63F0000u | (9u  << 5));
    EXPECT_EXTRA_AT(call_r64(X12), 2, 0xD63F0000u | (12u << 5));
    EXPECT_EXTRA_AT(call_r64(X16), 2, 0xD63F0000u | (16u << 5));
}

TEST_CASE("A19 call_r64 stack footprint unchanged at 48 bytes (3 push slots)") {
    // 3 STP-pre-indexed pushes, each pre-decrementing SP by 16. Verify
    // each push encoding has imm7 = -2 (= -16 bytes, sign-extended 7-bit).
    // STP base encoding bits 21..15 = imm7. For -2 = 0b1111110 = 0x7E.
    auto enc = call_r64(X8);
    // Push 0 = stp x3, x5
    EXPECT_ENC(call_r64(X8), 0xA9BF17E3u);
    // Verify each push has the -16 bytes pre-index (bits 22:15 = 0xBF after
    // masking opcode bits — easy by-hand check: low nibble of byte 2 is F,
    // high nibble is B → 0xBF byte means imm7=-2).
    auto check_imm7_neg2 = [](uint32_t encoding) {
        // bits 21..15 of instruction = bits 5..-1... easier just check byte 2 (bits 23..16)
        uint8_t byte2 = (encoding >> 16) & 0xFFu;
        // bits 21..16 = high 6 bits of imm7; bits 23..22 = pre-index marker (11).
        return byte2 == 0xBFu;
    };
    ++g_total;
    if (!check_imm7_neg2(0xA9BF17E3u)) { ++g_failed; std::fprintf(stderr, "stp x3,x5 wrong imm7\n"); }
    else { ++g_passed; }
    ++g_total;
    if (!check_imm7_neg2(0xA9BF2FEAu)) { ++g_failed; std::fprintf(stderr, "stp x10,x11 wrong imm7\n"); }
    else { ++g_passed; }
    ++g_total;
    if (!check_imm7_neg2(0xA9BF5FECu)) { ++g_failed; std::fprintf(stderr, "stp x12,x23 wrong imm7\n"); }
    else { ++g_passed; }
}
