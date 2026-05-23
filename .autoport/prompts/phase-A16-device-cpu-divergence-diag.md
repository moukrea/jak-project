# Phase A16 — diagnose what the Redmi Note 9 Pro CPU rejects that qemu accepts

## First step — read the cookbook

Read `.autoport/CODEGEN_COOKBOOK.md`. Pay particular attention to §11
"What NOT to do" — the last entry is the A15 attempt-1/2 qemu-vs-device
divergence lesson which gates this phase.

## Status

**Authored 2026-05-24 by the supervisor** after A15 attempts 1 and 2
both got reverted for the same root cause: a regalloc change advanced
qemu boot (+46 link-finishes) but regressed real-device boot (-101 to
-113 link-finishes). claude's A15 attempt-2 next-blocker
(`A15-attempt-2-next-blocker.md`) pinpointed the device crash as a
clobbered X16 inside the per-CGO sym-table initializer loop —
specifically `x16 = 0xe418c0f914`, a value impossible to produce via
any honest ADRP on this device's address space.

**Two failed fix attempts is enough — we need data, not more guesses.**

A16 is a **diagnostic-only phase**: capture exactly what the device CPU
rejects, so A17 can be precisely targeted.

## Bucket

A — diagnostics (no codegen change).

## Goal

Add a GK-DIAG dump that, on the device SIGSEGV with `x16` containing
an impossible-ADRP value, walks back through the lr-window decoding
**each ADRP/ADD pair** and printing:

```
A16-DIAG adrp-pair: pc=<addr> adrp_enc=<hex> add_enc=<hex>
        adrp_rd=X<n> add_rn=X<n> add_rd=X<n> imm12=<hex>
        resolved_target=<addr>   <-- the GOAL pointer the pair produced
```

Then walk forward from each ADRP/ADD pair until either:

- The next instruction that READS the same Xd (which validates that
  the value was preserved), OR
- The first instruction that WRITES Xd before the read (THIS is the
  clobber site — print it explicitly:

```
A16-DIAG x16-clobber: adrp@<addr> resolved=<addr>
        next-write@<addr> instr=<hex> decoded=<...>
        next-read@<addr>  instr=<hex> decoded=<...>
        clobbered-between TRUE
```

Apply the same diag to the linux_arm64 SIGSEGV handler so qemu_repro
can reproduce the diag flow even though qemu doesn't trigger the
clobber. The output difference (qemu prints "preserved" entries,
device prints a "clobber" entry) is itself the data we need.

## What we expect to learn

Per claude's hypothesis in `A15-attempt-2-next-blocker.md`:

> One of the redistributed assignments puts a live vreg in a register
> that's clobbered by a ADRP/ADD/LDR sym-slot triplet emitted by the
> GOAL top-level's sym initializer. The clobbered register happens
> to be x16.

If the diagnostic confirms x16's value flows from ADRP, gets clobbered
by a specific instruction in between, the supervisor can:

- Author A17 as **emitter-side IDIV spill** (claude's A16-b) IF the
  clobber is from an IDIV-class emit reaching x16.
- Author A17 as **explicit X16 modelling in regalloc** IF the clobber
  is from a regular regalloc-chosen vreg reuse of x16.
- Author A17 as a **specific arm64 ISA quirk avoidance** IF the
  clobber is from an instruction qemu accepts but Cortex-A76 refuses
  to execute correctly.

We don't know which yet. The diagnostic tells us.

## Scope (locks)

**UNLOCKED for A16 only:**

- `game/linux-arm64/linux_arm64_main.cpp` — extend SIGSEGV diag with
  the ADRP/ADD walk.
- `android/gk_android_main.cpp` — same.

**STILL LOCKED** (carried forward from A6–A15):

- All `goalc/*` (no codegen change — A16 is diagnostic-only).
- `game/kernel/asm_funcs_arm64.s`.
- `game/kernel/common/kscheme.cpp`.
- `game/kernel/common/kmachine.cpp`.
- `game/system/IOP_Kernel.{cpp,h}`.
- `game/linux-arm64/linux_arm64_runtime_compat.cpp`.
- `android/android_runtime_compat.cpp`.
- `game/kernel/common/klink.{cpp,h}`.
- `.autoport/lib/*.sh`, `.autoport/lib/*.py`,
  `.autoport/validators/*.sh` (supervisor-owned).

## Anti-cheat invariants

Inherited. **Key**:

- arm64 CGOs MUST remain byte-identical to A11 baseline (no codegen
  change — this phase is diagnostic-only).
- x86 CGOs byte-identical to A2 baseline.
- All anti-cheat checks (dodge, abort, weak, stubs, inline-stubs,
  rename-evasion, infra-lock, asm-trampoline lock, CBZ fingerprint)
  must remain green.
- Link-finish count regression check: ≥ 166 (A14 baseline). This
  phase shouldn't change the count at all (no codegen change), so
  166 is the floor.

## Required deliverables

1. The diag handler emits `A16-DIAG adrp-pair:` for every ADRP/ADD
   pair in the lr-256..lr-4 window when a SIGSEGV fires.
2. The diag handler emits `A16-DIAG x16-clobber: ... clobbered-between
   TRUE` for the specific pair whose Xd was overwritten before being
   read by a subsequent LDR/STR.
3. Run the device validator and capture the A16-DIAG output in
   `.autoport/reports/A16-device-diag-output.txt`.
4. `.autoport/reports/A16-fix-summary.md` — names the specific clobber
   site identified by the diag output, with a hypothesis for A17's
   scope.

## Honest exit

This phase REPLACES "fix" with "data collection". Success = data
captured + recommendation written. The validator's check 8 (qemu
advance > 166) is NOT required to pass — diagnostic-only phases
don't advance the boot ceiling.

## Cost expectation

~45-60 min. The diag is mechanical (decode ADRP/ADD via the existing
A11 helper pattern; walk forward; track Xd usage). Then one device
run to capture the output.

## Rate-budget caution

Weekly rate is at 87% — well past the natural halt threshold. The
user has explicitly granted autonomy ("FIGURE IT OUT AUTONOMOUSLY")
to make progress toward title screen on device. A16 is the
cheapest-possible information-gathering step before the next codegen
attempt.
