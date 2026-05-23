// test_call_r64_saves.s — A6 call_r64 caller-side callee-saved preservation.
//
// The A6 fix wraps every BLR in STP/STR pushes and LDP/LDR pops of the GOAL
// "saved" GPRs (X3=RBX, X5=RBP, X10=R10, X11=R11) and X23 (a callee-saved
// register that goalc never assigns but the C FFI uses for canary state).
// A callee can freely clobber all five inside the BLR; the pre/post-index
// stack pops restore them. This test verifies bit-exactly that the seven-
// word sequence call_r64 emits actually preserves those five registers
// when the called function deliberately writes 0xDEAD into each.

.include "lib_common.s"

.text
.global _start
_start:
    // Seed the "live" GOAL saved regs with recognisable patterns.
    movz    x3,  #0xAAAA, lsl #0
    movz    x5,  #0xBBBB, lsl #0
    movz    x10, #0xCCCC, lsl #0
    movz    x11, #0xDDDD, lsl #0
    movz    x23, #0xEEEE, lsl #0

    // Replicate the exact A6 call_r64 sequence byte-for-byte. These are
    // the constants from goalc/emitter/IGenARM64.cpp's call_r64() helper.
    //   stp x3, x5,  [sp, #-16]!
    //   stp x10, x11, [sp, #-16]!
    //   str x23,     [sp, #-16]!
    //   blr Xn
    //   ldr x23,     [sp], #16
    //   ldp x10, x11, [sp], #16
    //   ldp x3, x5,  [sp], #16
    adr     x12, callee_that_clobbers
    stp     x3,  x5,  [sp, #-16]!
    stp     x10, x11, [sp, #-16]!
    str     x23,      [sp, #-16]!
    blr     x12
    ldr     x23,      [sp], #16
    ldp     x10, x11, [sp], #16
    ldp     x3,  x5,  [sp], #16

    // After the bracketed BLR, the "saved" regs must be back to their
    // pre-call values.
    EXPECT_EQ_OR_FAIL x3,  0xAAAA
    EXPECT_EQ_OR_FAIL x5,  0xBBBB
    EXPECT_EQ_OR_FAIL x10, 0xCCCC
    EXPECT_EQ_OR_FAIL x11, 0xDDDD
    EXPECT_EQ_OR_FAIL x23, 0xEEEE

    PASS_AND_EXIT
FAIL_LABEL

// callee_that_clobbers — writes 0xDEAD into every register the call_r64
// stack-bracket promises to preserve, then returns. If the preserving
// stack-pops are wrong the caller's checks above will SEE 0xDEAD.
callee_that_clobbers:
    movz    x3,  #0xDEAD, lsl #0
    movz    x5,  #0xDEAD, lsl #0
    movz    x10, #0xDEAD, lsl #0
    movz    x11, #0xDEAD, lsl #0
    movz    x23, #0xDEAD, lsl #0
    ret
