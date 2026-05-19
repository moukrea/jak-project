# Phase 28 — Replace `kStateSeq` stub with real `KernelCheckAndDispatch`

## Goal

`android/android_goal_main.cpp:108-130` contains the smoking gun: a
hand-rolled `kStateSeq` array that emits fake `engine: state=boot/load/
title` lines on a hardcoded timer, then drops into a
`while(MasterExit==RUNNING) sleep(250)` loop. Phase 27 just linked the
real runtime. This phase wires `android_goal_main`'s dispatcher thread
to call the real `KernelCheckAndDispatch` — and **deletes the
`kStateSeq` array**.

## Anti-stub rules

The validator runs two anti-stub checks specifically targeted at this
phase's failure modes:

1. **Source-tree forbid-list**: `android/android_goal_main.cpp` must not
   contain the substrings `kStateSeq`, `kStateSeq[`, or the literal
   triple `"boot"`, `"load"`, `"title"` in a fixed-array context. Use
   `anti_stub_forbid_strings`.
2. **Timing-jitter**: `engine: state=` log lines must have inter-event
   intervals that do NOT match the kStateSeq pattern (1500ms then
   2000ms ±50ms). Use `anti_stub_check_timing_jitter`. Real GOAL kernel
   execution has natural jitter from heap allocations, file IO, and
   thread scheduling — a stub does not.

Both checks must pass.

## Concrete deliverables

1. **Delete the `kStateSeq` array and its for loop** from
   `android/android_goal_main.cpp`. Delete the loop body, the comments
   that reference "synthetic sequence", and the file's
   `kSyntheticBootSequence` (or similarly named) helpers.

2. **Replace the dispatcher thread body** with the real
   `KernelCheckAndDispatch` loop. The desktop equivalent in
   `game/kernel/jak1/kdispatch.cpp` (or wherever) is the reference;
   call it directly, do NOT re-implement it under android/.

   Pseudocode:
   ```cpp
   while (MasterExit == RuntimeExitStatus::RUNNING) {
     KernelCheckAndDispatch();
     // The dispatcher does its own pacing; no sleep needed.
   }
   ```

3. **Wire `gstate.gc`'s `set!` hooks** so state transitions emit
   `engine: state=<name>` from real GOAL code. If the existing
   `set_state!` macro doesn't already emit a log line on transition,
   add ONE call to `__android_log_print` (or an existing logging
   shim) inside the C++ side of the macro, gated behind
   `#ifdef __ANDROID__`. The log call's source location must be in
   `game/kernel/`, NOT `android/`.

4. **Sanity helper for the validator**: add a
   `goal_dispatch_heartbeat_count` global that the dispatcher
   increments each iteration, exposed via a JNI getter
   `NativeGk.getDispatchHeartbeat()`. The validator polls this from
   adb shell over a 10-second window and asserts it strictly increases
   (proving the real dispatcher runs, not a sleep loop).

## Don't

- Do not keep the `kStateSeq` array commented out. Delete it.
- Do not move the state-transition log line into `android/`. It must
  come from `game/kernel/` so its file:line in the log proves origin.
- Do not add a `sleep_for(X)` inside the dispatcher thread "to pace".
  The dispatcher's own work paces it.
- Do not wrap `KernelCheckAndDispatch` in a try/catch that swallows
  exceptions and emits a fake state log. If the dispatcher faults,
  let it fault — that's a real bug to diagnose, not paper over.

## Pitfalls

- The desktop `KernelCheckAndDispatch` expects a fully initialized
  `Machine`. Make sure phase 27's `InitMachine` actually runs before
  the dispatcher loop spins up.
- The first dispatcher tick may take seconds (heap init, DGO load,
  symbol resolution). Don't add a timeout that fires before the kernel
  finishes initial work.
- The state transitions from gstate.gc may not be every-second by
  default; they're driven by the kernel boot path. The validator
  budget for state=title is 180s — but if the kernel is genuinely
  slower than that (large DGOs), bump the budget rather than fake the
  state.

## Validator

```
.autoport/validators/phase-28-dispatcher-real.sh
```

## Success

`android/android_goal_main.cpp` no longer contains `kStateSeq`. The
dispatcher heartbeat counter advances steadily on device. State
transition timings (boot→load→title) do not match the kStateSeq
hardcoded pattern. `engine: state=title` is reached within 180s.
