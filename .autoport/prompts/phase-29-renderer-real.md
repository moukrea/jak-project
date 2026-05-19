# Phase 29 — Real renderer chain: tfrag/tie/sprite/sky/merc/generic

## Goal

Phase 21's "GLES shader port" left the renderer at exactly **one shader
(`solid_color`)** plus a `glClear`+`eglSwapBuffers` loop. The framebuffer
is a single color over and over. This phase ports the actual OpenGOAL
renderer chain (tfrag, tie, sprite, sky, merc, generic, shadow) from
`game/graphics/opengl_renderer/` to GLES 3.2, integrates the CPU-side
DMA emulation that feeds them, and confirms via **on-device framebuffer
pixel content** that real rendering is happening.

## Anti-stub rules

The validator uses `adb shell screencap -p` and analyzes the actual
pixels. A `glClear` loop produces a near-uniform image; real rendering
produces hundreds of distinct RGB values per region.

Specifically:

1. The shader-compile count grep must show ≥10 distinct shader names
   compiled, not just `solid_color`.
2. A 200×200 region in the center of the screencap must contain ≥50
   unique RGB values AND no single color may dominate >70% of the
   region.
3. `nm libgk.so | grep -E 'TfragRenderer|TieRenderer|MercRenderer|SpriteRenderer|SkyRenderer'`
   must find each renderer class. Bodies ≥500 bytes
   (per `anti_stub_check_symbol_body_size`).

## Concrete deliverables

1. **Port every shader** under `game/graphics/opengl_renderer/shaders/`.
   Phase 21's preprocessor approach (Python script that prepends
   `#version 320 es` + precision qualifiers) is the right one — extend
   it to handle every shader, not just `solid_color`. Existing shaders:
   - `tfrag` (terrain fragment)
   - `tfrag3` (newer tfrag pipeline)
   - `tie` (instanced environment)
   - `merc` (skinned characters)
   - `sprite`
   - `sky`
   - `shadow`
   - `generic` (catch-all)
   - `depth_cue`
   - `direct_basic`, `direct_basic_textured`
   - `etie` (eye textures, etc.)

   Run the preprocessor at build time via the existing
   `add_custom_command` hook in `android/CMakeLists.txt`.

2. **Port the renderer C++ classes** from
   `game/graphics/opengl_renderer/`. These exist on desktop; the
   missing piece is making them link + run under GLES 3.2. Audit each
   for desktop-only GL calls and gate per phase 21's audit (the
   audit was supposed to be exhaustive — extend it).

3. **Wire the renderer dispatcher** so the GfxDispatcher → renderer
   chain runs every frame. This already exists in
   `game/graphics/opengl_renderer/OpenGLRenderer.cpp`; link it,
   call it from the SDL main loop.

4. **Remove the placeholder "solid_color clear" loop** from
   `android/android_renderer.cpp`. Replace it with a call into the real
   `OpenGLRenderer::render`. The placeholder logic must be **deleted**,
   not commented out.

5. **Shader-compile logging**: each `OpenGLRenderer::compile_shader`
   call must log `shader: <name> compiled OK` (real path, not synthetic
   from `android/`). The validator counts distinct names.

## Don't

- Don't write replacement shaders that are visually similar to
  jak1's but simpler. Use the real shaders, GLES-translated.
- Don't disable a renderer because it doesn't compile. Fix the
  GLES-incompatibility (`glPolygonMode` → gate, `glDrawPixels` → gate,
  `texelFetch` for sampler2D works in GLES 3.x — verify). The point is
  to render correctly, not to render something.
- Don't tint the framebuffer with a synthetic gradient to pass the
  pixel-diversity check. The validator will catch this if the gradient
  is a known synthetic pattern (e.g., diagonal stripes from a debug
  shader).

## Pitfalls

- GLES 3.2 supports `texelFetch`, sampler2DArray, layered FBOs — most
  jak1 shaders work directly. Gotchas: `gl_FragDepth` writes need
  explicit precision; integer interpolation needs `flat`;
  uniform-buffer-object size limits are tighter than desktop.
- The CPU side does heavy DMA emulation. The desktop runtime's PCDMA
  code is single-threaded and timing-sensitive; on slower mobile CPUs
  it may stall. Profile, but don't reduce the simulation's accuracy
  unless documented.
- Adreno drivers cache shader binaries. Stale shader files in the APK
  may not invalidate; bump the resource path or use the existing
  shader hash.

## Validator

```
.autoport/validators/phase-29-renderer-real.sh
```

## Success

≥10 distinct shaders log `compiled OK`, libgk.so exposes all renderer
classes with non-trivial bodies, and the screencap shows ≥50 unique
RGB values in the center region with no dominant color above 70%. The
title screen is visibly something (even if pre-title splash, not the
final logo).
