# Phase A11 — texture-CGO top-level sym=0 SIGILL (sym-MEM binding gap)

## Status

**Authored 2026-05-23 by the supervisor** after A10 landed its
IR.cpp `ADD Xd, SP, #imm12` (Rn=31) fix and honestly exited with a
detailed next-blocker report
(`.autoport/reports/A10-attempt-1-next-blocker.md`).
A10 raised the boot ceiling to 104 unique CGOs linked, then the
`texture` CGO top-level SIGILLs (sig=4) on a `BLR X9` whose target
is `ee_base` because the sym-MEM slot it loads from contains 0.

## Bucket

A — runtime/linker (klink + symbol-table binding).

## Motivation

Per A10 next-blocker:

```
GK-DIAG sig=4 fault=0x720c158000 pc=0x720c158000 lr=0x720f810058
GK-DIAG x9=0x720c158000     ; BLR target = ee_base
GK-DIAG x16=0x720c2aeab4    ; sym-MEM slot addr
GK-DIAG x15=0x720c158000    ; ee_base
```

LR-relative disassembly (from A10 report):

```
lr-52  d0fe54f0  ADRP X16, page          ; the FAILING sym-MEM ADRP
lr-48  912ad210  ADD  X16, X16, #imm     ; sym slot addr materialised
lr-44  b9400209  LDR  W9, [X16, #0]      ; W9 = sym value (= 0 — slot empty)
…
lr-20  8b0f0129  ADD  X9, X9, X15        ; X9 = host(W9=0) = ee_base
lr-4   d63f0120  BLR  X9                  ; SIGILL: *(u32*)ee_base = 0 = UDF
```

Diagnosis (claude, A10):

- A5 sym-MEM encoding is correct — X16 matches the expected slot
  address for both qemu and device.
- The LDR is real (top 16 bits != A5 sentinel marker), so the runtime
  klink patcher resolved the relocation.
- The slot itself contains 0 — the symbol whose value lives at that
  slot was never bound, or bound to GOAL `nothing` (= 0), then used
  as a function pointer.

## Goal (concrete, narrow)

Two-step:

1. **Diagnose** — identify the failing sym by name.
   Instrument the GK-DIAG SIGILL handler in `android/gk_android_main.cpp`
   to walk the sym-MEM table backwards from `X16` (the LDR's base
   addr), find the matching entry in the symbol-name table, and print
   `texture-sym-zero: name=<sym_name> slot=<addr> bound_by_cgo=<...>`.
   Same change in `game/linux-arm64/linux_arm64_main.cpp`'s SIGSEGV
   handler so qemu_repro shows the same.

2. **Fix root cause** — once the failing sym is named, the root cause is
   most likely one of:
   - **CGO link-order**: the sym is defined in a later CGO. Move it
     forward in the DGO load list (data side) OR pre-bind the sym at
     `init_machine_scheme` (kernel side) with a `nothing-or-trap`
     stub that aborts loudly instead of jumping to ee_base.
   - **Missing top-level define**: a kernel-c-side symbol whose `intern_from_c` call exists for x86 but is `#ifdef`'d out for
     arm64 — restore the equivalent registration.
   - **Type-method-vs-sym confusion**: the sym is actually a method
     slot loaded via the wrong base; the emit is loading from sym-MEM
     when it should be loading from a type's method table.

Use the diagnostic output to choose the right fix. **One fix per
phase** — if the diagnostic surfaces a deeper cascade, commit the
diagnostic and the first-layer fix, then write an
`A11-attempt-N-next-blocker.md` report.

## Scope (locks)

**UNLOCKED for A11 only:**

- `android/gk_android_main.cpp` — extend the SIGSEGV/SIGILL diag
  handler to walk sym-MEM and print the failing symbol name.
- `game/linux-arm64/linux_arm64_main.cpp` — same for qemu repro.
- `game/kernel/common/klink.cpp` — narrow: only the runtime
  sym-MEM fixup path. If the fix is "pre-bind the sym at init",
  the patch lives in `init_machine_scheme` /
  `game/kernel/common/kmachine.cpp`.
- `game/kernel/common/kmachine.cpp` — narrow: only
  `init_machine_scheme` for adding a missing `intern_from_c` /
  `make_func_symbol_func` registration.
- `game/kernel/common/symbol.cpp` — narrow: optional sym-bind trace
  for diagnosis. Revert the trace at end of phase.

**STILL LOCKED:**

- All `goalc/emitter/*` files (A5/A6/A8 unlocks closed).
- `goalc/compiler/IR.cpp` (A10 unlock closed).
- `goalc/compiler/CodeGenerator.cpp` / `.h` (A9 unlock closed; A10
  removed A9 workaround cleanly).
- `.autoport/lib/classify_ir_arm64.py`.

## Anti-cheat invariants

Same as A6-A10:

- 0 `gk_recover_to_renderer` / `forced-recovery handoff` /
  `g_fault_recovery_armed` in source.
- 0 new `abort()` / `std::abort()` / `__attribute__((weak))` in
  `.cpp` / `.h` / `.s` since A10 close.
- 0 new `*_stubs.cpp` since A10 close.
- D4 validator's hardened check #10 must pass (≥3/5 SDL/GL real-init
  markers, no synthesised renderer-entered dodge).
- x86 CGOs byte-identical to A2 baseline (the change is arm64-only
  or runtime-only — must not affect x86 CGO bytes).
- Desktop x86 `gk` smoke still reaches `link finish: logo`.

## Required deliverables

1. The diag handler emits `texture-sym-zero: name=<sym_name>` (or
   equivalent) when the SIGILL fires — committed before any fix
   code so we have evidence-of-bug.
2. The fix — one of the three candidate angles above, narrowly
   scoped, with `#ifdef __aarch64__` or arm64-only file split where
   feasible.
3. arm64 CGOs regenerated if any compiler change; new
   `.autoport/reports/A11-baseline-arm64-cgo-hashes.txt`.
4. CGO sync into APK assets:
   `cp out/jak1-arm64/iso/{KERNEL,ENGINE,GAME}.CGO android/app/src/jak1/assets/iso_data/jak1/`
5. `bash .autoport/lib/qemu_repro.sh` — must reach `link finish: logo`
   OR `engine: state=` (post-texture progression).
6. `bash .autoport/validators/phase-D4-android-apk-title.sh` exits 0
   end-to-end with hardened SDL/GL marker check.
7. `.autoport/reports/A11-fix-summary.md` — names the failing sym,
   the root cause, and the byte-level fix.

## Honest exit condition

If the diagnostic identifies the failing sym but the fix needs an
unlock beyond A11's scope (e.g. a new `goalc/data_compiler/*` unlock
for DGO ordering), commit the diagnostic + sym name + analysis and
write `A11-attempt-N-next-blocker.md`. The supervisor will read it
and author A12 narrowly.

## Cost expectation

Diagnosis is mostly mechanical (walk sym-MEM table from a known
addr). Fix is one of three candidates depending on diag output.
Budget: ~90 min / $40-60.

## Rate-budget caution

Weekly rate is at 74% when this phase starts. Each cascade phase
adds ~5-10% to weekly. If A11 takes more than 1 attempt, weekly
could approach 85% halt threshold. **Bias toward honest-exit-with-diagnosis**
over multi-class fix attempts. The diagnostic alone is worth a
commit — it converts "unknown sym" into "named sym" and dramatically
narrows A12's scope if needed.
