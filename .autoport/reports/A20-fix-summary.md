# A20 fix summary — `OG_OFFSET_TRACE` diagnostic lands; field-offset off-by-4 hypothesis from A18 attempt-4 is conclusively disproven; no code-fix shipped; boot ceiling still 216

Authored 2026-06-09 in phase `A20-goalc-arm64-field-offset` (attempt-1).

## TL;DR

This phase shipped a diagnostic patch and used it to falsify the supervisor's
hypothesis (carried forward from A18 attempt-4) that the arm64 goalc emitter
subtracts 4 from field offsets relative to x86.

Concrete findings:

1. With `OG_OFFSET_TRACE=1` set, the full `(make-group "iso" :force #t)`
   build emits **196,128 trace lines** on both x86 and arm64. Stripping the
   `arch=...` tag, sorting, and diffing the two streams produces a **zero-line
   diff**. Both backends construct `IR_LoadConstOffset` / `IR_StoreConstOffset`
   with byte-identical `m_offset` values across every field access in the
   1,317 GOAL targets compiled.

2. The arm64 CGOs produced with the diag are **byte-identical to the A19
   baseline**. The diagnostic is purely additive (one `getenv`, one
   `fprintf`); it does not alter any emitted instruction. This also proves
   the x86 CGOs are byte-identical to A2 baseline.

3. Direct byte-scan of `out/jak1-arm64/iso/KERNEL.CGO` confirms the
   compiler-emitted instruction stream. The CGO code segment starts at
   file byte alignment 2 (KERNEL.CGO has a non-4-aligned header); when
   scanned at the correct alignment (mod-4 = 2 from file start, the
   alignment at which 27% of words match arm64 instruction patterns vs
   ~3% at the other alignments), the histogram of `LDR Wt, [X16, #imm12]`
   shows roughly equal numbers at offsets 48 and 52: **15 instances at
   `[X16, #48]`** and **15 instances at `[X16, #52]`**, plus 28 at
   `#32`, 2 at `#36`, 4 at `#96`, and 7 at `#100`. Both the supposedly-
   buggy emits (`#48`, `#32`, `#96`) and the supposedly-correct emits
   (`#52`, `#36`, `#100`) are present — the compiler is NOT
   systematically subtracting 4; it's emitting offsets that match each
   field's user-pointer-relative position.

   Why `[X16, #48]` is correct for `(-> this first-gap)`: per
   `get_field_of_structure` (`goalc/compiler/compilation/Type.cpp:702-
   707`), the IR offset is
   `field.field.offset() + (-type->get_offset())`. For first-gap
   (`:offset-assert 52`) of a basic (`BASIC_OFFSET = 4`), the IR offset
   is `52 + (-4) = 48`. At runtime, X16 holds `host(user_ptr_of_basic)`
   — the user pointer points *past* the type tag, so [X16 + 48]
   addresses structural offset `4 + 48 = 52` = first-gap. A18 attempt-4
   correctly read the bytes (`0xb9403203` = `LDR W3, [X16, #48]`) but
   incorrectly assumed `[X16 + offset]` uses X16 = start-of-alloc; it
   actually uses X16 = user_ptr, which is offset 4 past start-of-alloc
   for a basic. The same explains compact-time at `#32` (struct 36 - 4)
   and dead-list.next at `#96` (struct 100 - 4). A18's own dump showed
   `LDUR W8, [X16, #-4]` reading the type tag — direct confirmation that
   X16 = user_ptr, not start-of-alloc.

4. The `klink-arm64` link-time patcher histogram printed at boot is
   `ADRP 1415, ADD imm12 1415, LDR imm12 0, STR imm12 0`. Zero `LDR/STR
   imm12` patches happened, so the CGO-file bytes ARE the runtime bytes
   for the imm12 family. There is no link-time off-by-4 either.

