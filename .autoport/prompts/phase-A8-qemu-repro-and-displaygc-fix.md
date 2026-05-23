# Phase A8 — qemu-aarch64 reproduction + display.gc NULL fn-ptr fix

## Status

**Authored 2026-05-23 by the supervisor** after A7's unit-test
harness landed but the extended scope (qemu repro + display.gc fix)
was prompt-only (validator wasn't gated on it). Carving A8 as a
dedicated phase for the bug A6 attempt 4's blocker analysis
identified.

## Bucket

A — emitter / linker / runtime (deep diagnostic + fix).

## Motivation

A6 attempt 4's blocker analysis
(`.autoport/reports/A6-attempt-4-blocker.md`) identified the
remaining boot blocker: **a NULL function pointer BLR inside
`display.gc`'s top-level execution**. The crash fingerprint:

```
sig=4 fault=0x720a052000 pc=0x720a052000
X3=X15=0x720a052000  (BLR target = EE base = host VA of GOAL ptr 0)
X16=0x720a558cc4     (host of GOAL ptr 0x506cc4)
```

= BLR via `X3 = X15 + 0` after loading a 0 value from a GOAL pointer.
The IR is `IR_FunctionCall::do_codegen_arm64` in
`goalc/compiler/IR.cpp:578-586`.

52 unique CGOs link cleanly before the crash — the X19 trampoline
save + 6 off-register helpers from A6 are real progress. The bug is
NOT in those layers; it's in either:

1. A GOAL symbol's value-cell stayed 0 (the A5 sym-mem STR mis-fires
   for some symbol-index range — `set-display` is the prime suspect),
2. A method-table slot wasn't installed (the A6 `store_goal_gpr`
   STR overflows scaled-imm12 for high-index slots),
3. The `defmethod new display` install itself failed (the
   `make_function_from_c_arm64` trampoline's `blr-via-X16-movz/movk`
   fails for `method-set!`'s specific host VA),
4. A `defun` in display.gc top-level mis-encodes.

Device-cycle diagnosis is 3 min per iteration. qemu-aarch64-static
reproduction would be ~30 s per cycle and give us per-BLR
instrumentation directly — claude's recommended path in the blocker
analysis.

## Goal (concrete)

A reproducible qemu-aarch64-static boot of gk-linux-arm64 that:

1. Loads KERNEL.CGO + ENGINE.CGO + GAME.CGO with `LINK_FLAG_EXECUTE`,
2. Reaches the same `link finish: display` milestone the Android
   device run reached,
3. Crashes (or doesn't) at the same display.gc NULL fn-ptr BLR,
4. Has per-BLR trace logging that prints the target host address
   + saved register state immediately before each `call_r64` BLR,
5. **The bug is fixed** — qemu boot reaches at least one marker past
   `link finish: display` (e.g. `link finish: connect`, `engine:
   state=`, or the desktop oracle's next-after-display CGO).

After the fix, re-run the D4 device validator —
`.autoport/validators/phase-D4-android-apk-title.sh` must exit 0
with all hardened checks passing (≥3/5 SDL/GL real-init markers,
no `forced-recovery handoff`, no synthesized markers).

## Scope (unlocked files)

- `game/linux-arm64/linux_arm64_main.cpp` (extend to load
  ENGINE.CGO + GAME.CGO via direct DGO loader, LINK_FLAG_EXECUTE on)
- `game/linux-arm64/CMakeLists.txt` (cross-compile rules for the
  extended scope)
- `game/linux-arm64/linux_arm64_runtime_compat.cpp` (additional
  abort-stubs for transitive ENGINE/GAME deps)
- `goalc/emitter/IGenARM64.cpp` (narrow: ADD per-BLR trace
  instrumentation behind `OG_DEBUG_BLR_TRACE` build flag; the
  non-trace codepath must stay byte-identical to A6's close)
- One of these depending on root cause:
  - `goalc/emitter/IGenARM64.cpp` (broader: if a different emit
    helper has a bug)
  - `goalc/emitter/ObjectGenerator.cpp` (narrow: if a klink-time
    fixup is wrong)
  - `game/kernel/common/klink.cpp` / `game/kernel/jak1/klink.cpp`
    (if the runtime patcher has the bug)
  - `game/kernel/jak1/kscheme.cpp` (if `make_function_from_c_arm64`
    or `set-display`'s install path is wrong)

The candidate set is broader than A6's because the bug is
genuinely outside A6's narrow IGenARM64.cpp+asm_funcs slot.

## STILL LOCKED

- `goalc/compiler/IR.cpp`
- `goalc/emitter/IGenARM64.h`
- `goalc/emitter/ObjectGenerator.h`
- `goalc/compiler/CodeGenerator.{cpp,h}`
- `.autoport/lib/classify_ir_arm64.py` (locked since A1)
- The A6 close commit's IGenARM64.cpp content for non-trace paths

## Anti-cheat invariants

Same as A6/A7:

- 0 `gk_recover_to_renderer` / `forced-recovery handoff` /
  `g_fault_recovery_armed` in source (these would re-introduce the
  signal-handler dodge).
- 0 new `abort()` / `std::abort()` / `__attribute__((weak))` in
  `.cpp` / `.h` / `.s` since A6's anchor.
- D4 validator's check #10 (the hardened one) must pass after the
  fix lands: ≥3/5 SDL/GL real-init markers in the device boot log.
- 0 NOPs in arm64 patcher report.
- x86 CGOs byte-identical to A2 baseline.
- Desktop x86 `gk` smoke still reaches `link finish: logo`.

## Honest exit condition

If after a reasonable retry budget (say 6-8 attempts) the qemu repro
is set up but the bug isn't fixed, the honest outcome is an
A8-attempt-N-blocker.md report describing what the per-BLR trace
identified and why fixing it requires further unlock (potentially
extending IR.cpp or CodeGenerator.cpp). The supervisor will read it
and either extend A8 or insert A9.

## Required deliverables

1. `.autoport/lib/qemu_repro.sh` — wraps cross-build + qemu run,
   ENGINE.CGO/GAME.CGO loading, per-BLR trace capture.
2. `.autoport/reports/A8-displaygc-root-cause.md` — names the actual
   failing symbol, the IR / emitter helper / runtime function that
   produces the NULL, and the fix's location.
3. The fix itself, applied to one of the unlocked files.
4. `.autoport/reports/A8-baseline-arm64-cgo-hashes.txt` if CGOs
   regenerated (likely if the fix is in goalc).
5. D4 validator passes (the post-fix device run reaches sustained
   swap with hardened SDL/GL marker requirements).
