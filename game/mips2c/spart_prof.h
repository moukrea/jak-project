#pragma once

// Gperf-particles: lightweight counters for the particle pipeline, so the
// A35-PERF dump can attribute a fire-heavy frame between the GOAL-kernel-thread
// sparticle kernels (mips2c) and the render-thread sprite submission. Written
// by the kernel thread (sparticle kernels) and the render thread (Sprite3 /
// DirectRenderer); read+reset by the A35-PERF dump site every 60 frames.
// Diagnostic only — relaxed atomics, no behavior change.

#include <atomic>
#include <chrono>
#include <cstdint>

struct SpartProf {
  // GOAL-thread mips2c kernel wall time (ns), call counts, and per-particle
  // slot iterations (block_1 entries — includes invalid slots).
  std::atomic<uint64_t> ns_3d{0}, ns_2d{0}, ns_launch{0}, ns_adgif{0};
  std::atomic<uint64_t> calls_3d{0}, calls_2d{0}, calls_launch{0}, calls_adgif{0};
  std::atomic<uint64_t> iters_3d{0}, iters_2d{0};
  // render-thread sprite submission shape (per A35 window)
  std::atomic<uint64_t> sprite_buckets{0}, sprite_quads{0}, direct_flushes{0};
  // render-thread Sprite3 wall time (ns): per-quad build vs per-bucket flush
  std::atomic<uint64_t> gl_spr_build{0}, gl_spr_flush{0};
};

extern SpartProf g_spart_prof;

// RAII wall-clock accumulator (ns) into one SpartProf slot.
struct SpartScopedNs {
  std::atomic<uint64_t>& tgt;
  std::chrono::steady_clock::time_point t0;
  explicit SpartScopedNs(std::atomic<uint64_t>& t)
      : tgt(t), t0(std::chrono::steady_clock::now()) {}
  ~SpartScopedNs() {
    tgt.fetch_add(
        std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - t0)
            .count(),
        std::memory_order_relaxed);
  }
};
