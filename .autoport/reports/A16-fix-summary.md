# A16 fix summary — device CPU divergence diagnostic captured; the
# A15-attempt-2 x16-clobber hypothesis is REFUTED at the current
# baseline, and A17 should be authored as emitter-side IDIV spill
# (claude's A16-b) rather than a regalloc-layer fix

Authored 2026-05-24 in phase A16-device-cpu-divergence-diag.
Diagnostic-only phase — no codegen changes.

## TL;DR

The new `A16-DIAG adrp/add pair walk` runs in the SIGSEGV/SIGILL/SIGBUS
handlers in both `game/linux-arm64/linux_arm64_main.cpp` and
`android/gk_android_main.cpp`. For each ADRP/ADD pair in the lr-256..
lr-8 window it walks forward up to 32 instructions and emits one of:

- `A16-DIAG x16-clobber: ... clobbered-between TRUE` — a later write
  to the ADRP target reg Xd reached Xd before any read.
- `A16-DIAG preserved:   ... clobbered-between FALSE` — Xd was read
  before any write (Xd's value survived to its sym-MEM consumer).
- `A16-DIAG no-use:      ...` — neither read nor write in the window.

Captured output from BOTH qemu (`.autoport/reports/A8-qemu-repro.log`)
and the Redmi Note 9 Pro device (`.autoport/reports/A16-device-diag-
output.txt`, derived from `.autoport/reports/D4-boot.log`):

| Observation | qemu-aarch64-static | Redmi Note 9 Pro Cortex-A76 |
|------------|--------------------:|----------------------------:|
| Signal     | sig=7 SIGBUS        | sig=7 SIGBUS                 |
| PC (= ee_base + offset) | 0x2123084812 (unaligned, bit 1 set) | 0x7208f85cf3 (unaligned, bits 0+1 set) |
| ee_base (X15) | 0x2123000000     | 0x7208f08000                 |
| X16 at crash | 0x212319b2a4     | 0x72090631c4                 |
| X16 sym-name | "sin*!" (hash 0xff8c9691) | "sin" (hash 0xff8c9691) |
| X16 sym-slot value | 0x52d0b4 (valid fn-ptr) | 0x4ea184 (valid fn-ptr) |
| X8 at crash (= sin*! ptr / 10 + ee_base) | 0x2123084812 | 0x7208f85cf3 |
| ADRP/ADD pairs in lr-256..lr-8 | 1 | 1 |
| A16-DIAG entries: clobber | **0** | **0** |
| A16-DIAG entries: preserved | 1 | 1 |
| A16-DIAG entries: no-use | 0 | 0 |
| Link-finish count before crash | 166 | 166 (matches qemu) |

**Both the qemu and the device crash at the SAME bug**: the post-A14
`sin*!` `SDIV X8, X8, X9` site that clobbers the function pointer in
X8 before the `BLR X8` (the A14-attempt-1-next-blocker root cause).
X16 is preserved correctly across the lr-window on BOTH backends.
There is **no x16-clobber at the current baseline** — qemu and device
agree.

## What this refutes

The A15-attempt-2-next-blocker hypothesis was:

> One of the redistributed assignments [under the A15 fix] puts a live
> vreg in a register that's clobbered by a ADRP/ADD/LDR sym-slot
> triplet emitted by the GOAL top-level's sym initializer. The
> clobbered register happens to be x16.

The A16 diagnostic data shows this hypothesis was specifically about
the **A15-INTRODUCED state**, not about an inherent bug present at the
A11/A14 baseline. With A15 reverted, the device's `x16 = 0xe418c0f914`
garbage value (the impossible-ADRP signature documented in A15-attempt-
2-next-blocker §"Device evidence (regresses)") does NOT appear. Both
qemu and device produce the same `x16 = <valid sym slot pointer>` and
the same SIGBUS at unaligned PC from `sin*!` arithmetic in X8.

In other words: **A15's x16-clobber was a side effect of A15's regalloc
redistribution, not the underlying bug A14 left to find**.

## What this confirms

1. **The post-A14 next-blocker (sin*! SDIV-X8 collision) IS the actual
   underlying codegen bug** that has to be fixed for boot to advance
   past the 166-link-finish ceiling. Same bug on qemu, same bug on
   device. No CPU divergence at this site.

2. **The A16 diagnostic itself is functioning correctly** — it can
   correctly classify ADRP-pair / preserved / clobber, validated
   against a real crash where X16 IS preserved (which is the truth on
   both backends here).

3. **The X16 pair found on each backend is the sin\*! sym-MEM triplet**:
   - qemu: `ADRP X16, page ; ADD X16, X16, #0x2a4 ; LDR W8, [X16, #0]`
     → resolved_target = 0x212319b2a4 = sin*! sym slot
   - device: `ADRP X16, page ; ADD X16, X16, #0x1c4 ; LDR W8, [X16, #0]`
     → resolved_target = 0x72090631c4 = sin sym slot
   The X16-as-LDR-base is the "next-read" in both cases; nothing
   between the ADD and the LDR-W writes X16. So X16 reaches the
   load-base intact, the load happens, and the loaded fn-ptr lands
   in W8 — where the subsequent SDIV X8, X8, X9 destroys it.

4. **The OpenGOAL backend lays out the sin\*! call site as a single
   sym-MEM triplet, not a repeating per-CGO sym-table initializer
   loop**. The repeating-loop pattern that the A15-attempt-2 crash
   showed (the per-CGO initializer with many alternating ADRP+ADD
   pairs in the lr-window) was specific to the math-camera-h crash
   site that the A15 fix advanced to. At the actual baseline crash
   site (sin*!), there's exactly ONE pair, and it's preserved.

## Recommended A17 scope: emitter-side IDIV spill (A16-b)

Given the diagnostic data:

- **Don't** authorise another regalloc-layer fix. A15 attempts 1 and 2
  both proved that changing the V2 allocator's constraint graph for
  X8/IDIV produces whole-function ripple effects that qemu accepts
  but Cortex-A76 rejects. Two failed attempts at the same layer is
  enough evidence to switch layers.
- **Do** authorise the emitter-side IDIV spill (claude's A16-b from
  the recommended-A16-scope section of `A15-attempt-2-next-blocker.md`):

  ```
  ;; before SDIV
  sub  sp, sp, #16
  str  x8, [sp]              ; preserve caller's X8
  sdiv x8, x8, xN
  mov  Xdst, x8              ; copy result to allocated dest
  ldr  x8, [sp]              ; restore caller's X8
  add  sp, sp, #16
  ```

  This change is **emitter-local**: only the IDIV-emission site is
  rewritten. The regalloc never sees X8 as clobbered, so its
  allocations elsewhere in the function remain identical to the A14
  baseline. The byte change is contained to IDIV sites; nothing else
  shifts. Critically: this is the smallest possible byte-change that
  could possibly fix the bug, which minimises the chance of yet
  another qemu-vs-device divergence.

- **Files A17 should unlock** (mirroring what A6/A8/A10 already
  unlocked):
  - `goalc/emitter/IGenARM64.cpp` (the IDIV emit lives here).
  - `goalc/compiler/IR.cpp` (if any IR-level signalling is needed to
    distinguish "IDIV with regalloc-known-X8-clobber" from "IDIV with
    caller-X8-preserved", though ideally the emit change is enough
    without IR changes).
  - The arm64 CGO baseline file (`.autoport/reports/A17-baseline-
    arm64-cgo-hashes.txt`) should be written after the rebuild.

- **Files A17 should NOT unlock**:
  - `goalc/regalloc/*` — keep at A14 baseline. Any regalloc change is
    what got A15 in trouble.
  - `goalc/emitter/Register.h` — the A15-attempt-2 hypothesis included
    a "expand the regalloc's view of fixed-purpose regs" angle (A16-a
    in the report). The diagnostic refutes the premise; no need to
    touch Register.h.

## What the diag would have shown under A15-attempt-2 state

The A15-attempt-2 commit is reverted, so we cannot directly capture
A16-DIAG output from the math-camera-h crash that A15 had advanced to.
But based on the lr-window pattern documented in
A15-attempt-2-next-blocker.md §"Device evidence (regresses)" (the
repeating 6-instruction per-CGO sym-table initializer cycle with
alternating ADRP and ADRP+ADD pairs), we would expect the diagnostic
to emit MANY adrp-pair / adrp-solo entries, and at least one of them
to flag `clobbered-between TRUE` for the X16 that ended up holding
the garbage value `0xe418c0f914`.

The diagnostic is in place now, so if a future phase wants to recheck
that state (e.g. by temporarily re-applying A15 attempt-2 in a side
branch), the data will be captured automatically. The current phase
deliberately stays out of that scope.

## Files touched in A16

- `game/linux-arm64/linux_arm64_main.cpp` — added `decode_arm64_*`
  helpers + `dump_a16_adrp_pair_walk()` in namespace `gk_diag`; wired
  call site into `gk_sigsegv_diag` right after the A11 sym-name dumps
  and before the A11 triplet scan / raw disasm dump.
- `android/gk_android_main.cpp` — same code, with `__android_log_print
  (ANDROID_LOG_FATAL, kGkLogTag, ...)` in place of `std::fprintf
  (stderr, ...)`. Line shapes are identical so device logcat and
  qemu_repro stderr are diff-able.
- `.autoport/reports/A16-device-diag-output.txt` — captured device
  logcat lines (sig dump + A16-DIAG markers + A11-DIAG sym-name).
- `.autoport/reports/A16-fix-summary.md` — this file.

NOT touched:
- `goalc/*` (no codegen change — A16 is diagnostic-only).
- `game/kernel/asm_funcs_arm64.s`, `kscheme.cpp`, `kmachine.cpp`,
  `IOP_Kernel.{cpp,h}`, `klink.{cpp,h}`, runtime-compat files
  (still locked per A16 scope).
- `.autoport/lib/*`, `.autoport/validators/*` (supervisor-owned).

## Honest exit

This phase REPLACES "fix" with "data collection" per the phase prompt's
explicit framing:

> This phase REPLACES "fix" with "data collection". Success = data
> captured + recommendation written. The validator's check 8 (qemu
> advance > 166) is NOT required to pass — diagnostic-only phases
> don't advance the boot ceiling.

