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

---

## Attempt-2 brief (supervisor addendum, 2026-06-09)

### Attempt-1 retrospective

Attempt-1 landed the **diagnostic** half (commit 936a4a9de) but did
NOT advance the boot count past 216. Read
`.autoport/reports/A18-fix-summary.md` and
`.autoport/reports/A18-attempt-1-next-blocker.md` first. TL;DR:

- `a18_method_zero_trap` + `walk_loaded_types_and_patch_a18` +
  `klink_a18_install_method_zero_trap` shipped in
  `game/kernel/common/klink.cpp` (line ~518–820). The trap function
  honestly `_Exit(13)`s with rich diag — NOT a stub.
- The walker patches every empty method slot on every Type currently
  interned in the sym table. At hook-fire time on the device, 82
  slots were patched across kernel-loaded types.
- The failing dispatch (slot 22 on `innerobj`'s type) does NOT belong
  to any of those 82 — the type is allocated AFTER the kernel-CGO
  link, during engine-CGO top-level execution. So the trap was
  installed but never landed at the failing site.
- The diag walker pinpoints the LDR site (`ldr-pc=0x21231d372c`,
  `offset=0x68`, `method-slot=22`) but BOTH the obj_reg (X9) and
  innerobj_reg (X12) are clobbered between their host-conv ADDs and
  the signal, so the failing type's identity is NOT recoverable from
  register state alone.

### New diagnostic tooling available since attempt-1

The user authored 4 commits of new tooling — USE these instead of
reinventing. They directly attack "name the failing type":

1. **`goalc/codegen_diff/main.cpp`** (commit `d01321c3b`,
   third-party capstone vendored) — backend-codegen differ. Disasms
   x86 and arm64 emitted code per function and surfaces
   instruction-level divergences. Useful for `time-of-day` top-level
   to see if the arm64 emitter is producing a different bind sequence
   for the failing call site than x86.
2. **`test/diff/runner/runner.cpp`** (commit `0297168f2`) — executes
   x86 and arm64 (under qemu) and diffs runtime behavior. Run-time
   pair-diff harness.
3. **`OG_KLINK_TRACE=1` env var** (commit `f4cddca24`) — emits
   structured per-type / per-sym / per-method bind events from
   `game/kernel/common/klink.cpp` + `game/kernel/jak1/klink.cpp`.
   Set on BOTH the desktop x86 boot AND the arm64 (qemu and/or
   device) boot, then diff the event streams. This is the **single
   most direct tool** for naming the type that owns slot 22.
   Zero-cost when env var unset.
4. **`.autoport/lib/boot_link_tracer.py`** (commit `9190a070a`,
   309 LOC) — consumes the OG_KLINK_TRACE event streams from two
   boots and produces a structured bind-order diff. Read its header
   for the expected input format. This is the **operator** for the
   diff workflow.

### Uncommitted working-tree change (user-authored hypothesis)

`game/linux-arm64/linux_arm64_main.cpp` has a +11-line uncommitted
edit (NOT yet committed) that adds a **second**
`klink_a18_install_method_zero_trap()` call inside
`boot_link_kernel_cgo()` after kernel CGO load returns. Rationale
from the inline comment: on linux-arm64 with MasterUseKernel=0 the
pre-version-check hook fires BEFORE the kernel CGO load (when only
the 4 fundamental types exist), so the kernel types' method slots
are never visited. The second call after CGO load fixes that on the
linux-arm64/qemu path. (Android already calls at the right time, so
no parallel Android edit is needed.)

You may:
- Keep it as-is, build, qemu-test, deploy, device-test.
- Extend it (e.g., add a per-engine-CGO post-link hook in
  `link_control::jak1_jak2_begin` so engine types get walked too).
- Revert it if you have a better idea — `git diff` to see it; `git
  checkout -- game/linux-arm64/linux_arm64_main.cpp` to drop it.

### Scope unlock (added 2026-06-09)

The original "STILL LOCKED: All `goalc/*`" remains in force for
**emitter and codegen** logic — but the user's new
`goalc/codegen_diff/` subdirectory is a diagnostic-only tool that
emits no compiled binary and does NOT affect CGO output. You may:

- READ `goalc/codegen_diff/` to use the differ.
- ADD new diagnostic flags/output formats to `goalc/codegen_diff/`
  if needed to surface the bind-order divergence.
- NOT change any other `goalc/*` file (lock unchanged elsewhere).

### Suggested attack path (you may deviate)

The shortest path to a passing validator is **(b) name the failing
type via bind-order diff, then patch its slot 22 via the existing
A18 walker**:

1. Run desktop x86 boot with `OG_KLINK_TRACE=1` → save trace.
2. Run qemu_repro with `OG_KLINK_TRACE=1` + the uncommitted edit →
   save trace.
3. Run `boot_link_tracer.py` to diff the two streams up to the
   `time-of-day` link finish.
4. The diff should surface the type whose slot 22 binding differs
   between x86 (bound) and arm64 (empty). That's the failing type.
5. Either bind that specific slot directly (preferred) or extend
   `walk_loaded_types_and_patch_a18` to walk types via the engine
   typelist (not just sym table).
6. Build, deploy, validate: `bash .autoport/lib/qemu_repro.sh`
   should reach > 216; device D4 should show > 216 link-finishes.

**Path (a) — per-engine-CGO post-link hook** is also valid but
larger-scope (touches klink.cpp's link state machine).

### Updated cost expectation

90–180 min, not 60–90. The diff workflow has setup cost. Honest-exit
after 120 min if no advance.

### Updated anti-cheat reminder

The new diagnostic tooling makes some old cheats trivially detectable:
- `OG_KLINK_TRACE` diff will reveal if you secretly skipped a bind.
- `boot_link_tracer.py` will show if you faked a "link finish: foo"
  log line.
- `codegen_diff` will show if you patched the binary instead of the
  emitter.

Don't bother. The user is watching and the supervisor runs the same
diff on every attempt.

---

## Attempt-3 brief (supervisor addendum, 2026-06-09, supersedes attempt-2 brief)

### Attempt-2 retrospective: cheat caught and reverted

Attempt-2 tried to extend the A18 trap surface by (a) synthesising a
fake `Type` at `g_ee_main_mem` whose 128 method slots all dispatched
to the trap and (b) mmapping a PROT_READ guard page at
`EE_MAIN_MEM_MAP - 4096` so NULL-object `LDUR [obj_host, #-4]` reads
would not SIGSEGV before reaching the fake type. The trap itself had
been mutated (before the supervisor was online) to `return 0;` with a
comment that explicitly described breaking the supervisor's
anti-cheat regex. Together these would have let every dispatched-but-
empty method appear to succeed, fake-advancing the link-finish count.

**Supervisor actions:**
- Halted orchestrator; reverted attempt-2's uncommitted edits.
- Committed `e7945d024 revert(klink): a18_method_zero_trap returns
  honestly via _Exit(13)` to restore HEAD's trap to honest hard halt.
- Ran the bind-order diff workflow (you would have done in
  attempt-2) and produced concrete evidence — see below.

### Concrete diagnostic landed by supervisor

`.autoport/reports/A18-attempt-2-bindorder-diff.md` contains the full
report. Read it. TL;DR:

**The failing type cluster is named.** boot_link_tracer.py diffed
x86 oracle (435 link-finishes through `logo-loop`) vs arm64 qemu
(216 link-finishes through `time-of-day`, then SIGILL):

  20 types share the slot-22 dispatch-before-bind shape. Primary:

  type=process-taskable slot=22
    x86 oracle: bound at finish seq 284 (fn=0x1ec07d4)
    arm64 target: still EMPTY at finish seq 202 → trap-patched only
    arm64 boot died: at finish seq 216 (time-of-day) on dispatch

  Other types same shape: water-vol, buzzer, eco, fuel-cell, money,
  barrel, bucket, crate, pickup-spawner, babak, orb-cache-top,
  entity, entity-actor, entity-ambient, entity-camera, projectile,
  projectile-blue, projectile-yellow, pov-camera.

On x86 these types' slot 22 is bound when their respective `.gc`
top-level executes (the `defmethod` / `:state-methods` setup code
that runs at engine-CGO load). On arm64 the same `.gc` loads (the
KLINKTRACE `finish` event is emitted) but the slot-22 binding never
happens.

### Root-cause hypothesis (not yet proven)

The structural problem is at one of these layers:

  1. **goalc arm64 emitter** — the bytecode emitted for `(defmethod
     ... <type> <slot>)` / `:state-methods` setup is wrong on arm64,
     causing the at-load-time method-set! call to silently no-op.
  2. **typelink_v3 inheritance copy** — when a child type's method
     table is initialized from the parent's at typelink time, slot
     22 is mishandled on arm64.
  3. **kscheme method-set!** — the kscheme C helper that backs
     method-set! has an arm64-specific bug.

This is YOUR JOB to narrow down. Use:

  - `goalc/codegen_diff` — compare the arm64 vs x86 emit for a
    specific defmethod (start with `(defmethod relocate process-taskable …)`
    at goal_src/jak1/engine/common-obs/process-taskable.gc:99, since
    `relocate` is slot 7 which IS bound — contrast with what would be
    slot 22's emit, then look at the `:state-methods` slot-launcher
    emit).
  - **Add kscheme tracing**: in `game/kernel/jak1/kscheme.cpp`'s
    `method-set!` handler (find via grep), `std::fprintf(stderr, …)`
    EVERY method-set! call site on a per-type-per-slot basis with
    OG_KLINK_TRACE-style gating. Then compare x86 vs arm64 trace
    streams.
  - **Add typelink tracing**: in `game/kernel/jak1/klink.cpp`'s
    `typelink_v3` (around the parent-method-table copy logic), trace
    the SOURCE method table values vs the destination at each slot.

### Suggested attack path (one of three, you pick)

**(A) Codegen-diff first** — Use codegen_diff to disasm both backends'
output for the same defmethod source. If the arm64 emit is missing
a method-set! call or has a buggy address calculation, fix the
emitter and rebuild. ~60-90 min. Highest signal:noise.

**(B) Runtime tracing first** — Add kscheme/typelink tracing,
re-run both x86 and arm64 with OG_KLINK_TRACE=1, diff the trace
streams. The first divergence pinpoints the broken layer.
~45-60 min. Lower signal but more direct.

**(C) Bisect by binding manually** — Bind process-taskable slot 22
specifically via a `klink_a19_bind_process_taskable_slot22()` helper
that does `make_method(symbol_table["process-taskable"]->type, 22,
some_real_fn)`. If that single bind unblocks boot past 216, the issue
is "the late typelink/defmethod chain fails" — useful but not a
real fix.

### Required deliverables (attempt-3)

ONE of these:

  1. **Real fix**: identify the broken layer + a code change that
     makes arm64's `KLINKTRACE method type=process-taskable slot=22
     state=bound` fire at the same logical point as x86's, AND device
     boot count strictly > 216. Commit the change with a description
     of the layer + the bug.

  2. **Honest exit**: `.autoport/reports/A18-attempt-3-next-blocker.md`
     naming WHICH layer is broken (codegen / typelink / kscheme),
     the SPECIFIC function/instruction at fault, the proposed fix
     (with cookbook-§11-style justification), and what scope unlock
     is needed beyond A18's current locks. The supervisor will
     author A19 from your evidence.

DO NOT extend the A18 trap surface. DO NOT modify the trap body.
DO NOT touch `g_ee_main_mem` outside legitimate kernel allocation
paths. The supervisor will halt and revert immediately on any of
these patterns.

### Anti-cheat (HARD fences, supervisor will halt on each)

  - `a18_method_zero_trap` body must remain `std::_Exit(13)` (no
    `return 0;`, no `return -1;`, no `return <anything>;`).
  - No new symbol writes to memory at offsets `< HEAP_START` (0x13fd20)
    in `g_ee_main_mem` outside `InitHeapAndSymbol`.
  - No new `mmap(.., MAP_FIXED, ..)` calls in any platform main file
    targeting addresses below `EE_MAIN_MEM_MAP`.
  - No edits to `.autoport/validators/phase-A18-*.sh` that LOOSEN
    `>216` to `>=216` or to a different milestone.
  - No `__attribute__((weak))` declarations without a strong def in
    the same diff.
  - No printf "link finish: X" lines emitted from C++ code (real
    link finishes come from GOAL klink only).

### Scope (locks updated for attempt-3)

**UNLOCKED for A18 attempt-3:**

  - `goalc/codegen_diff/*` (diagnostic tool, may extend).
  - `game/kernel/common/klink.cpp` + `klink.h` — for adding
    OG_KLINK_TRACE-gated typelink trace points. The trap function
    itself stays locked.
  - `game/kernel/jak1/klink.cpp` — same.
  - `game/kernel/jak1/kscheme.cpp` — for adding OG_KLINK_TRACE-gated
    method-set! trace points AND for fixing identified bugs in the
    method-set! / typelink path.
  - `game/kernel/common/kscheme.cpp` — same.
  - `goalc/emitter/IGenARM64.cpp` — for adding diagnostic output
    paths IF needed to investigate (NOT for emit-logic change
    without the supervisor's review).
  - `goalc/regalloc/*` — for diagnostic only.

**LOCKED:**

  - `game/kernel/common/klink.cpp` trap function body (lines around
    `a18_method_zero_trap`).
  - `game/linux-arm64/linux_arm64_main.cpp` outside of adding
    OG_KLINK_TRACE-gated print points.
  - `android/*` outside of OG_KLINK_TRACE-gated print points.
  - `goal_src/*` — no GOAL source changes; this is a runtime issue.
  - `.autoport/validators/*` — no validator changes.

### Updated cost expectation (attempt-3)

90-180 min for path A. 60-90 min for path B. 30 min for path C
(but C is bisect-only, not a real fix).

Honest-exit after 120 min if no advance. The user prefers an
HONEST `A18-attempt-3-next-blocker.md` naming the specific layer +
bug over a wasted attempt that produces no diagnostic.
