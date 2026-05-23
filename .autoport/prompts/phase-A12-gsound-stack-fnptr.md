# Phase A12 — gsound stack-loaded fn-ptr=0 SIGILL (post-FFI-bridge ceiling)

## First step — read the cookbook

Before grepping the goalc tree or re-deriving lock state, read
`.autoport/CODEGEN_COOKBOOK.md`. It compresses what A6→A11 each
re-discovered: encoding helpers, lock structure with anchors,
build+test cycle, GK-DIAG output decoder, anti-cheat enumeration,
per-phase yield log. ~30 seconds of focused reading saves 5–15
minutes of rediscovery.

## Status

**Authored 2026-05-23 by the supervisor** after A11 landed its
runtime FFI arg-bridge (commit ba7bd3c74) and honestly exited with a
detailed next-blocker report
(`.autoport/reports/A11-attempt-3-next-blocker.md`).
A11 raised the boot ceiling from 104 to 156 unique CGOs linked (+52,
biggest single-phase yield in the cascade). The new ceiling is a
sig=4 SIGILL at `gsound` top-level: a function pointer loaded from
a stack slot is 0, BLR jumps to `ee_base`, hits a zero word = UDF #0.

## Bucket

A — runtime/linker (diag + sym-binding extension).

## Motivation

Per A11 next-blocker, the failing site (LR-relative disasm):

```
lr-152 f0ff5e70  ADRP X16, page          ; sym ptr setup (not the failing LDR base)
lr-148 912b3210  ADD  X16, X16, #0xacc
lr-144 b9400209  LDR  W9, [X16, #0]      ; W9 = some sym value
…
lr-44  f94007e9  LDR  X9,  [SP, #8]
lr-36  f9400be9  LDR  X9,  [SP, #16]
lr-24  f9400feb  LDR  X11, [SP, #24]     ; load fn-ptr from stack — 0!
lr-20  8b0f016b  ADD  X11, X11, X15      ; X11 = host(0) = ee_base
lr-16  a9bf17e3  STP  X3, X5, [SP, #-16]!
lr-12  a9bf2fea  STP  X10, X11, [SP, #-16]!
lr-8   f81f0ff7  STR  X23, [SP, #-16]!
lr-4   d63f0160  BLR  X11                 ; SIGILL — *(u32*)ee_base = UDF
```

GK-DIAG dump shows the loaded value is 0 (`X11=0 → ADD X15 → ee_base`),
and X16 is OUTSIDE the sym-MEM range (so A11's
`gk_diag::dump_sym_name_at_slot` returned `name="<empty>"
in_sym_range=0`). The A11 stack-dump diagnostic confirmed `sp+72 = ZERO`
(= pre-call SP+24 after the call_r64 save sequence pushed 48 bytes).

Three candidate causes per claude's A11 analysis:

1. **Sym-load returned 0 and got spilled** — an earlier ADRP+LDR
   triplet in the same function produced W9=0 (because the sym was
   unbound or `nothing`), which got STR'd to `[SP, #24]` and reloaded
   into X11 at lr-24.
2. **Method-table slot = 0** — `(method-of obj some-method-name)`
   where the type's method-table cell is 0.
3. **Uninitialised struct field** — a process / thread / sound-iop
   struct field that should have been initialised at intern time
   but wasn't on arm64.

## Goal (concrete, narrow)

**Step 1 — extend the diag**: backward-trace from the LDR sites
(lr-44, lr-36, lr-24) to the store that put 0 in the slot. Output
shape:

```
A12-DIAG stack-fnptr-zero: lr=… slot=[SP, #24] addr=… value=0
A12-DIAG provenance-trace: stored-by=<PC>  inst=<encoding>
A12-DIAG     stored-from=<reg> origin=<earlier ADRP+LDR base, or "spill", or "uninit">
A12-DIAG sym-walk-back: name=<sym_name> if the origin is a sym-MEM LDR
```

**Step 2 — fix the root cause** based on what step 1 names:

- If a sym is unbound, add an explicit `make_function_symbol_from_c`
  registration in `init_machine_scheme` (same pattern as A11's
  `klink_a11_ensure_pc_mips2c_bound`).
- If a method-table slot is unset, find the corresponding
  `(defmethod …)` and verify the runtime's method-set path runs.
- If a struct field is uninitialised, find the missing
  initialisation in `kmachine.cpp` or equivalent.

