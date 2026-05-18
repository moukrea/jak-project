# Phase 10 — Android NDK cross-build

## Goal

Cross-compile the whole project with the Android NDK for `arm64-v8a`. Validator: the resulting binary loads on an Android emulator and runs `gk --version` successfully.

## Scope

1. Add an `android/` directory at the repo root with:
   - A CMake toolchain wrapper or instructions to use NDK's `android.toolchain.cmake`
   - A small Android-specific main shim (since Android apps don't have a traditional `main`)
2. Update all third-party dependency build scripts to support the NDK target. Critical ones:
   - SDL2 — has Android backend, well-supported
   - OpenGL → use GLES 3.2 (or GLES 3.1 + extensions if 3.2 unavailable on target devices)
   - OpenAL Soft — Android port exists
   - zlib, libzstd — straightforward
3. Replace any uses of glibc-specific extensions with bionic-compatible alternatives. Common culprits:
   - `pthread_setname_np` signature differences
   - `getauxval` availability
   - `mallinfo` / `malloc_usable_size` differences

## Don't yet

- Don't build an APK (that's phase 11).
- Don't tackle controller/touch input (phase 11 too).
- Don't worry about user-data paths and scoped storage (phase 11).

## Pitfalls

- The NDK uses Clang. Some warnings-as-errors that pass on GCC may fail. Either fix or relax `-Werror`.
- `<filesystem>` and other C++17/20 features: NDK r27 supports them but some need explicit `-lc++_static` linkage.
- Inline assembly: any remaining `asm` blocks must be aarch64-compatible already after phase 05/08.

## Success

```bash
# Build for android-arm64
cmake -B build-android -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-29 \
  -DGOALC_BACKEND=arm64
cmake --build build-android --target gk

file build-android/game/gk  # must say "ELF 64-bit LSB shared object, ARM aarch64"
```

The validator additionally adb-installs to an emulator if `adb` is available, but defaults to file-format check if not.