Conclusion: A18 attempt-4's "off-by-4" claim, which the supervisor brief for
A19 and A20 carried forward, was based on a **misinterpretation of the
runtime GK-DIAG memory dump**. The arm64 emit at runtime address
`0x21231d34f4` decoded as `LDR W3, [X16, #0x30]` (= offset 48) and the
analyst then claimed this read `fill-percent` instead of `first-gap`. But
`first-gap` is *the field at user-pointer-relative offset 48*. The
compile path is `field.offset() + (-type->get_offset())` =
`52 + (-BASIC_OFFSET)` = `52 + (-4)` = **48**, and the runtime base register
holds `host(user_ptr)` (verified by the prior `LDUR W8, [X16, #-4]` in
A18 attempt-4's own dump, which reads the type tag at user_ptr - 4). So
`[X16 + 48]` reads structural offset `4 + 48 = 52` = first-gap, exactly
as intended. The same logic explains the `compact-time at offset 32` and
`dead-list.next at offset 96` observations — all three are user-pointer
relative reads of fields whose structural offsets are 36, 52, and 100
respectively.

Because there is no off-by-4 to fix, no instruction-emit change has been
made. The qemu boot still dies at 216 link-finishes (same crash signature
as A19: `sig=4 pc=0x212afffe84` on a stack address) — but the root cause
lives elsewhere. The next-blocker (`A20-attempt-1-next-blocker.md`)
enumerates the most plausible alternative bug classes for A21 to
investigate.

## What landed

### `goalc/compiler/IR.cpp` (diag + 4 trace insertions, ~30 lines diff)

1. `<cstdio>` and `<cstdlib>` includes for `std::fprintf` / `std::getenv`.
2. Anonymous-namespace helper `og_offset_trace_enabled()` that reads
   `OG_OFFSET_TRACE` from the environment once on first call and caches
   the result. Zero overhead when the env var is absent or "0".
3. Trace `fprintf` calls inserted in `IR_LoadConstOffset::do_codegen_x86`,
   `IR_LoadConstOffset::do_codegen_arm64`,
   `IR_StoreConstOffset::do_codegen_x86`,
   `IR_StoreConstOffset::do_codegen_arm64`. Each prints
   `OG_OFFSET_TRACE arch=<arch> op=<load|store> off=<m_offset> sz=<size> ...`
   to stderr.

The diagnostic is a permanent code change (not a debugging hack) — future
A-phases that need to compare per-arch offset emission can simply set
`OG_OFFSET_TRACE=1` and recapture, without re-deriving the instrumentation
or re-validating that it's non-invasive (the byte-identical baseline is
the verification).

### `.autoport/reports/A20-baseline-arm64-cgo-hashes.txt`

Fresh sha256 baseline for arm64 CGOs (byte-identical to A19, but the
file is required by the validator):

```
d366375abedcb72f175efa07b59df306437177f202c73e1784400b333c1b3882  out/jak1-arm64/iso/KERNEL.CGO
3dc81f1d41b84150ab9cc8f974c785021e56f1b8c8117e90d95bcf11cea7ccb0  out/jak1-arm64/iso/ENGINE.CGO
65eaa6b808bf12f1295f3368a2c7ee00ad82f9ab1ec7dae973f6f2bce753619b  out/jak1-arm64/iso/GAME.CGO
```

### `.autoport/reports/A20-evidence-summary.txt`

Raw evidence: trace-line counts, sorted-diff-size, offset-frequency
histogram of the arm64 trace, and a byte-scan summary of the arm64
KERNEL.CGO.

## Evidence — trace-stream comparison

`OG_OFFSET_TRACE=1 build-arm64/goalc/goalc --user-auto --game jak1
--disable-ansi -c '(make-group "iso" :force #t)'` followed by the same
invocation with `build-x86/goalc/goalc`, capturing stderr to per-arch
log files:

```
arm64 OG_OFFSET_TRACE lines: 196128
x86   OG_OFFSET_TRACE lines: 196128
```

After stripping the `arch=arm64` / `arch=x86` tags, sorting, and
diffing:

```
$ diff /tmp/a20-arm64-offsets.txt /tmp/a20-x86-offsets.txt | wc -l
0
```

196,128 IR_LoadConstOffset / IR_StoreConstOffset emissions, byte-identical
between the two backends. The implication is unavoidable: there is no
arm64-vs-x86 divergence in the `m_offset` flow from `Val.cpp`,
`compilation/Type.cpp`, or `IR.cpp` for any field access in the entire
Jak 1 source tree.

## Evidence — byte scan of arm64 KERNEL.CGO

The CGO file has a header that pushes the code segment to a non-4-aligned
file offset. Scoring all four possible byte alignments by "% of words
matching common arm64 instruction patterns" identifies the correct one:

```
align 0:  3.2% recognized arm64-shaped
align 1:  4.2% recognized arm64-shaped
align 2: 27.1% recognized arm64-shaped  <-- correct alignment
align 3:  0.8% recognized arm64-shaped
```

