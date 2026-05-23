# A8 — display.gc NULL fn-ptr BLR: root-cause analysis

Authored 2026-05-23. Qemu-aarch64-static reproduction of the device
crash (A6-attempt-4-blocker.md) succeeded; the trace now identifies
the underlying compiler bug in detail and a NEW pinpointed fix
location.

## TL;DR

**Failing symbol / call site:** the BLR-to-NULL fires inside the
JIT'd top-level of `display.gc`, in the `(new 'global 'font-context …)`
expansion (display.gc:243-244):

```lisp
(define *font-context*
  (new 'global 'font-context *font-default-matrix* 0 24 0.0
       (font-color default) (font-flags shadow kerning)))
```

The call dispatches via `(method-of-type font-context 'new)` →
`MemoryDerefVal` → `IR_LoadConstOffset(re=V_function, offset=16,
base=type_ptr, info)`. The LDR for method 0 of font-context lands
in `W2`; arg2 of the call (`*font-default-matrix*`'s value) must also
end up in X2 (GOAL ABI arg2). Their live ranges overlap.

**Root cause (codegen-level):** `CodeGenerator::do_goal_function_arm64`
in `goalc/compiler/CodeGenerator.cpp:404-440` emits **NOPs**
(`0xd503201f`) for every spill load and spill store the register
allocator requests. The relevant lines:

```cpp
for (const auto& op : bonus.ops) {
  if (op.load) {
    m_gen.add_instr(emitter::InstructionARM64(0xd503201fu), i_rec);  // spill load placeholder
  }
}
ir->do_codegen_arm64(&m_gen, allocs, i_rec);
for (const auto& op : bonus.ops) {
  if (op.store) {
    m_gen.add_instr(emitter::InstructionARM64(0xd503201fu), i_rec);  // spill store placeholder
  }
}
```

The comment on line 397-399 acknowledges the gap:

> No stack pointer manipulation for spills: we don't generate spill
> load/store ops on the arm64 path. If a function ever needs spills
> the regalloc will assert and we'll know to expand this.

…but the regalloc doesn't assert; it silently inserts the bonus ops
and CodeGenerator silently emits NOPs. Values that need to be spilled
(the function-pointer for `(new …)` calls being the most common) are
**lost** — the register holding the value gets reused for an arg by
the arg shuffle, and the "reload" before the BLR is a no-op so the
register retains whatever the arg shuffle / constant load wrote to
it. For our case that value is `0` (from the `MOVZ X0, #0` emitted
for the literal `0` arg3 in the `new`-form), so `BLR X3` (after
`MOV X3, X0; ADD X3, X3, X15`) jumps to `X15` = `g_ee_main_mem` =
offset 0 of the EE memory map. The 0x00000000 bytes at the start of
the EE map decode as `UDF #0` → SIGILL.

## Evidence (qemu repro)

`.autoport/lib/qemu_repro.sh` builds + runs `gk` under
`qemu-aarch64-static -L /usr/aarch64-linux-gnu` with the extended
boot path (KERNEL+ENGINE+GAME CGOs, `LINK_FLAG_EXECUTE` on for all)
and a SIGSEGV/SIGILL diag handler that mirrors Android's
`gk_sigsegv_diag` shape. One run ~30 s.

Crash dump:

```
GK-DIAG sig=4 fault=0x2123000000 pc=0x2123000000 lr=0x2126ab7c9c
GK-DIAG x0=0x0
GK-DIAG x3=0x2123000000
GK-DIAG x15=0x2123000000   ; EE base
GK-DIAG x6=0x549b54        ; font-context type ptr (heap)
GK-DIAG x14=0x2123193…     ; s7 (sym table base)
```

Reverse-decode of the bytes around LR (the BLR is at `lr-4 = BLR X3`):

```
lr-104 @ 0x2126ab7c34 = 0xd2800000  MOVZ  X0, #0           ; IR_LoadConstant64(X0, 0)  = arg3
lr-100 @ 0x2126ab7c38 = 0xd2800303  MOVZ  X3, #0x18        ; IR_LoadConstant64(X3, 24) = arg4
lr-96  @ 0x2126ab7c3c = 0x1c000017  LDR   S23, [PC, #0]   ; LDR-literal — separately broken (imm19=0)
lr-92  @ 0x2126ab7c40 = 0xd2800005  MOVZ  X5, #0           ; IR_LoadConstant64(X5, 0)  = arg6 (font-color default)
lr-88  @ 0x2126ab7c44 = 0xd280006c  MOVZ  X12, #3          ; IR_LoadConstant64(X12, 3) = arg7 (font-flags)
lr-84  @ 0x2126ab7c48 = 0x90fe54f0  ADRP  X16, page        ; A5 sym-MEM for 'font-context
lr-80  @ 0x2126ab7c4c = 0x912a3210  ADD   X16, X16, #lo12
lr-76  @ 0x2126ab7c50 = 0xb9400202  LDR   W2,  [X16, #0]   ; X2 = font-context type ptr
lr-72  @ 0x2126ab7c54 = 0x8b0f0050  ADD   X16, X2, X15     ; X16 = host(X2) = type host addr
lr-68  @ 0x2126ab7c58 = 0xb9401202  LDR   W2,  [X16, #16]  ; X2 = method-table[0]  ← V_function def
lr-64  @ 0x2126ab7c5c = 0xd503201f  NOP                    ; **spill STORE of V_function (X2) — emitted as NOP!**
lr-60  @ 0x2126ab7c60 = 0xaa0903e7  MOV   X7, X9           ; arg shuffle starts
lr-56  @ 0x2126ab7c64 = 0xaa0803e6  MOV   X6, X8
lr-52  @ 0x2126ab7c68 = 0xaa0103e2  MOV   X2, X1           ; **X2 OVERWRITTEN — V_function lost**
lr-48  @ 0x2126ab7c6c = 0xaa0003e1  MOV   X1, X0
lr-44  @ 0x2126ab7c70 = 0xaa0303e8  MOV   X8, X3
lr-40  @ 0x2126ab7c74 = 0xaa1703e9  MOV   X9, X23
lr-36  @ 0x2126ab7c78 = 0xaa0503ea  MOV   X10, X5
lr-32  @ 0x2126ab7c7c = 0xaa0c03eb  MOV   X11, X12
lr-28  @ 0x2126ab7c80 = 0xd503201f  NOP                    ; **spill LOAD of V_function → X0 — emitted as NOP!**
lr-24  @ 0x2126ab7c84 = 0xaa0003e3  MOV   X3, X0           ; IR_RegSet temp_function ← V_function (X0=0 because reload was NOP)
lr-20  @ 0x2126ab7c88 = 0x8b0f0063  ADD   X3, X3, X15      ; IR_FunctionCall: ADD freg, freg, X15
lr-16  @ 0x2126ab7c8c = 0xa9bf17e3  STP   X3, X5, [SP,#-16]!   ; call_r64 prologue
lr-12  @ 0x2126ab7c90 = 0xa9bf2fea  STP   X10,X11,[SP,#-16]!
lr-8   @ 0x2126ab7c94 = 0xf81f0ff7  STR   X23,[SP,#-16]!
lr-4   @ 0x2126ab7c98 = 0xd63f0060  BLR   X3                ; ← SIGILL: X3 = 0 + X15 = EE base
```

The two NOPs at `lr-64` and `lr-28` are spill store and spill load
respectively. Both are `0xd503201f`. The register allocator's
intention:
- Spill store (lr-64): save `X2` (= V_function = method ptr) to a
  stack slot before the arg shuffle touches X2.
- Spill load (lr-28): restore from the stack slot into V_function's
  final allocated register (`X0` per the trace, which then
  `MOV X3, X0` propagates).

Both are emitted as NOPs. X0's value when the IR_RegSet emit-reads it
= the most-recent write to X0 = `MOVZ X0, #0` (lr-104, the literal 0
for arg3). So freg = 0, BLR via `X15 + 0` lands at the EE base, which
holds zeros, decoded as `UDF #0`.

## Cross-reference: existing partial mitigation

`goalc/compiler/compilation/Function.cpp:654-674`
(`compile_real_function_call`) already documents the same bug
class:

```cpp
#ifdef GOALC_BACKEND_ARM64
// A6 attempt 7+ (arm64-only): emit the function-ptr IR_RegSet BEFORE
// the arg IR_RegSets so that the `function` ireg (deref result) has a
// short live range (def→IR_RegSet) and doesn't span the arg shuffle.
// The `temp_function` ireg then becomes the long-lived function-pointer
// holder, properly marked as a function crosser (live + read at
// IR_FunctionCall), and gets saved-first allocation. Without this
// reorder the `function` ireg's range crosses all arg setups; the
// arm64 regalloc spills it to stack and the spill load/store emit as
// NOPs (CodeGenerator::do_goal_function_arm64), silently losing the
// function pointer. The BLR then fires with the wrong (or 0) value.
```

That workaround is in place, but is insufficient when the arg list
itself contains a deref-style argument (here `*font-default-matrix*`'s
sym-MEM load). The intermediate `function` ireg's lifetime is short,
but `temp_function` STILL gets spilled because there aren't enough
saved registers (only X3/X5/X12 are "saved" per the x86-shaped
RegisterInfo) to hold the function pointer through 8 arg setups
plus a deref chain.

## The fix's location

`goalc/compiler/CodeGenerator.cpp:425-440` — the bonus.ops loop.

The NOPs at line 430 (spill load) and line 437 (spill store) must be
replaced with real `LDR Xt, [SP, #spill_off]` and `STR Xt, [SP,
#spill_off]` instructions. The prologue at line 412-421 must reserve
real stack space (`SUB SP, SP, #frame_size`) instead of emitting a
NOP. The epilogue at line 442-449 must un-reserve (`ADD SP, SP,
#frame_size`).

The spill slot index is in `op.slot`, the register is `op.reg`. The
relevant `op` struct is `BonusOps::Op` in
`goalc/regalloc/Allocator.h` — already populated by the regalloc.

The implementation pattern (in pseudocode):

```cpp
constexpr int kSpillSlotSize = 8;  // 64-bit values
int frame_bytes = std::max(allocs.stack_slots_for_spills,
                           allocs.stack_slots_for_vars) * kSpillSlotSize;
// 16-byte aligned for AArch64.
frame_bytes = (frame_bytes + 15) & ~15;
if (frame_bytes) {
  // SUB SP, SP, #frame_bytes (imm12 — emit as ADRP-style if >4095)
  m_gen.add_instr_no_ir(f_rec,
      emitter::InstructionARM64(0xD1000000u | ((frame_bytes & 0xFFFu) << 10)
                                | (31u << 5) | 31u),  // SUB SP, SP, #frame_bytes
      InstructionInfo::Kind::PROLOGUE);
}

// In the per-IR loop:
for (const auto& op : bonus.ops) {
  if (op.load) {
    // LDR Xt, [SP, #slot*8]
    uint32_t imm12 = (op.slot * kSpillSlotSize / 8) & 0xFFFu;
    uint32_t Rt = arm64_reg5(op.reg);  // or similar
    m_gen.add_instr(emitter::InstructionARM64(
        0xF9400000u | (imm12 << 10) | (31u << 5) | Rt), i_rec);
  }
}
ir->do_codegen_arm64(&m_gen, allocs, i_rec);
for (const auto& op : bonus.ops) {
  if (op.store) {
    uint32_t imm12 = (op.slot * kSpillSlotSize / 8) & 0xFFFu;
    uint32_t Rt = arm64_reg5(op.reg);
    m_gen.add_instr(emitter::InstructionARM64(
        0xF9000000u | (imm12 << 10) | (31u << 5) | Rt), i_rec);
  }
}

// Epilogue:
if (frame_bytes) {
  m_gen.add_instr_no_ir(f_rec,
      emitter::InstructionARM64(0x91000000u | ((frame_bytes & 0xFFFu) << 10)
                                | (31u << 5) | 31u),  // ADD SP, SP, #frame_bytes
      InstructionInfo::Kind::EPILOGUE);
}
```

(For `frame_bytes > 0xFFF` the SUB/ADD needs a 2-instruction form or
a scratch-reg materialise; for our case `display.gc`'s biggest spill
function has ~16 slots = 128 bytes, well under 0xFFF.)

## Why this is outside A8's narrow unlock

A8's scope explicitly UNLOCKS:
- `goalc/emitter/IGenARM64.cpp` (broader, if a different emit helper has a bug)
- `goalc/emitter/ObjectGenerator.cpp` (narrow, if a klink-time fixup is wrong)
- `game/kernel/common/klink.cpp` / `game/kernel/jak1/klink.cpp`
- `game/kernel/jak1/kscheme.cpp`

…and explicitly STILL-LOCKS `goalc/compiler/CodeGenerator.{cpp,h}`. The
phase prompt's "Honest exit condition" anticipates this exact case:

> If after a reasonable retry budget … the bug isn't fixed, the honest
> outcome is an A8-attempt-N-blocker.md report describing what the
> per-BLR trace identified and why fixing it requires further unlock
> (potentially extending IR.cpp or CodeGenerator.cpp).

The bug IS in `CodeGenerator.cpp`. None of the narrowly-unlocked files
can fix it:
- IGenARM64.cpp emitter helpers don't control prologue/epilogue/spill
  emission — that's CodeGenerator's job.
- ObjectGenerator.cpp just buffers instructions; it doesn't know which
  NOPs are spill ops.
- klink.cpp patches per-symbol references; it can't synthesise spill
  load/store with the correct slot index.
- kscheme.cpp is the runtime; the bug is in the emitted bytecode, not
  the runtime patcher.

Function.cpp's `compile_real_function_call` already has the partial
arm64 mitigation; extending it to fully avoid spills via inline-asm
emit would require a new IR type (locked, IR.cpp).

## Recommendation to the supervisor

Extend A8 (or create A9) with:
1. `goalc/compiler/CodeGenerator.cpp` unlocked.
2. Implement real `LDR Xt, [SP, #imm]` / `STR Xt, [SP, #imm]` for the
   bonus.ops loop, plus real `SUB/ADD SP, SP, #frame` in prologue/
   epilogue.
3. Re-run the qemu repro (`.autoport/lib/qemu_repro.sh`) — should
   reach engine.gc top-level / past display.gc.
4. Re-run D4 device validator. With spills working, `(new …)` calls
   stop NULL-derefing, display.gc top-level completes, *display* is
   created, allocate-dma-buffers runs, and the renderer reaches the
   SDL/GL bring-up (≥ 3/5 markers).

A separate but related bug, visible in the same trace: the LDR-literal
at `lr-96` has `imm19 = 0` (loads from itself). The
`klink_arm64_patch_pc_rel` LDR-literal branch can't reach the literal
pool when it's > 1 MB away (engine.gc + game.gc inflate the heap
distance). Either move literal pools closer (compiler change) or
patch via ADRP+ADD into a scratch reg (runtime klink change). This
likely needs follow-up after the spill fix lands.

