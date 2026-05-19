# Phase 26 — Execute jak1 CGOs under qemu-aarch64 (GOAL VM proof of life)

## Goal

Phase 25 just proved the CGOs are aarch64-shaped at the byte level.
That's necessary but not sufficient: aarch64-encoded gibberish would
also pass a disassembly check. This phase actually **runs** the cross-
built `gk` binary under `qemu-aarch64-static` against the new CGOs and
asserts the GOAL VM has measurable internal state changes — heap
allocations, symbol resolution, kernel dispatch — that can only happen
if real GOAL code is executing.

This is what phase 19 was supposed to be before it became a thin
"document the gap" stub.

## Anti-stub rules

- The validator runs a real cross-built `gk` binary under qemu, with the
  same argv shape phase 20+ use on Android. It is NOT satisfied by a
  custom test harness that fakes the GOAL VM. Use the production
  `gk` codepath.
- The validator captures **stack-pointer-style observables** that a stub
  cannot fake without effectively reimplementing GOAL: GOAL kheap top
  pointer must move by at least 1 MB; at least 50 distinct GOAL symbols
  must be interned; at least 100 `call_goal_on_stack` invocations must
  complete.
- These observables are emitted by **instrumented hooks placed in the
  real C++ runtime code paths**, not by free-floating logs. The
  instrumentation patches are part of the deliverable.
- If a CGO load SIGILLs, that's not a "documented gap" — it's an
  emitter bug. Fix `goalc/emitter/IGen_arm64.cpp`, run
  `bash .autoport/validators/phase-25-cgo-regen.sh` to regenerate, then
  re-run phase 26.

## Concrete deliverables

1. **Runtime instrumentation** (in real game/runtime code, NOT in
   android/ shim files):

   - Add to `game/kernel/common/kmalloc.cpp` near the kheap allocator:
     ```cpp
     #ifdef GOAL_RUNTIME_TRACE
     extern "C" void __goal_runtime_trace_kheap(uint64_t top);
     // call after each alloc/free that changes kheap.top
     __goal_runtime_trace_kheap(reinterpret_cast<uint64_t>(kheap.top));
     #endif
     ```
   - Add to `game/kernel/common/Symbol*.cpp` (wherever interning lives):
     similar callback when a new symbol is added.
   - Add to `call_goal_on_stack` (or its jak1 equivalent in
     `game/kernel/jak1/`): a callback on entry.

   The callbacks have weak default implementations that no-op. A test
   harness provides strong implementations that count + report.

2. **A cross-build target** at `tools/arm64-stress/main.cpp` that:
   - Defines the strong callbacks counting kheap-top changes, symbol
     interns, and call_goal_on_stack invocations.
   - Calls `goal_main(argc, argv)` with jak1 argv.
   - On exit, prints the three counters in a fixed format:
     `goal-stress: kheap-delta=<N> symbols-interned=<N> goal-calls=<N>`.

   The target is cross-built for arm64-linux (CMake target name
   `goal_stress_arm64`).

3. **A validator-driven qemu run:**
   ```
   qemu-aarch64-static -L /usr/aarch64-linux-gnu \
       build-arm64-linux/tools/arm64-stress/goal_stress_arm64 \
       --game jak1 --portable -fakeiso \
       -iso-data $(pwd)/out/jak1/iso/ \
       --max-frames 600
   ```

   `--max-frames 600` is a new flag on `gk` to cap the run at ~10s
   of GOAL kernel work (real, not synthetic) so the validator doesn't
   wait forever.

4. **Expected counters** (validator asserts):
   - `kheap-delta ≥ 1 MB` — proves the GOAL kernel did real allocations.
   - `symbols-interned ≥ 50` — proves the symbol table is alive.
   - `goal-calls ≥ 100` — proves the dispatcher actually runs GOAL code.

5. **No SIGILL / SIGSEGV / "qemu: uncaught" during the run** — checked
   in qemu's stderr stream.

## Don't

- Don't add a flag that disables the instrumentation. The validator
  needs the counters; a stub that prints fixed numbers gets caught
  because every run would print the same numbers.
- Don't move the instrumentation into `android/` — that's the shim
  layer; phase 28 will replace it. The instrumentation belongs in
  `game/kernel/`.
- Don't catch SIGILL inside the runtime. Let qemu emit its error to
  stderr; the validator must see it to fail honestly.

## Pitfalls

- `qemu-aarch64-static` is slow (~10x). Budget time accordingly.
- The cross-build under `build-arm64-linux/` is **different from**
  `build-arm64/` (the host x86 build of goalc-arm64). Don't confuse
  them.
- The `--max-frames` flag may not exist yet in `game/main.cpp`. Adding
  it is part of this phase's deliverable; on non-Android desktop builds
  it just sets a frame counter cap.
- The instrumentation callbacks must be `extern "C"` so the test
  harness's strong versions override the weak defaults.

## Validator

```
.autoport/validators/phase-26-cgo-exec-qemu.sh
```

## Success

`qemu-aarch64-static` runs `goal_stress_arm64` against the real jak1
CGOs for ~10s of GOAL kernel work and prints kheap-delta ≥ 1 MB,
symbols-interned ≥ 50, goal-calls ≥ 100. No fault signals from qemu.
This is the first phase that proves real arm64 GOAL execution end-to-end.
