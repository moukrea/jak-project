// Encoding tests for the A5 far-reloc + A6 MOVZ/MOVK paths.
//
// The A5 sym-mem marker is the sentinel encoding the IGen emit step writes
// when ObjectGenerator::add_instr will later expand to an ADRP+ADD+LDR/STR
// triplet. The marker's exact bit layout matters — ObjectGenerator decodes
// the kind+Rt back out of these bits. Any drift here silently breaks every
// sym-table access in the linked program.

#include "test_helpers.h"
#include "common/link_types.h"

namespace {

// A5 sym-mem marker — bits 31..16=0x0000, 15..12=0xA, 11..8=kind, 4..0=Rt.
constexpr uint32_t kA5SymMemMarker = 0x0000A000u;
constexpr uint32_t kA5KindLoad32U = 1u;
constexpr uint32_t kA5KindLoad32S = 2u;
constexpr uint32_t kA5KindStore32 = 3u;

constexpr uint32_t expect_sym_marker(uint32_t kind, uint32_t rt) {
    return kA5SymMemMarker | ((kind & 0xfu) << 8) | (rt & 0x1fu);
}

// MOVZ Xd, #imm16, LSL #(shift*16) — base 0xD2800000.
constexpr uint32_t expect_movz(uint32_t rd, uint16_t imm16, uint32_t shift_div16) {
    return 0xD2800000u | ((shift_div16 & 3u) << 21) | ((uint32_t)imm16 << 5) | rd;
}
// MOVK Xd, #imm16, LSL #(shift*16) — base 0xF2800000.
constexpr uint32_t expect_movk(uint32_t rd, uint16_t imm16, uint32_t shift_div16) {
    return 0xF2800000u | ((shift_div16 & 3u) << 21) | ((uint32_t)imm16 << 5) | rd;
}

}  // namespace

// ---- emit_load32s sym-PTR rewrite: offset == LINK_SYM_NO_OFFSET_FLAG ----
// load32s_gpr64_gpr64_plus_gpr64_plus_s32 with the sentinel offset →
// a5_sym_mem_marker(kind=2, Rt=dst). Other offsets follow the regular LDRSW path.
TEST_CASE("emit_load32s sym-mem marker (LINK_SYM_NO_OFFSET_FLAG) → load32s marker") {
    int64_t sentinel = (int64_t)(int32_t)LINK_SYM_NO_OFFSET_FLAG;
    EXPECT_ENC(load32s_gpr64_gpr64_plus_gpr64_plus_s32(X3, X5, X9, sentinel),
               expect_sym_marker(kA5KindLoad32S, 3));
}
TEST_CASE("emit_load32u sym-mem marker (LINK_SYM_NO_OFFSET_FLAG) → load32u marker") {
    int64_t sentinel = (int64_t)(int32_t)LINK_SYM_NO_OFFSET_FLAG;
    EXPECT_ENC(load32u_gpr64_gpr64_plus_gpr64_plus_s32(X3, X5, X9, sentinel),
               expect_sym_marker(kA5KindLoad32U, 3));
}
TEST_CASE("emit_store32 sym-mem marker (LINK_SYM_NO_OFFSET_FLAG) → store32 marker") {
    int64_t sentinel = (int64_t)(int32_t)LINK_SYM_NO_OFFSET_FLAG;
    EXPECT_ENC(store32_gpr64_gpr64_plus_gpr64_plus_s32(X5, X9, X3, sentinel),
               expect_sym_marker(kA5KindStore32, 3));
}

// Different Rt registers — marker preserves Rt in low 5 bits.
TEST_CASE("emit_load32s sym-marker preserves Rt=X7") {
    int64_t sentinel = (int64_t)(int32_t)LINK_SYM_NO_OFFSET_FLAG;
    EXPECT_ENC(load32s_gpr64_gpr64_plus_gpr64_plus_s32(X7, X5, X9, sentinel),
               expect_sym_marker(kA5KindLoad32S, 7));
}
TEST_CASE("emit_load32s sym-marker preserves Rt=X18") {
    int64_t sentinel = (int64_t)(int32_t)LINK_SYM_NO_OFFSET_FLAG;
    EXPECT_ENC(load32s_gpr64_gpr64_plus_gpr64_plus_s32(X18, X5, X9, sentinel),
               expect_sym_marker(kA5KindLoad32S, 18));
}

