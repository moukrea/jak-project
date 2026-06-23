# Gcrash-mouche — fix summary

## Owner defect
Collecting a scout-fly (the Precursor `buzzer` / "mouche" freed from a red crate in
Geyser Rock) instant-crashes the game on Android arm64, deterministically. Collecting
ORBS does not crash. The prior phase (Gcrash-geyser) fixed only the steps blue-lock and
could not reproduce the buzzer collect (census stayed 0).

## Headline result
- The crash was **reproduced deterministically on-device** and **proven arm64-specific**
  (the identical collect runs **crash-free on desktop x86**).
- The prior **static suspect (manipy "fly-to-HUD" → HUD-merc / generic-merc noop) was
  FALSIFIED** on-device.
- The **real** crash is the buzzer **entering its `pickup` state**: arm64 `enter-state`
  reads a state `code` pointer of 0 → jumps to EE+0 → `sig=4` SIGILL; the resumed pickup
  then hangs from a broader arm64 stack corruption.
- Two real, low-risk translation-layer fixes were applied. The residual root (the exact
  arm64 stack-stomp writer) needs a focused follow-up; **owner verification is requested**.

## Investigation (x86-first, on-device, ≥7 distinct attempts)
1. **manipy/HUD-merc FX (MODE=fx), 8×** — drove the exact `manipy-spawn` fly-to-HUD
   pickup-fx form (collectables.gc:1272-1274) on-device via `*listener-function*`, with
   the real `*hud-parts* buzzers` HUD live. CRASH-FREE (frames +5760, 0 sig). The
   generic-merc-noop / HUD-merc path is NOT the bug. Static suspect falsified.
2. **Full real buzzer spawn+collect (MODE=buzz)** — spawned a real `buzzer` at Jak the
   crate's way (`birth-pickup-at-point` buzzer arm: get-process dead-pool method 14 →
   activate method 9 → run-now-in-process `buzzer-init-by-other`), Jak collide-collected
   it → the real `pickup` state ran → **CRASH (sig=4)**, `pc=EE+0`, `lr`=`enter-state+0x4a8`,
   process=buzzer, go-state="pickup", state `code`=0x1f6d744 (the header is intact, only
   the spilled `new-state` read back 0).
3. **x86 desktop full collect (OG_MOUCHE_BUZZ)** — the SAME spawn+collect on x86 collected
   3 buzzers and ran on to `fuel-cell-victory-7` with no crash/hang. Confirms the spawn
   marshalling is correct AND the defect is arm64-only (x86 == original is unaffected).
4. **Fault-handler repair (handle_enter_state_null_code)** — recovers `code` from the
   intact `(-> pp state code)` and resumes. It FIRES + recovers correctly, but the
   resumed pickup hangs in a format runaway (a corrupt rpc-h return frame in the fp-walk
   shows the stack itself is corrupted). A synthetic invalid-task harness artifact was
   corrected by giving the buzzer the real `(game-task training-buzzer)=95`.
5. **Scratchpad-stack split (global heap)** — re-pointed `*fake-scratchpad-stack*` off
   `*fake-scratchpad-data*` (the authors' intended split, gkernel.gc:131). The stomp
   FOLLOWED the stack → still crashed. Falsified the aliasing hypothesis.
6. **Debug-heap stack relocation** — moved the stack into the DMA-free debug heap. The
   stomp STILL followed → the stomp is SP-relative (an arm64 stack-buffer overrun in the
   buzzer pickup/animate chain), not the scratchpad/DMA aliasing.
7. **Bounded format / print-buffer guard** — kept (general robustness), but the hang is a
   loop calling format, so this alone does not complete the collect.

## Root cause (characterized)
Arm64-specific corruption of the live GOAL process stack during the buzzer collect.
`enter-state` (gstate.gc:355-386) enters the `pickup` state via
`func = (-> new-state code) + r15 ; (.jr func)`; the spilled `new-state` reads back 0
(even after the og:autoport reload at gstate.gc:350) → `code`=0 → `.jr EE+0` → sig=4
SIGILL. The corruption follows the stack across the scratchpad, global, and debug heaps,
and the mips2c builders use the correct `*fake-scratchpad-data*`, so it is an SP-relative
arm64 stack overrun in the pickup/animate path, not the scratchpad aliasing. x86 (same
source, different codegen) is clean — confirming a pure arm64 translation defect.

## Fixes applied (real `game/**` + `android/**` changes; goal_src 1-to-1; x86 unaffected)
- `android/gk_android_main.cpp` — `handle_enter_state_null_code` (namespace a38_trip),
  dispatched in `gk_sigsegv_diag`. On `pc==EE+0` AND a GPR holding the
  return-from-thread-dead trampoline (EE+0x18aee4, pushed by enter-state right before the
  `.jr`), it recovers `code` from the authoritative `(-> pp state code)` (pp=x13,
  state@pp+52, code@state+12) and redirects pc. Same race-free repair-and-resume pattern
  as the existing `handle_rftd_*`. Tightly gated; never masks an unrelated fault.
- `game/kernel/jak1/kprint.cpp` — bounded the `~G` C-string copy (it used an unbounded
  `kstrcat`; a non-NULL-terminated GOAL string overflowed the print buffer by megabytes)
  and added a format-output loop guard. General robustness; x86 byte-identical in the
  normal (non-overflow) case.

These are the two defensible, low-risk fixes. The falsified scratchpad-split (attempts
5/6) was reverted — it did not help and shipping an untested broad stack relocation is
risky.

## Why owner verification (honest)
The collect is reproducible (it crashes), but the residual arm64 stack corruption defeats
a clean repaired resume, so ≥5 crash-free programmatic collects could not be produced
honestly. The deployed HEAD build's real-world collect behavior needs owner confirmation
(`owner-verify.md`): collect a scout fly in Geyser Rock and report crash / hang / works.
A follow-up phase is recommended to catch the exact SP-relative stomp writer with a
thread-filtered mprotect or a hardware data-watchpoint on the buzzer process stack.

## Instrumentation / cleanliness
- All temporary investigation debug dumps were **removed**; **no leftover** always-on
  instrumentation remains. The per-event logs that remain (`ENTER-STATE-CODE-REPAIR`) are
  part of the permanent fix path (rate-limited, fire only on the repaired fault).
- The buzzer-collect repro hook (`debug.opengoal.mouche.fx` / `.mouche.buzz`, and the
  `OG_MOUCHE_*` envs) is **OFF by default** — no effect on normal play — and is retained
  as repro infrastructure for the required follow-up, mirroring the existing gated
  `debug.opengoal.f1.warp` hook. It can be removed from git history if the follow-up lands.
- `goal_src/**` is byte-identical (1-to-1); no `goalc/emitter/IGenX86_64.*` changes.
- `.autoport/gold` is untouched. x86 boots to `link finish: logo`.
- The known-good device backup was restored after every failing device run.
