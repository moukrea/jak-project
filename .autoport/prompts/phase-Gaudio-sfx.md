# Phase Gaudio-sfx — in-game SFX + voice are silent on Android (only music plays) — wire the sound-bank/989snd path to AAudio

## The defect (owner, 2026-06-23) — F2-audio "passed" but is a FALSE GREEN
On device: **only the background MUSIC plays.** Silent: **SFX** (breaking crates, collecting orbs,
generic gameplay sounds) and **VOICE** (the Sage's dialog, the woman's dialog, pickup voice). The
prior `F2-gameplay-audio` phase was marked complete but the owner HEARS that SFX/voice don't play —
calibrate this phase to FAIL on that real defect, not on a "the function ran" proxy.

## The split (why music works but SFX/voice don't)
- **Music** = a **VAG STREAM** (`PlayVAGStream`/`QueueVAGStream`, `iso_api`) → already reaching
  AAudio (works).
- **SFX** = **sound BANK** samples synthesized by **989snd** (`game/overlord/common/sbank.cpp`,
  `ssound.cpp`, `game/sound/989snd` synth) → mixed to the output. THIS is silent.
- **Voice/dialog** = either VAG streams (a different stream slot than music) or bank samples — also
  silent. Determine which and why.
So the **sound-bank/989snd SFX synthesis → AAudio mix** path (and the voice path) is not producing
samples on Android, while the VAG-stream music path is.

## Methodology — x86-first, then find where Android SFX goes silent (deterministic, not "it played")
1. **x86-first:** confirm on desktop x86 that breaking a crate / collecting an orb / the sage dialog
   produce SFX + voice (they do — game logic is fine). Note the call chain
   (`sound-play`/`snd-play` GOAL → 989snd `snd_PlaySound`/`snd_PlayVagStream` → mixer → output).
2. **On Android, trace where it dies:** is the **sound bank LOADED** (`LoadSoundBank`)? does
   **989snd synthesize** the SFX voices (the PS2 SPU/synth emulation running + producing non-silent
   samples)? does the mixed SFX buffer reach **`android_input_audio.cpp`'s AAudio callback** (or is
   only the music stream mixed in)? Likely gaps: the 989snd synth/mixer not running or not summed
   into the AAudio output, the SFX bank not loaded/parsed on arm64, or a sample-format/IRQ/timer
   issue. Instrument the AAudio callback to measure per-source RMS: music source non-zero, SFX source
   zero → after the fix SFX source non-zero when a sound is triggered.
3. Fix the root so SFX + voice samples are synthesized and mixed to AAudio. libgk/runtime/overlord
   translation layer; goal_src 1-to-1; x86 unaffected.

## Validator (`phase-Gaudio-sfx.sh`) PASS requires
1. `.autoport/reports/Gaudio-sfx/audio.txt`: a deterministic measurement that, when a SFX is
   triggered on device (crate-break / orb-collect / a `snd-play`), the **AAudio output contains
   NON-SILENT SFX samples** (per-source or post-mix RMS rises from ~0), AND a **voice** line plays —
   a calibrated BEFORE (SFX/voice RMS ≈ 0 while music RMS > 0) → AFTER (SFX RMS > 0, voice RMS > 0).
   With `RESULT: SFX + VOICE AUDIBLE ON DEVICE (samples reach AAudio)`. Name the gap that was fixed.
2. Real `game/**`/`android/**`/`goalc/**` change; goal_src 1-to-1. Fix-summary
   `.autoport/reports/Gaudio-sfx-fix-summary.md` ≥60 lines; temp instrumentation removed.
3. x86 `link finish: logo`; device boots to gameplay crash-free; `deploy_verify.sh eae4df44` PASS.
4. The actual SOUND is owner-ear-final — calibrate the RMS gate to FAIL on the current silent build.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY. Keep device
awake. After any failing device run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind.

## Max settings
`max_turns: 1600`, `max_retries: 4`.
