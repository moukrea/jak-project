// Phase A3 — AArch64 syscall-only harness for qemu-aarch64-static.
//
// Layout:
//   _start performs:
//     1. mmap(0x40000000, 0x10000, PROT_READ|PROT_WRITE,
//             MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED, -1, 0)
//        so tests can use 0x40000000 as a scratch buffer.
//     2. Zero out the GOAL-convention registers the codegen depends on:
//          X4  — alias the codegen uses for "RSP-as-source" (see IGenARM64
//                comment about treating allocator id 4 as ARM64 X4).
//          X15 — the GOAL offset register (allocator id 15 = R15 in x86,
//                arm64 maps to X15 here).
//        and zero X22 for completeness (the symbol-table register on x86).
//     3. BL test_fn — the GOAL-emitted function bytes are appended right
//        after this harness in the linker output.
//     4. exit(x0) — the test function leaves its int return value in x0
//        (the GOAL ARM64 codegen returns via RAX = arm64 X0), which is
//        already in the right place for the AArch64 exit syscall.
//
// No libc; this binary is static and meant to run under qemu-aarch64-static.

.section .text
.global _start
_start:
    // mmap(0x40000000, 0x10000, RW, PRIVATE|ANON|FIXED, -1, 0)
    mov     x0, #0x4000              // addr_hi = 0x4000 ...
    lsl     x0, x0, #16              // ... << 16  → 0x40000000
    mov     x1, #0x10000             // length 64 KB
    mov     x2, #3                   // PROT_READ | PROT_WRITE
    mov     x3, #0x32                // MAP_PRIVATE(2)|MAP_ANON(0x20)|MAP_FIXED(0x10)
    mov     x4, #-1                  // fd
    mov     x5, #0                   // offset
    mov     x8, #222                 // __NR_mmap
    svc     #0

    // Zero the GOAL convention regs. After mmap, x4 holds -1 (we passed it
    // as fd argument); we MUST reset it to 0 here because the arm64 codegen
    // uses x4 as the GOAL "stack-pointer alias" in IR_GetStackAddr /
    // IR_RegValAddr emit paths.
    mov     x4,  #0
    mov     x15, #0
    mov     x22, #0

    // Call the GOAL test function. The linker glues its raw arm64 bytes
    // immediately after this stub (see build_a3_diff.sh).
    bl      test_fn

    // Exit with the function's return value (already in x0).
    mov     x8, #93                  // __NR_exit
    svc     #0

.global test_fn
test_fn:
    // The harness build script appends the GOAL-emitted function bytes
    // here via .incbin in a generated wrapper. This empty stub is here so
    // a "just the harness" link still produces a parseable ELF; in the
    // real build we ALWAYS overwrite the body via the generated wrapper.
    ret
