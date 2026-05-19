# Phase 12 — Full Android NDK runtime (real libgk.so)

## Goal

Replace the phase-10 scaffold `libgk.so` (a 50 KB stub that only exports
`gk_version_string()`) with a **real** cross-build of the OpenGOAL `gk`
runtime as a single arm64-v8a shared library. The validator enforces:

- `libgk.so` ≥ 2 MB
- DT_NEEDED includes liblog/libdl/libm/libc AND at least one of
  SDL/GLES/EGL/OpenAL
- Exported symbols (or strings) contain GOAL runtime markers like
  `goal_main`, `kheap_alloc`, `exec_dgo`, `InitMachineScheme`, or
  `kernel_main`

If your build only adds `android/gk_android_main.cpp` again, phase 12
WILL fail. The whole `runtime` static library plus its dependencies must
link into `libgk.so`.

## Concrete scope

1. **Root CMakeLists.txt** — the `if(ANDROID)` block currently returns
   early after `add_subdirectory(android)`. Rework it so on Android the
   normal targets (`common`, `game`, `goalc/emitter` only, `runtime`)
   are reachable, but the `gk` *executable* target is rebuilt as a SHARED
   library named `libgk.so`. The trampoline in `android/gk_android_main.cpp`
   becomes the JNI entry point that calls into `game/main.cpp`.

2. **Third-party deps**. Cross-build, or vendor prebuilts for arm64-v8a:
   - SDL3 (preferred; the repo's `third-party/sdl` already has Android
     backend support). Configure with `-DSDL_VIDEO_DRIVER_ANDROID=ON`,
     `-DSDL_STATIC=ON`.
   - OpenAL Soft — set `-DALSOFT_BACKEND_OPENSL=ON` for Android.
   - zlib, libzstd, fmt — vanilla cross-builds.

3. **Renderer: GL 4.1 → GLES 3.2.** This is the substantive porting
   work in phase 12. Audit shows: OpenGOAL uses `#version 410 core`
   shaders with no compute / tessellation / geometry shaders. The
   translation is bounded:

   - Translate every shader file under
     `game/graphics/opengl_renderer/shaders/*.{vert,frag}`:
     - `#version 410 core` → `#version 320 es` (or 310 es)
     - Add `precision highp float;` / `precision highp int;` / `precision
       mediump sampler2D;` etc. at the top of each fragment shader.
     - Layout qualifiers for inputs/outputs unchanged (GLES 3.x supports them).
   - Audit the C++ GL surface for desktop-only calls. Replace as needed:
     - `glPolygonMode` (not in GLES) → no-op or wireframe fallback path.
     - `glDrawPixels` / `glRasterPos*` (not in GLES) — only used by debug;
       gate behind `#ifndef __ANDROID__`.
     - `glTexImage*` with desktop-only formats — pick GLES-compatible
       sized internal formats (e.g. `GL_RGBA8`, `GL_R8`, `GL_RG8`).
     - `GL_TEXTURE_BUFFER` (GLES 3.2 has it; lower needs an SSBO).
   - Use SDL3's `SDL_GL_*` to create a GLES 3.2 context on Android, GL
     4.1 core on desktop. The same `OpenGLRenderer.cpp` paths should run
     on both; only the context-creation differs.

   You may introduce a thin shader-preprocessing step
   (`game/graphics/opengl_renderer/shaders/preprocess.py` or in-CMake
   `configure_file`) that, on Android builds, prepends the GLES version
   line + precision qualifiers automatically. That keeps one source of
   truth for shaders.

4. **Bionic vs glibc**:
   - `pthread_setname_np(thread, name)` exists; `pthread_setname_np(name)` does not.
   - `getauxval` is fine on API 18+.
   - `mallinfo` is missing — use `mallinfo2` or skip the stats path.
   - Wrap any remaining `<execinfo.h>` use behind `#ifdef __GLIBC__`.

5. **W+X memory for the JIT**. Android API 29 blocks `PROT_WRITE | PROT_EXEC`
   on most mappings. Use the dual-mapping pattern: `memfd_create` + two
   `mmap` calls (one RW, one RX) backed by the same fd, then flush with
   `__builtin___clear_cache`. Implement under `goalc/emitter/jit_mem_android.cpp`
   guarded by `#ifdef __ANDROID__`. The desktop allocator must keep
   working unchanged.

## Don't

- Don't replace SDL with a hand-written Android surface — SDL3's Android
  driver is what makes the activity bridge work.
- Don't gate the renderer behind `#if 0`. The GLES translation is the
  point of this phase.
- Don't try to embed `goalc` itself inside `libgk.so`. `goalc` runs on
  the build host (phases 14-16 use it).
- Don't regress the x86 desktop build. Both `cmake -B build` (x86) and
  `cmake -B build-android` (arm64) must continue to succeed.

## Validator

```
.autoport/validators/phase-12-android-runtime.sh
```

It nukes `build-android/`, reconfigures with the NDK toolchain, builds
the `gk` target, and inspects the resulting `libgk.so`.

## Pitfalls

- The NDK uses Clang. Stricter `-Wall` may turn previously-silent
  signed/unsigned mismatches into errors. Fix the code, don't relax
  `-Werror`.
- `<filesystem>` requires `-lc++_static` or the shared variant in NDK r27.
- Inline assembly: anything that survived phase 7 must already be NEON.
  Grep for `__asm__` / `asm(` in `common/` and `game/`.
- GLES precision qualifiers: vertex shaders default to `highp`, fragment
  shaders have NO default for `float` in GLES — you MUST declare one or
  the shader compiler errors.

## Success

```
== Phase 12 validator (real Android runtime in libgk.so) ==
  found: build-android/lib/arm64-v8a/libgk.so
  file: ... ARM aarch64 ... shared object ...
  size: NN... bytes (floor: 2097152)
  DT_NEEDED:
    ... liblog.so ...
    ... libSDL3.so or libGLESv3.so ...
  GOAL runtime markers found in exported symbols
== Phase 12 validator PASSED ==
```
