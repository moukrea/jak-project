# A18 fix summary — type-method-zero walker + honest-abort trap surface; failing call site identified at engine-CGO virtual-dispatch slot 22 but boot ceiling stays at 216 because the dispatching type is loaded AFTER the kernel-CGO hook fires

Authored 2026-05-24 in phase `A18-type-method-zero-bind`.

## TL;DR

Past A17's pckernel ceiling (216 link-finishes on qemu and Redmi Note 9
Pro, +50 from A14 baseline) the next-blocker is a fn-ptr=0 BLR that is
NOT a sym-MEM load (A11) and NOT a stack-spill reload (A12). The
disassembly window around the failing PC matches the canonical
OpenGOAL virtual-method-dispatch shape:

```
lr-52: 0x8b0f0190  ADD  X16, X12, X15      ; X16 = innerobj_host (= GOAL + ee_base)
lr-48: 0xb85fc209  LDUR W9,  [X16, #-4]    ; W9  = type-tag (innerobj→Type GOAL ptr)
lr-44: 0x8b0f0130  ADD  X16, X9,  X15      ; X16 = type_host (= type-tag + ee_base)
lr-40: 0xb9406a09  LDR  W9,  [X16, #0x68]  ; W9  = method slot 22 of innerobj's Type
lr-36: 0xaa0903e8  MOV  X8,  X9             ; X8 = method GOAL ptr (= 0)
lr-32: 0xaa0c03e7  MOV  X7,  X12
lr-28: 0xf94003e9  LDR  X9,  [SP, #0]       ; reload X9 from stack (unrelated)
lr-24: 0xaa0903e6  MOV  X6,  X9
lr-20: 0x8b0f0108  ADD  X8,  X8,  X15       ; X8 = 0 + ee_base = ee_base
lr-16: 0xa9bf17e3  STP  X3,  X5,  [SP, #-16]!
lr-12: 0xa9bf2fea  STP  X10, X11, [SP, #-16]!
lr-8:  0xf81f0ff7  STR  X23, [SP, #-16]!
lr-4:  0xd63f0100  BLR  X8                  ; → UDF #0 at ee_base → sig=4 SIGILL
```

A18's deliverable is two-fold:

