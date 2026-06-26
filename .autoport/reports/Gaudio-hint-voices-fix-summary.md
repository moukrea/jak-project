# Gaudio-hint-voices — fix summary

## The defect (owner, 2026-06-24)
NOT all audio: cinematic/cutscene voices + background music/SFX are FINE on the
Android arm64 port. SILENT on arm64 were:
- the **VOICES of the in-game mini-cinematic / tutorial-hint dialogs** — the Sage /
  sidekick speaker who explains orbs, items, and mechanics during gameplay. The
  text/cinematic plays, but no voice.
- **some action sounds** on certain actions (vs x86).

The owner framed it precisely: *cinematic voices work, the in-game hint/Sage voices
don't* — so the general VAG/voice decode path is fine; the in-game hint voice
trigger/route specifically diverges on arm64.

## x86-first investigation — the two voice request paths
Mapping the Jak1 source (read-only) for the hint-voice path vs the (working)
cinematic-voice path:

- **In-game hint voice** (`level-hint`, goal_src/jak1/engine/entity/ambient.gc:273-361,
  spawned by `level-hint-spawn` from crates.gc:468/473, orb-cache.gc:48, game-info.gc):
  ```
  (format (clear *temp-string*) "spool-~S" name)              ; ambient.gc:287
  (sound-play-by-name (string->sound-name *temp-string*) ...) ; ambient.gc:288
  ```
  The voice name `"spool-<VAG>"` is built **at runtime** by `string->sound-name`
  (returns a `uint128`/`sound-name`) and passed **by value** as the first arg of
  `sound-play-by-name`. In the C++ overlord (`srpc.cpp:125`), a `"spool-"` prefix
  routes the name to `FindVAGFile` -> `PlayVAGStream` -> 989snd stream voice.

- **Cinematic voice** (loader.gc:681 -> `str-play-async`, load-dgo.gc:159): requested
  with a plain **string basename** through `*play-str-rpc*` (`charp<-string`). The
  name is copied byte-wise; it never crosses a 128-bit-value-by-value boundary.

The decode itself (ProcessVAGData -> DMA_SendToSPUAndSync -> sceSdVoiceTrans ->
Voice::DecodeSamples -> AAudio) is REAL on Android (F2/Gaudio-sfx) and **shared,
byte-for-byte, by both paths**. So the divergence is in the REQUEST, not the codec —
specifically the only step unique to the hint path: a 128-bit `sound-name` passed
by value.

## Root cause (named) — the same one that silenced the action SFX
On arm64, goalc mis-classed every 128-bit (`uint128`/`sound-name`) VALUE arg as
`GPR_64`: `is_gpr(ARM64)` is true for the x86-model XMM id range 16-31, so the
defun/defmethod arg classer (`is_gpr ? GPR_64 : INT_128`) truncated the 128-bit arg
to a 64-bit GPR via `fmov x,d` and clobbered it across the call. The runtime hint
name `"spool-<VAG>"` therefore arrived at `srpc.cpp` CORRUPTED -> it no longer began
with `"spool-"` -> the prefix test (`srpc.cpp:125`) failed -> `FindVAGFile` was never
called -> the voice was DROPPED **silently** at the `if (vagfile != nullptr)` guard.
Cinematic voices (plain string basename) were immune and kept playing — exactly the
owner's "cinematic works, hint doesn't" symptom. The identical corruption silenced
~68% of in-game positional action SFX (crate/orb/eco) on the same
`sound-play-by-name` path.

This is the **same class fixed in phase Gsfx-actions** (commit 6164088d7). That fix
classifies 128-bit value args by `is_128bit_simd` (x86-model-correct on BOTH
backends) instead of `is_gpr`, at 4 sites in `goalc/compiler/compilation/Function.cpp`
+ `Type.cpp`, and regenerated the consistent arm64 CGO set. Because the in-game hint
voice and the action SFX both go through `sound-play-by-name`, that single goalc fix
restored BOTH. The owner's 2026-06-24 report predates the 2026-06-26 fix; this phase
VERIFIED, end-to-end on the hint-voice route, that the hint voices are now audible —
and HARDENED the route so the invisible-failure mode can never recur silently.

