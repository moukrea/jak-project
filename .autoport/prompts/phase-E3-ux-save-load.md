# Phase E3 — UX: save/load (binary-identical to desktop)

## Status

**Authored 2026-05-21 by the supervisor**, replacing the May-21
placeholder. Same-behavior contract: a save file produced on Android
must be byte-identical to one produced by the desktop x86_64 build
under the same game-state. The whole point is portability — saves
must move between platforms losslessly.

## Bucket

E — UX corrections (REDESIGN.md §8).

## Goal (concrete, device-verifiable)

1. The GOAL kernel's `kmemcard` subsystem cross-compiles for arm64
   Android and links into libgk.so without stubs.
2. Save target is `filesDir` (`/data/data/org.opengoal.gk.jak1/files/saves/`)
   — Android-appropriate path, no SD-card or external-storage
   dependency.
3. **Binary identity**: a save produced by the Android build at a
   deterministic checkpoint (e.g. immediately after `link finish:
   logo` with a fixed RNG seed) is byte-identical to the desktop
   x86_64 save produced under the same conditions.
4. **Load round-trip**: loading the Android-produced save on the
   desktop x86_64 build, or vice versa, results in identical
   subsequent game-state for at least 1000 frames (trace-diff).

## Hard rules — same-behavior contract

- Save file format byte-identical to desktop (no Android-specific
  header / framing). If the platform needs different metadata,
  that lives outside the save payload.
- Shim governance from E1: every function in `android/*.cpp` carries
  a `SHIM_KIND:` tag. A save-IO shim qualifies as
  `PLATFORM_FEATURE` (filesDir vs PS2 memory-card path).
- `goalc/` codegen + classifier byte-identical to A5 close.
- x86 + arm64 CGOs byte-identical to A2 / A5 baselines (E3 must
  not re-emit bytecode).
- No new `abort()` / `__attribute__((weak))` / `*_stubs.cpp` files.
- Desktop `build-x86/game/gk` still reaches `link finish: logo`.

## What's likely needed

- `game/kernel/common/kmemcard.cpp` already builds in the Android
  archive (the D4 commits added it via android_arm64_kernel target).
  Confirm with `nm --defined-only build-android/lib/arm64-v8a/libgk.so | grep kmemcard`.
- Replace the PS2 memory-card I/O calls (`sceMcRead`, `sceMcWrite`,
  etc.) with Android-side wrappers that target filesDir. Each new
  function gets a `SHIM_KIND: PS2_HW_EMULATION` tag (we're
  substituting for absent PS2 hardware) and uses the exact same
  binary file format the desktop build uses.
- The desktop build's save path is in
  `game/kernel/common/kmemcard.cpp::psstore_init` (it stubs to a
  local-file backend). Mirror that exactly on Android.

## e3_run.sh

- Boot the APK
- Trigger a save at the deterministic checkpoint (need a way to
  drive the GOAL save command — likely via the listener socket or
  a debug command injected through the SDL event queue)
- `adb pull` the resulting save file
- Compare its SHA-256 against
  `.autoport/reports/E3-desktop-save-reference.sha256`
- If desktop reference doesn't exist, generate it first on the
  desktop build under the same conditions

## Reality check toolkit

- `sha256sum` for byte-identity check
- Round-trip: take Android save, run it through `build-x86/game/gk`
  with `--load <save>`, verify boot + 1000 frames produce same
  trace as desktop-native session
- `.autoport/lib/trace_diff.py` for the round-trip step
- Shim governance scan, codegen-lock diff, x86+arm64 CGO baselines

## Cost expectation

Medium. Cross-compile is mostly done; the work is binary-format
fidelity + driving the save command from a script + producing
the desktop reference save. ~2 hours / $20-30.
