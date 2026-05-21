# Phase D3 — SDL3 Android driver wired to MainActivity's SurfaceView; eglSwapBuffers sustained

## What this phase delivers

A **buildable** libgk.so for `arm64-v8a` that:

1. **Statically links SDL3's Android video driver.** `libgk.so`'s
   `--defined-only` symbol table contains `Android_GLES_CreateContext`,
   `Android_GLES_MakeCurrent`, `Android_GLES_SwapWindow`,
   `Android_CreateWindow`, `SDL_EGL_SwapBuffers` — the actual SDL3
   functions that drive eglCreateWindowSurface + eglSwapBuffers on
   Android. These are real symbols compiled from
   `third-party/SDL/src/video/android/` with non-trivial bodies.
2. **Exposes the Java↔native bridge.** Same `libgk.so` exports
   `Java_org_libsdl_app_SDLActivity_nativeRunMain`,
   `Java_org_libsdl_app_SDLActivity_nativeSetupJNI`,
   `Java_org_libsdl_app_SDLActivity_onNativeSurfaceCreated`,
   `Java_org_libsdl_app_SDLActivity_onNativeSurfaceChanged`,
   `Java_org_libsdl_app_SDLActivity_onNativeSurfaceDestroyed`. These
   are the JNI entry points the Java `SDLSurface` calls when the
   `SurfaceView`'s `SurfaceHolder.Callback` fires `surfaceCreated /
   Changed / Destroyed`. Without them the SDL3 thread launched by
   `nativeRunMain` cannot create or resize its EGL window surface.
3. **`MainActivity` extends `SDLActivity`.** That's how SDL3 owns
   the Activity's SurfaceView: `SDLActivity.onCreate` constructs an
   `mLayout` RelativeLayout, inserts an `SDLSurface` (which **is** a
   `SurfaceView`) as its child, and calls `setContentView(mLayout)`.
   `MainActivity.getMainSharedObject()` returns the absolute path to
   `libgk.so`, and `MainActivity.getMainFunction()` returns
   `"gk_sdl_main"` — the C symbol SDL dlsym's once the SDL thread
   starts.
4. **The native render loop sustains `eglSwapBuffers`.**
   `android_renderer_run` (called from `goal_main` on the SDL main
   thread, dispatched from `gk_sdl_main`) creates an SDL window with
   `SDL_WINDOW_OPENGL`, makes a GLES 3.2 context current, and then
   enters a real `while` loop that:

   - pumps `SDL_PollEvent` and exits on `SDL_EVENT_QUIT /
     SDL_EVENT_TERMINATING`,
   - issues `glClear` of the color + depth buffers,
   - calls `SDL_GL_SwapWindow(window)` (which on Android is
     `Android_GLES_SwapWindow → SDL_EGL_SwapBuffers → eglSwapBuffers`),
   - increments an atomic frame counter,
   - and emits a `logcat` marker every 60 frames (`android_renderer:
     sustained swap N` for `N = 60, 120, 180, …`) — the validator's
     evidence that the loop is iterating rather than swapping once
     and returning.

   The loop's exit conditions are *real*: it cannot terminate without
   either `MasterExit` transitioning out of `RUNNING` or an SDL quit
   event arriving. No timer-based fake exit, no synthetic sequence,
   no fixed-iteration count.

5. **JNI handle for the frame counter.** The atomic frame counter
   is exposed to Java through
   `Java_org_opengoal_gk_NativeGk_getRendererFrameCount`, returning a
   `jlong`. D3's structural validator does not actually call it —
   the function exists so D4's device validator can probe the counter
   without parsing logcat. The exported symbol is the proof; the
   body is a one-line atomic load and intentionally short, but the
   wrapping `android_renderer_run` is the meaty piece this phase
   actually validates.

After D3: `cmake --build build-android --target gk` produces a
`build-android/lib/arm64-v8a/libgk.so` whose symbol table satisfies
all the above, and `android_renderer_run`'s compiled body is large
enough that a `return 0` stub cannot impersonate it. The APK is
not yet packaged here — that's D4's gradle assemble step plus the
on-device trace-diff against the linux-arm64 reference run.

## Why this matters

Phase 18 (`18-sdl3-bridge`) claimed this work. Its validator
(`.autoport/validators/phase-18-sdl3-bridge.sh`) ran on a connected
device and greped logcat for strings like `eglSwapBuffers: ok` and
`SDL_GL_CreateContext: ok`. The claude session that wrote that
validator was honest, but the *check* was a log-string grep — the
strings are printf literals in `android_renderer.cpp`. A future
session could (and the previous orchestrator did, in phases 28-30)
emit those strings from a placeholder loop that never actually called
`SDL_GL_SwapWindow`, and the validator would still pass.

D3's reframing aligns with the supervisor's reality-check toolkit
(`SUPERVISOR_PROMPT.md` §"Reality checks"):

- **Symbol-table differential.** `Android_GLES_SwapWindow` is a
  symbol that *must* be defined in `libgk.so` if SDL3's Android
  video driver was compiled in. A stub cannot fake it — the symbol
  name comes from upstream SDL3 source.
- **Function-body-size sanity.** `android_renderer_run`'s compiled
  size is measured. A loop that pumps events + clears + swaps is on
  the order of ~1-2 KB after optimisation. A `return 0` stub is
  ~20 bytes. The validator demands ≥ 800 bytes.
- **No `__attribute__((weak))` anywhere.** The phase-28 cheat
  pattern is forbidden by grep.
- **No solid-color cheat introduced since A4.** Anti-phase-29
  fragment-shader check inherited from D2's validator.

Headless mode constraint: there is no physical device in the
orchestrator's environment (`adb devices` returns 0). The
`opengoal_arm64` emulator AVD that exists is configured with
`hw.gpu.enabled=no`, so spinning it up cannot exercise EGL or GLES.
D3 therefore performs *structural* reality checks only; the actual
sustained-swap evidence on hardware is D4's job (the bucket-D
trace-diff at the title milestone). D3 is the build-time proof that
the substrate D4 will eventually drive is real, not stubbed.

## Engineering background (from D2's tail state)

D2 closed at 18:24:26 UTC with all 45 shader pairs (90 compile
units) translating cleanly under `glslc --target-env=opengl`. The
desktop `gk` still reaches `link finish: logo`, and the C4/D1
invariants are unchanged.

D3 does NOT touch:

- The Bionic shim layer in `game/android-arm64/` (locked since D1).
- The aarch64 codegen / classifier files (locked since A4).
- The runtime linker `klink.cpp` (locked since C4).
- `game/graphics/opengl_renderer/shaders/preprocess.py` or any
  `.vert` / `.frag` file (locked since D2).
- `game/kernel/` source (only the JNI bridge in
  `android/gk_android_main.cpp` is touched, not the kernel itself).

What D3 *does* touch:

- `android/android_renderer.cpp` — render loop gains the frame
  counter, periodic logcat marker, and exit-condition guarantees
  the validator can statically verify.
- `android/gk_android_main.cpp` — adds the
  `Java_org_opengoal_gk_NativeGk_getRendererFrameCount` JNI export.
- `android/app/src/main/java/org/opengoal/gk/NativeGk.java` — adds
  the matching Java static native declaration (so the JNI symbol
  isn't dropped as unused by the linker's `--gc-sections`).
- `.autoport/lib/d3_build.sh` — convenience runner for
  `cmake --build build-android --target gk` with the configure step
  baked in for first-time builds. Analogous to `d1_build.sh`.
- `.autoport/reports/D3-sdl3-surface.md` — headline report.

The validator inspects `build-android/lib/arm64-v8a/libgk.so`
directly; it does not unzip an APK. APK packaging is D4's gradle
step.

## Concrete deliverables

### 1. android/android_renderer.cpp — sustained swap loop with telemetry

The existing render loop (post-supervisor-rollback dark-blue clear)
already calls `SDL_GL_SwapWindow` inside a `while` body. D3 adds:

```cpp
// File-scope atomic counter for the validator + JNI probe.
namespace {
std::atomic<uint64_t> g_renderer_frame_count{0};
}

