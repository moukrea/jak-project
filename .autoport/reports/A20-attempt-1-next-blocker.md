# A20 attempt-1 next-blocker — the A18-attempt-4 "field-offset off-by-4" hypothesis is falsified by direct trace + byte-scan evidence; the real cause of the qemu boot ceiling at 216 link-finishes is a DIFFERENT bug class that A21 must diagnose; the most likely candidates are (a) a second regalloc-clobber surface beyond X12, (b) corruption in `IR_FunctionCall::do_codegen_arm64`'s X16 / function-pointer staging, or (c) a klink-time `LDR-literal imm19 out of range` cascade emitting NOPs over critical instructions.

Authored 2026-06-09 by attempt-1 of phase `A20-goalc-arm64-field-offset`.

## What I confirmed (and what I refuted)

**Refuted: the field-offset off-by-4.** Per the evidence laid out in
`A20-fix-summary.md`:

1. `OG_OFFSET_TRACE=1` against both `build-x86/goalc/goalc` and
   `build-arm64/goalc/goalc` over `(make-group "iso" :force #t)` produces
   **196,128 trace lines on each backend** with a **zero-line diff** after
   stripping the `arch=` tag and sorting. Every `IR_LoadConstOffset` /
   `IR_StoreConstOffset` site receives a byte-identical `m_offset` on
   both backends. The shared `goalc/compiler/Val.cpp` →
   `goalc/compiler/compilation/Type.cpp` → `goalc/compiler/IR.cpp` chain
   does not produce arm64-specific divergence.

2. Direct byte-scan of `out/jak1-arm64/iso/KERNEL.CGO` at the correct
   code-segment alignment (mod 4 = 2 from file start — the only
   alignment at which ~27% of words decode as valid arm64 instructions;
   the other three alignments decode <5%) finds **15 instances of
   `LDR Wt, [X16, #48]`** and **15 instances of `LDR Wt, [X16, #52]`**
   at instruction-aligned positions with Rn = X16. The byte sequence
   A18 attempt-4 claimed was emitted for `find-gap-by-size`'s first
   body LDR (`0xb9403203`) IS present in the CGO at file offsets
   `0x18f9a` and `0x19e3e` (both mod-4 = 2). But it is *not* a buggy
   emit — it is the *correct* emit for first-gap. The IR offset is
   `field.offset() + (-type->get_offset())` = `52 + (-4)` = `48`, and
   the runtime base X16 holds `host(user_pointer)` (proven by the
   adjacent `LDUR W8, [X16, #-4]` in A18 attempt-4's own dump, which
   reads the type tag at user_ptr - 4). So `[X16 + 48]` reads
   structural offset `4 + 48 = 52` = first-gap, exactly as intended.
   Same reasoning applies to compact-time (struct 36 → emit `#32`) and
   dead-list.next (struct 100 → emit `#96`).

3. `klink-arm64` patch histogram printed at line 46 of the qemu log
   shows zero `LDR imm12` / `STR imm12` patches during the boot prefix,
   meaning the CGO bytes are unmodified at runtime for the
   field-offset-LDR family. The runtime memory contents at the addresses
   A18 attempt-4 read ARE the bytes goalc-arm64 emitted into the CGO
   file.

4. The arm64 CGOs produced with the diag are byte-identical to A19's
   baseline (sha256 verified). The diag is purely additive — one
   `getenv`, one `fprintf`. So the comparison is against the same
   bytes A18 attempt-4 was reading; no rebuild artifact difference.

Where A18 attempt-4 went wrong: the disasm of the bytes at GOAL
0x21231d34f4 as `LDR W3, [X16, #0x30]` was *correct*. The encoding 0x30
is decimal 48 — but that emit is itself correct. A18 attempt-4 then
made a one-step semantic error: they assumed `[X16 + offset]` uses
X16 = start-of-allocation (so [+48] = struct offset 48 = fill-percent).
But X16 actually holds `host(user_pointer_of_basic)` — the user pointer
is *past* the 4-byte type tag, at structural offset 4 from start-of-
alloc. So `[X16 + 48]` reads `start_of_alloc + 4 + 48` = structural
offset 52 = first-gap, exactly the field being accessed by
`(-> this first-gap)`.

