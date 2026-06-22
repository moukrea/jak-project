# Phase Gcine-crash-mid — the intro cinematic CRASHES mid-way (non-deterministic) — reproduce it and fix the root

## The defect (owner, 2026-06-22, CURRENT consolidated build)
The owner reports the NEW-GAME intro cinematic **renders well but CRASHES mid-cinematic**. This is
NEW/separate from the already-fixed ENTRY crash ([[gfix-cinematic-crash]] fixed the save-overwrite
RET-to-null). Critically: the `Gfinal-acceptance` automated run drove the same owner path and
reached gameplay frame 14700 **crash-free** — so this crash is **NON-DETERMINISTIC** (it does not
fire every run). That is the signature of the deferred **merc/DMA blend-shape/envmap stomp class**
([[gcine-cut-deferred]], [[gd3-jak-cinematic-state]], [[a38-blind-to-dma-content-canary]],
[[cross-thread-stomp-repair-resume]]): a villain/merc draw writes a corrupted base pointer over EE
kernel code → scattered SIGILL/SIGSEGV at a non-fixed point in the cinematic. Gd3/Gmatch repaired
some sites; a residual remains deeper in the full cinematic.

## Methodology — reproduce the non-determinism, then name the stomp
- Drive the **owner-exact full intro cinematic** (NEW GAME → SLOT 0 → OVERWRITE → YES →
  memcard-saving → the WHOLE intro cinematic → gameplay) via cpad_inject, and run it **many times
  (≥ 8)** through to gameplay. The crash is intermittent, so a single clean run proves nothing —
  you must reproduce the owner's crash at least once and characterize it.
- On a crash, name it deterministically: `GK-DIAG sig=(4|6|11)` / `Fatal signal`, fp-walk + 24-word
  LR windows ([[a34-crash-forensics-loop]]), and a **content canary / mprotect tripwire** on the EE
  kernel-code band to catch the DMA/SIMD/GPU stomp the mprotect-only tripwire is blind to
  ([[a38-blind-to-dma-content-canary]]). Identify the writer (which merc/envmap/blend-shape draw)
  and the victim address.
- Fix the ROOT: extend the **repair-and-resume content canary** ([[cross-thread-stomp-repair-resume]])
  / the Merc2 bone / base-pointer repair to the residual stomp site so the kernel code is restored
  on the faulting thread before it executes. libgk-side; x86 unchanged; goal_src 1-to-1.

## Validator (`phase-Gcine-crash-mid.sh`) PASS requires
1. `.autoport/reports/Gcine-crash-mid/runs.txt`: the owner-exact full cinematic driven **≥ 8 times**,
   each reaching gameplay (frame ≥ 10500, foreground=jak1) with **0 sig(4/6/11)/Fatal** across the
   WHOLE cinematic-through-gameplay window — with `RESULT: FULL CINEMATIC COMPLETES CRASH-FREE (8/8)`.
   Plus a documented BEFORE that reproduced the owner's mid-cinematic crash (sig + writer + victim),
   OR, if it genuinely cannot be reproduced in ≥ 20 runs, an explicit honest statement of that with
   the run log (do NOT claim fixed on a non-reproduction).
2. Real libgk code change (`android/**`/`game/**`) addressing the named stomp; fix-summary
   `.autoport/reports/Gcine-crash-mid-fix-summary.md` ≥60 lines naming the mechanism; temp
   instrumentation removed; `.autoport/gold` git-clean; goal_src 1-to-1.
3. x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASS.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY/pristine.
After any failing device run, `bash .autoport/restore_knowngood_device.sh` (restores fresh HEAD set).
NO screenshot grind.

## Max settings
`max_turns: 1500`, `max_retries: 4`.
