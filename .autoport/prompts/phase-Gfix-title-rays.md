# Phase Gfix-title-rays — title-logo light rays LINGER after the smash (regression) — fix it for real

## The defect (owner, 2026-06-21, on the consolidated build)
On the title screen, the Jak&Daxter logo smashes the black background. **Blue light rays
(the expected volumetric light) are SUPPOSED to flash during the smash and then vanish — but
they now REMAIN over the logo for ~1-2 seconds after the smash.** The owner is explicit:
**"it didn't do that before"** → this is a REGRESSION introduced by recent title work
(`Ghalo` 39222b554 / `Gtitle-pixelmatch` 73c22d4c3, both in `title-obs.gc`).

Prime suspect: the **`logo-volumes`** process (the light-volume skelgroup, title-obs.gc:57-68)
is not being deactivated / its alpha not driven to 0 after the smash beat — but CONFIRM the
real element x86-first before fixing. (`logo-black` = the smashed background; `logo` = the logo
itself; `logo-volumes` = the light rays.)

## Methodology — DETERMINISTIC DUMPS, x86-FIRST, NEVER pixels (mandatory)
Owner standing rule ([[proxy-dumps-false-green]], [[state-dumps-x86-first-not-screenshots]]):
**no pixel/screenshot comparison** (I'm unreliable at it AND the title flyover is a moving
camera). Use deterministic STATE DUMPS of the data that reflects the defect, and compare
**our build vs the UNTOUCHED original** at `.autoport/gold/` FIRST.

1. **Find the element x86-first.** Identify exactly which process/joint/sparticle draws the
   post-smash light rays (start from `logo-volumes`, the `logo` main-joint, and any title-sequence
   sparticle/glow in the title-obs title/ndi states). Confirm by dumping on the **original x86**
   (`.autoport/gold`) build what that element's **alpha / active-state / lifetime** looks like
   across the frames spanning the smash → ~2s after.
2. **Calibrate (BEFORE).** On OUR build, dump the same element across the same beat:
   - **our-x86 vs original-x86 FIRST** — if ours keeps the rays alive/visible longer than the
     original on x86, the regression is in our `title-obs.gc` SOURCE change (fix it in source —
     correct on both backends).
   - then **device** — if the lingering only shows on device (our-x86 matches original), it's
     arm64-specific. Either way the BEFORE dump MUST show ours lingering vs the original vanishing
     (this is the calibration; if it doesn't reproduce, the dump is measuring the wrong element).
3. **Dump format:** per-frame `frame, logo-volumes-active?, ray-alpha (or fade), <element>-alive?`
   for ~60 frames around the smash, written to `.autoport/reports/Gfix-title-rays/rays.txt` for
   original-x86, our-x86, and device. Numbers, not images.

## Mandate
Fix the real cause so the light rays vanish on the SAME frame (±a small tolerance) as the
untouched original — on both our-x86 and the device. If it's a source regression in
`title-obs.gc`, fix the source (TIT.DGO is a level DGO: safe to rebuild+push —
[[game-cgo-rebuild-unsafe]]). Remove all temp dumps after; keep `.autoport/gold` byte-pristine.
x86 must still boot (`link finish: logo`).

## Validator (`phase-Gfix-title-rays.sh`) PASS requires
1. `.autoport/reports/Gfix-title-rays/rays.txt`: per-frame ray/volume alpha+active dumps for
   **original-x86, our-x86, AND device**, with a documented BEFORE proving ours lingered
   (rays active/alpha>0 for ~2s post-smash) while the original's went to 0 promptly — and an
   AFTER showing ours now matches the original's vanish frame (±tolerance). With
   `RESULT: TITLE RAYS VANISH MATCHING ORIGINAL`.
2. Real code change (`goal_src/**` or `game/**`/`android/**`); fix-summary
   `.autoport/reports/Gfix-title-rays-fix-summary.md` ≥60 lines naming the element + the
   mechanism + the fix; temp instrumentation removed; `.autoport/gold` git-clean.
3. x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASS (device runs fresh HEAD).

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY/pristine.
Device may need the owner unlocked. After any failing device run, `bash .autoport/restore_knowngood_device.sh`.
NO screenshot/video grind — dumps only.

## Max settings
`max_turns: 1500`, `max_retries: 4`.
