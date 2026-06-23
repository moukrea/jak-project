# Phase Gcrash-geyser — Geyser Rock crash when climbing the steps (blue-screen-lock OR crash-to-home) — fix the root

## The defect (owner, 2026-06-23, on the current in-game build)
The build warps straight into the first playable level (Geyser Rock) after the ND logo. Playing:
walk to the **steps/stairs and climb them (requires jumping up 2-3 steps)** — and **non-
deterministically** ONE of two failures hits:
- **(A) BLUE SCREEN / render lock** at the very first steps: the screen goes blue and the game
  freezes, **but the background music keeps playing** → the GOAL/audio threads are alive while the
  **render thread is hung / stuck drawing blue** (A35-RENDER frames stop advancing). NOT a process
  crash.
- **(B) HARD CRASH TO HOME** if you get a bit further past the steps: the app dies to the launcher
  (a signal — SIGSEGV/SIGILL).
Same area, two modes — likely one root corruption that sometimes hangs the Adreno GPU (blue lock)
and sometimes faults (crash). Prime suspects: the deferred merc/DMA blend-shape/envmap stomp class
([[a38-blind-to-dma-content-canary]], [[cross-thread-stomp-repair-resume]]), an arm64/GLES draw that
hangs Adreno (a shader/texture/geometry first hit in that area), or a collision/object handler.

### (C) DETERMINISTIC trigger — START HERE: collecting a SCOUT FLY ("mouche") = INSTANT CRASH
The owner reports: **collecting a scout fly (the little Precursor "mouche" freed from boxes) crashes
the game INSTANTLY, every time.** This is DETERMINISTIC (unlike the steps crash) — so it is your best
handle. The crash is in the COLLECT/pickup code, not the platforming to reach it.

**Reach the collect PROGRAMMATICALLY — do NOT try to platform Jak to the fly blind** (the owner only
got there with manual touch controls; you don't have those and don't need them). Use the most
reliable trigger:
- **Directly invoke the scout-fly pickup** via the GOAL listener (find the fly/`fly-trap`/
  `money`/`buzzer`-style pickup or `(send-event ... 'touch ...)` / `pickup` handler and call it on a
  live fly), OR
- **Teleport Jak onto a scout fly** (`(set! (-> *target* control trans) <fly-pos>)` / a debug
  move-to) so the proximity-collect fires, OR
- **Spawn a scout fly at Jak's position** and let the collect trigger.
Any of these reproduces the collect crash without navigating. `cpad_inject` (synthetic gamepad) is
available for movement if needed, but the listener-driven collect is the deterministic path.
Fix this crash FIRST (it's reliable + instant), then verify the steps modes are also clean.

## Methodology — reproduce BOTH modes, name them, fix the root
- Drive the owner's path via cpad_inject: in-game at Geyser Rock → move forward to the steps → **jump
  up the steps** → continue further. Run it **many times (≥8)** — it's intermittent, so a clean run
  proves nothing; you must reproduce at least one blue-lock AND/OR one crash and characterize them.
- **Detect BOTH failure modes:**
  - HARD CRASH (B): `GK-DIAG sig=(4|6|11)` / `Fatal signal`, app-not-foreground; fp-walk + 24-word LR
    windows ([[a34-crash-forensics-loop]]); content-canary if it's a DMA/SIMD stomp.
  - BLUE LOCK (A): the app stays foreground + alive (music/GOAL thread advancing) but **A35-RENDER
    frame STOPS advancing** (render hung) and the framebuffer is ~uniform blue. Instrument the render
    thread to catch WHERE it hangs (which bucket/draw/GL call) — an Adreno GPU stall, a fence/sync
    wait, or an infinite loop in a GLES path first exercised by that area's geometry.
- Fix the ROOT so climbing the steps and progressing further is crash-free AND render-progress-free
  of the blue lock. libgk/translation-layer fix; goal_src 1-to-1; x86 unaffected.

## Validator (`phase-Gcrash-geyser.sh`) PASS requires
1. `.autoport/reports/Gcrash-geyser/runs.txt`: the Geyser-Rock climb-the-steps path driven **≥8
   times**, each progressing PAST the steps and further, with **0 sig(4/6/11)/Fatal** AND **render
   frames keep advancing** the whole time (no blue-lock: A35-RENDER frame monotonically rises past
   the steps beat, app foreground). With `RESULT: GEYSER STEPS CLIMBED CRASH-FREE + NO RENDER LOCK (8/8)`.
   Plus a documented BEFORE that reproduced the owner's blue-lock and/or crash (the named mode +
   writer/victim or the hung GL site).
2. Real libgk/translation-layer change (`game/**`/`android/**`/`goalc/**`); goal_src 1-to-1.
   Fix-summary `.autoport/reports/Gcrash-geyser-fix-summary.md` ≥60 lines naming the mechanism;
   temp instrumentation removed; `.autoport/gold` git-clean.
3. x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASS.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY/pristine.
Keep device awake/unlocked. After any failing device run, `bash .autoport/restore_knowngood_device.sh`.
NO screenshot grind (a couple frames to confirm blue-vs-rendered is fine).

## Max settings
`max_turns: 1600`, `max_retries: 4`.
