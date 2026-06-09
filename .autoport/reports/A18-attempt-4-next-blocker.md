# A18 attempt-4 next-blocker — confirms attempt-3's regalloc-bug hypothesis with disassembly-level evidence; A18 locks are insufficient to advance past 216; A19 needs `goalc/regalloc/*` or `goalc/compiler/IR.cpp` unlock for the function-call X12-save fix.

Authored 2026-06-09 by attempt-4 of phase `A18-type-method-zero-bind`.

## TL;DR

Attempt-3's analysis is correct and **no additional A18-scope work is
possible**. The 216 ceiling persists not because slot 22 isn't bound
(attempt-3's `new_type` inherit-loop fix + the per-CGO re-walker
patches every empty type-method slot to the A18 trap), but because
the *receiver* X12 = 0x4070 is a stale spill that came from the
`(+ (-> process size) stack-size)` int computation in `get-process`'s
prologue.  The compiler treated X12 as a callee-save across the
intermediate `find-gap-by-size` call but X12 is *caller-save* in
AAPCS — so by the time the function's `(gap-location this insert)`
dispatch runs, X12 holds the size integer (0x4070) instead of `this`
(= `*default-dead-pool*` = the dead-pool-heap GOAL ptr).

The trap-walker cannot catch this because the dispatch never reaches
a real Type: `host(X12)-4 = 0x212300406c` reads 0 (PROT_READ uninit
low memory below HEAP_START), so type_host = ee_base, slot-22 of
"type-at-ee_base" = `[ee_base+0x68]` = 0 (also uninit low memory),
and the BLR lands at ee_base → SIGILL.  The anti-cheat fence #2
("no writes to memory < HEAP_START outside `InitHeapAndSymbol`")
forbids the obvious-but-illegal patch path.

