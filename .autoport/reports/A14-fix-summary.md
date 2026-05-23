# A14 fix summary — `__mem-move` bound; boot advances dma-buffer → debug-sphere (+8 CGOs)

Authored 2026-05-23 in the A14-pc-memmove-bind phase.

## The bug

Post-A13 the boot ceiling on linux-arm64 (and the Redmi Note 9 Pro
device) sat at 158 unique CGOs linked, with `sig=4 SIGILL` at
`pc=ee_base` just after `link finish: collide-func`. The A11+A12
diagnostic chain (texture-sym-zero triplet scan + stack-fnptr-zero
backward provenance) named the failing sym definitively:

```
GK-DIAG A11-DIAG texture-sym-zero: slot=0x720c1aea1c value=0x0
  info=0x720c1cea18 hash=0x9290899a str=0x4f14e4 name="__mem-move"
  in_sym_range=1
```

`__mem-move` (hash `0x9290899a`) is the GOAL kernel's fast-memcpy
entry point — invoked by `dma-buffer`'s top-level to copy DMA-chain
templates into scratch buffers. Its C implementation
(`pc_memmove` at `game/kernel/common/kmachine.cpp:480`) is wired in
the upstream `init_common_pc_port_functions` registration table,
but BOTH the linux-arm64 and android-arm64 builds skip that table
(android via `android_runtime_compat.cpp::init_common_pc_port_functions`
override; linux-arm64 inherits the gap via its own runtime-compat
stub list). Without a binding, the A5 sym-MEM `LDR W9, [X16, #0]`
pulled 0, `ADD X9, X9, X15` made `X9 = ee_base`, and `BLR X9`
landed at the EE map's first word (a UDF #0) → SIGILL.

## The fix — bind `__mem-move` via the A11/A12 klink helper pattern

A new helper `klink_a14_ensure_pc_memmove_bound` in
`game/kernel/common/klink.cpp` mirrors the A11 + A12 binders:

- Static-local guard for idempotency.
- `SymbolTable2.offset == 0` early-return so callers can fire it
  before `jak1::InitHeapAndSymbol` returns.
- Single `jak1::make_function_symbol_from_c("__mem-move", …)` call
  that registers the GOAL sym pointing at a local impl
  (`a14_pc_memmove_impl`).
- Bind-trace `A14-DIAG sym-bind-trace:` line on stderr so the
  scoreboard can confirm the binding fired.

The local impl is a literal 1-line wrapper:

```cpp
void a14_pc_memmove_impl(u32 dst, u32 src, u32 size) {
  memmove(Ptr<u8>(dst).c(), Ptr<u8>(src).c(), size);
}
```