## What this attempt delivered

1. `.autoport/lib/qemu_repro.sh` — cross-build + qemu run + GK-DIAG
   capture. Wall-clock ~30 s per cycle. Reproduces the device crash
   bit-exact (same MOVZ X0,#0 / MOV X3, X0 / BLR X3 sequence).
2. `game/linux-arm64/linux_arm64_main.cpp` — extended to load
   ENGINE.CGO + GAME.CGO with `LINK_FLAG_EXECUTE`. Installs SIGSEGV/
   SIGILL/SIGBUS handler that emits the same `GK-DIAG …` line shape
   as the device.
3. `game/linux-arm64/linux_arm64_runtime_compat.cpp` — minimal
   `jak1::InitMachineScheme_LinuxArm64Stubs()` registering kernel C
   funcs (cpad-open, put-display-env, install-handler, the scf-get-*
   set, etc.) against no-op stub bodies. Without this, pad.gc's
   `(define *cpad-list* (new 'global 'cpad-list))` would NULL-deref
   on the first cpad-open call (separate problem from the
   display.gc bug; needed for the qemu repro to even reach display).
4. `game/kernel/jak1/klink.cpp` — `OG_KLINK_TRACE=1` diagnostic
   logging in `symlink_v3` that prints every patched symbol's name
   + slot + value cell + pre-patch encoding. Off by default.

The fix itself is NOT applied — it requires CodeGenerator.cpp which is
locked.