The A16 validator's checks 1-9 should pass (diag handlers changed,
markers present, x86 + arm64 CGO byte-identity preserved, A11
baseline matches, no codegen / runtime / klink touched, no
anti-cheat regressions). The device boot-ceiling stays at 166
link-finishes — exactly the same as the A14 baseline, as required
for a diagnostic-only phase.

## Anti-cheat invariants — A16 status

- 0 dodges, 0 abort/weak additions, 0 new `_stubs.cpp`, 0 inline
  `_stub(` additions, 0 rename-evasion stub-shaped functions.
- 0 modifications to codegen (IGenARM64, ObjectGenerator,
  CodeGenerator, IR, regalloc/Allocator{,_v2}.cpp), asm trampoline
  (`asm_funcs_arm64.s`), `kscheme.cpp`, `kmachine.cpp`,
  `IOP_Kernel.{cpp,h}`, `klink.{cpp,h}`, runtime-compat files.
- 0 modifications to `.autoport/lib/*` / `.autoport/validators/*`.
- x86 CGOs byte-identical to A2 baseline (only the diag handler TUs
  were rebuilt; nothing in x86 changed).
- arm64 CGOs byte-identical to A11 baseline (no goalc-arm64 rebuild
  needed; only `gk` was rebuilt for qemu, and `libgk.so` for Android).
- ENGINE.CGO CBZ-Xt,+40 occurrences unchanged from A14 baseline.

## Cost note

The phase prompt budgeted "~45-60 min" and indicated weekly rate at
87% (past the 85% natural halt threshold), with explicit autonomy
granted. The diagnostic is mechanical (decode → walk → classify),
takes a single qemu_repro + a single D4 device run to validate, and
adds **zero** risk of regression (read-only diag with safe_read_u32
protection on every memory access). The captured data plus this
recommendation should keep A17 in scope for a narrow emitter-side
fix rather than another speculative regalloc rewrite.
