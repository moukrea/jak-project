// Phase B2 — qemu-aarch64 decode-stress harness.
//
// A single static aarch64 ELF that hosts ALL functions of one CGO
// concatenated together. argv[1] is parsed as a decimal function index;
// the harness branches to the indexed function with a "safe exit"
// trampoline in x30.
//
// Exit code → classification (per .autoport/lib/b2_stress.py):
//   0..127  : function returned cleanly with that value
//   137     : timeout (sent by the python driver, not by this harness)
//   132     : SIGILL  — qemu translated the function but the host CPU
//             (or qemu's arm64 emulator) couldn't decode it: a real
//             encoder bug
//   139     : SIGSEGV — function dereferenced something invalid; per
//             B2 spec this is tolerated as long as it occurs post-
//             prologue (proven by construction: the kernel-provided
//             stack guarantees `stp x29, x30, [sp, #-16]!` cannot fail)
//   200     : harness arg error (missing or non-decimal argv[1])
//   201     : index out of range
//
// The per-CGO data segment defines:
//   fn_count    : u32, number of functions
//   fn_offsets  : u32[fn_count], byte offset of each function inside fn_base
//   fn_base     : raw concatenated function bytes (16-byte aligned per fn)
//
// These three symbols are emitted by .autoport/lib/b2_wrap_fn.py into a
// per-CGO data .S that is assembled separately and linked together with
// this harness.

.section .text
.global _start
.type _start, %function
_start:
    // ---- Parse argv[1] as a decimal index ----
    // At _start, sp points to argc; argv begins at sp+8.
    //   sp+0  : argc
    //   sp+8  : argv[0] pointer
    //   sp+16 : argv[1] pointer  ← what we want
    ldr     x9, [sp, #16]
    cbz     x9, .Lerr_args

    mov     x10, #0                  // x10 = parsed index
    mov     w12, #10
.Lparse_loop:
    ldrb    w11, [x9], #1
    cbz     w11, .Lparse_done
    sub     w11, w11, #'0'
    cmp     w11, #9
    b.hi    .Lerr_args
    mul     x10, x10, x12
    add     x10, x10, x11, uxtb
    b       .Lparse_loop
.Lparse_done:

    // ---- Bounds-check vs fn_count ----
    adrp    x9, fn_count
    add     x9, x9, :lo12:fn_count
    ldr     w9, [x9]
    cmp     x10, x9, uxtw
    b.hs    .Lerr_range

    // ---- Compute function address ----
    //   addr = fn_base + fn_offsets[x10]
    adrp    x9, fn_offsets
    add     x9, x9, :lo12:fn_offsets
    ldr     w11, [x9, x10, lsl #2]   // w11 = offset

    adrp    x9, fn_base
    add     x9, x9, :lo12:fn_base
    add     x16, x9, x11, uxtw       // x16 = absolute function address
                                     // (use x16 = IP0; safe to clobber)

    // ---- Map a 64 KB scratch buffer at 0x40000000 ----
    // Several GOAL IRs use base+offset addressing through registers
    // (x4, x15, x22); giving them a writable, readable page means more
    // functions execute deeper before tripping SIGSEGV — which is the
    // whole point of decode-stress.
    mov     x0, #0x4000              // hi(addr) = 0x4000
    lsl     x0, x0, #16              // x0 = 0x40000000
    mov     x1, #0x10000             // length = 64 KB
    mov     x2, #3                   // PROT_READ | PROT_WRITE
    mov     x3, #0x32                // MAP_PRIVATE|MAP_ANON|MAP_FIXED
    mov     x4, #-1                  // fd
    mov     x5, #0                   // offset
    mov     x8, #222                 // __NR_mmap
    svc     #0

    // ---- Seed GOAL convention registers ----
    // x15 is the GOAL "offset register" (R15 in the x86 IR, used by
    // load/store-with-offset IRs). x22 is the legacy slot kept for
    // symmetry with Register.h's comment-mapping. Pointing both at the
    // middle of the mmap'd buffer means base+small-offset loads land in
    // mapped memory, so the function gets to exercise more of its body.
    mov     x9, #0x4000
    lsl     x9, x9, #16
    add     x9, x9, #0x8000          // x9 = 0x40008000
    mov     x15, x9
    mov     x22, x9

    // ---- Zero the AAPCS arg regs (zero-arg call, per spec) ----
    mov     x0, #0
    mov     x1, #0
    mov     x2, #0
    mov     x3, #0
    mov     x4, #0
    mov     x5, #0
    mov     x6, #0
    mov     x7, #0

    // ---- Set link register and branch in ----
    // x30 = safe_exit ensures `ret` (or any branch via x30) returns
    // here cleanly.
    adr     x30, safe_exit
    br      x16

.global safe_exit
.type safe_exit, %function
safe_exit:
    // Function returned. x0 holds its return value; clamp to 8 bits so
    // the process exit code stays in the "exited cleanly" band.
    and     x0, x0, #0xff
    mov     x8, #94                  // __NR_exit_group
    svc     #0

.Lerr_args:
    mov     x0, #200
    mov     x8, #94
    svc     #0

.Lerr_range:
    mov     x0, #201
    mov     x8, #94
    svc     #0
.size _start, .-_start
