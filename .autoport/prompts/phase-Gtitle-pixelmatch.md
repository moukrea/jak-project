# Phase Gtitle — the title screen ("PRESS START" over Sandover) must PIXEL-MATCH the original, gated objectively.

## Why (chronological, owner directive)
Next beat after the Naughty Dog logo (Gndlogo ✓ — now matches the original on black). The owner wants the boot sequence perfect in order: SCE → ND logo → **title screen** → menu. The title beat is where the owner reported issues (level names stuck over "PRESS START", the Jak&Daxter logo's right edge, missing/misplaced elements). Gated OBJECTIVELY by `frame_compare` vs the original-build golden — NOT eyeballing.

## The golden + the proven gate pattern (reuse Gndlogo's, it WORKED)
- Golden beat: `.autoport/gold/pristine-frames/title-pressstart-f001590.png` (1280x720, from Pcompare). It shows the original title: the "JAK AND DAXTER — the Precursor Legacy" logo + "PRESS START" over the Sandover backdrop.
- The gate `.autoport/lib/frame_compare.py` + `capture_device_beat.sh` exist (Pcompare). Gndlogo established the FAIR-comparison recipe that you MUST reuse:
  1. **Recapture the golden at 2400x1080** (phone aspect) from the oracle (`/home/emeric/code/jak-original-v033` @ c4bc4d3ff): temporary env-gated auto-screenshot hook in its `opengl.cpp` at `frame_idx` anchor 1590, 2400x1080 window (`XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.RKSTQ3 DISPLAY=:0`, software-Mesa fallback), dump → `.autoport/gold/pristine-frames-2400/title-pressstart.png`, then `git -C /home/emeric/code/jak-original-v033 checkout -- .` (leave it pristine).
  2. **Touch-overlay mask** + **cross-GPU threshold calibration** in `.autoport/reports/Gtitle/mask.txt` (same format Gndlogo used: `--ignore-rect X,Y,W,H` for the D-pad/buttons/START overlay regions + a `--threshold N` calibrated to the cross-GPU floor). The title beat has MORE shaded 3D (the whole village) than the on-black ND logo, so expect more legitimate Adreno-vs-desktop edge/shading noise — calibrate honestly.
  3. **MANDATORY anti-gaming proof** (the supervisor will check this): the residual at the STRICT threshold (24) must localize to EDGES/shaded-surface NOISE in the diff image, NOT a filled content blob; golden-vs-black with your mask+threshold must still MISMATCH well above 2%; and a known defect (e.g. the level-names-over-pressstart, or village-missing) must measure far above 2%. Document these in the fix-summary.

## Frame-alignment note (harder than the on-black beat)
Unlike the ND logo (on black, load-independent), the title is a settled flythrough over the moving village. Anchor the device capture to the **"PRESS START" state** (the flythrough has settled / the title+press-start are up) via `capture_device_beat.sh` + the phase's event trigger — not a raw frame number. The 2400x1080 golden has the SAME FOV/aspect as the phone, so the village framing should align; the camera may slowly orbit, so capture at the press-start-visible moment closest to the golden's composition.

## Mandate
1. Do the fair-comparison setup (2400x1080 golden + mask + calibrated threshold + the anti-gaming proofs).
2. Capture the device title beat (ANDROID_SERIAL=eae4df44 ONLY; verify `mCurrentFocus=org.opengoal.gk.jak1`) → `.autoport/reports/Gtitle/device-title.png`.
3. `frame_compare` device-vs-golden (masked). If MISMATCH, diagnose against the original (e.g. stray level-names over PRESS START, J&D-logo edge, missing/extra geometry). `goal_src/jak1/levels/title/title-obs.gc` is editable; oracle-diff arm64 vs x86 for behavioral divergences; rebuild TIT.DGO both backends + sync DGOs to APK assets. Fix until MATCH.
4. No regression: ND-logo beat still matches its golden (re-run that compare), village still renders, intro still on black, no crash.

## Rules / locks
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. No `(mi)` CGO regen. Leave the oracle repo pristine. `.autoport/gold/` core read-only (ADD to `pristine-frames-2400/`). No painted/faked title.

## Validator (`phase-Gtitle-pixelmatch.sh`)
PASS requires (validator runs `frame_compare` itself, reading `.autoport/reports/Gtitle/mask.txt`): the 2400x1080 `title-pressstart` golden exists; masked self-test (identical→MATCH, golden-vs-black→MISMATCH) holds; `frame_compare` of `.autoport/reports/Gtitle/device-title.png` vs the golden → **MATCH**; forbidden-edit gate; x86 `link finish: logo`; device no sig=11, frame≥300, focus held, village tris≥200k; the Gndlogo ND-logo compare STILL matches (no regression); oracle pristine; `Gtitle-fix-summary.md` (≥80 lines) with the diff-image-localization + anti-gaming proofs + the device-vs-golden diff_frac.

## Max settings
`max_turns: 1500`, `max_retries: 3`.

## Strategic note
Reuse exactly what made Gndlogo work (fair gate + honest threshold + diff-image proof). Frame alignment is the new hard part — anchor to the press-start state. The supervisor will scrutinize the threshold + diff image before accepting, same as Gndlogo.
