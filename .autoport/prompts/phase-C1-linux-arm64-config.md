# Phase C1 — Configure build-arm64-linux with cross-toolchain; gk builds

## What this phase delivers

A real **aarch64-linux-gnu** `gk` binary at
`build-arm64-linux/game/gk` (or under `build-arm64-linux/game/linux-arm64/`),
cross-built from the existing source tree with the host's clang/lld and
the Debian-mirrored aarch64 sysroot already installed for phase 26. The
binary must contain real GOAL kernel code (not the phase-09 syscall stub,
not a goal_stress_arm64 rename, not a single-printf cheat).

Buckets C2 and C3 follow C1: C2 makes the binary actually run far enough
under qemu-aarch64-static to load KERNEL.CGO; C3 drives it to the
`engine: state=title` milestone with a trace-diff against the oracle. C1
is narrowly about **the build itself**.

## Why this matters

Bucket C is "Linux-arm64 first" — the same source tree, cross-compiled
for aarch64-linux-gnu, runs under qemu-user without any of Android's
Bionic / W^X / GLES / SurfaceView headaches. If gk runs end-to-end
under qemu, the only remaining work for Android is the Bionic+GLES
diff, which is bucket D.

Without C1 we cannot even start C2 (no binary to inspect, no symbols
to fix). The cheap version of C1 is the phase-09 syscall stub (which
the supervisor already flagged as fraudulent). The honest version of
C1 produces a binary whose symbol table is dominated by **upstream
GOAL kernel code** — kscheme, kmalloc, klisten, kdgo, klink — so that
C2's symbol-resolution work has something real to chew on.

## Concrete deliverables

### 1. CMake configuration: `OG_LINUX_ARM64` build mode

Add a new top-level option, `OG_LINUX_ARM64`, that:

- Diverts the root `CMakeLists.txt` into a dedicated subdirectory
  (e.g., `game/linux-arm64/`) before pulling in any of the desktop
  build's SDL3 / OpenGL / discord-rpc / curl chain, mirroring how
  `OG_ANDROID_NDK_BUILD` already diverts into `android/`.
- Forces `GOALC_BACKEND=arm64` (the host-build goalc is x86, but the
  cross-built gk loads arm64 CGOs).
- Coexists with `OG_ARM64_STRESS` (the phase-26 stress harness path)
  so the existing `tools/arm64-stress/` build still works when that
  flag is passed instead.

