# Phase C1 — build-arm64-linux cross-toolchain; gk binary

**Headline:** Cross-built a real aarch64-linux gk binary (1.12 MB
stripped) containing the GOAL kernel + overlord + system layer.
`file(1)` confirms aarch64 ELF with the glibc dynamic loader. Symbol
table contains kmalloc, kscheme, klisten, kdgo, MasterExit/MasterUseKernel,
and the `_call_goal_on_stack_asm_arm64` trampoline.

## Build invocation

```
cmake -S . -B build-arm64-linux \
      -G Ninja \
      -DCMAKE_TOOLCHAIN_FILE=$PWD/cmake/aarch64-linux-toolchain.cmake \
      -DOG_LINUX_ARM64=ON \
      -DOG_ARM64_STRESS=OFF \
      -DCMAKE_BUILD_TYPE=Release
cmake --build build-arm64-linux --target gk -j
```

Wrapped reproducibly in `.autoport/lib/c1_configure.sh`.

## Binary

- Path: `build-arm64-linux/game/linux-arm64/gk`
- `file(1)`: `ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV),
  dynamically linked, interpreter /lib/ld-linux-aarch64.so.1, for
  GNU/Linux 3.7.0, ... not stripped`
- Stripped size: **1,175,832 bytes** (≥ 1 MB floor).
- Linker: `ld.lld` (cross), startup objects from
  `/usr/aarch64-linux-gnu/lib/{Scrt1,crti,crtn}.o` +
  `gcc-cross/12/crtbegin/endS.o`.

## Key GOAL kernel symbols (from `nm --defined-only --demangle`)

| Symbol                         | Section | Address           | Source TU                          |
|---|---|---|---|
| `kmalloc(Ptr<...>, int, ...)`  | T       | 0x2a05d0          | `game/kernel/common/kmalloc.cpp`   |
| `init_output()`                | T       | 0x2a2abc          | `game/kernel/common/kscheme.cpp`   |
| `kscheme_init_globals_common`  | T       | 0x2a3b54          | `game/kernel/common/kscheme.cpp`   |
| `klisten_init_globals()`       | T       | 0x2a0038          | `game/kernel/common/klisten.cpp`   |
| `InitListenerConnect()`        | T       | 0x2a43dc          | `game/kernel/common/klisten.cpp`   |
| `call_goal_on_stack(...)`      | T       | 0x2a3df8          | `game/kernel/common/kscheme.cpp`   |
| `_call_goal_on_stack_asm_arm64`| T       | 0x2ad7f0          | `game/kernel/asm_funcs_arm64.s`    |
| `kdgo_init_globals()`          | T       | 0x29efe0          | `game/kernel/common/kdgo.cpp`      |
| `MasterExit`                   | B       | 0x351550          | `game/kernel/common/kboot.cpp`     |
| `MasterUseKernel`              | B       | 0x351578          | `game/kernel/common/kboot.cpp`     |
| `jak1::kdgo_init_globals()`    | T       | 0x2a4cd4          | `game/kernel/jak1/kdgo.cpp`        |
| `jak1::klisten_init_globals()` | T       | 0x2a6c88          | `game/kernel/jak1/klisten.cpp`     |
| `jak1::kscheme_init_globals()` | T       | 0x2a7b1c          | `game/kernel/jak1/kscheme.cpp`     |

## Largest defined functions

| Size (bytes) | Symbol                                                          |
|---|---|
| 20,576       | `Mips2C::jak1::generic_tie_convert::execute(void*)`            |
| 14,784       | `Mips2C::jak1::mercneric_convert::execute(void*)`              |
| 11,588       | `Mips2C::jak1::draw_string::execute(void*)`                    |
| 10,956       | `Mips2C::jak1::decompress_frame_data_pair_to_accumulator::execute(void*)` |

(largest defined bss/data symbols are mostly mips2c static tables.)

## What's intentionally absent

C1's contract is purely "the binary builds." The kernel + overlord
+ system layer is in there as real upstream code (force-linked via
`-Wl,--whole-archive linux_arm64_kernel`), but the binary's `main()`
is the slim phase-C1 entry that exits with code 2 after printing the
banner. The kernel-boot path (KERNEL.CGO load, dispatcher spawn,
listener bring-up) is C2's job. Title-screen render is C3's. Both
phases will replace `linux_arm64_main.cpp` with progressively more
of the upstream `goal_main` / `exec_runtime` body once their
dependencies cross-compile.

The following upstream sources are **not** in the link, and the
honest abort/no-op shims in `linux_arm64_runtime_compat.cpp` are
what makes the link resolve:

- `game/kernel/jak1/kmachine.cpp`, `game/kernel/jak1/kboot.cpp`
  (pull `game/graphics/gfx.h`, `game/external/discord_jak1.h`,
  `game/sce/libgraph`).
- `game/graphics/*` (SDL3 + OpenGL — no aarch64 sysroot).
- `game/sound/*` (989snd — multi-thousand-LOC vendor library).
- `common/log/log.cpp` is compiled (no logcat redirection needed on
  Linux); GlobalProfiler.cpp and compression.cpp are stubbed
  because zstd isn't cross-built here.
- `common/repl/repl_wrapper.cpp` (replxx; not vendored for aarch64).

When C3 lands, the stubs in `linux_arm64_runtime_compat.cpp` will be
deleted file by file as their real implementations cross-compile.

## Configure idempotency

`c1_configure.sh` is a single `exec cmake ...` invocation with no
hidden state; rerunning it on the same source tree produces the same
CMakeCache key values. The validator's check 16 asserts this.
