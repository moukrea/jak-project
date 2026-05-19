# Phase 31 — Reach the first playable level (Geyser Rock)

## Goal

Drive the runtime from title screen through main menu → New Game →
opening cinematic → first level (`geyser-rock` in jak1). The validator
asserts the engine state transitions to a level name that comes from
`game/kernel/jak1/`, that the screencap shows a 3D scene (depth +
many colors, not a 2D menu), and that the game keeps running for ≥60
seconds without crash.

This is the stretch goal — the "we actually shipped jak1 on Android"
milestone.

## Anti-stub rules

- The engine state name must come from `game/kernel/jak1/gstate.gc`'s
  generated state list (`geyser-rock`, `village1`, `intro-control`,
  etc.). Hardcoded "level1" or "stage_one" in android/ does not count.
- The validator does a perceptual hash on the screencap. A 2D menu
  (uniform background + sparse UI) has a different visual fingerprint
  than a 3D scene (foliage, lighting gradient, perspective). The
  Python helper computes color-block statistics and asserts the post-
  load screen looks 3D-shaped.
- ≥60s longevity without `Fatal signal` / SELinux denial / SIGSEGV /
  process disappearance.

## Concrete deliverables

1. **Input driver script** at `.autoport/lib/jak1_first_level_drive.sh`
   that:
   - Waits for `engine: state=title`.
   - Taps START.
   - Waits for `engine: state=main-menu` (or whatever gstate emits).
   - Taps the "New Game" hitbox.
   - Taps through the opening dialog (if any).
   - Waits for `engine: state=geyser-rock` (or first-level name).

2. **Pixel-content "3D-scene" check** in `anti-stub.sh`:
   `anti_stub_check_3d_scene_like <png>` returns 0 if the image has
   characteristics of a rendered 3D scene: ≥150 unique RGB values,
   non-uniform vertical gradient, presence of mid-tone pixel clusters
   (not pure black/white).

3. **Longevity sub-test**: 60s of continuous logcat tail with the same
   crash/denial checks as phase 22.

## Don't

- Don't add a debug shortcut that skips the menu. The point is to
  prove the input → state → renderer chain works end-to-end.
- Don't reduce the longevity window to 30s. Real users won't tolerate
  a game that crashes after a minute.

## Pitfalls

- If the menu requires a directional press before START, the script
  needs to do that. Update the script (not the validator) when
  observed.
- Some opening dialogs auto-advance; some require a tap. Test what
  jak1 actually does and have the script handle both.
- The first level load is slow (~10-30s on mobile). Budget for it.

## Validator

```
.autoport/validators/phase-31-playable.sh
```

## Success

The runtime reaches a real `engine: state=<level-name>` from
`game/kernel/jak1/`, a screencap of the level looks like a 3D scene by
the pixel-content checks, and the game stays alive for ≥60s of
gameplay.
