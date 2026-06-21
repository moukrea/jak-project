# Phase Gconsolidate — build ONE consistent HEAD build with ALL the fixes, deploy it, and LEAVE it on the device

## Why
Many fixes have landed in HEAD across separate phases — menu placement (tint), ND-logo + title halos, the cutscene-clock real-time decoupling (Gd1), Jak-visible-in-cinematic (Gd3), and 3D particles/stars/sun-corona (Gd2). BUT each phase's validator **restores the f1c known-good build afterward**, so the **device is NOT currently running any of these fixes** — the owner has been looking at the old build. This phase makes the cumulative result real on the device so the owner can SEE it, and verifies all fixes coexist on one consistent build (no fix interaction/regression).

## Mandate
1. **Build ONE fully-consistent current-HEAD arm64 build** — the 28-file CGO/DGO set + libgk.so all from HEAD (use `.autoport/build_arm64_full_consistent.sh` / the consistent-build path). All the committed fixes are in HEAD; do NOT mix builds.
2. **Deploy it** to the device (CGOs → files/iso_data via run-as keeping `.extracted_v1`; libgk via APK reinstall). `deploy_verify.sh eae4df44` must PASS (device provably runs fresh HEAD: build==APK==device, built-after-source).
3. **Verify ALL fixes hold together on this one build** (deterministic, x86-first where applicable — reuse the existing per-fix tooling):
   - cinematic plays at real-time (cutscene clock ~60Hz wall-clock, Gd1);
   - Jak visible in the cinematic (merc draws >0, Gd3);
   - 3D particles/stars + sun corona render (sp-process-block-3d buckets >0, Gd2);
   - menu matches the original (overlay-masked main-menu state, Gmenu);
   - boots + reaches gameplay, no sig 4/6/11.
4. **LEAVE this consolidated build on the device — do NOT restore known-good at the end.** The whole point is the owner sees the fixes. (The restore button remains available if ever needed.)

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. Original golden READ-ONLY/pristine. Device may need the owner to keep the phone unlocked for the deploy + captures. NO screenshot/video grind — verify via the deterministic per-fix signals.

## Validator (`phase-Gconsolidate.sh`) PASS requires
1. `deploy_verify.sh eae4df44` PASS (device runs the fresh consistent HEAD build) — and the device is LEFT on it (validator does NOT restore known-good).
2. `.autoport/reports/Gconsolidate/holds.txt` summarizing the deterministic verdicts that ALL the fixes hold on this single build: cutscene-clock real-time, Jak-visible, 3D-particles+sun render, menu-matches-original, crash-free reach gameplay — with `RESULT: ALL FIXES HOLD ON CONSOLIDATED BUILD`.
3. No new sig 4/6/11 in a fresh long routed-logcat (frame ≥ 10500, foreground=org.opengoal.gk.jak1); x86 still `link finish: logo`.

## Max settings
`max_turns: 1500`, `max_retries: 4`.