// ---- emit_movz_gpr64_imm16_lsl / movk_gpr64_imm16_lsl (the MOVZ+MOVK pair) ----
// Used by the A6 sym-PTR resolution path: dst = MOVZ #lo16 ; MOVK #lo16, lsl#16 ;
//                                                MOVK #hi16, lsl#32 ; ...
TEST_CASE("emit_movz_gpr64_imm16_lsl X3 #0x1234 LSL 0") {
    EXPECT_ENC(movz_gpr64_imm16_lsl(X3, 0x1234, 0), expect_movz(3, 0x1234, 0));
}
TEST_CASE("emit_movz_gpr64_imm16_lsl X3 #0xABCD LSL 16") {
    EXPECT_ENC(movz_gpr64_imm16_lsl(X3, 0xABCD, 1), expect_movz(3, 0xABCD, 1));
}
TEST_CASE("emit_movz_gpr64_imm16_lsl X3 #0xFFFF LSL 32") {
    EXPECT_ENC(movz_gpr64_imm16_lsl(X3, 0xFFFF, 2), expect_movz(3, 0xFFFF, 2));
}
TEST_CASE("emit_movz_gpr64_imm16_lsl X3 #0x1 LSL 48") {
    EXPECT_ENC(movz_gpr64_imm16_lsl(X3, 0x1, 3), expect_movz(3, 0x1, 3));
}
TEST_CASE("emit_movk_gpr64_imm16_lsl X3 #0x1234 LSL 0") {
    EXPECT_ENC(movk_gpr64_imm16_lsl(X3, 0x1234, 0), expect_movk(3, 0x1234, 0));
}
TEST_CASE("emit_movk_gpr64_imm16_lsl X3 #0xABCD LSL 16") {
    EXPECT_ENC(movk_gpr64_imm16_lsl(X3, 0xABCD, 1), expect_movk(3, 0xABCD, 1));
}
TEST_CASE("emit_movk_gpr64_imm16_lsl X3 #0xFFFF LSL 32") {
    EXPECT_ENC(movk_gpr64_imm16_lsl(X3, 0xFFFF, 2), expect_movk(3, 0xFFFF, 2));
}
TEST_CASE("emit_movk_gpr64_imm16_lsl X3 #0x1 LSL 48") {
    EXPECT_ENC(movk_gpr64_imm16_lsl(X3, 0x1, 3), expect_movk(3, 0x1, 3));
}

// ---- emit_mov_gpr64_u32 / emit_mov_gpr64_u64 / emit_mov_gpr64_s32 ----
// All three emit the low-16 MOVZ; the IR codegen path follows up with MOVK
// shifts when the full constant doesn't fit in 16 bits.
TEST_CASE("emit_mov_gpr64_u64 X3 #0xCAFEBABEDEADBEEF → MOVZ low-16") {
    EXPECT_ENC(mov_gpr64_u64(X3, 0xCAFEBABEDEADBEEFULL),
               expect_movz(3, 0xBEEF, 0));
}
TEST_CASE("emit_mov_gpr64_u32 X3 #0xDEADBEEF → MOVZ low-16") {
    EXPECT_ENC(mov_gpr64_u32(X3, 0xDEADBEEFu), expect_movz(3, 0xBEEF, 0));
}
TEST_CASE("emit_mov_gpr64_s32 X3 #-1 → MOVZ low-16 of two's complement") {
    EXPECT_ENC(mov_gpr64_s32(X3, -1), expect_movz(3, 0xFFFF, 0));
}

// ---- emit_static_addr — ADRP placeholder (the materialise-page-of-sym path) ----
TEST_CASE("emit_static_addr X3 +0 → ADRP placeholder X3") {
    EXPECT_ENC(static_addr(X3, 0), 0x90000000u | 3u);
}
TEST_CASE("emit_static_addr X3 +1024 → still ADRP placeholder X3 (offset patched)") {
    EXPECT_ENC(static_addr(X3, 1024), 0x90000000u | 3u);
}

// ---- emit_adrp_placeholder / emit_adr_placeholder (the lower-level emitters) ----
TEST_CASE("emit_adrp_placeholder X14") {
    EXPECT_ENC(adrp_placeholder(X14), 0x90000000u | 14u);
}
TEST_CASE("emit_adr_placeholder X14") {
    EXPECT_ENC(adr_placeholder(X14), 0x10000000u | 14u);
}

// ---- A5 imm12 overflow guard — for valid offsets the marker is NOT emitted ----
TEST_CASE("emit_load32s normal offset=0 does NOT emit sym-mem marker") {
    // 0xB9400000 = LDR Wt, [Xn, #0]
    // Wait: load32s uses LDRSW Xt, base 0xB9800000.
    // ldrsw_x_imm(X3, X5, 0): 0xB9800000 | 0 | (5<<5) | 3 = 0xB98000A3
    auto r = load32s_gpr64_gpr64_plus_gpr64_plus_s32(X3, X5, X9, 0);
    ++g_total;
    if ((r.encoding & 0xFFFFF0E0u) == kA5SymMemMarker) {
        std::fprintf(stderr,
            "  FAIL %s:%d: load32s with offset=0 wrongly emitted sym-mem marker\n",
            __FILE__, __LINE__);
        ++g_failed;
    } else {
        ++g_passed;
    }
}
TEST_CASE("emit_load32u normal offset=4 does NOT emit sym-mem marker") {
    auto r = load32u_gpr64_gpr64_plus_gpr64_plus_s32(X3, X5, X9, 4);
    ++g_total;
    if ((r.encoding & 0xFFFFF0E0u) == kA5SymMemMarker) {
        std::fprintf(stderr,
            "  FAIL %s:%d: load32u offset=4 wrongly emitted sym-mem marker\n",
            __FILE__, __LINE__);
        ++g_failed;
    } else {
        ++g_passed;
    }
}