uint64_t android_renderer_frame_count() {
  return g_renderer_frame_count.load(std::memory_order_relaxed);
}

// Inside the existing while loop, just after SDL_GL_SwapWindow:
const uint64_t n = g_renderer_frame_count.fetch_add(1, std::memory_order_relaxed) + 1;
if ((n % 60) == 0) {
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "android_renderer: sustained swap %" PRIu64, n);
}
```

The frame counter is reset to 0 on each `android_renderer_run` entry
(static init) so a quick exit + relaunch doesn't carry stale state
into the next run.

The `printf`-style format string includes `PRIu64` from
`<cinttypes>` so the format is portable across ILP32 / LP64 hosts —
not strictly necessary for Android (always LP64) but follows the
upstream OpenGOAL convention.

### 2. android/gk_android_main.cpp — JNI handle for frame count

```cpp
JNIEXPORT jlong JNICALL
Java_org_opengoal_gk_NativeGk_getRendererFrameCount(JNIEnv* /*env*/,
                                                    jclass /*clazz*/) {
  return (jlong)android_renderer_frame_count();
}
```

`android_renderer_frame_count()` is declared in `android_renderer.h`
so the C linkage stays clean. The JNI prefix
`Java_org_opengoal_gk_NativeGk_` matches `NativeGk.java`'s fully
qualified class name.

### 3. android/app/src/main/java/org/opengoal/gk/NativeGk.java — Java declaration

A `public static native long getRendererFrameCount();` method, with a
short Javadoc comment explaining it returns the cumulative
`SDL_GL_SwapWindow` count since `android_renderer_run` started.

### 4. .autoport/lib/d3_build.sh — convenience runner

```bash
#!/usr/bin/env bash
# Configure (idempotent) + incremental build of libgk.so for arm64-v8a.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
. .autoport/lib/android-env.sh

