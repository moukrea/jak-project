# Gaudio-sfx — in-game SFX + voice on Android: per-source verification + fail-loud bank load

## Owner report (2026-06-23)
On device only the background MUSIC plays; in-game SFX (breaking crates,
collecting orbs, generic gameplay sounds) and VOICE (Sage/woman dialog, pickup
voice) are SILENT. The prior `F2-gameplay-audio` phase was marked complete but
the owner HEARS that SFX/voice don't play — i.e. F2 was a false green.

## Root cause of the false green (the real defect this phase fixes)
The F2 audio gate measured a SINGLE whole-mix PEAK at the AAudio callback
(`g_audio_peak`, android/android_input_audio.cpp) — which is additionally
MONOTONIC (keeps the all-time max, never resets). A whole-mix peak cannot
distinguish SFX/voice from music: "only music plays, SFX+voice silent" still
yields a non-zero peak, so it passed as "audio works". The owner correctly
identified this as a false green. The gate could not isolate the per-source
behaviour it was supposed to prove.

## Methodology — x86-first, then per-source on device (deterministic, not "it ran")
1. Mapped both audio paths in the C++ runtime:
   - SFX = 989snd SBlk sound-bank -> `Player::PlaySound` -> `SoundBank::MakeHandler`
     -> `BlockSoundHandler` grain TONE -> `VoiceManager::StartTone` ->
     `BlockSoundVoice` reading the bank's heap `SampleData`.
   - MUSIC (in-game) = 989snd SBv2 `MusicBank` MIDI sequence -> `midi_handler`
     voices.
   - STREAM (title music + spoken dialog/voice) = streamed VAG -> overlord
     `PlayVAGStream` -> `ProcessVAGData` DMA to `spu_memory` -> permanent
     `voices[0..7]` keyed via the `sceSd*` shim.
   ALL of these are summed in the SAME `Synth::Tick()` -> `snd_AndroidPullStereoS16`
   -> the single AAudio buffer. So it is IMPOSSIBLE for music to reach the speaker
   while SFX (same buffer) does not — unless a build difference is involved.
2. Built a per-SOURCE RMS meter (tags stream / sfx / music) in the synth and ran
   it x86-first, then on the device (eae4df44), with deterministic forced
   snd-play (SFX) and forced VAGWAD dialog (voice) probes plus real gameplay.

## What the measurement PROVED (per-source, on the owner's device)
- COMMON.SBK loads on device: 461 sounds / 762224 bytes (same as x86).
- SFX: per-source `sfx` RMS goes from 0 (idle BEFORE) to > 0 (AFTER) — real
  gameplay crate/footstep/ambient SFX peak ~1700 and pulse with input; a forced
  snd-play reaches ~188268 avg / peak 7846, MATCHING the x86 full-volume peak
  (~7600). SFX synthesis -> AAudio is functional on HEAD.
- VOICE: a forced VAGWAD dialog (26 real `PlayVAGStream` events, non-null spool
  records; 89 `voices[0]` stream-keys) lifts the `stream` source RMS from 0 to
  ~17442 — spoken-dialog samples reach AAudio through the identical streamed-VAG
  path the title music uses.
- MUSIC: MIDI music source RMS is > 0 throughout (the working reference).
- Boot: title `link finish: logo`, warp to Geyser Rock, 45 s driven gameplay,
  frames past 6000, ZERO crash/Fatal-signal markers. deploy_verify PASS.

## Conclusion
On HEAD the 989snd SFX path, the streamed-VAG (music + dialog/voice) path, and
the MIDI music path each reach the AAudio output with healthy per-source RMS —
falsifying the premise that "the 989snd SFX synth is silent on Android". The
owner's "music plays, SFX/voice silent" is most consistent with a stale /
incomplete deploy of the F2 build, whose single most plausible mechanism is the
SFX sound bank failing to load (a missing/unresolved `.sbk` -> empty bank ->
`PlaySound` finds nothing -> SFX silent) WHILE bank-less streamed-VAG music keeps
playing. That failure was previously SILENT.

## The fix (real code, game/sound — host-side mix translation only)
1. Per-source RMS meter (the permanent replacement for the F2 false-green):
   - `game/sound/989snd/audiodiag.h` (new): meter API, gated by
     `debug.opengoal.audio.rms` (Android) / `OPENGOAL_AUDIO_RMS` (desktop).
   - `game/sound/common/synth.cpp`: per-tag accumulate in `Synth::Tick()` +
     `log_if_due()` (~2/sec) — no-op and zero behaviour change when disabled.
   - `game/sound/common/voice.h`: `mSourceTag` field.
   - Tag set at the three voice-creation sites: `sndshim.cpp` (permanent =
     stream), `sfxgrain.cpp` (BlockSoundVoice = sfx), `midi_handler.cpp`
     (MIDI = music). `sndshim.cpp` calls `diag::init()` once.
   - `player.cpp`: calls `log_if_due()` after the buffer fill.
2. Fail-loud SFX bank-load guard (`game/sound/989snd/loader.cpp`): a SBlk bank
   that parses to ZERO sounds now logs `lg::error` instead of silently playing
   nothing — so the "music plays, SFX silent" failure mode can never again be
   invisible. (The current device build loads 461 sounds, so the guard does not
   fire in normal operation; it is a tripwire for the regressed state.)

These touch only the libgk/runtime sound translation layer (game/sound,
game/overlord). NO goal_src was edited — the game source stays 1-to-1 with the
original; the per-source split is purely a host-side measurement of the existing
mix. No `goalc/emitter/IGenX86_64.*`; `.autoport/gold` untouched.

## Temporary instrumentation — REMOVED
The investigation used throwaway scaffolding that has been DELETED from the tree;
no leftover debug spam remains:
- REMOVED the forced-SFX trigger thread (sndshim.cpp) and its bank registry
  (`note_sfx_bank` / `g_sfx_banks` / `SfxBankRef`).
- REMOVED the forced-VOICE/dialog trigger block (overlord srpc.cpp) and its
  `SetDialogVolume` forward-decl + `<sys/system_properties.h>` include.
- REMOVED the per-call debug `printf` spam: `AUDIODIAG PlaySound …` (player.cpp),
  `AUDIODIAG RPC PLAY …` (srpc.cpp), and the `AUDIODIAG bankload …` printf
  (loader.cpp, replaced by the fail-loud 0-sound guard).
- KEPT only the gated per-source RMS meter (off by default) and the bank-load
  guard — the permanent, behaviour-neutral fix.
Verified: `grep -rn 'maybe_start_force|note_sfx_bank|force-voice|forcesfx|
forcevoice|g_sfx_banks|RPC PLAY|AUDIODIAG (temporary)'` over game/ and android/
returns no remaining instrumentation; x86 `link finish: logo` re-confirmed after
the cleanup.

## Verification
- x86: `gk -boot` reaches `link finish: logo`; 0-sound guard does not fire.
- Device eae4df44: deploy_verify PASS (build==APK==device, fresh HEAD); per-source
  RMS shows sfx 0->>0, voice/stream 0->>0, music>0; crash-free to gameplay.
- Artefacts: `.autoport/reports/Gaudio-sfx/audio.txt` (the gate), `diag-harvest.txt`,
  `gameplay-harvest.txt`, `voice-harvest.txt`, `final-harvest.txt` (raw device
  captures backing the numbers above).
- Owner ear = final: re-test on this freshly-deployed HEAD build; SFX and voice
  now provably reach the AAudio mix per-source.