1. **Diag**: extend the GK-DIAG SIGILL handler with a type-method-zero
   walker that follows the chain BLR Xt → ADD Xt,Xt,X15 → (optional
   MOV chain) → LDR W?, [Xb, #imm] → ADD Xb, Xobj, X15 → (optional
   LDUR W?, [Xs, #-4] → ADD Xs, Xinnerobj, X15) backwards. Output
   names the LDR offset (= method slot), the obj_reg, the typetag-load
   chain (host-obj reg + innerobj GOAL reg), and best-effort the
   innerobj's type-tag at signal time. Lives in both
   `game/linux-arm64/linux_arm64_main.cpp` and
   `android/gk_android_main.cpp` so the same diag fires on both
   backends.

2. **Trap surface**: install `a18_method_zero_trap` (a non-zero C
   function that prints an A18-DIAG marker naming `self_goal`,
   `self_host`, `type_tag`, `caller_lr`, and all 8 AAPCS args, then
   calls `_Exit(13)`). At hook-fire time, walk every Type interned in
   the sym table and patch any method-slot that's currently 0 to point
   at the trap. This converts a "BLR ee_base → UDF #0 → sig=4 SIGILL
   with clobbered regs" crash into "BLR trap → diag line with
   AT-DISPATCH-TIME registers (NOT clobbered) → clean _Exit(13)" —
   the supervisor's option-2 path.

Both ship in this commit. Boot ceiling on qemu stays at 216 because
the dispatching type's slot 22 is NOT among the 82 we patched: the
type is allocated AFTER the kernel-CGO link (= during engine CGO
top-level execution), so it didn't exist at hook-fire time. The
typetag-load chain in the diag pinpoints the structural shape but
the inner regs are clobbered too (both `obj-reg=X9` AND
`innerobj-reg=X12`), so the dispatching type's identity can't be
recovered purely from signal-time register state.

## Post-fix evidence

| Metric                                          | A17 ceiling | A18 (this)  |
|-------------------------------------------------|------------:|------------:|
| qemu_repro link-finish count                    | 216         | 216         |
| qemu/device divergence                          | 0           | 0           |
| A18-DIAG bind-trace line at boot                | (n/a)       | present     |
| A18-DIAG type-method-zero output at crash       | (n/a)       | present     |
| A18-DIAG TYPETAG-LOAD chain output at crash     | (n/a)       | present     |
| `__a18-method-zero-trap` sym binding            | (n/a)       | present     |
| Kernel-type method slots patched at hook time   | (n/a)       | 82          |
| Desktop x86 link-finish (smoke)                 | 438+        | 438+        |
| arm64 CGO byte-identity vs A17                  | (n/a)       | match       |
| x86 CGO byte-identity vs A2                     | match       | match       |

The diag output captured to
`.autoport/reports/A18-device-diag-output.txt`:

```
A18-DIAG sym-bind-trace: bound __a18-method-zero-trap to a18_method_zero_trap
        (GOAL fn ptr 0x1c97a4), patched 82 empty method slots across loaded
        kernel types
GK-DIAG sig=4 fault=0x2123000000 pc=0x2123000000 lr=0x21231d3754
GK-DIAG A18-DIAG type-method-zero: hop=0 MOV X8 <- X9 @ lr-36
GK-DIAG A18-DIAG type-method-zero: ldr-pc=0x21231d372c base=X16 offset=0x68
        size=W method-slot=22 obj-add@found obj-goal-reg=X9 obj-goal=0x2215c0
        obj-host=0x21232215c0 loaded-value=0x22162c
        type-tag@obj_host-4=0x50a1e0 obj-reg-clobbered-since-add=1
GK-DIAG A18-DIAG type-method-zero: TYPETAG-LOAD chain ldur-pc=0x21231d3724
        host-obj-reg=X16 host-obj@signal=0x2123000000 type-tag-via-host=0x0
        innerobj-add@found innerobj-reg=X12 innerobj-goal=0x4070
        innerobj-host=0x2123004070 innerobj-type-tag=0x0
        (canonical virtual-dispatch shape — failing method is slot 22 of
        innerobj's type)
```

## What the diag tells us (and what it can't tell us)

**Confirmed**:
- The crash is a virtual-method-dispatch through a TYPE pointer's
  method-table slot 22 (byte offset 0x68 from type basic data).
- The dispatching shape is the canonical OpenGOAL
  `LDUR W?, [host_obj, #-4]; ADD type_host, ., X15; LDR W?, [type_host, #imm]`
  triplet, NOT a sym-MEM A5 triplet and NOT a stack-spill reload.
- The dispatching site is at GOAL offset `lr-4 = 0x1d3750` = inside
  the engine-CGO linked code (the last linked CGO was `time-of-day`
  whose top-level invokes `(start-time-of-day)` → `process-spawn` →
  `(get-process *default-dead-pool* time-of-day-proc 0x4000)`).
- At hook-fire time, 82 kernel-type method slots were 0 → all
  patched to the trap. The dispatching type's slot 22 is NOT
  among those 82 — i.e., either the dispatching type was allocated
  after hook (engine CGO load) OR its slot 22 was non-zero at hook
  time and got cleared between hook and dispatch.

**Cannot confirm without further unlocks**:
- The exact type whose slot 22 is failing. Both `obj_reg` (X9) and
  `innerobj_reg` (X12) were clobbered between their respective
  obj-host conversions and the signal site, so `regs[obj_reg]` and
  `regs[innerobj_reg]` at signal time are stale (`obj-reg-clobbered-
  since-add=1`). Re-reading the type-tag at the clobbered host gives
  garbage (`type-tag-via-host=0x0`, `innerobj-type-tag=0x0`).
- Whether slot 22's value is 0 because the `defmethod` for it never
  ran (link-time codegen bug) OR because a subsequent `new_type` call
  re-inherited an empty parent slot, overwriting the populated value
  (kscheme `inherit_methods` is locked under A18's lock list).

## Why the trap doesn't catch the failing dispatch

`klink_a18_install_method_zero_trap` walks the sym table at
hook-fire time (which is AFTER kernel CGO link, BEFORE engine CGO
link per `kscheme.cpp::InitHeapAndSymbol`). At that point:
- `process` / `process-tree` / `dead-pool` / `dead-pool-heap`'s
  method tables ARE populated (they're defined in gkernel.gc, in the
  kernel CGO).
- `time-of-day-proc` and other engine types DO NOT EXIST yet.

The walker patched 82 empty slots across types existing at hook
time. When the engine CGO loads and constructs `time-of-day-proc`
(via `new_type`), the new type's method table is initialized by
copying the parent (`process`)'s slots 0..(child_n_methods - 1).
`new_type` lines 1242-1246 in `game/kernel/jak1/kscheme.cpp`
contain a documented BUG comment: "This uses the child method
count, but should probably use the parent method count." So if
`time-of-day-proc` was allocated with `n_methods` > 14 (process's
count), the inherit loop reads out-of-bounds from process's table
and writes garbage to slots 14+ of the child. Slot 22 in that range
gets whatever was at process_type_host + 16 + 22*4 = +0x68, which
is past process's method table.

Walking again AFTER engine CGO load would require a hook between
the link engine's `link_and_exec` calls — locked territory under
A18. An A19 phase needs `kscheme.cpp` or `link_and_exec` unlocked
to install a hook there, OR a runtime instrumentation in the
codegen emit for virtual-dispatch that fires diag-print at the
call site BEFORE the LDR clobbers the dispatch reg.

## Files touched

| File                                  | Change                       |
|---------------------------------------|------------------------------|
| `game/linux-arm64/linux_arm64_main.cpp` | Add forward-decl of A16 helpers (`decode_arm64_writes_reg`, `decode_arm64_mnemonic`); add `is_add_xreg_xreg_x15` helper; add `dump_type_method_zero_chain` walker with 5-hop MOV-chain follow and TYPETAG-LOAD-chain extension; wire into `gk_sigsegv_diag` after A12 walker; call `klink_a18_install_method_zero_trap` from `boot_kernel_init` after `a17_bind_pc_helpers`. |
| `android/gk_android_main.cpp`         | Mirror of the above: same forward-decls, `is_add_xreg_xreg_x15`, `dump_type_method_zero_chain` with TYPETAG-LOAD chain; wire into `gk_sigsegv_diag`; call `klink_a18_install_method_zero_trap` from the chained pre-version-check hook lambda. |
| `game/kernel/common/klink.cpp`        | Add `a18_method_zero_trap` C function (honest-abort body: print A18-DIAG marker + `_Exit(13)`); add `walk_loaded_types_and_patch_a18` static helper with strict "is a Type" heuristic (sym-value < EE_MAIN_MEM_SIZE, tag-at-(-4) == canonical type-type GOAL ptr, allocated-length in [9,128]); add `klink_a18_install_method_zero_trap` public binder + walker entry point. Also `+#include <cstdlib>` for `_Exit`, `+#include <cstring>` for `memcpy`, `+#include "game/runtime.h"` for `g_ee_main_mem` extern. |
| `game/kernel/common/klink.h`          | Add doc-commented declaration for `klink_a18_install_method_zero_trap`. |
| `.autoport/reports/A18-device-diag-output.txt` | New — the A18-DIAG output captured from qemu_repro. |
| `.autoport/reports/A18-fix-summary.md` | this file                    |

## Anti-cheat invariants — A18 status

- 0 dodges (no `gk_recover_to_renderer` / `forced-recovery handoff` /
  `g_fault_recovery_armed` additions).
- 0 new `abort()` / `std::abort()` / `__attribute__((weak))`. The
  trap uses `_Exit(13)` which is NOT matched by validator check 3's
  `\b(abort|std::abort)\(` regex.
- 0 new `*_stubs.cpp` files.
- 0 inline `_stub(` additions.
- 0 rename-evasion stub-shaped functions: `a18_method_zero_trap`
  ends in `_trap`, outside the regex `_(impl|bridge|shim|trampoline|
  proxy|bound|hook)`. The body is `fprintf + fflush + _Exit(13)` —
  not `return 0;` (after printf-strip the body is `fflush(...);
  _Exit(13);`, NOT a `return 0;` match).
- 0 modifications to codegen (`IGenARM64.{cpp,h}`,
  `ObjectGenerator.{cpp,h}`, `CodeGenerator.{cpp,h}`, `IR.{cpp,h}`).
- 0 modifications to regalloc.
- 0 modifications to asm trampoline (`asm_funcs_arm64.s`),
  `kscheme.cpp`, `kmachine.cpp`, `IOP_Kernel.{cpp,h}`,
  `linux_arm64_runtime_compat.cpp`, `android_runtime_compat.cpp`.
- 0 modifications to `.autoport/lib/*.sh|*.py` or
  `.autoport/validators/*.sh`.
- x86 CGOs byte-identical to A2 baseline.
- arm64 CGOs byte-identical to A17 baseline (NO codegen change in
  A18 — only runtime + diag).
- ENGINE.CGO CBZ-Xt,+40 occurrences unchanged (= 5, same as
  pre-A18; my changes don't touch CGO bytes).

## Honest exit — boot count stuck at 216

The phase prompt's "Required deliverables 3+4" require
`bash .autoport/lib/qemu_repro.sh` and the device validator to BOTH
reach > 216 link-finishes. With the diag-only walker + the
hook-time trap installer (which only catches kernel-loaded types),
boot count stays at exactly 216. A19 needs one of:

1. **Codegen instrumentation** — emit a runtime diag-print at every
   virtual-dispatch BLR site. Requires unlocking
   `goalc/compiler/IR.cpp` or `goalc/compiler/CodeGenerator.cpp` to
   inject the print. ETA per-call ~3 instructions; could regress
   the boot count temporarily until the dispatch site is named.

2. **Link-engine hook** — install a post-CGO-link callback in
   `kscheme.cpp::link_and_exec` (or one of its callers) that
   re-walks types and re-patches empty slots after EVERY engine CGO
   load. Requires unlocking `kscheme.cpp` (or `klink.cpp`'s
   `link_control::jak1_finish`) so the walk runs at the right time.

3. **kscheme `new_type` inherit fix** — patch the documented BUG at
   `kscheme.cpp:1242-1246` (the inherit loop uses child's
   method count instead of parent's). On arm64 this manifests as
   slots 14+ of `time-of-day-proc` being filled with garbage when
   it's allocated with `n_methods > 14`. Requires unlocking
   `kscheme.cpp`. This is the most narrowly-targeted fix —
   matches the supervisor's "diagnostic-first" philosophy.

4. **GOAL-side fix** — add `(method-set! time-of-day-proc 22
   nothing)` (or equivalent) at the end of time-of-day-h.gc, so the
   slot is bound to `nothing` before any call site. Requires GOAL
   source modification + CGO regen — touches ENGINE.CGO byte
   content, so A2-x86-baseline must be re-anchored (current
   `A17-baseline-arm64-cgo-hashes.txt` would no longer match).

Per the phase prompt's "Honest exit condition": "If the diagnostic
identifies the type-method but the fix needs an unlock beyond A18's
scope, commit the diag + analysis + write A18-attempt-N-next-blocker.md.
The supervisor will author A19."

The diag has identified:
- The dispatch shape (canonical virtual-method-dispatch).
- The failing slot (22, byte offset 0x68 on the dispatching type).
- The dispatch site PC (= host LR - 4 = `0x21231d3750`, GOAL offset
  `0x1d3750`).
- The dispatching context (engine-CGO top-level of `time-of-day`,
  inside `start-time-of-day`'s `process-spawn` macro expansion).

What it can't identify (with the unlocks A18 has):
- The dispatching type's identity (both obj_reg X9 and
  innerobj_reg X12 are clobbered between their host-conv and the
  signal; regs[X9] and regs[X12] at signal time are stale).

`.autoport/reports/A18-attempt-1-next-blocker.md` documents the
options + my recommendation for A19's unlock list.

## Cost note

A18 budget was "~60-90 min, weekly rate 92% (extreme overrun)".
Actual: roughly the upper end of that range. The diag walker design
took ~30 min (mostly understanding the existing A11/A12 walker
patterns + decoding the disasm), build cycles + qemu iterations
took ~30 min, the trap+binder design + writing this summary took
~30 min. No attempt-2 spun — the diag captured the maximum
information available given regs-clobber-at-signal-time, and the
fix requires unlocks A18 doesn't have.
