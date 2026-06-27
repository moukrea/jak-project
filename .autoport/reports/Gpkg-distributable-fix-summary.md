# Gpkg-distributable — fix summary

**Goal (owner directive 2026-06-27, REVISED).** Keep the PC build. Make the
*final* APK a self-contained, owned-copy product: bundle the PC-extracted jak1
runtime assets **compressed** inside the APK, and **decompress them once at first
run** behind a progress UI, version-stamped and idempotent. No file-chooser, no
decompiler/transcoder running on the phone (that earlier draft was scrapped —
"would be a massacre"). Packaging + UX only; engine and goal_src stay 1-to-1.

## Why the previous attempt failed

Validator said `no report.txt`. Attempt 1 had pivoted toward the *scrapped*
on-phone-extractor design and left only dead scaffolding:
- a `OG_ANDROID_EXTRACTOR` block added to root `CMakeLists.txt` (cross-builds the
  decompiler+goalc for Android — the scrapped path), OFF by default but engine-tree
  pollution all the same;
- `__ANDROID__` guards added to `common/cross_os_debug/xdbg.cpp` purely so that
  scrapped extractor's `common` sub-build would compile;
- a 282-file `build-android-extract/` CMake config dir, staged into git;
- and **no** report / no actual packaging change.

The current `build-android/lib/arm64-v8a/libgk.so` (mtime 07:50) was built *before*
those edits (08:11), so reverting them is consistent with the deployed engine.

## What I did

### 1. Reverted the scrapped-approach cruft (engine/build back to pristine HEAD)
- `git checkout HEAD -- CMakeLists.txt common/cross_os_debug/xdbg.cpp`
- removed `build-android-extract/` and added it + the bundle artifact to
  `.gitignore`. Engine is now provably unaffected (deploy_verify chain PASS).

### 2. PC build step — `android/build_asset_bundle.sh` (new)
- Packs `app/src/jak1/assets/iso_data/jak1` + `app/src/jak1/assets/fr3` into ONE
  DEFLATE archive `app/src/jak1/assets-bundled/bundle/jak1_assets.zip` plus a
  `manifest.properties` (version, file_count, raw_bytes, zip_bytes).
- Entry layout is the on-device *relative* layout: `iso_data/jak1/*` and `fr3/*`
  (LoaderActivity remaps `fr3/*` → `out/jak1/fr3/*`).
- Idempotent: repacks only when the zip is missing/older than any raw input or the
  version changed — so it is a ~1 s no-op on every subsequent build.
- `zip -6` (balanced): the STR/VAG/SBK/MUS payload is audio-heavy ADPCM and barely
  compresses, so a higher level buys little for a lot more time.

### 3. APK packaging — `android/app/build.gradle.kts`
- jak1 assets srcDir → `assets-bundled/` (the compressed archive), **not** the raw
  `src/jak1/assets` dirs (kept on disk only as the bundle's build input). `-PslimIso`
  fast-iteration build preserved (fr3-only, no payload).
- `androidResources.noCompress = ["zip"]` so AGP **stores** the already-DEFLATE'd
  archive verbatim — re-compressing a ~1 GB compressed file buys nothing and risks
  the mergeAssets/package GC death-spiral the old raw-payload build fought.
- Registered `bundleJak1Assets` (Exec → the script) and wired it as a dependency of
  the `merge*Jak1*Assets` tasks, gated off for `-PslimIso`.

### 4. First-run decompression UI — `LoaderActivity.java` (rewritten)
- Reads `bundle/manifest.properties` for version + raw-byte total + file count.
- **Idempotent / version stamp:** `<filesDir>/.asset_bundle_stamp` holds the bundle
  version; if present and matching, boot straight through (no unpack). A bumped
  version (new APK) forces a single clean re-decompress.
- **Determinate progress bar:** a real horizontal `ProgressBar` (permille of the
  manifest raw-byte total) + "Decompressing game data… NN%" status, updated from a
  background worker thread (UI thread would ANR).
- **Decompress:** streams the archive from the APK via `AssetManager.open(...,
  ACCESS_STREAMING)` → `ZipInputStream` (the ~1 GB archive is never materialised in
  RAM), writing each entry to its on-device home.
- **Low-storage pre-check:** `StatFs` free bytes vs raw_bytes × 1.05 → clean error
  instead of filling the disk mid-write.
- **Integrity:** `ZipInputStream.closeEntry()` validates each entry's CRC32 against
  the archive (corrupt/truncated → throws); after the loop the written file count +
  byte total are cross-checked against the manifest.
- **Crash-tolerant:** the stamp is written LAST, only after a fully-verified unpack,
  so a kill mid-unpack is "not done" and the next launch wipes + redoes it.
- Path-traversal guard rejects any entry resolving outside filesDir.

## Measured result

| metric | value |
|---|---|
| raw runtime assets | 1,441,122,917 B (1.34 GiB, 325 files) |
| compressed bundle (zip) | 950,871,866 B (907 MiB) = **66.0% of raw**, ~490 MB saved |
| final jak1 APK | 1,024,325,765 B (977 MiB) |
| first-run decompress | 325 files / 1,441,122,917 B in **40,659 ms**, integrity OK |
| first-run boot | reached `link finish: logo`, 43 GLES shaders, Adreno 618, frame 240 |
| second run | `already unpacked (version=1) — skipping decompress`; 0 re-decompress |
| deploy_verify (eae4df44) | PASS — device runs fresh HEAD b2208f88d libgk.so |

## Verification

`bash .autoport/reports/Gpkg-distributable/run_device_test.sh` drives the whole
cycle on eae4df44 (build → prove bundle stored-compressed in APK → install →
wipe-then-first-run decompress+boot → second-run skip → deploy_verify). All
artifacts are saved under `.autoport/reports/Gpkg-distributable/` (10–23 + 16 PNG).
I read the raw logcat + APK listing + on-device state myself rather than trusting
the harness summary; the on-device count check was re-captured correctly into
`19b-firstrun-ondevice-verified.txt` after a shell-quoting bug was fixed in the
driver.

## Scope / 1-to-1

- goal_src: **0** files changed.
- Engine: libgk.so unchanged (deploy_verify build==APK==device chain PASS).
- `.autoport/gold`: untouched (pristine).
- Only packaging/UX files changed (script, gradle, LoaderActivity.java, .gitignore).
