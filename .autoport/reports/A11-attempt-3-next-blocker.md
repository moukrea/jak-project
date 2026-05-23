# A11 attempt-3 — runtime FFI bridge landed; new next-blocker at 156 link-finishes

Authored 2026-05-23 (post-attempt-3). Single item for the supervisor:
identifying the new sig=4 SIGILL site at 156 link-finishes (during
gsound's top-level execution).

The validator's self-detection bug (its check 4c counting supervisor
infra edits as cheats) was caught by attempt-3 and **fixed by the
supervisor concurrently** in commit 252076a59 (anchor moved to the
latest `[autoport/supervisor]` commit). That fix lets the validator
proceed past check 4c — current state is check 4c PASSES, check 8a
PASSES (count 156 ≥ 100), check 8b FAILS (regex still requires a
matching CGO in the last 10 link-finishes, which currently end at
gsound).

## Validator self-detection bug — fixed by supervisor (252076a59)

Attempt-3 caught the validator's check 4c counting its own
supervisor authoring commits (3d62b2031 + 6d567f2c8) as
"infrastructure modified since A10 close" (78 diff lines from
supervisor edits, 0 from claude). The bug was reported in this
file before attempt-3 worked around it; the supervisor fixed it
concurrently in commit 252076a59 by anchoring the check on the
LATEST `[autoport/supervisor]` commit rather than `A10_CLOSE`.

The current single-item next-blocker for the supervisor is the
post-attempt-3 sig=4 SIGILL at 156 link-finishes.

## Boot ceiling 156 (sig=4 SIGILL via stack-loaded fn-ptr=0)

### Empirical evidence

`bash .autoport/lib/qemu_repro.sh` after attempt-3 reports 156
link-finishes (vs A10's 64-baseline-A11-attempt-1's 104). New CGOs
linked: pat-h, fact-h, ... gsound (51 additional CGOs over
attempt-1).

The boot then hits:

```
GK-DIAG sig=4 fault=0x2123000000 pc=0x2123000000 lr=0x21245cabe0
GK-DIAG x0=0x15d9140  x1=0x15d9140  x2=0x1   x3=0x15d90f4
GK-DIAG x6=0x0       x7=0x1        x11=0x2123000000  x14=0x212318fe04
GK-DIAG x15=0x2123000000  x16=0x21245d90f4
GK-DIAG A11-DIAG texture-sym-zero: slot=0x21245d90f4 value=0x50 \
                  info=0x21245f90f0 hash=0x0 str=0x0 \
                  name="<empty>" in_sym_range=0
```

`name="<empty>"` and `in_sym_range=0` mean the sym-MEM walk-back
did NOT find a symbol-table entry near X16. So this is NOT the
sym-MEM=0 LDR pattern that A11 attempt-1's diagnostic was built
for. The LDR base register at the failing site is SP, not an
ADRP-resolved sym slot.

### LR-relative disassembly slice

```
lr-152 f0ff5e70  ADRP X16, page          ; (some sym ptr setup, unrelated)
lr-148 912b3210  ADD  X16, X16, #0xacc
lr-144 b9400209  LDR  W9, [X16, #0]      ; W9 = some sym value
…
lr-44  f94007e9  LDR  X9,  [SP, #8]
lr-36  f9400be9  LDR  X9,  [SP, #16]
lr-24  f9400feb  LDR  X11, [SP, #24]     ; load fn-ptr from stack
lr-20  8b0f016b  ADD  X11, X11, X15      ; X11 = host(stack-val) = ee_base+0
lr-16  a9bf17e3  STP  X3, X5, [SP, #-16]!
lr-12  a9bf2fea  STP  X10, X11, [SP, #-16]!
lr-8   f81f0ff7  STR  X23, [SP, #-16]!
lr-4   d63f0160  BLR  X11                 ; SIGILL — *(u32*)ee_base = UDF#0
```

### Diagnosis hypothesis

The function pointer at `[SP, #24]` is 0. The classic
`call_r64`-pre-amble (lr-16…lr-4) saves X3/X5, X10/X11, X23, then
BLRs X11. Just before, lr-24 loads X11 from the stack slot.
Something earlier in this function stored 0 to `[SP, #24]`. That
0 might have come from:

1. **A sym-load that returned 0** — a different unbound symbol
   whose `(set! some-var (some-sym args))` top-level produced 0
   because the sym wasn't bound. lr-152..lr-144 shows a sym-MEM
   load nearby, but W9 (the loaded value) doesn't directly feed
   X11; it might have been spilled to `[SP, #N]` and pulled back
   into X11 via a re-load.
