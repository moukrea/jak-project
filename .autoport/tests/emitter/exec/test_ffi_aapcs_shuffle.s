// test_ffi_aapcs_shuffle.s — A6 FFI calling-convention shuffle.
//
// On arm64 the GOAL arg registers happen to be X0..X7, which matches the
// AAPCS arg-register layout exactly — so the simple-case shuffle is the
// identity. The interesting case is when the caller spills/holds GOAL
// args in non-X0..X7 registers and the trampoline must move them into
// the AAPCS slots before the BLR. This test models that: load constants
// into X9..X16, shuffle into X0..X7, BL to a callee that asserts the
// shuffled values match expectations, then exit 42.

.include "lib_common.s"

.text
.global _start
_start:
    // Set up scratch registers as if regalloc had spilled them there.
    movz    x9,  #0x1111, lsl #0
    movz    x10, #0x2222, lsl #0
    movz    x11, #0x3333, lsl #0
    movz    x12, #0x4444, lsl #0
    movz    x13, #0x5555, lsl #0
    movz    x14, #0x6666, lsl #0
    movz    x15, #0x7777, lsl #0
    movz    x16, #0x8888, lsl #0

    // Shuffle into AAPCS arg slots (the trampoline shape).
    mov     x0, x9
    mov     x1, x10
    mov     x2, x11
    mov     x3, x12
    mov     x4, x13
    mov     x5, x14
    mov     x6, x15
    mov     x7, x16

    // Call the verifier — it inspects X0..X7 and exits with PASS/FAIL itself.
    bl      verify_aapcs_args
    // verify_aapcs_args returns iff every slot matched expected; we then
    // exit 42 to signal pass.
    PASS_AND_EXIT

FAIL_LABEL

// Verify the AAPCS arg slots hold the expected values, exit 1 if any mismatch.
verify_aapcs_args:
    EXPECT_EQ_OR_FAIL x0, 0x1111
    EXPECT_EQ_OR_FAIL x1, 0x2222
    EXPECT_EQ_OR_FAIL x2, 0x3333
    EXPECT_EQ_OR_FAIL x3, 0x4444
    EXPECT_EQ_OR_FAIL x4, 0x5555
    EXPECT_EQ_OR_FAIL x5, 0x6666
    EXPECT_EQ_OR_FAIL x6, 0x7777
    EXPECT_EQ_OR_FAIL x7, 0x8888
    ret
