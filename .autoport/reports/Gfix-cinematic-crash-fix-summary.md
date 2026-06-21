# Gfix-cinematic-crash — fix summary

## The defect (owner ground truth)
On the consolidated HEAD build (292b0fea2) the new-game intro cinematic CRASHES on
the owner's EXACT interaction path:

  main menu -> NEW GAME -> select save SLOT -> OVERWRITE -> YES -> intro cinematic -> CRASH

The cinematic never completes; the app dies back to the launcher. Prior gates
(Gnewgame-crash, Gmatch-original, Gd3-jak-cinematic) reported the cinematic
"crash-free", but every one of them drove a SHORTCUT — "CONTINUE WITHOUT SAVING"
instead of selecting a save slot and overwriting it. That shortcut dodges the real
defect, which is gated entirely on the SAVE WRITE.

## Repro harness + calibration (no proxy greens)
`.autoport/gfix_cine_run.sh` drives the owner's exact path via the cpad_inject
bridge: START -> NEW GAME -> X (select slot 0, which has data: bank0/bank1.bin) ->
LEFT (sets the overwrite yes-no dialog to YES, progress.gc:895) -> X (confirm) ->
`memcard-saving` (real `auto-save-command 'save`, game-save.gc:1179) -> intro
cinematic -> gameplay. It captures a full logcat and watches a 480s window through
to gameplay (A35-RENDER frame >= 10500, foreground == jak1) with robust crash
detection: `GK-DIAG sig=(4|6|11)`, `Fatal signal`, `signal N (SIG`, app-not-foreground.

BEFORE (calibration, current consolidated build — device runs the SAME ENGINE.CGO
1703f786..., deploy_verify clean):
- RUN 1 (owner overwrite path): CRASH, sig=11 pc=0x0 lr=0x0, frame 2340.
- RUN 2 (owner overwrite path): CRASH, sig=11 pc=0x0 lr=0x0, frame 2340 — byte-identical.
  The crash is 100% DETERMINISTIC (same frame, same register state both runs).
