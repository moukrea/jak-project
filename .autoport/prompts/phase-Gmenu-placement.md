# Phase Gmenu-placement — main-menu UI assets bunched toward center — fix placement (x86-first POSITIONS, no pixels)

## The defect (owner, 2026-06-21)
On the main menu the **UI textures/assets beneath the text are bunched toward the CENTER instead
of placed where they belong**. A prior phase (`Gmenu-ui-placement`) claimed PASS (tint-backdrop
scale=1.0 proxy) but the owner still sees bunching — a proxy false-green.

## CRITICAL: no pixel comparison (owner-stated, twice)
The menu is a **TRANSPARENT overlay over the island**, and the island is at a **different camera
position depending on when the menu opened** — so a pixel diff fails on the background even when
the UI is perfect ([[proxy-dumps-false-green]]). Dump the **computed on-screen X/Y position (and
scale) of each menu UI element** (the actual post-projection / post-`adjust-ratios` draw coords) —
that is the defect-relevant DATA. NEVER pixels, never my eyes.

## Re-baseline on fresh HEAD first
The sun/rays/particles defects were stale-libgk artifacts already fixed on HEAD ([[gsun-halo]],
[[gparticles-stars]]). The menu placement path (`progress.gc` adjust-ratios + 2D coord/scale,
some via mips2c) may be affected by the recent arm64 libgk fixes. **Deploy fresh HEAD and
re-measure before assuming a bug.**

## The decisive x86-first question (resolve it explicitly)
The device panel is **2400x1080 (~20:9 ultrawide)**. Dump each menu element's X/Y at 2400x1080 on:
**original-x86 (.autoport/gold)**, **our-x86 (HEAD)**, **device**.
- If **original-x86 at 2400x1080 places the elements correctly** but **device bunches them** →
  our arm64/translation regressed it (the adjust-ratios / 2D coord-scale math computes wrong on
  arm64, e.g. a mips2c #f-guard/float-compare misfire, OR the device aspect is fed wrong). Fix in
  the translation layer (`goalc/**`, `game/**`, `android/**` window-size glue) so device == original.
- If **original-x86 ALSO bunches at 2400x1080** (the original doesn't lay out UI for ultrawide) →
  this is an ultrawide-SUPPORT gap, a legitimate platform-required alteration. Feed the device's
  real aspect into the EXISTING aspect code via runtime glue; do NOT hardcode menu geometry in
  goal_src. Document the decision.
- our-x86 MUST == original-x86 (1-to-1); if our-x86 diverges, a source hack did it → revert to pristine.

## Validator (`phase-Gmenu-placement.sh`) PASS requires
1. `.autoport/reports/Gmenu-placement/menu.txt`: per-element computed X/Y (+scale) for original-x86,
   our-x86, device at 2400x1080 — our-x86 == original-x86 (1-to-1), a calibrated BEFORE where device
   elements cluster toward center vs the correct spread, and an AFTER where device element positions
   match the intended spread (== original at the same aspect, or the documented correct ultrawide
   layout). With `RESULT: MENU ELEMENTS PLACED CORRECTLY (device, positions match intended)`.
2. our-x86 == original-x86 explicitly; any `goal_src/**` edit must be a documented pristine revert
   (else fix is in `goalc/**`/`game/**`/`android/**`). The decisive x86-at-2400x1080 finding is recorded.
3. Fix-summary `.autoport/reports/Gmenu-placement-fix-summary.md` ≥60 lines; temp instrumentation
   removed; `.autoport/gold` git-clean.
4. x86 still `link finish: logo`; device boots crash-free to the menu; `deploy_verify.sh eae4df44` PASS.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. `.autoport/gold` READ-ONLY/pristine.
After any failing device run, `bash .autoport/restore_knowngood_device.sh`. NO screenshot grind.

## Max settings
`max_turns: 1400`, `max_retries: 3`.
