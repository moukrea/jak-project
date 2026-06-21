# Phase Gd2-particles-sun — restore the 3D world-particles / stars / sun corona on arm64 (un-noop sp-process-block-3d)

## The defect (owner + Grender-audit D2/D4)
Owner: the original shows particles, stars, and a real sun; on the device they're absent and **the sun is a "weird halo."** Audit root cause (single): the **3D world-particle processor `sp-process-block-3d` is deliberately noop'd on arm64** (`game/mips2c/mips2c_table_jak1_arm64.cpp:452-457` — "deliberately NOT enabled; it SIGSEGVs at frame ~190"). That builder produces the 3D ambient particles/sparks/stars AND the sun **corona/glow** (`group-sun`, `weather-part.gc:482`, defparts 1950/1951/1952, textures middot/starflash2/sun-glow). With it noop'd, only the additive sky-quad sun survives = the "halo." 2D sparticles already work. Note: Ghalo/Ghalo-sun did NOT touch this — this is the real fix for the sun + particles.

## Mandate
1. **Fix the frame-~190 SIGSEGV first (the reason it was noop'd).** Re-enable `sp-process-block-3d` in the arm64 allowlist on a branch, reach frame ~190, and capture the crash. Diagnose the arm64 mechanism (almost certainly the recurring class: a `#f`/upper-32 compare misfire, a wild launcher/launch-control pointer, or a low-base DMA — cf. [[arm64-mips2c-fnull-guard]], [[project-cgo-rebuild-sparticle-regression]], [[gnd-state]]). Fix the real cause so the 3D particle builder runs without crashing.
2. **Un-noop the builder** (`mips2c_table_jak1_arm64.cpp` — add `sp-process-block-3d` and any required sub-builders to `kSet`/the allowlist) + the 3-part renderer pattern if a renderer TU/bucket is also gated ([[gwater-state]]: kSet + CMakeLists TUs + register bucket/GLES gate).
3. **x86-first:** x86 already renders these; your change must be arm64-gated and leave x86 byte-identical.

## Verify (deterministic, NOT screenshots)
- Per-bucket census on device vs x86 at the title/vista beat: the 3D-particle / `group-sun` corona draws now show **>0 tris on device** (matching x86 within tolerance), where they were 0 before. The sun is a real disc+corona, not a bare halo (measured by the corona sparticle bucket drawing).
- Regression: no crash at frame ~190 or later (0 sig 4/6/11); device still boots + reaches gameplay; x86 still `link finish: logo`.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. Golden READ-ONLY/pristine; temp dumps removed. `deploy_verify.sh eae4df44` PASS. After any failing run, `bash .autoport/restore_knowngood_device.sh`. Device may need the owner to keep the phone unlocked. NO screenshot/video grind.

## Validator (`phase-Gd2-particles-sun.sh`) PASS requires
1. `.autoport/reports/Gd2-particles-sun/bucket-census.txt`: device vs x86 per-bucket tris for the 3D-particle / sun-corona buckets — BEFORE (device 0) and AFTER (device >0, matching x86) — with `RESULT: 3D PARTICLES + SUN RENDER`.
2. A real code change (`game/mips2c/**` un-noop + the SIGSEGV fix; possibly `game/**`/`goal_src/**`); fix-summary ≥60 lines naming the frame-190 arm64 crash mechanism + the fix + the un-noop; temp dumps removed; golden git-clean.
3. x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASS; no crash at frame ~190+ (0 sig 4/6/11); reaches gameplay.

## Max settings
`max_turns: 1500`, `max_retries: 4`.
