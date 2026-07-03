# Phase Gorb-hud-regression — Precursor orbs render WHITE again on HUD/interfaces (render-split regression)

## Why (owner 2026-07-03)
The "Precursor orb rendered white on the HUD" bug was FIXED earlier (Gorb-icon phase, completed). It
REGRESSED when we split the UI/HUD off the main render (Grender-split: scaled-3D pass + native UI
pass). It now affects EVERY interface where a Precursor orb is rendered (HUD counter, menus, save
screens...), not just the in-game HUD. Owner mandate: fix it while KEEPING the render-split
("tout en gardant la corrélation") — do NOT revert the split.

## Mandate
1. Recover the ORIGINAL Gorb-icon fix (git log/report for the Gorb-icon phase): what made orbs render
   correctly (likely a texture/EYE/environment-map or sprite-tex binding on the orb draw)?
2. Diagnose WHY the render-split broke it: the orb draw presumably moved to (or samples from) the
   native-UI pass where some input it needs (a texture bound during the 3D pass, an FBO source, the
   scene color for envmap, a render-state) is no longer available/bound → falls back to white.
3. Fix IN THE SPLIT ARCHITECTURE: make the orb's required inputs available to the UI pass (bind the
   texture/envmap source in the UI pass, or render orbs in the pass that has their inputs) so orbs
   render correctly on ALL interfaces, with the split intact (UI still native-crisp, 3D still scaled).
4. Sweep: HUD orb counter, pause/progress menu, save/load screens — every orb site correct.

## Verify (device eae4df44)
Screencaps of each orb site (HUD in-game, menu, save screen) showing correctly-rendered orbs (not
white), at render-scale 100% AND 50% (split active, UI crisp, orbs correct in both). 0 flicker.
Prior fixes intact. x86 unaffected (link finish: logo). Full CONSISTENT build, deploy_verify PASS.

## Report (`.autoport/reports/Gorb-hud-regression/report.txt`) with `RESULT: PRECURSOR ORBS CORRECT IN SPLIT`
the original fix recovered, why the split broke it, the in-split fix, per-site screencap proof at
100%+50% scale, split intact (UI native), x86 ok.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; engine goal_src untouched if avoidable; .autoport/gold READ-ONLY.
## Max: max_turns 2000, max_retries 5. device: true, owner_verify: true.
