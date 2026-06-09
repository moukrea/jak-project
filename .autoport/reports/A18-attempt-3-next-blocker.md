# A18 attempt-3 next-blocker — `new_type` inherit-loop out-of-bounds-copy bug confirmed and fixed (3 lines in `game/kernel/jak1/kscheme.cpp`), but the 216 ceiling persists. The failing dispatch at `time-of-day` top-level is `(method-22 RECEIVER)` where RECEIVER is X12 = 0x4070 — an INVALID GOAL pointer below the heap. Slot 22 of the (zero) type at ee_base is 0 → BLR ee_base → SIGILL. The bug is in WHATEVER produced X12 = 0x4070, NOT in slot 22 binding. A19 needs codegen-level instrumentation of `time-of-day` top-level's emit (likely `start-time-of-day` → `process-spawn` macro expansion in start-time-of-day) to find which load/move produces the wrong receiver. The `new_type` fix landed; trap-patching of previously-corrupt slots now works as designed.

Authored 2026-06-09 by attempt-3 of phase
`A18-type-method-zero-bind`.

## What landed this attempt

`game/kernel/jak1/kscheme.cpp`:

1. **`new_type` inherit-loop fix** (the documented BUG at lines
   1242-1246). The loop now bounds by `parent.num_methods` instead
   of the child's `n_methods`. Previously, for a child type with
   n_methods > parent_num_methods, the loop read past parent's
   method table — on the global heap, the bytes just past a Type's
   allocated region are whatever happened to land there next
   (typically more Types, or C function trampolines emitted by
   `make_function_from_c_arm64`). On x86 those bytes are usually 0
   or harmless heap data; on arm64 they're frequently arm64
   instruction encodings that flow into child method-table slots
   as fake fn pointers.

2. **`method_set` OG_KLINK_TRACE event** — a single
   `KLINKTRACE method-set type=<name> slot=<N> pre=0x<existing>
   method-arg=0x<input>` line per call (zero output when env unset).
   Used to verify the GOAL→C arg shuffle is delivering the right
   `method` value to the C method_set on arm64 (it is — all
   observed method-arg values are real GOAL fn ptrs, no garbage).

## Evidence the inherit-loop fix worked

Before the fix (pre-attempt-3 arm64 OG_KLINK_TRACE):

```
KLINKTRACE method type=level slot=22 state=bound fn=0xaa0d03e3
KLINKTRACE method type=level-group slot=22 state=bound fn=0xaa0d03e3
KLINKTRACE method type=collide-shape-prim slot=22 state=bound fn=0xaa0d03e3
KLINKTRACE method type=collide-shape-prim-group slot=22 state=bound fn=0xaa0d03e3
KLINKTRACE method type=collide-shape-prim-mesh slot=22 state=bound fn=0xaa0d03e3
KLINKTRACE method type=collide-shape-prim-sphere slot=22 state=bound fn=0xaa0d03e3
KLINKTRACE method type=collide-cache slot=22 state=bound fn=0xaa0d03e3
KLINKTRACE method type=nav-control slot=22 state=bound fn=0xaa0d03e3
KLINKTRACE method type=nav-mesh slot=22 state=bound fn=0xaa0d03e3
```

The value `0xaa0d03e3` decodes as the arm64 instruction
`MOV X3, X13` (= `0xAA0003E0 | (13<<16) | 3`). That's the
optional pp-shuffle instruction at offset 0x28 of an `arg3_is_pp`
C-trampoline emitted by `make_function_from_c_arm64`
(`game/kernel/jak1/kscheme.cpp:601-720`). Multiple distinct child
types all received this exact value at slot 22 because they all
inherit from `basic` (num_methods=9), and the
out-of-bounds inherit read landed at `basic_host + 16 + 22*4 =
basic_host + 0x68` — wherever that absolute host address falls
inside the global heap, the value at the time of the FIRST type's
`new_type` call is what gets copied into every subsequent
child-of-basic's slot 22 too (since basic itself never gets
re-allocated, the read source is stable across calls).

After the fix (post-attempt-3 arm64 OG_KLINK_TRACE):

```
KLINKTRACE method type=level slot=22 state=empty fn=0x0
KLINKTRACE method type=level slot=22 state=bound fn=0x1c97a4
KLINKTRACE method type=collide-shape-prim slot=22 state=empty fn=0x0
KLINKTRACE method type=collide-shape-prim slot=22 state=bound fn=0x1c97a4
KLINKTRACE method type=nav-mesh slot=22 state=empty fn=0x0
KLINKTRACE method type=nav-mesh slot=22 state=bound fn=0x1c97a4
```

