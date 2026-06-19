# Phase Gvistruth — build a TRUSTWORTHY programmatic visual-quality gate vs the v0.3.3 original (so the owner never has to watch)

## Why this phase exists (read carefully — this is a correction of a real failure)
On 2026-06-19 the `Gmatch-original` gate reported PASS on three LIVENESS signals (no-crash, reaches-in-game, one halo number) while the SAME `report.json` measured **main-menu 57% and title-pressstart 75% pixel-divergence vs the matched-aspect v0.3.3 oracle** (both MISMATCH, ungated) and the halo metric read **0.0 at the ND logo while the owner clearly saw a halo**. The owner saw, instantly and correctly: halo on the ND logo AND title, garbled menu, cinematic animation/transition/graphical issues. **The framework MEASURED the defects and the gate threw the data away.** The owner has demanded this be fixed "hundreds of times": LIVENESS (boots, reaches in-game) is NOT QUALITY. See memory [[gate-visual-quality-not-liveness]], [[feedback-objective-frame-comparison]], [[device-ground-truth-no-mixing]].

## The deliverable: a detector the owner can TRUST instead of watching
A hardened `verify_device_graphics.sh` (+ helpers) that, for every comparable beat, compares the **current device build** to the **untouched v0.3.3 original** (`/home/emeric/code/jak-original-v033`, commit `c4bc4d3ff`) and produces an HONEST per-beat verdict that **matches what the owner sees**:
1. **Global oracle pixel-diff gate** on the STATIC beats (intro-logo / title-pressstart / main-menu): a beat MISMATCHing the matched-aspect oracle is a FAIL, full stop. The oracle frames are 2400×1080 (2.222) = the device aspect, so a large diff is REAL garble, not an aspect artifact. (Clean cross-renderer floor ≈ 2–5%, see [[project-pcompare-gate]] / [[feedback-pixel-gate-cross-renderer-floor]]; 57–75% is garbage.)
2. **A WORKING localized halo/bloom detector.** Halos are LOCAL bright blobs → low global diff but visible. The current metric is BROKEN (0.0 on a visible halo). Find why (wrong captured frame/moment? wrong oracle? threshold/region?) and fix it until it fires on the real ND-logo AND title halos. Validate against the owner's ground truth, not your eyes.
3. **Cinematic + in-game become MEASURED, not NO_ORACLE.** Capture v0.3.3 oracle reference frames for newgame-cinematic + ingame-firstframe (solve the `capture_oracle_beats.sh` TODO: the original's DECI2 listener doesn't bind on this host + START is remapped — fix that so the cutscene/in-game oracle beats can be captured). If a specific beat genuinely cannot be captured, say so EXPLICITLY in the report — never imply an unmeasured beat is "fine."
4. Make this the **STANDING graphics gate**: `verify_device_graphics.sh`'s `overall_verdict` (and any phase validator that calls it) must FAIL on any static-beat oracle MISMATCH or halo > threshold. Future phases inherit the strictness automatically.

## The anti-false-green requirement (this is what makes it trustworthy — NON-NEGOTIABLE)
A gate is only trustworthy once it provably **catches the defects the owner sees** AND does **not** false-FAIL a clean render. Your validator (below) will REQUIRE both, so a lenient gate cannot pass this phase:
- **Must FAIL on known-bad:** run the hardened gate on the CURRENT device build (the one the owner is looking at) — it MUST report FAIL with main-menu=MISMATCH (garble), intro-logo halo>threshold (halo), title-pressstart halo/MISMATCH (halo). Capture and save these as the calibration baseline (`.autoport/reports/graphics-verify/known-bad/`).
- **Must PASS on known-good:** run the gate oracle-vs-oracle (compare the v0.3.3 oracle frame to itself) → MATCH / no halo. No false-FAIL.
- Localize each defect with the diff image (`frame_compare.py --diff`) so the report shows WHERE it diverges (per [[feedback-objective-frame-comparison]]).

## Calibration discipline
- Verify oracle frames are matched-aspect to the device before trusting any diff ([[feedback-oracle-capture-aspect]]). They are 2400×1080/2.222 today — confirm still.
- Pick thresholds that cleanly separate the ~2–5% clean floor from the 57–75% garbage; document the chosen thresholds + the evidence in the fix-summary.
- The owner's live view is GROUND TRUTH. If your metric disagrees with "owner sees a halo / garbled menu", the metric is wrong — fix it.

## Locks / delivery
- ANDROID_SERIAL=eae4df44 only. adb `/home/emeric/Android/platform-tools/adb`. After any failing device run, `bash .autoport/restore_knowngood_device.sh`. Never leave the phone bricked.
- This phase is DETECTION + HONEST MEASUREMENT. It does NOT have to FIX the menu/halo/cinematic defects — those are the immediately-following gated fix phases. But it MUST produce the trustworthy gate + an honest current-state report that flags them.
- The crash counter must match `GK-DIAG sig=(4|6|11)` (the current `sig=11`-only grep misses SIGILL/SIGABRT — see [[gmatch-pass]]). Fix that here too.

## Validator (`phase-Gvistruth.sh`) PASS requires
1. Hardened `verify_device_graphics.sh` present with: static-beat oracle-diff gating wired into `overall_verdict`; a halo/bloom detector; crash regex `sig=(4|6|11)`.
2. `.autoport/reports/graphics-verify/known-bad/report.json` proving the gate FAILS on the current build: main-menu MISMATCH AND (intro-logo OR title-pressstart) halo>threshold. (Anti-false-green: the gate demonstrably catches the owner's defects.)
3. An oracle-vs-oracle self-test artifact proving the gate PASSES a clean render (no false-FAIL).
4. Cinematic + in-game oracle frames present under `.autoport/gold/oracle-beats/` (or an explicit documented impossibility per beat).
5. `Gvistruth-fix-summary.md` (≥60 lines): the metrics, the chosen thresholds + calibration evidence, why the old halo metric read 0.0, and the per-beat current-state honest verdict.
6. Real code change under `.autoport/lib/**` (and/or `game/**` if the halo capture-moment needed an instrumentation hook).

## Max settings
`max_turns: 1500`, `max_retries: 4`.