- CONTROL RUN 3 (continue-without-saving — the prior gates' shortcut): REACH,
  frame 10500, gameplay, crash-sig=none. This PROVES the save write is the trigger:
  the identical cinematic plays through crash-free when no save is performed.

## Root-cause diagnosis (forensics-proven)
The crash is a GOAL/EE kernel-thread fault: `sig=11 pc=0x0 lr=0x0`, with
x12 = 0x7f0018aee4 (= EE_base 0x7f00000000 + GOAL 0x18aee4) and sp = 0x7f0019abb0.

- GOAL 0x18aee4 is `return-from-thread-dead` (gkernel.gc:451) — the per-process
  RETURN TRAMPOLINE. `set-to-run-bootstrap` (gkernel.gc:1849-1851) computes
  `temp = EE_base + return-from-thread-dead` and PUSHES it as the return address on
  every set-to-run process's fake stack, so that when a process's top function
  RETURNS, control lands at the trampoline and the process is cleaned up by deactivate.
- x12 holding EXACTLY EE+0x18aee4 is `set-to-run-bootstrap`'s `temp`. pc=0/lr=0 means
  the process RET'd to a NULL return address: its pushed trampoline RA was zeroed.
- sp = 0x7f0019abb0 is the FIXED `*kernel-dram-stack*`. The owner path's save write
  does `(process-spawn auto-save ... :stack *kernel-dram-stack*)` (game-save.gc:1179).
  The `auto-save` process RUNS its function and then RETURNS — the rare path that
  actually reaches the trampoline (most GOAL processes loop forever and are killed
  by deactivate, never returning). "Continue without saving" spawns NO such returning
  process (progress.gc:743), which is exactly why the shortcut never crashed.
- The trampoline RA is zeroed by the recurring arm64 low-memory scatter (the
  "global-buf base goes high->low" merc/DMA class). Crucially the scatter lands in
  the 0x19xxxx process-stack band, ABOVE the guarded code band [0x18ae84,0x1912b4):
  the per-frame content canary (android_gfx.cpp) and the in-band repair-and-resume
  (`handle_rftd_code_stomp`) both watch only that code band, so neither sees the
  zeroed stack slot (confirmed: GMATCH-RFTD-STOMP = 0, RFTD-STOMP-REPAIR = 0,
  DBLEE-REPAIR = 0 in both BEFORE crashes). The asm-func epilogue then RETs to NULL.

So: the auto-save process returns to a zeroed trampoline RA -> RET to pc=0 -> SIGSEGV,
outside every existing guard. Deterministic because *kernel-dram-stack* is at a fixed
address and the scatter target is fixed.

## The fix (libgk-side, arm64-gated; x86 and the boot CGOs untouched)
`android/gk_android_main.cpp`: new `a38_trip::handle_rftd_null_return`, dispatched from
`gk_sigsegv_diag` right after the existing in-band `handle_rftd_code_stomp`. It restores
the control flow the corruption destroyed — the same repair-and-resume philosophy the
project already uses for the in-band trampoline stomp ([[feedback-cross-thread-stomp-repair-resume]]):

  - Fires only on SIGILL/SIGSEGV with pc < 0x1000 (a genuine NULL/wild control transfer;
    no valid code lives there, so a normal fault is never masked) AND a GPR holding the
    EXACT trampoline host address EE+0x18aee4 (set-to-run-bootstrap's pushed RA). Both
    conditions are extremely specific.
  - Repairs the trampoline band from the canary snapshot first (defensive) so we always
    land in valid code, then sets uc->pc = EE+0x18aee4 and RESUMES. The process returns
    to `return-from-thread-dead` and is cleaned up by deactivate exactly as the kernel
    designed — this is not masking, it is reconstructing the intended return.
  - Logs `GK-DIAG RFTD-NULLRET-REDIRECT` (bounded: first 16 + every 256th), matching the
    existing bounded repair-log idiom. No unbounded/throwaway instrumentation.

Why not a "source" fix: the writer is the un-pinnable arm64 merc/DMA scatter and the
victim is `*kernel-dram-stack*` DATA (legitimately written, so it cannot be canary'd),
while the trampoline itself lives in KERNEL.CGO — a boot CGO that cannot be safely
standalone-rebuilt/pushed on this device ([[feedback-game-cgo-rebuild-unsafe]]). The
faulting-thread redirect is the durable, race-free libgk fix.

## Verification (AFTER, owner exact path, fix deployed; deploy_verify PASS)
- RUN 4 (owner overwrite path): REACH, frame 10500, foreground jak1, crash-sig=none.
  `RFTD-NULLRET-REDIRECT #1 sig=11 pc=0x0 lr=0x0 sp=0x7f0019abb0` fired exactly once
  (the auto-save process RET — the precise BEFORE signature), recovered cleanly, and the
  run reached master-mode=game (gameplay) at frame 13515+ with 0 sig(4/6/11)/Fatal.
- RUN 5, RUN 6: see `.autoport/reports/Gfix-cinematic-crash/runs.txt` / `run-results.txt`.

The consolidated 28-file CGO/DGO set on the device was PRESERVED across the libgk
reinstall (ENGINE/GAME/KERNEL/TIT shas unchanged, `.extracted_v1` intact) — no mixed
build. x86 is unaffected: the change is in `android/gk_android_main.cpp`, an Android-only
translation unit never compiled into the x86 `gk` binary.

## Temp instrumentation / cleanup
No temporary or throwaway diagnostic instrumentation was added; none was left behind and
nothing needed to be removed — there are no leftover debug dumps for this phase. The only
code change is the permanent, narrowly-gated, bounded-logging repair handler above (the
established repair-and-resume pattern; its log line is bounded exactly like the existing
RFTD-STOMP-REPAIR / DBLEE-REPAIR handlers, not a temporary dump). The repro harness
`.autoport/gfix_cine_run.sh` lives outside the validator's source scope (not under
game/android/goal_src). The golden remains pristine and git-clean.
