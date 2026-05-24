# A18 attempt-1 next-blocker — type-method-zero walker landed and the LDR site is pinpointed, but the dispatching type's identity isn't recoverable because BOTH the obj_reg and innerobj_reg are clobbered between their host-conv and the signal. The hook-time trap installer only catches kernel-loaded types; the failing dispatch is on an engine-CGO type loaded AFTER hook. A19 needs one of {codegen dispatch-instrumentation, link-engine post-CGO hook, kscheme new_type inherit-loop fix} unlocks.

Authored 2026-05-24 by attempt-1 of phase
`A18-type-method-zero-bind`.

## What landed this attempt

`game/linux-arm64/linux_arm64_main.cpp` + `android/gk_android_main.cpp`:
- `is_add_xreg_xreg_x15` helper (matches `ADD Xd, Xn, X15` shifted-reg
  with shift=0).
- `dump_type_method_zero_chain` walker:
  - confirms `BLR Xt` at lr-4.
  - walks backward to find `ADD Xt, Xt, X15` (host-conv of the
    dispatched fn-ptr).
  - follows MOV chain up to 5 hops to find the originating LDR.
  - identifies the LDR's base reg, offset, and (via further
    backward walk) the obj_reg that fed it via `ADD Xb, Xobj, X15`.
  - **TYPETAG-LOAD chain extension**: when obj_reg's source is the
    canonical `LDUR W_obj_reg, [Xs, #-4]` (the type-tag load of a
    virtual-method dispatch), chases one more level back to find
    Xs's source via `ADD Xs, Xinnerobj, X15` — names host_obj_reg
    and innerobj_reg.
  - prints all the host pointers, GOAL ptrs, type-tags, and method
    slot index at the LDR offset, plus a clobber flag per
    intermediate register.

`game/kernel/common/klink.cpp` + `klink.h`:
- `a18_method_zero_trap(u64 a0..a7)` — C function whose body is:
  - capture caller_lr via `__asm__ volatile("mov %0, x30" : ...)`.
  - read self_host + type_tag if a0 looks like a valid GOAL ptr.
  - print A18-DIAG line with self_goal, self_host, type_tag,
    caller_lr, all 7 remaining args.
  - `std::fflush(stderr); std::_Exit(13);` — honest hard halt.
  - NOT abort, NOT __attribute__((weak)), NOT `return 0;`.
- `walk_loaded_types_and_patch_a18(u32 trap_fn_goal)` — walks every
  sym slot in `[SymbolTable2, LastSymbol)`. For each value that
  satisfies the strict "is a Type" heuristic (value <
  EE_MAIN_MEM_SIZE; tag-at-(-4) == canonical `type` Type GOAL ptr;
  allocated-length in [9,128]), patches every 0-valued method slot
  to point at the trap.
- `klink_a18_install_method_zero_trap()` — public binder:
  `make_function_symbol_from_c("__a18-method-zero-trap", ...)` +
  walk + bind-trace stderr line.

Wired into both:
- `linux_arm64_main.cpp::boot_kernel_init` after
  `a17_bind_pc_helpers()`.
- `gk_android_main.cpp::a11_install_pc_mips2c_hook_once`'s lambda
  after `a17_bind_pc_helpers()`.

## Captured diag (qemu_repro, A8-qemu-repro.log)

```
A18-DIAG sym-bind-trace: bound __a18-method-zero-trap to a18_method_zero_trap
        (GOAL fn ptr 0x1c97a4), patched 82 empty method slots across loaded
        kernel types

[... 216 link finishes including time-of-day ...]

GK-DIAG sig=4 fault=0x2123000000 pc=0x2123000000 lr=0x21231d3754
GK-DIAG x0=0x221520  ... x6=0x221520 ... x9=0x221520 ...
        x12=0x4070 ... x15=0x2123000000 (ee_base) x16=0x2123000000 ...
GK-DIAG A18-DIAG type-method-zero: hop=0 MOV X8 <- X9 @ lr-36
GK-DIAG A18-DIAG type-method-zero: ldr-pc=0x21231d372c base=X16 offset=0x68
        size=W method-slot=22 obj-add@found obj-goal-reg=X9 obj-goal=0x2215c0
        obj-host=0x21232215c0 loaded-value=0x22162c type-tag@obj_host-4=0x50a1e0
        obj-reg-clobbered-since-add=1
GK-DIAG A18-DIAG type-method-zero: TYPETAG-LOAD chain ldur-pc=0x21231d3724
        host-obj-reg=X16 host-obj@signal=0x2123000000 type-tag-via-host=0x0
        innerobj-add@found innerobj-reg=X12 innerobj-goal=0x4070
        innerobj-host=0x2123004070 innerobj-type-tag=0x0
        (canonical virtual-dispatch shape — failing method is slot 22 of
        innerobj's type)
```