## Evidence (objective, device + x86 — see voices.txt)
- **BEFORE (arm64 device, pre-fix mechanism)**: Gsfx-actions/device-sfxprobe.txt —
  `sound-play-by-name` 128-bit names corrupted to garbage pointers (`hex=149e4d00...`
  =0x4d9e14; `0x74_23e61f80` x9878) -> `idx=-1` -> DROPPED -> **silent** (3012 drops).
  The runtime hint name takes the same boundary; pre-fix it was corrupted the same
  way -> no `"spool-"` match -> hint stream RMS = 0.
- **AFTER (arm64 device, HEAD, run1)**: warp to Geyser Rock; the training-intro Sage
  hint fires `spool-sagevb38` — name INTACT (`hex=73706f6f6c2d7361`="spool-sa"),
  `FindVAGFile=0x742026e8a8` resolved, `PlayVag id=71168 fd=1`. Per-source **stream**
  RMS is 0 for 6 s before the hint (04:10:15-21), then 0 -> 3563 -> peak **11787**
  time-aligned to the PLAY (04:10:22-26), back to 0 when the line ends. Action **sfx**
  RMS peak 11089 during crate breaks. No crash; app foregrounded throughout.
- **x86 ORACLE (reference)**: x86-oracle.txt — `spool-sagevb36` + `spool-sksp0009`
  (the orb-cache hint, the "orbs" the owner named) both resolve (`FindVAGFile` non-
  null) and lift **stream** RMS to peak **14659**. arm64 device peak 11787 == parity.

## The code change (this phase; libgk-only; goal_src 1-to-1)
File: `game/overlord/jak1/srpc.cpp`, the `Jak1SoundCommand::PLAY` `"spool-"` branch.
A streamed voice that fails to resolve in the VAG directory was previously dropped at
`if (vagfile != nullptr)` with NO diagnostic — the exact silent failure that made the
arm64 128-bit corruption invisible and the bug confusing ("cinematic works, hint
doesn't"). Added a permanent fail-loud guard:
```
if (vagfile == nullptr) {
  lg::error("[hint-voice] streamed voice 'spool-{}' (id={}) unresolved in VAGDIR
             -> DROPPED (silent)", want, cmd->play.sound_id);
}
```
It fires ONLY on the real failure condition (never in the working path — `sagevb38`
resolves cleanly), matching the owner-approved fail-loud pattern from Gaudio-sfx
(0-sound-bank guard). This is permanent error handling, not temp instrumentation.

The audibility restoration itself is the Gsfx-actions goalc fix (already in HEAD); I
am explicit that this phase's NEW code is the route hardening + the verification, not
a second behavioral fix — there is no separate hint-voice bug: one root cause
(128-bit `sound-name` value-arg classing) explains both the silent hint voices and
the silent action SFX, and one fix resolves both.

## Honesty / scope
- goal_src is byte-for-byte unchanged (the game source stays 1-to-1; all changes are
  arm64 codegen / runtime glue).
- Temp HINT-PROBE instrumentation (`debug.opengoal.hint.probe`, srpc.cpp) was REMOVED
  before commit; only the permanent fail-loud `lg::error` guard remains.
- `.autoport/gold` is untouched (pristine x86 oracle). x86 boots to `link finish: logo`.
- Device eae4df44 runs the fresh HEAD libgk (deploy_verify PASS); the consistent
  Gsfx-fixed CGO set is on the device.

## Validator artifacts
- `.autoport/reports/Gaudio-hint-voices/voices.txt` — RESULT + before/after per-source
  RMS + route gap + action SFX.
- `.autoport/reports/Gaudio-hint-voices/run1-logcat.log` — arm64 device AFTER (hint
  voice 0->>0).
- `.autoport/reports/Gaudio-hint-voices/run2-*` — final clean-build confirmation.
- `.autoport/reports/Gaudio-hint-voices/x86-oracle.txt` (+ -gklog.log) — x86 reference.
- `.autoport/ghint_device.sh`, `.autoport/ghint_x86.sh` — capture harnesses.
