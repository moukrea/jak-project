# A9 — CodeGenerator spill ops fix summary

Authored 2026-05-23. Implements real AArch64 spill load/store + frame
setup in `goalc/compiler/CodeGenerator.cpp::do_goal_function_arm64`,
replacing the NOP placeholders that caused the display.gc NULL fn-ptr
BLR identified by A8.

## What was wrong

Pre-A9, every spill emit on the arm64 path was a NOP
(`0xD503201F`):

```cpp
// pre-A9
for (const auto& op : bonus.ops) {
  if (op.load) {
    m_gen.add_instr(emitter::InstructionARM64(0xd503201fu), i_rec);
    // ^ spill load placeholder (NOP)
  }
}
ir->do_codegen_arm64(&m_gen, allocs, i_rec);
for (const auto& op : bonus.ops) {
  if (op.store) {
    m_gen.add_instr(emitter::InstructionARM64(0xd503201fu), i_rec);
    // ^ spill store placeholder (NOP)
  }
}
```

…and the prologue's `sub sp, sp, #frame` was likewise a single NOP
instead of a real allocation. The V2 register allocator faithfully
spilled values to the stack at IRs where pressure exceeded the saved
register pool; the codegen then refused to materialise the
load/store. Consumers of spilled values read whatever stale register
state remained — for display.gc's `(new 'global 'font-context ...)`
expansion that meant the dispatched method's function pointer was
lost, and the eventual `BLR X3` fired with `X15 + 0` = the EE base,
where the zero-filled MMU page decoded as `UDF #0` (SIGILL).

See `.autoport/reports/A8-displaygc-root-cause.md` and
`A6-attempt-5-blocker.md` for the per-instruction trace of the failing
display.gc top-level.

## What changed

`goalc/compiler/CodeGenerator.cpp::do_goal_function_arm64` now emits
real AArch64 frame setup, spill load/store, and frame teardown.
Nothing outside that function is touched.

### Prologue

```
stp x29, x30, [sp, #-16]!     ; save FP/LR, SP -= 16       0xA9BF7BFD
mov x29, sp                   ; FP = SP                     0x910003FD
sub sp, sp, #frame_bytes      ; reserve spill area          (only if > 0)
                              ;   enc = 0xD10003FF | ((frame_bytes & 0xfff) << 10)
```

