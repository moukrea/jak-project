# village-tie — port the instanced TIE buckets (l0-tie / l1-tie) to Android

## Symptom
The jak1 title attract flythrough over Sandover village was missing its dense
built detail: huts, fences, props, wooden platforms/scaffolds, and the
moss-covered Precursor ruins — the geometry drawn through the TIE instance
system. (Foliage/shrub had just been fixed in `ac011616e`.)

## Per-bucket evidence (BEFORE)
Device logcat (eae4df44) of the attract, grep `A35-RENDER skip bucket=`:

    A35-RENDER skip bucket=l1-tie id=16 (not ported)
    A35-RENDER skip bucket=shadow id=47 (not ported)

The skip log fires only when the bucket HAS data, so the populated `TIE_LEVEL1`
bucket was being discarded every frame. (`l0-tie`/TIE_LEVEL0's skip line did not
fire in this attract window — that bucket carried no data for the camera path
sampled — but it was wired identically as a `SkipRenderer`, so both are ported.)
frame_max=3300, tris_max=263225, sig11=0.

## Root cause — same curated-subset omission as Shrub
The jak1 desktop table backs `TIE_LEVEL0`/`TIE_LEVEL1` with a single
`Tie3WithEnvmapJak1` renderer per level (TIE + TIE-envmap in one),
`OpenGLRenderer.cpp::init_bucket_renderers_jak1` lines 689 / 711. On Android
those two buckets were wired as `SkipRenderer` in the `unported[]` list of
`android/android_opengl_renderer.cpp`, and `Tie3.cpp` was never added to
`android/CMakeLists.txt` (only `background_common.cpp`, `TFragment.cpp`, and
`Shrub.cpp` were). So the renderer class simply did not exist in the Android
build and the TIE-instanced DMA was dropped every frame. Not a mips2c-allowlist
or bucket-chain-corruption defect.

## GLES blockers
- Time-of-day LUT: ALREADY a Wx1 GL_TEXTURE_2D + `sampler2D` in `Tie3.cpp` and
  the tie/etie/tie_wind/tfrag3 shaders (commit `9fe0be120`). No change needed —
  the non-envmap TIE path shares the TFRAG3 shader and already rendered textured.
- Primitive restart: the two `glEnable(GL_PRIMITIVE_RESTART); glPrimitiveRestartIndex(UINT32_MAX)`
  calls in `Tie3.cpp` (`render_tree_category` and the wind draw) were the one
  remaining blocker. `glPrimitiveRestartIndex` is NULL in the GLES loader on
  arm64 (BLR-to-0 → sig=11 fault=0x0, same class that crashed the shrub port's
  first attempt). Gated to `GL_PRIMITIVE_RESTART_FIXED_INDEX` under `__ANDROID__`,
  which restarts on the all-ones index = UINT32_MAX for our u32 index buffers
  (identical semantics). Same fix as TFragment.cpp / Shrub.cpp.

## The fix (3-part pattern, matching `ac011616e`)
1. `android/CMakeLists.txt`: add `Tie3.cpp` to the `gk` sources.
2. `android/android_opengl_renderer.cpp`: include `background/Tie3.h`; register
   `Tie3WithEnvmapJak1` for `TIE_LEVEL0` (level 0) and `TIE_LEVEL1` (level 1);
   drop both from the `unported[]` SkipRenderer list.
3. `game/graphics/opengl_renderer/background/Tie3.cpp`: gate the two
   `glPrimitiveRestartIndex` calls for GLES.

No goalc/codegen change. No CGO/DGO regen. C++/CMake only.

## Verification (AFTER, device eae4df44)
- `A35-RENDER skip bucket=l0-tie|l1-tie` → GONE. Only `shadow` remains skipped.
- tris_max 263225 → **616871** (+353646, +134%): the instanced TIE detail draws.
- sig11=0, frame_max=2400 (>=300), no crash, focus held on org.opengoal.gk.jak1
  for every capture.
- Visual (my own eyes): the fisherman's hut + wooden scaffold/tower, fences,
  the Precursor ruin arch, and many props now render over the village; foliage
  (shrub) still renders; TIE structures still textured (not black silhouettes).
- Regression: intro still full black ("Created and Developed by Naughty Dog /
  © 2001 Sony", device-after-t004s.png); title still flies; shrub still draws;
  TIE structures still textured. No regression.

### Frames to open
BEFORE: `.autoport/reports/village-tie/device-before-{t062s,t082s,t092s}.png`
AFTER:  `.autoport/reports/village-tie/device-after-{t062s,t082s,t092s}.png`
(The attract camera path is not perfectly phase-locked frame-to-frame; compare
the village-overhead moments. The +353k-tri jump + skip-log disappearance are
the frame-independent proof.)

## Still unported (known, NOT fixed here — cosmetic / out of scope)
- `SHADOW` (id 47) — still a SkipRenderer (Shadow2 on desktop). Real-time blob
  shadows; cosmetic for the attract flythrough.
- `DEPTH_CUE` — desktop post-effect; cosmetic.
These are listed, not fixed, per the one-class-at-a-time mandate.
