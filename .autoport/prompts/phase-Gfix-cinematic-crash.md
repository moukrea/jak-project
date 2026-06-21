# Phase Gfix-cinematic-crash — the new-game intro cinematic CRASHES (owner's exact path) — fix it for real

## The defect (owner, 2026-06-21, on the consolidated build)
Owner path, EXACTLY: **main menu → NEW GAME → select save slot → OVERWRITE → YES → intro cinematic → CRASH** (cinematic does not complete). A prior validator claimed "crash-free to frame 11160" — but it used a different/shortcut entry and MISSED this. The crash is almost certainly the long-deferred **non-deterministic arm64 merc/DMA stomp** revealed in the villain cinematic ([[gcine-cut-deferred]]: blend-shape/envmap merc draw stomps EE memory; scattered SIGILL/SIGSEGV) — but reproduce it on the OWNER's exact path before concluding (the save-overwrite flow may also contribute).

## Methodology (mandatory — no proxy greens, see [[proxy-dumps-false-green]])
- Reproduce the **owner's EXACT interaction path** via cpad_inject: NEW GAME → navigate to a save slot → SELECT → OVERWRITE → YES → let the intro cinematic play. Do NOT use a shortcut that skips the save-overwrite or the villain beats.
- **Calibrate first:** on the CURRENT consolidated build, your repro MUST reproduce the crash (capture the sig + the full crash dump). If you can't reproduce the owner's crash, your harness is wrong — fix the repro before any fix.
- The crash is **non-deterministic** — run the full path **multiple times** (≥3 clean completions required to call it fixed). Robust crash detection: `GK-DIAG sig=(4|6|11)`, `Fatal signal`, `signal N (SIG`, and app-not-foreground-at-end — over a window that covers the WHOLE cinematic through to gameplay.

## Mandate
Fix the real cause so the cinematic plays through to gameplay on the owner's exact path, crash-free, repeatably. If it's the merc/DMA stomp, the durable approach is the content-canary detect/repair on the corrupted DMA destination during the villain blend-shape/envmap draw ([[a38-blind-to-dma-content-canary]], [[gnd-state]]); if the save-overwrite flow contributes, fix that too. x86 unchanged.

## Validator (`phase-Gfix-cinematic-crash.sh`) PASS requires
1. `.autoport/reports/Gfix-cinematic-crash/runs.txt`: the owner's exact path driven **≥3 times**, each reaching gameplay (frame ≥ 10500, foreground=org.opengoal.gk.jak1) with **0** sig(4/6/11)/Fatal across the full window — with `RESULT: CINEMATIC COMPLETES CRASH-FREE (3/3)`. Plus a documented BEFORE that reproduced the crash (calibration).
2. Real code change (`game/**`/`android/**`/`goal_src/**`); fix-summary ≥60 lines naming the crash mechanism + the fix; temp instrumentation removed; golden git-clean.
3. x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASS.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. Golden READ-ONLY/pristine. Device may need the owner unlocked. After any failing run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind.

## Max settings
`max_turns: 1500`, `max_retries: 4`.
