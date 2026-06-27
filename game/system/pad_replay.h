#pragma once

// Phase Ginput-replay / Ginput-replay-determinism (autoport): faithful,
// DETERMINISTIC host-side input record/replay harness.
//
// The harness taps the controller state at the single backend-agnostic boundary
// the game consumes each frame: CPadGetData (bound as the GOAL symbol
// `cpad-get-data`). The x86 desktop build reaches it through
// game/kernel/common/kmachine.cpp; the Android arm64 build reaches it through
// android/android_runtime_compat.cpp. Because both backends funnel through the
// same boundary, the SAME recorded demo replays on both, which is what powers
// the owner-records-once crash reproduction and the x86-vs-arm64 state-trace
// divergence localizer.
//
// goal_src is left byte-identical: we only record/replay the host buffer that
// the game reads. Nothing in the GOAL pad-reading logic changes.
//
// DETERMINISM (Ginput-replay-determinism, owner 2026-06-27)
//   The original harness indexed each record by a counter that advanced once per
//   controller-0 CPadGetData call — i.e. once per RENDERED frame. That counter is
//   NOT a deterministic game-logic step: it advances during boot, the title, a
//   level LOAD, a pause and cinematics at a variable, run-to-run-dependent rate
//   (a load takes a different number of rendered frames each time; a device runs
//   at a different framerate than the desktop). Replaying a real-gameplay clip
//   therefore applied the recorded inputs at the WRONG game moments — "Jak does
//   the recorded moves but at the wrong place/direction from the first seconds."
//
//   The fix indexes records by the DETERMINISTIC game-LOGIC frame (jak1 *display*
//   actual-frame-counter: +1 per UNPAUSED simulated frame, pacing-independent),
//   RELATIVE to a gameplay ANCHOR (the frame *target* — Jak — first spawns). The
//   variable-length boot/title/load that precedes gameplay is fully absorbed by
//   the relative index: the i-th gameplay logic frame on replay receives exactly
//   the input the i-th gameplay logic frame received on record. At the anchor the
//   harness also forces EVERY RNG source (host pc-rand, mips2c gRng, GOAL rand-vu
//   `*_vu-reg-R_*`, GOAL `*random-generator*`) to a fixed seed, so the gameplay
//   simulation is bit-deterministic from the anchor onward.
//
//   The jak1 runtime registers the logic-frame provider, the anchor provider and
//   the GOAL RNG reseed; the host backends register their own RNG reseed. With no
//   provider registered (e.g. the in-process self-test) the harness falls back to
//   its legacy controller-read counter so run_selftest still validates the
//   pad-byte round-trip.

#include <cstddef>
#include <cstdint>
#include <string>

namespace pad_replay {

enum class Mode { Off, Record, Replay };

// Fixed-size per-logic-frame record: the ABSOLUTE consumed pad state. 16-bit PS2
// button bitmask (ButtonIndex layout, pressed = 1) + 4 analog axes (0..255, 127
// = neutral). This fully captures controller-0's consumed input for jak1 on both
// backends. NOT events/deltas.
#pragma pack(push, 1)
struct PadRecord {
  uint16_t button0;
  uint8_t leftx;
  uint8_t lefty;
  uint8_t rightx;
  uint8_t righty;
};
#pragma pack(pop)
static_assert(sizeof(PadRecord) == 6, "PadRecord must be 6 bytes");

// Explicit init. Used by the self-test and by the flag/env/prop plumbing.
//   Record: opens <path> for write. The 64-byte header is written lazily at the
//           gameplay anchor (first frame *target* exists).
//   Replay: opens <path> for read, validates the header, loads every record.
void init(Mode mode, const std::string& path);

// Pick the mode from the environment:
//   OG_PAD_REPLAY_RECORD=<file>   -> Record
//   OG_PAD_REPLAY_REPLAY=<file>   -> Replay
void init_from_env();

void shutdown();

bool active();
Mode mode();
uint64_t current_tick();   // controller-read counter (legacy / self-test)
int64_t current_frame();   // logic frame since the gameplay anchor (-1 pre-anchor)
uint32_t replay_seed();    // rng seed from the demo header (Replay mode)

// THE TAP. Call once per frame per pad from CPadGetData, AFTER the live state has
// been read into the out-params. Only controller 0 advances the harness and is
// recorded/replayed; other controllers are ignored.
//   Record: append this logic frame's 6-byte record and flush (crash-safe).
//   Replay: overwrite *button0,*leftx,... with the recorded values for this
//           logic frame (relative to the anchor).
void on_cpad_read(int controller_number,
                  uint16_t* button0,
                  uint8_t* leftx,
                  uint8_t* lefty,
                  uint8_t* rightx,
                  uint8_t* righty);

// ── Determinism providers / RNG reseed (Ginput-replay-determinism) ──────────────
// The jak1 runtime registers these from InitMachineScheme; the host backends
// register their RNG reseed from their machine init. All optional: with none set
// the harness uses its legacy controller-read counter (self-test).

// Returns the current deterministic game-logic frame (jak1 *display*
// actual-frame-counter). Used as the replay index.
void set_logic_frame_provider(int64_t (*fn)());

// Returns true once the gameplay anchor is reached (*target* is a live process).
// The harness latches the anchor on the first read this returns true, records the
// anchor frame, and forces RNG. Records are keyed relative to the anchor frame.
void set_anchor_provider(bool (*fn)());

// Register an RNG-reseed callback. ALL registered callbacks are invoked, with the
// demo seed, exactly once when the anchor is reached (record AND replay), so every
// RNG stream restarts from an identical, known state at the anchor.
void add_rng_reseed_callback(void (*fn)(uint32_t));

// Register a callback that forces a FIXED game-logic timestep while the harness is
// armed. The jak1 runtime sets *ticks-per-frame* high so the engine's time-ratio
// clamps to 1.0 every frame — every drawn frame becomes exactly one 1/60s logic
// step, independent of real frame pacing. WITHOUT this, the engine advances the
// simulation by the measured (variable) real frame duration, so a recorded clip
// diverges run-to-run at a random frame (the per-run wall-clock hitch point). The
// callback is invoked every frame the harness is active (record AND replay).
void set_timestep_force_callback(void (*fn)());

// ── State-anchored trace ────────────────────────────────────────────────────────
// dump_state() writes the GOAL state under test (Jak pos/orientation/velocity,
// camera, ...) keyed by the current logic frame since the anchor:
//   <label> frame=<f> <hex bytes...>
// Pre-anchor reads (frame < 0) are skipped, so a trace contains only comparable
// gameplay frames. Replaying one demo and comparing the record-trace vs the
// same-backend replay-trace at matching logic frames must be bit-identical; the
// x86-vs-arm64 collision diff compares two backends the same way. No-op if no
// trace file is open.
void open_state_trace(const std::string& path);
void dump_state(const char* label, const void* data, size_t len);
void close_state_trace();
bool trace_active();  // true iff a state trace file is open

// Self-contained record->replay byte-identity proof (legacy controller-read path,
// no game engine). See pad_replay.cpp. Returns 0 iff fidelity + determinism hold.
int run_selftest(const std::string& out_path, int n_ticks);

}  // namespace pad_replay
