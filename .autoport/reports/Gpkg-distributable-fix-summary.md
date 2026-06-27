# Gpkg-distributable — fix summary

**Goal (owner directive 2026-06-27, REVISED — do LAST).** Keep the PC build.
Ship ONE self-contained jak1 APK that bundles the full PC-extracted runtime
assets COMPRESSED, and decompresses them once on FIRST LAUNCH (progress UI,
version-stamped / idempotent). No ISO file picker, no on-phone asset extractor
(that idea was scrapped). Packaging/UX only — goal_src stays 1-to-1.

## Why this was a re-run (the prior false-green)

The first pass got the *mechanism* right but shipped the wrong *content*. Its
`build_asset_bundle.sh` packed the on-disk staging dirs
`android/app/src/jak1/assets/{iso_data,fr3}`. Those staging dirs had drifted:

- `assets/fr3` was the **slim** fast-iteration subset — only **4 of 26** fr3
  texture packs (GAME, intro, title, village1).
- `assets/iso_data/jak1` carried the **stale June-11** CGO/DGO code set, predating
  many later arm64 codegen fixes.

The APK booted, but with assets DROPPED the main-menu orange tint backdrop
rendered as a broken narrow band with the blue night sky bleeding through the
sides (owner screencap `reports/Gregress-menu-overlay/device-105736.png`). The
hardened validator now requires the bundle to equal the FULL PC build AND
requires verified in-game RENDERING (the menu tint), not just boot.

## Root cause

Staging dirs drift. The bundle must be assembled from the *authoritative build
outputs*, not from a hand-maintained staging copy that can silently go slim/stale.
There was also a correctness subtlety: the device is arm64, so the CGO/DGO must be
the **arm64-compiled** set, internally consistent with the HEAD `libgk.so` — not
the x86 oracle in `out/jak1/iso`, and not an older arm64 build (mixed-build SIGILL
risk, the owner's #1 "no mixed builds" rule).

## The asset layout (what "full + consistent" means here)

- `out/jak1/iso/` = 321 files: **293** arch-independent data files
  (STR/VAG/TXT/VIS/…, identical across x86/arm64 builds) + **28** `*.CGO`/`*.DGO`
  (the x86 oracle copies live here).
- `out/jak1-arm64-full/iso/` = the **28 ARM64-compiled** CGO/DGO, built in one
  internally-consistent pass by `.autoport/build_arm64_full_consistent.sh`
  (June 26, after the last goalc codegen change June 26 03:31 — verified
  consistent with HEAD; Gledge/Gdeath since then touched only libgk runtime, not
  codegen or the linker ABI).
- `out/jak1/fr3/` = the **full 26** renderer texture packs (all levels).

Full consistent bundle = 293 data + 28 ARM64 code (overlaid) + 26 fr3 = **347**.

## The fix (packaging only)

`android/build_asset_bundle.sh` rewritten to:

1. Assemble from the authoritative outputs above into a **symlink farm** under
   `out/jak1-bundle-stage/` (`zip` dereferences symlinks and stores real content,
   so the ~1.6 GiB set is packed with no multi-GiB intermediate copy — PC disk is
   tight). The farm always points at the current build outputs, so the bundle
   can never drift to a stale staging copy again.
2. **HARD-FAIL guards** (the false-green guard):
   - iso staged count must == full `out/jak1/iso` (321);
   - fr3 count must == full `out/jak1/fr3` (26) and must be `>= 26` (slim guard);
   - `KERNEL.CGO` content must == the arm64 build **and** must `!=` the x86 oracle
     (mixed-build guard).
3. Bump bundle **version 1 -> 2** so devices that ran the slim v1 re-decompress.
4. Fixed a `sort | head` SIGPIPE under `set -o pipefail` (broke the Gradle task);
   replaced with a single-pass `awk` max-mtime in the staleness check.

`android/app/build.gradle.kts`: updated the `bundleJak1Assets` comment to describe
the new authoritative-output sourcing. `LoaderActivity.java` was already correct
and is unchanged: it streams the zip from the APK, maps `iso_data/<game>/*` and
`fr3/* -> out/<game>/fr3/*`, version-stamps for idempotency, pre-wipes on a
version change, StatFs low-storage pre-check, per-entry CRC32, file-count + byte
integrity, stamp written last.

## Verification (device eae4df44, fresh install — no unpacked data)

- **Bundle**: 347 files, `version=2`, raw 1,639,349,155 B -> zip 1,145,911,923 B
  (69.9% via DEFLATE -6). Ships all 26 fr3 + the arm64 CGO/DGO (KERNEL.CGO
  c0c9bab4…, != x86 oracle 0b2d5fcc…).
- **APK**: 1.14 GiB, the zip Stored (noCompress, not re-deflated); libgk
  build==APK==device (babe446a). Clean repackage removed ~950 MB of AGP
  incremental dead bytes.
- **First run**: progress UI captured ("Decompressing game data… 86% 1,32 GB" +
  determinate bar); StatFs precheck ran ("storage ok: need 1,60 GB, have
  3,67 GB"); "asset bundle decompressed: 347 files, 1639349155 bytes in 56253ms
  (version=2)"; on-device `iso_data/jak1=321`, `out/jak1/fr3=26` (COMPLETE);
  booted (kernel "play", InitMachine 0, frame 9780+, 0 crashes); title renders.
- **Menu render gate**: reached the MAIN MENU; the orange tint backdrop renders
  full-width and uniform. Objective vs oracle + regression — backdrop tint
  warmth (R-B) across 8 bands: device min +88 / **0 blue bands** ~ oracle min
  +101 / 0 blue bands; regression min -71 / **2 blue bands**. Device matches the
  oracle; the owner-reported menu defect is FIXED.
- **Second run**: "asset bundle already unpacked (version=2) — skipping
  decompress, data ready" in 3s; booted directly (idempotent).
- **Error handling**: low-storage StatFs precheck + per-entry CRC32 + count/byte
  integrity + crash-tolerant stamp-last + path-traversal guard.
- **Gates**: goal_src 1-to-1 (clean); `.autoport/gold` pristine; deploy_verify
  eae4df44 PASS.

## Note on the MIUI fresh-install gate

On this Redmi, MIUI allows adb `pm install -r` *updates* but blocks *new* USB
installs (USER_RESTRICTED). The fresh install required approving MIUI's
`AdbInstallActivity` dialog once (tapped Install + "remember my choice" so future
re-installs don't prompt). Updates over the now-installed package are unaffected.

## Files changed

- `android/build_asset_bundle.sh` — rewritten (authoritative-output assembly +
  completeness/consistency guards + version 2 + SIGPIPE fix).
- `android/app/build.gradle.kts` — comment update only (bundleJak1Assets sourcing).
- (LoaderActivity.java unchanged — already correct.)
- goal_src: untouched (1-to-1).
