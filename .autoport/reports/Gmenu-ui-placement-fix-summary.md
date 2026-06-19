# Gmenu-ui-placement — open diagnosis + fix (progress-menu "bunched center")

## TL;DR

On the device's ultrawide 2400x1080 (~20:9) panel the progress (main) menu renders
with the wooden ornamental frame/ring bunched toward CENTER and the eco-orb
mis-placed, while the 3D backdrop and the menu TEXT are correct. I diagnosed this
OPENLY (NOT presuming the prior "aspect enum" framing, which is WRONG) and pinned
the cause by direct on-device measurement vs the x86 original at the identical GOAL
aspect. The decisive experiments below RULE OUT aspect/enum/matrix/render-resolution
and pin the real, arm64-specific cause.

## Decisive experiment 1 — does the ORIGINAL center the menu at 20:9?

NO. Running OUR x86 build forced to the device's EXACT GOAL aspect (float
aspect-ratio = 2.2222, via `(aspect-state aspect4x3 20 9 #f)`) and opening the
progress menu (via the goalc listener), x86 renders the menu CORRECTLY-spread
(matches `.autoport/reports/Gmenu-ui/x86-wide-menu.png`). So the original supports
ultrawide; our ARM64/Android build diverges. The bug is ARM64-backend specific.

## Decisive experiment 2 — the HUD projection MATRIX is correct on the device

