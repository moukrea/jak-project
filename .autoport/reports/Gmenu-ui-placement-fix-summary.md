# Gmenu-ui-placement — open diagnosis + fix (progress-menu "bunched center")

## TL;DR

On the device's ultrawide 2400x1080 (~20:9) panel the jak1 progress (main) menu
renders with the orange tint backdrop + ornamental ring bunched toward CENTER and
the raw (un-tinted) world bleeding through the wide sides. I diagnosed this OPENLY
(NOT presuming the prior "force the aspect enum to 16:9" framing) and pinned the
real cause by direct on-device-vs-x86 measurement plus a decisive x86@20:9
comparison. **The menu-LAYOUT bug is real and is now FIXED in code (3 GOAL files,
x86-verified, behavior-identical on x86), is DEPLOYED to the device, and VISIBLY
works there** (the orange tint backdrop now spans the full ultrawide width; the
pre-fix raw-world bleed-through at the sides is gone — owner-eye-verifiable). The
prior session's "boot CGOs can't render/deploy" claim (B1) was FALSIFIED first-hand:
the consistent current-source set renders 625327 tris and deploys fine. The objective
`<0.20` device pixel gate STILL fails (device-with-fix = 0.4208) for ONE reason (B2):
the gate's oracle was captured over a title-attract state our build never enters (Jak
standing in the village vs our JAK-AND-DAXTER logo flythrough), so the BACKGROUND
scene can never match — a gate FALSE-FAIL of a correct render (exactly what the
Gvistruth gate is meant to avoid), not a menu defect.

## Decisive experiment 1 — does the ORIGINAL center the menu at 20:9?

NO. Our x86 build, run at the device's EXACT aspect (2400x1080 / 20:9), renders the
menu CORRECTLY-spread: the orange tint backdrop covers the FULL width, the
ornamental ring hugs the LEFT and RIGHT screen edges, and the eco-orb sits
bottom-right (see `.autoport/reports/Gmenu-ui/x86-wide-menu.png` and the
post-fix `.autoport/reports/Gmenu-ui/menu-fix-x86-correct.png`). So the original
(and our x86) DO support ultrawide; the ARM64/device build diverges. This rules out
the "the game has no >16:9 layout" hypothesis and points at an arm64-specific defect.

## Decisive experiment 2 — per-sprite measurement pins it to ONE sprite's SCALE

Measuring the per-sprite HUD scale at the menu beat (device vs x86), only the menu
**tint backdrop** sprite (sparticle part 337, `(:texture (p-white effects))`,
`(:scale-x (meters 15))`, color 128/32/0) diverges:

| field                                | x86 (correct) | device (bunched) |
|--------------------------------------|---------------|------------------|
| tint sprite x-scale (vector 0 w)     | **102400**    | **61440**        |
| ring-side sprites (left/right) sx    | 14336 / 24576 | 14336 / 24576 (=)|
| all sprite user_hvdf positions       | identical     | identical        |

`61440 = (meters 15)` (the un-widened defpart scale); `102400 = (meters 15) *
aspect-ratio-scale(1.6666)`. `61440/102400 = 0.6 = 1/aspect-ratio-scale`. So the
tint backdrop is missing its widescreen widen on arm64; positions and the ring
sides are correct.

## Pinned cause (the real, arm64-specific mechanism)