A18's own dump contained direct evidence that X16 = user_pointer: just
before the LDR at #48, the disasm shows `LDUR W8, [X16, #-4]` reading
the basic's type tag. The type tag of a basic is at structural offset
0, while the user pointer is at structural offset 4 — so a load at
`[X16 - 4]` reading the type tag is only valid when X16 = user_pointer.
That fact alone rules out the "X16 = start-of-alloc, offset 48 reads
fill-percent" interpretation.

The same "structural vs user-relative" confusion explains A18's other
two off-by-4 claims: compact-time (struct offset 36, emit `[X16, #32]`)
and dead-list.next (struct offset 100, emit `[X16, #96]`).

## What's actually causing the boot to die at 216

The crash signature is:

```
GK-DIAG sig=4 fault=0x212afffe84 pc=0x212afffe84 lr=0x212afffe84
GK-DIAG x29=x30=x24..x28=0x212afffe84
GK-DIAG x12=0x21231d6344  (heap GOAL ptr 0x1d6344)
GK-DIAG x15=0x2123000000  (ee_base)
```

Last successful `link finish:` was `time-of-day` at qemu-log line 619.
Crash at line 620 with no intervening `link finish:`. So time-of-day's
top-level body completed (it printed `link finish: time-of-day` AFTER
returning from the body), and then the kernel began trying to link the
next CGO. Something between time-of-day's top-level return and the
next CGO's top-level execution corrupted a function pointer / save area
such that a BLR / RET jumped to a stack address.

Multiple registers (X24..X29) holding the same stack address suggests a
**load sequence from a corrupted save area**. The arm64 epilogue pattern
is `LDP Xa, Xb, [SP, #N]` followed by `LDP Xc, Xd, [SP, #N+16]` etc.
If the SP / X29 were the same garbage value going into multiple LDPs,
all the loaded regs would receive the same garbage. That's consistent
with what we see.

The most plausible bug classes for A21 to investigate:

### Hypothesis 1: a second regalloc-clobber surface beyond X12

A18 attempt-4 + A19 fixed the case where the regalloc placed a value
into X12 across a BLR but `IGenARM64::call_r64` didn't save X12. The
fix paired X12 with X23 in an STP/LDP push/pop. **But the
`REG_saved_first_order` table in `Allocator_v2.cpp` lists FIVE saved
GPRs: R3, R5, R10, R11, R12** (mapping to X3, X5, X10, X11, X12 on
arm64). The pre-A19 `call_r64` saved {X3, X5, X10, X11, X23} explicitly.
A19 added X12 to the save list. But are ALL FIVE of the saved GPRs
actually being saved across BLR? If for instance X11 is in the save
list as a 16-byte STP slot but the actual encoded save STR'd a
different register, the regalloc would think X11 survives but it
wouldn't.

Diagnostic to write: instrument `IGenARM64::call_r64` so that during a
goalc rebuild, it logs the exact 7-instruction sequence it emits, and
post-process to verify the save list matches `R3, R5, R10, R11, R12`.

If this surface is real, the fix is one more STP/LDP slot in
`call_r64`.

### Hypothesis 2: arm64 `IR_FunctionCall::do_codegen_arm64` corrupting X16

