# Phase 18 — SDL3 cross-build + Activity↔SDL surface bridge

## Goal

Get an SDL3 window with a working EGL/GLES context on the user's Activity
SurfaceView. After this phase, `libgk.so` linked with SDL3 (static) can
call `SDL_CreateWindow(SDL_WINDOW_OPENGL)` and `SDL_GL_CreateContext`,
and the resulting context renders to the existing per-flavor Activity's
SurfaceView. No game loop yet — just `SDL_Init`, window, context,
`glClear(...)`, `eglSwapBuffers`, then idle.

This unblocks phase 19 (real `goal_main`) because the runtime expects
SDL to own the window and the GL context.

## Concrete deliverables

1. **Cross-build SDL3 as a static library** linked into `libgk.so`.
   - Source: `third-party/SDL/` (SDL 3.4, already vendored).
   - In `android/CMakeLists.txt` (Android-only build), add SDL via
     `add_subdirectory` with options forced:
       ```cmake
       set(SDL_STATIC ON CACHE BOOL "" FORCE)
       set(SDL_SHARED OFF CACHE BOOL "" FORCE)
       set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
       set(SDL_AUDIO ON CACHE BOOL "" FORCE)
       set(SDL_VIDEO ON CACHE BOOL "" FORCE)
       set(SDL_RENDER OFF CACHE BOOL "" FORCE)   # we use raw GLES
       add_subdirectory(${CMAKE_SOURCE_DIR}/third-party/SDL
                        ${CMAKE_BINARY_DIR}/SDL-android EXCLUDE_FROM_ALL)
       ```
   - Link `libgk.so` with `SDL3::SDL3-static` via `--whole-archive`
     so the JNI `SDL_*` entry points expected by the Java side survive
     `--gc-sections` and `--exclude-libs`.
   - Make sure the desktop build is **NOT** affected — the SDL
     add_subdirectory call must live in a branch guarded by
     `if(ANDROID)` or in `android/CMakeLists.txt` only.

2. **Drop SDL3's Java-side bridge into our app source set.**
   - Copy `third-party/SDL/android-project/app/src/main/java/org/libsdl/app/`
     into `android/app/src/main/java/org/libsdl/app/`.
     (This is the canonical way SDL3 expects the activity to be wired —
     do not hand-roll an equivalent.)
   - In `android/app/build.gradle.kts`, no per-flavor changes needed for
     this — the SDL Java sources are shared across all three game flavors.

3. **Make MainActivity extend SDLActivity.**
   - File: `android/app/src/main/java/org/opengoal/gk/MainActivity.java`.
   - Change `extends AppCompatActivity` → `extends org.libsdl.app.SDLActivity`.
   - Override `getLibraries()` to return `new String[] { "gk" }` (loads
     `libgk.so` instead of SDL's default `libSDL3.so`/`libmain.so`).
   - Override `getMainSharedObject()` to return the absolute path SDL
     should `dlopen` (i.e., the `libgk.so` extracted by the system).
   - Override `getMainFunction()` to return `"gk_sdl_main"` — phase 19
     will provide that symbol. For now, define a temporary
     `gk_sdl_main` in `android/gk_android_main.cpp` that just calls
     `SDL_Init(SDL_INIT_VIDEO)`, creates an `SDL_WINDOW_OPENGL` window,
     creates a GL context, clears to a recognizable color (e.g., dark
     blue), swaps the buffer, then sleeps in a `for(;;)` loop polling
     events until quit.
   - Keep the `TouchControlsView` overlay — it's still useful and
     SDLActivity supports child views via `mLayout`.

4. **Logging — exact strings, the validator greps for them:**
   - `gk_sdl_main: entered`
   - `SDL_Init: video subsystem OK`
   - After `SDL_CreateWindow`: `SDL_CreateWindow: NxM created` (use the
     actual returned dimensions).
   - After `SDL_GL_CreateContext`: `SDL_GL_CreateContext: ok`
   - After first `SDL_GL_MakeCurrent`: `eglMakeCurrent: success`
   - Right after the first `SDL_GL_SwapWindow`:
     `eglSwapBuffers: ok` (you'll have to add this log explicitly; SDL
     doesn't emit one by default).
   - After `glGetString(GL_RENDERER)`:
     `GL_RENDERER: <whatever the driver returns>` (Adreno on the user's
     Redmi Note 9 Pro).

5. **Touch passthrough** still works — `MainActivity.dispatchTouchEvent`
   is now inherited from `SDLActivity` which converts to `SDL_EVENT_*`.
   That's fine; we'll wire the GOAL pad mapping in phase 22. For this
   phase, just ensure `TouchControlsView` still draws.

## Don't

- Do **not** build SDL3 as a shared library. The app's lib path is
  `lib/arm64-v8a/`, but Android's loader resolves `dlopen("SDL3")`
  from there only if the .so is named exactly `libSDL3.so` and is
  added to `lib/`. Static-link into libgk.so is simpler and matches
  the phase-12 design ("one .so, libgk.so, owns everything").
- Do **not** call `SDL_Quit` from `gk_sdl_main` — the SDLActivity Java
  side manages lifecycle and will call it during `onDestroy`.
- Do **not** delete the SurfaceHolder.Callback we currently have if
  the SDLActivity inheritance keeps it; if you switch the surface
  management to SDL, just remove the obsolete code rather than
  leaving dead code in.
- Do **not** introduce a runtime dependency on `libc++_shared.so`
  unless absolutely required. NDK r27 + static libc++ is the path
  we're already on.

## Pitfalls

- SDL3's CMakeLists adds many feature flags. The cache `FORCE` calls
  above are required because SDL caches its own defaults.
- The SDLActivity Java code expects specific JNI symbols
  (`Java_org_libsdl_app_SDLActivity_*`). Those come from
  `SDL/src/core/android/SDL_android.c` which compiles when
  `SDL_VIDEO_DRIVER_ANDROID=ON`. Verify with `nm -D libgk.so | grep SDLActivity`
  after the build — you should see the JNI entries.
- `--exclude-libs` from phase 12 may hide SDL's JNI symbols from the
  dynsym. Either widen the exclude list with an explicit SDL include,
  or drop `--exclude-libs` for the SDL .a file.
- `MainActivity` is now an `SDLActivity` — the `LoaderActivity`'s
  `startActivity(MainActivity.class)` still works because the Intent
  flow is unchanged. The intent filter in AndroidManifest (Loader is
  LAUNCHER, Main is not) is also unchanged.

## Validator

```
.autoport/validators/phase-18-sdl3-bridge.sh
```

Builds + installs + launches via LoaderActivity (which transitions to
MainActivity), then watches logcat for the SDL/EGL marker sequence
above within 60s. Fails on any crash signature or absence of any of
the markers.

## Success

App launches, "Preparing game data…" screen appears (or skips if
sentinel exists), then a colored surface (the SDL clear color) is
visible on the Activity SurfaceView. logcat shows the SDL init →
window → context → swap sequence within 30s. No crash. Desktop x86
build still passes.
