# Phase F1 — Gameplay: reach + navigate Geyser Rock

## Status

**Authored 2026-05-22 by the supervisor**, replacing the May-21
placeholder. F1 is the north-star phase — the entire port exists to
make this work: **Jak runs through the Geyser Rock tutorial level on
the Redmi Note 9 Pro, with identical physics, collision, and game
state as the desktop x86_64 build under the same input sequence**.

## Bucket

F — Stretch gameplay (REDESIGN.md §8).

## Goal (concrete, device-verifiable)

1. Navigate title → "New Game" → Geyser Rock loads on device.
2. Jak character spawns at the canonical spawn point (verified by
   GOAL state probe: `(-> *target* trans)` matches desktop's first
   frame within float epsilon).
3. **Determinism test**: drive a recorded input script (forward,
   jump, forward, jump-jump) via `adb shell input` events; the
   resulting game-state trace at frame 600 (~20 sec) matches the
   desktop oracle's state at frame 600 within position epsilon
   (< 0.1 unit) and matches collision-state exactly.
4. Trace-diff against the desktop oracle through the level-loaded
   milestone (`engine: state=in-game` or `load 'geyser-rock` in the
   trace, whichever exists).

## Hard rules — same-behavior contract

- Shim governance from E1: every `android/*.cpp` function carries
  a `SHIM_KIND:` tag.
- `goalc/` codegen + classifier byte-identical to A5 close.
- x86 CGOs byte-identical to A2 baseline; arm64 CGOs byte-identical
  to A5 baseline.
- No new `abort()` / `__attribute__((weak))` / `*_stubs.cpp` files.
- Desktop smoke still works.

## What's likely needed

By F1 most kernel code should already work (D4 brought up the boot
path; A5 closed the codegen gap). Remaining concerns:

- Renderer port: the title-screen renderer in D4 was the bare SDL3
  clear+swap loop. Geyser Rock needs the actual OpenGL renderer
  port from `game/graphics/opengl_renderer/` running. This is the
  biggest piece of real work in F1.
- Collision detection bytecode is heavy on the mips2c-translated
  functions; verify those execute correctly under the A5 emitter.
  The mips2c TUs in the build already cross-compile.
- Audio (handled in F2) may need to be at least loaded for
  triggers; muted-but-running is acceptable here.

## f1_run.sh

- Build + install + launch
- Drive the input script through `adb shell input` events at known
  timestamps (or via the listener socket if it's available)
- Capture 120 sec of logcat into `.autoport/reports/F1-boot.log`
- `adb pull` the game-state dump (the desktop build supports
  `--dump-state-frame N` or equivalent; if not, add a custom log
  line that emits `(format ...)`-style state at known frames)
- Screencap at frame 600 → phash against
  `.autoport/reports/F1-geyser-rock-frame-600.png` reference

## Reality check toolkit

- `adb shell input` for synthetic gameplay input
- Game-state probe via listener socket or instrumented log emission
- Screencap phash against checked-in reference frame
- `.autoport/lib/trace_diff.py` against desktop oracle
- Shim governance, codegen-lock, CGO baseline checks

## Cost expectation

Heavy phase. Renderer port alone is probably 3-5 hours.
Determinism test scaffolding 1-2 hours. ~$60-100.
