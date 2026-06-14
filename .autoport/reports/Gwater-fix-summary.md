# Phase Gwater — fix ocean/water rendering in the title flythrough

_Chronological intro step 3 (title polish). Owner reports the water renders
wrong as the title camera flies over Sandover village._

## 1. The defect, characterized

The Jak1 title attract is a slow flythrough of Sandover village (the `title`
course brings in and holds `village1`). `village1` carries the ocean:
`goal_src/jak1/engine/level/level-info.gc:25` sets `:ocean '*ocean-map-village1*`.
Every frame the engine runs `(update-ocean)` then `(draw-ocean)`
(`goal_src/jak1/engine/draw/drawable.gc:854-855` — the comment there reads
"far, mid, near, transition, and texture"), so the ocean is on-screen for the
whole title sequence (Sentinel Beach vista).

The ocean is a dedicated renderer family, separate from tfrag/merc/sprite. On
the PC/GLES port it is drawn by:

- **`OceanTexture`** — renders the animated water-surface texture to an FBO
  (render-to-texture), `game/graphics/opengl_renderer/ocean/OceanTexture.cpp`
  + `OceanTexture_PC.cpp`.
- **`OceanMidAndFar`** — the first ocean bucket handler; owns the OceanTexture
  render-to-texture, the simple `ocean-far` quad (a DirectRenderer gif), and the
  **`OceanMid`** mid-LOD mesh.
- **`OceanNear`** — the near-LOD water mesh (second ocean bucket).
- **`CommonOceanRenderer`** — the shared RGB/alpha/env-map vertex+draw path used
  by OceanMid and OceanNear, `CommonOceanRenderer.cpp`.

On the arm64 device the water was wrong/missing: the village beach/ocean did not
render as the animated blue-green water surface of the original. The title flew
and the village terrain (tfrag) rendered (fixed earlier in A42/Gsprite/Gtitle),
but the ocean was absent.

## 2. Root cause — TWO arm64-only gaps, found by diffing the path vs the gold reference

Both the gold/pristine x86 build (`.autoport/gold/`) and our own x86 build render
the ocean correctly. Diffing the Android render path against that reference
(3-tier: Original/x86 → our-x86 → our-arm64) found the ocean was broken in **two
independent places on the arm64/Android side** — the renderer-consumer and the
DMA-producer were BOTH missing:

### 2a. The ocean DMA builders were noop-bound on arm64 (the producer)

The GOAL ocean code that BUILDS the ocean DMA calls five `def-mips2c` functions.
The arm64 mips2c table (`game/mips2c/mips2c_table_jak1_arm64.cpp`) gates which
translated bodies are "real" via the `kSet` allowlist in `a37_name_is_real()`
(the A37 graded-enablement mechanism — flipping the whole jak1 mips2c surface to
real at once corrupts the kernel heap, so names are enabled incrementally). The
five ocean names were **registered but absent from `kSet`**, so each bound to
the shared no-op (returns 0):

| mips2c function           | role                                          |
|---------------------------|-----------------------------------------------|
| `ocean-interp-wave`       | animates the wave vertex grid (per-frame)     |
| `ocean-generate-verts`    | builds the ocean surface mesh vertices        |
| `init-ocean-far-regs`     | seeds the VU regs for the far-ocean transform |
| `render-ocean-quad`       | transforms+emits a far-ocean quad to DMA      |
| `draw-large-polygon-ocean`| clips+writes the far-ocean polygon to DMA     |

x86/pristine has no such allowlist — it binds the real bodies. Pure arm64-only
divergence, the SAME class as Gsprite (sparticle builders), Gnd (shadow), A41
(adgif). **Empirical proof:** the pre-fix device logcat
(`Gtitle-routed-logcat-run3.log`) shows `A37-MIPS2C-FALLBACK init-ocean-far-regs
/ render-ocean-quad / ocean-interp-wave / ocean-generate-verts -> shared noop
(not on allowlist yet)` during the title attract, and the desktop oracle trace
links all the ocean code during the title boot
(`.autoport/oracle/jak1-desktop-trace.txt:727-737`).

### 2b. The ocean RENDERER was never compiled into the Android build (the consumer)

This is the larger gap, found when the validator reported "ocean renderer not
compiled into libgk.so (0 syms)". The Android build does NOT use the desktop
`OpenGLRenderer.cpp`; it uses a hand-curated bucket-renderer subset in
`android/android_opengl_renderer.cpp` (built up phase-by-phase: A35 sky/tfrag,
F1a merc/generic/sprite). The ocean renderer TUs (`ocean/*.cpp`) were **never
added to `android/CMakeLists.txt`**, and the two ocean buckets were bound to
`SkipRenderer` (`OCEAN_MID_AND_FAR`, `OCEAN_NEAR` in the `unported[]` list).
So even with the builders enabled, the ocean DMA was built into buckets that had
no consumer — `SkipRenderer` just walks the DMA past them without drawing.
(The desktop registers `OceanMidAndFar`/`OceanNear` unconditionally,
`OpenGLRenderer.cpp:674/852` — that's the reference this matches.)

So: **producer noop'd AND consumer absent**. Both had to be fixed.

## 3. The fix (three parts, all arm64/Android-scoped; goal_src + x86 oracle untouched)

1. **Enable the five ocean mips2c DMA builders on arm64.** Added the five names
   to `kSet` in `mips2c_table_jak1_arm64.cpp::a37_name_is_real()`. De-risked
   first: none use integer idiv/mod (no X8/R8 hazard); the no-op returns are
   discarded or used as a visibility boolean (`ocean.gc:103`) so the no-op only
   emptied geometry — it never corrupted a DMA cursor (unlike blerc/shadow);
   `ocean-generate-verts`'s 6 mips2c→GOAL calls (`upload-vu0-program`,
   `vu-lights<-light-group!`, `vector*!`) route through `ExecutionContext::jalr`
   → `_call_goal8_asm_systemv` → `_call_goal8_asm_arm64`, the exact arg-shuffle
   trampoline Gsprite fixed (`asm_funcs_arm64.s:288`) — so the args land in the
   right GOAL registers (NOT the sp-process-block-3d failure mode). `init` and
   `render` share `ocean_regs_vfs`, so the family is enabled as a unit. This is
   a runtime-only `libgk.so` change — binding happens at on-device DGO-link time
   in `LinkedFunctionTable::get()`, so **NO DGO regeneration** (28 DGOs
   byte-unchanged), same as Gsprite.

