# Grecharged-grass-overhang6 — Delivery (owner real install flow)

Date: 2026-07-14
Device: Redmi Note 9 Pro (adb eae4df44, arm64), org.opengoal.gk.jak1

## Result: PASS (all 7 steps)

## libgk.so chain (deploy_verify.sh eae4df44 jak1)
- build == APK == device libgk.so sha (short): 3b67c9252c46f3ac
- "libgk.so newer than newest source": OK
- HEAD: 57acec55a
- DEPLOY-VERIFY PASS

## grassbake (GBK7) sha256 chain — build == archive == device
- bf5f24faf78a5858bdadf6dab04219e50cc87ff79c8b9604f0b9927e03b20126
  - build : out/jak1/fr3/training.grassbake (2031035 bytes)
  - archive entry: out/artifacts/jak1_assets.zip -> fr3/training.grassbake
  - device: /storage/emulated/0/OpenGOAL/jak_1/assets/fr3/training.grassbake
    (bf5f24faf78a5858bdadf6dab04219e50cc87ff79c8b9604f0b9927e03b20126)

## Owner-extraction equivalence (unchanged entries, archive == device)
- fr3/training.fr3 : 17710ec0b23d237b2ace0e83141aa666fd5d768a7943f8352ab0370f62ba0252  MATCH
- fr3/GAME.fr3     : e79b6a8465eca343c0b7c38f0f2a98685b6d25f66f3a2ded96929a77951e9c3a  MATCH

## APK installed (update -r)
- android/app/build/outputs/apk/jak1/debug/app-jak1-debug.apk (built 15:20, 195864651 bytes)
- Install: Success (adb install -r -i com.android.vending)

## Boot proof (precomputed path) — warp training-start @ pos (-134.5 36 205.5)
- external asset mode: gameRoot=/storage/emulated/0/OpenGOAL/jak_1
- [LEVEL-WARP] get-continue-by-name("training-start") -> #x1da1b04 (found)
- [recharged-grass] PLACE-TIME mode=precomputed total=361ms instances=807956
- LIVE fallback / PRECOMPUTED unavailable: NONE
- mCurrentFocus=org.opengoal.gk.jak1 (MainActivity) throughout
- crash signal 11/6/4: NONE (only gk_install_sigsegv_diag installer line, not a crash)

### GOVERHANG6 census line (exact, from device):
[recharged-grass] GOVERHANG6 zones: lean_tagged=65842 lean_twins=65842 (band 0.90m) z2_strip=32354 z3_fall=92928 (layers=2) comb_repl=452 curl_blades=2048 curl_tilt0=1871 plane_capped=7953 plane_dropped=1108
- z2_strip=32354 > 0  OK
- z3_fall=92928  > 0  OK

## Artifacts
- .autoport/reports/Grecharged-grass-overhang6/delivery-boot-logcat.log
- .autoport/reports/Grecharged-grass-overhang6/delivery.md

## Anomalies
- setprop NAME '' (empty clear) errors ("usage: setprop NAME VALUE") — harmless; the stale
  warp.pos was intentionally reused as a valid grass-overhang vantage; warp NAME re-armed to
  training-start. No functional impact.
- The 90s boot WITHOUT a warp lands at title/logo-loop (grass level not loaded), so PLACE-TIME
  and the GOVERHANG6 census do not fire on a bare boot; a training-start warp is REQUIRED to
  exercise the precomputed grass place path. Second capture (warped) produced all required lines.
