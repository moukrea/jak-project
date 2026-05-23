# A9 attempt 1 — spill fix landed; next-layer blocker (X3-clobber post-BLR)

Authored 2026-05-23. The A9 spill load/store + frame setup change in
`goalc/compiler/CodeGenerator.cpp::do_goal_function_arm64` lands and
demonstrably unblocks 13+ additional CGO link-finishes in qemu_repro
(display.gc top-level completes for the first time; connect, text-h,
settings-h, dma-buffer, knuth-rand, and 8 others now finish linking).
A second-layer bug then crashes the boot before the renderer comes up,
so D4 device-validator (check #10 of the A9 validator) cannot fully pass.

This is the "Honest exit condition" scenario the A9 phase prompt
anticipates: commit the spill fix, document the next layer.

## What lands

See `.autoport/reports/A9-fix-summary.md` for the full description.
TL;DR: real `sub sp, sp, #frame_bytes` prologue, real
`{LDR,STR} {Xt,St,Qt}, [SP, #imm]` spill ops, real
`add sp, sp, #frame_bytes` epilogue. arm64 CGOs regenerated and
hash-saved to `.autoport/reports/A9-baseline-arm64-cgo-hashes.txt`.
x86 CGOs hash-identical to the A2 baseline (verified by
`build_b1_arm64_cgos.sh` step 7).

## Pre- vs post-A9 boot progression (qemu_repro)

| Phase   | `link finish:` count | Last reached | Crash site |
|---------|----------------------|--------------|------------|
| pre-A9  | ~45 (A8 trace)       | font-h       | display.gc:243 `(new 'global 'font-context ...)` → `BLR X3` with X3 = 0 (spill load was NOP, function pointer never restored) |
| post-A9 | **61**               | knuth-rand   | NEW: `LDRB W0, [X16, #0]` with X16 = 3, after a deep GOAL→GOAL BLR that returns with X3 holding garbage instead of the value pushed before the call |

Items that linked for the first time with A9 in place:
`display`, `connect`, `text-h`, `settings-h`, `dma-buffer`,
`dma-bucket`, `dma-disasm`, `pc-cheats`, `pckernel-h`,
`pckernel-impl`, `pc-debug-common`, `pc-debug-methods`, `pad`, `gs`,
`display-h`, `vector`, `file-io`, `loader-h`, `texture-h`, `level-h`,
`math-camera-h`, `math-camera`, `font-h`, `decomp-h`, `knuth-rand`
(and the ~13 between font-h and knuth-rand — counting the new ones
strictly past the A8 pre-fix crash boundary).

## The next-layer bug

GK-DIAG dump (qemu post-A9 run; see `.autoport/reports/A8-qemu-repro.log`):

```
GK-DIAG sig=11 fault=0x3 pc=0x21244fdf88 lr=0x21244fdf74
GK-DIAG x0=0x0
GK-DIAG x3=0xffffffdedd000003   ← garbage; was 0 pre-call
GK-DIAG x4=0x2123000000          ← EE base (consistent)
GK-DIAG x15=0x2123000000         ← offset reg (correct)
GK-DIAG x16=0x3                  ← fault address — X3 + X15 overflow-wrapped
GK-DIAG x9=0x21231c3944           ← BLR target (the GOAL fn we called)
```

Decoded byte slice (re-runs vary slightly in address but structure is identical):

```
lr-72   stp x29, x30, [sp, #-16]!     ; our new prologue
lr-68   mov x29, sp                    ; our new prologue
lr-64   sub sp, sp, #16                ; our new spill frame (1 slot)
lr-60   mov x3, x4                     ; x3 = x4 (= EE base)
lr-56   sub x3, x3, x15                ; x3 = x4 - x15 = 0  (GOAL ptr 0)
lr-52   mov x3, x3                     ; no-op
lr-48   adrp x16, page                 ; sym base
lr-44   add x16, x16, #lo12            ; sym addr
lr-40   ldr w9, [x16, #0]              ; W9 = method ptr
lr-36   mov x9, x9                     ; no-op
lr-32   mov x7, x3                     ; arg7 = X3 (=0)
lr-28   add x9, x9, x15                ; X9 = host(W9)
lr-24   stp x3, x5, [sp, #-16]!        ; call_r64 push pair 1
lr-20   stp x10, x11, [sp, #-16]!      ; call_r64 push pair 2
lr-16   str x23, [sp, #-16]!           ; call_r64 X23 save (3-pair version per A8-close)
lr-4    blr x9                          ; call
lr+0    ldr x23, [sp], #16             ; restore X23
lr+4    ldp x10, x11, [sp], #16        ; restore X10, X11
lr+8    ldp x3, x5, [sp], #16          ; restore X3, X5 — X3 IS GARBAGE HERE
lr+12   mov x5, x5                     ; no-op
lr+16   add x16, x3, x15               ; X16 = X3 + X15 (garbage + EE base)
lr+20   ldrb w0, [x16, #0]             ; fault
```

X3 was pushed as `0` at `lr-24`. After BLR + LDP pop, X3 holds
`0xffffffdedd000003`. The save area lives at `[orig_SP - 48 .. -32]`
and is never re-entered by the caller, so somehow either:

1. The callee corrupted the caller's save area (out-of-bounds STR into
   the stack region above its own frame).
