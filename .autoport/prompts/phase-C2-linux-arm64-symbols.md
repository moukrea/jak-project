# Phase C2 — Resolve glibc + dynamic symbol issues so gk dlopens cleanly

## What this phase delivers

A **runnable** aarch64-linux gk binary that, under
`qemu-aarch64-static`, exercises the upstream OpenGOAL kernel-init
sequence far enough that the GOAL heap is allocated, the GOAL symbol
table is populated with fundamental types (`object`, `structure`,
`basic`, `symbol`, `type`, …), and the upstream kernel logs the line
`Initialized GOAL heap in <duration> ms` produced by
`game/kernel/jak1/kscheme.cpp::InitHeapAndSymbol` (jak1/kscheme.cpp:1751).

C1 cross-built the binary but its `main()` exited with code 2 after
printing a banner — none of the kernel was exercised. C2 replaces
that slim main with a real boot driver that calls the same C++ init
chain `runtime.cpp::ee_runner` calls on desktop, minus everything
graphics/sound/discord-related (those are C3's job). C3 will then
layer on KERNEL.CGO loading via the IOP overlord and reach the title
screen with a trace-diff against the oracle.

The phase title intentionally uses the word "dlopens": the GOAL
runtime's notion of "loading a CGO and linking its top-level code"
is conceptually equivalent to a dynamic-loader's `dlopen`. C2 proves
the build's glibc + libstdc++ symbol resolution is clean, the
runtime's globals get constructed in the right order, the upstream
`*_init_globals*()` chain runs without aborting, and the kernel
heap allocator + GOAL symbol-table machinery work end-to-end under
qemu-aarch64. (Loading the actual KERNEL.CGO via the IOP overlord
RPC is the C3 milestone — C2 stops one step before that, with
`MasterUseKernel=false` short-circuiting the DGO load while still
exercising every other step of `InitHeapAndSymbol`.)

## Why this matters

Without C2 we cannot tell whether the C1 binary's symbols actually
work at runtime. The C1 validator only proved the binary builds and
has the right shape — `file`, `nm`, `readelf` reports. It did not
prove that, e.g., `kinitheap` runs to completion on aarch64 without
SIGSEGV, that `kmalloc` correctly threads its bump pointer through
the kheap, that the bsearch-based symbol-table machinery doesn't
trip a UBSan / ABI mismatch, that the `s7` register-relative symbol
addressing math survives a 64-bit pointer base
(`EE_MAIN_MEM_MAP=0x2123000000`), or that the C function-wrapper
construction in `make_function_from_c` produces a callable shape
the arm64 trampoline understands at the assembly level.

If any of those go wrong, C3's title-screen attempt will crash with
a hard-to-diagnose SIGSEGV deep inside the overlord-driven CGO
loader. C2 finds and fixes those problems in isolation: single-
threaded, no IOP, no overlord, no GOAL bytecode execution, just the
pure-C++ kernel-init sequence.

## Concrete deliverables

### 1. Replace `linux_arm64_main.cpp` with a real boot driver

The current `linux_arm64_main.cpp` (C1) prints a banner and exits
with code 2. C2 replaces it with a driver that:

1. Records `g_main_thread_id`.
2. Re-mmaps `g_ee_main_mem` at the canonical `EE_MAIN_MEM_MAP =
   0x2123000000` (declared in `common/goal_constants.h`) with
   `PROT_EXEC|PROT_READ|PROT_WRITE` so that the JIT-allocated kheap
   regions live in executable memory.  The C1 compat layer's
   default static-init `mmap(nullptr, …)` becomes a no-op when this
   driver takes over.
3. Sets the master flags for an honest "no-IOP, no-DGO" boot:
   `MasterUseKernel = false; MasterDebug = false; DiskBoot = 0;
   SplashScreen = 0;`. With `MasterUseKernel=false`, the kernel-load
   block inside `InitHeapAndSymbol` is skipped — the rest of the
   function still runs.
4. Calls the same `*_init_globals*()` chain `runtime.cpp::ee_runner`
   calls, in the same order:
   - `fileio_init_globals()`
   - `jak1::kboot_init_globals()` + `kboot_init_globals_common()`
   - `kdgo_init_globals_common()` + `jak1::kdgo_init_globals()`
   - `kdsnetm_init_globals_common()` + `klink_init_globals()`
   - `kmachine_init_globals_common()`  (compat-layer stub)
   - `jak1::kscheme_init_globals()` + `kscheme_init_globals_common()`
   - `kmalloc_init_globals_common()`
   - `klisten_init_globals()` + `jak1::klisten_init_globals()`
   - `kmemcard_init_globals()` + `kprint_init_globals_common()`
   - `xdbg::allow_debugging()`
5. Allocates the global kheap with `kinitheap(kglobalheap,
   Ptr<u8>(HEAP_START), GLOBAL_HEAP_END - HEAP_START)`.  Leaves
   `kdebugheap.offset = 0` since `MasterDebug == false`.
6. Calls `init_output()` (allocates print-buf out of global heap).
7. Calls `InitHeapAndSymbol()` — the jak1 variant.  Upstream behavior
   in the `MasterUseKernel=false` branch:
   - Allocate symbol-table buffer, set up `s7`, set up fundamental
     types (object/structure/basic/symbol/type/integer/binteger/…).
   - Set the fixed boolean/function/heap/level symbols.
   - Set `protoBlock.deci2count = intern_from_c("*deci-count*").cast<s32>()`.
   - Call `InitListener()` — interns `*listener-link-block*`,
     `*listener-function*`, `kernel-dispatcher`, `*kernel-packages*`
     and prepends `"kernel"` to `kernel_packages`.
   - Call `jak1::InitMachineScheme()` — our compat stub is a no-op
     when `MasterUseKernel=false`; the real implementation would
     register C-function symbols and (if `DiskBoot && MasterUseKernel`)
     load GAME.CGO. C3 lands a real body.
   - Call `make_function_symbol_from_c("test-function", &test_function)`.
   - Return 0.
   The upstream `lg::info("Initialized GOAL heap in {:.2} ms", …)`
   line is the **C2 ground-truth milestone**.
8. After `InitHeapAndSymbol` returns 0, prints a final
   `linux-arm64: C2 kernel-init complete (NumSymbols={N})` line for
   sanity, and `return 0;` from `main`.

The driver must NOT emit any synthetic log marker that looks like a
real upstream string. The only line the validator greps for is
`Initialized GOAL heap`, which comes directly from upstream
`kscheme.cpp:1751`. The driver's own log lines must be visibly
distinct ("linux-arm64: …").

### 2. Extend `linux_arm64_runtime_compat.cpp`

The C1 compat layer already owns `g_ee_main_mem`, `Mips2C::*`, sound
shims, etc. C2 adds the symbols the kernel-init path needs but
upstream `game/kernel/common/kmachine.cpp` would normally own.
Specifically (each is a real upstream variable/function whose body
lives in `kmachine.cpp` which pulls graphics — we own it here as
the **same name, same type, honest stub body**):

- `OverlordDataSource isodrv = fakeiso;`
- `u32 modsrc = 1;`
- `u32 reboot_iop = 1;`
- `const char* init_types[] = {"fakeiso", "deviso", "iso_cd"};`
- `u8 pad_dma_buf[2 * SCE_PAD_DMA_BUFFER_SIZE] = {};`
- `u32 vif1_interrupt_handler = 0;`
- `u32 vblank_interrupt_handler = 0;`
- `Timer ee_clock_timer{};`
- `AutoSplitterBlock g_auto_splitter_block_jak1{};`
- `void kmachine_init_globals_common()` — empty body; matches the
  upstream behavior since our globals are constexpr-initialised.
- `void InitVideo()` — empty body (no splash, by design).
- `void InitCD()` — empty body.
- `void InitGoalProto()` — empty body.
- `void ShutdownGoalProto()` — empty body.
- `void InitSound()` — empty body.
- `void ShutdownSound()` — empty body.
- `void InitSoundScheme()` — empty body.
- Any additional symbols the linker complains about when
  linux_arm64_main.cpp's new boot driver is wired in. Each must be a
  real upstream name with an honest empty body; no `weak`, no
  fabricated logs, no synthetic state-machine hooks.

C3 will progressively replace each empty body with a real
implementation as the corresponding subsystem (graphics, sound,
discord) gets cross-built.

### 3. `.autoport/lib/c2_run.sh`

Reproducible wrapper that:
1. Builds gk (re-uses C1's `c1_configure.sh` + `cmake --build`).
2. Runs `qemu-aarch64-static -L /usr/aarch64-linux-gnu
   build-arm64-linux/game/linux-arm64/gk` with a 60 s timeout.
3. Captures stdout+stderr to `.autoport/reports/C2-boot.log`.
4. Captures exit code to `.autoport/reports/C2-exit.txt`.

Idempotent (rerunning produces the same log modulo timestamps).

### 4. `.autoport/reports/C2-symbols.md`

Headline section:
- Exit code under qemu
- Time-to-`Initialized GOAL heap` (extracted from the log)
- Final `NumSymbols` count
- The `file(1)` line of gk (carried from C1)
- The `nm`-derived count of `Init*Connect`-family symbols defined

### 5. Validator at `.autoport/validators/phase-C2-linux-arm64-symbols.sh`

Strict superset of C1's validator: re-runs all 16 C1 invariants
unchanged, then layers C2's additional reality checks on top. The
authoritative list lives in §Done-definition below.

## Anti-cheat constraints

The supervisor's standard set, plus C2-specific patterns the
previous orchestrator's claude is known to reach for:

1. **No fabricated log markers.** The only log line the validator
   greps for is the upstream `Initialized GOAL heap` text. Do not
   add a print to `linux_arm64_runtime_compat.cpp` or
   `linux_arm64_main.cpp` that emits it; that would defeat the
   check. If you accidentally find yourself wanting to `lg::info` a
   string that exists in upstream code, stop and reconsider.

2. **No `weak_jak1_*` declarations.** The phase 28 cheat. Any new
   declaration whose attribute is `weak` and whose body is missing
   is a hard fail.

3. **No `kStateSeq` / `kSyntheticBootSequence` / `engine: state=*`.**
   Even relocated. Even in compat. The grep is the same as C1's.

4. **No edit to validator scripts under `.autoport/validators/`
   that LOOSENS a check.** If C1's validator's checks need
   adjustment, the only acceptable direction is stricter — see
   §Done-definition for the exact superset C2 enforces.

5. **No silent skip when the GOAL heap setup fails.** If, under
   qemu, the boot driver SIGSEGVs or aborts before
   `InitHeapAndSymbol` returns 0, the validator must report the
   failure point and exit non-zero. Adding a `setjmp`-style
   recovery to make the qemu invocation always exit 0 is a hard
   fail (caught by the validator's per-marker grep).

6. **No edit to `goalc/`** — the codegen-locked-since-A4 invariant
   carries from B1/B2/C1.

7. **No edit to upstream `game/kernel/`, `common/`, or
   `game/runtime.cpp`.** C2's work is purely additive in
   `game/linux-arm64/`. The compat layer expands; upstream sources
   stay byte-identical to A4.

8. **No regression on C1 invariants.** Each of C1's 16 checks
   re-runs as part of C2's validator. They must all stay green.

## Files you will create / modify

| Path | Purpose |
|---|---|
| `game/linux-arm64/linux_arm64_main.cpp` | rewrite — boot driver replacing the C1 banner-and-exit |
| `game/linux-arm64/linux_arm64_runtime_compat.cpp` | extend — add the kmachine-equivalent globals + stubs the boot path needs |
| `game/linux-arm64/CMakeLists.txt` | only if a new TU lands; otherwise byte-identical |
| `.autoport/lib/c2_run.sh` | new — reproducible qemu-run wrapper |
| `.autoport/reports/C2-symbols.md` | new — headline report |
| `.autoport/prompts/phase-C2-linux-arm64-symbols.md` | this file (already authored) |
| `.autoport/validators/phase-C2-linux-arm64-symbols.sh` | new — strict superset of C1 |

Read-only (must not change): everything in `goalc/`, every file in
`game/kernel/`, every file in `game/runtime.{h,cpp}`,
`cmake/aarch64-linux-toolchain.cmake` and the root `CMakeLists.txt`
(the C1 divert branch is the entry into game/linux-arm64).

## Pitfalls

- **`g_ee_main_mem` constexpr-init order.** The C1 compat layer's
  global initialiser runs before `main()`. If you mmap a second
  time in `main()` without `munmap`ing the C1 mapping first, you
  leak 128 MB. Either: (a) skip the C1 static init when
  OG_LINUX_ARM64 + a sentinel macro are both defined, (b) explicit
  `munmap(g_ee_main_mem_c1, kEEMainMemSize)` before the C2 remap,
  or (c) keep the C1 mapping and skip the C2 remap (the upstream
  kernel reads `g_ee_main_mem` by name, not by address — both
  paths work, but option (c) means HEAP_START offsets land outside
  the 32-bit canary range, which is *fine* but unusual). Pick one,
  document it.

- **`MasterUseKernel=false` short-circuit point.** Confirm by
  reading `kscheme.cpp:1753` — the `if (MasterUseKernel) { … }`
  block is the only DGO-load path inside `InitHeapAndSymbol`. The
  rest of the function (symbol setup, `InitListener`,
  `InitMachineScheme`, `test-function` reg) runs unconditionally.

- **`new_pair` inside `InitListener`.** `kernel_packages->value`
  starts at 0 (set by `klisten_init_globals`). `new_pair(…, …,
  make_string_from_c("kernel"), 0)` is the first call. The cdr=0
  case is well-defined in `new_pair`: it stores raw 0. No crash.

- **`intern_from_c` needs `FIX_SYM_STRING_TYPE` to be set up
  first.** Look at the call order in `InitHeapAndSymbol`: types
  are set up before any `set_fixed_symbol(name, value)` (the
  string-building path is needed for symbol names). If your
  re-order changes that, intern of `"nothing"` will produce
  garbage. Don't reorder; just call `InitHeapAndSymbol` as a
  single atomic operation.

- **kdebugheap with offset 0.** Several upstream call sites (e.g.,
  `kheapused(kdebugheap)` from log lines) deref `kdebugheap` when
  `kdebugheap.offset == 0`. Those call sites guard with `if
  (kdebugheap.offset) …` first — verified at
  `kdgo.cpp:189`. Don't add a non-zero `kdebugheap` value to
  avoid them; that would mean allocating a debug heap which only
  makes sense with `MasterDebug=true`.

- **`AutoSplitterBlock g_auto_splitter_block_jak1`.** Lives in
  `kmachine.cpp` upstream. Don't conflate with phase-22's
  `g_auto_splitter_block` (different game). The validator does
  not check for this symbol but its absence will fail link with
  an explicit "undefined symbol" — own it in compat with the
  upstream default-constructed type.

- **`gMusicFade` and `gStartTime`.** `runtime.cpp::exec_runtime`
  sets these. Their definitions live in `common/global_profiler/…`
  or `kprint.cpp` — verify which TU owns them in our build
  (`nm -D | grep gMusicFade` after a build) and add a compat owner
  if neither side resolves the symbol.

## Reading list

- `game/runtime.cpp::ee_runner` (lines 149-252) — the canonical
  init order. C2's boot driver mirrors this minus `mprotect`,
  `kmachine_init_globals_common` is a stub (we own the variables
  ourselves), and the `switch (g_game_version)` collapses to
  `jak1` only.
- `game/kernel/jak1/kmachine.cpp::InitMachine` (lines 309-377) —
  the post-globals init sequence. C2 calls the kheap subset and
  skips graphics/IOP/RPC/sound.
- `game/kernel/jak1/kscheme.cpp::InitHeapAndSymbol` (lines 1456-
  1789) — the heap-and-symbol setup. C2's milestone is the
  `lg::info("Initialized GOAL heap in {:.2} ms", …)` at line
  1751.
- `game/kernel/jak1/klisten.cpp::InitListener` (lines 34-49) —
  what runs after the kernel-load short-circuit.
- `common/goal_constants.h` — `EE_MAIN_MEM_MAP`,
  `EE_MAIN_MEM_SIZE`, `EE_MEM_LOW_MAP`.
- `game/kernel/common/memory_layout.h` — `HEAP_START`,
  `GLOBAL_HEAP_END`, `GLOBAL_HEAP_INFO_ADDR`.
- `.autoport/validators/phase-C1-linux-arm64-config.sh` — the
  base set of 16 checks C2's validator re-runs.

## Done definition

`.autoport/validators/phase-C2-linux-arm64-symbols.sh` exits 0.
Checks (the first 16 are C1's invariants, re-asserted unchanged;
17-25 are C2-specific):

1-16. (carried verbatim from C1) toolchain + cmake structure +
linux-arm64 CMakeLists + c1_configure.sh + cmake build + aarch64
ELF + glibc interp + stripped ≥1 MB + SHA≠stress + required
kernel symbols + no synthetic-state diff vs A4 + codegen frozen +
desktop smoke test green + C1-config.md headline + reconfigure
idempotent.
17. `.autoport/lib/c2_run.sh` exists, is executable, exits 0
    (the qemu run completes in under 60 s with exit code 0).
18. The qemu boot log at `.autoport/reports/C2-boot.log`
    contains the upstream string `Initialized GOAL heap in`
    (from `kscheme.cpp:1751`) verbatim.
19. The qemu boot log contains the driver-banner
    `linux-arm64: C2 kernel-init complete` (proves we reached
    after `InitHeapAndSymbol` returned 0 and the driver kept
    running past it).
20. The qemu boot log does NOT contain any of: `SIGSEGV`, `SIGILL`,
    `qemu: uncaught target signal`, `terminate called`, `Assertion
    failed:` (qemu's hard-failure messages). A single ASSERT can
    sneak past a happy-path grep — these are belt-and-braces.
21. The qemu boot log does NOT contain the forbidden synthetic
    markers `kStateSeq`, `engine: state=boot`, `engine: state=load`,
    `engine: state=title`, `weak_jak1_`.
22. C2-symbols.md exists and contains the headline lines (exit
    code, time-to-heap, NumSymbols).
23. `linux_arm64_runtime_compat.cpp` (the C2-extended version)
    does NOT match the forbidden regex `(__attribute__\s*\(\(weak|
    kStateSeq|kSyntheticBootSequence|engine:\s*state=(boot|load|
    title)|weak_jak1_)`.
24. `linux_arm64_main.cpp` does NOT emit any of the upstream log
    strings the validator greps for (anti-forgery: a `printf` of
    `Initialized GOAL heap` in our driver would defeat check 18).
25. The qemu boot log records, on a line starting with
    `linux-arm64: C2 NumSymbols=`, a symbol count ≥ 75 (a
    sanity floor — upstream's InitHeapAndSymbol interns ~26
    fundamental types + ~17 fixed symbols + ~25 make-function
    registrations + 4 from InitListener even with
    MasterUseKernel=false, empirically 97 on this build).

When all 25 pass, the binary has demonstrably executed real
upstream kernel-init code on aarch64 under qemu-user, and C3 can
build on a foundation that is provably alive.
