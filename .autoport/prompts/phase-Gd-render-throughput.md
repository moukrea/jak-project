# Phase Gd-render-throughput — lift the device gameplay framerate (the remaining "slow")

## The defect (owner + Grender-audit D1)
The cutscene-clock is fixed (cinematics now real-time), but **gameplay is still render-bound on the Adreno 618**: the village flythrough is **646 draw-calls / 536k tris per frame → ~20 fps** (x86 holds 60). That's the residual "everything's slow" the owner feels in-game. The game clock is correct (real-time), so this is purely render throughput.

## Mandate — reduce per-frame GPU/driver cost on the arm64/GLES path, x86 byte-identical
Profile the heavy beat (village flythrough) on device and cut the per-frame cost without dropping content:
- **Draw-call reduction / batching:** 646 draws/frame is the prime suspect. Merge/batch draws (same shader/state), reduce redundant GL state changes / uniform uploads / buffer rebinds in the arm64 renderer path (`android/`, `game/graphics/opengl_renderer/**`).
- **Culling:** skip off-screen / fully-occluded buckets or fragments where the original would too.
- Adreno-specific: avoid per-draw map/unmap stalls, reduce small-draw overhead, check primitive-restart/index-buffer usage.
- Do NOT remove content (particles/sun/Jak/shadows must still render — no visual regression). The change must be Android/arm64-gated; x86 stays byte-identical (still 60 fps, `link finish: logo`).

## Verify (deterministic, NOT screenshots)
- A35-RENDER on the village-flythrough beat: **sustained fps rises measurably** from the ~20 baseline (target **≥28 fps**, and/or **draw-calls/frame meaningfully reduced** from 646) — dump BEFORE/AFTER on device.
- No visual regression: the per-bucket census still shows the content buckets (tfrag/tie/merc/particle/sun) drawing (compare to the Gd2 consolidated census).
- No crash (0 sig 4/6/11); reaches gameplay; x86 unchanged.

## Locks / delivery
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. Golden READ-ONLY/pristine; temp dumps removed. `deploy_verify.sh eae4df44` PASS. After any failing run, `bash .autoport/restore_knowngood_device.sh`. Device may need the owner to keep the phone unlocked. NO screenshot/video grind.

## Validator (`phase-Gd-render-throughput.sh`) PASS requires
1. `.autoport/reports/Gd-render-throughput/fps.txt`: device BEFORE/AFTER on the heavy beat — sustained fps up to ≥28 (or draw-calls/frame reduced ≥25%) — with `RESULT: GAMEPLAY FPS IMPROVED`.
2. No-visual-regression note: content buckets still drawing (cite per-bucket tris).
3. Real code change (`android/**` or `game/graphics/**`); fix-summary ≥60 lines naming the per-frame cost reductions; temp dumps removed; golden git-clean.
4. x86 still `link finish: logo`; `deploy_verify.sh eae4df44` PASS; no crash; reaches gameplay.

## Max settings
`max_turns: 1500`, `max_retries: 3`.