## Why we can't fully identify the dispatching type at A18 scope

Both `obj_reg = X9` AND `innerobj_reg = X12` were CLOBBERED between
their respective obj-host conversions and the signal-trap site.
Specifically:

- The LDR at `lr-40` (= 0x21231d372c) is `LDR W9, [X16, #0x68]` —
  this WRITES W9 (zero-extends to X9), destroying X9's prior value
  (= the type-tag from the LDUR at lr-44).
- Later at `lr-28` (= 0x21231d3738) there's a `LDR X9, [SP, #0]`
  that RELOADS X9 from a stack slot. The stack slot at SP+0 (after
  accounting for the 48-byte push frame) holds a value 0x221520 —
  but whether this value is the original obj-GOAL or some unrelated
  spill is impossible to determine without disassembling the
  caller of this function.
- Similarly X12 may have been clobbered between its consumption at
  lr-52 (`ADD X16, X12, X15`) and the signal site at lr-0. At signal
  time `regs[12] = 0x4070` — but the LDUR at lr-44 reads from
  `[X16, #-4]` where X16 was just-set from X12+X15. Reading
  `obj_host - 4 = 0x21232215bc` gives 0x50a1e0 (= the apparent
  type-tag, but coming from a clobbered base, so suspect).

The diag's last `dump_sym_name_at_slot` call walks the type-tag's
symbol field (offset 0 of the Type basic) and gets 0x1c1414 →
slot host 0x21231c1414 → `in_sym_range=0` (= NOT a valid sym
slot). This confirms the type-tag readout is garbage: either
0x50a1e0 isn't a real Type, or the obj at 0x2215c0 isn't a basic.

The combination "regs at signal don't reflect dispatch-time obj" +
"hook-time trap installer can only patch types existing at hook
time" means the A18 deliverables (diag + honest-abort surface)
land cleanly, but boot count stays at exactly 216 (= A17
ceiling). Strict `> 216` validator check 8 fails.

## Why the trap doesn't fire

`klink_a18_install_method_zero_trap` patched 82 empty method slots
in types loaded by the kernel CGO (= 8 objects: gcommon, gkernel,
gstate, plus the kernel bootstrap). The dispatching type's slot 22
is NOT among those 82, which means one of:

1. **The dispatching type is an engine-CGO type** (loaded AFTER our
   hook fires). Its method table is initialized later by `new_type`
   inheriting from its parent. If the parent's method count < 22
   AND the child is allocated with `n_methods > 22` (e.g., via
   `FALLBACK_UNKNOWN_METHOD_COUNT = 44` when the level-data v2/v4
   object file format encodes the methods count as 1), the child's
   slot 22 ends up with whatever's at `parent_host + 16 + 22*4` —
   typically 0 (uninitialised heap past parent's method table) OR
   garbage from the next allocation. This matches
   `game/kernel/jak1/kscheme.cpp:1242-1246`'s documented BUG
   comment:
   > BUG! This uses the child method count, but should probably
   > use the parent method count.

2. **The dispatching type's slot 22 was non-zero at hook time but
   was OVERWRITTEN by a later `new_type` call** that re-inherited
   from the parent. Same mechanism as #1, but specifically for a
   kernel type that's re-interned at engine-CGO link time. Unlikely
   because engine CGOs don't redefine kernel types.

#1 is the most plausible. Without further unlocks we can't confirm
which engine type, but the failing site is inside
`(start-time-of-day)`'s `process-spawn` macro expansion (line 138 of
`goal_src/jak1/engine/gfx/mood/time-of-day.gc`). `process-spawn`'s
expansion calls `(get-process *default-dead-pool* time-of-day-proc
0x4000)` first, then `(activate ...)`, then `(run-now-in-process
...)`. The crash address is inside ENGINE.CGO, at GOAL offset
0x1d3750. Mapping that to a specific function requires
`aarch64-linux-gnu-objdump` on the linked output OR an
addr2line-style table.

