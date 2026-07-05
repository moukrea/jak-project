// Gswamp-fstore round-trip proof — asm glue.
// Drives the REAL _mips2c_call_arm64 trampoline (GOAL-ABI entry, not AAPCS) and
// provides a fake "GOAL callee" that materialises #f the way goalc does (x14-x15).
    .text

// int64_t drive_mips2c(void* body, uint64_t pp, uint64_t st_host, uint64_t off, uint64_t stack_sz)
//   x0=body  x1=pp  x2=st_host  x3=off  x4=stack_sz
// Loads the GOAL ABI registers exactly as goalc-emitted code would before a
// mips2c call (x16=body, x12=fake-stack-size, x13/x14/x15=pp/st/off, GOAL args
// x7,x6,x2,x1,x8,x9,x10,x11 = 0) then `bl _mips2c_call_arm64`.
    .global drive_mips2c
    .type drive_mips2c, %function
drive_mips2c:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x16, x0          // body ptr
    mov x13, x1          // pp   (capture before zeroing arg regs)
    mov x14, x2          // st_host (arm64 live st = HOST addr of symbol table)
    mov x15, x3          // off  (EE base)
    mov x12, x4          // fake GOAL stack size
    mov x7,  xzr         // GOAL args = 0
    mov x6,  xzr
    mov x1,  xzr
    mov x2,  xzr
    mov x8,  xzr
    mov x9,  xzr
    mov x10, xzr
    mov x11, xzr
    bl  _mips2c_call_arm64
    ldp x29, x30, [sp], #16
    ret
    .size drive_mips2c, .-drive_mips2c

// int64_t goal_probe()  — a bare "GOAL function" reached through _call_goal8_asm_arm64.
// On entry the trampoline has set x14 = st + off (host symtab) and x15 = off.
// It returns #f exactly as goalc emits it: MOV dst,x14 ; SUB dst,dst,x15.
    .global goal_probe
    .type goal_probe, %function
goal_probe:
    sub x0, x14, x15     // #f = x14 - x15  (== symtab GOAL offset iff x14 is correct)
    ret
    .size goal_probe, .-goal_probe
