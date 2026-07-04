# Phase Gperf-particles — particle-heavy zones tank the fps (fire effects worst); big perf still on the table

## Why (owner 2026-07-03, v3 playtest on his Snapdragon 8 Elite Gen 5)
On the best mobile SoC on the market (runs emulated AAA PC games), some zones drop BELOW 25 fps at
30% render scale. The WORST offenders are particle-heavy areas — e.g. moving fire effects. Low
render scale not helping proves it is NOT fill-rate: it is CPU/submission again (Gperf-batching's
finding), and the particle path is the prime suspect. The owner is right that nothing in this 2001
game justifies this cost — there is a lot of performance left to grab.

## Context — what Gperf-batching already established (read its report first)
- Device is draw-call-submission/CPU bound; fill-rate has huge headroom.
- Per-family profiler exists: `debug.opengoal.perf.buckets=1` → A35-PERF per-bucket dump (ms/draws/
  tris + flush-phase children). Kill switch pattern: `debug.opengoal.perf.nobatch`.
- Merc was fixed (state cache, sync dedupe, bone-UBO ring). Sprite/generic/sparticle families were
  NOT touched (sprite was only 2.8ms/10 draws in the STATIC Geyser profile — but particle-heavy
  scenes are a different regime entirely).

## Mandate — profile the OWNER's regime first, then attack the top cost
1. PICK a particle-heavy scene on eae4df44 (fires: Rock Village torches/bonfire, Misty camp fire;
   use the warp + eco-spawn/debug hooks as needed). Reproduce the collapse: capture fps + A35-PERF
   at LOW render scale so fill-rate is excluded (e.g. 30-40%).
2. ATTRIBUTE, split CPU vs GPU vs submission:
   - buckets_ms per family in that scene (sprite? generic? sparticle bucket builders?),
   - the CPU side: mips2c sparticle kernel cost per frame (sp-process loops, per-particle GOAL/
     mips2c work on the render or kernel thread?), DMA-chain build cost,
   - draw counts: are particles issued as MANY tiny draws (per-cluster glDrawElements/state churn)?
3. FIX the top item(s), renderer/GLES/runtime only (goal_src untouched, gold READ-ONLY). Candidate
   levers (pick by profile, not by guess): batch/instance sprite quads into one draw per texture
   page (the sprite renderer already aggregates on desktop — check what the GLES path lost),
   state-cache the sprite/generic per-draw setup like Merc2 got, cut per-flush syncs (map/orphan
   patterns), reduce redundant uniform/texture rebinds in the hot loop, and if the CPU sparticle
   kernel dominates, memoize/vectorize its per-particle inner loop (arm64 NEON is fine — it is
   translation-layer).
4. MEASURE: NUMERIC before→after fps + buckets_ms + draw count in the SAME pose-held particle
   scene (in-session A/B like Gperf-batching round4). Gate: >= +20% fps in the particle-heavy
   scene (or >= +5 fps absolute, whichever is larger), zero visual delta (screencap parity),
   0 flicker, all prior fixes intact (orbs, eco bursts — same families, HIGH regression risk:
   re-verify eco pickup bursts + orb HUD explicitly). Kill switch prop for every change.

## Verify (device eae4df44)
Pose-held A/B numbers in the fire scene; eco-burst + orb regression screencaps; 0 flicker; x86
link finish: logo; full CONSISTENT build, deploy_verify PASS.

## Report (`.autoport/reports/Gperf-particles/report.txt`) with `RESULT: PARTICLE PERF <before>-><after> FPS`
the profile table (family ms/draws, CPU sparticle cost), the named top cost, each fix + its
measured gain, the A/B, eco/orb regression check, kill switches, x86 ok.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; engine goal_src untouched; .autoport/gold READ-ONLY.
## Max: max_turns 2400, max_retries 5. device: true, owner_verify: true.

## OWNER CLUE (2026-07-04, v4 playtest) — WORSE AT NIGHT, worst with fire; it's slow EVERYWHERE
The owner reports the slowdown is NOT localized: "c'est partout à opti, surtout la nuit on dirait,
et encore plus quand il y a des effets type feu". Two strong signals to steer the profiling:
 1. NIGHT is worse than day. Profile the SAME scene at NIGHT vs DAY (set time-of-day via the debug
    hook / `*time-of-day*`), A35-PERF both. Night-specific cost suspects: the TOD-texture blend/
    ping-pong path (already touched in round 3 — measure its real per-frame cost at night), extra
    light/additive/emissive passes, sky/ambient, more visible glow sprites. Find WHY night costs
    more and cut it — this likely helps the WHOLE game, not just fire scenes.
 2. FIRE is the worst case on top of night. The headline A/B MUST be a NIGHT scene WITH fire
    (Rock Village torches/bonfire at night, Misty fire) — not a day static Geyser.
 3. "Everywhere" means the win should generalize: prefer fixes to hot paths that run in every
    scene (per-draw state churn, TOD blend, sprite/generic submission) over one-scene hacks.
    Report day-vs-night numbers for at least two zones so the owner sees a broad gain.
Warp DIRECTLY to the chosen night-fire scene (don't wander): use the level warp + time-of-day +
eco/particle debug hooks to land on the exact beat, then pose-hold the A/B.
