# Phase Grender-audit — pinpoint, DETERMINISTICALLY and x86-FIRST, why the device render diverges from the original (NO fix, diagnostic only)

## Why (owner observations on the latest device run, 2026-06-20)
The owner compared the phone to the untouched original and reported, concretely:
1. **The game runs at ~HALF SPEED** — "fluid, but everything takes twice the time." Render looks smooth (~60fps) but the simulation/animation advances at ~half rate. THIS likely also explains why the cinematic "doesn't complete" in the capture window (reaches ~frame 4200 because it's slow, not only crashing).
2. **Missing particles / stars; the SUN renders as a "weird halo"** instead of a real sun — these effects are present in the original but absent/wrong on the device (the arm64 renderer is a curated subset; sparticle/effect/sun-corona builders may be noop'd).
3. **Jak is INVISIBLE in the cinematic** (and the villains' draw crashes it) — the arm64 **merc (character) draw** renders nothing for Jak and memory-stomps for the villains.
4. **Camera/transition timing still off** — likely downstream of the half-speed clock.
The owner: "these should be issues you should be able to pinpoint programmatically." So: MEASURE, don't eyeball. See memory [[state-dumps-x86-first-not-screenshots]], [[cinematic-audit-findings]] (Gcine-audit DATA-diff is the model).

## Mandate — DIAGNOSE ONLY (no code fix this phase). Produce a ranked, evidence-backed divergence map.
Deterministic STATE/DATA dumps, compared our-x86 / original-x86 / device. NO screenshot pixel-diffs, NO video grind. Add temporary instrumentation behind env flags; REMOVE it after; keep `jak-original-v033` git-clean.

**D1 — Game-clock / half-speed (HIGHEST priority — likely one root cause for several symptoms).**
- Measure the GAME-LOGIC advance rate vs wall-clock on the DEVICE and on x86: dump the engine frame/clock counter (e.g. `(-> *display* base-frame-counter)` / `*display*` field, the vsync-callback tick, the game-clock delta) with timestamps over ~30s at a steady beat (title attract or in-game). Compute game-frames-per-real-second. Is the device ~½ of x86 (e.g. 30 vs 60)? Pin WHERE: is the vsync callback firing at half rate, is the per-tick delta-time halved, is logic ticked once per 2 display frames? Name the file:line that sets the rate on arm64 vs x86.

**D2 — Per-bucket render census (what is NOT being drawn).**
- At each beat (title, newgame-cinematic, in-game), dump per-bucket draw-count + tri-count on DEVICE vs x86 (the A35-RENDER log already has buckets_drawn/draws/tris; extend to PER-BUCKET, by bucket id/name). Diff → which buckets are empty/missing on the device: the **sparticle/particle buckets** (→ missing particles/stars/sun), the **merc bucket(s)** (→ invisible Jak/characters), the **sky/sun-corona**. List each missing bucket + whether its builder is noop'd in the arm64 mips2c allowlist (`game/mips2c/mips2c_table_jak1_arm64.cpp`) or its renderer TU is excluded from the Android CMake build.

**D3 — Merc / Jak invisibility + villain crash (same path?).**
- Confirm the cinematic merc draw: is Jak's merc bucket present but drawing 0 tris (skipped), or absent? Is it the SAME merc path as the villain blend-shape/envmap draw that stomps EE memory (the deferred merc/DMA bug, [[gcine-cut-deferred]], [[gnd-state]])? Name whether "Jak invisible" and "villain crash" share one arm64 merc-render root.

**D4 — Sun / sparticle specifically.** Is the sun a real disc+corona in the original but a bare additive blob ("halo") on device because the corona/sparticle builder is noop'd? Were Ghalo/Ghalo-sun's changes SUPPRESSING the sun rather than rendering it? State plainly.

## Output (the deliverable)
`.autoport/reports/Grender-audit/divergences.md` — a RANKED divergence map: each issue (D1 half-speed, D2 missing buckets, D3 merc/Jak, D4 sun) with the deterministic numbers (device vs x86), the pinned mechanism (file:line / noop'd builder / excluded TU), severity, and a recommended FIX ORDER. Plus the raw dumps under `.autoport/reports/Grender-audit/`. Supervisor triages this into single-defect fix phases.

## Locks
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. Original repo + `.autoport/gold/` READ-ONLY/pristine (remove temp dumps). NO code fix, NO screenshot/video grind. Device may need the owner to keep the phone unlocked for captures.

## Validator (`phase-Grender-audit.sh`) PASS requires
`.autoport/reports/Grender-audit/divergences.md` exists with: a D1 game-clock rate number for BOTH device and x86 (proving/measuring the half-speed factor); a D2 per-bucket census naming ≥1 missing/empty bucket on device vs x86 with its noop'd-builder/excluded-TU cause; a D3 verdict on Jak-invisible vs villain-crash sharing a merc root; a ranked fix order; raw dump artifacts present; original golden git-clean (temp instrumentation removed); NO `.mp4`/large frame-pool grind.

## Max settings
`max_turns: 1500`, `max_retries: 3`.