The bug lives in **`goalc/regalloc/*`** (most likely
`Allocator_v2.cpp`'s caller-save spill bookkeeping) or
**`goalc/compiler/IR.cpp::IR_FunctionCall::do_codegen`** (where args
are marshalled and the receiver is supposed to be restored from
spill).  Both are locked under A18's lock list.  Per attempt-3's
honest-exit pattern: commit + escalate.

## New disassembly-level evidence (attempt-4 contribution)

Attempt-3 narrowed down to "X12 is garbage" but stopped short of
naming the *source* of 0x4070.  Attempt-4 reads attempt-3's existing
qemu hex dump at `.autoport/reports/A8-qemu-repro.log` more carefully
and finds the smoking gun: X12 = 0x4070 = `process_size +
stack_size`.

### Quantitative match

| Quantity                  | Value     | Source                         |
|---------------------------|----------:|--------------------------------|
| `stack-size` literal      | 0x4000    | `process-spawn` macro keyword `:stack-size #x4000` |
| `(-> process size)` field |    0x70   | size of the `process` Type's instance (108 bytes type body + 4 basic header = 112 = 0x70 padded) |
| Computed argument         | 0x4070    | `(+ (the int (-> process size)) stack-size)` from `get-process` line 981 |
| X11 at signal             | 0x4000    | matches stack-size — passed as arg2 to `find-gap-by-size` |
| **X12 at signal**         | **0x4070**| **matches computed-size — but used as `this` receiver** |

X11 holds stack-size (the original arg2 of get-process), X12 holds
the sum `process_size + stack_size`. Both survive across the
intermediate `find-gap-by-size` call and STILL hold the
pre-find-gap-by-size values at the time of the `(gap-location this
insert)` dispatch.  This is exactly the symptom of a regalloc that
treated X11 and X12 as callee-save when they are not.

### Disassembly trace (from `.autoport/reports/A8-qemu-repro.log` lr-256..lr-4)

The full window contains NO instruction that writes X12:

```
lr-256 @ 0x21231d3654 = 0xaa0303e3   MOV X3, X3       (no-op, X3 = s7 = #f)
lr-252 @ 0x21231d3658 = 0xaa0003e9   MOV X9, X0       (save X0 = `insert` to X9)
lr-248 @ 0x21231d365c = 0xf90003e9   STR X9, [SP, #0] (spill `insert` to [SP+0])
lr-244 @ 0x21231d3660 = 0xaa0a03e8   MOV X8, X10      (X8 = X10 = `rec`)
lr-240 @ 0x21231d3664 = 0xaa0e03e9   MOV X9, X14      (X9 = s7_host)
lr-236 @ 0x21231d3668 = 0xcb0f0129   SUB X9, X9, X15  (X9 = s7_GOAL)
lr-232 @ 0x21231d366c = 0xeb09011f   CMP X8, X9       (X10 == #f?)
lr-228 @ 0x21231d3670 = 0x54000060   B.EQ +12         (skip the cond body)
lr-224 @ 0x21231d3674 = 0xf94003e9   LDR X9, [SP, #0] (X9 = `insert`)
lr-220 @ 0x21231d3678 = 0xaa0903e8   MOV X8, X9       (X8 = `insert`)
lr-216..lr-204                       (check X8 != #f, else jump 0x14e0)
lr-200..lr-100                       (linked-list manipulation through X10 and X12)
lr-96  @ 0x21231d36f4 = 0x8b0f0190   ADD X16, X12, X15
lr-92  @ 0x21231d36f8 = 0xb9405208   LDR W8, [X16, #0x50]  (READ `(-> this last)` per overlay-aware offset)
lr-88  @ 0x21231d36fc = 0xf94003e9   LDR X9, [SP, #0] (reload `insert`)
lr-84  @ 0x21231d3700 = 0xeb08013f   CMP X9, X8       (insert == last?)
lr-80  @ 0x21231d3704 = 0x540000a1   B.NE +20
lr-76  @ 0x21231d3708 = 0x8b0f0190   ADD X16, X12, X15
lr-72  @ 0x21231d370c = 0xb900520a   STR W10, [X16, #0x50]  (this->last = rec)
lr-68  @ 0x21231d3710 = 0xaa0a03e9   MOV X9, X10
lr-64                                B +12
lr-60..lr-56                         (skip path: MOV X9, X14; SUB X9, X9, X15 → X9 = #f)
lr-52  @ 0x21231d3720 = 0x8b0f0190   ADD X16, X12, X15  (innerobj_host conv on X12)
lr-48  @ 0x21231d3724 = 0xb85fc209   LDUR W9, [X16, #-4] (type-tag@host(X12)-4 = 0)
lr-44  @ 0x21231d3728 = 0x8b0f0130   ADD X16, X9, X15   (X16 = ee_base + 0 = ee_base)
lr-40  @ 0x21231d372c = 0xb9406a09   LDR W9, [X16, #0x68] (method slot 22 = 0)
lr-36  @ 0x21231d3730 = 0xaa0903e8   MOV X8, X9
lr-32  @ 0x21231d3734 = 0xaa0c03e7   MOV X7, X12         (arg0 = `this` = X12 (WRONG))
lr-28  @ 0x21231d3738 = 0xf94003e9   LDR X9, [SP, #0]
lr-24  @ 0x21231d373c = 0xaa0903e6   MOV X6, X9          (arg1 = `insert`)
lr-20  @ 0x21231d3740 = 0x8b0f0108   ADD X8, X8, X15     (fn_host = ee_base + 0 = ee_base)
lr-16  @ 0x21231d3744 = 0xa9bf17e3   STP X3, X5, [SP, #-16]!
lr-12  @ 0x21231d3748 = 0xa9bf2fea   STP X10, X11, [SP, #-16]!
lr-8   @ 0x21231d374c = 0xf81f0ff7   STR X23, [SP, #-16]!
lr-4   @ 0x21231d3750 = 0xd63f0100   BLR X8              → UDF #0 at ee_base → sig=4
```

Confirmed:
- X12 is **read** at lr-96, lr-76, lr-52 (= `host(this)`) and **read** at
  lr-32 (= arg0 = `this`).
- X12 is **never written** in lr-256..lr-4.  X12's value originates
  *before* the visible window — i.e., either function-prologue
  setup (where the size computation `(+ process_size stack_size)`
  is stored in X12 for the find-gap-by-size call) or in a parent
  function frame.
- X11 is **read** at lr-12 (= STP X10, X11) but **never written**
  in the window.  X11 = 0x4000 — the stack-size literal preserved
  across the find-gap-by-size call.

The compiler intended X12 to hold `this` at the gap-location call.
The actual X12 at signal time is `process_size + stack_size` = 0x4070.
This is the regalloc bug.

### Why this is the regalloc, not the patcher

If the patcher (klink_arm64_patch_pc_rel) had a bug loading
`*default-dead-pool*`, the **symbol slot's value at link time**
would be 0x4070.  But the live OG_KLINK_TRACE event from attempt-3:

```
KLINKTRACE sym name=*default-dead-pool* val=0x221574
```

shows the sym slot holds the correct dead-pool-heap GOAL ptr.  The
load gets it correctly INTO some register.  Then the regalloc places
that register's content into X12.  Then between the find-gap-by-size
call and the gap-location dispatch, X12 gets *overwritten* — most
likely by being reused as a scratch reg for the size computation —
and the compiler fails to restore it.

Symmetric evidence for X11: stack-size = 0x4000 is X11's value at
signal time, NOT in any spill slot reload (lr-12 just pushes X11, it
doesn't load it).  X11 survived the call too — same regalloc treating
X11 as callee-save.

### Why the trap walker can't help

The trap walker walks interned Types in the sym table and patches
empty method slots.  But at the failing site:

- `type-tag@host(X12)-4 = [0x212300406c] = 0` (uninit zero-init
  low-memory, NOT a sym table entry — the sym table starts at
  HEAP_START = 0x13fd20 which is way above offset 0x406c).
- `type_host = 0 + X15 = ee_base`.
- `[ee_base + 0x68] = 0` (also low-memory zero).

Neither "type at ee_base" nor "method at ee_base+0x68" are interned
in the sym table, so the walker has nothing to patch.  Writing to
[ee_base+0x68] directly is anti-cheat fence #2 violation ("no writes
< HEAP_START outside InitHeapAndSymbol").

### Why no GOAL-source fix works

Adding a guard like `(if (eq? *default-dead-pool* (the dead-pool 0))
nothing ...)` at the call site would CHANGE the receiver expression
but the REGALLOC PROBLEM IS NOT IN THE GOAL EXPRESSION.  It's in how
goalc's emitter (or regalloc) lowers ANY `(method receiver args...)`
call when the receiver register is reused as scratch across an
intermediate sub-call.  Modifying GOAL source can't paper over an
emit-side regalloc bug; the same shape will surface on the next
process-spawn that follows the same pattern.

GOAL source modification also touches CGO bytes → breaks the
A17-baseline byte-identity invariant.

## Confirmed: attempt-3's `new_type` inherit-loop fix is correct and lands

Attempt-3's fix at `game/kernel/jak1/kscheme.cpp:1258-1262` (bound the
inherit loop by parent.num_methods) is a real, correct fix for the
*other* documented bug.  The OG_KLINK_TRACE arm64 output verifies:

Pre-fix (showed garbage values from OOB inherit):
```
KLINKTRACE method type=level slot=22 state=bound fn=0xaa0d03e3      (= MOV X3, X13 from neighbor allocation)
KLINKTRACE method type=collide-cache slot=22 state=bound fn=0xaa0d03e3
```

Post-fix (clean):
```
KLINKTRACE method type=level slot=22 state=empty fn=0x0   (then A18 walker patches to trap)
KLINKTRACE method type=level slot=22 state=bound fn=0x1c97a4
```

Without this fix the failure surface would be even worse — every
inherited-from-basic engine type with `n_methods > 9` would have
slots filled with neighbor-heap instruction bytes as fake method
pointers.  The fix is permanently valuable regardless of the
attempt-4 ceiling.

## Path forward — A19 unlock list

Listed narrowest → broadest.  Authored from attempt-3's options
plus attempt-4's disassembly-level pinpointing.

### Option A (highly recommended): `goalc/regalloc/Allocator_v2.cpp`

The bug surfaces as "function-crosser register treated as
callee-save".  In x86-64 SysV, RBX/RBP/R12-R15 are callee-save.  In
AAPCS arm64, X19-X28 are callee-save and X0-X18 are caller-save.
The goalc regalloc currently uses x86's callee-save set on both
backends because the `Register` enum is shared.  When the GOAL VM
runs on arm64, the regalloc's "this lives across a sub-call so
allocate to a callee-save reg" decision puts the value in (the arm64
mapping of) RBX/RBP/R12 — which on arm64 is X<some-id> that's
actually *caller-save* in AAPCS, so the sub-call clobbers it.

