# Phase A21 — arm64 codegen deeper investigation (post-off-by-4 falsification)

## First step — read these

1. `.autoport/CODEGEN_COOKBOOK.md`.
2. `.autoport/reports/A20-attempt-1-next-blocker.md` — falsifies the
   off-by-4 hypothesis with OG_OFFSET_TRACE (196,128 trace lines per
   backend, zero-line diff after `arch=` strip) and KERNEL.CGO
   byte-scan (15 instances each of LDR Wt,[X16,#48] and [X16,#52] at
   mod-4=2 alignment). Lists 4 candidate hypotheses (H1-H4) for the
   actual 216-link-finish ceiling.
3. `.autoport/reports/A20-fix-summary.md` — the trace methodology.
4. `.autoport/reports/A19-attempt-1-next-blocker.md` — A19's X12 fix
   evidence + Bug 2 (off-by-4) disproof in encoder layer.

## Status

**Authored 2026-06-09 by the supervisor** after A20 attempt-1
honest-exited. A20 added an OG_OFFSET_TRACE diag to `goalc/compiler/IR.cpp`
and used it to prove every field-offset emit is byte-identical between
x86 and arm64. The 216-link-finish ceiling is caused by a different
bug class.

Pre-A21 supervisor reality-check:

- Verified A20's byte-scan core claim (15+15 LDR instances at
  mod-4=2 alignment, other alignments empty). VERIFIED.
- Verified OG_OFFSET_TRACE diag patch lives in HEAD at
  `goalc/compiler/IR.cpp:1440,1471,1524,1555` (all 4 codegen paths).
- Verified A19 X12 fix lives in HEAD at
  `goalc/emitter/IGenARM64.cpp:1580-1589` (call_r64 save list now
  pairs X3+X5, X10+X11, X12+X23).
- **H1 (more regalloc-clobber surfaces) is WEAK**: HEAD already saves
  all 5 regalloc-saved GPRs {X3,X5,X10,X11,X12} plus X23 in call_r64.
  Diag should still verify, but the hypothesis is unlikely.

That leaves H2/H3/H4 as the candidates A21 should discriminate
between.

## The 216-link-finish failure (restated for A21)

Last successful `link finish:` is `time-of-day` at qemu log line 619.
Crash at line 620 with no intervening `link finish:`. Crash signature:

```
GK-DIAG sig=4 fault=0x212afffe84 pc=0x212afffe84 lr=0x212afffe84
GK-DIAG x29=x30=x24..x28=0x212afffe84
GK-DIAG x12=0x21231d6344 (heap GOAL ptr 0x1d6344)
GK-DIAG x15=0x2123000000 (ee_base)
```

Multiple registers holding the same stack address suggests a **load
sequence from a corrupted save area** (e.g. `LDP Xa,Xb,[SP,#N]` with
a garbage SP/X29).

## Candidate hypotheses (from A20 next-blocker §72-173)

### H1 — second regalloc-clobber surface beyond X12

Status: WEAK per supervisor reality-check above. A21 should still run
the Allocator_v2 debug print to verify the save list matches the
emitted instructions at every BLR site, but spend more time on H2/H3/H4.

### H2 — arm64 `IR_FunctionCall::do_codegen_arm64` corrupts X16 across BLR

Possible if some emit path stages a value through X16 across a BLR
sequence. BLR doesn't naively clobber X16 but X16 is in the explicit
scratch list and not in the call_r64 save list. If post-BLR work
reads X16 expecting a pre-BLR value, that's UB.

Diagnostic: scan goalc-arm64 emit output for sequences where X16 is
loaded with a value, a BLR fires, and a subsequent instruction
references X16 without first reloading it.

### H3 — klink-time `LDR-literal imm19 out of range` NOPs

The qemu log contains **81 lines** of
`klink-arm64: LDR-literal imm19 ... out of range at 0x...` warnings.
Each one is a place where `arm_patch_ldr_literal_imm19` couldn't
compute an in-range pc-rel offset and so left the instruction at its
original sentinel encoding. Some of these may be in dma-buffer /
time-of-day code paths.

Diagnostic: log each `LDR-literal imm19 out of range` warning with
its instruction encoding, the symbol/target being resolved, and the
CGO it's in. Cross-reference against the GOAL function table.