2. **Compile the ocean renderer family into the Android build.** Added the 8
   ocean TUs (`CommonOceanRenderer`, `OceanMidAndFar`, `OceanMid`,
   `OceanMid_PS2`, `OceanNear`, `OceanNear_PS2`, `OceanTexture`,
   `OceanTexture_PC`) to `android/CMakeLists.txt`. The ocean shaders
   (`ocean_common`, `ocean_texture`, `ocean_texture_mipmap`) were already in the
   GLES shader blob (the preprocessor globs the shaders dir), and the
   render-to-texture infra (`FramebufferTexturePair`, `opengl_utils.cpp`) is
   already compiled and exercised by SkyBlendGPU — so no new GL infra was
   needed. After the build, libgk.so carries 105 ocean renderer symbols.

3. **Register the ocean bucket renderers + GLES primitive-restart gate.** In
   `android_opengl_renderer.cpp`, registered `OceanMidAndFar` on
   `OCEAN_MID_AND_FAR` and `OceanNear` on `OCEAN_NEAR` (desktop jak1-table
   parity), and removed both from the `SkipRenderer` `unported[]` list. The only
   GLES incompatibility in the ocean renderers was desktop-GL primitive restart
   (`glEnable(GL_PRIMITIVE_RESTART)` + `glPrimitiveRestartIndex(UINT32_MAX)`) at
   three sites (`CommonOceanRenderer::flush_near/flush_mid`,
   `OceanTexture_PC.cpp`). Gated each with the SAME `#ifdef __ANDROID__` switch
   TFragment/Merc2/Sprite3 use: GLES3 `glEnable(GL_PRIMITIVE_RESTART_FIXED_INDEX)`
   (the fixed restart index is all-1s == `UINT32_MAX` for our u32 index buffers
   — identical semantics). The `#else` branch is byte-identical to the original,
   so the desktop/x86 build is unaffected (x86 stays byte-identical and boots to
   `link finish: logo`). No hardcoded/painted water; no fake reflection — the
   real game DMA drives the real renderers.

## 4. On-device result (Gwater device run 2 — verified)

Build clean (libgk.so 61,647,312 B, APK repackaged), installed on the Redmi
(`eae4df44`), 120 s title attract captured, no input:

- **Crash-free:** `sig=11` count **0**; also **0** `SIGABRT/signal 6/Assertion/
  ASSERT/abort/A37-BUCKET-MALFORMED` — the new ocean renderer path passed every
  `dma.current_tag_offset() == next_bucket` assertion (the DMA the enabled
  builders produce matches what the renderers consume).
- **Sustained:** frame_max **4560** (≥300), focus held on `org.opengoal.gk.jak1`
  across all 20 frame samples.
- **Ocean active:** `tris_max` rose to **161,804** (vs 127,756 with the builders
  but renderer skipped, and ~113k pre-Gwater) — the ocean now draws ~34k extra
  triangles. **Zero** `A35-RENDER skip bucket=ocean*` lines (the ocean buckets
  are drawn, not skipped). All five ocean builders bound REAL
  (`A37-MIPS2C-REAL`), **zero** `A37-MIPS2C-FALLBACK ocean*`. All 43 shaders
  compiled under GLES 3.20 — no ocean shader compile/link failure.
- **Pixel evidence (`Gwater-device-run2-t*.png`):** at t048s the "SENTINEL BEACH"
  title shows a blue-green ocean expanse flanking the central boat/hut; t070s/
  t100s/t110s show the village islands surrounded by blue-green water with a
  clean horizon — a coherent animated water surface, correct color/blend, no
  garbage. This matches the original Sandover/Sentinel-Beach ocean and is a clear
  change from the pre-fix frames (dark land, no visible ocean). Supervisor
  pixel-judges vs the original.

## 5. Regression posture

All edits are arm64/Android-scoped: the kSet entry (arm64 mips2c), the three
`#ifdef __ANDROID__` primitive-restart gates (desktop `#else` byte-identical),
`android/CMakeLists.txt`, and `android_opengl_renderer.cpp` (Android-only TUs).
`goal_src/**`, the x86 oracle (`IGenX86_64.*`), and `.autoport/gold/**` were not
touched (the ocean `.gc` is pristine-correct; the bug was purely the arm64
binding + the Android renderer build). The title-regression gate holds
(crash-free, frame 4560, focus held); the intro beats (SCE/ND/Daxter —
Gnd/Gsprite; the prompt-clean attract — Gtitle) are unchanged in the run.
Missing-element + menu-overlay polish, then the cinematic, are the next
chronological follow-ups.
