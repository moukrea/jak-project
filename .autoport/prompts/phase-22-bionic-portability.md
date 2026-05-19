# Phase 22 — Bionic / NDK portability + W^X code mapping + longevity

## Goal

By phase 21 we have a rendered frame, but the runtime may still hit
intermittent crashes from Bionic-vs-glibc API mismatches (these don't
necessarily fire on the boot path; they fire mid-game when something
calls e.g. `mallinfo()` or `pthread_setname_np(name)`). Also: code pages
loaded from CGOs must be mapped read+execute, NEVER write+execute
simultaneously — Android API 29+ enforces this and the SELinux policy
on most retail devices will kill the process if W^X is violated.

This phase produces a **5-minute-stable** runtime: app stays alive,
keeps drawing frames, no `Fatal signal`, no SELinux policy denials,
and the engine reaches `state=title` (the title screen state in
`gstate.gc`).

## Concrete deliverables

1. **Bionic API shims** — go through the runtime and fix portability
   issues. Required pattern: where Bionic supports a slightly-different
   form, use it directly behind `#ifdef __ANDROID__` (or `#ifndef __GLIBC__`);
   do NOT vendor a wholesale glibc compat layer.

   Known specifics:
   - `pthread_setname_np(name)` (single-arg glibc form) →
     `pthread_setname_np(pthread_self(), name)`.
   - `mallinfo()` not available → `mallinfo2()` (Bionic API 31+) OR
     stub the stats path with zeros under `__ANDROID__`. Grep for
     `mallinfo(` to find call sites.
   - `<execinfo.h>` (`backtrace`, `backtrace_symbols`) → gate behind
     `#ifndef __ANDROID__`; on Android the existing
     `common/log/log.cpp` panic path should emit a logcat line rather
     than a backtrace.
   - `getauxval(AT_HWCAP2)` → fine on Bionic API 18+, but verify
     `<sys/auxv.h>` is included on Android.
   - `getpwuid`/`getlogin` (if used) — Bionic has them but they return
     `nullptr` for non-app uids. The few callers should handle null.

2. **W^X code mapping for CGO-loaded native code.**
   - Find the CGO code-page mapper (likely in
     `game/kernel/common/kmalloc.cpp` or `kdgo.cpp` — wherever a `.text`
     section from a loaded CGO is made executable).
   - On Android, the sequence must be: `mmap(PROT_READ|PROT_WRITE)` →
     copy bytes in → `mprotect(PROT_READ|PROT_EXEC)` →
     `__builtin___clear_cache(start, end)`.
   - NEVER `PROT_WRITE | PROT_EXEC` simultaneously. SELinux on retail
     devices kills the process for this.
   - If the code currently uses `mmap(PROT_READ|PROT_WRITE|PROT_EXEC)`,
     split into the two-step pattern under `#ifdef __ANDROID__`.
   - Log a marker `code-map: <N> pages RX, 0 RWX` once per process
     after the kernel finishes loading CGOs.

3. **Filesystem & path handling**:
   - `<filesystem>` works under NDK r27 with libc++ static. Verify that
     `std::filesystem::canonical(p)` doesn't fail on paths in
     `/data/user/0/.../files/` (it shouldn't, but the symlinkiness can
     trip it).
   - Any code that hard-codes `"/tmp"` or `"/var/log"` must use
     `getCacheDir()` / `getFilesDir()` (passed in via the existing
     `data_root` plumbing or a new JNI getter).

4. **State-marker logging** for the validator:
   - When `gstate` transitions to a state, log:
     `engine: state=<name>` (use the existing state-machine code,
     add the log only where state changes).
   - The "title" state is the goal — typical sequence:
     `state=boot → state=load → state=title`.

## Don't

- Do **not** weaken security by allowing W^X. The mprotect dance is
  required.
- Do **not** stat-sample `mallinfo` outside the stats panel. If it's
  only used by debug HUD, just gate the call.
- Do **not** add bionic-isms to the desktop code paths. Every change
  must be `#ifdef __ANDROID__`-conditional or genuinely portable.

## Pitfalls

- **`pthread_setname_np` length limit**: Bionic caps thread names at
  15 chars (16 incl. NUL). Truncate `"opengoal-runtime"` (16 chars
  + NUL = 17, fails) to `"opengoal-rt"`.
- **`__builtin___clear_cache` is required after writing code, before
  executing it.** On AArch64 without it, the I-cache may serve stale
  bytes and the process SIGILLs.
- **SELinux denials don't always log** at the app's log tag. Search
  `adb logcat -d -s SELinux` separately if you see unexplained kills.
- **API level**: `compileSdkVersion` and `targetSdkVersion` should be
  `34` (Android 14) — let AGP enforce W^X for us. Don't lower it.

## Validator

```
.autoport/validators/phase-22-bionic-portability.sh
```

- Builds, installs, launches.
- Confirms boot through phase 20+21 markers.
- Confirms `engine: state=title` within 180s.
- Confirms `code-map: <N> pages RX, 0 RWX` was logged (W^X discipline).
- Tails logcat for an additional **5 minutes** asserting:
  - No `Fatal signal`, `SIGSEGV`, `SIGABRT`, `SIGILL`.
  - No `avc: denied` (SELinux denial against our package).
  - At least 50 `eglSwapBuffers: ok` events in the window.
- Desktop x86 build still passes.

## Success

App launches, reaches the title state, stays alive without crashes
for 5 minutes, ≥50 frames swapped. No SELinux denials. No
`PROT_WRITE | PROT_EXEC` mappings visible in
`adb shell run-as <pkg> cat /proc/self/maps`.
