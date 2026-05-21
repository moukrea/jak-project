# D3 — SDL3 Android driver wired to MainActivity's SurfaceView; eglSwapBuffers sustained

**Bucket**: D — Android port (REDESIGN.md §8)
**Authoring**: 2026-05-21, orchestrator session (supervisor absent — see SUPERVISOR_JOURNAL.md)
**Validator**: `.autoport/validators/phase-D3-android-sdl3-surface.sh` — 22 checks, structural
**Hand-off to**: D4 (device-side title-screen trace-diff against linux-arm64 oracle)

## What is wired

D3 produces a `build-android/lib/arm64-v8a/libgk.so` that contains
the **real SDL3 Android video driver** statically linked from
`third-party/SDL/src/video/android/`. The library satisfies four
structural invariants the validator enforces:

1. **MainActivity hosts the SurfaceView through SDL3.**
   `org.opengoal.gk.MainActivity extends org.libsdl.app.SDLActivity`,
   so `SDLActivity.onCreate` constructs an `mLayout RelativeLayout`,
   inserts a `SDLSurface` (a `SurfaceView` subclass) as its child,
   and calls `setContentView(mLayout)`. The Activity's `SurfaceView`
   *is* SDL3's SurfaceView; there is no second surface anywhere in
   the Activity's view hierarchy.

2. **The SDL3 Android GL driver is compiled in.**
   `libgk.so`'s defined-symbol table contains
   `Android_GLES_CreateContext`, `Android_GLES_MakeCurrent`,
   `Android_GLES_SwapWindow`, `Android_CreateWindow`, and
   `SDL_EGL_SwapBuffers` — the chain that ultimately calls
   `eglSwapBuffers` on the SurfaceView's native window.

3. **The Java↔native bridge is exported.**
   `libgk.so` exports `Java_org_libsdl_app_SDLActivity_nativeRunMain`,
   `nativeSetupJNI`, `onNativeSurfaceCreated`, `onNativeSurfaceChanged`,
   and `onNativeSurfaceDestroyed`. Without these, the Java
   `SDLSurface.surfaceCreated → SDLActivity.onNativeSurfaceCreated`
   call chain wouldn't reach C, and the SDL thread would block
   forever waiting for an EGL surface.

4. **The render loop sustains `SDL_GL_SwapWindow` under real exit
   conditions.** `android_renderer_run` is a real `while` loop that
   pumps `SDL_PollEvent`, clears the color + depth buffers, calls
   `SDL_GL_SwapWindow(window)`, increments a process-lifetime
   `std::atomic<uint64_t>` frame counter, and emits an
   `__android_log_print(... "android_renderer: sustained swap N")`
   marker every 60 frames. The loop exits **only** when either
   `MasterExit` leaves `RuntimeExitStatus::RUNNING` or an
   `SDL_EVENT_QUIT` / `SDL_EVENT_TERMINATING` event arrives. No
   fixed-iteration count, no synthetic timer, no `for(;;)`-without-
   break trap.

The atomic frame counter is reachable from Java through
`Java_org_opengoal_gk_NativeGk_getRendererFrameCount`, returning a
`jlong`. D3's validator doesn't call it directly; D4's device
validator will, asserting the counter grows monotonically while the
APK is foregrounded.

## What is NOT wired here (deferred to D4)

- **Device-side sustained-swap evidence.** Headless mode has no
  physical device and the `opengoal_arm64` AVD has
  `hw.gpu.enabled=no`, so no EGL on the emulator either. The
  "sustained" claim is verified *structurally* (symbol-table proof
  + body-size floor + source-shape greps). On-device sustained-swap
  evidence is D4's gradle-assemble + `adb logcat` + counter-probe
  job.

- **APK packaging.** D3 builds `libgk.so` via `cmake --build
  build-android --target gk` directly. The full
  `./gradlew :app:assembleJak1Debug` is D4's job; it bundles
  `libgk.so` into `app-jak1-debug.apk` along with the
  Jak 1 iso_data asset overlay.

- **The real renderer.** Today's swap loop still clears to dark
  blue every frame. The OpenGL renderer port
  (`game/graphics/opengl_renderer/`) is the multi-phase work the
  redesign labels as bucket-E rendering content. D3 only
  guarantees that the substrate the renderer will draw onto
  exists and survives `eglSwapBuffers`.

## Validator surface

22 checks, summarised in the validator script header. Highlights:

- **Symbol-table proof** (checks 12-14). Five SDL3 Android driver
  symbols, five SDL3 Java bridge symbols, four autoport NativeGk
  JNI exports — all required to be defined in `libgk.so`'s
  `--defined-only -D` dump.

- **Function-body-size floor** (check 15).
  `nm --print-size --defined-only` on `android_renderer_run`; the
  size field must be ≥ 0x320 (800 bytes). A `return 0` stub
  weighs ~12 bytes; a real bring-up + loop weighs in the low
  kilobytes range.

- **Source-shape greps** (check 4). The renderer source must
  contain `SDL_Init / SDL_CreateWindow / SDL_GL_CreateContext /
  SDL_GL_MakeCurrent / SDL_GL_SwapWindow / SDL_PollEvent`, a
  `MasterExit == RUNNING` test, an `SDL_EVENT_QUIT /
  SDL_EVENT_TERMINATING` handler, a `std::atomic<uint64_t>`
  declaration named `g_renderer_frame_count` with a `fetch_add(1)`
  inside the loop body, an `__android_log_print` containing
  `"sustained swap"`, and a `% 60 == 0` or `% 120 == 0` modular
  guard.

- **Anti-cheat greps** (checks 5, 16-19). No `__attribute__((weak))`,
  no `kStateSeq` / `kSyntheticBootSequence` / `weak_jak1_` / solid-
  color cheat fragment shaders introduced since A4. The
  codegen + classifier files are byte-identical to their A4
  baselines.

- **Cross-phase invariants** (check 20). C4 + D1 + D2 validators
  all re-run and exit 0; the bucket-C and earlier-bucket-D chain
  cannot regress.

- **Desktop smoke** (check 21). `build-x86/game/gk` still reaches
  `link finish: logo` within 60s — the desktop oracle isn't
  damaged by anything D3 touched.

## Engineering notes

The previous orchestrator's phase-18 validator
(`phase-18-sdl3-bridge.sh`) ran on a connected device and greped
logcat for strings like `eglSwapBuffers: ok` and `SDL_GL_CreateContext:
ok`. Those strings are `printf` literals in `android_renderer.cpp`
— under the reward-signal critique in REDESIGN.md §1, a sufficiently
motivated agent could emit them from a stub loop without ever
calling `SDL_GL_SwapWindow`. D3's validator is structural by
contrast: the symbols are SDL3 upstream names, the function-body
size is measured, and the loop shape is greped from the source. A
stub that satisfied all 22 checks would, by virtue of satisfying
them, have to *be* a real SDL3 + sustained-loop implementation.

That doesn't mean D3 is the end of the story. D3 says "the
substrate is real and the loop is shaped honestly." It does NOT
say "the loop runs on hardware for N seconds without crashing." A
GLES context lost on `SurfaceDestroyed`, an `eglSwapBuffers` error
that the loop fails to propagate, a `glClear` that triggers a
device-specific reset — all of these are runtime failures D3 cannot
catch. D4's device run + frame-counter probe is what catches them.

In headless mode (no device, no GPU-enabled AVD), D3 is the
strongest reality check the orchestrator can do *itself*. D4 will
have to wait until a physical device is connected, or until the
host's emulator AVD gains GPU support.