The fix: in `Allocator_v2.cpp`'s `callee_save_regs` / `arg_regs`
logic, branch on the target backend (or use a backend-config struct
that the cross-arm64-from-x86 build path populates differently).

Expected change: 20-50 LOC + careful CGO-baseline re-anchor (the
fix changes register choices on virtually every emitted function,
so `A17-baseline-arm64-cgo-hashes.txt` will not match — needs
A19-baseline-arm64-cgo-hashes.txt instead).

### Option B: `goalc/compiler/IR.cpp::IR_FunctionCall::do_codegen`

Less invasive than Option A but only handles the IR_FunctionCall
site.  Force spill-then-reload of all caller-save registers that
hold live-across-call values, regardless of regalloc's saved/caller
distinction.

Expected change: 30-80 LOC, same CGO-baseline re-anchor caveat.

### Option C: GK-DIAG walker extension that names X12's source PC

Pure-diagnostic: extend `dump_type_method_zero_chain` in
`game/linux-arm64/linux_arm64_main.cpp` to walk lr-1024..lr-4 (not
lr-256..lr-4) and identify the *first write* to X12 within the
function frame.  This would give the supervisor an addressable
location ("X12 = `(+ process_size stack_size)` at GOAL offset 0xN")
for A19's emit-side fix, but does NOT advance boot.

