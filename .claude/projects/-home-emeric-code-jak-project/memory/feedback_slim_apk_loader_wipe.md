---
name: feedback_slim_apk_loader_wipe
description: Installing the SLIM jak1 APK can make LoaderActivity WIPE iso_data+fr3 and fail; recover with a full-bundle APK.
metadata:
  type: feedback
---

Deploying via the **slim** APK (`-PslimIso=true`) is dangerous when its bundled
`assets/bundle/manifest.properties` `version` differs from the device's
`files/.asset_bundle_stamp`. On the next `LoaderActivity` launch the loader
(`unpackBundleIfNeeded`) sees a version MISMATCH → `deleteRecursive` wipes
`files/iso_data/<game>` (321 files: 293 data + 28 CGO/DGO) AND `files/out/<game>/fr3`
(26 fr3) → then throws `FileNotFoundException: bundle/jak1_assets.zip` because the slim
APK has no zip → boot dies at the loader (0 frames, not a native crash). A plain CGO
re-push can't recover it (the whole dir is gone).

**Why:** loader skips extraction ONLY iff stamp content == APK manifest `version`. Slim's
`assets-slim/bundle/manifest.properties` is a stale static manifest (e.g. v2) while the
real full bundle is v3 (`android/build_asset_bundle.sh BUNDLE_VERSION`). Mismatch → wipe.

**How to apply:** for a CONSISTENT boot-band change (pckernel/engine CGOs), deploy the
**FULL** APK, not slim: delete `android/app/src/jak1/assets-bundled/bundle/jak1_assets.zip`
(force fresh), `cd android && ./gradlew assembleJak1Debug` (no slim → `bundleJak1Assets`
packs 293 data + your arm64 CGOs from `out/jak1-arm64-full/iso` + 26 fr3, version 3),
`pm install -r`, launch loader → clean extract (writes stamp=3), then sha-verify
`files/iso_data/jak1/KERNEL.CGO == out/jak1-arm64-full/iso/KERNEL.CGO` + `deploy_verify`.
Reusable harness: `.autoport/gdynrs_run.sh recover`. Related: [[game_cgo_rebuild_unsafe]],
[[stale_asset_dgos]]. Also: x86 data rebuild = goalc `(mi)` (full repack), NOT
`(build-game)` (code objects only — leaves DGOs stale).
