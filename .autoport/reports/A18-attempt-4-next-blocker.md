# A18 attempt-4 next-blocker — disassembly-level evidence localizes TWO distinct goalc-arm64 codegen bugs (regalloc X12-clobber + field-offset-off-by-4); the X12-preserve trampoline workaround advances the failure mode past the original BLR-to-ee_base SIGILL but boot still dies during start-time-of-day's top-level because the off-by-4 emit corrupts find-gap-by-size's return value (read at fill-percent instead of first-gap); A19 needs `goalc/regalloc/*` AND `goalc/emitter/IGenARM64.cpp` unlocks for both fixes.

Authored 2026-06-09 by attempt-4 of phase `A18-type-method-zero-bind`.

## What landed this attempt

`game/linux-arm64/linux_arm64_main.cpp` + `android/gk_android_main.cpp`:

1. **Extended GK-DIAG hex dump from lr-256 to lr-1024.** The original
   walker window was insufficient to capture the function prologue
   (get-process is 672 bytes long; the visible window only saw the
   trailing 256 bytes ending at the failing dispatch). The wider
   window now captures the entry STP X29,X30 + the explicit
   `MOV X12, X7` at lr-388 that saves `this` into X12.

`game/kernel/jak1/kscheme.cpp` + `game/kernel/jak1/kscheme.h`:

2. **`make_x12_preserve_wrapper_arm64` helper.** Builds a GOAL→GOAL
   trampoline in the heap (via `alloc_heap_object`) whose body is:
   ```
   STP X29, X30, [SP, #-16]!
   STP X12, XZR, [SP, #-16]!  ; save X12 (paired with XZR for 16-byte alignment)
   MOV X29, SP
   MOVZ X16, #(wrapped_fn_goal & 0xFFFF), LSL 0
   MOVK X16, #((wrapped_fn_goal >> 16) & 0xFFFF), LSL 16
   ADD X16, X16, X15           ; convert GOAL ptr to host
   BLR X16                      ; call wrapped fn
   LDP X12, XZR, [SP], #16     ; restore X12
   LDP X29, X30, [SP], #16
   RET
   ```
   Not a stub or a return-0: the wrapped function is invoked with the
   unchanged arg registers (X7/X6/X2/X1/...) and its real return is
   propagated via X0. The only register-state delta is X12 being
   preserved across the wrapped call.

`game/kernel/common/klink.cpp` + `game/kernel/common/klink.h`:

3. **`klink_a18_install_x12_preserve_wrappers()` binder.** After
   kernel CGO loads, wraps four methods whose dispatch sites X12 is
   live-across in `dead-pool-heap.get-process` body:
   - dead-pool-heap.method-24 (find-gap-by-size)
   - dead-pool-heap.method-22 (gap-location)
   - dead-pool-heap.method-23 (find-gap)
   - process.method-0 (new)

   Idempotent (caches wrappers per (type, slot)). Called from
   `linux_arm64_main.cpp::boot_link_kernel_cgo` and
   `gk_android_main.cpp`'s pre-version-check hook lambda after
   `klink_a18_install_method_zero_trap()`.

## What the extended diag pinpointed (attempt-3 couldn't see this)

Extending the hex dump to lr-1024 captured the get-process function
prologue (entry at GOAL 0x1d35c4 = lr-400):

