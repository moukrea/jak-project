# Phase D1 — Android Bionic shims: gk links cleanly against Bionic libc

## What this phase delivers

A **buildable** android-arm64 `gk` executable, cross-compiled with the
Android NDK r27c clang toolchain, that:

1. Links cleanly against **Bionic** (`libc.so` / `libm.so` /
   `libdl.so` / `liblog.so`) — NOT glibc, NOT `libpthread.so.0`, NOT
   `/lib/ld-linux-aarch64.so.1`.
2. Contains the same set of GOAL kernel marker symbols
   (`kmalloc`, `init_output`, `klisten_init_globals`,
   `call_goal_on_stack`, `_call_goal_on_stack_asm_arm64`,
   `kdgo_init_globals`, `MasterExit`, plus the jak1::-namespaced
   bridge entry points) as the linux-arm64 `gk` from C1/C2/C3/C4.
3. Provides **real** Bionic-vs-glibc shims for every glibc-only entry
   point the GOAL kernel + overlord + system layer touches —
   `pthread_setname_np` arity mismatch, `mallinfo` shape difference,
   `<execinfo.h>` absence on API < 33, and the `xdbg::` thread-id
   helpers that the desktop `xdbg.cpp` ties to `<sys/user.h>` (which
   Bionic doesn't expose).

D1 is purely the libc shim layer. It does **not** wire SDL3, GLES,
the Activity, audio output, or input handling. Those land in D2/D3
under the existing `android/` libgk.so build. D1 stands the
android-arm64 `gk` next to the linux-arm64 `gk` so that anything
that builds for one and not the other is a Bionic-vs-glibc gap with
a clearly attributable shim.

After D1: the android-arm64 gk **builds and links**. It exits 2 with
a "D1 only links; D2 wires graphics" banner if you try to run it.
No SIGILL / no SIGSEGV — the executable is well-formed, just not
hooked up to a surface yet.

## Why this matters

The existing `android/CMakeLists.txt` (libgk.so for the Activity)
mixes Bionic shims with SDL3 + GLES + Activity-bridge work. The
phase 12/22 validators only checked that libgk.so exists and has
some DT_NEEDED entries — they did not enforce "every glibc entry
point is either present in Bionic or shimmed by a real
implementation." Phase 28's `__attribute__((weak))` cheat
(declaring `weak_jak1_*` without defining them, then branching on
the always-null pointer) slipped past every previous check.

D1 isolates the Bionic shim layer in `game/android-arm64/` —
parallel to `game/linux-arm64/` — so the validator can demand that
the android-arm64 `gk` executable's symbol table, dynamic
dependencies, and shim file contents *match the linux-arm64
baseline*. A stub can't fake parity against a real kernel built
from the same sources.

## Engineering background (from C4's tail state)

C4 closed the bucket-C work: aarch64-linux gk runs under
qemu-aarch64-static, links and executes gcommon's top-level GOAL
function with `LINK_FLAG_EXECUTE` enabled. The runtime linker
(`klink.cpp`) now patches ADRP+ADD/LDR-imm12 fields bit-correctly.
NumSymbols climbs from 317 (post-link) to ≥ 517 (post-execute).

The relocators, the asm trampoline (`asm_funcs_arm64.s`), the
`ObjectGenerator` linker fixups (A4), the IR classifier
(`classify_ir_arm64.py`), and the codegen baseline are all locked
since A4. **D1 must not touch any of them.**

What D1 *does* touch:

- A new `cmake/android-arm64-toolchain.cmake` (thin — it just
  forwards into the NDK's `android.toolchain.cmake` and pins
  ANDROID_ABI=arm64-v8a + ANDROID_PLATFORM=android-29).
- A new `game/android-arm64/` subdirectory mirroring
  `game/linux-arm64/` (CMakeLists, main, runtime_compat, plus a
  dedicated `android_arm64_bionic_shims.cpp` for the Bionic-only
  shims).
- The root `CMakeLists.txt` gains an `option(OG_ANDROID_ARM64 ...)`
  + a divert branch that fires when both `ANDROID=1` (set by the
  NDK toolchain) and `OG_ANDROID_ARM64=ON`. The existing `android/`
  subdir divert (no OG_ANDROID_ARM64) is preserved verbatim for the
  libgk.so Activity build.
- `.autoport/lib/d1_configure.sh` + `d1_build.sh` — analogous to
  `c1_configure.sh`.

## Concrete deliverables

### 1. NDK toolchain forwarder

`cmake/android-arm64-toolchain.cmake` — minimal wrapper that
`include()`s `$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake`
and pins ABI / platform / STL. The wrapper exists so the configure
script can pass a single `-DCMAKE_TOOLCHAIN_FILE=` argument without
the caller needing to know the NDK path, matching how
`cmake/aarch64-linux-toolchain.cmake` works.

ANDROID_PLATFORM=android-29 matches the existing
android/build.gradle.kts minSdk + Redmi Note 9 Pro target (MIUI 12
on Android 10 = API 29). ANDROID_STL=c++_static is required for the
GOAL kernel's `std::unordered_map<>` + `std::filesystem` paths.

### 2. game/android-arm64/CMakeLists.txt

Mirror of `game/linux-arm64/CMakeLists.txt`, modulo:

- Source list **identical** for the kernel / overlord / system /
  mips2c TUs (one source of truth: the same upstream files under
  `game/kernel/common`, `game/kernel/jak1`, `game/system`,
  `game/overlord`, `game/mips2c/jak1_functions`, plus the
  pre-processed `asm_funcs_arm64_gnu.s`). Any TU that's good enough
  for linux-arm64 is good enough for android-arm64 — Bionic differs
  in libc surface, not in C++.
- Compat layer split into TWO files:
  * `android_arm64_runtime_compat.cpp` — the same abort/no-op
    stubs the linux-arm64 build uses (graphics / sound / sce /
    GlobalProfiler / Gfx::g_global_settings / lzokay / etc).
  * `android_arm64_bionic_shims.cpp` — the Bionic-specific shim
    layer. SEPARATE FILE because the validator's "shim must be
    real" checks grep for symbol presence + body size in this file
    by name.
- Link command targets Bionic libs: `log android dl m c`. NO
  `pthread` (it's part of Bionic libc on Android), NO `rt` (Bionic
  folds rt into libc).
- The `gk` executable lands at
  `build-arm64-android/game/android-arm64/gk`.

### 3. game/android-arm64/android_arm64_main.cpp

Banner-and-exit at the C1 level — exit code 2 with a one-line
banner identifying the build. No kernel boot yet. C2/C3/C4
equivalents in bucket D would extend this; D1 is the configure +
link gate.

```c++
int main(int /*argc*/, char** /*argv*/) {
    __android_log_print(ANDROID_LOG_INFO, "opengoal-gk",
        "D1: android-arm64 gk built; D2 will wire graphics/runtime");
    std::fprintf(stderr,
        "D1: android-arm64 gk built; D2 will wire graphics/runtime\n");
    return 2;
}
```

The dual log (logcat + stderr) is so this works either way — pushed
to a device and run via `adb shell /data/local/tmp/gk`, or run
under any future Bionic-capable qemu-android setup.

### 4. game/android-arm64/android_arm64_runtime_compat.cpp

Port of `game/linux-arm64/linux_arm64_runtime_compat.cpp`. The
upstream code being shimmed is identical; only the logging route
changes — desktop `fmt::color` → stdout becomes
`__android_log_print` via the `lg::internal::log_message` /
`log_print` / `log_vprintf` overrides (same shape as
`android/android_runtime_compat.cpp` uses).

Everything else (g_ee_main_mem, Gfx::g_global_settings,
Mips2C globals, snd_* no-ops, jak{N}::InitMachineScheme stubs,
xdbg::allow_debugging, lzokay::decompress) stays the same and
behaves the same. lzokay's Success-with-out_size=0 stub is
documented in the linux-arm64 compat layer and is honest for
extracted (uncompressed) DGOs — same applies on Android.

### 5. game/android-arm64/android_arm64_bionic_shims.cpp

REAL Bionic-vs-glibc shims. Each one is a strong symbol with a
non-trivial body. No `__attribute__((weak))`. The set:

- **`opengoal_compat::set_current_thread_name(const char* name)`** —
  truncates to 15 chars and calls
  `pthread_setname_np(pthread_self(), trimmed)`. The 1-arg glibc form
  `pthread_setname_np(name)` doesn't exist on Bionic; this is the
  portable helper upstream code uses on Android.
- **`compat_mallinfo opengoal_compat_mallinfo()`** — returns a
  zero-filled `compat_mallinfo` (same struct shape Bionic exposes
  via `<malloc.h>`'s `mallinfo` deprecated wrapper). Diagnostic-only
  on the desktop runtime; zero values are safe.
- **`int opengoal_compat_backtrace(void** buf, int size)`**,
  **`char** opengoal_compat_backtrace_symbols(void* const* buf,
  int size)`**, **`void opengoal_compat_backtrace_symbols_fd(...)`**
  — Bionic ships `<execinfo.h>` only on API 33+; our minSdk=29
  target can't rely on it. The shims return 0 / nullptr / void and
  emit a `__android_log_print(ANDROID_LOG_WARN, ...)` warning so
  the operator sees the diagnostic gap honestly rather than silent
  loss.
- **`xdbg::ThreadID xdbg::get_current_thread_id()`** +
  **`xdbg::ThreadID::ThreadID(pid_t)`** + **`ThreadID::to_string()`**
  +**`xdbg::allow_debugging()`** — the linux-arm64 build owns these
  in its compat layer because `<sys/user.h>` and PTRACE_GETREGS are
  x86-only; Bionic's `<sys/user.h>` is even more restricted. Same
  shim shape, gettid()-based body.

The file must be **named** `android_arm64_bionic_shims.cpp` so the
validator can grep it by name. Body sizes are validated against a
minimum byte threshold to catch "shim is just `return 0;`" cheats.

### 6. game/android-arm64/android_arm64_main.cpp force-link

The `gk` target uses `-Wl,--whole-archive android_arm64_kernel
-Wl,--no-whole-archive -Wl,--no-gc-sections` so the kernel marker
symbols stay in the dynsym even though `main()` doesn't reach
them. Same trick C1 uses for linux-arm64.

### 7. Root CMakeLists.txt: OG_ANDROID_ARM64 option + divert

```cmake
option(OG_ANDROID_ARM64 "Build the bucket-D android-arm64 gk (D1+)" OFF)

if(ANDROID)
    if(OG_ANDROID_ARM64)
        message(STATUS "Bucket D: android-arm64 NDK gk")
        if(NOT GOALC_BACKEND)
            set(GOALC_BACKEND "arm64" CACHE STRING "" FORCE)
        endif()
        add_compile_definitions(OG_ANDROID_ARM64=1)
        add_subdirectory(game/android-arm64)
        return()
    endif()
    # else: existing android/ Activity-libgk.so divert preserved
    ...
endif()
```

This puts the new branch INSIDE the existing `if(ANDROID)` so the
android/ branch keeps working for `gradle assembleRelease` (which
configures with the NDK toolchain but without OG_ANDROID_ARM64).

### 8. .autoport/lib/d1_configure.sh + d1_build.sh

`d1_configure.sh` runs:

```bash
cmake -S . -B build-arm64-android \
    -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$PWD/cmake/android-arm64-toolchain.cmake" \
    -DOG_ANDROID_ARM64=ON \
    -DCMAKE_BUILD_TYPE=Release
```

`d1_build.sh` runs `cmake --build build-arm64-android --target gk -j`.

### 9. .autoport/reports/D1-shims.md

A short headline file describing what was wired, what shim layer
covers what symbol, and the build-arm64-android artifact path.
Validator greps for the headline string.

## Anti-cheats (validator enforces these)

The D1 validator is strict by design. It enforces:

1. **Required files** — toolchain forwarder, both compat sources,
   bionic_shims source, CMakeLists, configure+build scripts,
   D1-shims.md report.
2. **NDK toolchain forwarder is correct** — includes
   `android.toolchain.cmake`, pins ANDROID_ABI=arm64-v8a, mentions
   OG_ANDROID_ARM64.
3. **Root CMakeLists.txt divert** — `option(OG_ANDROID_ARM64 ...)`
   exists; an `if(OG_ANDROID_ARM64) add_subdirectory(game/android-arm64)`
   path exists inside the `if(ANDROID)` block; the existing
   android/ Activity divert is preserved unmodified.
4. **game/android-arm64/CMakeLists.txt structure** —
   `add_executable(gk ...)`; references real upstream kernel
   sources (kmalloc.cpp, kscheme.cpp, klisten.cpp, kdgo.cpp, the
   asm trampoline); links against Bionic libs `log android dl m`
   (NOT pthread, NOT rt).
5. **d1_configure.sh produces the expected CMakeCache** with
   OG_ANDROID_ARM64=ON, ANDROID=1, ANDROID_ABI=arm64-v8a.
6. **cmake --build --target gk produces an aarch64 ELF** at
   `build-arm64-android/game/android-arm64/gk`.
7. **file(1) reports aarch64 ELF**.
8. **Dynamic interpreter is `/system/bin/linker64`** (Bionic), NOT
   `/lib/ld-linux-aarch64.so.1` (glibc). The single strictest
   check — distinguishes a Bionic-link from a glibc-link
   conclusively.
9. **DT_NEEDED contains only Bionic-class libs** — libc.so,
   libdl.so, liblog.so, libm.so. NOT libc.so.6, NOT libpthread.so.0,
   NOT libdl.so.2.
10. **Stripped size ≥ 1 MB** (anti-stub floor — same as C1).
11. **SHA-256 differs from linux-arm64 gk** (anti-rename cheat).
12. **All required GOAL kernel symbols present in nm output** —
    same set C1 requires (kmalloc, init_output, klisten_init_globals
    or InitListenerConnect, call_goal_on_stack OR
    _call_goal_on_stack_asm_arm64, kdgo_init_globals,
    MasterExit/MasterUseKernel).
13. **The Bionic shim file contains real implementations** —
    grep for the four required free-function names in
    `android_arm64_bionic_shims.cpp`. Each function definition
    region (start brace to matching brace) must be ≥ 50 bytes.
14. **No `__attribute__((weak))` in bionic_shims** — the phase-28
    cheat pattern is forbidden by grep.
15. **No synthetic-state patterns introduced since A4** —
    `kStateSeq`, `kSyntheticBootSequence`, `weak_jak1_`,
    `synthetic.*gradient`, `kSolidColorOnly`, etc. (Same forbidden
    list C1/C3/C4 enforce.)
16. **Codegen + classifier files byte-identical to A4** —
    `goalc/compiler/IR.cpp`, `goalc/emitter/IGenARM64.{cpp,h}`,
    `goalc/emitter/ObjectGenerator.{cpp,h}`,
    `goalc/emitter/CodeGenerator.{cpp,h}`,
    `.autoport/lib/classify_ir_arm64.py`.
17. **Bucket-C invariants still hold** — C1 / C3 / C4 validators
    all still exit 0. (D1 must not regress the linux-arm64 chain.)
18. **Desktop gk smoke test still passes** — same
    `--portable -fakeiso -boot -debug-mem` smoke that C1 + later
    phases use; "link finish: logo" reachable in 60s.
19. **D1-shims.md headline present** — the report exists and
    mentions "android-arm64" + "Bionic" in the first non-blank
    lines.

## Don't

- **Do NOT touch the existing `android/` directory.** That's the
  libgk.so Activity build, owned by D2/D3/D4. D1 only adds
  parallel infrastructure under `game/android-arm64/`.
- **Do NOT use `__attribute__((weak))` anywhere.** Strong symbols
  only. If a shim can't be implemented honestly, it abort()s
  loudly — but D1's shims are all honest implementations.
- **Do NOT modify the codegen or classifier files.** They're
  locked since A4.
- **Do NOT introduce kStateSeq, weak_jak1_, or any synthetic-state
  pattern.** The C1/C3/C4 forbidden-pattern grep is inherited
  verbatim.
- **Do NOT change the linux-arm64 build.** D1 must build android
  from the same source files; if a source file needs an Android
  guard, add it as `#ifdef OG_ANDROID_ARM64` (or `#ifdef
  __ANDROID__`), never as a destructive edit of the linux-arm64
  path.
- **Do NOT call into SDL3 / GLES / OpenSLES.** Those are D2/D3.
  D1's gk is a banner-and-exit; the link surface is libc only.

## Success

`bash .autoport/validators/phase-D1-android-bionic-shims.sh` exits
0. The build-arm64-android tree contains a real Bionic-linked
aarch64 gk executable with the kernel marker symbols, every glibc
gap is shimmed with strong real symbols, and the bucket-C chain
is still green.
