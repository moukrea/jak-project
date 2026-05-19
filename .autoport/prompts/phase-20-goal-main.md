# Phase 20 — Wire `goal_main` into `gk_sdl_main` so the kernel actually loads

## Goal

Replace the phase-18 `gk_sdl_main` placeholder (clear-color demo) with the
real game runtime entry point. After this phase, launching the APK causes
the GOAL kernel to come up far enough to:

1. Load `KERNEL.CGO` from the extracted iso_data path.
2. Initialize the kheap (kernel heap).
3. Spawn the gkernel dispatcher thread.
4. Reach the interpreter-ready state, idling waiting for work.

No rendering yet — that's phases 21-22 (shader port, then sustained
frames). We're proving the **kernel boots**, not that the engine draws.

This is the phase that will surface any latent AArch64 emitter bugs from
phases 01-08 — real GOAL code (kernel.gc, gstate.gc, gkernel.gc) exercises
register pressure and edge cases the synthetic test corpora can't hit.
If a CGO is loaded and SIGILLs on first call, that's the signal — see
"Failure modes" below.

## Concrete deliverables

1. **Link the full game/runtime libraries into `libgk.so`.**
   Today `android/CMakeLists.txt` only links a curated kernel subset
   (`kboot`, `kmalloc`, `ksocket`). Extend it to link:
   - `game/main.cpp` (renamed function — see below)
   - `game/runtime.cpp`
   - All of `game/kernel/common/*.cpp`
   - All of `game/kernel/jak1/*.cpp`
   - The dependencies these pull in from `common/log/`, `common/util/`,
     `common/symbols/`, etc.

   Keep using `--whole-archive` so the marker symbols stay in dynsym.
   Keep the existing `android/android_runtime_compat.cpp` shim for the
   bits that need Bionic-specific impls — but minimize it. Where the
   upstream code can be portably compiled, prefer that over a shim.

2. **Refactor `game/main.cpp`** so its `main` body is callable from
   our JNI entry point without the executable-only `main(argc, argv)`
   linkage:
   - Rename the existing `int main(int argc, char** argv) { … }` body
     into `int goal_main(int argc, char** argv) { … }`.
   - On non-Android builds, keep a thin `int main(int argc, char** argv)
     { return goal_main(argc, argv); }` so the desktop `gk` binary
     still links.
   - The branch must be `#ifndef __ANDROID__` (NOT `__linux__`).

3. **`gk_sdl_main` body** in `android/gk_android_main.cpp` becomes:
   ```cpp
   int gk_sdl_main(int /*argc_ignored*/, char** /*argv_ignored*/) {
     __android_log_print(ANDROID_LOG_INFO, "opengoal-gk", "gk_sdl_main: entered");
     // Resolve the per-flavor game name from a global the JNI bridge sets.
     const char* game_name = g_selected_game ? g_selected_game : "jak1";
     // data_root was set in Java via NativeGk.setDataRoot(getFilesDir() + "/iso_data/" + game_name)
     const char* data_root = g_data_root ? g_data_root : "";

     // Assemble argv for goal_main. -fakeiso tells the runtime to read
     // from a filesystem directory rather than a virtual ISO image.
     // -iso-data <path> overrides the data root.
     const char* argv[] = {
       "gk",
       "--game",       game_name,
       "--portable",
       "-fakeiso",
       "-iso-data",    data_root,
       nullptr,
     };
     int argc = (int)(sizeof(argv) / sizeof(argv[0])) - 1;

     __android_log_print(ANDROID_LOG_INFO, "opengoal-gk",
       "goal_main: argv=[%s,%s,%s,%s,%s,%s,%s]",
       argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6] ? argv[6] : "(null)");

     int rc = goal_main(argc, (char**)argv);
     __android_log_print(ANDROID_LOG_INFO, "opengoal-gk", "goal_main: returned %d", rc);
     return rc;
   }
   ```