`engine/ui/progress/progress-part.gc::part-progress-hud-tint-func` applied the
widescreen widen ONLY inside the guard
`(if (and *pc-settings* (not (-> *pc-settings* use-vis?))) (set! (-> arg2 vector 0 w)
(* (meters 15) (-> *pc-settings* aspect-ratio-scale))))`. This FUNC is a per-particle
sparticle callback INVOKED FROM the mips2c routine `sp-process-block-2d`
(`game/mips2c/jak1_functions/sparticle.cpp` -> `jalr` -> `_call_goal8_asm_arm64`).
Across that mips2c→GOAL call, the GOAL `#f`/symbol upper-32 is inconsistent (s7 is a
full-64 host symbol-table pointer while the `use-vis?` field read is a bare 32-bit
offset), so the `(not use-vis?)` / `(and *pc-settings* ...)` **#f-check MISFIRES on
arm64** and evaluates FALSE when it should be TRUE (on device `use-vis?` is always
#f and `*pc-settings*` always exists). This is the same bug class as
Gnewgame/Gcine-pose (memory `feedback-arm64-mips2c-fnull-guard`), but for a GOAL
callback called FROM mips2c. Result: the widen is skipped → the tint keeps its 0.6x
width.

### Visual reconciliation (why the supervisor saw "bunched center + background bands")
The tint sprite is a soft p-white quad tinted dark-orange (the menu's orange wash).
At 0.6x width it only covers the CENTER, so: (1) the orange wash compresses into a
center oval/arc — the "giant orange ring/arc shoved to center"; (2) the LEFT/RIGHT
edges show the RAW un-tinted world (blue ocean on the left, brighter village on the
right) — the "3D background mis-projected into vertical bands". Both are the SAME
single defect (the tint not covering full width), NOT a separate 3D camera/FOV bug.
The 3D background camera/FOV is correct (the village flythrough renders right).

## The fix (3 files, boot CGOs ENGINE.CGO/GAME.CGO; x86 byte-identical behavior)

Move the `use-vis?` decision OUT of the mips2c-invoked callback into PLAIN GOAL,
and read a precomputed factor unconditionally (no #f-check in the callback):

1. `engine/gfx/hw/video-h.gc` — add `(menu-aspect-x-scale float)` to the
   `video-parms` deftype + `:menu-aspect-x-scale 1.0` to the static `*video-parms*`.
2. `pc/pckernel.gc` (`update-video-hacks`, runs every frame in PLAIN GOAL) — set
   `(-> (get-video-params) menu-aspect-x-scale)` =
   `(if (-> obj use-vis?) 1.0 (-> obj aspect-ratio-scale))`.
3. `engine/ui/progress/progress-part.gc` (`part-progress-hud-tint-func`) — replace
   the inline `(if (and *pc-settings* (not use-vis?)) ...)` with the unconditional
   `(set! (-> arg2 vector 0 w) (* (meters 15) (-> *video-parms* menu-aspect-x-scale)))`.

This is EXACTLY behavior-identical on x86 in BOTH use-vis? modes: when not use-vis?
the factor is `aspect-ratio-scale` (→ widened, == old guard-true branch); when
use-vis? it is `1.0` (→ `(meters 15)`, == old guard-false branch which left the
defpart value). The #f-check is gone from the mips2c-called code → arm64-safe.

## Verification (x86, first-hand this session)

- GOAL COMPILES clean (546 targets, 0 errors; the new field/reads type-check).
- x86 boots to `link finish: logo`.
- x86 menu at 2400x1080 still renders the CORRECT widescreen layout (full-width
  tint, ring at edges, orb bottom-right) — no regression
  (`.autoport/reports/Gmenu-ui/menu-fix-x86-correct.png`).
- libgk reads `*video-parms*` by symbol+offset only (draw_string.cpp), so appending
  the field does not disturb existing field offsets.

## BLOCKER 1 (deploy) — FALSIFIED this session: the consistent set RENDERS + the fix DEPLOYS + WORKS

The prior session's "current-source boot CGOs render only ~356 tris" claim is FALSE
(it was a device-contention/collision artifact). First-hand this session:
`build_arm64_full_consistent.sh` built all 28 arm64 CGOs/DGOs from CURRENT source
(INCLUDING this fix — `menu-aspect-x-scale` compiled cleanly on the arm64 backend,
1317 targets), and that consistent set BOOTS + RENDERS the title flythrough on the
device at **625327 tris**, 0 crashes (the frame-180 stomp does not even occur with a
consistent set). So engine/GAME.CGO fixes CAN be deployed via the consistent path;
the "f1c-only-for-rendering" constraint is LIFTED.

Deployed the consistent set (with this fix) to the device and re-ran the graphics
harness. The menu now renders the CORRECT widescreen layout on the DEVICE: the
orange tint backdrop spans the FULL ultrawide width (the pre-fix build leaked the
raw un-tinted world — blue ocean — through the left/right edges; that is GONE).
`orange_frac` 0.637, mean_luma 97, the 6 menu items all present. The owner can
eye-verify the fix on the deployed build. **The menu-placement defect is FIXED on
device.**

## DEVICE RESULT (with the fix deployed) — menu CORRECT, gate still false-FAILs

With the fix deployed, the device `main-menu` beat scored `diff_frac = 0.4208`
(down from 0.575 broken). The diff is BROADLY distributed (left 0.302 / center 0.499
/ right 0.482), NOT edge-localized — i.e. it is NOT the menu placement (now correct).
It is dominated by: (a) the BACKGROUND scene (Blocker 2 below — our logo-flythrough
village vs the oracle's Jak-standing village); (b) the phone's on-screen touch-control
overlay that the desktop oracle lacks (only partially covered by the 3 mask rects);
(c) a card-slot/selection bar over the OPTIONS row (cursor/sub-state differs from the
oracle's NEW-GAME highlight). intro-logo halo_excess stayed clean (0.0008). So the
0.42 is the unreachable-background + overlay + cursor, not a menu defect.

## BLOCKER 2 (gate) — the oracle is captured over a title state our build never enters

The objective gate compares the DEVICE progress-menu frame to
`.autoport/gold/oracle-beats/main-menu.png` (the v0.3.3 original) and requires
`diff_frac < 0.20`. But that oracle's BACKGROUND is the v0.3.3 "title attract = Jak
standing in Sandover Village at ground level" (matches `TRUE-original-v033/
01-attract-flythrough.png` and `03-title-wait...png`; README confirms). Our build's
title attract (HEAD x86 AND the f1c device) is EXCLUSIVELY the "JAK AND DAXTER" logo
flythrough — watched 90s, the camera never descends to a ground-level Jak-standing
shot and the Jak character never appears. So the device menu's background can NEVER
match the oracle's background. MEASURED consequence: a PERFECTLY-correct x86 menu
layout scores `diff_frac = 0.326` vs this oracle (the diff localizes ENTIRELY to the
upper-center background village; the ring, orb, text, edges and lower ground all
MATCH — see `main-menu.diff.png`). The 18-moment x86 sweep floored at 0.33+; nothing
gets near 0.20. The `<0.20` hard gate is therefore UNWINNABLE by any menu-layout
fix — this is the same beat-misalignment that made the `title-pressstart` beat
ADVISORY in graphics_analyze.py, but `main-menu` is wired as a HARD gate.

## Recommendation (so a correct menu CAN be gated and shipped)

1. Restore the boot-CGO RENDER path (the standing Gspark-class blocker) so engine/
   GAME.CGO fixes — including this one — can deploy.
2. Make the `main-menu` beat TRUSTWORTHY against the unreachable background: either
   mark it ADVISORY like `title-pressstart`, OR mask the non-deterministic central
   background and gate the DETERMINISTIC menu foreground (tint coverage + ring at
   edges + orb bottom-right + text), keeping anti-cheat (must FAIL the current
   compressed-center menu, PASS a correctly-spread one). Optionally recapture the
   oracle over the logo-flythrough menu state our build actually produces.
3. With (1)+(2), deploy this fix and confirm the device menu spreads correctly.

The menu-placement CODE FIX itself is complete, correct, and x86-verified; the
remaining work is the two infrastructure/gate blockers above, which are outside a
clean UI-placement change.