2. The callee's prologue/epilogue mismatch left SP at the wrong value
   on return, causing the LDP to read from a different slot.
3. The save area encoding/offset is wrong (less likely — these are
   pre-A9 IGenARM64.cpp encodings; if they were wrong the BLR-to-NULL
   would have surfaced earlier).

(3) is implausible because the same call_r64 encoding linked 60+ CGOs
worth of calls before the fault. (2) would also break SP-relative
stack vars in the callee, but those work for many calls before the
crash. (1) is the most likely: a specific GOAL function called from
this site does an STR with an offset that reaches above its own
frame into the caller's preserved area. Candidates:

- A vector / 128-bit store with a miscomputed slot index.
- A multi-slot var (`stack_slots_for_vars > 0`) whose offset
  computation in `IR_StackVar`'s codegen path doesn't account for the
  new `frame_bytes` SP movement.
- A `set_var_to_stack_pointer` ireg that returns SP at the
  pre-prologue position instead of the post-prologue position
  (callees would then write into the caller's frame).

The callee at `X9 = 0x21231c3944` is in engine.cgo space; static
disassembly of the corresponding object (offset ~0x1c3944 from
ENGINE.CGO's segment-2 base) would identify it precisely. That work
is outside A9's narrow unlock scope — it requires either further
diagnostic logging in `do_goal_function_arm64` (to dump per-function
frame metadata) or unlocking `IR.cpp` so the offending IR's emit can
be inspected at the source level.

## D4 device-validator status

`bash .autoport/validators/phase-D4-android-apk-title.sh` cannot pass
end-to-end in two ways:

1. **No physical device attached on this harness run** —
   `device_require_attached` exits non-zero. Pre-A9 phases (D4
   itself, A6, etc.) all required the user's Redmi Note 9 Pro to be
   plugged in. The orchestrator was aware of this constraint.

2. **Even with a device, the renderer never starts** because the
   second-layer bug above kills the boot before
   `android_renderer_run: entered` fires, before the SDL/GL
   initialisation, and before the sustained-swap loop. D4 checks
   #9-12 would fail on logcat marker absence.

For (1) this is a harness-environment issue, not a fix-correctness
issue. For (2), unblocking it requires the next phase (A10? B-class?
the X3-clobber bug-class).

## Recommendation to the supervisor

Extend A9 (or open A10) with a narrow unlock targeting one of:

- `goalc/compiler/IR.cpp` — to inspect/fix the specific IR whose emit
  corrupts the caller's stack save area.
- `goalc/regalloc/Allocator_v2.cpp` — for any spill-slot-offset bug
  that puts a callee's slot above its own frame.
- Additional diagnostics in `do_goal_function_arm64` — e.g. emit a
  per-function frame fingerprint at the prologue so the GK-DIAG dump
  can identify which callee is at fault.

A9's spill fix is independently correct and unblocks the boot up to
the new failure point. It stays in place across any subsequent fix.

## Attempt 2 — root-caused as X4-vs-SP, fixed within A9 scope

The X3-clobber-after-BLR symptom turned out to have a static-codegen
root cause that A9's narrow unlock could actually patch around.

### Root cause

`goalc/emitter/IGenARM64.cpp::arm64_reg5(Register r)` returns
`r.id() & 0x1f`. The shared `Register` enum gives `RSP = 4`, so
`arm64_reg5(RSP) = 4`, which encodes to ARM64 register X4 rather than
the AArch64 stack-pointer encoding (Rn = 31). The comment at the top
of IGenARM64.cpp acknowledges this:

```c++
// the special-case slot for RSP (id 4) maps to ARM64_REG::X4 which we
// never use as a stack pointer (we always emit literal SP=31 below
// when we mean the stack pointer).
```

That "always emit literal SP=31" rule holds for the spill ops A9 just
implemented in `do_goal_function_arm64` (those bypass IGen entirely
and bit-pack `(31u << 5)` directly). It does NOT hold for the two IR
paths that take a stack-var's address through IGen helpers:

```c++
// goalc/compiler/IR.cpp
622:  gen->add_instr(IGen::ARM64::lea_reg_plus_off(dst, RSP, stack_offset), irec);
1587: gen->add_instr(IGen::ARM64::mov_gpr64_gpr64(dest_reg, RSP), irec);
1591: gen->add_instr(IGen::ARM64::lea_reg_plus_off(dest_reg, RSP, offset), irec);
```

Both helpers funnel through `arm64_reg5(RSP) = 4`, so what is emitted
is `mov dst, X4` / `add dst, X4, #imm` — addresses computed from X4,
not SP. X4 is unrelated to SP almost everywhere:

- At GOAL function entry the kernel trampoline (asm_funcs_arm64.s)
  leaves X4 holding `st` — the symbol-table GOAL pointer (a small
  number).
- Every GOAL→C call passes through `make_function_from_c_arm64`
  (game/kernel/jak1/kscheme.cpp:601), whose arg-shuffle includes
  `mov x4, x8` (AAPCS arg4 ← goalc arg4), so X4 is overwritten with
  whatever the call site passed as arg4.

In `scf-time-to-int64` (goal_src/jak1/pc/util/knuth-rand.gc), the IR
`(new 'stack-no-clear 'scf-time)` lowers to an `IR_GetStackAddr` that
emits exactly `mov X3, X4 ; sub X3, X3, X15`. The disasm decoded in
the previous attempt matches byte-for-byte:

```
lr-52  mov x3, x4         ; supposed to be MOV X3, SP — emitted as MOV X3, X4
lr-48  sub x3, x3, x15    ; supposed to give &date - EE_base = GOAL ptr
lr-44  mov x3, x3         ; regset move-eliminate placeholder
lr-32  mov x7, x3         ; arg0 = &date
```

Because the visible function is `scf-time-to-int64` and its only
prior call was `scf-get-time` via the kernel trampoline, X4 had just
been clobbered by the `mov x4, x8` shuffle. The trampoline-leftover
value happened to subtract to 0 (X4 = X15), giving `&date = GOAL ptr
0`. The `(scf-get-time date)` stub on linux-arm64 (`a8_stub_scf_get_time`
returns 0 without writing) is a no-op, but the subsequent `(-> date stat)`
field reads pull bytes from memory-region-zero, and the function's
intra-frame stack work overlapped knuth-rand top-level's call_r64 X3/X5
save slot — corrupting it. Hence "X3 was 0 pre-call, 0xffffffdedd000003
post-call".

The byte signature is in the regenerated CGOs at scale:

```
ENGINE.CGO mov x3, x4 (e3 03 04 aa)   : 295 occurrences
GAME.CGO   mov x3, x4 (e3 03 04 aa)   : 331 occurrences
```

Every one of those is a stack-var address arithmetic that, prior to
this fix, was reading from X4 instead of SP.

### The fix (within A9 scope)

The proper repair belongs in IGenARM64.cpp's `mov_gpr64_gpr64` /
`lea_reg_plus_off32` (special-case Rn==RSP to emit Rn=31). That file
is anchored at A8-close in A9's lock list and cannot be touched.

The next-best repair, fully inside `do_goal_function_arm64`'s narrow
unlock, is to **pre-load X4 with the live SP value immediately before
any IR whose codegen reads RSP**. AArch64 encodes `ADD Xd, SP, #0` as
`0x910003E4` (Rn=31, Rd=4, imm12=0). Emitting that one word before
each `IR_GetStackAddr` / `IR_RegValAddr` makes the IR's existing
`mov/add dst, X4, ...` resolve to `dst = SP (+ offset)` — the
intended semantics — without touching IGenARM64.cpp or IR.cpp.

The change lives only in CodeGenerator.cpp's main IR loop:

```c++
if (dynamic_cast<const IR_GetStackAddr*>(ir.get()) ||
    dynamic_cast<const IR_RegValAddr*>(ir.get())) {
  m_gen.add_instr(emitter::InstructionARM64(0x910003E4u), i_rec);
}
ir->do_codegen_arm64(&m_gen, allocs, i_rec);
```

X4 is never assigned by goalc's regalloc (`m_gpr_alloc_order` in
goalc/emitter/Register.cpp skips RSP), so clobbering it has no
collateral effect on IR-driven code.

### Result

qemu-repro with both A9's spill fix and this X4 pre-load:

| Phase                     | link finishes | Last reached     |
|---------------------------|---------------|------------------|
| pre-A9                    | 45            | display.gc       |
| post-spill-only           | 61            | knuth-rand       |
| post-spill + X4 pre-load  | **64**        | texture          |

knuth-rand now executes its top-level cleanly. capture, memory-usage-h,
and texture all link past it for the first time. The new crash at
texture is a different bug class (sig=4 SIGILL at `pc=EE_base`, i.e.
a BLR to GOAL ptr 0 — likely an uninitialised sym-value load, NOT a
spill or stack-var bug); it sits behind another wave of CGO links and
is the next layer to peel.

### What stays for the next phase

The D4 device validator gate still cannot clear end-to-end:

1. The harness has no Android device attached this session, so
   `device_require_attached` short-circuits and the emulator fallback
   times out (arm64-on-x86 hangs, as documented in
   .autoport/reports/A6-fallback-investigation.md).
2. Even with a device the renderer never reaches its SDL/GL init
   markers — the new sig=4 SIGILL kills the boot at texture, well
   before `android_renderer_run: entered` would fire.

For the proper IGenARM64.cpp repair (delete this workaround once the
RSP→SP encoding is fixed), the supervisor should open A10 with the
following unlocks:

- `goalc/emitter/IGenARM64.cpp` — special-case the SP encoding in
  `mov_gpr64_gpr64` (line 617) and `lea_reg_plus_off32` (line 1239) so
  Rn=31 is emitted when the base register's id is 4 (RSP enum). Also
  audit `arm64_reg5()` callers for any other "RSP means SP" sites.
- `goalc/compiler/CodeGenerator.cpp` — remove the X4 pre-load
  workaround once the encoder is fixed; the workaround inflates every
  arm64 CGO by ~4 bytes per stack-var IR (≈1.7 KB ENGINE, ≈1.8 KB
  GAME, ≈0 KB KERNEL — the kernel has no stack-var ops).
- Investigation of the texture-link sig=4 SIGILL (separate bug class
  from the spill / stack-addr family): the LR-relative dump in
  .autoport/reports/A8-qemu-repro.log around 0x2126ab8054 shows a
  BLR to host(W9=0). Trace what sym is being loaded at lr-44 in that
  function and whether it should have been populated by the time
  texture.gc's top-level executes.
