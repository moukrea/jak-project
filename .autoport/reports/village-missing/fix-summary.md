# village-missing: Sandover title attract — missing foliage (shrub) class

## Missing class
**Shrub** — the dense foliage class: palm trees, plants, bushes, ground grass,
and the thatched detail on the village huts. (Its sibling overlay band — TIE
*instanced* structures, shadows, depth-cue — are still un-ported; see follow-up.)

## Matched-capture evidence (before)
Device attract flythrough (ANDROID_SERIAL=eae4df44, focus held on
`org.opengoal.gk.jak1`, no input):
- `device-run1-t010s.png` — bare wooden plank floor, character, NO plants.
- `device-run1-t046s.png` / `device-run1-t102s.png` — bare green terrain chunks +
  bare wood huts; no palm trees, bushes, grass, orbs, or birds.

Pristine v0.3.3 reference (clean upstream, unmodified toolchain):
- `.autoport/gold/TRUE-original-v033/01-attract-flythrough.png` — dense palm
  trees, bushes, foreground grass, floating precursor orbs, a bird, grounded
  huts. (Ground-camera moment; the missing CLASS is camera-invariant.)
- Live pristine X-capture at a matched aerial moment was attempted but the
  headless Xwayland :0 capture path (import/magick) stalled on X-auth; it was
  not needed — the per-bucket skip log below names the class unambiguously.

## Per-bucket stat diff that named the class (not eyeballing)
The Android renderer (`android/android_opengl_renderer.cpp`) keeps a per-bucket
`m_bucket_ported[]` gate. When a bucket HAS data but is not ported it logs
`A35-RENDER skip bucket=<name> (not ported)`. Run-1 logcat
(`villmiss-routed-logcat-run1.log`):

```
A35-RENDER skip bucket=l0-shrub id=26 (not ported)   <-- foliage, HAS data, dropped
A35-RENDER skip bucket=l1-shrub id=26 (not ported)
A35-RENDER skip bucket=l0-tie   id=16 (not ported)
A35-RENDER skip bucket=l1-tie   id=16 (not ported)
A35-RENDER skip bucket=shadow   id=47 (not ported)
```

The skip log fires only inside `if (had_data)` — proving the shrub buckets were
**populated every frame but discarded** on arm64. Frame aggregate tris ceilinged
at 161 982 (run-1). The shrub DMA itself is built by pure GOAL code
(`goal_src/jak1/engine/gfx/shrub/shrubbery.gc draw-drawable-tree-instance-shrub`
→ `add-pc-tfrag3-data`, explicitly "completely rewritten for PC", no mips2c
builder), so this was NOT a mips2c-allowlist or bucket-chain-corruption defect —
it was a curated-subset omission in the C++ renderer.

## Root cause
`SHRUB_NORMAL_LEVEL0/1` were wired as `SkipRenderer` in the Android
`unported[]` list, and `Shrub.cpp` was never added to the Android build
(`android/CMakeLists.txt` listed only `background_common.cpp` + `TFragment.cpp`).
The Shrub bucket renderer + ShrubLoadStage (which DOES load `shrub_vertex_data`)
were compiled into the desktop build but absent from `libgk.so`.

Two GLES incompatibilities had to be fixed for the renderer to run on Adreno
(both the SAME bug classes already fixed for TFragment/TIE):
1. `Shrub.cpp` uploaded the per-tree time-of-day LUT as `GL_TEXTURE_1D`
   (`glTexImage1D`/`glTexSubImage1D`) and `shrub.vert` sampled `sampler1D
   tex_T10`. GLES has no 1D textures; the arm64 loader binds `glTexImage1D` to
   NULL. (Same class as TIE fix `9fe0be120`.)
2. The render path called `glPrimitiveRestartIndex(UINT32_MAX)` — NULL in GLES
   (no settable restart index). This is what crashed run-2:
   `GK-DIAG F1A-BUCKET in-render=l1-shrub id=26` → `sig=11 fault=0x0 pc=0x0`
   (BLR-to-null). (Same class as the A36 tfrag crash.)