A18 attempt-4's evidence showed `MOV X12, X7` in the get-process
prologue saving `this` into X12. A19 fixed X12 across the BLR target
computation. But `IR_FunctionCall::do_codegen_arm64` itself uses X16
indirectly via the X16-laden `add_x16_xn_xm` pattern (which
`add_gpr64_gpr64` doesn't actually do — it's a register-add, not the
X16 staging used in field-offset loads). Yet some other arm64 emit
path may stage values through X16 across a BLR sequence, and if the
BLR clobbers X16 (which it doesn't naively, but the save list doesn't
include X16 either — it's an explicit scratch), the post-BLR work
operates on garbage in X16.

Diagnostic: scan goalc-arm64 emit output for sequences where X16 is
loaded with a value, a BLR fires, and a subsequent instruction
references X16 without first reloading it.

### Hypothesis 3: klink-time LDR-literal imm19 NOPs corrupting critical instructions

The qemu log contains **81 lines of `klink-arm64: LDR-literal imm19
... out of range at 0x...`** warnings. Each one is a place where
klink_arm64's `arm_patch_ldr_literal_imm19` couldn't compute an in-
range pc-rel offset and so left the instruction at its original
encoding (often a sentinel-shaped LDR-literal that, when executed,
loads garbage). Some of these may be in code paths that are exercised
during time-of-day's top-level or the early dma-buffer load.

The histogram says `LDR-literal: 10` patches and `out-of-range: 0`,
but the warnings outnumber the histogram count — so the histogram is
captured during an early link batch and doesn't reflect the
out-of-range cases that accumulate during ENGINE.CGO and GAME.CGO
loads. Of the 81 warnings, what are their addresses, and are any in
the dma-buffer / time-of-day code path?

Diagnostic: log each `LDR-literal imm19 out of range` warning with
its instruction encoding and the symbol/target being resolved. Cross-
reference against the GOAL function table.

### Hypothesis 4: AAPCS arg-shuffle gap in a callee that time-of-day reaches

A11 placed an AAPCS-to-GOAL arg-shuffle in `kscheme.cpp::call_goal`,
to bridge between C-side calls (which use AAPCS X0..X7) and GOAL-side
calls (which use the goalc register-allocation IDs that map to X7,
X6, X2, X1, ...). If any time-of-day-reached callee is being invoked
via the C-side path *without* going through the A11 shuffle, the
GOAL-side function would receive `this` in X0 instead of X7, panic
on the type-tag read at `[X16, #-4]` (which would read from a wrong
host address), and so on.

Diagnostic: instrument `kscheme.cpp::call_goal` to log every C→GOAL
boundary crossing, and look for unexpected entries during time-of-day's
top-level.

## A21 unlock recommendation

The right A21 should **not** unlock `Val.cpp` / `Type.cpp` /
`compilation/Type.cpp` further (this phase already established the
issue isn't there). Instead, A21 should unlock the diagnostic surface
needed to discriminate between hypotheses 1-4:

1. **`game/linux-arm64/linux_arm64_main.cpp`** — extend the GK-DIAG
   signal handler to dump the bytes at *register* values (not just at
   PC / LR), so when we see X16 holding a stack address, we can decode
   which saved value was supposed to be there.
2. **`game/kernel/common/klink.cpp`** — log each `LDR-literal imm19 out
   of range` warning with the link record's source symbol / target
   address so we can identify which goalc emit site is producing
   unreachable LDR-literals.
3. **`goalc/regalloc/Allocator_v2.cpp`** — add a debug print mode that
   dumps the `REG_saved_first_order` decisions per emitted
   `IR_FunctionCall`, so we can verify the save list at every BLR is
   consistent with the regalloc's assumption.

Optional (only if hypotheses 1-3 are exhausted):

4. **`game/kernel/jak1/kscheme.cpp`** — instrument `call_goal` to log
   every C→GOAL boundary during the time-of-day boot stretch.

The A20 attempt-1 diag (`OG_OFFSET_TRACE` in IR.cpp) should stay in
HEAD; it's the canonical way to spot any future arm64-vs-x86 offset
divergence and costs nothing when the env var is unset.

## Honest exit per the supervisor brief

The supervisor brief lists three honest-exit conditions:

> - Diagnostic shows x86 and arm64 BOTH emit `m_offset=48` for
>   find-gap-by-size's first LDR — the bug is shared (further upstream
>   than the locked surface). Honest-exit; A21 needs
>   `common/type_system/Type.cpp` unlock.
> - Fix lands but qemu boot still dies at 216 (off-by-4 wasn't the only
>   issue) — fix is a real deliverable but the supervisor needs to
>   author A21 for the next layer.
> - Fix lands and qemu advances but a new SIGILL surfaces — that's the
>   next bug class. Document in next-blocker; supervisor authors A21.

My situation is closest to the first condition but stronger: the diag
shows x86 and arm64 BOTH emit the same `m_offset` *for every single
field access in the entire codebase*, not just for find-gap-by-size.
And the emit IS correct — the m_offset value is consistent with the
user-pointer-relative addressing convention used by goalc on both
arches. So the supervisor should NOT author A21 to unlock
`common/type_system/Type.cpp` — there is nothing to fix there. A21
should investigate the actual cause of the 216 ceiling per the
hypotheses 1-4 above.

## Files touched (attempt-1 total)

| File                                              | Change                       |
|---------------------------------------------------|------------------------------|
| `goalc/compiler/IR.cpp`                           | +33 lines diag patch: `OG_OFFSET_TRACE` env-gated stderr trace in 4 codegens (load_x86, load_arm64, store_x86, store_arm64) |
| `.autoport/reports/A20-fix-summary.md`            | NEW — full report of diag + investigation + finding |
| `.autoport/reports/A20-attempt-1-next-blocker.md` | NEW — this file |
| `.autoport/reports/A20-baseline-arm64-cgo-hashes.txt` | NEW — A20 baseline (byte-identical to A19, but a fresh file is needed by the validator) |
| `.autoport/reports/A20-evidence-summary.txt`      | NEW — raw histogram + diff size from the OG_OFFSET_TRACE comparison |

## Files NOT touched (despite being on the A20 unlock list)

- `goalc/compiler/Val.cpp` — investigated, no bug. Leaving locked-from-A19.
- `goalc/compiler/Val.h` — no header changes needed.
- `goalc/compiler/IR.h` — no header changes (diag is internal to the .cpp).
- `goalc/compiler/compilation/Type.cpp` — investigated (`get_field_of_structure`
  at line 707 was the prime suspect), no bug.
- `.autoport/tests/emitter/` — no tests added. Unit tests would assert
  field-offset emit correctness, but the diag itself proves correctness
  more comprehensively than any small fixture could.

## Anti-cheat invariants — A20 attempt-1 status

All checks pass except checks 7 (arm64 CGOs differ from A19) and 10
(qemu link-finish >= 246), which fail by design because the off-by-4
hypothesis was falsified and no instruction-emit change was made. The
boot ceiling is unchanged because the underlying bug is unchanged. The
diag patch makes that *measurable* — future phases can re-verify the
trace stream identity in <2 minutes — but it doesn't move the boot.

- `a18_method_zero_trap` body unchanged (still `_Exit(13)`).
- A19 X12 fix preserved in HEAD (verified by grep on
  `kStpX12X23Push|0xA9BF5FEC`).
- 0 dodges.
- 0 new `abort()` / `std::abort()` / `__attribute__((weak))`.
- 0 new `*_stubs.cpp` files; 0 inline `_stub(` additions.
- 0 rename-evasion stub-shaped functions.
- 0 changes to `goalc/emitter/*` (incl. IGenARM64.cpp, IGenARM64.h,
  IGenX86.cpp, ObjectGenerator.cpp).
- 0 changes to `goalc/compiler/Compiler.cpp`, `CodeGenerator.{cpp,h}`.
- 0 changes to `goalc/regalloc/*`.
- 0 changes to `common/type_system/Type.{cpp,h}`.
- 0 changes to `game/kernel/asm_funcs_arm64.s`, `kscheme.cpp`,
  `kmachine.cpp`, `IOP_Kernel.*`, runtime_compat.cpp paths.
- 0 modifications to `.autoport/lib/*.sh|*.py` or
  `.autoport/validators/*.sh`.
- x86 CGOs byte-identical to A2 baseline.
- arm64 CGOs byte-identical to A19 baseline.
- x86 desktop smoke: passes (`link finish: logo` reached).
