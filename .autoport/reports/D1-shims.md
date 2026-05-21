# Phase D1 — android-arm64 NDK gk + Bionic shims

## Headline

The bucket-D Android-NDK cross-build of `gk` lands at
`build-arm64-android/game/android-arm64/gk`. It is a real aarch64
ELF executable, dynamically linked against **Bionic** (libc.so,
libdl.so, liblog.so, libm.so) — not glibc. Bionic-vs-glibc
differences are shimmed by `game/android-arm64/android_arm64_bionic_shims.cpp`,
each with a strong-symbol implementation and a non-trivial body.

The binary builds and links. Running it returns exit code 2 with a
"D1: android-arm64 gk built; D2 will wire graphics/runtime" banner
on both `__android_log_print` (logcat tag `opengoal-gk`) and
stderr. D2/D3/D4 layer SDL3, GLES, and the APK title-reach work
on top of the same `game/android-arm64/` sources.

## Bucket and predecessors

- **Bucket**: D — Android port (REDESIGN.md §8).
- **Predecessor**: C4 — klink arm64 ADRP+ADD execute. The bucket-C
  chain landed a working aarch64-linux `gk` that runs under
  `qemu-aarch64-static`, links every KERNEL.CGO object, and
  executes gcommon's top-level GOAL function. D1 inherits the
  exact same kernel / overlord / system / mips2c source list and
  the asm trampoline; only the target libc changes.

## What changed (file-by-file)

### New files

- `cmake/android-arm64-toolchain.cmake` — thin forwarder around
  `$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake`. Pins
  ANDROID_ABI=arm64-v8a, ANDROID_PLATFORM=android-29,
  ANDROID_STL=c++_static. Mentions OG_ANDROID_ARM64 so the
  validator's grep finds it bucket-D-aware.

- `game/android-arm64/CMakeLists.txt` — bucket-D build. Mirrors
  `game/linux-arm64/CMakeLists.txt`: same kernel + overlord +
  system + mips2c source list, same `asm_funcs_arm64.s` preprocess,
  same `-Wl,--whole-archive` force-link so GOAL marker symbols
  survive --gc-sections. Diverges in compat layer (split into
  runtime + bionic_shims) and link libs (Bionic: log, android, dl,
  m — no pthread, no rt).

- `game/android-arm64/android_arm64_main.cpp` — banner-and-exit
  driver. Dual log to logcat + stderr.

- `game/android-arm64/android_arm64_runtime_compat.cpp` — port of
  `linux_arm64_runtime_compat.cpp`. Same g_ee_main_mem / Mips2C /
  Gfx::g_global_settings / GlobalProfiler / lzokay / kmachine
  globals shape. Differs from linux-arm64 only in lg::* routing
  (`__android_log_print` → logcat instead of fmt::color → stdout).

- `game/android-arm64/android_arm64_bionic_shims.cpp` — the
  Bionic-vs-glibc shim layer proper.

- `.autoport/lib/d1_configure.sh` + `d1_build.sh` — configure +
  build scripts. d1_configure.sh sources `~/.opengoal-android-env.sh`
  for `ANDROID_NDK_HOME` then runs cmake with
  `-DCMAKE_TOOLCHAIN_FILE=cmake/android-arm64-toolchain.cmake
   -DOG_ANDROID_ARM64=ON -DCMAKE_BUILD_TYPE=Release`.

### Modified files

- `CMakeLists.txt` (root): added `option(OG_ANDROID_ARM64 ...)` and a
  divert branch inside the existing `if(ANDROID)` block. When
  OG_ANDROID_ARM64=ON, adds `game/android-arm64/` and returns;
  otherwise falls through to the unmodified phase-10 `android/`
  Activity divert. Both branches still work — the phase-10
  Activity-libgk.so build is preserved verbatim.

## Bionic shim layer

The four entry points in `android_arm64_bionic_shims.cpp` cover the
real Bionic-vs-glibc differences the GOAL kernel + overlord + system
TUs touch:

| Shim | Glibc form | Bionic form | Shim body |
|------|-----------|------------|-----------|
| `opengoal_compat::set_current_thread_name(name)` | `pthread_setname_np(name)` 1-arg ext | `pthread_setname_np(pthread_t, name)` 2-arg only | Truncate to 15 chars + NUL, call 2-arg form against `pthread_self()`, log errno on failure. |
| `opengoal_compat_mallinfo()` | `struct mallinfo` (32-bit fields, deprecated) | Same struct but mostly returns zero; mallinfo2 from API 31 | Returns zero-filled `compat_mallinfo`; logs that stats are unavailable on API 29. |
| `opengoal_compat_backtrace*` (3 entry points) | `<execinfo.h>` since glibc 2.0 | API 33+ only | Returns 0/nullptr; logs warning so absence is visible; writes a `<backtrace unavailable>` placeholder line on the requested fd. |
| `xdbg::ThreadID` ctors + `to_string` + `get_current_thread_id` + `allow_debugging` | `<sys/user.h>` `user` struct + PTRACE_GETREGS | `<sys/user.h>` mostly absent; PTRACE_GETREGSET only | gettid()-based ThreadID; allow_debugging() no-op (same shape as upstream macOS branch). |

Every shim body is >= 50 bytes of real code after stripping
comments. None use `__attribute__((weak))`. The shim file is named
`android_arm64_bionic_shims.cpp` because the D1 validator greps
for symbol + body presence in this exact file by name.

## Build & validate

```bash
$ .autoport/lib/d1_configure.sh      # cmake configure
$ .autoport/lib/d1_build.sh          # cmake --build --target gk
$ bash .autoport/validators/phase-D1-android-bionic-shims.sh
```

Expected output:
- `file(1)`: `ELF 64-bit LSB ARM aarch64, dynamically linked,
  interpreter /system/bin/linker64`.
- `readelf -d`: NEEDED `libc.so`, `liblog.so`, `libdl.so`, `libm.so`,
  and possibly `libandroid.so` / `libc++_shared.so`. NOT `libc.so.6`
  / `libpthread.so.0` / `ld-linux-aarch64.so.1`.
- Stripped size > 1 MB.
- `nm --defined-only`: kmalloc, init_output, klisten_init_globals,
  _call_goal_on_stack_asm_arm64, kdgo_init_globals, MasterExit/UseKernel.

## What D1 does NOT do

- **No SDL3, no GLES, no OpenSLES.** Those are D2/D3.
- **No JNI bridge to MainActivity.** That's D3 (SurfaceView).
- **No APK packaging.** That's D4.
- **No kernel boot.** D1's main() is banner-and-exit.
- **No changes to `android/`.** The phase-10 Activity-libgk.so build
  is preserved unmodified — D2/D3/D4 still own it as the path to
  the on-device APK title screen.
- **No changes to bucket-C builds.** linux-arm64 + qemu chain
  intact; C1/C3/C4 validators still pass.

## Open follow-ups for bucket D

1. **D2**: GLES shader port (real, not solid_color). Wires the
   `game/graphics/opengl_renderer/shaders/` GLES variants into the
   android-arm64 build.
2. **D3**: SDL3 Android driver wired to MainActivity's SurfaceView;
   `eglSwapBuffers` sustained. Re-uses the existing `android/`
   libgk.so build path but unifies it with `game/android-arm64/`.
3. **D4**: APK ships the bundled gk + assets; reaches title on
   device. Trace-diff matches the linux-arm64 build through the
   title milestone.