### H4 — AAPCS arg-shuffle gap in `kscheme.cpp::call_goal`

A11 placed an AAPCS-to-GOAL arg-shuffle in `kscheme.cpp::call_goal`,
bridging C-side calls (AAPCS X0..X7) to GOAL-side (X7,X6,X2,X1,...).
If any time-of-day-reached callee is invoked via the C-side path
*without* going through the shuffle, GOAL receives `this` in X0
instead of X7 and SEGVs.

Diagnostic: instrument `kscheme.cpp::call_goal` to log every C→GOAL
boundary crossing.

## Bucket

A — emitter / compiler.

## Goal

**A21 is a diagnostic phase, not a fix phase.** The goal is to
discriminate between H2/H3/H4 with concrete runtime evidence, then
honest-exit with a `A21-attempt-N-bug-class-identified.md` report
naming ONE primary hypothesis and recommending A22's narrow fix
scope.

If during diagnosis you locate a bug whose fix fits inside A21's
narrow unlock list (linux_arm64_main, klink, Allocator_v2, kscheme),
you may land that fix — but only if the diagnostic evidence
unambiguously implicates one of those files. Out-of-scope fixes
(IGenARM64, IR.cpp, Val.cpp) **MUST** be deferred to A22; A21
should ESCALATE in next-blocker, NOT silently unlock.

## Scope (locks)

**UNLOCKED for A21:**

- `game/linux-arm64/linux_arm64_main.cpp` — extend GK-DIAG signal
  handler to dump bytes at *register* values (not just at PC/LR),
  so when X16/X29/etc hold a stack address we can decode which
  saved value was supposed to be there.
- `game/kernel/common/klink.cpp` — instrument the
  `LDR-literal imm19 out of range` warning path to log each
  occurrence's instruction encoding + symbol + CGO source. Env-gate
  with `OG_KLINK_IMM19_TRACE=1`.
- `goalc/regalloc/Allocator_v2.cpp` — env-gated debug print mode
  (`OG_REGALLOC_TRACE=1`) that dumps the `REG_saved_first_order`
  decisions per emitted `IR_FunctionCall` (which GPRs are
  expected-saved-across-call, which are live-through). Comment-
  block additions only outside the env-gate.
- `game/kernel/jak1/kscheme.cpp` — env-gated trace
  (`OG_CALLGOAL_TRACE=1`) in `call_goal` logging every C→GOAL
  boundary: caller PC, callee GOAL addr, arg registers (X0..X7).
- `.autoport/tests/emitter/` — optional unit tests.
- `.autoport/reports/A21-*.md`,
  `.autoport/reports/A21-baseline-arm64-cgo-hashes.txt`.

**STILL LOCKED:**

- `goalc/emitter/IGenARM64.{cpp,h}` — A19's X12 fix stays; A20
  proved no field-offset bug here.
- `goalc/emitter/IGenX86_64.{cpp,h}` — x86 oracle, NEVER edit.
- `goalc/compiler/IR.{cpp,h}` — A20's OG_OFFSET_TRACE diag stays;
  no further changes (Val.cpp / IR.cpp / compilation/Type.cpp all
  proven clean by A20's 196k-line zero-diff trace).
- `goalc/compiler/Val.{cpp,h}`, `goalc/compiler/compilation/Type.cpp`.
- `goalc/compiler/Compiler.cpp`, `goalc/compiler/CodeGenerator.cpp`.
- `goalc/regalloc/Allocator.cpp`, `allocate_common.cpp`.
- `goalc/emitter/ObjectGenerator.{cpp,h}`.
- `common/type_system/Type.{cpp,h}`.
- `game/kernel/common/kscheme.cpp` (the COMMON one, not jak1).
- `game/kernel/common/kmachine.cpp`, IOP_Kernel*, all other runtime.
- `game/kernel/asm_funcs_arm64.s` and the build-arm64-android
  generated `asm_funcs_arm64_gnu.s` (build artifact, not source).
- `android/*` (NEVER for A21 — diagnostic surfaces target linux-arm64
  qemu first; android extensions belong to a later phase).
- `.autoport/validators/*` (NEVER edit validator scripts).
- `.autoport/lib/*` (NEVER edit supervisor lib).

## Anti-cheat invariants

- **x86 CGOs MUST be byte-identical to A2 baseline.** A21 must not
  change any shared path. If x86 CGOs drift, you edited a shared
  file by accident.
- **arm64 CGOs SHOULD be unchanged from A19 baseline.** A21 is
  diagnostic only — env-gated patches in linux-arm64/kernel sources
  don't affect what goalc-arm64 emits. If arm64 CGOs differ, you
  edited something that ripples into the emitter and you've gone
  outside A21's intended diag-only behavior.
- `a18_method_zero_trap` body unchanged (still `_Exit(13)`).
- A19's X12 fix preserved (`kStpX12X23Push` constant + `call_r64`
  emit sequence in `IGenARM64.cpp`).
