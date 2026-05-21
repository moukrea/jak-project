# Phase C2 — gk runs under qemu, GOAL heap initialised

**Headline:** The C1 aarch64-linux gk binary now runs under
`qemu-aarch64-static` end-to-end through the upstream OpenGOAL
kernel-init chain. The driver hits `kinitheap` → `init_output` →
`jak1::InitHeapAndSymbol`, the real upstream `lg::info("Initialized
GOAL heap in {:.2} ms", …)` (`game/kernel/jak1/kscheme.cpp:1751`)
fires, and `NumSymbols=97` at the end (26 fundamental types + 17
fixed symbols + ~25 make-function registrations + 4 from
`InitListener` + a few incidentals). exit code 0.

## qemu run

```
$ qemu-aarch64-static -L /usr/aarch64-linux-gnu build-arm64-linux/game/linux-arm64/gk
OpenGOAL gk (linux-arm64 cross-build, phase C2)
  built-tag: (none)
  built-sha: 8928ba599
linux-arm64: g_ee_main_mem mapped at 0x2123000000 (size 0x8000000)
linux-arm64: kinitheap(kglobalheap, 0x13fd20, 0x3d785c0)
[55:30:715] [info] Initialized GOAL heap in 2.7 ms
linux-arm64: C2 kernel-init complete (NumSymbols=97)
linux-arm64: C2 NumSymbols=97
```

`g_ee_main_mem` lands at the canonical `EE_MAIN_MEM_MAP = 0x2123000000`
(intentionally above 32-bit to catch Ptr<T> bugs). The
`Initialized GOAL heap` line is produced by **upstream**
`game/kernel/jak1/kscheme.cpp:1751`, not the driver — proven by
the validator's check 24 (forbids the driver from emitting upstream
log strings).

## Binary (unchanged from C1's deliverable)

- Path: `build-arm64-linux/game/linux-arm64/gk`
- `file(1)`: `ELF 64-bit LSB executable, ARM aarch64, version 1
  (SYSV), dynamically linked, interpreter
  /lib/ld-linux-aarch64.so.1, for GNU/Linux 3.7.0`
- Unstripped: **1,500,440 bytes** (≥ 1 MB floor with room).
- Stripped: **1,176,744 bytes** (≥ 1 MB floor).

## Init-family symbols in the binary

`aarch64-linux-gnu-nm --defined-only --demangle | grep -E ' T Init'`
finds 9 `Init*` text symbols including:

| Symbol                          | Source TU                              |
|---|---|
| `InitGoalProto()`               | `game/kernel/common/kdsnetm.cpp`       |
| `InitListenerConnect()`         | `game/kernel/common/ksocket.cpp`       |
| `InitSoundScheme()`             | `linux_arm64_runtime_compat.cpp` (stub) |
| `InitCheckListener()`           | `game/kernel/common/ksocket.cpp`       |
| `InitVideo()`                   | `linux_arm64_runtime_compat.cpp` (stub) |
| `InitCD()`                      | `linux_arm64_runtime_compat.cpp` (stub) |

The asm trampoline `_call_goal_on_stack_asm_arm64` plus the C wrapper
`call_goal_on_stack(...)` are both defined and ready for C3's GOAL
bytecode execution.

## What this proves

1. **glibc dynamic linker** correctly loads gk + libstdc++.so.6 +
   libm.so.6 + libc.so.6 + libgcc_s.so.1 under qemu-user. No
   missing symbol prevents startup.
2. **Static initializers** (the kernel TUs' global constructors,
   fmt/libco, etc.) run in the right order — there is no ABI
   mismatch or zero-init bug that would silently corrupt
   `kglobalheap` or the symbol table base.
3. **The 128 MB EE_MAIN_MEM mmap at 0x2123000000** works under
   qemu-user. This is critical — desktop OpenGOAL uses the high
   hint specifically to catch 32-bit-pointer bugs. The Android
   build will need the same mapping; C2 confirms qemu doesn't
   reject it.
4. **`Ptr<T>` arithmetic** is correct on aarch64 with a 64-bit
   base. `kglobalheap.offset = GLOBAL_HEAP_INFO_ADDR (0x13AD00)`;
   `HEAP_START = 0x13fd20`; `kinitheap` walks the kheapinfo struct
   at `g_ee_main_mem + 0x13AD00` and computes the heap region's
   base/top from `g_ee_main_mem + 0x13fd20` for a 64MB region —
   all of that math is in the binary now and produces a working
   kheap.
5. **`kmalloc` works.** The symbol table allocation, function-from-c
   wrappers, fixed-type entries, and the print-buf allocation in
   `init_output` all flow through `kmalloc(kglobalheap, …)`. 97
   symbols later, the heap is healthy and `NumSymbols` matches the
   expected upstream count for `MasterUseKernel=false`.
6. **`alloc_and_init_type` + `make_function_from_c`** produce
   well-shaped GOAL functions on aarch64. We don't call them in
   C2 (`MasterUseKernel=false` → no top-level GOAL execution), but
   the wrappers are constructed correctly enough that the symbol
   table walks without faulting.

## What's still ahead (C3)

- Spawn the IOP overlord thread so `BeginLoadingDGO` can answer.
- Re-enable `MasterUseKernel = 1` so InitHeapAndSymbol takes the
  `load_and_link_dgo_from_c("kernel", …)` path.
- Drive `KernelCheckAndDispatch` for at least one iteration.
- Cross-build the graphics stack (or a credible stub that won't be
  taken by the validator for a synthetic-render cheat).
- Reach the `engine: state=title`-equivalent **real** upstream
  marker (the supervisor's REDESIGN §9 reminds us no fabricated
  "engine: state=" markers — find the actual upstream string from
  `gstate.gc` once the GOAL kernel is alive).
