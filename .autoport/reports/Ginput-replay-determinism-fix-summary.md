# Ginput-replay-determinism — fix summary

Owner defect (2026-06-27): replaying a recorded REAL-gameplay clip does NOT
reproduce the playthrough — "Jak does the recorded moves but at the wrong
place/direction from the first seconds." The scripted self-test (pad-byte
round-trip, no engine) passed, but real gameplay diverged. This blocks the
owner-demo collision diff (Gcollision-replay-diff): you cannot diff two runs of
one demo if the demo does not even reproduce on the SAME backend.

`goal_src` is left byte-identical. The fix is entirely in the host/runtime layer
(the C++ harness + jak1 runtime glue). No goalc/emitter/IGenX86_64 change.

## Root causes found (three, all confirmed with per-logic-frame state diffs)

1. INDEX = CONTROLLER-READ COUNTER (not a game-logic frame). The harness keyed
   each record by a counter incremented once per controller-0 `CPadGetData`
   call — i.e. once per RENDERED frame. That counter advances during boot, the
   title, a level LOAD, a pause and cinematics at a VARIABLE, run-to-run rate (a
   load takes a different number of rendered frames each time; a device runs at a
   different framerate than the desktop). So a gameplay input recorded at index N
   replayed at a completely different GAME moment.
   BEFORE evidence: the prior Gcollision-replay-diff `x86_coll.trace` (replaying
   the owner's 28229-tick device demo on x86) ran the counter to tick 61594
   (2.18x overrun) with Jak frozen at the title-state position for the whole run
   — the recorded gameplay inputs landed during boot/title and never reached
   gameplay.

2. IDLE-UNTIL-FIRST-INPUT ASYMMETRY. Record skipped leading neutral reads (demo
   frame 0 = the player's first non-neutral input), but replay applied
   `records[0]` from the VERY FIRST controller read (early boot). So even
   same-backend, every input was shifted ~boot-length earlier and the demo was
   exhausted before gameplay began.

3. UNRESTORED / NON-DETERMINISTIC RNG. The harness reseeded only the desktop
   host `extra_random_generator`. It did NOT restore: the GOAL gameplay RNG
   `*_vu-reg-R_*` (rand-vu) or `*random-generator*` (both persist + evolve across
   frames); the mips2c `gRng`; and on Android `pc-rand` is a SEPARATE
   `std::random_device`-seeded mt19937 (`a35_pc_rand`) that ignored the seed
   entirely. rand-vu XORs a fresh host `pc-rand()` draw into its state EVERY call
   (math.gc:153), so the host stream is part of gameplay RNG and must be restored.

4. REAL-TIME-DELTA CLOCK (the dominant remaining non-determinism, found by state
   diff). Even after (1)-(3), the engine advances the simulation by the MEASURED
   real frame duration: `time-ratio = timer-count / *ticks-per-frame*`
   (drawable.gc:978-989), clamped to 1.0 only when float-time-ratio < 1.3. A
   slow frame (a wall-clock hitch) makes time-ratio jump to 2+, doubling the
   per-frame counter/physics advance. This is data-dependent on system load, so a
   recorded clip diverged run-to-run at a RANDOM frame.
   BEFORE evidence (this phase, fix (1)-(3) in but NOT (4)): record vs replay
   diverged at frame 202; replay#1 vs replay#2 at 202; record vs replay#2 at 515
   — a non-deterministic divergence point = a per-run wall-clock hitch.

## The fix (host/runtime only)

INDEX BY THE DETERMINISTIC GAME-LOGIC FRAME, RELATIVE TO A GAMEPLAY ANCHOR.
- `game/system/pad_replay.{h,cpp}`: records are keyed by the jak1 *display*
  `actual-frame-counter` (+1 per UNPAUSED simulated frame, pacing-independent;
  C++ read = `*display* + 812`, deftype offset 816 minus the 4-byte basic tag),
  RELATIVE to a gameplay ANCHOR. Pre-anchor reads record nothing and do not
  advance the index, so the variable-length boot/title/level-load before gameplay
  is fully ABSORBED: the i-th gameplay logic frame on replay receives exactly the
  input the i-th gameplay logic frame received on record. Demo format bumped to
  v2. The legacy controller-read path is kept for the in-process self-test
  (no providers registered).
- `game/kernel/jak1/kmachine.cpp` (`InitMachineScheme`): registers the
  logic-frame provider, the anchor provider (*target* spawned in gameplay), the
  GOAL RNG reseed, and the fixed-timestep force.

FORCE EVERY RNG STREAM AT THE ANCHOR (record AND replay), to a fixed seed:
- desktop host `extra_random_generator` (`pc_set_rand_seed`),
- mips2c `gRng` (new `Mips2C::reseed_rng`),
- GOAL `*_vu-reg-R_*` (set to a valid [1.0,2.0) bit pattern, as rand-vu-init) and
  `*random-generator*` seed (obj+0),
- Android `a35_pc_rand`'s generator (refactored to a reseedable static + new
  `a35_pc_set_rand_seed`, registered into the harness reseed chain).
All are registered through a single `pad_replay::add_rng_reseed_callback` chain
and fired once when the anchor is reached.

FORCE A FIXED GAME-LOGIC TIMESTEP WHILE ARMED:
- A per-frame callback sets `*ticks-per-frame*` very high, so float-time-ratio
  (= timer-count / *ticks-per-frame*) is ~0 < 1.3 and the PC-port clamp pins
  time-ratio to 1.0 EVERY frame: each drawn frame is exactly one 1/60s logic step,
  so the simulation no longer depends on the (variable) real frame duration.
  *ticks-per-frame* only feeds the time-ratio and the cosmetic perf bar. Default
  OFF — only ever set while the input-replay harness is recording/replaying.

## Result (same-backend record-trace vs replay-trace, x86)

A REAL-gameplay clip (OG_F1_WARP deterministic warp to Geyser Rock, then a
scripted in-engine drive: sustained run + arcing heading + periodic jumps +
camera pan — Jak really moves and collides) was recorded WITH a per-logic-frame
state dump (Jak position + orientation quaternion + velocity + camera), then
replayed on the same backend with the same dump.

- SHORT clip: 3812 game-logic frames (Jak running/jumping/roaming, 3490 distinct
  positions). record-trace == replay#1 == replay#2, BIT-IDENTICAL over the whole
  clip (sha256 684c8901...4acfa878). No per-run drift.
- LONG clip (~4 min): record 14261 frames, replay 13681; 13681-frame common
  prefix record == replay, BIT-IDENTICAL (sha256 6a808457...8fa605d6).

See `.autoport/reports/Ginput-replay-determinism/report.txt`.

## Temp instrumentation — REMOVED before close

The determinism PROOF used temporary scaffolding that is REMOVED from the
committed change (the permanent fix above stays):
- the per-logic-frame collision/pos/quat/camera state DUMP (`colldump` + its
  CPadGetData hooks + the trace-open plumbing) used to capture the record/replay
  traces — removed;
- the `OG_PAD_REPLAY_DRIVE` scripted gameplay drive (the headless record-run
  input source) — removed.
No temp dump or drive is left in the tree; `.autoport/gold` is untouched
(pristine); `goal_src` is byte-identical; the x86 build still reaches
`link finish: logo`; the device runs the fresh HEAD libgk.so (deploy_verify).

## 1-to-1 note / owner re-record

The demo FORMAT changed (v2, logic-frame anchored). The owner's existing
`.autoport/demos/*.inputs` (v1, read-counter indexed, recorded on device) must be
re-recorded with the fixed harness before the collision diff. This is expected
and called out in the phase mandate; the owner re-records in the loop.
