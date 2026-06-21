# Phase Gd1-cutscene-clock — make cinematics play at REAL-TIME (decouple the cutscene/spool clock from the render vsync)

## The defect (Grender-audit D1, deterministically measured — `.autoport/reports/Grender-audit/divergences.md`)
The game-logic clock is fine on arm64 (real-time; time-ratio catch-up works). The owner's "fluid but 2× time" is the **cutscene running in slow-motion** because its timeline is paced by the **IOP/overlord VBlank fired once per render-vsync**, not by wall-clock. On the Adreno 618 the cutscene renders at ~16 fps, so the spool/str-pos clock ticks ~16 Hz instead of 60 Hz → the cinematic plays at ~0.27× real-time (≈3.7× slow-motion) but stays fluid (camera/joints interpolate). x86 holds 60 fps so it plays 1×. This is ALSO the prime suspect for the deferred `Gcine-cut` "device glides where x86 cuts" — a hard cut smeared over a 0.27× timeline reads as a glide.

## Mechanism (from the audit)
`android/android_gfx.cpp` `vsync()` (~:562–569,618) fires the IOP/overlord vblank exactly **once per call (= once per rendered game-frame)** via `fire_iop_vblank`. That handler advances the spooled-audio / fake-VAG str-pos that paces every cutscene. Because it's per-vsync (render-cadence) not wall-clock, it slows whenever render fps drops.

## Mandate
1. **CONFIRM first (deterministic).** Reach the new-game cinematic on device and dump the **str-pos / IOP-vblank advance rate vs wall-clock** (and vs the A35-RENDER fps). Show it ticks at the render fps (~16 Hz) not 60 Hz. (The audit measured the title beat; this confirms the cutscene specifically.)
2. **Fix: pace the IOP/overlord VBlank on a wall-clock 60 Hz schedule**, decoupled from the render-swap cadence — so the cutscene spool clock advances at real-time even when the render rate drops (catch up / fire the vblank the correct number of times per wall-clock 16.67 ms, capped sanely). Do NOT break the normal per-frame game-chain pacing or audio sync; keep gameplay timing correct. x86/`#else` path unchanged (this is Android-runtime only — likely no goal_src change, an `android/` change).
3. **x86-first sanity:** x86 already plays cinematics at 1× (60 fps) — your change must be Android-runtime-gated and leave x86 byte-identical.

## Verify (deterministic, NOT screenshots)
- After the fix, re-dump the cutscene str-pos / IOP-vblank rate on device: it must advance at **~60 Hz wall-clock** (within tolerance) regardless of the ~16 fps render rate → the cinematic timeline now plays at ~1× real-time (the cinematic reaches a given str-pos / scene-beat in ~1× the wall-clock time, not 3.7×).
- Regression: device still boots + reaches gameplay; no new sig 4/6/11; audio not desynced; gameplay (non-cutscene) timing unchanged.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. Original repo READ-ONLY/pristine; remove temp dumps. `deploy_verify.sh eae4df44` PASS. After any failing run, `bash .autoport/restore_knowngood_device.sh`. Device may need the owner to keep the phone unlocked for captures.

## Validator (`phase-Gd1-cutscene-clock.sh`) PASS requires
1. `.autoport/reports/Gd1-cutscene-clock/clock-rate.txt`: BEFORE/AFTER cutscene str-pos (or IOP-vblank) advance rate vs wall-clock on device — BEFORE ≈ render fps (~16 Hz), AFTER ≈ 60 Hz wall-clock — with `RESULT: CUTSCENE CLOCK REAL-TIME`.
2. A real code change under `android/**` (or `game/**` if needed); x86 `#else`/desktop path unchanged (x86 still `link finish: logo`); fix-summary ≥60 lines naming the mechanism + the fix; temp dumps removed; golden pristine.
3. `deploy_verify.sh eae4df44` PASS; device reaches gameplay, no new sig 4/6/11.

## Max settings
`max_turns: 1500`, `max_retries: 3`.
