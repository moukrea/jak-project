// test_sym_ptr_movz.s — A6 sym-PTR resolution: MOVZ + 3x MOVK reconstructs
// a 64-bit constant.
//
// The IR_LoadSymbolPointer path uses this sequence to materialise the host
// address of a GOAL symbol slot. If the emitter's MOVZ/MOVK helpers drop
// the LSL shift or zero the imm16, the reconstructed pointer is wrong and
// every subsequent symbol access dereferences garbage. This test asserts
// the four-instruction sequence reconstructs a known 64-bit value bit-exact.

.include "lib_common.s"

.text
.global _start
_start:
    // Reconstruct 0xCAFEBABEDEADBEEF via the exact MOVZ/MOVK pattern the
    // A6 emitter produces for IR_LoadSymbolPointer (the IR_LoadSymbolValue
    // path that resolves to a host address). Matches movz_x_lsl + 3x movk_x_lsl.
    movz    x1, #0xBEEF, lsl #0
    movk    x1, #0xDEAD, lsl #16
    movk    x1, #0xBABE, lsl #32
    movk    x1, #0xCAFE, lsl #48
    EXPECT_EQ_OR_FAIL x1, 0xCAFEBABEDEADBEEF

    // Lower-half-only constant should leave high bits cleared (MOVZ semantics).
    movz    x2, #0x1234, lsl #0
    EXPECT_EQ_OR_FAIL x2, 0x1234

    // MOVK preserves bits NOT in the imm16 window — verify by stacking on
    // top of an already-set x3.
    movz    x3, #0xAAAA, lsl #0
    movk    x3, #0xBBBB, lsl #16
    EXPECT_EQ_OR_FAIL x3, 0xBBBBAAAA

    PASS_AND_EXIT
FAIL_LABEL
