# Phase 30 — Title screen visible and reactive to input

## Goal

Phase 29 proved the renderer is alive and the framebuffer has real
content. This phase proves that content is actually the **jak1 title
screen** (not a debug splash) and that pressing START transitions to
the menu (proving input + GOAL state machine + renderer are end-to-end
wired).

## Anti-stub rules

The validator is two screencaps and a tap:

1. screencap **before** any input → `pre.png`
2. tap the START hitbox via `adb shell input tap`
3. wait 3s
4. screencap **after** → `post.png`
5. Assert `pre.png` and `post.png` differ by a meaningful perceptual
   delta (not just one pixel; not noise-level).

A stub that renders the same image regardless of input cannot pass
this. A stub that flickers randomly would have to also match a known
title-screen template — the validator optionally does template-matching
against a reference (provided in `test/jak1_title_ref.png`).

## Concrete deliverables

1. **A reference title-screen PNG** at
   `test/jak1_title_ref.png`. Capture from the desktop build at the
   same resolution as the device, OR provide a synthetic reference if
   the desktop build is unavailable. Document its provenance in
   `test/README.md`.

2. **Touch overlay coordinate sanity** — ensure phase 23's overlay
   hitbox geometry matches what the validator will tap. Add log line
   `touch-hitbox: start_button at (X,Y)-(W,H)` on overlay creation
   so the validator can use those coords instead of guessing.

3. **No new code in `android/`** — phase 30 is observation-only.
   Renderer + dispatcher + input are all phase-28/29 work. Phase 30
   just proves the system works.

## Don't

- Don't add a "title screen ready" log line and call that proof.
  The proof is the framebuffer pixels and the input response.
- Don't lower the perceptual-diff threshold to make the validator
  easy. The threshold is set to detect a meaningful screen change
  (e.g., menu overlay appearing).
- Don't synthesize the "menu state" with a TextView overlay drawn by
  Java. The state change must come from GOAL's gstate.gc.

## Pitfalls

- The exact coordinates of "START" on the on-screen overlay depend
  on TouchControlsView's layout, which depends on screen size. The
  log line from deliverable #2 makes this device-independent.
- Some Android devices freeze the screen during screencap; if pre
  and post are identical because screencap is broken, the validator
  fails — that's correct. Force a hardware screenshot via
  `adb shell screencap -p /sdcard/pre.png && adb pull /sdcard/pre.png`
  as a fallback.
- jak1's actual title screen takes a few seconds to fully draw
  (logo, "press start" text, etc.). Wait at least 5s after
  `engine: state=title` before the pre-screenshot.

## Validator

```
.autoport/validators/phase-30-title-screen.sh
```

## Success

The title screen is on-screen (verified by perceptual content), and a
START tap produces a measurably different screen within 3s (menu).
