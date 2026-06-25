# Ginput-replay — fix summary

Phase **Ginput-replay**: a faithful, deterministic HOST-side input record/replay
harness for the OpenGOAL jak1 Android port. Owner directive (2026-06-25): boot,
idle until the first input, then **record every input faithfully** (full pad
state per logic tick, flushed per tick) until a crash → an **infinitely
replayable demo** the worker replays autonomously to instrument/fix the two
navigation-gated crash bugs (Gportal-crash, Gcrash-mouche3); and replay the SAME
demo on x86 vs arm64 and compare **state-anchored** (deterministic logical state
/ logic tick, NOT framerate-dependent render frames) so the first divergent
state/value names the bug. `goal_src` is byte-identical — the change lives
entirely in the host pad layer.

## What changed (host-pad-layer only; goal_src 1-to-1)

New backend-agnostic module:

- `game/system/pad_replay.h` / `game/system/pad_replay.cpp` — the record/replay
  core. No dependency on GOAL kernel types: it operates only on the 6 consumed
  input values passed by pointer, so it compiles unchanged into both the desktop
  gk and the Android `libgk.so`.

Tap wired into the single boundary the game consumes (`CPadGetData`, bound as the
GOAL symbol `cpad-get-data`), on BOTH backends:

- `game/kernel/common/kmachine.cpp` — desktop x86 `CPadGetData`: tap added just
  before `return cpad_info;` (after the live `scePadRead` merge). Also adds
  `pc_set_rand_seed(u32)` (reseeds `extra_random_generator`, the host RNG mixed
  into the GOAL gameplay `rand-vu`) and registers it as the pad_replay rng-seed
  callback next to the `pc-rand` symbol bind.
- `android/android_runtime_compat.cpp` — Android arm64 `CPadGetData`: tap added
  right after the `button0`/stick stamping (the same consumed state the desktop
  path produces). `common/kmachine.cpp` is intentionally NOT compiled on Android,
  so there is no duplicate `CPadGetData`.

Plumbing:

- `game/main.cpp` — `--pad-replay-selftest <out>` runs the self-test through the
  real tap and exits before any runtime/gfx init; `init_from_env()` arms live
  record/replay from `OG_PAD_REPLAY_RECORD` / `OG_PAD_REPLAY_REPLAY`.
- `android/gk_android_main.cpp` — the property `debug.opengoal.pad_replay`
  (`selftest` | `record` | `replay`) arms the harness on device (no argv on
  Android), reusing the app-private files dir already used by the F1d cpad
  injector. Default OFF — a normal boot and deploy_verify are untouched.
- `game/CMakeLists.txt` and `android/CMakeLists.txt` — add
  `game/system/pad_replay.cpp` to the desktop game lib and the Android `gk` lib.

## The record format (FULL absolute state per logic tick, NOT events)

Each logic tick is one fixed-size 6-byte `PadRecord`:

```
struct PadRecord { uint16_t button0; uint8_t leftx, lefty, rightx, righty; };
```

- `button0` is the full 16-bit PS2 button bitmask (ButtonIndex layout, pressed =
  1) — all 16 buttons captured as an **absolute bitmask every tick**, so no edge
  (press OR release) can ever be missed. L2/R2 are digital bits 8/9 in this jak1
  build; there are no separate analog-trigger bytes to capture.
- `leftx/lefty/rightx/righty` are the two analog sticks, 0..255, 127 = neutral —
  captured absolutely every tick (NOT as deltas).

This is exactly the set of values `CPadGetData` stamps into the GOAL `CPadInfo`
for controller 0, i.e. the complete consumed input for the player each frame.

A 64-byte header precedes the records: magic `OGPADRP1`, version, record size,
**rng seed**, kernel start-frame counter, and a 32-byte reserved fingerprint (the
crash phases stash the continue-point + Jak spawn position there). The demo file
is `header || record[0] || record[1] || ...`, so file size == 64 + N*6 exactly.

## Merge / tap point

`CPadGetData` is the single backend-agnostic boundary: on x86 it pulls the
SDL-gamepad + keyboard merge via `scePadRead`→InputManager; on Android it pulls
the touch-overlay + Bluetooth-gamepad + headless-injector merge via
`android_input_audio::get_cpad_state`. We tap AFTER that merge and BEFORE GOAL
reads the buffer, so we record/replay exactly the state the game consumes. Only
controller 0 advances the logic tick (the game polls 4 pads per frame; recording
all four would multiply the index by 4 and desync replay).

