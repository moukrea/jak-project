// Copyright: 2021 - 2024, Ziemas
// SPDX-License-Identifier: ISC
#include "synth.h"

#include <cstdio>
#include <cstdlib>
#include <stdexcept>

#include "game/sound/989snd/audiodiag.h"

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace snd {

// ===== Per-source AAudio output RMS meter (see audiodiag.h) ==============
namespace diag {
bool g_enabled = false;
static u64 g_sumabs[4] = {0, 0, 0, 0};
static s32 g_peak[4] = {0, 0, 0, 0};
static u64 g_samples = 0;

void init() {
#ifdef __ANDROID__
  char prop[92] = {0};
  g_enabled = __system_property_get("debug.opengoal.audio.rms", prop) > 0 && prop[0] == '1';
#else
  const char* e = std::getenv("OPENGOAL_AUDIO_RMS");
  g_enabled = e && e[0] == '1';
#endif
}

void accumulate(int tag, s32 left, s32 right) {
  if (!g_enabled) {
    return;
  }
  if (tag < 0 || tag > 3) {
    tag = 0;
  }
  s32 al = left < 0 ? -left : left;
  s32 ar = right < 0 ? -right : right;
  g_sumabs[tag] += (u64)al + (u64)ar;
  s32 pk = al > ar ? al : ar;
  if (pk > g_peak[tag]) {
    g_peak[tag] = pk;
  }
}

void note_output_sample() {  // called once per output sample (Synth::Tick)
  if (g_enabled) {
    g_samples += 1;
  }
}

void log_if_due() {
  if (!g_enabled || g_samples < 24000) {  // ~0.5s of output @ 48 kHz
    return;
  }
  // avg = mean |L|+|R| contributed by that source per output sample.
  u64 n = g_samples ? g_samples : 1;
  std::printf(
      "AUDIODIAG rms avg|peak  stream=%llu|%d  sfx=%llu|%d  music=%llu|%d  "
      "unknown=%llu|%d  (n=%llu)\n",
      (unsigned long long)(g_sumabs[1] / n), g_peak[1],
      (unsigned long long)(g_sumabs[2] / n), g_peak[2],
      (unsigned long long)(g_sumabs[3] / n), g_peak[3],
      (unsigned long long)(g_sumabs[0] / n), g_peak[0],
      (unsigned long long)g_samples);
  std::fflush(stdout);
  for (int i = 0; i < 4; i++) {
    g_sumabs[i] = 0;
    g_peak[i] = 0;
  }
  g_samples = 0;
}
}  // namespace diag
// ========================================================================

static s16 ApplyVolume(s16 sample, s32 volume) {
  return (sample * volume) >> 15;
}

s16Output Synth::Tick() {
  s16Output out{};

  mVoices.remove_if([](std::shared_ptr<Voice>& v) { return v->Dead(); });
  for (auto& v : mVoices) {
    s16Output vo = v->Run();
    out += vo;
    diag::accumulate(v->mSourceTag, vo.left, vo.right);
  }
  diag::note_output_sample();

  out.left = ApplyVolume(out.left, mVolume.left.Get());
  out.right = ApplyVolume(out.right, mVolume.right.Get());

  mVolume.Run();

  return out;
}

void Synth::AddVoice(std::shared_ptr<Voice> voice) {
  mVoices.emplace_front(voice);
}

void Synth::SetMasterVol(u32 volume) {
  mVolume.left.Set(volume);
  mVolume.right.Set(volume);
}
}  // namespace snd
