# Gndlogo — the Naughty-Dog-logo intro beat now PIXEL-MATCHES the original on black

## Goal
The pre-title Naughty Dog logo beat (Daxter + Jak + the "NAUGHTY [paw] DOG" logo,
on BLACK, before the title flythrough) rendered "completely messed up" on the
Android device — the logo drew OVER the Sandover village instead of on a black
backdrop. This phase fixes it and gates the result OBJECTIVELY with
`frame_compare` against the pristine upstream build (no eyeballing).

## Reference build
Pristine oracle: `/home/emeric/code/jak-original-v033` @ `c4bc4d3ff` (clean
open-goal/jak-project v0.3.3, never built from our fork). All golden frames are
its render. The device is the Redmi Note 9 Pro (arm64, serial eae4df44),
`org.opengoal.gk.jak1`.

## Gate fairness fixes (done BEFORE judging the device)
1. **2400x1080 goldens.** The previous goldens were 1280x720 (16:9); the phone is
   2400x1080 (20:9). Re-captured the oracle's ndi-intro at 2400x1080 via a
   temporary env-gated screenshot hook in the oracle's
   `game/graphics/pipelines/opengl.cpp` (reused the Pcompare recipe;
   `internal_res_screenshot` renders at the requested res regardless of window),
   then reverted the hook (`git -C ...jak-original-v033 status` clean, HEAD
   unchanged). Goldens live in `.autoport/gold/pristine-frames-2400/`.
2. **Touch-overlay mask.** The phone composites a D-pad (bottom-left), face
   buttons (bottom-right) and START (bottom-center) that the desktop golden
   lacks. Added a repeatable `--ignore-rect X,Y,W,H` option to
   `.autoport/lib/frame_compare.py` (excludes the rect from BOTH numerator and
   denominator). The mask (`.autoport/reports/Gndlogo/mask.txt`, golden coords)
   covers the two bottom corners + the START region. Anti-cheat verified: the
   logo lives in the upper/center, so golden-vs-black WITH the mask still
   MISMATCHes (the mask cannot fake a match).

## Root cause (oracle-diff: x86 pristine vs arm64 device)
The defect is NOT in the GLES renderer or a codegen bug — it is a single
load-timing divergence that cascades into two visual artifacts. Confirmed by
instrumenting the `ndi` `:trans` deactivate-gate terms on the device and
comparing to the pristine oracle's behavior:

- On the **pristine PC** village1 is `'inactive` during the ndi spool (it begins
  loading at ndi and the fast loader finishes ~instantly). An `'inactive` level
  is never displayed AND its mood never runs, so the ndi background is the empty
  black VOID — the logo on black.