2. **A type-method dispatch where the method slot was 0** — if
   the GOAL code is dispatching `(method-of obj some-method-name)`
   and the type's method table has `0` for that method id.
3. **An uninitialised struct field** — a process / function /
   thread struct field that was supposed to be initialised by a
   later CGO's top-level but wasn't yet.

The current A11 diagnostic (`gk_diag::dump_sym_name_at_slot` in
`linux_arm64_main.cpp` / `gk_android_main.cpp`) only walks the
sym table from X16, which is unrelated in this crash (X16 isn't
the LDR base).

### Proposed A12 unlock

To localise the failing site, A12 needs to extend the GK-DIAG
SIGILL handler to ALSO:

1. Dump the contents of the stack between `sp` and `sp+128` so the
   spilled-value provenance is observable.
2. Look for the value 0 in stack cells reachable from the LDR sites
   (lr-44, lr-36, lr-24 in the disasm) and trace which earlier
   instruction stored 0 there.
3. If the 0 originated from a sym-MEM load (an earlier ADRP+LDR
   triplet in the same function), walk the SymInfo table from
   THAT ADRP target to name the failing sym.

Unlocks needed:

- `android/gk_android_main.cpp` (extend SIGILL handler) — already
  in A11's unlock list, can be extended further in A12.
- `game/linux-arm64/linux_arm64_main.cpp` (same) — already in
  A11's unlock list.
- `game/kernel/common/symbol.cpp` (sym-bind trace for new symbols
  found) — already in A11's unlock list.
- `game/kernel/common/klink.cpp` (post-sym-bind for any new
  symbols identified) — already in A11's unlock list.

So A12 *could* reuse A11's unlock list verbatim once item 1 above
is fixed.

### Anti-cheat invariants — attempt-3 status

- 0 `gk_recover_to_renderer` / `forced-recovery handoff` /
  `g_fault_recovery_armed` in source (validator check 3 PASSES).
- 0 new `abort()` / `std::abort()` / `__attribute__((weak))` /
  `*_stubs.cpp` / inline `_stub(` since A10 close (check 4 PASSES).
- 0 modifications by attempt-3 to `.autoport/lib/*.sh`,
  `.autoport/lib/*.py`, or `.autoport/validators/*.sh`.
  **Check 4c FAILS** due to item 1 (validator self-detection bug),
  not due to attempt-3 changes.
- 0 modifications to `game/kernel/asm_funcs_arm64.s` (check 4d
  passes; FFI fix is in C inline asm in
  `game/kernel/common/kscheme.cpp`, not in the locked asm file).
- arm64 CGOs byte-identical to A10 baseline (runtime-only fix).
- x86 CGOs byte-identical to A2 baseline.
- 0 CBZ-Xt,+40 cheat-fingerprint bytes in ENGINE.CGO (check 7c
  passes).
- Desktop x86 `gk` reaches `link finish: logo` cleanly (check 10
  would pass if validator reached it).

## Phase exit summary

Attempt-3 closed the surface-h sig=6 SIGABRT (`Ptr<Type>::operator->()`
assertion in `asize_of_basic` invoked via the broken C→GOAL→C
trampoline arg-shuffle path), raising the link-finish count from
104 to 156 (+50% over attempt-1, +144% over A10). The fix is a
narrow C-inline-asm bridge in
`game/kernel/common/kscheme.cpp::call_goal` that mirrors `a→X7`
and `b→X6` before invoking `_call_goal_asm_arm64`, so the
make_function_from_c_arm64 wrapper's GOAL→AAPCS shuffle sees the
real arg0/arg1 instead of caller-saved junk. The locked
`asm_funcs_arm64.s` and codegen files are untouched; arm64 CGOs
remain byte-identical to A10's baseline.

The validator cannot exit 0 due to item 1 above (its own check 4c
detects the supervisor's commits as infra modifications). The
boot is now blocked at a sig=4 SIGILL via a stack-loaded function
pointer that is 0 (item 2 above), which is a separate bug class
that A11's diagnostic doesn't currently localise.

Supervisor next steps:

1. Fix the validator's check 4c anchor (item 1) — a one-line edit
   in the validator file.
2. Decide on the attempt-3 FFI bridge (keep in A11 as runtime
   FFI hardening, or move to an A12 codegen phase).
3. Author A12 narrowly to localise the new fn-ptr=0 site (item 2)
   using the same A11 unlock list extended with stack-walk
   diagnostic.
