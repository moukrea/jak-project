#pragma once
// ===========================================================================
// Per-source audio RMS meter for the Android AAudio output (phase Gaudio-sfx).
//
// The phase-F2 audio gate measured ONE whole-mix peak at the AAudio callback,
// which could not tell SFX/voice apart from music — so "only music plays, SFX
// & voice are silent" passed as "audio works" (a false green). This meter
// splits the 989snd synth output RMS by SOURCE so each can be verified to
// reach the mix independently:
//   tag 1 = STREAM (streamed VAG: music-stream AND spoken dialog/voice,
//                   permanent voices[0..7] fed from spu_memory)
//   tag 2 = SFX    (989snd SBlk sound-bank, BlockSoundVoice)
//   tag 3 = MUSIC  (989snd SBv2 MusicBank MIDI sequence, midi_handler voices)
//
// Off by default; enable with `setprop debug.opengoal.audio.rms 1` (Android)
// or env OPENGOAL_AUDIO_RMS=1 (desktop). When disabled, accumulate()/log() are
// a no-op so normal playback is unaffected.
// ===========================================================================
#include "common/common_types.h"

namespace snd {
namespace diag {

extern bool g_enabled;  // read once from the gate at sound-system start

void init();                                    // read the gate (idempotent)
void accumulate(int tag, s32 left, s32 right);  // per voice; no-op if disabled
void note_output_sample();                      // once per output sample
void log_if_due();                              // ~2x/sec RMS line when enabled

}  // namespace diag
}  // namespace snd
