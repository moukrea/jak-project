// test_make_function_arm64.s — minimum-viable arm64 function shape.
//
// The pre-A6 bug class "make_function_from_c emits x86 opcodes" would show
// up as immediate SIGILL when qemu tries to execute the produced bytes —
// x86 opcode bytes are wildly invalid as arm64 instructions. This test
// runs a trivial arm64 function and exits with 42 if it executes; any
// emitter-shape regression that drops back to x86 would crash before
// reaching the exit syscall.

.include "lib_common.s"

.text
.global _start
_start:
    // Materialise 42 into x0 via the exact MOVZ encoding the A6 emitter
    // uses for small constants. mov_gpr64_u64 = MOVZ Xd, #imm16, LSL #0.
    movz    x0, #42, lsl #0
    // SYS_exit: x8 = 93, x0 = status, SVC #0.
    mov     x8, #93
    svc     #0

FAIL_LABEL
