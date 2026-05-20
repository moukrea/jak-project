# test/ — autoport phase-30 artifacts

This directory predates the autoport effort and primarily holds the
GoogleTest-driven C++ unit tests for the OpenGOAL decompiler / runtime
(`test_main.cpp`, `test_kernel_jak1.cpp`, etc.). Phase 30 of the
Android port adds two extra artifacts that are consumed (or referenced)
by `.autoport/validators/phase-30-title-screen.sh` and any humans
auditing whether the device-side title screen really matches the
shipping game.

## `jak1_title_ref.png` — synthetic reference image

**Provenance:** synthesized procedurally from
`.autoport/logs/30-title-screen/README` regeneration step using
Pillow. Not captured from a running game.

**Why synthetic:** the autoport harness runs headless and the only
available x86 desktop GOAL build at this phase has the same renderer
pipeline as the Android side (phase 29 brought up the real renderer
chain end-to-end). Capturing a "desktop reference" would only prove
the desktop build also renders something — it wouldn't be an
independent ground truth. The phase-30 validator therefore relies on
two device-side checks that *don't* need a pixel-perfect reference:

1. `anti_stub_count_pixel_diversity` (≥50 distinct RGB values in the
   200×200 centre region and dominant colour <70%) — proves the
   framebuffer is not a glClear of a constant colour.
2. A perceptual diff between the pre-tap and post-tap screencaps
   (≥3% of central pixels changed by ≥30 luma) — proves the START
   tap drove the kernel from `state=title` into a visibly different
   state (menu).

`jak1_title_ref.png` exists so that future, manual visual audits have
*something* to align against; if you want a real reference, replace
this file with a `adb shell screencap -p` of the live device once
phase 30 lands. Resolution is 640×480 (4:3, ~PS2 aspect) and the
content is a hand-drawn approximation of the title's sunrise sky +
centred logo + "PRESS START" prompt.

**Do not use this PNG as input to any automated diff threshold** — it
is documentation, not ground truth.

## Other phase-30 artifacts

- Successful-run logcat:
  `.autoport/logs/30-title-screen/evidence/device-logcat.successful-run.log`
  contains the kernel `engine: state=boot|load|title` transitions and
  the `touch-hitbox: start_button at (X,Y)-(W,H)` line emitted by
  `TouchControlsView.onSizeChanged()`. The validator parses the latter
  to derive device-independent tap coordinates.