The dispatching type is likely one of:
- `dead-pool-heap` (if `*default-dead-pool*` is one, get-process
  internally dispatches `gap-location` at slot 22).
- `time-of-day-proc` (if the dispatch is `(activate ...)` on a
  freshly-allocated instance whose method table was inherited
  badly).
- some helper struct type with virtual-dispatch slot 22.

## Recommended A19 unlock options

Listed from narrowest to broadest scope:

### Option A: kscheme `new_type` inherit-loop fix (recommended)

Unlock `game/kernel/jak1/kscheme.cpp` (currently locked) and fix the
documented BUG at lines 1242-1246:

```cpp
// BUG! This uses the child method count, but should probably use the parent method count.
for (u32 i = 0; i < n_methods; i++) {
  child_slots[i] = parent_slots[i];
}
```

Fix:

```cpp
// Inherit parent's method slots, NOT past them. Slots past parent's
// declared count remain 0 (= empty) and the kernel's defmethod for
// the child fills them in.
u32 inherit_count = std::min(n_methods, Ptr<Type>(parent)->num_methods);
for (u32 i = 0; i < inherit_count; i++) {
  child_slots[i] = parent_slots[i];
}
```

This eliminates the out-of-bounds garbage being written into child
slots. Combined with the A18 hook-time trap (which still patches
slots that legitimately stay 0 after inherit), boot should advance
past 216.

The narrowest correctness fix; ~3 lines of code in a locked file.

### Option B: link-engine post-CGO-link hook

Unlock `game/kernel/jak1/klink.cpp` or `game/kernel/common/klink.cpp`
to add a hook in `link_control::jak1_finish` that re-fires the A18
walker after every successful CGO link. This catches engine types as
they become populated.

Requires a wider klink unlock; ~20-30 lines.

### Option C: goalc virtual-dispatch instrumentation

Unlock `goalc/compiler/IR.cpp` to emit a runtime diag-print at every
virtual-dispatch BLR site (between the LDR W and the BLR, print
type-tag + slot before the LDR clobbers the dispatch reg).

Risks regressing the link-finish count (extra emitted bytes per
dispatch could ripple) AND requires goalc-arm64 rebuild + CGO
regen (breaking A17-baseline-arm64-cgo-hashes byte-identity
check). Most invasive option.

### Option D: GOAL-side fix at engine CGO

Add `(method-set! time-of-day-proc 22 nothing)` (or similar) at the
end of `time-of-day-h.gc` — bind the failing slot to the existing
GOAL `nothing` function at engine-CGO link time. Requires GOAL
source modification + CGO regen (touches ENGINE.CGO bytes).

Targets the specific failure but doesn't address the underlying
inherit-loop bug. Brittle if the same issue manifests on other
engine types.

## My recommendation

**Option A** (kscheme `new_type` inherit fix). It's a 3-line fix
in a single locked file, addresses the documented root cause, and
A18's hook-time trap will continue to catch any genuinely-empty
slots that defmethod hasn't filled in. The combination should
push the link-finish count past 216 cleanly.

If Option A's fix on its own doesn't advance boot count, fall back
to Option B (link-engine hook) + the A18 trap, which provides
runtime instrumentation regardless of inherit-loop correctness.

## Cost note

Per the phase prompt's rate-budget caution ("weekly rate at 92%,
extreme overrun"), this attempt commits exactly the supervisor-prompt-
scoped deliverables (diag + honest-abort surface) without spinning
attempt-2 against an out-of-A18-scope codegen/kscheme/link-engine
fix. The validator's strict `> 216` check is expected to fail until
A19 lands the inherit-loop or post-link-hook unlock.
