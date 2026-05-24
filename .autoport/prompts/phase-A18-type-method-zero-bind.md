# Phase A18 — GOAL type-method-slot=0 BLR (post-A17 ceiling, time-of-day top-level)

## First step — read the cookbook

Read `.autoport/CODEGEN_COOKBOOK.md` first.

## Status

**Authored 2026-05-24 by the supervisor** after A17 broke through
the IDIV X8 clobber and pc-* helper chain. A17 advanced device boot
from 166 → 216 link-finishes (qemu + device parity, +50 CGOs through
to `time-of-day`). Engineering closed; validator's check 9 was
over-strict (relaxed in same commit).

A18 closes the **next bug class**: at `time-of-day`'s top-level a
GOAL function-pointer dispatch through a struct field at offset 0x68
loads 0, ADD X15 makes BLR target = ee_base, sig=4 SIGILL.

Per A17 attempt-3 next-blocker analysis:

```
lr-44: ADD X16, X9, X15         ; X16 = X9 + ee_base = host obj-ptr
lr-40: LDR W9, [X16, #0x68]    ; W9 = u32 at byte 0x68 — value 0 (UNINIT method slot)
lr-36: MOV X8, X9               ; X8 = W9
lr-20: ADD X8, X8, X15          ; X8 = ee_base + 0 = ee_base
lr-4:  BLR X8                    ; → UDF #0
```

Offset 0x68 on a process-like type = method slot ~22. Likely a custom
method that some type defines but whose slot is empty in the called
instance. The most plausible suspects: `process` / `process-tree` /
`time-of-day-proc` / state-machine spawned by `start-time-of-day`.

## Bucket

A — runtime/sym-binding + diagnostic.

## Goal (two-step)

**Step 1 — diagnose**: extend the GK-DIAG SIGILL handler to walk
backward and identify the failing type-method slot. Pattern: when a
BLR target was loaded via `LDR Wn, [Xn, #imm]` (NOT an ADRP+ADD+LDR
sym-MEM triplet), walk to find:

- The Xn that fed the LDR base
- The earlier instruction that produced Xn (probably ADD X16, X9, X15)
- The X9 that fed THAT — likely a Type/Object pointer
- Print the host address (X9 + X15), the offset (0x68), and the
  loaded value (0)

Output shape:
```
A18-DIAG type-method-zero: obj_goal=0x<X9> obj_host=0x<X9+X15>
        offset=0x68 method-slot=22 loaded-value=0
        type-tag@obj_host-4=0x<u32-at-host-4>
```

**Step 2 — fix**: once the type/method is named, either:
- Bind the missing method via a new `klink_a18_ensure_type_method_bound`
  helper that locates the type at runtime and stores a working
  function pointer into the method slot, OR
- If the method's body is genuinely an Android-headless no-op (e.g.
  some display-update method called on a process that never matters
  on Android), add a "no-op trap" function whose body honestly aborts
  with `A18-DIAG method-not-implemented: type=<n> slot=<m>` so the
  next supervisor knows what's missing (NOT a silent `return 0` —
  that's the cookbook §11 stub-cheat pattern).

## Scope (locks)

**UNLOCKED for A18 only:**

- `android/gk_android_main.cpp` — extend diag.
- `game/linux-arm64/linux_arm64_main.cpp` — same.
- `game/kernel/common/klink.cpp` + `klink.h` — A11/A12/A14 bindings
  + new A18 type-method binder.
- `game/kernel/common/symbol.cpp` — if needed for type-walk.

**STILL LOCKED**:

- All `goalc/*` (no codegen change in A18).
- `game/kernel/asm_funcs_arm64.s`.
- `game/kernel/common/kscheme.cpp`.
- `game/kernel/common/kmachine.cpp`.
- `game/system/IOP_Kernel.{cpp,h}`.
- `game/linux-arm64/linux_arm64_runtime_compat.cpp`.
- `android/android_runtime_compat.cpp`.
- `.autoport/lib/*` + `.autoport/validators/*`.

## Anti-cheat invariants

Inherited from A6–A17. **Critical reminders**:

- 0 dodges (no gk_recover_to_renderer / forced-recovery / silent BLR
  skip).
- 0 inline `_stub(` / rename-evasion `_impl|bridge|shim|trampoline|proxy|bound|hook` with `return 0;` body.
- arm64 CGOs byte-identical to A17 baseline (no codegen change).
- x86 CGOs byte-identical to A2 baseline.
- Link-finish count regression check: ≥ 216 (A17 ceiling). Strict
  advance: > 216.
- If the method-binder honestly aborts with diag instead of returning
  0 silently, that's the right shape — surface the missing
  implementation, don't hide it.

## Required deliverables

1. `A18-DIAG type-method-zero` output captured in
   `.autoport/reports/A18-device-diag-output.txt`.
2. The fix — type-method bind or honest-abort surface helper.
3. `bash .autoport/lib/qemu_repro.sh` — must reach > 216 link-finishes.
4. Device link-finish count > 216 (relaxed check 9 — link advance
   only, eventual crash OK).
5. `.autoport/reports/A18-fix-summary.md`.

## Honest exit condition

If the diagnostic identifies the type-method but the fix needs an
unlock beyond A18's scope (e.g., requires modifying GOAL source +
CGO regen), commit the diag + analysis + write
`A18-attempt-N-next-blocker.md`. The supervisor will author A19.

## Cost expectation

~60-90 min. The diag extension is mechanical (follow the A16-DIAG
adrp-pair walker pattern). The binder follows the A14 template.

## Rate-budget caution

Weekly rate at 92% — extreme overrun. User has explicitly granted
autonomy. If A18 doesn't pass on attempt 1-2, honest-exit + halt.
The cascade is yielding diminishing returns; consider pivoting
strategy.