- 0 changes to anti-cheat surfaces: no `__attribute__((weak))`,
  no MAP_FIXED into ee_base region, no synthesised type tables,
  no fake `printf("link finish: …")`.

## Forbidden cheat patterns

These will get the attempt reverted and fingerprinted:

- Editing the LDR-literal warning path to silently SUPPRESS warnings
  ("fix by hiding"). The diagnostic must ADD logging, not remove it.
- Adding a runtime "register fix-up table" that rewrites X16 / X29
  values mid-execution (same shape as kStateSeq cheat).
- Editing `kscheme.cpp::call_goal` to add a behavior change beyond
  the env-gated trace (e.g. a "fix" that shifts arg registers when
  some condition holds — that's an unscoped fix in a runtime path).
- Inflating CGO hash diversity by touching unrelated files to make
  any validator check pass.
- Writing a `bug-class-identified.md` that just rehashes A20's
  hypotheses without adding NEW runtime evidence. The validator
  requires the report to reference specific qemu log lines and
  contain a sample of the new diagnostic output.

## Required deliverables

1. **At least ONE of the four diagnostic instrumentations** landed
   in HEAD, with its env-gate var name (`OG_A21_REG_TRACE` /
   `OG_KLINK_IMM19_TRACE` / `OG_REGALLOC_TRACE` /
   `OG_CALLGOAL_TRACE`).
2. **A21-diagnostic-summary.md** (≥100 lines): which diag(s) you
   added, what you ran, what you observed. Must include sample
   stderr output snippets (≥10 lines per snippet).
3. **A21-attempt-N-bug-class-identified.md** (≥150 lines): names
   ONE primary hypothesis (H1/H2/H3/H4) as the cause, with:
   - The specific runtime evidence implicating it (qemu log line
     numbers; specific bytes / register values / addresses).
   - The proposed A22 fix scope (file paths + function names).
   - What you ruled out about the OTHER hypotheses.
4. **A21-baseline-arm64-cgo-hashes.txt** — fresh sha256 of every
   `out/jak1-arm64/iso/*.CGO` (should be byte-identical to A19
   baseline since A21 is diag-only).
5. Optional: if you locate a fix that fits in A21's unlock list
   (klink.cpp, kscheme.cpp::call_goal, linux_arm64_main.cpp) and the
   fix advances qemu link-finish past 216, land it AND write
   `A21-fix-summary.md`. This is BONUS, not required.

## Honest exit conditions

- All 4 diag patches added, all 4 ran, none of H1-H4 looks like the
  primary cause — escalate. Write `A21-attempt-N-no-hypothesis-fits.md`
  with the elimination evidence for each. Supervisor will author a
  broader A22.
- Diagnosis lands on a hypothesis whose fix lies OUTSIDE A21's
  unlock list — write `A21-attempt-N-bug-class-identified.md` with
  the proposed A22 unlock and stop. Do NOT silently extend A21's
  scope.
- Build break — fix the build; don't honest-exit on a build break.
- qemu won't boot at all under your diag-patched binary — back off
  the diag (env-vars unset by default; check your `if (!getenv(...))`
  guards).

## Cost expectation

90-150 min per attempt. Diag is simpler than emit fixes — the runtime
of qemu_repro.sh is the bottleneck (5-10 min per run).

- 30 min: read references, plan which 1-2 diags to add first.
- 30-60 min: write the diag patches, rebuild gk-arm64, run
  qemu_repro.sh with the new env vars set.
- 30 min: analyze output, write the diagnostic + bug-class-identified
  reports, regenerate the baseline file.

Cost-of-attempt cap: ~$50. Honest-exit before $100 if no progress.

## Phase budget

max_turns: 600. max_retries: 6.