One fix per phase. If step 1 surfaces a deeper cascade, commit the
diagnostic + name and write `A12-attempt-N-next-blocker.md`.

## Scope (locks)

**UNLOCKED for A12 only** (same as A11 plus a memory-walk helper):

- `android/gk_android_main.cpp` — extend SIGILL handler with
  backward-trace.
- `game/linux-arm64/linux_arm64_main.cpp` — same for qemu.
- `game/kernel/common/klink.cpp` — runtime sym-MEM patcher /
  bind hooks.
- `game/kernel/common/kmachine.cpp` — `init_machine_scheme`
  registrations.
- `game/kernel/common/symbol.cpp` — symbol-bind trace.

**STILL LOCKED** (carried forward from A6–A11):

- All `goalc/emitter/*` (codegen).
- `goalc/compiler/IR.cpp`, `CodeGenerator.cpp/.h` (codegen).
- `.autoport/lib/classify_ir_arm64.py`.
- `game/kernel/asm_funcs_arm64.s` (FFI trampoline — codegen-owned).
- `game/kernel/common/kscheme.cpp` (A11-touched; locked in A12).
- `.autoport/lib/*.sh`, `.autoport/lib/*.py`,
  `.autoport/validators/*.sh` (supervisor-owned test infra).

## Anti-cheat invariants

Inherited from A6–A11 (see the cookbook §6):

- 0 `gk_recover_to_renderer` / `forced-recovery handoff` /
  `g_fault_recovery_armed` in source.
- 0 new `abort()` / `std::abort()` / `__attribute__((weak))` since
  A11 close.
- 0 new `*_stubs.cpp` AND 0 inline `_stub(` additions since A11 close.
- 0 modifications to `.autoport/lib/*` or `.autoport/validators/*`.
- 0 modifications to `game/kernel/asm_funcs_arm64.s`.
- 0 modifications to `game/kernel/common/kscheme.cpp` (A11-touched;
  the runtime FFI bridge stands as-is).
- D4 hardened SDL/GL check (≥3/5 markers, no dodge).
- x86 CGOs byte-identical to A2 baseline.
- **arm64 CGOs byte-identical to A11 baseline** (regenerate baseline
  from A11 post-fix CGOs and check against that). A12 unlocks NO
  goalc / asm code, so CGO bytes MUST NOT change.
- Desktop x86 `gk` smoke still reaches `link finish: logo`.
- Link-finish count regression check: ≥ 156 (the A11 ceiling).
  Going below 156 means the A12 fix broke prior progress.

## Required deliverables

1. The diag handler emits `A12-DIAG stack-fnptr-zero` + provenance
   trace at the failing SIGILL — committed before any fix code so
   we have evidence-of-bug.
2. The fix — one of the candidate angles above, narrowly scoped.
3. arm64 CGOs regenerated if any compiler change (should be 0); new
   `.autoport/reports/A12-baseline-arm64-cgo-hashes.txt` matching
   A11's baseline if no codegen change.
4. `bash .autoport/lib/qemu_repro.sh` — must reach `link finish: logo`
   OR `link finish: loader` OR `engine: state=`.
5. `bash .autoport/validators/phase-A12-gsound-stack-fnptr.sh` exits 0.
6. `.autoport/reports/A12-fix-summary.md` — names the failing
   slot's provenance (which earlier store wrote 0), the root cause,
   and the fix.

## Honest exit condition

If the diagnostic identifies the provenance but the fix needs an
unlock beyond A12's scope (e.g. a `goalc/data_compiler/*` unlock for
DGO ordering, or a structural change in the GOAL source for a
missing `(defmethod …)`), commit the diagnostic + analysis and
write `A12-attempt-N-next-blocker.md`. The supervisor will read it
and author A13.

## Cost expectation

The A11 attempt-2/3 cycle showed that diag-first work with the
cookbook + anti-cheat in place produces honest +52 CGO yield per
phase. Budget ~90 min / $40-60 for diag + fix.

## Rate-budget caution

Weekly rate at 80% when this phase starts. One more A-phase fits;
two pushes against the 85% halt threshold. **Bias toward
honest-exit-with-diagnosis** if a quick fix isn't apparent — the
backward-trace alone is worth a commit because it converts "unknown
0 in stack slot" into "named provenance" and dramatically narrows
A13's scope if needed.