`frame_bytes = ((stack_slots_for_spills + stack_slots_for_vars) * 8 +
15) & ~15`, i.e. 16-byte-aligned per AArch64 SP requirement. `ASSERT`
guards `frame_bytes <= 0xfff` — display.gc's biggest spilled function
uses ~16 slots = 128 bytes, well inside imm12 range. (If a future
function blows the budget we'll see the assert and add an LSL #12 path.)

### Spill load / store (per IR)

```
LDR Xt, [SP, #byte_off]   0xF9400000 | (imm12_div8  << 10) | (31 << 5) | Rt
STR Xt, [SP, #byte_off]   0xF9000000 | (imm12_div8  << 10) | (31 << 5) | Rt
LDR St, [SP, #byte_off]   0xBD400000 | (imm12_div4  << 10) | (31 << 5) | Rt
STR St, [SP, #byte_off]   0xBD000000 | (imm12_div4  << 10) | (31 << 5) | Rt
LDR Qt, [SP, #byte_off]   0x3DC00000 | (imm12_div16 << 10) | (31 << 5) | Rt
STR Qt, [SP, #byte_off]   0x3D800000 | (imm12_div16 << 10) | (31 << 5) | Rt
```

`byte_off = allocs.get_slot_for_spill(op.slot) * GPR_SIZE`. Spill load
runs before the IR's own codegen (so inputs are restored); spill store
runs after (so outputs are stashed). `Rt = op.reg.id() & 0x1f` — for
GOAL's x86-shaped allocator that maps `RAX..R10` → `X0..X10` for GPRs
and `XMM0..XMM15` → `Q16..Q31` for FPSIMD. Q-reg alignment is
enforced by an `ASSERT` and guaranteed by the V2 allocator's
`slot_size = 2` round-up for `INT_128 / VECTOR_FLOAT` vars.

### Epilogue

```
add sp, sp, #frame_bytes      ; free spill area          (only if > 0)
                              ;   enc = 0x910003FF | ((frame_bytes & 0xfff) << 10)
ldp x29, x30, [sp], #16       ; restore FP/LR, SP += 16   0xA8C17BFD
ret                           ;                           0xD65F03C0
```

## Disassembly evidence

`out/jak1-arm64/iso/{KERNEL,ENGINE,GAME}.CGO` regenerated with the
patched compiler. Hash baseline saved to
`.autoport/reports/A9-baseline-arm64-cgo-hashes.txt`:

```
60ae3ceda828230fa931f306feca5b90a8735ad3e80ccf2fe681ff2f715d5e47  out/jak1-arm64/iso/KERNEL.CGO
f2640b073c7c21e56b1584e174ad28cab8ad5fbd0d34482f10fd7f5a5901642b  out/jak1-arm64/iso/ENGINE.CGO
033f255a36810c5b9d3c2a47c417010be0b4e35aa03d9a5c90fcc4685616f864  out/jak1-arm64/iso/GAME.CGO
```

(Compared to the A6 baseline — `9e9a19e7…` / `38a0806b…` /
`14cf084b…` — every CGO has shifted bytes; the spill ops change is
threaded across hundreds of jak1 functions.)

Slice from the new ENGINE.CGO near a function with a spilled value
(qemu_repro log lines 220-265, addresses in the EE map):

```
0x21245017_94  a9bf7bfd  stp x29, x30, [sp, #-16]!   ← prologue
0x21245017_98  910003fd  mov x29, sp                  ← prologue
0x21245017_9c  d10043ff  sub sp, sp, #16              ← *NEW* — was NOP pre-A9
...
0x21245017_c4  a9bf17e3  stp x3, x5,  [sp, #-16]!     ← call_r64 push
0x21245017_c8  a9bf2fea  stp x10, x11, [sp, #-16]!    ← call_r64 push
0x21245017_cc  a9bf63f7  stp x23, x24, [sp, #-16]!    ← call_r64 push
0x21245017_d0  a9bf6bf9  stp x25, x26, [sp, #-16]!
0x21245017_d4  a9bf73fb  stp x27, x28, [sp, #-16]!
0x21245017_d8  d63f0120  blr x9                       ← real call
0x21245017_dc  a8c173fb  ldp x27, x28, [sp], #16      ← call_r64 pop
...
```

`d10043ff` decodes as `sub sp, sp, #16` (imm12 = (0x43FF >> 10) &
0xFFF = 0x010 = 16): the new spill frame reservation that replaces
the pre-A9 NOP.

## What it unblocks (qemu_repro)

`bash .autoport/lib/qemu_repro.sh` extended boot (KERNEL+ENGINE+GAME
CGOs with `LINK_FLAG_EXECUTE`) before and after the fix:

| Phase | `link finish:` count | Last reached object | Crash site |
|-------|----------------------|---------------------|------------|
| pre-A9 (A8 trace) | ~45 | font-h (display.gc top-level enters but BLRs to NULL) | display.gc:243 `(new 'global 'font-context …)` → `BLR X3=X15+0` |
| post-A9 (this fix) | **61** | knuth-rand (5 objects past display.gc finish) | NEW: `pc=0x21245017f8` LDRB `[X16,#0]` after a deep call (X16 clobbered through BLR — different bug class, see next-blocker doc) |

Objects that linked for the first time with A9 in place include
`display`, `connect`, `text-h`, `settings-h`, `knuth-rand` — the
`FIRST POST-FIX CGO LINKED:` marker emitted by the patched
qemu_repro.sh names `dma-buffer` (the earliest object in the
boundary-set regex that crossed the previous failure line).

## Honest scope of the fix

A9's narrow unlock is `do_goal_function_arm64` only. Other functions
in `CodeGenerator.cpp` are byte-identical. The x86 path
(`do_goal_function_x86`) is unchanged, and the three jak1 x86 CGOs
hash-match the A2 baseline byte-for-byte (verified by
`build_b1_arm64_cgos.sh` step 7 after the regen cycle).

The fix is necessary but not sufficient for full boot: the qemu
trace identifies a new crash class downstream — see
`A9-attempt-1-next-blocker.md` for the analysis. D4 device-validator
re-pass remains gated on that next bug (and on physical-device
availability for the harness running this phase).