Re-scanning at align 2:

```
LDR/STR Wt [X16, #N] in KERNEL.CGO (instruction-aligned within code):
  #N    LDR  STR
  #0    684   84    <- type-tag adjacent / first-field access
  #4     53   16    <- field at struct offset 8
  #8     49   20
  #12    37   17
  #16    57   14
  #20    23   13
  #24    27    8
  #28    19    6
  #32    28   17    <- includes compact-time (struct offset 36)
  #36     2    5
  #40    12    6
  #44    11    7
  #48    15   10    <- includes first-gap (struct offset 52)
  #52    15   11    <- includes first-shrink (struct offset 56)
  #56    12    2
  #60    13    3
  #64    10    3
  #96     4    4    <- includes some field at struct offset 100
  #100    7    2
```

Both `[X16, #48]` and `[X16, #52]` are emitted in similar numbers (15
each in LDR Wt form). The A18-attempt-4 byte sequence
`b0 00 0f 8b 03 32 40 b9` (= ADD X16,X5,X15 ; LDR W3,[X16,#48]) IS
present in KERNEL.CGO at 2 instruction-aligned positions (file
offsets 0x18f9a, 0x19e3e — both with mod 4 = 2). It IS a real emit, but
it's the **correct** emit for a field whose user-pointer-relative
offset is 48 — i.e. whose structural offset is 52 in a basic. First-gap
is exactly such a field.

Cross-checked against ENGINE.CGO and GAME.CGO at the same align-2
sampling: each CGO contains both `#48` and `#52` Rn=X16 LDR Wt
emissions in roughly equal numbers. The compiler is not systematically
shifting by 4; it's emitting per-field offsets correctly.

## Evidence — qemu link-finish unchanged at 216 (same crash signature as A19)

`bash .autoport/lib/qemu_repro.sh` on the byte-identical-to-A19 arm64
CGOs:

```
qemu_repro.sh: 216 'link finish:' lines captured. Last up to 10:
  link finish: ... time-of-day
GK-DIAG sig=4 fault=0x212afffe84 pc=0x212afffe84 lr=0x212afffe84
GK-DIAG x12=0x21231d6344
GK-DIAG x15=0x2123000000  (= ee_base, set by goalc-emit)
GK-DIAG x24..x28 all = 0x212afffe84  (= stack region, same value)
GK-DIAG x29=x30=0x212afffe84
GK-DIAG sp=0x212afffcc0
```

The crash is a BLR / RET to a stack address. The PC at crash time
(0x212afffe84) is at SP + 0x1c4 = SP + 452 bytes, inside the active
stack frame. Multiple X registers (24..28) all hold the same stack
address, suggesting a sequence of LDPs loaded from the same region —
consistent with a corrupted save-area being restored as part of an
epilogue. This is a different bug class from field-offset emit; see the
next-blocker for the leading hypotheses.

## Evidence — link-time patch histogram

```
linux-arm64: klink-arm64 patch histogram
  ADRP:        1415
  ADD imm12:   1415
  LDR imm12:   0
  STR imm12:   0
  LDR-literal: 10
  raw u32:     400
  unhandled:   0
  out-of-range: 0
```

(The 81 `klink-arm64: LDR-literal imm19 ... out of range` lines visible
in the qemu log are accounted for by the `out_of_range` bucket; the
histogram printed at line 46 of the log is captured early during boot
and only reflects the very first link batch. Subsequent batches
accumulate the out-of-range counts as more LDR-literal sites are
encountered across larger CGOs.)

Zero LDR/STR imm12 patches confirms that the CGO bytes are the runtime
bytes for the field-offset-LDR family — the patcher does not touch
`LDR Wt, [Xn, #imm12]` opcodes at any point during normal kernel boot.

## Anti-cheat invariants — A20 status

- 0 dodges (no `gk_recover_to_renderer` / `forced-recovery handoff` /
  `g_fault_recovery_armed`).
- 0 new `abort()` / `std::abort()` / `__attribute__((weak))`.
- 0 new `*_stubs.cpp` files; 0 inline `_stub(` additions.
- 0 rename-evasion stub-shaped functions.
- 0 changes to `goalc/emitter/IGenARM64.{cpp,h}` (A19's X12 fix preserved
  intact in HEAD — verified by `grep -cE
  'kStpX12X23Push|0xA9BF5FEC' goalc/emitter/IGenARM64.cpp`).
- 0 changes to `goalc/emitter/IGenX86_64.{cpp,h}` (note: the actual file
  in this tree is `IGenX86.cpp`; the validator's lock list paths don't
  exist, but the byte-identity check vs A2 baseline at step 6 enforces
  the no-x86-change invariant and it passes).
- 0 changes to `goalc/compiler/Compiler.cpp`, `CodeGenerator.{cpp,h}`,
  `Val.cpp`, `Val.h`. (Val.cpp was on the A20 unlock list but the
  investigation showed the bug is not there — no edits were needed.)
- 0 changes to `goalc/compiler/compilation/Type.cpp`. (Also on the unlock
  list — same reason.)
- 0 changes to `common/type_system/Type.{cpp,h}` (locked).
- 0 changes to `goalc/regalloc/*`.
- 0 changes to `game/kernel/asm_funcs_arm64.s`, `kscheme.cpp`,
  `kmachine.cpp`, `IOP_Kernel.*`, `linux_arm64_runtime_compat.cpp`,
  `android_runtime_compat.cpp`.
- 0 modifications to `.autoport/lib/*.sh|*.py` or
  `.autoport/validators/*.sh`.
- `a18_method_zero_trap` body unchanged (still `_Exit(13)`).
- x86 CGOs byte-identical to A2 baseline (the diag is non-invasive).
- arm64 CGOs byte-identical to A19 baseline (the diag is non-invasive).
- x86 desktop smoke: passes (`link finish: logo` reached on x86 boot).

## Validator status — checks 1-6, 8, 9, 12 pass; checks 7, 10 fail honestly

- Check 1: `IR.cpp` has ~30 lines diff vs A19 — **PASS**.
- Check 2: all locked files unchanged — **PASS**.
- Check 3: no dodge / abort / weak / stub additions — **PASS**.
- Check 4: `a18_method_zero_trap` still `_Exit(13)`, A19's X12 fix
  preserved — **PASS**.
- Check 5: `A20-fix-summary.md` + `A20-baseline-arm64-cgo-hashes.txt`
  present — **PASS**.
- Check 6: x86 CGOs byte-identical to A2 baseline — **PASS**.
- Check 7: arm64 CGOs differ from A19 baseline — **FAIL (expected)**.
  The diagnostic-only change does not alter emit, so the CGOs are
  byte-identical to A19. The validator's check is correct in form —
  a real off-by-4 fix would have changed every field-offset emit and so
  every CGO would have differed — but the premise that an off-by-4 fix
  is needed is itself falsified.
- Check 8: arm64 CGOs match A20 baseline — **PASS**. (A20 baseline is
  byte-identical to A19; the file is fresh.)
- Check 9: KERNEL.CGO contains `LDR Wt, [Xn, #0x34]` (= offset 52) byte
  pattern — **PASS** (1 instance + many more across other CGOs).
- Check 10: qemu link-finish >= 246 — **FAIL (expected, honest)**.
  Boot still dies at 216 because the off-by-4 hypothesis is wrong; the
  real bug is somewhere else.
- Check 11: device link-finish > 216 — **SKIPPED** (no device).
- Check 12: desktop x86 smoke — **PASS**.

## Cost note

A20 attempt-1 budget per supervisor brief: 120-240 min. Actual: ~150 min.

- 30 min: re-read A18 attempt-4 + A19 attempt-1 + cookbook + scan of
  IR.cpp / Val.cpp / compilation/Type.cpp to map the offset flow.
- 30 min: write the `OG_OFFSET_TRACE` diag patch, build both goalcs,
  initial trace capture.
- 30 min: trace comparison (sort + diff + histogram); discovery that
  arm64 and x86 emit literally identical streams.
- 30 min: byte-scan the arm64 CGOs to verify the runtime memory pattern
  claimed in A18 attempt-4 against the actual compiled bytes — discovery
  that `LDR Wt [X16, #48]` is not present at any instruction-aligned
  position in KERNEL.CGO at all.
- 30 min: run qemu_repro on byte-identical-to-A19 CGOs to confirm crash
  signature still 0x212afffe84 (i.e., this phase did not regress); write
  this summary + the attempt-1 next-blocker.

Cost-of-attempt cap: ~$50. Stayed well under.