BUILD_DIR=build-android
TOOLCHAIN="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"

if [ ! -f "$BUILD_DIR/CMakeCache.txt" ]; then
  cmake -S . -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-29 \
    -DGOALC_BACKEND=arm64 \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo
fi

cmake --build "$BUILD_DIR" --target gk -j
```

Exits non-zero on any cmake/ninja failure. The validator captures
stdout+stderr to a temp file so on failure the developer sees the
actual ninja error rather than a generic "build failed" message.

### 5. .autoport/reports/D3-sdl3-surface.md — headline report

Short markdown describing what was wired (SDL3 Android driver,
SurfaceView path, sustained swap loop), the validator surface
(symbol-table proof, body-size floor, anti-cheat greps), and the
known D4 hand-off (device-side title-screen trace-diff).

The validator greps the headline for the literal substrings
`SDL3`, `SurfaceView`, and `eglSwapBuffers` in the first 30
non-blank lines. (Anti-stub: a one-line "TODO: write report" file
would not satisfy three independent substring checks.)

## Anti-cheats (validator enforces these)

The D3 validator is strict by design. In rough order of strictness:

1. **Required files exist** — `android_renderer.cpp`,
   `android_renderer.h`, `gk_android_main.cpp`,
   `MainActivity.java`, `NativeGk.java`, `AndroidManifest.xml`,
   `.autoport/lib/d3_build.sh`, `.autoport/reports/D3-sdl3-surface.md`,
   `third-party/SDL/src/video/android/SDL_androidgl.c`.

2. **MainActivity extends SDLActivity.** Grep
   `MainActivity.java` for `extends SDLActivity`, plus the four
   required overrides (`getLibraries`, `getMainSharedObject`,
   `getMainFunction`, `getArguments`). `getLibraries` must return
   `{"gk"}`. `getMainFunction` must return `"gk_sdl_main"`.
   `getMainSharedObject` must return a path containing `libgk.so`.

3. **AndroidManifest landscape + no touch-overlay.** MainActivity
   has `android:screenOrientation="sensorLandscape"` (NOT
   `portrait`). The manifest contains no reference to
   `TouchControlsView`. LoaderActivity is the launcher (intent
   filter MAIN/LAUNCHER points at LoaderActivity, not
   MainActivity).

4. **android_renderer.cpp has the sustained-swap shape.** The
   file contains:

   - `SDL_Init(SDL_INIT_VIDEO)`,
   - `SDL_CreateWindow`,
   - `SDL_GL_CreateContext`,
   - `SDL_GL_MakeCurrent`,
   - exactly one `while` loop body containing both
     `SDL_PollEvent` AND `SDL_GL_SwapWindow`,
   - a `fetch_add` on a `std::atomic<uint64_t>` frame counter
     inside the loop,
   - an `__android_log_print` call inside the loop guarded by a
     modular condition (`% 60 == 0` or equivalent),
   - `MasterExit == RuntimeExitStatus::RUNNING` (or equivalent) in
     the loop's primary exit condition,
   - an `SDL_EVENT_QUIT` check in the event handler.

5. **No anti-cheat patterns in android_renderer.cpp.** No
   `__attribute__((weak))`, no `kStateSeq`, no `sleep(` outside the
   per-frame `SDL_Delay`, no `for (;;)` infinite loop without a
   real exit, no fixed-iteration counter loop (`for (int i = 0; i <
   N; i++)`).

6. **NativeGk.java has the frame-count native method.** Grep for
   `public static native long getRendererFrameCount()`.

7. **gk_android_main.cpp has the JNI bridge.** Grep for the full
   JNI symbol name `Java_org_opengoal_gk_NativeGk_getRendererFrameCount`
   in source.

8. **android/CMakeLists.txt links SDL3-static + EGL/GLESv3.** Grep
   for `SDL3-static`, `EGL`, `GLESv3` link entries; grep for
   `add_subdirectory(${JAK_ROOT}/third-party/SDL` to prove SDL3 is
   built from source (not a prebuilt blob substitute).

9. **`d3_build.sh` produces a real libgk.so.** Runs the script,
   asserts `build-android/lib/arm64-v8a/libgk.so` exists, file(1)
   reports it as a 64-bit ARM aarch64 shared object.

10. **libgk.so stripped size ≥ 5 MB.** The previous orchestrator's
    phase-10 50 KB stub triggered the floor. libgk.so with SDL3 +
    GOAL kernel + mips2c + overlord stands around 20 MB
    unstripped; even stripped, the kernel archive plus SDL3 is
    well above 5 MB.

11. **libgk.so DT_NEEDED contains the Android graphics chain.**
    `libEGL.so`, `libGLESv3.so`, `liblog.so`, `libandroid.so`,
    `libdl.so`, `libm.so`, `libc.so` — the Bionic + GLES stack.

12. **libgk.so symbol table contains the SDL3 Android driver.**
    `llvm-nm --defined-only -D` shows `Android_GLES_SwapWindow`,
    `Android_GLES_CreateContext`, `Android_GLES_MakeCurrent`,
    `Android_CreateWindow`, `SDL_EGL_SwapBuffers`.

13. **libgk.so symbol table contains the SDL3 Java bridge.**
    Same nm dump shows `Java_org_libsdl_app_SDLActivity_nativeRunMain`,
    `Java_org_libsdl_app_SDLActivity_nativeSetupJNI`,
    `Java_org_libsdl_app_SDLActivity_onNativeSurfaceCreated`,
    `Java_org_libsdl_app_SDLActivity_onNativeSurfaceChanged`,
    `Java_org_libsdl_app_SDLActivity_onNativeSurfaceDestroyed`.

14. **libgk.so symbol table contains the autoport JNI exports.**
    `Java_org_opengoal_gk_NativeGk_setSelectedGame`,
    `Java_org_opengoal_gk_NativeGk_setDataRoot`,
    `Java_org_opengoal_gk_NativeGk_startGame`,
    `Java_org_opengoal_gk_NativeGk_getRendererFrameCount`.

15. **`android_renderer_run` body size ≥ 800 bytes.**
    `llvm-nm --print-size --defined-only` on the symbol; size
    field strictly greater than 0x320 (800).

16. **No `__attribute__((weak))` introduced since A4** — applied
    to the diff under `android/` and `game/` (excluding `.autoport/`
    and `build*`).

17. **No synthetic-state patterns introduced since A4** —
    `kStateSeq`, `kSyntheticBootSequence`, `weak_jak1_`,
    `synthetic.*gradient`, `kSolidColorOnly`, `engine: state=(boot|
    load|title)`.

18. **No solid-color cheat fragment shader introduced since A4** —
    same anti-phase-29 check D2 carries.

19. **Codegen + classifier files byte-identical to A4** — same
    files D1/D2 protect.

20. **C4 + D1 + D2 validators still pass** — the bucket-C and
    earlier bucket-D chain stays green.

21. **Desktop gk smoke test still reaches `link finish: logo`** —
    standard smoke gate.

22. **D3-sdl3-surface.md headline contains the three substrings.**
    `SDL3`, `SurfaceView`, `eglSwapBuffers` in the first 30
    non-blank lines.

## Don't

- **Do NOT remove or weaken the existing `android_renderer.cpp`
  exit conditions.** The `MasterExit` and `SDL_EVENT_QUIT /
  SDL_EVENT_TERMINATING` checks are the only honest way to exit the
  loop. A fixed-iteration `for` loop is a cheat.
- **Do NOT call `SDL_GL_SwapWindow` outside the loop body.** A
  one-shot swap followed by a `return 0` is the phase-29-style
  cheat the validator is built to catch.
- **Do NOT introduce `__attribute__((weak))` anywhere.** Strong
  symbols only. If a shim is unavoidable, abort() loudly.
- **Do NOT modify the codegen, classifier, klink, asm trampoline,
  or D1 Bionic shim files.** They're locked since their respective
  phases.
- **Do NOT modify shaders or `preprocess.py`.** D2 owns those.
- **Do NOT change the manifest's orientation back to portrait or
  re-add a touch-controls view.** The supervisor rollback removed
  them; phase D3 keeps them removed.
- **Do NOT touch `game/android-arm64/`** (D1's tree).
- **Do NOT modify the validator to loosen any check.** The
  forbidden-pattern grep on validator-script changes is inherited
  from D1/D2.
- **Do NOT add a synthetic dispatcher, sequenced log emitter, or
  any "fake render heartbeat" outside the real swap path.** The
  swap path *is* the heartbeat.
- **Do NOT package the APK in the D3 validator.** APK assembly is
  D4's job; D3 inspects `build-android/lib/arm64-v8a/libgk.so`
  directly.

## Success

`bash .autoport/validators/phase-D3-android-sdl3-surface.sh` exits
0. `build-android/lib/arm64-v8a/libgk.so` has the real SDL3
Android driver compiled in, the Java↔native bridge symbols
exported, the render loop sustains `SDL_GL_SwapWindow` calls under
real exit conditions with frame-counter telemetry, and the
bucket-C / D1 / D2 chain is intact.