4. **Pass game_name and data_root from Java to native.**
   - Add `NativeGk.setSelectedGame(String name)` and `NativeGk.setDataRoot(String path)` JNI stubs.
   - Implement them in `android/gk_android_main.cpp` to copy to
     module-static `g_selected_game` / `g_data_root` (strdup'd; never freed
     — process-lifetime).
   - In `MainActivity.onCreate`, call them BEFORE `super.onCreate`
     (so SDLActivity's lifecycle gets them in time):
     ```java
     NativeGk.setSelectedGame(getString(R.string.game_name));
     NativeGk.setDataRoot(new File(getFilesDir(), "iso_data/" + getString(R.string.game_name)).getAbsolutePath());
     super.onCreate(savedInstanceState);
     ```

5. **Log markers** (the validator greps for these):
   - `goal_main: argv=[gk,--game,jak1,--portable,-fakeiso,-iso-data,...]`
   - `kheap_alloc: OK` (existing or added log inside `kmalloc.cpp`'s
     kheap init — prefer to use an existing one; only add if absent)
   - `KERNEL.CGO: loaded <N> bytes` (add this around the kernel.cgo
     load path, in `kboot.cpp` or `kdgo.cpp` wherever the file open
     happens)
   - `gkernel: dispatcher started` (add when the dispatcher thread/loop
     enters its main loop)

## Don't

- Do **not** add `-nokernel`. The whole point is to load KERNEL.CGO.
- Do **not** silently skip files that fail to load. If `KERNEL.CGO`
  can't open or fails to map, log an error and `abort()` — clean
  failure surfaces in logcat.
- Do **not** patch the runtime to use lowercase file names. The PS2
  convention is uppercase; the desktop pipeline reads uppercase from
  `iso_data/jak1/*`. Keep it.
- Do **not** disable `LTO` or `-Wall -Werror`. NDK Clang catches real
  issues; fix them, don't suppress.

## Failure modes & where to look

Phase 19 (emitter-stress under qemu-aarch64) should have caught most
emitter bugs already, so CGO-execution SIGILL on the device is unlikely.
If you see one here, it means the bug only surfaces under Bionic /
Android, not under Linux/glibc qemu — which is plausible (different
allocator layout, different syscall numbers).

- **`SIGILL` inside a code page loaded from a CGO**: the emitter
  generated an invalid AArch64 encoding for a specific instruction
  pattern. Use `adb logcat -b crash` + `tombstones` to get the
  faulting PC. Fix in `goalc/emitter/IGen_arm64.cpp`, then re-run
  **both** the emitter-stress AND CGO regeneration:
      bash .autoport/validators/phase-19-emitter-stress.sh
      bash .autoport/validators/phase-14-jak1.sh
  before re-attempting phase 20.

- **`SIGSEGV` in libgk.so's own code** (not CGO-loaded): a portability
  bug — likely `pthread_setname_np` one-arg form, `<execinfo.h>`,
  `mallinfo` etc. These are catalogued in the phase-22 prompt, but
  fix them here if they block the kernel boot.

- **`KERNEL.CGO: loaded 0 bytes`** or file-not-found:
  the data_root passed from Java is wrong, or the extracted files
  aren't where we think. Verify with `adb shell run-as <pkg> ls files/iso_data/jak1/KERNEL.CGO`.

- **Hangs on first goal_main call** with no log output: stuck before
  the first `__android_log_print`. Sprinkle log lines into the boot
  path until you find the silent hang point. Common: blocking I/O
  on a missing dir, deadlock in static init.

## Validator

```
.autoport/validators/phase-20-goal-main.sh
```

Builds, installs (assuming sentinel from phase 17 already extracted),
launches, watches logcat for the goal_main+kheap+KERNEL.CGO+gkernel
sequence within 90s. Crash = fail. Marker missing = fail.

## Success

`adb logcat` shows the kernel boot sequence above within 90 seconds of
launching the activity. Surface may still be black (rendering is
phase 21). Desktop x86 build (`cmake --build build --target gk`) still
links and runs.