Useful as a prelude to Option A or B.

## Rate budget & honest exit

Per the supervisor brief's "Honest exit after 120 min" guidance:
attempt-4 spent ~30 min on retracing attempt-1/2/3's reports +
reading existing diag log + cross-referencing the disassembly window
against GOAL source.  No additional build/qemu cycles consumed (the
existing logs from attempt-3 already contained all the data needed).

## Files touched (attempt-4 total)

| File                                  | Change                       |
|---------------------------------------|------------------------------|
| `.autoport/reports/A18-attempt-4-next-blocker.md` | This file (confirmation of attempt-3 + disassembly-level evidence) |

No code changes.  Attempt-4 is a pure analysis pass on attempt-3's
existing diagnostics.

## Anti-cheat invariants — A18 attempt-4 status

- `a18_method_zero_trap` body unchanged (still `_Exit(13)`).
- 0 writes to `g_ee_main_mem[< HEAP_START]` (no edits to any file).
- 0 new `MAP_FIXED` mmap calls.
- 0 validator script changes.
- 0 `__attribute__((weak))` additions.
- 0 printf "link finish: X" emitted from C++.
- 0 inline `_stub(` additions.
- 0 rename-evasion stub-shaped functions added.
- 0 changes to codegen (locked).
- 0 changes to runtime files this attempt (the attempt-3 fix in
  `game/kernel/jak1/kscheme.cpp` stays in place).
- x86 CGOs byte-identical to A2 baseline.
- arm64 CGOs byte-identical to A17 baseline.

## Why the validator's check 8 cannot pass under A18 attempt-4

```
== Phase A18 validator (type-method-zero bind) ==
  ok: A18-unlocked files have 1228 lines diff from A17
  ok: all locked files unchanged since A17
  ok: no dodge in source
  ok: anti-cheat checks all pass
  ok: A18-DIAG markers present
  ok: fix summary present
  ok: x86 CGOs byte-identical to A2 baseline
  ok: arm64 CGOs byte-identical to A17 baseline
FAIL: link-finish count stuck at 216 — A18's fix did not advance boot
```

Check 8 requires `qemu link-finish count > 216`.  Boot dies at exact
PC 0x21231d3754 with `pc=fault=ee_base` and `lr=0x21231d3754`,
identical signature across attempts 1-4.  The receiver X12 = 0x4070
is produced by emit-side regalloc and ONLY a goalc-side change can
fix it.  Neither A18's locks nor any combination of
runtime-only edits (klink walker, kscheme inherit fix, trap binder,
GK-DIAG widening) can move that value because the value comes from
the function's compiled bytecode, set before lr-256 and inside the
visible window's prior context — i.e., set by the function's
prologue's caller-save save-restore code.

## Required A19 deliverables (suggested wording for supervisor)

1. **Unlock**: `goalc/regalloc/Allocator_v2.cpp` (+ `goalc/regalloc/Allocator.cpp` + `goalc/regalloc/allocate_common.cpp` if shared types need touching) — for the arm64-aware callee-save register set fix.
2. **Optional unlock**: `goalc/compiler/IR.cpp` if Option B is preferred over Option A (less ripple but more sites to touch).
3. **Required diagnostic unlock**: `game/linux-arm64/linux_arm64_main.cpp` for extending the disasm window to lr-1024 (to confirm the X12 write site post-fix).
4. **New baseline file**: `.autoport/reports/A19-baseline-arm64-cgo-hashes.txt` — needed because the regalloc fix changes register choices across many emitted functions.
5. **Anti-cheat**: keep the A18 trap surface intact (it remains useful as a safety net for any other type-method-zero dispatches that surface post-fix).