…which mirrors `pc_memmove` (kmachine.cpp:480-482) byte for byte.
We re-define it locally rather than `extern`-declaring the upstream
symbol because **neither the linux-arm64 nor the android-arm64
build compiles `game/kernel/common/kmachine.cpp`** — that TU pulls
`Display::*` + `Gfx::*` + discord + sce-libgraph transitively,
none of which have arm64 bodies yet (see the linux-arm64 CMakeLists
comment "no kmachine/kboot here: those pull graphics" and the
android CMakeLists' equivalent exclusion). Honest analogue of what
A11 did for `pc_get_mips2c` (also a `kernel/common/kmachine.cpp`
helper not reachable from the arm64 builds).

Call sites:

- `game/linux-arm64/linux_arm64_main.cpp::boot_kernel_init` —
  immediately after `klink_a12_ensure_sound_rpc_bound`, before
  `::a13_arm64_init_iop()`.
- `android/gk_android_main.cpp::a11_install_pc_mips2c_hook_once` —
  chained into the lambda right after the A12 bind, before the A13
  note (the lambda is installed onto
  `g_jak1_pre_kernel_version_check_hook`).

Both call sites are inside the same pre-version-check hook the A11
+ A12 helpers already use, so the bind always fires before the
first CGO that needs `__mem-move` ever runs its top-level.

Anti-cheat safety:
- `a14_pc_memmove_impl` has `_impl` suffix (same as
  `a11_pc_get_mips2c_impl`), but the body is a real `memmove` call,
  not `return 0;` — so the rename-evasion stub-shape detector
  passes.
- No new `_stubs.cpp`, no `abort()`/`weak_` additions, no infra
  edits, no codegen edits.

## Post-fix qemu_repro evidence

```
qemu_repro.sh: 166 'link finish:' lines captured.
FIRST POST-FIX CGO LINKED: dma-buffer
```

Last 10 CGOs linked under qemu post-A14:

```
link finish: transformq
link finish: collide-func
link finish: joint
link finish: cylinder
link finish: wind
link finish: bsp
link finish: subdivide
link finish: sprite
link finish: sprite-distort
link finish: debug-sphere
```

Net advance: **+8 CGOs (158 → 166)**. Notably, `dma-buffer` —
the CGO whose `__mem-move` call triggered the A13-attempt-3 next-
blocker — now links cleanly. The `A14-DIAG sym-bind-trace:` line
appears in stderr before the first link begins, confirming the bind
fires.

## What the fix exposes — A15 next-blocker (regalloc, not sym-binding)

The boot ceiling advanced to 166 CGOs but hits a **different bug
class** at the very next CGO past `debug-sphere`. The new crash:

```
GK-DIAG sig=7 fault=0x2123084812 pc=0x2123084812 lr=0x212492ff7c
GK-DIAG x8=0x2123084812   ←← BLR target (clobbered)
GK-DIAG x15=0x2123000000  ←← ee_base
```

PC = ee_base + 0x84812 = an **unaligned** instruction-fetch address
(bit 1 set), so it's SIGBUS rather than SIGILL. The full LR-relative
disasm window (decoded via `aarch64-linux-gnu-objdump`) shows:

```
ldr   w8, [x16]      ; w8 = sin*! sym value = 0x52d0b4 (valid fn-ptr)
mov   x0, #0xb4
mov   x9, #0xa
sdiv  x8, x8, x9     ; x8 = 0x52d0b4 / 10 = 0x84812  ← CLOBBERS fn-ptr
scvtf s23, w0
… fp arithmetic …
mov   x8, x8         ; no-op (x8 still has SDIV result)
add   x8, x8, x15    ; x8 = ee_base + 0x84812
blr   x8             ; SIGBUS on unaligned PC
```

The sym `sin*!` (hash `0xff8c9691`) IS bound (slot value =
`0x52d0b4` ≠ 0) — so this is **NOT another unbound-pc-helper**
cascade. It's a **register-allocator bug**: the codegen picked X8
for two independent purposes — holding the function pointer for
the BLR, AND as the destination of an SDIV that's part of the
argument computation — and the SDIV destroys the function pointer
before the BLR fires.

A14's prompt anticipated a "yet another unbound pc-*" cascade as
the likely next-blocker. The actual next-blocker is more interesting:
it's the first **codegen-class** crash exposed past dma-buffer,
specifically a **regalloc same-reg collision between the call-target
reg and an SDIV temp**.

Detailed write-up + recommended A15 framing in
`.autoport/reports/A14-attempt-1-next-blocker.md`.

## What changed since attempt-1 (this attempt)

| Layer                              | attempt-1 (this)          |
|------------------------------------|---------------------------|
| `klink_a14_ensure_pc_memmove_bound`| added to klink.cpp        |
| `a14_pc_memmove_impl`              | added (1-line memmove)    |
| klink.h declaration                | added next to A11+A12     |
| linux_arm64_main.cpp chain         | after A12, before A13     |
| gk_android_main.cpp chain          | after A12 in lambda       |
| qemu_repro link-finish count       | 166 (+8 vs A13 ceiling)   |
| `dma-buffer` top-level CGO         | links cleanly             |
| Desktop x86 smoke                  | 446 link-finishes (unchanged)|
| arm64 CGO byte-identity            | matches A11 baseline      |
| Next-blocker                       | regalloc fn-ptr/SDIV clash (A15 codegen scope) |

## Anti-cheat invariants — A14 status

- 0 dodges, 0 abort/weak additions, 0 new `_stubs.cpp`, 0 inline
  `_stub(` additions, 0 rename-evasion stub-shaped functions.
- 0 modifications to codegen (IGenARM64, ObjectGenerator,
  CodeGenerator, IR), asm trampoline (`asm_funcs_arm64.s`),
  `kscheme.cpp`, `kmachine.cpp`, `IOP_Kernel.{cpp,h}`,
  `linux_arm64_runtime_compat.cpp`, `android_runtime_compat.cpp`.
- 0 modifications to `.autoport/lib/*` / `.autoport/validators/*`.
- x86 CGOs byte-identical to A2 baseline (no rebuild needed; x86
  build only links the new helper as dead code since neither
  desktop main calls it).
- arm64 CGOs byte-identical to A11 baseline (no goalc-arm64
  rebuild needed; only `gk` was rebuilt).
- ENGINE.CGO CBZ-Xt,+40 occurrences unchanged (= 4, well below
  the 10-cheat threshold).

## Honest exit

The A14 prompt:

> If A14's bind lands but boot then hits yet another pc-* helper
> (highly likely — dma-buffer's top-level probably uses
> `__send-gfx-dma-chain` or similar next), commit the bind + write
> `A14-attempt-N-next-blocker.md` naming the next unbound symbol +
> recommending A15. The cascade may continue helper-by-helper or
> the supervisor may pivot to A-bulk (bind all non-Display/non-Gfx
> pc-* helpers at once).

This attempt-1 fires that clause but with a refinement: the next
blocker is **not** another unbound pc-* helper. The `__mem-move`
bind opened up 8 more CGOs (dma-buffer through debug-sphere) all
linking cleanly. The first crash past those is a codegen-class
regalloc bug — same physical reg (X8) chosen for both the
call-target fn-ptr and an SDIV destination in trig-math argument
prep.

Per the cookbook §10 ("Honest-exit pattern") and the prompt's
rate-budget caution (84% weekly utilization at phase start; 85%
halt threshold), this attempt commits the A14 fix + the
attempt-1-next-blocker analysis and does NOT spin attempt-2 against
an out-of-A14-scope codegen bug. The supervisor's next move is
either:

- **A15 (codegen unlock)** — narrowly unlock `goalc/regalloc/` to
  fix the same-reg collision between fn-ptr-target and SDIV
  destination, OR
- **A15 (alternate path)** — if the trig-call site has a simpler
  GOAL-side fix (e.g. an inline-`/`-rewrite in trigonometry.gc that
  would dodge the regalloc collision), pursue that first.

Rate-budget guard fired exactly as the prompt prescribed: one
honest attempt, narrow scope, no scope-creep into codegen.
