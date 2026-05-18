# Phase 08 — GOAL kernel context switch for AArch64

## Goal

Rewrite the GOAL kernel's thread context-switch and throw/catch implementation for AArch64. Validator: `coroutine` tests pass; `gkernel-test` reaches its main loop tick.

## Background

OpenGOAL's threading model is cooperative: GOAL threads yield voluntarily, and the kernel switches contexts by saving callee-saved registers + stack pointer + program counter to a thread struct, then loading those from another thread's struct.

On x86-64, this lives in:
- `goal_src/jak1/kernel/gkernel.gc` (the GOAL-side scheduler)
- `goal_src/jak1/kernel/gstate.gc` (state machine)
- The x86 trampoline assembly in `game/kernel/` (read these to understand the contract)

The save/restore set is ABI-specific. **You must NOT modify the .gc files** (those are the game source). Instead:

1. Modify the goalc *compiler* to emit AArch64-correct save/restore sequences when it sees the GOAL primitives for context switch.
2. Replace any inline-asm trampolines for AArch64.

## Concrete tasks

1. Audit `goalc/compiler/` for where it emits the x86 save sequence (look for grep `pushaq`, `popaq`, or similar — the goalc-specific naming).
2. Add the arm64 variant: save x19..x29, fp (x29), lr (x30), sp, and all callee-saved v-regs (v8..v15 low 64 bits).
3. The thread-state struct in goal_src defines slot offsets. Confirm these match what arm64 expects and document any size differences.
4. The `throw`/`catch` mechanism: similar register save/restore, but uses setjmp-style longjmp semantics. Mirror.

## Pitfalls

- AArch64 requires 16-byte stack alignment at function boundaries. The save sequence must preserve this.
- LR (x30) is special: it's where the return address lives. Saving/restoring it is what makes a context switch "return" to a different place.
- Don't forget the floating-point status register (FPCR) if any thread modifies it; though defaults match across threads usually.

## Success

The validator boots `gk` (the game kernel binary) under qemu-aarch64 and checks for the message `kernel: thread system online` (or whatever the actual init message is — grep gkernel.gc) in the first 30 seconds of stdout.
