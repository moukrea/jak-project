# Phase Gpkg-distributable — self-contained APK: first-launch ISO picker + on-device asset extraction

## Goal (owner directive 2026-06-27, do LAST — after branding)
Anyone can take the built APK + their OWN original Jak & Daxter ISO and play — **no PC build step, no
pre-bundled copyrighted assets.** On first launch the app detects missing game data, shows a clean
onboarding UI that asks for the ISO, runs the OpenGOAL extractor ON-DEVICE to produce the runtime data,
shows progress, then launches the game. Subsequent launches skip straight to the game.

## Scope / design
- **Ship clean:** the distributable APK bundles ONLY the engine (`libgk.so`) + the extractor — NOT the
  extracted CGO/DGO/textures (those are copyrighted, and they come from the user's ISO). Today assets are
  extracted on the build host into `out/jak1/` and bundled; this phase moves extraction on-device.
- **On-device extractor:** OpenGOAL already has the `extractor`/decompiler pipeline (ISO → decompile →
  build → fakeiso data dir). Cross-compile/bundle it for Android arm64 (or expose the needed entrypoints
  in `libgk`), so it runs on the phone. This is the big piece — may need sub-phases (build the arm64
  extractor; wire it; handle the multi-minute run + storage).
- **First-launch UI (SAF):** an onboarding Activity — if the data dir is absent/incomplete, present
  "Select your Jak & Daxter (NTSC) ISO" via the Storage Access Framework file picker; copy/stream the
  ISO; run the extractor with a **progress bar + step labels**; on success mark data ready + launch the
  game; on failure (wrong/corrupt ISO, low storage) show a clear error. Validate the ISO (expected
  size/hash of the supported release) before extracting.
- **Idempotent:** detect already-extracted data (version-stamped) and skip extraction on later launches.

## OWNER INPUT NEEDED (when this phase runs)
Confirm the target: supported ISO region/version (NTSC jak1 v?), and whether the extractor should run
fully on-device (preferred for "anyone can run it") vs an adb-assisted fallback. A test ISO must be
available at the [[reference-iso-data]] path for the validator.

## Validator PASS requires
1. The distributable APK contains the engine + extractor but **NO pre-bundled copyrighted game assets**
   (assert the CGO/DGO/textures are absent from the clean APK).
2. On a device with NO extracted data, the first-launch flow: ISO picker shown → extraction runs to
   completion from the test ISO → game boots to `link finish: logo` / in-game. Second launch skips
   extraction and boots directly.
3. Clear error handling for missing/invalid ISO + low storage. Report
   `.autoport/reports/Gpkg-distributable/report.txt` with `RESULT: SELF-CONTAINED APK — ISO ONBOARDING + ON-DEVICE EXTRACTION OK`.
4. goal_src 1-to-1 (packaging/UX + extractor port, no game-logic change); fix-summary ≥60 lines; golden pristine.

## Note
Large/likely needs splitting into sub-phases when reached (arm64 extractor build → onboarding UI →
extraction run/progress → idempotent data-ready gate). Refine the breakdown at that time.

## Locks: ANDROID_SERIAL=eae4df44 only; .autoport/gold READ-ONLY.
## Max: max_turns 1600, max_retries 4.