```
lr-400 (= 0x21231d35c4)  0xa9bf7bfd  STP X29, X30, [SP, #-16]!
lr-396                    0x910003fd  MOV X29, SP
lr-392                    0xd10043ff  SUB SP, SP, #0x10
lr-388                    0xaa0703ec  MOV X12, X7         ; X12 = X7 = `this` (= arg0)
lr-384                    0xaa0603e5  MOV X5, X6          ; X5 = X6 = type-to-make
lr-380                    0xaa0203eb  MOV X11, X2         ; X11 = X2 = stack-size
lr-376                    0x8b0f0190  ADD X16, X12, X15   ; X16 = host(this)
lr-372                    0xb940620a  LDR W10, [X16, #0x60] ; W10 = [host(this) + 0x60] = `dead-list.prev`?
...
lr-348                    0xb9400209  LDR W9, [X16, #0]    ; sym-MEM load (process Type ptr)
lr-344                    0x8b0f0130  ADD X16, X9, X15
lr-340                    0x79401209  LDRH W9, [X16, #8]   ; W9 = process.size (u16 at offset 8 of Type)
lr-328                    0x8b0b0129  ADD X9, X9, X11      ; X9 = process.size + stack-size = 0x4070
lr-324                    0x8b0f0190  ADD X16, X12, X15    ; X16 = host(this) -- X12 STILL == this here
lr-320                    0xb85fc208  LDUR W8, [X16, #-4]  ; W8 = type-tag of this
lr-316                    0x8b0f0110  ADD X16, X8, X15     ; X16 = type_host
lr-312                    0xb9407208  LDR W8, [X16, #0x70] ; W8 = slot 24 (find-gap-by-size) of dead-pool-heap
lr-304                    0xaa0c03e7  MOV X7, X12          ; X7 = X12 = this (arg0 to find-gap-by-size)
lr-300                    0xaa0903e6  MOV X6, X9           ; X6 = X9 = size (arg1)
lr-296                    0x8b0f0108  ADD X8, X8, X15      ; X8 = fn_host
lr-292-284                STP/STP/STR  X3,X5 / X10,X11 / X23 ; saves before BLR (NO X12 SAVE)
lr-280                    0xd63f0100  BLR X8               ; call find-gap-by-size
[find-gap-by-size internally clobbers X12, returns]
lr-276..lr-260            pops of X3,X5,X10,X11,X23
[lr-256 onwards: original walker window — X12 is used as if it were still == this]
lr-52                     0x8b0f0190  ADD X16, X12, X15    ; X16 = host(X12 = WRONG VALUE)
lr-48                     0xb85fc209  LDUR W9, [X16, #-4]  ; W9 = type-tag at garbage offset = 0
lr-44                     0x8b0f0130  ADD X16, X9, X15     ; X16 = ee_base
lr-40                     0xb9406a09  LDR W9, [X16, #0x68] ; W9 = 0 (uninit low mem)
lr-32                     0xaa0c03e7  MOV X7, X12          ; arg0 = garbage
lr-20                     0x8b0f0108  ADD X8, X8, X15      ; X8 = ee_base
lr-4                      0xd63f0100  BLR X8               ; → UDF #0 at ee_base → sig=4
```

The **pre-call stack-save list at lr-292..lr-284 saves {X3, X5, X10,
X11, X23} but NOT X12** — and find-gap-by-size's body (also
goalc-emitted) uses X12 as a local register (per its own
prologue at GOAL 0x1d34e4: `MOV X12, X6` = stash size in X12). After
find-gap-by-size returns, X12 holds the size argument (0x4070), not
`this`. The subsequent gap-location dispatch at lr-52..lr-4 uses
X12 = 0x4070 as the receiver → SIGILL.

This is a **goalc regalloc bug**: the emitter treats X12 as
callee-save across an IR_FunctionCall but emits a save list that
doesn't include X12. The bug is consistent across multiple get-
process-like emit patterns (any function that holds an args-marshalled
value in X12 across a sub-call).

## Second codegen bug surfaced: field-offset off-by-4

After the X12-preserve wrapper for slot 24 (find-gap-by-size) was
installed, boot advanced PAST the original BLR-to-ee_base SIGILL but
died at a NEW SIGILL signature:

```
GK-DIAG sig=4 fault=0x212afffe84 pc=0x212afffe84 lr=0x212afffe84
GK-DIAG x12=0x21231d6344
GK-DIAG x16=0x212afffe84
```

`PC = 0x212afffe84` is a STACK address — i.e., a BLR/RET landed on
the stack. Reading find-gap-by-size's compiled body at GOAL 0x1d34e4
shows the smoking gun:

```
0x21231d34f0  0x8b0f00b0  ADD X16, X5, X15      ; X16 = host(this)
0x21231d34f4  0xb9403203  LDR W3, [X16, #0x30]  ; W3 = [host(this) + 48]
```

Per `decompiler/config/jak1/all-types.gc:1840`:
```
(fill-percent       float                       :offset-assert 48)
(first-gap          dead-pool-heap-rec          :offset-assert 52)
```

The find-gap-by-size body should read `(-> this first-gap)` (offset
**52** = 0x34), but the emit reads offset **48** = 0x30 — that's
`fill-percent` (a float). The off-by-4 surfaces in MULTIPLE other
functions checked:

- `compact-time` method body (0x21231d34b4): reads `(-> this
  compact-time)` (= offset 36 = 0x24) but emits LDR at offset 32 =
  0x20 (= allocated-length). Off by -4.
