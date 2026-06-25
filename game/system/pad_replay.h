#pragma once

// Phase Ginput-replay (autoport): faithful, deterministic HOST-side input
// record/replay harness.
//
// The harness taps the controller state at the single backend-agnostic
// boundary the game consumes each logic frame: CPadGetData (bound as the GOAL
// symbol `cpad-get-data`). The x86 desktop build reaches it through
// game/kernel/common/kmachine.cpp; the Android arm64 build reaches it through
// android/android_runtime_compat.cpp. Because both backends funnel through the
// same boundary, the SAME recorded demo replays bit-identically on both, which
// is what powers the owner-records-once crash reproduction (Gportal-crash,
// Gcrash-mouche3) and the x86-vs-arm64 state-trace divergence localizer.
//
// goal_src is left byte-identical: we only record/replay the host buffer that
// the game reads. Nothing in the GOAL pad-reading logic changes.
//
// KEY DESIGN POINTS
//   * The record is the FULL ABSOLUTE pad state per logic tick (a 16-bit PS2
//     button bitmask + 4 analog axes), NOT events/deltas, so no edge can ever
//     be missed.
//   * Records are indexed by the framerate-INDEPENDENT logic tick (one record
//     per controller-0 CPadGetData call = one fixed-timestep game-logic step),
//     never by the variable render frame.
//   * Every record is flushed to disk the same tick it is produced, so a crash
//     loses nothing — the crash tick is always the last record in the file.
//   * Recording starts at frame 0 = the first NON-NEUTRAL pad state
//     (idle-until-first-input), and stamps a start-state fingerprint (rng seed,
//     kernel frame counter) so a replay is deterministic.

#include <cstddef>
#include <cstdint>
#include <string>

namespace pad_replay {

enum class Mode { Off, Record, Replay };

// Fixed-size per-logic-tick record: the ABSOLUTE consumed pad state. 16-bit PS2
// button bitmask (ButtonIndex layout, pressed = 1) + 4 analog axes (0..255, 127
// = neutral). This fully captures controller-0's consumed input for jak1 on
// both backends. NOT events/deltas.
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
//   Record: opens <path> for write. The 64-byte header (magic, version, rng
//           seed, start frame counter, reserved fingerprint) is written lazily
//           at frame 0 — the first non-neutral input (idle-until-first-input).
//   Replay: opens <path> for read, validates the header, loads every record,
//           and arms a one-shot rng reseed for deterministic replay.
void init(Mode mode, const std::string& path);

// Pick the mode from the environment:
//   OG_PAD_REPLAY_RECORD=<file>   -> Record
//   OG_PAD_REPLAY_REPLAY=<file>   -> Replay
// (no-op if neither is set). Lets the desktop runtime and the Android launcher
// arm the harness without a code change.
void init_from_env();

void shutdown();

bool active();
Mode mode();
uint64_t current_tick();  // framerate-independent logic-tick index
uint32_t replay_seed();   // rng seed loaded from the demo header (Replay mode)

// THE TAP. Call once per logic frame per pad from CPadGetData, AFTER the live
// state has been read into the out-params. Only controller 0 advances the logic
// tick and is recorded/replayed; other controllers are ignored (they are not
// the player and would desync the tick index).
//   Record: append this tick's 6-byte record and flush (crash-safe).
//   Replay: overwrite *button0,*leftx,... with the recorded values for this
//           logic tick.
void on_cpad_read(int controller_number,
                  uint16_t* button0,
                  uint8_t* leftx,
                  uint8_t* lefty,
                  uint8_t* rightx,
                  uint8_t* righty);

// Register a callback that reseeds the host RNG (extra_random_generator) for
// deterministic replays. Invoked exactly once, at the first replayed tick, with
// the seed from the demo header. Optional — if unset, replay still reproduces
// the input perfectly; the seed only matters for GOAL-side gameplay RNG.
void set_rng_seed_callback(void (*fn)(uint32_t));

// State-anchored trace. Crash phases and the x86-vs-arm64 diff call dump_state()
// with the GOAL state under test (Jak pos/vel/control-state, target/process
// state, the handful of globals). Each line is keyed by the current logic tick:
//   <label> tick=<t> <hex bytes...>
// Replaying one demo on x86 and on arm64 and comparing these dumps at matching
// logic ticks must be bit-identical; the first differing (tick,label) names the
// bug. No-op if no trace file is open.
void open_state_trace(const std::string& path);
void dump_state(const char* label, const void* data, size_t len);
void close_state_trace();

// Self-contained record->replay byte-identity proof. Drives N logic ticks of a
// scripted, varied input sequence through the REAL on_cpad_read() tap (record),
// then replays the written demo TWICE through the same tap, and checks the
// applied pad state is bit-identical to what was recorded at EVERY logic tick.
// Writes the demo to <out_path> and a per-logic-tick state dump to
// <out_path>.statedump.txt. Prints the PAD DIFF / determinism / first-divergence
// report. Returns 0 iff all-input fidelity AND determinism hold.
int run_selftest(const std::string& out_path, int n_ticks);

}  // namespace pad_replay
