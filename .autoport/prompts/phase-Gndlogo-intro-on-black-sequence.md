# Phase Gndlogo — the Naughty Dog logo beat must PIXEL-MATCH the original (on black), gated objectively. TOP PRIORITY.

## Why (owner directive)
The Naughty Dog intro beat — **Daxter on the ground + Jak pushing the "NAUGHTY [paw] DOG" logo, on a BLACK background, BEFORE the title** — is "completely messed up" on the Android device: it renders OVER the village instead of on black. This is the owner's #1 chronological priority and they believe fixing it propagates to other issues. The supervisor twice over-claimed this fixed from eyeballing — so this phase is gated OBJECTIVELY by `frame_compare` against the ORIGINAL build's golden, NOT by anyone's eyes.

## The golden (the reference the device must match)
`.autoport/gold/pristine-frames/intro-ndlogo-full-f000630.png` (and `intro-ndlogo-enter-f000400.png`) — captured from the pristine upstream build (`/home/emeric/code/jak-original-v033` @ `c4bc4d3ff`) by phase Pcompare. The "full" golden shows the NAUGHTY DOG logo + Jak pushing it (right) + Daxter (lying, center-left) on clean black. The device at the same beat must look like this.

## TWO fairness fixes the gate needs FIRST (do these before judging the device)
1. **Same aspect/resolution.** The existing goldens are 1280x720 (16:9); the phone is 2400x1080 (20:9). Re-capture the two ndlogo goldens AT 2400x1080 from the oracle (reuse the Pcompare approach: temporary env-gated auto-screenshot hook in the oracle `game/graphics/pipelines/opengl.cpp` at the same `frame_idx` anchors 400 & 630, run gk with a 2400x1080 window — `XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.RKSTQ3 DISPLAY=:0`, software Mesa fallback — dump, then `git -C /home/emeric/code/jak-original-v033 checkout -- .` to restore pristine). Save as `.autoport/gold/pristine-frames-2400/intro-ndlogo-{enter,full}.png`.
2. **Exclude the on-screen touch overlay.** The phone composites a D-pad (bottom-left), face buttons (bottom-right), START (bottom-center) that the desktop golden lacks — they must NOT count as differences. Add a mask/crop option to `.autoport/lib/frame_compare.py` (e.g. `--ignore-rect x,y,w,h` repeatable, or `--crop` to a region) and exclude the overlay bands; OR disable the touch overlay for the capture if the build supports it. The ND logo/Jak/Daxter are in the upper-center, clear of the bottom overlay, so masking the bottom band is sufficient. Document the mask.

## Mandate — in order
1. Do the two fairness fixes above (2400x1080 goldens + overlay-masked compare). Re-self-test the masked compare (identical→MATCH, golden-vs-black→MISMATCH).
2. Capture the device at the ndlogo beats anchored to the EVENT (the ND-logo state, via `.autoport/lib/capture_device_beat.sh` + the phase's own trigger — NOT a raw frame number; the phone's slow loader desyncs frame counts). ANDROID_SERIAL=eae4df44 ONLY; verify `mCurrentFocus=org.opengoal.gk.jak1`. Save to `.autoport/reports/Gndlogo/device-ndlogo-{enter,full}.png`.
3. `frame_compare` device-vs-golden@2400 (masked). If MISMATCH, diagnose the mechanism. Strong prior: `dd3ee36ad` made the village `display-self` UNCONDITIONAL in the `ndi` `:trans`, so the village displays DURING the ND logo. Fix so village1 is PRELOADED but NOT displayed until `ndi` deactivates (satisfy both: no village-black deadlock from `0445f78da`, no village-behind-logo). `goal_src/jak1/levels/title/title-obs.gc` is editable; oracle-diff the `ndi` state machine arm64-vs-x86 (`build-x86/game/gk`) to confirm the timing divergence. Rebuild TIT.DGO with BOTH arm64 + x86 goalc and sync the affected DGO(s) to the APK assets.
4. Re-capture device + `frame_compare` until both ndlogo beats MATCH (within tolerance, overlay masked). Confirm no regression: title still flies + village still renders later (shrub/TIE detail), intro on black, no crash.

## Rules / locks
- ANDROID_SERIAL=eae4df44 only. Do NOT edit `goalc/emitter/IGenX86_64.*` (LOCKED). Do NOT rebuild CGOs via `(mi)`. Leave `/home/emeric/code/jak-original-v033` pristine (revert the temp hook). `.autoport/gold/` existing core read-only (you may ADD `pristine-frames-2400/`).
- No painted/faked intro, no hardcoded frame. The fix must be a real `ndi` timing/state change proven by the device-vs-golden MATCH + the oracle-diff.

## Validator (`phase-Gndlogo-intro-on-black-sequence.sh`)
PASS requires (OBJECTIVE — the validator runs `frame_compare` itself): `.autoport/gold/pristine-frames-2400/intro-ndlogo-{enter,full}.png` exist (2400x1080); the masked-compare self-test passes; `frame_compare` (masked) of `.autoport/reports/Gndlogo/device-ndlogo-full.png` vs the 2400 golden → **MATCH (exit 0)**, and same for `enter`; forbidden-edit gate (IGenX86_64 untouched, no `(mi)` marker); x86 still reaches `link finish: logo`; on device: no sig=11, frame≥300, focus held, and a late frame ≥200k tris (village renders, not the black-deadlock floor); oracle repo pristine; a `Gndlogo-fix-summary.md` (≥80 lines) with the oracle-diff + the masked device-vs-golden diff_frac numbers + before/after.

## Max settings
`max_turns: 1500`, `max_retries: 3`.

## Strategic note
The gate must be FAIR before it judges (same aspect, overlay excluded). Then the pass criterion is purely objective: the device ND-logo beat pixel-matches the original on black. No eyeballing.
