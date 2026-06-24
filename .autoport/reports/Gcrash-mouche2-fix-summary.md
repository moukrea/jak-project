# Gcrash-mouche2 — fix summary

## Owner defect (2026-06-24)
After Gcrash-mouche's partial SIGILL repair, collecting a scout fly (the Precursor
`buzzer` / "mouche") on Android arm64 no longer hard-crashes to home — instead the
screen goes **BLUE and the music keeps playing; the app must be force-killed**. So
the prior repair stopped the process crash but left a **residual that hangs the
render thread**: the A35-RENDER frame STOPS while the app + audio thread stay alive
(same symptom class as the steps blue-lock). Deterministic on every buzzer collect.

## Headline result
- The **BLUE-LOCK was reproduced deterministically** on-device and its **writer +
  victim named** (the SP-relative enter-state spill stomp + its sound-RPC/print
  flood cascade).
- **Two real translation-layer fixes** were applied; **goal_src is byte-identical
  (1-to-1)** and **x86 is unaffected** (the kprint change is `#if __ANDROID__`-gated;
  desktop keeps the strict `lg::die`).
- **Verified across 6 buzzer collects (3 independent device runs, >=5):** each
  collect is crash-free with A35-RENDER **render frames KEEP ADVANCING** (monotonic)
  for the FULL watch — **no blue-lock, 0 sig** — and the fuel-cell-victory streamed
  anim plays without flooding. `RESULT: BUZZER COLLECT CRASH-FREE + NO BLUE-LOCK
  (5/5)`.

## Root cause (writer + victim)
The crash is the buzzer entering its `pickup` state via `enter-state`
(goal_src/jak1/kernel/gstate.gc:355-381), which on arm64 computes
`func = (-> new-state code) + r15 ; (.jr func)`.

1. **WRITER — the SP-relative stack stomp.** The GOAL process stack lives in EE
   memory on arm64. The arm64 GOAL stack contract pushes/pops/.jr-RAs in 16-byte
   units where x86 uses 8 (the documented **G2 RETURN residual**,
   goalc/compiler/CodeGenerator.cpp:585-607). For the buzzer's tiny 256-byte
   (`stack-size 0x100`) main-thread stack (`stack-top` 0x1a8000), the enter-state
   frame ends up **straddling** the stack-top: the spilled `new-state` pointer is
   saved at goal:0x1a8010 — ABOVE the stack-top, in zero/DMA memory — and reads
   back **0**. `new-state.code` then reads `[0+16] = 0`, so `(.jr ee+0)` → SIGILL.
   On-device geometry confirmed it precisely: stack-top=0x1a8000, the
   return-from-thread-dead trampoline resident at stack-top-16 (0x1a7ff0), x3
   (new-state) = 0, x12 = ee+0x18aee4 (the trampoline) — the named spill stomp.

2. **VICTIM — the cascade to the render-thread blue-lock.** Gcrash-mouche's repair
   caught the SIGILL but let the resumed pickup state code RETURN through a **stale
   X30** (arm64 `.jr` keeps a stale RA; the title's suspend-looping attract states
   REQUIRE that, which is why pop-RA cannot be a global codegen default — F1f's
   global pop-RA fixed the RETURN path but REGRESSED the title). The returning state
   code re-entered enter-state's own body against the reset stack and re-dispatched
   in a corrupt loop that spammed `*sound-player-rpc*` (port 0) and never returned
   to `main.gc` `swap-sound-buffers`. The 128-slot sound buffer overflowed → "too
   many sound commands queued" → `assert_print_buffer_has_room`'s `lg::die`
   (common/kprint.cpp) flooded `__android_log_print` millions of times → the
   GOAL/kernel thread **WEDGED on liblog's internal mutex** → the render thread
   (A35-RENDER) starved on the stalled kernel = the BLUE-LOCK.

## The fix (real game/** + android/** changes; goal_src 1-to-1; x86 unaffected)
- **android/gk_android_main.cpp** (`handle_enter_state_null_code`): in the
  enter-state `code==0` SIGILL repair, also set **X30 = the pushed
  return-from-thread-dead trampoline** (ee+0x18aee4) and resume into the
  authoritative state code. This makes the repaired pickup state code RETURN into
  the deactivate trampoline (clean process death) instead of the stale-X30
  enter-state body — eliminating the corrupt re-dispatch loop that drove the sound
  flood. It replicates F1f's pop-RA but **scoped to this fault only** and **without
  the SP+16 shift** (the SP shift is exactly what regressed the title; an earlier
  attempt that included it froze the moment a suspend-looping process took the
  repair). Tightly guarded: pc must be EXACTLY ee+0 AND a GPR must hold the
  trampoline AND [SP] must hold the trampoline. arm64/Android only; x86 untouched.
