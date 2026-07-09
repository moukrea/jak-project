---
name: project_jak2_slim_apk_deploy_model
description: jak2/jak3 deploy = SLIM APK (libgk only) + CGOs pushed to files/iso_data; rebuild libgk => MUST reassemble+reinstall slim APK or deploy_verify false-FAILs "STALE .so"
metadata:
  type: project
---

jak2 (and jak3) ship on-device via a **SLIM APK + external asset push**, NOT a
self-contained APK. The device already has the full jak2 bundle extracted to
`files/iso_data/jak2/` (marker `files/.asset_bundle_stamp_jak2`). Deploy pipeline
(`.autoport/gjak2polish_deploy.sh`):
- build arm64 CGO set -> `out/jak2-arm64-full/iso` (151 CGO/DGO; built by
  `.autoport/build_arm64_full_consistent_jak2.sh`, then it RESTORES the x86 oracle to `out/jak2/iso`).
- assemble SLIM APK: `cd android && ./gradlew assembleJak2Debug -PslimIso=true`
  (bundles libgk + manifest.properties ONLY — no `jak2_assets.zip`; the APK's
  `assets/bundle/` holds just `*.manifest.properties`).
- `adb install -r -d -t -i com.android.vending` (keeps the extracted bundle).
- push the 151 fresh CGO/DGO **and** the platform-independent `*.TXT` banks
  (from `out/jak2/iso`, e.g. COMMON.TXT/SUBTI2.TXT — menu labels live here) to
  `files/iso_data/jak2/` via run-as, sha256-verified per file.

**Two independent deploy gates** (both must pass; owner is final):
- `.autoport/lib/deploy_verify.sh eae4df44 jak2` — libgk chain build==APK==device.
- `.autoport/lib/deploy_verify_assets.sh eae4df44 jak2` — 151/151 on-device
  CGO/DGO byte-identical to `out/jak2-arm64-full/iso` + newer than goal_src/jak2.
close_gate (orchestrator) only runs the libgk `deploy_verify` + a boot check; run
deploy_verify_assets yourself to prove the CGO fixes (menu/progress/fps/aspect) landed.

**THE TRAP** (caused Gjak2-polish attempts 1+2 "stuck at CLOSE-GATE/deploy"):
after a libgk rebuild you MUST reassemble the slim APK AND reinstall, else
`deploy_verify` false-FAILs `build libgk.so != APK-bundled libgk.so — STALE .so`.
The failure is a stale SNAPSHOT of ordering (libgk built after the APK was last
assembled), not a code bug — just complete the reassemble+reinstall+push cycle.
See [[feedback_deploy_landing_guard]], [[project_build_pipeline]],
[[feedback_device_ground_truth_no_mixing]]. Serial ALWAYS eae4df44
([[reference_real_device]]); crouch fix = arm64 mips2c allowlist
`(method 17 collide-cache)` + nav-engine 17/18/20/21 REAL in mips2c_table_jak1_arm64.cpp.
