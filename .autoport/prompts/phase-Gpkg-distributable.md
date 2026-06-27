# Phase Gpkg-distributable — self-contained APK: PC-built assets bundled COMPRESSED, decompressed at first run

## Goal (owner directive 2026-06-27, REVISED — do LAST after branding)
Keep the **PC build** (extracting/decompiling assets on-device would be a massacre — scrapped). Instead
the **final compiled APK bundles all runtime assets COMPRESSED**, and **decompresses them on first
launch** into the app data dir. No ISO picker, no on-device extractor. Result: one self-contained APK
the owner builds on PC; first run unpacks the assets once, then it just plays.

## Scope / design
- **Build (PC, unchanged):** the host pipeline extracts the jak1 runtime data into `out/jak1/` (the
  CGO/DGO/fr3/texture set) exactly as today.
- **Bundle the FULL asset set COMPRESSED in the APK:** package that runtime data set into a compressed
  archive (single archive or per-asset; pick a fast decompressor — e.g. zstd/zip/xz) shipped inside the
  APK. **CRITICAL — bundle the COMPLETE asset set, identical to the full PC build (`out/jak1`), NOT the
  `slimIso`/assets-slim subset.** A prior attempt false-greened by bundling a slim/partial set: it
  booted but DROPPED assets, breaking the menu orange tint backdrop on device. The decompressed set on
  device MUST equal the full build's file list/count.
- **Verify RENDERING, not just boot:** after first-run decompression, confirm the game actually RENDERS
  correctly — at minimum the main menu (the orange tint backdrop must render, not a broken block) plus a
  gameplay frame — via an oracle/state check, not just "reached link finish". Boot-only is NOT enough.
- **First-run decompression UI:** on launch, if the data dir is absent/incomplete, show a clean
  one-time "Setting up… / Decompressing assets" screen with a **progress bar**, decompress the bundled
  archive into the app-private data dir the runtime reads (the same fakeiso data root), then boot.
- **Idempotent:** version-stamp the unpacked data; on later launches detect it and boot straight to the
  game (no re-decompress). Re-decompress only if the stamp/version changed (new APK).
- **Integrity + space:** verify the unpack (count/size or hash) and handle low-storage with a clear error.

## What changed vs the earlier draft
SCRAPPED: SAF ISO picker, on-device OpenGOAL extractor/decompiler, "ship engine-only / no assets". The
APK now DOES bundle the (PC-extracted) assets, compressed. This is the owner's project / owned copy.

## Validator PASS requires
1. The built jak1 APK contains the runtime assets as a COMPRESSED bundle (not raw uncompressed dirs);
   document the archive format + compressed vs raw size.
2. On a device with NO unpacked data: first launch shows the decompression/progress UI, unpacks to the
   data dir, and the game boots (`link finish: logo` / in-game). SECOND launch detects the unpacked,
   version-stamped data and boots directly (no re-decompress).
3. Low-storage / corrupt-bundle error handling. Report `.autoport/reports/Gpkg-distributable/report.txt`
   with `RESULT: SELF-CONTAINED APK — BUNDLED COMPRESSED ASSETS DECOMPRESS AT FIRST RUN`.
4. goal_src 1-to-1 (packaging/UX only); fix-summary ≥60 lines; `.autoport/gold` pristine;
   `deploy_verify.sh eae4df44` still PASS (engine unaffected).

## Locks: ANDROID_SERIAL=eae4df44 only; .autoport/gold READ-ONLY.
## Max: max_turns 1500, max_retries 4.
