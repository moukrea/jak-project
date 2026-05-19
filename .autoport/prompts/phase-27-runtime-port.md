# Phase 27 — Cross-build the full game/ runtime tree into libgk.so

## Goal

`libgk.so` today is ~2.4 MB. The desktop `gk` binary is roughly 30-60 MB.
The difference is the entire OpenGOAL runtime that phase 12-13 promised
but didn't actually link: `game/system/`, `game/overlord/`,
`game/sound/`, `game/graphics/opengl_renderer/` (real renderer chain),
`game/kernel/jak1/` (the jak1 dispatcher + InitMachine prerequisites),
the listener stubs, etc.

This phase compiles every file under `game/` for arm64-Android (Bionic,
NDK r27) and links them into libgk.so. Bionic-vs-glibc gaps that
phase 22 stubbed are now fixed for real because the validator measures
**libgk.so size and symbol count**, not log strings.

## Anti-stub rules

- The validator checks `nm -D --defined-only libgk.so` for a list of
  named runtime symbols (InitMachine, KernelCheckAndDispatch,
  goal_dispatcher, Overlord, etc.). Each symbol must (a) exist and (b)
  have a body of ≥200 bytes (via `anti_stub_check_symbol_body_size`).
- libgk.so must be ≥ 20 MB after the build. A stub couldn't fake that
  size without padding the binary with junk, which is detectable as a
  block of zero bytes.
- Compile errors are fixed at the source level, not silenced. Don't
  add `-Wno-` flags; don't `#ifdef __ANDROID__` around the bug to skip
  the code.
- Don't disable LTO or `-Werror` to "make it build". Fix the actual
  Bionic incompatibility.

## Concrete deliverables

1. **CMakeLists.txt updates** in `android/CMakeLists.txt`:
   - Add the full `game/runtime.cpp`, `game/main.cpp` (now gated for
     Android: `goal_main` is the entry point, `main` only on non-Android)
     to libgk.so.
   - Add ALL `game/kernel/common/*.cpp` and `game/kernel/jak1/*.cpp`
     (today it's a curated subset).
   - Add `game/system/*.cpp`, `game/overlord/*.cpp`,
     `game/sound/*.cpp` modulo files that genuinely require a desktop
     SDL window manager.
   - Keep `--whole-archive` so symbol table stays populated.

2. **Bionic shims** in `android/android_runtime_compat.cpp` (extend the
   existing file, don't rewrite). Documented in
   [[feedback-bionic-shims]] memory but at minimum:
   - `pthread_setname_np(name)` → `pthread_setname_np(pthread_self(),
     name_truncated_to_15_chars)`.
   - `mallinfo` → `mallinfo2` (Bionic API 31+) or null stub returning
     zeros.
   - `<execinfo.h>` (`backtrace`, `backtrace_symbols`) gated behind
     `#ifdef __GLIBC__`, replaced with logcat-based stubs.
   - `_Exit` / `quick_exit` differences.
   - Audit `<filesystem>` use; Bionic + libc++ static handles it.

3. **No removal of any code that compiles**. If `game/system/Listener.cpp`
   compiles under NDK r27 with minor tweaks, link it. Don't `#ifndef
   __ANDROID__` around the whole file.

4. **Validator-checked symbols** (must exist in `nm libgk.so`, with
   bodies ≥200 bytes):
   - `InitMachine` (or `jak1::InitMachine`, whichever the source uses)
   - `KernelCheckAndDispatch` (jak1 variant)
   - `call_goal_on_stack` (or `_Z19call_goal_on_stack…` mangled — match
     by demangled name)
   - `Listener::Listener` (constructor; proves listener class is linked)
   - `kdgo_init` or similar overlord-side init
   - `make_iop_thread` or equivalent IOP init

   The validator's exact list is in
   `.autoport/validators/phase-27-runtime-port.sh`.

5. **libgk.so size:**
   - Stripped: ≥ 15 MB
   - Unstripped (debug build): ≥ 30 MB

6. **APK rebuild** so libgk.so in the APK matches the on-disk one.

## Don't

- Don't comment out the `set!`-state hooks in `game/kernel/jak1/gstate.gc`
  generated code. Phase 28 needs those alive to validate real
  `engine: state=` logs.
- Don't add a custom Activity launcher class to bypass SDLActivity.
  Keep the existing wiring from phase 18.
- Don't stub `Listener::receive()` with `return false`. If the listener
  is genuinely impossible on Android without network plumbing, comment
  the **WHY** in code; the validator doesn't require Listener to
  function, only to compile + link.

## Pitfalls

- The desktop renderer compiles dozens of OpenGL extension wranglers.
  GLES 3.2 may not have all of them. Use `glad` configured for GLES
  (already present at `third-party/glad/`) and ifdef the GL-only paths.
- NDK r27 changed how `<stdfilesystem>` is linked. Use the libc++
  static config the existing build already chose.
- `--whole-archive` of the full game/ tree may push libgk.so past
  AGP's 100 MB cap. Phase 13's prompt mentioned the AAB pivot; use it
  if needed (gradle `bundleJak1Debug`).
- `-flto` is fragile across the whole game/ tree at first. Get
  `-O2` -fno-lto working first, then re-enable LTO once symbols verify.

## Validator

```
.autoport/validators/phase-27-runtime-port.sh
```

## Success

`libgk.so` weighs ≥15 MB stripped, exposes all the runtime entry
symbols (each with a real body), and the APK ships byte-identical
content. Logcat after launch shows the same `goal_main → kheap_alloc
→ KERNEL.CGO loaded` sequence as before — but now coming from the
real linked-in code, not the shim.
