# Phase Gcrash-mouche2 — buzzer collect now BLUE-LOCKS (residual SP-relative stack stomp) — catch the writer, fix it

## The defect (owner verification, 2026-06-24)
After Gcrash-mouche's partial fix, collecting a scout fly (`buzzer`) **no longer hard-crashes to home**
— instead the screen goes **BLUE and the music keeps playing; the app must be force-killed.** So the
SIGILL repair stopped the process crash but left a **residual corruption** that now **hangs the render
thread** (same symptom class as the steps blue-lock: app+audio alive, A35-RENDER frames stop). This is
the **SP-relative stack stomp** Gcrash-mouche flagged as the recommended follow-up. It is now
**DETERMINISTIC** (every buzzer collect) — a reliable repro.

## Lead (from Gcrash-mouche)
The buzzer pickup path is `buzzer` pickup-state entry → `manipy` (fly-to-HUD) → merc draw. The residual
is an **SP-relative (stack) stomp** that corrupts the render/DMA path (the manipy merc draw is the prime
suspect — the merc/DMA blend-shape stomp class, [[a38-blind-to-dma-content-canary]],
[[cross-thread-stomp-repair-resume]], [[gcine-cut-deferred]]). x86 is fine (the same collect reaches the
7-fly reward on x86) → arm64-specific.

## Methodology — reproduce the blue-lock, name the stomp writer, fix the root
- Reuse Gcrash-mouche's programmatic buzzer-collect trigger (listener spawn/pickup) to reproduce the
  **blue-lock deterministically**: app stays foreground + alive (music thread advancing) but A35-RENDER
  frame STOPS. Confirm the blue-lock (not a sig crash) on the current build.
- **Catch the SP-relative stomp writer:** a thread-filtered **mprotect tripwire** can't see SP-relative
  stores it doesn't fault on, so use a **content canary** over the victim (the render/DMA bucket chain
  or the kernel/manipy structures the manipy draw touches) + fp-walk on the hang
  ([[a34-crash-forensics-loop]], [[a38-blind-to-dma-content-canary]]); if available, an arm64 **HW data
  watchpoint** on the buzzer/manipy stack region names the exact store. Identify writer + victim and
  WHY the render thread then hangs (corrupted DMA NEXT pointer / bucket / fence).
- Fix the ROOT (the manipy/merc SP-relative stomp) so the render chain stays intact — prefer fixing the
  bad store; the repair-and-resume content canary is the fallback. libgk/translation layer; goal_src
  1-to-1; x86 unaffected.

## Validator (`phase-Gcrash-mouche2.sh`) PASS requires
1. `.autoport/reports/Gcrash-mouche2/runs.txt`: the buzzer collect reproduced the **BLUE-LOCK** BEFORE
   (A35-RENDER frame stops while app+music alive; writer/victim named), and AFTER collecting a buzzer
   **≥5×** the render frames KEEP ADVANCING (no blue-lock) with **0 sig**, app foreground, gameplay
   continues. With `RESULT: BUZZER COLLECT CRASH-FREE + NO BLUE-LOCK (5/5)`. Name the SP-relative stomp
   writer + victim.
2. Real `game/**`/`android/**` change; goal_src 1-to-1. Fix-summary
   `.autoport/reports/Gcrash-mouche2-fix-summary.md` ≥60 lines; temp instrumentation removed;
   `.autoport/gold` git-clean.
3. x86 `link finish: logo`; `deploy_verify.sh eae4df44` PASS.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY. Keep device
awake. After any failing device run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind.

## Max settings
`max_turns: 1600`, `max_retries: 4`.
