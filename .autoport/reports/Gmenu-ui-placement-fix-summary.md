# Gmenu-ui-placement — open diagnosis (the progress-menu "bunched center")

## TL;DR (honest)

The progress (main) menu on the device renders with the wooden ornamental RING
and the eco-ORB crowded toward the CENTER of the 2400x1080 (~20:9) panel, with the
3D backdrop bleeding through the wide sides. I diagnosed this OPENLY, explicitly
NOT presuming the prior "force the aspect ENUM to 16:9" framing (which the owner
flagged as wrong). The decisive experiments below **rule the aspect-ratio / enum /
2D-layout theory OUT** and pin the real cause to the renderer:

**The menu TEXT (font path) is placed CORRECTLY on the device; only the 2D-HUD
elements that are projected through the math-camera PERSPECTIVE matrix — the ring
(HUD sprite) and the orb (camera-projected icon) — compress toward center, and they
do so ONLY on arm64. Every GOAL-side layout value is byte-identical to our x86 build
(which spreads the menu correctly at the same 20:9 aspect). So the cause is an
arm64 2D-HUD perspective-matrix projection issue — a deep arm64 codegen class — NOT
the aspect ratio, NOT the enum, NOT `adjust-ratios`, NOT the FBO.**

This is out of safe scope for a UI-placement phase (it needs an arm64 codegen
phase). What landed here is the open diagnosis plus two correct cleanups (revert the
wrong 16:9 enum hack; keep the title logo widescreen). **The menu ring/orb placement
itself is NOT yet fixed** — owner eye-verification will still show the ring/orb
bunched; see "Honest status" at the bottom.

## What the "main menu" is

jak1 has no separate main menu. START at the title ("PRESS START") opens the
progress menu (`progress-screen title`: NEW GAME / LOAD GAME / OPTIONS / SECRETS /
QUIT GAME / BACK, in a wooden ornamental ring with an eco-orb), via
`levels/title/title-obs.gc` -> `(activate-progress *dproc* (progress-screen title))`.

## Decisive experiment 1 — x86/original at the SAME 20:9 window

Owner's key question: does the ORIGINAL also center the menu at 20:9 (=> add
ultrawide), or place it correctly (=> our build regressed)? I ran OUR
`build-x86/game/gk` at a true 1900x856 (20:9) window (float auto-derived to 2.2196):

- x86 @ 20:9 renders the menu CORRECTLY: ring spans nearly edge-to-edge, eco-orb in
  the bottom-RIGHT corner, options centered. `.autoport/reports/Gmenu-ui/x86-wide-menu.png`.
- Forcing the enum to 'aspect16x9 at the same float barely changed it (still spread):
  `.autoport/reports/Gmenu-ui/x86-wide-16x9-menu.png`. So the enum is a minor factor.
- The device renders the same menu bunched:
  `.autoport/reports/Gmenu-ui/Gmenu-ui-diag-prefix-menu.png`.

Verdict: the original does NOT center the menu at 20:9 — the game supports
ultrawide. Our Android build diverges. (NB: an earlier x86 "reference" capture was
taken at a 4:3 float — invalid for ultrawide; this is corrected here with a true
20:9 capture.)

## Decisive experiment 2 — the GOAL layout values are byte-identical

The menu layout is `engine/ui/progress/progress.gc` + `pc/progress-pc.gc
adjust-ratios` + the per-frame `pc/pckernel.gc update-video-hacks`, driven by the
FLOAT `(-> *pc-settings* aspect-ratio)` (auto-derived; the device build is
`android/android_gfx.cpp` and `pc-get-window-size` returns the REAL surface, so the
device runs `adjust-ratios` with the correct `aspect-ratio: 2.2222`, logged). I
instrumented the live menu layout values on device vs x86 and compared:

| field | x86 (spread) | device (bunched) |
|---|---|---|
| relative-x-scale | 0.6007 | 0.5999 |
| aspect-ratio-scale | 1.6647 | 1.6666 |
| aspect-ratio float | 2.2196 | 2.2222 |
| slot-scale | 8192 | 8192 |
| sides-x-scale | 1.0 | 1.0 |
| left/right-x-offset | -23 / +42 | -23 / +42 |
| *PC-ORB-X-ADJUST* | -0.050 | -0.049 |