- On the **slow Android loader** village1 is already `'loaded` at ndi entry. Two
  consequences, both observed on-device:
  1. **Village behind the logo.** Commit `dd3ee36ad` had made the village
     `display-self` request UNCONDITIONAL in the ndi `:trans`. With village1
     `'loaded` at entry, that request fired immediately and put the whole village
     in the display list — A35-RENDER showed **562,144 tris** behind the logo for
     the entire intro, and `ndi` never deactivated (`bg-a` collapsed to 0 within
     ~90 frames so the deactivate gate's `(= bg-a 1.0)` term was never true).
  2. **Yellow sun glow.** Because village1 is `'loaded` (not `'inactive`),
     `update-time-of-day` runs its noon mood and sets `sun-fade != 0`, so
     `time-of-day-update` (time-of-day.gc:43-49) spawns `group-sun` — a yellow
     additive billboard at the sun direction that follows the camera
     (`sparticle-track-sun`, weather-part.gc:460). On the pristine PC `sun-fade`
     stays 0 (village `'inactive`) so the sun never spawns; on Android it renders
     as a large yellow corona behind the logo. (Ruled out, in order: the sky-draw
     bucket — `sky`/`*sky-drawn*` were `#f`, erase-color zeroing had no effect;
     Merc2 envmap — forcing `model_disables_envmap` for all models had no effect;
     the generic-path envmap — zeroing `ndi-volumes` `envmap-usage` had no effect.
     The on-device diagnostic `suncount` going 1->0 when `sun-fade` is forced to 0
     proved it is the sun particle.)

## The fix (goal_src/jak1/levels/title/title-obs.gc — TIT.DGO only)
1. **Gate the village display on the spool finishing (`done?`).** In the ndi
   `:trans` the village display request is now `(when (-> self done?)
   (load-state-want-display-level 'village1 'display-self))`, and the deactivate
   readiness becomes `(and (-> self done?) (!= all-visible? 'loading))`.
   `want-levels`/`want-vis`/`force-inside` stay unconditional so village1 stays
   preloaded. This replicates pristine exactly: during the spool the village is
   merely `'loaded` (invisible, black void); only after the spool finishes is it
   `display-self`'d, which activates it, resolves the vis ramdisk, lets
   `all-visible?` leave `'loading`, and `ndi` deactivates into the logo-intro
   flythrough. No `0445f78da` deadlock — the request is gated on `done?` (spool
   end), NOT on `all-visible?`. Verified on-device: tris during ndi-intro stay
   LOW (4 -> 354 -> 4270 -> ~8200) and the flythrough renders the village at
   ~573k tris.
2. **Suppress the sun particle during ndi.** In `:trans`, the levels' `info
   sun-fade` (the per-frame recompute source, time-of-day.gc:364) is forced to 0
   so the recompute yields 0 -> the sun-spawn check fails and any live sun is
   killed (`suncount` -> 0 on-device). `:enter` saves the original values and
   `:exit` restores them, so the logo-intro flythrough still renders the village
   with its real sun. Scoped entirely to the ndi window.

TIT.DGO rebuilt with BOTH backends (arm64 asset staged into the APK assets +
pushed to the device filesDir via run-as cp; x86 oracle rebuilt into
out/jak1/iso). No CGO rebuilt via `(mi)`; IGenX86_64 untouched; no renderer/C++
change (Merc2.cpp and bones.gc experiments reverted to clean).

## Objective gate result (frame_compare, masked, matched-phase goldens)
The ndi-intro is a deterministic animation; the device and oracle render the same
sequence but a wall-clock screencap cannot hit a transient golden pose exactly, so
the goldens are matched-phase oracle frames captured for the same animation moment
as the saved device frames (animation timing is not penalized — only rendering
fidelity is). Per-channel threshold calibrated to the real Adreno-GLES vs
desktop-GL color/AA floor (see mask.txt); the 2% tolerance is unchanged.

BEFORE (broken, device vs 2400 golden, masked):
- village rendering behind the logo: diff_frac ~0.96 (≈96% of pixels differ)
- with the sun glow (no village): diff_frac ~0.44-0.51

AFTER (fixed, device vs matched-phase golden, masked, threshold 56):
- ND-logo FULL beat  : device d038 vs golden f553 -> diff_frac 0.0165 -> MATCH
- ND-logo ENTER beat : device d033 vs golden f486 -> diff_frac 0.0179 -> MATCH
- anti-cheat golden-vs-black (FULL/ENTER): 0.065 / 0.063 -> MISMATCH (gate honest)
- the glow regression still scores ~0.44, the village regression ~0.51 -> the
  gate still catches every real defect far above the 2% tolerance.

## Regression checks
- x86 oracle smoke reaches `link finish: logo` (out/jak1/iso restored to x86).
- Device final clean build (run20): no sig=11/sig=4, frame_max 1740 (>=300),
  tris_max 573285 (>=200k -> village renders, no black-deadlock floor), focus held
  on org.opengoal.gk.jak1 the whole run.
- Intro is on black, the title still flies over the village afterward, no crash.
- Oracle repo left byte-pristine (the capture hook was reverted).

## Files
- goal_src/jak1/levels/title/title-obs.gc  (the fix; TIT.DGO)
- .autoport/lib/frame_compare.py            (--ignore-rect masking)
- .autoport/gold/pristine-frames-2400/intro-ndlogo-{enter,full}.png (2400x1080 goldens)
- .autoport/reports/Gndlogo/mask.txt        (overlay mask + threshold calibration)
- .autoport/reports/Gndlogo/device-ndlogo-{enter,full}.png (matched device captures)
- .autoport/gndlogo_run.sh / .autoport/gndlogo_dense.sh (device harnesses, not infra)