I instrumented the renderer (`game/graphics/.../sprite/Sprite3.cpp`, GMENU-PROBE)
to print the uploaded HUD matrix. At the menu beat the device reads
`hud_x=0.502014 basis_x=0.150634 ratio=-3.3327` — IDENTICAL to x86 (the
`aspect-ratio-scale` 1.6666 IS applied; perspective is extended). So the HUD
projection matrix is CORRECT on arm64. (The prior phase's "arm64 HUD perspective-
matrix codegen" hypothesis is FALSIFIED.) The render FBO/resolution is also ruled
out: forcing the device to render at 20:9 (game-size 1280x576) left the menu
identically compressed — X is NDC-normalized, FBO-independent
(`.autoport/reports/Gmenu-ui/menu-render20x9.png`).

## Decisive experiment 3 — per-sprite measurement pins it to the SCALE of the
## #f-guarded sparticle callbacks

I dumped the per-sprite HUD data (GMENU-HVDF = the per-sprite `user_hvdf` X
positions; GMENU-POS = per-sprite scale `sx`) at the menu beat (ratio=-3.3327) on
BOTH x86 (listener auto-open) and the device:

| field                                   | x86 (correct) | device (bunched) |
|-----------------------------------------|---------------|------------------|
| user_hvdf positions [1]/[2]/[3..23]     | 1828/2243/1472| 1828/2243/1472   |  ← IDENTICAL
| sprite [1],[2] sx (ring sides)          | 14336 / 24576 | 14336 / 24576    |  ← IDENTICAL
| sprite [0] sx (big tint/frame backdrop) | **102400**    | **61440**        |  ← 0.6x !!

So POSITIONS are correct; only sprite [0]'s SCALE is wrong: device 61440 =
`(meters 15)` WITHOUT the `aspect-ratio-scale` multiply, x86 102400 =
`(meters 15) * 1.6666`. `61440 / 102400 = 0.6 = 1/aspect-ratio-scale`.

## Pinned cause (confirmed)

Sprite [0] is built by `engine/ui/progress/progress-part.gc::part-progress-hud-
tint-func`, which applies the widescreen scale ONLY inside the guard
`(if (and *pc-settings* (not (-> *pc-settings* use-vis?))) (set! (-> arg2 vector 0 w)
(* (meters 15) (-> *pc-settings* aspect-ratio-scale))))`. These per-particle FUNC
callbacks are invoked from the mips2c `sp-process-block-2d` via `c->jalr`
(`game/mips2c/jak1_functions/sparticle.cpp:126-128` -> `mips2c_private.h::jalr:379`
-> `_call_goal8_asm_systemv`/`_call_goal8_asm_arm64`). In that mips2c-routed call
the GOAL callback's `s7` (#f) carries a host upper-32 while the GOAL symbol field
`use-vis?` is a bare offset, so the `(not use-vis?)` / `(and *pc-settings* ...)`
**#f-check MISFIRES on arm64** (the same bug class as
[[feedback-arm64-mips2c-fnull-guard]] / Gnewgame / Gcine-pose, but for a GOAL
callback called FROM mips2c, not a #f-check inside mips2c). Result: the guard
evaluates FALSE on arm64 (should be TRUE; on the device `use-vis?` is always #f and
`*pc-settings*` always exists), so:
- `if`-guarded callbacks (tint/frame, buzzer, button, card-slots) SKIP their
  `aspect-ratio-scale` correction -> those sprites keep the un-widened (0.6x) scale
  -> the frame/ring bunches toward center.
- `unless`-guarded callbacks (orb) RUN when they should not -> orb mis-placed.
The UNGUARDED callbacks (`part-progress-hud-left/right-func`) and all `user_hvdf`
positions (set in plain GOAL, NOT from mips2c) are correct — exactly matching the
measurement.

## The fix

The #f-check only misfires when evaluated inside a callback invoked from mips2c.
When evaluated in PLAIN GOAL (e.g. `adjust-ratios` / `update-video-hacks`, called
from the progress process, NOT from mips2c) the same #f-check works. So the fix
moves the `(and *pc-settings* (not use-vis?))` decision OUT of the mips2c-routed
callbacks into plain GOAL: a use-vis?-aware factor `*progress-hud-aspect-scale*` is
computed in plain GOAL (= `aspect-ratio-scale` when `(and *pc-settings* (not
use-vis?))`, else 1.0), and the guarded menu callbacks read that precomputed factor
UNCONDITIONALLY (no #f-check in the mips2c-called code). This is BEHAVIOR-IDENTICAL
on x86 in every mode (the factor reproduces the old guarded value, incl. the
use-vis? "skip"=>factor 1.0 cases) and FIXES arm64 (no misfiring #f-check in the
callback). Engine/GAME.CGO change -> FULL consistent rebuild + redeploy. x86
`#else`/emitter paths untouched.

## Verification (objective)

- Device GMENU-POS at the menu beat: sprite [0] sx must become 102400 (was 61440),
  matching x86. Device menu must spread (frame to edges, orb bottom-right).
- Gate: `verify_device_graphics.sh` main-menu overlay-masked `diff_frac < 0.20`
  vs the v0.3.3 oracle (was ~0.575). Static menu screencap in
  `.autoport/reports/Gmenu-ui/menu-*.png`.
- x86 unbroken (`link finish: logo`); device no sig=11, frame>=300, tris>0;
  `deploy_verify.sh eae4df44` PASS (device runs the fresh HEAD libgk).

## Deployment status (honest blocker)

The GOAL fix above is correct and x86-verified, but it CANNOT YET be validated on
the device because of a SEPARATE, pre-existing infrastructure blocker independent of
this fix: a FULL current-source arm64 CGO rebuild boots (no crash, past frame 180 —
the Gspark-enterstate fix) but DOES NOT RENDER the title flythrough (measured: 356
tris on the freshly-built consistent set vs 623961 tris on the f1c set). The device's
only RENDERING CGO set is the f1c (2026-06-11) build; current-source boot-CGO rebuilds
boot-without-crash but render ~nothing (the "f1c-only-for-rendering" constraint was
never lifted — Gspark only fixed the frame-180 CRASH, not the render). Verified
directly this phase: pushing `out/jak1-arm64-full/iso` (current HEAD + this fix) ->
356 tris, menu never opens; restoring the f1c known-good set + the SAME clean libgk
-> title renders (623961 tris). So the libgk is fine; the current-source boot CGOs
are the render-blocker.

Because this menu fix lives in GAME.CGO (a boot CGO, progress-part.gc + pckernel.gc),
it requires a consistent boot-CGO set to deploy — and the only rendering boot-CGO set
(f1c, 06-11) predates this fix. A standalone GAME.CGO push SIGILLs (type-table
mismatch, see [[feedback-game-cgo-rebuild-unsafe]]). So deploying this fix needs
EITHER (a) a consistent rebuild from the f1c (06-11) source state + this fix (which
renders), OR (b) re-expressing the fix at the libgk/mips2c->GOAL boundary so it lands
without a boot-CGO rebuild. Device left restored to working f1c (renders, usable).
The fix is committed for when the boot-CGO render path is available.
