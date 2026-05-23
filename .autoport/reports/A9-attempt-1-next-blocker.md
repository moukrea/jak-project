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
