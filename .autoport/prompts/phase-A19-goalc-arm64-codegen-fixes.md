# Phase A19 — goalc arm64 codegen fixes (X12 regalloc + field-offset off-by-4)

## First step — read these

1. `.autoport/CODEGEN_COOKBOOK.md` (the patterns + invariants).
2. `.autoport/reports/A18-attempt-4-next-blocker.md` — the disasm-level
   evidence and proposed fix surface.
3. `.autoport/reports/A18-attempt-3-next-blocker.md` — the X12 clobber
   confirmation (corroborating evidence).
4. `.autoport/reports/A18-fix-summary.md` — what A18 already shipped
   that you should NOT undo (kscheme inherit-loop fix, A18 method-zero
   trap walker, X12-preserve wrappers).

## Status

**Authored 2026-06-09 by the supervisor** after A18 attempt-4
honest-exited with two arm64-specific goalc codegen bugs identified
via disassembly-level evidence. A18's locks (no goalc/) could not
land the fixes; A19 unlocks the minimum codegen surface needed.

A18 attempt-4 ran in tandem on `dead-pool-heap.get-process` (called
from `start-time-of-day`'s top-level), captured the function prologue
+ pre-call save list + crash site, and pinpointed exactly two
distinct goalc-arm64 codegen bugs whose combined effect pins the
qemu boot at 216 link-finishes. Fixing either alone does not advance
boot. **Both must land together.**

## Bucket

A — emitter/regalloc.

## The two bugs

### Bug 1: X12 regalloc clobber across BLR

**Evidence** (from `A18-attempt-4-next-blocker.md` §52-105):

```
get-process prologue at GOAL 0x1d35c4:
  lr-388: 0xaa0703ec  MOV X12, X7        ; stash this in X12
  ...
  lr-292..lr-284: STP X3,X5 / STP X10,X11 / STR X23
                                          ; pre-call save list — X12 NOT included
  lr-280: 0xd63f0100  BLR X8              ; call find-gap-by-size — clobbers X12
  ...
  lr-52:  0x8b0f0190  ADD X16, X12, X15   ; uses X12 as this — but X12 was clobbered
  lr-4:   0xd63f0100  BLR X8              ; → SIGILL (X12 was 0x4070 = the size arg, not this)
```

The goalc-arm64 regalloc treats X12 as caller-saved (it's in the
"temporary" register pool), so values held across a function call
must be either (a) saved on the stack by the caller's prologue and
restored after the call, or (b) coloured into an AAPCS callee-saved
register (X19-X28). Neither happens here: get-process's compiled body
holds `this` in X12 across the BLR to find-gap-by-size, but the
caller's save list does not include X12, and X12 is not in a
callee-saved register.

**Likely fix surface**: `goalc/regalloc/Allocator_v2.cpp` (the
arm64-only allocator). Either:
- Add X12 to the call-clobber save list (cheap, always-pay the
  STP/LDP overhead on every call).
- Make the "live-across-call" detection prefer callee-saved
  X19-X28 when coloring a value that crosses a function-call IR op
  (correct, no per-call overhead).

The X12-preserve wrappers shipped by A18 attempt-4 in
`game/kernel/jak1/kscheme.cpp::make_x12_preserve_wrapper_arm64` and
`game/kernel/common/klink.cpp::klink_a18_install_x12_preserve_wrappers`
become inert once this fix lands (no clobber to preserve). You may
leave them in or remove them — the post-fix behavior is identical
either way. **Recommendation: leave them in until A19 validation
passes, then a follow-up commit can remove them.**

### Bug 2: field-offset off-by-4 in arm64 emit

**Evidence** (from `A18-attempt-4-next-blocker.md` §106-159):

```
find-gap-by-size's first body statement is (-> this first-gap):
  0x21231d34f0  0x8b0f00b0  ADD X16, X5, X15      ; X16 = host(this)
  0x21231d34f4  0xb9403203  LDR W3, [X16, #0x30]  ; W3 = [host(this) + 48]
```

The instruction `0xb9403203` decodes (LDR Wt, [Xn, #imm12 LSL #2])
to `LDR W3, [X16, #0x30]` — offset **48**.

Per `goal_src/jak1/kernel/gkernel-h.gc:292+`, the dead-pool-heap
layout is:

| Inherited | offset | size |
|-----------|--------|------|
| basic type-tag | -4 (offset 0 = first field) | 4 |
| process-tree (name, mask, parent, brother, child, ppointer, self) | 4..31 | 28 |
| dead-pool (no new fields) | (unchanged) | 0 |
| **dead-pool-heap.allocated-length** | 32 | 4 |
| dead-pool-heap.compact-time | 36 | 4 |
| dead-pool-heap.compact-count-targ | 40 | 4 |
| dead-pool-heap.compact-count | 44 | 4 |
| dead-pool-heap.fill-percent (float) | 48 | 4 |
| **dead-pool-heap.first-gap** | **52** | 4 |

So `(-> this first-gap)` should emit `LDR Wt, [X16, #0x34]` (offset
52), but the arm64 emit produces `LDR Wt, [X16, #0x30]` (offset 48 =
fill-percent — the wrong field, reinterpreted as a pointer).

The same -4 pattern surfaces in other emitted methods sampled by
attempt-4:
- `compact-time` read site: offset 32 (= allocated-length) instead
  of 36 (= compact-time).
- `dead-list.next` write site (a nested offset): 0x60 (= 96) instead
  of 0x64 (= 100, = dead-list@92 + next@8).

x86 ground truth: the desktop build boots and reaches the title
screen, which requires `find-gap-by-size` returning the correct
field. So x86 emit must encode offset 52 here, not 48. This is
an arm64-only emit bug.

**Likely fix surface**: `goalc/emitter/IGenARM64.cpp`. The lowering
of basic-relative `LDR/STR` (probably the helper that builds
`LDR Wt, [Xn, #imm12]` from an IR_LoadConstOffset / IR_StoreConstOffset
operand) is subtracting 4 from the offset before encoding it as the
imm12 field. Possible explanations:
- Confusion with the basic type-tag adjustment: basic types have
  the type-tag at offset 0 and fields starting at offset 4. Some
  emitter helper may be assuming the IR offset is "from start of
  fields" (= type-tag + 4) and subtracting 4 to convert it to
  "from start of object". This breaks because the IR already gives
  the from-start-of-object offset.
- Or: the emitter helper treats imm12 as `(offset / 4) - 1` instead
  of `offset / 4`.

Verify via single-instruction unit test — see deliverables.

## Bucket-A handoff

A19 supersedes A6 / A8 / A9's earlier "narrow codegen unlock"
hypotheses, all of which honest-exited because their scope was too
narrow OR because they were chasing the wrong layer. A19 has the
right diagnosis and the right surface.

## Goal

Land both fixes. After A19, qemu boot must:
- Pass `link finish: time-of-day` (already happens, at 216).
- Successfully execute `start-time-of-day`'s top-level body (which
  triggers get-process → find-gap-by-size today and dies inside
  the body because of the off-by-4-poisoned linked-list manipulation).
- Continue linking subsequent CGOs (advance link-finish count > 216
  by at least 30).

## Scope (locks)

**UNLOCKED for A19:**

- `goalc/regalloc/Allocator_v2.cpp` — for the X12 fix.
- `goalc/regalloc/Allocator_v2.h` — if header changes are needed.
- `goalc/regalloc/allocator_interface.h` — only if the X12 fix
  needs an interface change (avoid if possible).
- `goalc/emitter/IGenARM64.cpp` — for the off-by-4 fix.
- `goalc/emitter/IGenARM64.h` — if header changes are needed.
- `goalc/CMakeLists.txt` — only if a new unit-test target is added.
- `.autoport/tests/emitter/` — add unit tests for both fixes.
- `.autoport/reports/A19-*.md` — fix summary + baseline + diagnostic.
- `.autoport/reports/A19-baseline-arm64-cgo-hashes.txt` — NEW
  baseline file (replaces A17 baseline for arm64 CGO byte-identity).
- `game/kernel/jak1/kscheme.cpp` + `klink.cpp` — only to add a feature
  flag that disables the A18 X12-preserve wrappers when A19's fix is
  in place (no-op behavior). Optional.

**STILL LOCKED:**

- `goalc/emitter/IGenX86_64.{cpp,h}` — x86 emit must NOT change.
- `goalc/compiler/IR.{cpp,h}` — IR generation is shared between
  x86 and arm64; do not touch unless you have written-down proof
  the bug lives there (then ASK the supervisor for an unlock).
- `goalc/compiler/CodeGenerator.{cpp,h}` — same reasoning.
- `goalc/compiler/Compiler.cpp` and all of `goalc/compiler/*` except
  IR if escalated.
- `goalc/regalloc/Allocator.cpp` — the shared regalloc state.
  (`Allocator_v2.cpp` is the arm64-only one.)
- `goalc/regalloc/allocate_common.cpp` — shared.
- `goalc/debugger/*`.
- `goalc/data_compiler/*`.
- All of `game/kernel/common/*` and `game/kernel/jak1/*` EXCEPT
  the optional feature-flag in kscheme.cpp + klink.cpp.
- `game/kernel/asm_funcs_arm64.s`.
- `android/*` and `game/linux-arm64/*` (no runtime changes in A19).
- `.autoport/validators/*` (NEVER edit validator scripts —
  cookbook §13).
- `.autoport/lib/*` (NEVER edit supervisor lib — cookbook §13).

## Anti-cheat invariants

Inherited from A6–A18. **Critical for A19**:

- **x86 CGOs MUST be byte-identical to A2 baseline.** This is the
  hard regression check: if any x86 CGO changes, you broke shared
  code. `.autoport/lib/cgo_hash_check.sh` runs this.
- **arm64 CGOs MUST change** (every emitted basic-relative
  LDR/STR will encode at the corrected offset; every emitted
  function with X12-live-across-call will have a different save
  list). A new baseline `A19-baseline-arm64-cgo-hashes.txt` is
  the deliverable.
- 0 dodges. No `__attribute__((weak))`, no MAP_FIXED tricks, no
  silent `return 0` stubs, no fake-printf "link finish:".
- 0 changes to anti-cheat surfaces:
  - `a18_method_zero_trap` body stays `_Exit(13)`.
  - No edits to lib/validators.
- The X12-preserve wrappers MAY remain in place (they become inert
  once the regalloc fix lands). If you remove them, do so in a
  separate commit so the regalloc-fix-only commit is small and
  reviewable.

## Required deliverables

1. **The X12 regalloc fix** in `goalc/regalloc/Allocator_v2.cpp`.
   Single commit with a clear message naming the bug pattern.
2. **The off-by-4 emit fix** in `goalc/emitter/IGenARM64.cpp`.
   Single commit. Message must cite the diagnostic byte (`0xb9403203`)
   and the expected post-fix byte (`0xb9403403`).
3. **Unit tests** under `.autoport/tests/emitter/` (or `test/diff/`)
   for both fixes:
   - Field-offset round-trip: compile `(deftype foo (basic) ((a int32)
     (b int32) (c int32)))` and assert the arm64 emit for
     `(-> obj c)` encodes offset 0x08 (not 0x04).
   - X12 live-across-call: compile a function that stashes a value in
     X12 and calls another GOAL function across it, assert the
     emitted save list includes X12 (or that the value is in
     X19-X28 instead).
4. **`A19-fix-summary.md`** — short report on what changed, citing
   the diagnostic disasm before+after.
5. **`A19-baseline-arm64-cgo-hashes.txt`** — fresh `sha256sum` of
   every `out/jak1-arm64/iso/*.CGO` after rebuild. This becomes the
   new arm64 baseline.
6. **qemu boot advance**: `bash .autoport/lib/qemu_repro.sh` must
   reach **at least 246 link-finishes** (216 + 30). The exact count
   is less important than the strict advance past 216, but A19's
   fix should unblock a non-trivial number of subsequent CGOs.
7. **`A19-attempt-N-next-blocker.md`** if you can't reach > 216 link
   finishes — name the new failure mode honestly.

## Honest exit conditions

The orchestrator should honest-exit (NOT cheat) in these cases:

- **You can't find the off-by-4 in `IGenARM64.cpp`** — the bug is
  somewhere else (e.g., `IR.cpp` after all). Write an
  `A19-attempt-N-next-blocker.md` naming the file you suspect and
  the supervisor will unlock it for A20.
- **Fixing off-by-4 in `IGenARM64.cpp` breaks x86 CGO byte-identity**
  — you accidentally edited the shared LDR/STR helper instead of
  the arm64-specific one. Roll back, surface the call graph in the
  next-blocker.
- **Fixing X12 in Allocator_v2.cpp surfaces a new register-clobber
  bug** in a different register (X13, X14, etc.) — that's the same
  class of bug; if A19 has time, also fix it; if not, name it
  in the next-blocker and the supervisor will roll it into A20.
- **The fix is correct but boot still dies at 216** — the off-by-4
  diagnosis was wrong (the actual bug is somewhere downstream).
  Write a precise next-blocker.

## Forbidden cheat patterns (re-listed from §13 of cookbook)

These will get you reverted and the attempt fingerprinted:

- Editing `IGenX86_64.cpp` to "match" the off-by-4 (matching x86 to a
  broken arm64 is the wrong direction — x86 is the oracle).
- Adding a runtime patch in `game/kernel/*` that rewrites the emitted
  LDR offset after CGO load (this would be the arm64 equivalent of
  the kStateSeq cheat — patching the binary to mask a codegen bug).
- Adding an "arm64 offset adjustment table" in `klink.cpp` (same
  shape as above).
- Synthesising a fake type/method that pre-empts the dispatch
  (A18 attempt-2 cheat).
- Loosening the validator's "qemu link-finish > 246" check.

## Cost expectation

180-300 min for the full pair-fix + tests + baseline regen.

- 30-60 min: read attempt-4 evidence, locate the IGenARM64
  lowering of IR_LoadConstOffset, write a single-instruction unit
  test that reproduces the off-by-4 in isolation.
- 30-60 min: fix the off-by-4. Tiny one-line fix likely, but make
  sure unit test passes.
- 30-60 min: locate the regalloc call-clobber path in
  Allocator_v2.cpp, write a unit test that reproduces the X12 miss.
- 30-60 min: fix X12. Could be small or could need a different
  approach.
- 30-60 min: rebuild arm64 kernel + game CGOs, regenerate baseline,
  run qemu_repro, write fix summary.

## Rate-budget caution

Each A18 attempt cost ~$33 (4 attempts ≈ $132). A19 will likely cost
$30-60 per attempt. **Aim to pass on attempt 1.** Read the attempt-4
report carefully BEFORE writing any code.
