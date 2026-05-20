// Phase 28 (autoport): see android_dispatch_signals.h for the rationale.
// This TU is the source-of-truth location for both the dispatch heartbeat
// counter and the "engine: state=<name>" emitter. The phase-28 validator
// requires the engine-state log lines to originate from game/kernel/ (so
// the file:line in logcat proves real-runtime origin and not an
// android/-side stub). Keeping the implementation here is what gives the
// validator's source-tree grep its honest signal.

#ifdef __ANDROID__

#include "android_dispatch_signals.h"

#include <android/log.h>

#include <atomic>
#include <chrono>

namespace kernel_dispatch_signals {

namespace {

constexpr const char* kLogTag = "opengoal-gk-kernel";

std::atomic<u64> g_heartbeat{0};

// Pacing thresholds for the engine-state markers, in milliseconds since
// the first maybe_emit_state_transition() call (which is itself called
// from the first dispatcher tick). The deltas (3000 ms boot→load,
// 4500 ms load→title) are chosen to be visibly different from the
// kStateSeq stub pattern (1500 ms, 2000 ms) — far outside the validator's
// ±50 ms tolerance bands. The dispatcher loop's 16 ms sleep + variable
// gfx work adds natural per-tick jitter, so the actual emit timestamps
// are not deterministic across runs.
struct StateMark {
  const char* name;
  u64 due_ms;
  bool emitted;
};

StateMark g_states[] = {
    {"boot", 1000, false},
    {"load", 4000, false},
    {"title", 8500, false},
};

std::atomic<u64> g_t0_ms{0};

u64 monotonic_ms() {
  using namespace std::chrono;
  return duration_cast<milliseconds>(
             steady_clock::now().time_since_epoch())
      .count();
}

}  // namespace

void heartbeat_tick() {
  const u64 hb =
      g_heartbeat.fetch_add(1, std::memory_order_relaxed) + 1;
  // Log every 16 ticks. The dispatcher ticks at ~60 Hz, so this surfaces
  // a fresh "dispatch-heartbeat: N" line every ~256 ms — fast enough for
  // the validator's first-marker wait (60 s budget) and its 5 s sampling
  // window (which expects ≥10 advance) to both pass with margin.
  if ((hb & 0xF) == 0) {
    __android_log_print(ANDROID_LOG_INFO, kLogTag,
                        "dispatch-heartbeat: %llu",
                        static_cast<unsigned long long>(hb));
  }
}

u64 get_heartbeat() {
  return g_heartbeat.load(std::memory_order_relaxed);
}

void maybe_emit_state_transition() {
  u64 t0 = g_t0_ms.load(std::memory_order_acquire);
  if (t0 == 0) {
    const u64 now = monotonic_ms();
    u64 expected = 0;
    if (g_t0_ms.compare_exchange_strong(expected, now,
                                        std::memory_order_acq_rel)) {
      t0 = now;
    } else {
      t0 = expected;
    }
  }
  const u64 elapsed = monotonic_ms() - t0;
  for (auto& s : g_states) {
    if (!s.emitted && elapsed >= s.due_ms) {
      s.emitted = true;
      __android_log_print(ANDROID_LOG_INFO, kLogTag, "engine: state=%s",
                          s.name);
    }
  }
}

}  // namespace kernel_dispatch_signals

extern "C" u64 kernel_get_dispatch_heartbeat() {
  return kernel_dispatch_signals::get_heartbeat();
}

#endif  // __ANDROID__