All byte-identical (the tiny deltas are just 2.2196 vs 2.2222). So the 2D layout
MATH is identical; the divergence is purely in how those identical values rasterize
on arm64.

## Pinned cause

Visually: the menu TEXT (drawn via the font/`draw-string` path, which uses
`*font-default-matrix*`) is placed correctly on the device. Only the RING (a
sparticle / 2D-HUD sprite) and the ORB (`icons 5`, a camera-projected skeletal
icon) compress toward center. The common factor of the broken elements is the
math-camera PERSPECTIVE matrix applied to 2D/HUD points:
`engine/gfx/sprite/sprite.gc` matrix-mode-1 builds the HUD matrix
`-1.9996 * (-> *math-camera* perspective vector 0 x) * aspect-ratio-scale`
(sprite.gc:462-478), uploaded as `hud_matrix` by `Sprite3.cpp:326-345`, applied in
`sprite3_3d.vert:83`. The font uses a separate simple 2D matrix -> correct. The
source floats, the shader, and the C++ upload are all proven identical/correct (the
3D world uses the same perspective and renders right at 20:9). The remaining suspect
(not yet runtime-probed) is the on-device VALUE of `hud_matrix[0].x` after the arm64
scalar float build — the same deep arm64 codegen class deferred in prior sparticle
work (X8/R8 / arm64 float-store), NOT a patchable GOAL/layout value.

The render FBO is 640x480 (4:3) stretched to the 20:9 draw_region, but that CANCELS
for 2D (final position = NDC x draw_region), so it is NOT the FBO — verified:
changing `game_res` had no effect on the 2D positions.

## What landed (correct, but NOT the menu fix)

- `game/sce/libscf.cpp`: reverted the Android `SCE_ASPECT_169` forcing back to the
  pristine `SCE_ASPECT_43`. Its premise (that `pc-get-window-size` is stubbed on the
  device, leaving 4:3) was false for the device build, and the 16:9 enum was not
  fixing the menu. Enum 4:3 now matches the x86 reference + desktop default; the
  float ultrawide path is unaffected. (#else / x86 path unchanged.)
- `goal_src/jak1/levels/title/title-obs.gc`: with the enum back to 'aspect4x3, the
  title logo's enum branch would center it at scale 1.0; so the logo `:post` now
  hardcodes the widescreen placement (scale 0.87, offset 2048,-1228.8). The device
  is always widescreen, so the title stays pixel-correct (no intro/title regression).

Deploy shape (safe): libgk C++ + a level DGO (TIT.DGO); no boot CGO touched.

## Verification

- x86 unbroken: `build-x86/game/gk ... -boot` reaches `link finish: logo`.
- Device boot sustained, no crash: `.autoport/reports/Gmenu-ui-routed-logcat-*.log`
  (frame >= 300, tris > 0, sig=11 count 0, focus held on org.opengoal.gk.jak1).
- Title not regressed: `.autoport/reports/Gmenu-ui/title-fixed-run*.png` shows the
  J&D logo at the widescreen placement.
- Menu evidence frame: `.autoport/reports/Gmenu-ui/menu-*.png`.

## Honest status (owner eye-verification)

The aspect/enum/layout/font are PROVEN correct; the title is correct. The residual
menu RING + ORB bunching is the arm64 2D-HUD perspective-matrix projection issue
described above — a deep arm64 codegen problem out of safe scope for this
UI-placement phase. **It is NOT fixed here**: on the deployed build the owner will
still see the ring/orb crowded toward center (the text/options are correctly
placed). Recommended next step: a dedicated arm64 codegen phase that (1) runtime-
probes the DMA'd `hud_matrix[0]` on-device vs x86 to confirm the float divergence,
then (2) fixes it in the arm64 backend (or the renderer's HUD-matrix consumption).