- get-process body line `(set! (-> this dead-list next) ...)`: writes
  at offset 0x60 (= 96 = dead-list.prev) instead of 0x64 (= 100 =
  dead-list.next). Off by -4.

This is a **systematic field-offset codegen bug**: the arm64 emitter
subtracts 4 from every basic-relative field offset. The result:
every read returns the WRONG field's value, every write goes to the
WRONG field. find-gap-by-size returns the fill-percent value
(reinterpreted as a rec pointer = garbage). get-process's `insert =
garbage`. Then the linked-list manipulation corrupts memory.
Eventually a BLR with X16 = corrupted-data lands on stack memory →
sig=4 SIGILL.

The off-by-4 bug ALSO can't be fixed within A18: it lives in the
arm64 emitter's lowering of `IR_LoadConstOffset` /
`IR_StoreConstOffset` (or whichever IR ops compute the
basic-relative offset). Wrapping methods can't fix it because the
buggy offsets are baked into the COMPILED CGO bytes.

## Why the X12-preserve wrappers don't advance boot

The wrappers DO change the failure mode (from BLR-to-ee_base at
the gap-location dispatch site, to BLR-to-stack later inside
start-time-of-day's top-level execution). The X12 preservation
works as designed — the gap-location dispatch resolves correctly
to dead-pool-heap.method-22's wrapper, gap-location runs, returns,
process.new is invoked. But the off-by-4 bug corrupts the state
somewhere in this chain, and a subsequent BLR target gets
poisoned with stack-region garbage.

The link-finish counter doesn't advance past 216 because the
crash is INSIDE time-of-day's top-level body, AFTER the
"link finish: time-of-day" emit but BEFORE the next CGO links.

## Why none of attempt-4's other paths could work

| Path tried in attempt-4                                | Outcome |
|--------------------------------------------------------|---------|
| `make_x12_preserve_wrapper_arm64` for slot 24 only     | Crash mode changes (ee_base → stack), 216 ceiling persists |
| Extend to slots {24, 22, 23, 0}                        | Same stack-crash, 216 ceiling |
| Mock attempt: just preserve X12 in get-process via stack-relative hack | Can't — get-process is goalc-emitted, no patch slot |
| Pre-init `[ee_base+0x68]` to bypass the original dispatch | Anti-cheat fence #2 forbids writes < HEAP_START outside `InitHeapAndSymbol` |
| Honest-abort surface at the field-read site            | Not a "site" — every field access in every emitted GOAL function shifts by 4 |

The honest exit path from attempt-3's brief stands:

> If the diagnostic identifies the type-method but the fix needs an
> unlock beyond A18's scope (e.g., requires modifying GOAL source +
> CGO regen), commit the diag + analysis + write
> A18-attempt-N-next-blocker.md. The supervisor will author A19.

## A19 required unlocks (verified by attempt-4's evidence)

1. **`goalc/regalloc/Allocator_v2.cpp`** — for the X12-clobber fix.
   The regalloc's "live across function call" detection should
   either add X12 to the save list of every IR_FunctionCall in
   the function, or move the held-across-call value to a
   callee-save register (X19-X28 in AAPCS).

2. **`goalc/emitter/IGenARM64.cpp`** — for the field-offset
   off-by-4 fix. The lowering of `load_constant_offset` /
   `store_constant_offset` (or the equivalent IR helper that
   emits LDR Wt, [Xb, #imm] / STR Wt, [Xb, #imm]) currently
   subtracts 4 from the basic-relative field offset. The fix
   removes that subtraction. Note: changing this WILL ripple
   through every arm64 CGO. New baseline file needed.

3. **`goalc/compiler/IR.cpp`** — depending on which IR layer
   computes the offset (Lvar /  Field-ref / Load /  Store), the
   fix may need to live in IR rather than the emitter.

4. **New baseline**: `.autoport/reports/A19-baseline-arm64-cgo-hashes.txt`
   — both fixes change emitted bytes everywhere.

5. **Optional**: `goalc/regalloc/Allocator.cpp` and `allocate_common.cpp`
   if the shared regalloc state needs touching for the X12 fix.

## A18 attempt-4 file changes (kept; useful as A19 prelude)

| File                                  | Change                       |
|---------------------------------------|------------------------------|
| `game/linux-arm64/linux_arm64_main.cpp` | Extend GK-DIAG hex dump from lr-256 to lr-1024 |
| `android/gk_android_main.cpp`         | Mirror of the above |
| `game/kernel/jak1/kscheme.cpp`        | `make_x12_preserve_wrapper_arm64` helper |
| `game/kernel/jak1/kscheme.h`          | Declaration of the helper |
| `game/kernel/common/klink.cpp`        | `klink_a18_install_x12_preserve_wrappers` + diag method-table dump for dead-pool-heap |
| `game/kernel/common/klink.h`          | Declaration of the binder |
| `.autoport/reports/A18-attempt-4-next-blocker.md` | This file |

All changes are within the A18 unlock list. No modifications to:
- goalc/* (codegen locked)
- game/kernel/asm_funcs_arm64.s
- game/kernel/common/kscheme.cpp
- game/kernel/common/kmachine.cpp
- game/system/IOP_Kernel.{cpp,h}
- linux_arm64_runtime_compat.cpp
- android_runtime_compat.cpp
- `.autoport/lib/*` or `.autoport/validators/*`

## Anti-cheat invariants — A18 attempt-4 status

- `a18_method_zero_trap` body unchanged (still `_Exit(13)`).
- 0 writes to `g_ee_main_mem[< HEAP_START]` outside `InitHeapAndSymbol`.
- 0 new `MAP_FIXED` mmap calls.
- 0 validator script changes.
- 0 `__attribute__((weak))` declarations.
- 0 printf "link finish: X" emitted from C++ code.
- 0 inline `_stub(` additions.
- 0 rename-evasion stub-shaped functions.
- 0 changes to codegen (`IGenARM64.{cpp,h}`, `IR.{cpp,h}`,
  `CodeGenerator.{cpp,h}`, `ObjectGenerator.{cpp,h}`,
  `Allocator*.cpp`).
- 0 changes to runtime locks (asm_funcs, kscheme common, kmachine,
  IOP_Kernel, runtime_compat).
- x86 desktop smoke: passes (`link finish: logo-intro-2` reached,
  446+ link-finishes).
- x86 CGOs byte-identical to A2 baseline.
- arm64 CGOs byte-identical to A17 baseline (no goalc change).

The X12-preserve wrappers ARE a workaround (not a real fix); per
attempt-3's brief Option C, "useful but not a real fix". They
demonstrate the X12 issue concretely and would be removed once A19
lands the regalloc fix. Keeping them in the diff for A19's evidence
trail: when A19's regalloc fix lands, dead-pool-heap.method-{22,23,24}
and process.method-0's wrappers should be inert (no clobber to
preserve), so the wrappers add no functional change post-fix.

## Validator state — check 8 (qemu > 216) cannot pass under A18

```
== Phase A18 validator (type-method-zero bind) ==
  ok: A18-unlocked files have N lines diff from A17
  ok: all locked files unchanged since A17
  ok: no dodge in source
  ok: anti-cheat checks all pass
  ok: A18-DIAG markers present
  ok: fix summary present
  ok: x86 CGOs byte-identical to A2 baseline
  ok: arm64 CGOs byte-identical to A17 baseline
FAIL: link-finish count stuck at 216 — A18's fix did not advance boot
```

Boot dies at exact PC 0x212afffe84 (stack address) with the
X12-preserve wrappers installed. Without wrappers, boot dies at
0x2123000000 (ee_base). Both are time-of-day's top-level
(start-time-of-day → process-spawn → get-process). The 216 ceiling
is preserved through both crash modes because the field-offset
off-by-4 bug corrupts state during get-process body execution.

## Cost note

Attempt-4 cost: ~120 min (the supervisor's brief budget for path A).
- 25 min: catching up on attempt-3's prior work, reading existing diag.
- 30 min: writing + testing extended diag walker (lr-256 → lr-1024).
- 30 min: writing + testing `make_x12_preserve_wrapper_arm64` + binder.
- 30 min: decoding the extended disasm, confirming X12-save miss at lr-292..lr-284, narrowing slot 24 to find-gap-by-size, then discovering the off-by-4 field offset bug.
- 10 min: writing this report.

The attempt confirms attempt-3's regalloc-bug hypothesis with
disassembly-level evidence AND surfaces a NEW codegen bug
(field-offset off-by-4) that attempt-3 missed. The wrappers
(legitimate workaround) advance the failure mode past the
original BLR-to-ee_base SIGILL but can't fix the field-offset
bug. A19 needs both codegen unlocks.
