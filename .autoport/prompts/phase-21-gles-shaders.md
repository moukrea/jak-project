# Phase 21 — GLES shader port + desktop-GL API audit

## Goal

The desktop renderer uses GL 4.1 core (`#version 410 core` shaders) and a
handful of desktop-only entry points. On Android we have GLES 3.2 from
Adreno (and Mali on most other modern Android devices). This phase
translates every shader to GLES 3.2 in a way that **keeps a single source
of truth** for both backends, and audits the C++ GL call surface for
desktop-only functions that need Android-specific replacements.

After this phase, the runtime should produce at least one rendered frame:
`engine: frame 1 submitted` + `eglSwapBuffers: ok` (the second after the
phase-18 init swap).

## Concrete deliverables

1. **Shader preprocessor** — single source of truth.
   - All shaders live at `game/graphics/opengl_renderer/shaders/*.{vert,frag}`.
   - Each shader keeps its **current desktop body** (no inline `#ifdef`s).
   - At build time on Android, a preprocessor prepends a header:
     ```glsl
     #version 320 es
     precision highp float;
     precision highp int;
     precision highp sampler2D;
     precision highp sampler2DArray;
     precision highp sampler3D;
     // ... whatever other precision qualifiers the fragment shader needs
     ```
     On desktop the unchanged file is used (it already starts with
     `#version 410 core`).
   - Implementation: a Python script
     (`game/graphics/opengl_renderer/shaders/preprocess.py`) invoked
     from `android/CMakeLists.txt` via `add_custom_command` that
     transforms each `*.vert`/`*.frag` into a generated `*.android.vert`/
     `.android.frag` under `${CMAKE_BINARY_DIR}/shaders/`.
   - The runtime's shader loader uses the generated paths on Android,
     the originals on desktop. A single CMake-installed include
     (`shader_paths.h`) carries the right path constants.

2. **Audit & port C++ GL calls.** Walk `game/graphics/opengl_renderer/`
   and replace / gate the following:
   - `glPolygonMode(GL_FRONT_AND_BACK, GL_LINE/GL_FILL)` — not in GLES.
     Wrap the wireframe debug paths behind `#ifndef __ANDROID__`. The
     default `GL_FILL` path needs no replacement (it's the GLES default).
   - `glDrawPixels`, `glRasterPos*` — not in GLES. Gate behind
     `#ifndef __ANDROID__`.
   - `glClearDepth(double)` → `glClearDepthf(float)` on Android.
   - `GL_TEXTURE_BUFFER` — present in GLES 3.2. No change needed but
     verify with `glGetIntegerv(GL_MAX_TEXTURE_BUFFER_SIZE)`.
   - `glMapBuffer` — replace with `glMapBufferRange(..., GL_MAP_WRITE_BIT)`
     for cross-compat (GLES 3.x has `glMapBufferRange`, not `glMapBuffer`).
   - Anything using `glGetTexImage` (reads texels back to host) — not
     in GLES. Either implement a `glReadPixels`-via-FBO fallback or
     gate the debug feature behind `#ifndef __ANDROID__`.
   - `glEnable(GL_PROGRAM_POINT_SIZE)` — point size in GLES is set in
     the vertex shader via `gl_PointSize`. The enum doesn't exist on
     GLES. Gate.

3. **Per-shader audit** — adjust shader bodies that use desktop-only
   syntax (rare in this codebase, but verify):
   - Anywhere the desktop shader does `texelFetch(...)`: GLES 3.x
     supports it — leave as is.
   - `gl_FragDepth` writes need `#extension GL_EXT_frag_depth : require`
     in GLES — the preprocessor should append this only to shaders
     that actually write `gl_FragDepth` (detected by grep).
   - `out float gl_FragDepth` declarations: in GLES the precision must
     be `highp` (must come before the declaration).
   - **Do not** change semantics. If a shader doesn't compile under
     GLES, fix the GLES version of the shader, not the GLSL version.

4. **Engine-side render-loop logging** (the validator greps for these):
   - On each successful program compile: emit `shader: <name> compiled OK`
     (use `glGetShaderiv(GL_COMPILE_STATUS)`).
   - On any compile error: dump `glGetShaderInfoLog` then `abort()`.
     A black screen because a shader silently failed is unhelpful.
   - After the first frame finishes (last `glDrawElements`/`glDrawArrays`
     of the frame): `engine: frame 1 submitted` (a counter).
   - After the matching `SDL_GL_SwapWindow`: `eglSwapBuffers: ok`
     (phase-18 already logs this once; let it log on every swap or at
     least on the first 5).

## Don't

- Do **not** drop `#version 410 core` from the desktop sources. Keep the
  single-source-of-truth invariant.
- Do **not** suppress shader compile errors. A program that fails to link
  must `abort()` so the validator sees the crash rather than a silent
  black screen.
- Do **not** add a hand-maintained second copy of each shader for Android.
  Use the preprocessor.
- Do **not** target GLES 3.1 to "lower the bar" — the user's Adreno 618
  supports 3.2 and so do all reasonable port targets.

## Pitfalls

- **Precision in fragment shaders is not defaulted in GLES.** A frag
  shader missing `precision highp float;` will fail to compile with a
  cryptic message. The preprocessor must always inject it.
- **`#version` line must be the first non-comment line.** Cleanly
  replacing it via `sed -i '0,/#version/{s/#version.*$/#version 320 es/}'`
  is fragile — use the preprocessor's structured rewrite.
- **`flat in`** interpolation works in GLES 3.x but must be qualified
  on integer outputs in the vertex shader too (mirror).
- **`layout(location = N)` outputs** in fragments are supported by GLES
  3.x — keep them.
- The desktop GL context advertises `4.1 core`; GLES contexts advertise
  `OpenGL ES 3.2`. Don't gate engine logic on `glGetString(GL_VERSION)`
  string matching beyond what's already there.

## Validator

```
.autoport/validators/phase-21-gles-shaders.sh
```

Builds, installs, launches; passes if the boot sequence reaches a
**rendered frame** within 120s:
  - all shaders compile (no `shader: <name> compile FAILED`)
  - `engine: frame 1 submitted`
  - `eglSwapBuffers: ok` at least twice (once from init, once for frame 1)
  - no crash
  - desktop x86 build still passes (CRITICAL — shader work easily
    breaks the GL 4.1 path).

## Success

Activity opens, you see a Game-rendered surface (likely intro screen or
splash, depending on how far the engine boots without controller input).
First frame is logged within 120s of launch. No shader compile errors
in logcat.
