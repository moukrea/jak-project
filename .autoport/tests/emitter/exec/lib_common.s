// lib_common.s — shared macros + helpers for emitter exec tests.
// Each test_*.s includes this and exits via EXIT_WITH.
//
// Tests run under qemu-aarch64-static. The exec-side validates that the
// arm64 byte sequences the emitter helpers produce behave correctly when
// the AArch64 CPU actually executes them — catches semantic bugs that the
// Level-0 encoding tests can miss (e.g. an encoding that's correctly
// hand-derived but happens to have the wrong meaning under AAPCS).

// Linux/AArch64 syscall ABI: x8 = syscall number, args x0..x7, SVC #0.
// SYS_exit = 93. We never use libc — these are minimal static ELFs.

.macro EXIT_WITH val
    mov     x0, \val
    mov     x8, #93         // SYS_exit
    svc     #0
.endm

// EXPECT_EQ_OR_FAIL — compare reg to imm, fall through if equal, exit 1 if not.
.macro EXPECT_EQ_OR_FAIL reg, imm
    ldr     x9, =\imm
    cmp     \reg, x9
    b.ne    fail_path
.endm

// FAIL — terminate the program with exit code 1. Tests jump here on
// detected mismatch.
.macro FAIL_LABEL
fail_path:
    EXIT_WITH #1
.endm

// PASS — terminate with the expected exit code 42 (the convention every
// emitter exec test uses to signal "all assertions passed").
.macro PASS_AND_EXIT
    EXIT_WITH #42
.endm
