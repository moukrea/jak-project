#pragma once

#include <array>
#include <atomic>
#include <cstdio>
#include <ctime>
#include <string>
#include <unistd.h>
#ifdef __ANDROID__
#include <dlfcn.h>
#include "android/android_gfx.h"
#endif

#include "common/util/FileUtil.h"
#include "game/graphics/refset.h"
#include "game/graphics/refset_file.h"
#include "game/system/autoport_proof.h"

// Instrument only. The schedule uses the logical tick carried by the DMA, never wall time
// or the number of rendered frames. Missing ticks and different inputs remain defects.
namespace ao_static_probe {
constexpr const char* kItem = "ao-static-probe-deterministic";
constexpr int kStates = 6;
constexpr int kSamples = kStates * 3;
constexpr int64_t kStart = 1200;
constexpr int64_t kStride = 30;
inline std::atomic<uint64_t> anchor_executions{0}, anchor_defects{0};
inline uint64_t pair_gap_defects = 0;

inline bool requested() {
  return autoport_proof::feature_is(kItem) || autoport_proof::feature_is("ao-prepass-tie-alpha");
}
inline bool active() { return requested() && autoport_proof::armed(); }
inline int64_t logic_frame() {
#ifdef __ANDROID__
  return android_gfx::logic_frame_of_input_data();
#else
  return refset::render_logic_frame();
#endif
}

struct Sample {
  int64_t tick = -1;
  uint64_t input = 0;
};

class Run {
 public:
  int phase = -1;
  int state = -1;
  uint64_t samples = 0;
  uint64_t differences = 0;
  bool compared = false;

  void begin(uint64_t render_frame) {
    phase = state = -1;
    if (!active()) return;
    if (!initialized) initialize();
    const int64_t lf = logic_frame();
    if (lf >= 0) autoport_proof::publish("ao_probe_last_logic_tick", lf);
    if (lf > kStart + (kStates - 1) * kStride + 3) {
      finish();
      return;
    }
    if (lf < kStart || lf == last_tick) return;
    last_tick = lf;
    const int64_t offset = lf - kStart;
    // Slot 3 checks the acquired alpha/direct-light properties with live wind.
    // It is outside the static-input sample population (slots 0, 1, 2).
    if (offset / kStride >= kStates || offset % kStride > 3) return;
    state = int(offset / kStride);
    phase = int(offset % kStride);
    if (phase == 2 && (previous_render + 1 != render_frame || previous_phase != 1)) {
      pair_gaps++;
      pair_gap_defects++;
    }
    previous_render = render_frame;
    previous_phase = phase;
  }

  void record(uint64_t input) {
    if (phase < 0 || phase > 2 || !input) return;
    const int index = state * 3 + phase;
    if (current[index].input) return;
    current[index] = {logic_frame(), input};
    samples++;
    autoport_proof::note_hit_for(kItem);
    const std::string suffix = std::to_string(index);
    autoport_proof::publish(("ao_probe_tick_" + suffix).c_str(), current[index].tick);
    autoport_proof::publish(("ao_probe_input_" + suffix).c_str(), input);
    autoport_proof::publish("ao_probe_samples", samples);
    if (samples == kSamples) finish();
  }

 private:
  std::array<Sample, kSamples> current{}, previous{};
  bool initialized = false, finished = false, baseline = false;
  int64_t last_tick = -1;
  uint64_t previous_render = 0, pair_gaps = 0, binary = 0;
  int previous_phase = -1;
  std::string path;

  void initialize() {
    initialized = true;
#ifdef __ANDROID__
    Dl_info info{};
    if (dladdr(reinterpret_cast<const void*>(&logic_frame), &info) && info.dli_fname) {
      binary = refset_file::hash_file(info.dli_fname);
    }
#elif defined(__linux__)
    binary = refset_file::hash_file("/proc/self/exe");
#endif
    path = (file_util::get_user_home_dir() / "ao-static-probe-pending.txt").string();
    autoport_proof::publish("ao_probe_binary", binary);
    autoport_proof::publish_text("ao_probe_baseline_path", path.c_str());
    autoport_proof::publish_text("ao_probe_anchor", "dma-logic-tick+exact-depth-and-camera-inputs");
    unsigned long long old_binary = 0, old_time = 0;
    FILE* f = std::fopen(path.c_str(), "r");
    if (f) {
      baseline = binary && std::fscanf(f, "AO_STATIC_V1 %llu %llu", &old_binary, &old_time) == 2 &&
                 old_binary == binary;
      for (auto& sample : previous) {
        long long tick = -1;
        unsigned long long input = 0;
        if (std::fscanf(f, "%lld %llu", &tick, &input) != 2 || !input) baseline = false;
        sample = {tick, input};
      }
      if (std::fclose(f) != 0) baseline = false;
      // A baseline can serve one comparison only, including an interrupted comparison.
      if (std::remove(path.c_str()) != 0) baseline = false;
    }
    autoport_proof::publish("ao_probe_baseline_time", baseline ? old_time : 0);
  }

  void finish() {
    if (finished) return;
    finished = true;
    differences = 0;
    for (int i = 0; i < kSamples; i++) {
      if (!current[i].input || current[i].tick != kStart + (i / 3) * kStride + i % 3) {
        differences++;
      } else if (baseline && (current[i].tick != previous[i].tick ||
                              current[i].input != previous[i].input)) {
        differences++;
      }
    }
    compared = baseline;
    bool saved = false;
    if (!baseline && binary && samples == kSamples) {
      const std::string tmp = path + "." + std::to_string(getpid());
      if (FILE* f = std::fopen(tmp.c_str(), "wx")) {
        bool ok = std::fprintf(f, "AO_STATIC_V1 %llu %llu\n", (unsigned long long)binary,
                               (unsigned long long)std::time(nullptr)) > 0;
        for (const auto& sample : current) {
          if (std::fprintf(f, "%lld %llu\n", (long long)sample.tick,
                           (unsigned long long)sample.input) < 0) ok = false;
        }
        if (std::fclose(f) != 0) ok = false;
        saved = ok && std::rename(tmp.c_str(), path.c_str()) == 0;
        if (!saved) std::remove(tmp.c_str());
      }
    }
    autoport_proof::publish("ao_probe_baseline_saved", saved);
    autoport_proof::publish("ao_probe_pair_gap_defects", pair_gaps);
    autoport_proof::publish("ao_probe_expected_samples", kSamples);
    autoport_proof::publish("ao_probe_compared", compared);
    autoport_proof::publish("ao_probe_samples", samples);
    if (compared) autoport_proof::publish("ao_probe_nondeterminism", differences);
    else autoport_proof::publish_text("ao_probe_nondeterminism", "non-mesure");
  }
};
}  // namespace ao_static_probe