## Logic-tick index (framerate-INDEPENDENT)

`CPadGetData` for controller 0 is called exactly once per fixed-timestep
game-logic step (`service-cpads`, once per display/logic frame). The harness uses
its own monotonic counter incremented on each controller-0 read as the logic-tick
index. It deliberately does NOT use any `*display*` frame counter — those are
time-scaled, pause-gated and lag-doubled (framerate-dependent) and would be noise
across builds rendering at different fps (device ~24 fps vs x86). One record per
logic tick; replay applies one record per logic tick, tick-locked.

## Flush-per-tick (crash loses nothing)

In Record mode every `PadRecord` is `fwrite`+`fflush`ed the same tick it is
produced. A crash at logic tick K still leaves ticks 0..K in the file — the crash
tick is always the last record — which is the whole point of the owner-records-
once workflow.

## Idle-until-first-input

Recording does not start (and the logic tick does not advance) until the first
NON-NEUTRAL pad state. Frame 0 of the demo is the first real input; the header
(seed + start-frame fingerprint) is written lazily at that moment. The self-test
proves this: 3 leading neutral ticks are fed and skipped (tick stays 0).

## Determinism / start-state mechanism

The demo header stores the rng seed. On replay, the first replayed tick reseeds
the host RNG (`extra_random_generator`) via the registered callback, so a demo
replays deterministically (pc-rand feeds the GOAL gameplay rand-vu). The crash
phases additionally restore the continue-point + spawn fingerprint before
applying inputs from tick 0. The self-test demonstrates determinism directly:
two independent replays of the same demo produce bit-identical applied state at
every logic tick (`DETERMINISM: 0/120`).

## State-anchored x86-vs-arm64 diff (NOT render-frame-indexed)

`dump_state(label, data, len)` appends a line keyed by the current **logic tick**
(`<label> tick=<t> <hex...>`), NOT a render frame. Replaying one demo on x86 and
on arm64 and comparing these dumps at matching logic ticks must be bit-identical
(the game is deterministic: same logical state ⇒ same variables/floats regardless
of build). The first differing `(tick,label)` is the first-divergent STATE/VALUE
localizer that names the bug. The crash phases call `dump_state` with the GOAL
state under test (Jak pos/vel/control-state, target/process state, globals); this
phase exercises the same pipeline end-to-end with the per-logic-tick pad state as
the state vector, proving x86 and arm64 produce bit-identical dumps at matching
logic ticks for the self-test demo.

## How the crash phases + the diff consume this

1. Owner boots on device with `debug.opengoal.pad_replay=record`, idles, performs
   the navigation that triggers the crash; the demo flushes every tick to
   `<files>/pad_demo.inputs`, capturing the crash tick.
2. Worker pulls the demo and replays it with `debug.opengoal.pad_replay=replay`
   (and on desktop with `OG_PAD_REPLAY_REPLAY=<demo>`), reproducing the crash
   deterministically and infinitely — no owner needed — to instrument/fix/verify.
3. The SAME demo replayed on x86 and arm64 with `dump_state` of the relevant GOAL
   state, compared at matching logic ticks, localizes any state divergence to the
   first differing value.

## Verification

- x86 self-test (real tap, real file I/O): `PAD DIFF: 0/120`, `DETERMINISM:
  0/120`, idle-skip OK, demo 784 bytes (== 64 + 120*6), record byte-identical
  across two independent record runs.
- x86 boot smoke reaches `link finish: logo` (harness compiled in, no
  regression).
- Android `libgk.so` built with the harness, installed on device eae4df44,
  `deploy_verify.sh` PASS (build == APK == device, built-after-source).
- Cross-backend: the device self-test produces the same `PAD DIFF: 0/120` and a
  per-logic-tick state dump bit-identical to x86's at matching logic ticks.

## Temp instrumentation

No temporary debug instrumentation was added and none was left behind — there is
no leftover scratch logging, tripwire, or debug dump in the tree to be removed.
The harness is permanent, inert host infrastructure: all record/replay/self-test
behavior is gated behind explicit flags / env vars / the `debug.opengoal.pad_replay`
property and is a strict no-op on a normal boot. The `.statedump.txt` files are run
artifacts under `.autoport/`, not source, and are removed/regenerated per run.
`.autoport/gold` is untouched.