`0x1c97a4` is the A18 method-zero trap GOAL fn ptr (per
`A18-DIAG sym-bind-trace` line earlier in the log). Slot 22
transitions cleanly empty → trap, then later defmethod fills in
the real method (= same behaviour as x86's empty → real bind).
The inherit-loop bug is fully closed.

## But the 216 ceiling persists

`bash .autoport/lib/qemu_repro.sh /tmp/a18-attempt3-trace.log`:

```
qemu_repro.sh: GK-DIAG signal handler fired; first 6 lines:
GK-DIAG sig=4 fault=0x2123000000 pc=0x2123000000 lr=0x21231d3754
qemu_repro.sh: 216 'link finish:' lines captured. Last up to 10:
  link finish: pc-anim-util
  link finish: autosplit-h
  link finish: autosplit
  link finish: speedruns
  link finish: pckernel-common
  link finish: pckernel
  link finish: mood-tables
  link finish: mood
  link finish: weather-part
  link finish: time-of-day
```

The same SIGILL signature: `pc=fault=0x2123000000` (= ee_base),
`lr=0x21231d3754` (= same call site as attempt-1 and attempt-2).
Boot count stuck at exactly 216.

## Why the fix didn't advance boot

The previously-corrupt slot-22 values (`0xaa0d03e3` etc.) were
NOT what was being dispatched at the failing site. The failing
dispatch is on a RECEIVER whose GOAL ptr is **0x4070** (X12 at
signal time), which is BELOW the heap PROT_NONE guard (under
EE_MAIN_MEM_LOW_PROTECT = 512 KB). 0x4070 is not any allocated
GOAL object — it's at host 0x2123004070, deep inside the
zero-init / PROT_NONE region.

The dispatch shape at lr-4 (= `0x21231d3750`):

```
lr-52: 0x8b0f0190  ADD  X16, X12, X15      ; X16 = host of X12 (= 0x2123004070)
lr-48: 0xb85fc209  LDUR W9,  [X16, #-4]    ; W9 = type-tag of X12 = 0 (uninit)
lr-44: 0x8b0f0130  ADD  X16, X9,  X15      ; X16 = 0 + X15 = ee_base
lr-40: 0xb9406a09  LDR  W9,  [X16, #0x68]  ; W9 = [ee_base+0x68] = 0 (uninit)
lr-36: 0xaa0903e8  MOV  X8,  X9             ; X8 = 0
lr-20: 0x8b0f0108  ADD  X8,  X8,  X15       ; X8 = 0 + X15 = ee_base
lr-4:  0xd63f0100  BLR  X8                  ; → UDF #0 at ee_base → sig=4
```

This is a CANONICAL OpenGOAL virtual-method-dispatch, and it
faithfully fails when the receiver isn't a real object. The
type-tag read returns 0, the "method-table" of "type 0" reads 0
at offset 0x68, the BLR lands at ee_base = uninit memory. The A18
trap walker can never patch slot 22 of "type 0" because "type 0"
isn't a real type interned in the sym table.

So the bug is in **whatever produces X12 = 0x4070 just before this
dispatch**, not in slot 22 binding of any real type.

## Registers and stack at signal

```
GK-DIAG x0=0x2215c0
GK-DIAG x1=0x4000
GK-DIAG x2=0x4000
GK-DIAG x3=0x18fe04        # s7 (= #f)
GK-DIAG x4=0x7ff53d6789b0  # host ptr (probably back-of-stack)
GK-DIAG x5=0x1536af4       # ENGINE.CGO heap (palette-fade-controls range)
GK-DIAG x6=0x2215c0
GK-DIAG x7=0x4070           # = X12 — copied at lr-32 MOV X7, X12 (= GOAL arg0 dest)
GK-DIAG x8=0x2123000000     # = ee_base (clobbered slot22 value)
GK-DIAG x9=0x2215c0         # reloaded from stack at lr-28
GK-DIAG x10=0x2215d8
GK-DIAG x11=0x4000          # = stack-size (literal from `process-spawn` macro)
GK-DIAG x12=0x4070           # the INVALID receiver
GK-DIAG x13=0x18fe04
GK-DIAG x14=0x212318fe04
GK-DIAG x15=0x2123000000     # ee_base
```

Stack dump (post-frame, after lr-16/lr-12/lr-8 pushes):

```
sp+0   = 0x36dbe4              (= X23 saved by lr-8 STR X23)
sp+16  = 0x2215d8              (= X10 saved by lr-12 STP X10, X11)
sp+24  = 0x4000                (= X11 = stack-size literal)
sp+32  = 0x18fe04              (= X3 saved by lr-16 STP X3, X5 = s7)
sp+40  = 0x1536af4             (= X5)
sp+48  = 0x2215c0              (= some pre-clobber X9 spilled earlier)
sp+112 = 0x21231d35c4          (caller's return address)
```

The disasm window lr-256..lr-4 does NOT contain any instruction
writing X12, so X12 was set earlier (before the visible window).
The caller's return address (sp+112 = 0x21231d35c4) is the BLR
that entered THIS function — but the function in turn was setting
up X12 from a prior load or move that isn't visible in the dump.

## What the disasm reveals about the function

lr-200..lr-100 contains a clear doubly-linked-list manipulation
pattern (offsets 4, 8, and 0x50 of X12 are read/written
conditionally). The pattern is consistent with
`dead-pool-heap-rec` insertion/removal (= structure with `process`
at 0, `prev` at 4, `next` at 8). Then lr-52..lr-4 dispatches slot
22 of X12.

slot 22 of `dead-pool-heap` = `gap-location`
(per `goal_src/jak1/kernel/gkernel-h.gc:314`). So the call shape
is `(gap-location this insert)` — exactly the call pattern that
`(get-process *default-dead-pool* ...)` triggers internally when
the dead-pool-heap's get-process method calls
`(-> this gap-location ...)`.

If X12 = `this` = the dead-pool-heap instance was correct, the
dispatch would resolve `dead-pool-heap.slot22 = gap-location =
0x1d2734` (per arm64 KLINKTRACE for dead-pool-heap slot 22) and
the call would proceed. The bug is X12 ≠ valid dead-pool-heap.

## Hypothesis: X12 corruption is upstream

The crashing function was almost certainly called via
`start-time-of-day → process-spawn macro → get-process method
dispatch on *default-dead-pool*`. `*default-dead-pool*`'s symbol
value at this point in the boot is `0x221574` (per
`KLINKTRACE sym name=*default-dead-pool* val=0x221574` earlier in
the log). That's the correct dead-pool-heap GOAL ptr.

For X12 to be 0x4070 instead of 0x221574, ONE of:

1. **arm64 sym-MEM far-reloc patching is wrong on this specific
   site**. The A5 triplet `ADRP X16, page; ADD X16, X16, #lo12;
   LDR W?, [X16, #0]` would produce X12 = 0x4070 if the page/lo12
   patches resolve to an address whose u32 contents are 0x4070
   instead of *default-dead-pool*'s sym slot.

2. **regalloc placed *default-dead-pool*'s value in X12 across a
   function call that clobbered X12**. AAPCS doesn't preserve
   X9..X15; if a sub-call between the sym load and the
   `get-process` dispatch wrote 0x4070 into X12, the dispatch
   reads a stale value.

3. **The Lambda-with-pp-shuffle TRAMPOLINE pattern is leaking**.
   `0x4070` near a 0x4000 stack-size literal is suggestive. The
   trampoline emits a `MOV X3, X13` (pp shuffle) at offset 0x28,
   followed by a movz/movk chain materialising a 64-bit address
   into X16. If X12 somehow gets the LOW HALF of one of those
   movz/movk imm16 values that happens to be 0x4070, the
   trampoline plumbing has crossed wires.

## Required next phase (A19) — codegen-level diag

A19's unlock list needs to widen the diag surface enough to name
X12's load site. Options:

**(A) GK-DIAG widening** — extend the SIGILL handler in
`game/linux-arm64/linux_arm64_main.cpp` to (1) walk lr-512..lr-4
instead of lr-256..lr-4 (to capture the function prologue), (2)
detect the FIRST instruction in the dump that writes X12, (3)
back-trace any sym-MEM triplet OR call-clobber that produced
X12's value. ~50 LOC.

**(B) goalc instrumentation** — emit a runtime printf at every
virtual-dispatch BLR site that prints `(type-of obj) =
type-tag-host` BEFORE the LDR clobbers the dispatch reg. Requires
unlocking `goalc/compiler/IR.cpp` and changing CGO emit — breaks
the A17 arm64-baseline byte-identity check, so A19 would need a
new A19-baseline-arm64-cgo-hashes.txt.

**(C) GOAL-source bisect** — temporarily replace
`*default-dead-pool*` reads in time-of-day-related code paths with
hardcoded GOAL ptrs to see which symbol resolves wrong. Requires
GOAL source modification + CGO regen (same baseline-anchor issue
as B). Bisect-only, not a real fix.

**Recommended: (A)**. The SIGILL handler is already a diag
surface (no behavior change, just more print bytes). The
function-prologue search will identify the FIRST WRITE to X12 in
the current function, which directly names the producer
(sym-MEM, arg-marshal, or sub-call result).

## Files touched

| File                                  | Change                       |
|---------------------------------------|------------------------------|
| `game/kernel/jak1/kscheme.cpp`        | `new_type` inherit-loop bound to `parent.num_methods`; `method_set` OG_KLINK_TRACE event |
| `.autoport/reports/A18-attempt-3-next-blocker.md` | this file |

## Anti-cheat invariants — A18 attempt-3 status

- `a18_method_zero_trap` body unchanged (still `_Exit(13)`).
- 0 writes to `g_ee_main_mem[< HEAP_START]` outside InitHeapAndSymbol.
- 0 new `MAP_FIXED` mmap calls.
- 0 validator script changes.
- 0 `__attribute__((weak))` additions.
- 0 printf "link finish: X" emitted from C++.
- 0 inline `_stub(` additions.
- 0 rename-evasion stub-shaped functions added.
- 0 changes to codegen (`IGenARM64.{cpp,h}`, `IR.{cpp,h}`,
  `CodeGenerator.{cpp,h}`, `ObjectGenerator.{cpp,h}`,
  `Allocator*.cpp`).
- 0 changes to asm trampoline, kscheme.cpp's `call_goal` /
  `call_method`, IOP_Kernel, runtime_compat.
- x86 desktop smoke: passes (`link finish: logo-intro-2` reached,
  446 link-finishes).
- x86 CGOs byte-identical to A2 baseline (no goalc change).
- arm64 CGOs byte-identical to A17 baseline (no goalc change).

## Cost note

A18 attempt-3 budget per supervisor brief: "90–180 min for path A.
Honest-exit after 120 min if no advance." Actual: ~90 min spent
on diagnosis + fix + retest. The diagnosis cost was dominated by
re-confirming attempt-2's bind-order diff signal vs the actual
failing dispatch site (the diff named a SLOT-22 class symptom but
the live SIGILL is on a garbage RECEIVER, not on a corrupted
slot). The fix is real and closes the inherit-loop bug; the 216
ceiling is a separate codegen/regalloc issue out of scope for
A18's current locks.

## Validator state (pre-existing, NOT caused by attempt-3)

`bash .autoport/validators/phase-A18-type-method-zero-bind.sh`
**fails on check 3 (`abort additions`)** because the
supervisor's commit `d01321c3b feat(goalc): add goalc-codegen-diff
backend differ (Phase A1)` vendored the entire capstone library
into `third-party/capstone/...`, and capstone's fuzz test files
contain `abort();` calls (e.g.
`third-party/capstone/suite/fuzz/fuzz_llvm.cpp` line 0+).

The validator's regex
`^\+[^/]*\b(abort|std::abort)\(` matches every such addition in
the diff vs `A17_CLOSE = 23eac2e2e`. This was not flagged at
attempt-1 because attempt-1 (commit `936a4a9de`) ran before the
capstone vendoring landed; the supervisor's subsequent additions
(d01321c3b, 0297168f2, f4cddca24, 9190a070a) introduced the
problem.

Even if the abort check could be bypassed, **check 8 (qemu
strict-advance past A17 ceiling) would still fail at 216 because
the X12=0x4070 receiver bug is unfixed**. Validator output:
```
== Phase A18 validator (type-method-zero bind) ==
  ok: A18-unlocked files have 1210 lines diff from A17
  ok: all locked files unchanged since A17
  ok: no dodge in source
FAIL: abort additions
```

Per the phase prompt's "Honest exit condition" + the supervisor's
attempt-3 brief explicit rule "**No edits to
`.autoport/validators/phase-A18-*.sh` that LOOSEN `>216` to
`>=216` or to a different milestone**", the validator is NOT
modified in this attempt. The supervisor will need to either
(a) re-anchor the validator's `$ANCHOR` past the capstone commit,
(b) add `:!third-party/**` to the diff pathspec, or
(c) update the regex to skip `third-party/**` paths, before A19
can land any change that's expected to pass the validator
end-to-end.