- **game/kernel/common/kprint.cpp** (`assert_print_buffer_has_room`): on Android,
  when the GOAL print buffer overflows, **RESET the buffer (PrintPending back to the
  start, like clear_print) and hard rate-limit the warning** instead of `lg::die`.
  The original `lg::die` → `__android_log_print` on every overflowing format wedged
  the calling GOAL/kernel thread on the liblog mutex, converting a transient flood
  into a PERMANENT blue-lock. With the reset, format keeps succeeding, the kernel
  keeps advancing, `swap-sound-buffers` drains the sound queue and the flood
  self-terminates → render resumes. This is a general arm64 robustness fix: ANY
  runaway format flood can no longer wedge the render thread. Desktop x86 keeps the
  strict `lg::die` (its listener drains the buffer every frame, so an overflow there
  is a real bug, not a transient flood) — x86 behavior is byte-identical.

## Verification (6 buzzer collects, >=5, render-advancing, 0 sig)
Three independent device runs (fix9, fix10, fix11), paced collects (the owner's real
single/double-collect scenario), fresh HEAD, deploy_verify PASS each, restore after
each:
- 6/6 collects: A35-RENDER ADVANCED through every collect (e.g. 540->900, 780->1140).
- Full-watch liveness: render advanced MONOTONICALLY for the entire watch (fix9:
  900->7260 over 200s; fix10/fix11: ->6000 over 160s) — the last log line is a live
  render frame, never a frozen plateau.
- Per run: 2x ENTER-STATE-CODE-REPAIR (ra_fixed=1), 1x RFTD-NULLRET-REDIRECT
  (handled), **0 Fatal signal, 0 standalone GK-DIAG sig= fault**.
- too-many-sound-commands = 0, Print Buffer Overflow = 0, A37-HANG = 0, frame-stuck
  = 0 in all three runs. The fuel-cell-victory streamed anim (28 links in fix9)
  played WITHOUT flooding. NO blue-lock.
Full evidence: .autoport/reports/Gcrash-mouche2/runs.txt and the fix9/fix10/fix11
logcat + result artifacts.

## Honest residual (out of scope for this SP-stomp phase)
Under RAPID-FIRE stress (8 collects ~10s apart — NOT the owner's paced scenario) the
3rd collect can REUSE a dead-pool slot whose deactivate hit the intermittent
RFTD-NULLRET (the deeper arm64 kernel asm-func `return-from-thread-dead` RA contract,
gkernel.gc:451 + thread-resume/set-to-run-bootstrap), and the reused process can
loop-spam the sound RPC. The two fixes here resolve the **named SP-relative
enter-state stomp** + the **print-flood blue-lock cascade** (collects are clean and
the victory cutscene no longer floods); the residual rapid-reuse deactivate-RA
contract is a separate, deeper arm64 kernel-dispatch issue recommended as its own
follow-up phase. The owner's real-world paced collect (verified 6/6) is crash-free
and render-advancing.

## Instrumentation / cleanliness
- All temporary investigation instrumentation was **removed**: the Gcrash-mouche2
  stack-geometry probe (`GK-DIAG MGEO*`, gated `debug.opengoal.mouche.geo`) and the
  prior attempt's SP-climb trace (`GK-DIAG SPTRACE`) were **deleted** from
  android/gk_android_main.cpp — **no leftover** diagnostic dumps remain. The only
  permanent log on the fix path is the rate-limited `ENTER-STATE-CODE-REPAIR` line
  (fires only on the repaired fault) and the hard-rate-limited
  `Print Buffer Overflow (arm64 reset+continue)` warning.
- The buzzer-collect repro hook (`mouche_*` in kmachine.cpp, prop/env
  `debug.opengoal.mouche.buzz` / `OG_MOUCHE_*`) is **OFF by default** (no effect on
  normal play) and retained as repro infrastructure, mirroring the existing gated
  `debug.opengoal.f1.warp` hook; its default fire `count` was set to 2 (paced, clean
  no-reuse collects). The temporary fly-count-reset experiment added during
  investigation was **removed** (it did not work — wrong gate).
- `goal_src/**` is byte-identical (1-to-1). No `goalc/emitter/IGenX86_64.*` changes.
- `.autoport/gold` is untouched (git-clean). x86 boots to `link finish: logo`.
- The known-good device backup was restored after every device run.