## The fix (one class: shrub / foliage)
- `game/graphics/opengl_renderer/shaders/shrub.vert`: `sampler1D` → `sampler2D`,
  `texelFetch(tex_T10, i, 0)` → `texelFetch(tex_T10, ivec2(i,0), 0)`
  (matches tfrag3.vert; the GLES preprocessor's auto 1D→2D rewrite is now a
  no-op for it).
- `game/graphics/opengl_renderer/background/Shrub.cpp`: time-of-day LUT now a
  Wx1 `GL_TEXTURE_2D`, `GL_UNSIGNED_BYTE` (3 sites: create / sub-update /
  delete-bind), matching TFragment.cpp; primitive-restart gated
  `#ifdef __ANDROID__ → GL_PRIMITIVE_RESTART_FIXED_INDEX` (else desktop path
  unchanged).
- `android/CMakeLists.txt`: added `background/Shrub.cpp` to the gk sources.
- `android/android_opengl_renderer.cpp`: registered `Shrub` for
  `SHRUB_NORMAL_LEVEL0/1` (desktop jak1-table parity) and removed both from
  `unported[]`.

x86 oracle (`build-x86`) rebuilds clean (Shrub.cpp + OpenGLRenderer.cpp
recompile, gk links); texelFetch on a Wx1 2D is texel-exact on desktop GL, so
x86 visuals are unchanged. No CGO regen, no goalc/codegen, no IGenX86_64 touch.

## After (device-verified, ANDROID_SERIAL=eae4df44)
Run-3 (`villmiss-routed-logcat-run3.log`): `A35-RENDER skip bucket=l0/l1-shrub`
is GONE (only `shadow` + `l1-tie` remain skipped). sig11=0, frame_max=3660,
focus held on `org.opengoal.gk.jak1`. Frame-aggregate tris rose
**161 982 → 263 217** (+101 235 = the shrub geometry).

Before/after PAIR at the IDENTICAL camera moment (t010s):
- `device-run1-t010s.png` (before): bare plank floor, no plants.
- `device-run3-t010s.png` (after): green palm fronds + a red flowering plant +
  grass tufts in the same frame.
Wider shots: `device-run3-t046s.png` (SENTINEL BEACH, thatched-roof huts +
foliage), `device-run3-t102s.png` (vegetated terrain + visible precursor orb).
Intro still on full black: `device-run3-t003s.png`. TIE structures still
textured (TIE 2D-LUT fix preserved); title still flies.

## Frames to open
- BEFORE: `.autoport/reports/village-missing/device-run1-t010s.png`
- AFTER:  `.autoport/reports/village-missing/device-run3-t010s.png`
- AFTER (wide): `.autoport/reports/village-missing/device-run3-t046s.png`,
  `device-run3-t102s.png`
- PRISTINE: `.autoport/gold/TRUE-original-v033/01-attract-flythrough.png`

## Still missing (follow-up phases — NOT fixed here)
- **TIE instanced (`TIE_LEVEL0/1`, "l0-tie"/"l1-tie")** still `SkipRenderer`.
  TIE structures currently come through the generic-tie + tfrag path; the
  dedicated instanced-TIE bucket (Tie3 renderer) is un-ported. Some detail
  props / the densest hut geometry likely live here. Tie3.cpp already has the
  GLES 2D-LUT fix (`9fe0be120`) so this is mostly a CMake-add + un-skip +
  on-device verify, but it is its own class and was out of scope this pass.
- **SHADOW**, **DEPTH_CUE** still un-ported (cosmetic; not foliage).
- **Floating precursor orbs / birds**: the orb is now visible in run-3 frames
  (sprite/generic path), but a full audit of orb/bird coverage vs pristine was
  not done — flag for the TIE/sprite follow-up.