The `cmake/aarch64-linux-toolchain.cmake` toolchain file must be
generalised so it no longer hard-codes `OG_ARM64_STRESS=ON`. Both
modes are now configure-time choices: either you pass
`-DOG_ARM64_STRESS=ON` (B2's stress harness) or
`-DOG_LINUX_ARM64=ON` (this phase's full gk).

### 2. `game/linux-arm64/` subdirectory

Add `game/linux-arm64/CMakeLists.txt` and a small handful of host
files (logging shim, runtime globals owner, sentinel main entry if
upstream `main.cpp` can't be compiled verbatim). The structure mirrors
`android/CMakeLists.txt`:

- Cross-compile `third-party/fmt` and `third-party/libco` via
  `add_subdirectory(... EXCLUDE_FROM_ALL)`.
- Compile a curated, **upstream-verbatim** subset of the GOAL kernel:
  - `game/kernel/common/*.cpp` (full set: fileio, kboot, kdgo,
    kdsnetm, klink, klisten, kmalloc, kmemcard, kprint, kscheme,
    ksocket, ksound, runtime_trace).
  - `game/kernel/jak1/{fileio,kdgo,klink,klisten,kprint,kscheme,
    ksound}.cpp` (the jak1 subset that doesn't pull discord/graphics).
  - `game/kernel/asm_funcs_arm64.s` (the trampoline), preprocessed to
    GNU as syntax the same way `tools/arm64-stress/CMakeLists.txt`
    already does.
- Compile the `game/system/*`, `game/overlord/{common,jak1}/*`,
  `game/sce/{stubs,iop,deci2,libcdvd_ee,libdma,libscf,sif_ee,
  sif_ee_memcard}.cpp`, `common/{audio,dma,cross_sockets,log,util,
  versions}/*.cpp`, and `game/mips2c/jak1_functions/*.cpp` subsets
  that the kernel transitively references (same shape the Android
  build already uses).
- Provide one small Linux-arm64 compat file (`linux_arm64_runtime_compat.cpp`)
  that owns the runtime globals upstream `game/runtime.cpp` would own
  (`g_ee_main_mem`, `g_game_version`, `g_main_thread_id`,
  `g_server_port`, `g_background_worker`) — same pattern as
  `android/android_runtime_compat.cpp`. Because we're targeting glibc,
  not Bionic, the *only* shims this file needs beyond globals are:
  honest abort/return-error stubs for the graphics + sound + discord
  + curl symbols the kernel/overlord touch. Each stub aborts with a
  named message ("C1: graphics not yet linked for linux-arm64"). This
  is **not** a cheat — it is an honest "not implemented yet" that will
  fail loudly the moment the kernel calls into graphics. C3 replaces
  these with real implementations.
- Provide a `gk` `add_executable` target whose entry is
  `game/main.cpp` if it cross-compiles cleanly, or otherwise a thin
  `linux_arm64_main.cpp` that calls into the same `goal_main()` /
  `exec_runtime()` plumbing. Either way the binary must contain real
  upstream entry-point code.

### 3. Reproducible configure script

Add `.autoport/lib/c1_configure.sh` that, given a clean working tree,
configures `build-arm64-linux/` with `OG_LINUX_ARM64=ON` and the
existing toolchain file. The validator re-runs this to assert the
configure is deterministic (same CMakeCache values modulo timestamps).

### 4. `build-arm64-linux/game/.../gk`

After `cmake --build build-arm64-linux --target gk`, an aarch64 ELF
called `gk` exists somewhere under `build-arm64-linux/game/`. The
exact path depends on whether the target lives in
`game/linux-arm64/CMakeLists.txt` (path:
`build-arm64-linux/game/linux-arm64/gk`) or directly under `game/`.
Either is acceptable; the validator searches `build-arm64-linux/` for
an `aarch64` ELF named `gk`.

### 5. Markdown report

`.autoport/reports/C1-config.md` — one screen of headline numbers:
binary size, symbol count, top 10 largest functions by size, the
toolchain command, and the `file(1)` output line. Useful for C2 to
read.

## Anti-cheat constraints

The supervisor's standard set, plus a few new ones tailored to this
phase:

1. **No syscall-only stub.** Phase 09's `arm64_boot_stub.S` is the
   cautionary tale. The gk binary's symbol table must contain at
   minimum the following upstream-defined symbols (any spelling: C,
   C++ mangled, or namespaced):
   - `kmalloc` (the bump allocator)
   - `kscheme_init` (or `init_output`)
   - `klisten_init_globals` (or `InitListenerConnect`)
   - `call_goal_on_stack` (or the assembly trampoline export
     `_call_goal_on_stack_asm_arm64` from `asm_funcs_arm64.s`)
   - `kdgo_init_globals`
   - `MasterUseKernel` / `MasterExit` (kernel master state globals)
   Each must appear in `nm --defined-only` on the binary (i.e., the
   symbol has a real body, not just a declaration).

2. **No goal_stress_arm64 rename.** The validator computes the SHA-256
   of `build-arm64-linux/tools/arm64-stress/goal_stress_arm64` (if it
   exists) and of `build-arm64-linux/.../gk`, and asserts they differ.
   They must be distinct binaries.

3. **Binary size floor.** The gk binary must be **at least 1 MB
   stripped** (`llvm-strip --strip-all`). The phase-26 stress harness
   is ~600 KB; gk includes the kernel + overlord + mips2c +
   system-threads layer plus per-jak duplicates and runs ~10-30× that
   size. A 1 MB floor catches single-file or trivial-deps stubs and is
   well below any honest assembly of the kernel + overlord + mips2c.

4. **Real cross-toolchain.** `file(1)` on the binary must report
   "ELF 64-bit LSB ... ARM aarch64". The dynamic linker
   (`readelf -l | grep interpreter`) must be
   `/lib/ld-linux-aarch64.so.1` (glibc), NOT
   `/system/bin/linker64` (Android), NOT statically linked (we want a
   real glibc cross-binary, not a static syscall blob).

5. **No "synthetic state" patterns introduced.** Grep the diff
   between A4 and the C1 commit for kStateSeq, kSyntheticBootSequence,
   `state=boot/load/title` log markers, gradient-shader-only files,
   `weak_jak1_*` declarations. None permitted.

6. **Codegen still frozen since A4.** Same lock as B1/B2:
   `goalc/compiler/IR.cpp`, `goalc/emitter/IGenARM64.{cpp,h}`,
   `goalc/emitter/ObjectGenerator.{cpp,h}` byte-identical to their A4
   commit.

7. **Desktop x86 build still passes its smoke test.** Same as B2: a
   60-second timeout `gk --game jak1 --portable -fakeiso --verbose
   --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem` must
   reach `link finish: logo` in the stdout.

8. **Linux-arm64 mode must be opt-in.** Default behavior of the
   desktop CMake configure must not change. Building without
   `-DOG_LINUX_ARM64=ON` produces the same desktop binary, with the
   same dependencies, on the same path.

## Files you will create / modify

| Path | Purpose |
|---|---|
| `CMakeLists.txt` (root) | add OG_LINUX_ARM64 option + divert subdir |
| `cmake/aarch64-linux-toolchain.cmake` | generalise — no longer force OG_ARM64_STRESS=ON |
| `game/linux-arm64/CMakeLists.txt` | new — full gk cross-build |
| `game/linux-arm64/linux_arm64_runtime_compat.cpp` | new — runtime globals + honest abort stubs for graphics/sound/curl |
| `game/linux-arm64/linux_arm64_main.cpp` (if needed) | new — slim main if upstream main.cpp doesn't cross-build |
| `.autoport/lib/c1_configure.sh` | new — reproducible configure invocation |
| `.autoport/reports/C1-config.md` | new — headline report |

Read-only (must not change): everything in `goalc/`, all existing
desktop CMake plumbing for the non-cross path, every file the B2 /
phase-26 stress harness depends on (the existing
`tools/arm64-stress/CMakeLists.txt` and `cmake/aarch64-linux-
toolchain.cmake`'s structural choices around `OG_ARM64_STRESS`).

## Pitfalls

- **SDL3 / curl / OpenGL cross-build.** The simplest path is to NOT
  cross-build them. The kernel + overlord don't actually require
  graphics/sound/network to *link*: their `extern` references can be
  satisfied by a single `linux_arm64_runtime_compat.cpp` of honest
  abort stubs (`abort()` or `throw std::runtime_error(...)`). This
  matches Android's pattern (`android_graphics_stubs.cpp`,
  `android_sound_stubs.cpp`).
- **`game/main.cpp` cross-compile.** Upstream main.cpp `#include`s
  `graphics/gfx_test.h` and calls `tests::run_gpu_test`. If
  cross-compiling main.cpp drags graphics in, write a thin
  `linux_arm64_main.cpp` that mirrors the upstream `goal_main` shape
  minus the gpu-test/dialogs branches. The validator does not require
  `main.cpp` itself to be the entry — only that the binary contains
  the real upstream `goal_main` + `exec_runtime` symbol bodies.
- **AVX check in main.cpp.** Upstream main.cpp early-exits with
  `dialogs::create_error_message_dialog` on non-AVX CPUs. aarch64
  hasn't got AVX. For C1 (just *builds*), that's fine — the binary
  links, the runtime path is dead-on-launch, C2/C3 handle it. Do not
  silently delete the AVX check; it should remain as the honest
  reason the binary exits early.
- **`asm_funcs_arm64.s` syntax.** The same `; → //` sed transform
  that `tools/arm64-stress/CMakeLists.txt` already does is required —
  the upstream file uses Apple-as `;` line comments.
- **mips2c_table.cpp.** Same caveat as Android — `mips2c_table.cpp`'s
  static init pulls every game's link callbacks. Either include all
  of them or omit `mips2c_table.cpp` and let `klink`'s lookup return
  empty (matches Android).
- **revision.h.** Same caveat as `tools/arm64-stress/CMakeLists.txt`
  — write a placeholder if missing.

## Reading list

- `android/CMakeLists.txt` — closest pattern to mirror; the kernel
  subset, fmt/libco/SDL3 add_subdirectory pattern, and `_runtime_compat`
  file are all directly applicable.
- `tools/arm64-stress/CMakeLists.txt` — for the asm trampoline syntax
  transform and the toolchain coexistence pattern.
- `cmake/aarch64-linux-toolchain.cmake` — the existing toolchain that
  needs to be generalised.
- `game/main.cpp` — to understand the entry-point shape if
  cross-compiling it works.
- `game/runtime.h` + `game/runtime.cpp` — for `exec_runtime` /
  `MasterExit` / `g_main_thread_id` etc. that the compat file owns.

## Done definition

`.autoport/validators/phase-C1-linux-arm64-config.sh` exits 0. Checks:

- Toolchain file no longer hard-forces `OG_ARM64_STRESS=ON`.
- `CMakeLists.txt` exposes `OG_LINUX_ARM64` option and gates a divert
  branch on it.
- `game/linux-arm64/CMakeLists.txt` exists with the documented
  add_subdirectory + add_library + add_executable structure.
- `.autoport/lib/c1_configure.sh` is executable and re-running it
  produces the same CMakeCache state (re-configure idempotent).
- After `cmake --build build-arm64-linux --target gk`, an aarch64 ELF
  named `gk` exists under `build-arm64-linux/`.
- `file gk` reports `ELF 64-bit LSB executable, ARM aarch64`.
- `readelf -l gk | grep interpreter` shows `/lib/ld-linux-aarch64.so.1`.
- Stripped binary size ≥ 1 MB.
- Stripped binary SHA-256 ≠ `goal_stress_arm64`'s SHA-256 (or the
  stress binary is absent, in which case this check is vacuous).
- All of `kmalloc`, `kscheme_init`/`init_output`, `klisten_init_globals`/
  `InitListenerConnect`, `call_goal_on_stack`/`_call_goal_on_stack_asm_arm64`,
  `kdgo_init_globals`, and the master-state globals are in
  `nm --defined-only`.
- Diff vs A4 contains no kStateSeq / weak_jak1_ / synthetic-renderer
  patterns.
- Codegen files byte-identical to A4.
- Desktop gk smoke test still reaches `link finish: logo`.
- `.autoport/reports/C1-config.md` has the headline section.
