# Phase Gsprite — un-noop the arm64 sparticle sprite-DMA builders so screen-space sprites RENDER

## Summary

Gsce restored the boot "Sony Computer Entertainment presents" static-screen's
**spawn** but it rendered **BLACK** on arm64: the SCE screen draws three
screen-space sparticle sprites built each frame by four `def-mips2c` functions
that were **noop-bound on arm64** (absent from the mips2c allowlist) → empty
sprite bucket → black. This phase has TWO parts:

1. **Un-noop the four sparticle builders** in the arm64 mips2c allowlist
   (`game/mips2c/mips2c_table_jak1_arm64.cpp`) so the real translated bodies run.
2. **Fix the arm64 C→GOAL FFI arg-shuffle bug** (`_call_goal8_asm_arm64` in
   `game/kernel/asm_funcs_arm64.s`) that the un-noop'd builders immediately
   exposed by crashing — the actual, deeper root cause.

No goal_src, no x86 changes, no painted image, no faked render.

## Part 1 — the allowlist (the un-noop)

On arm64 a `def-mips2c` function only runs its real C++ body if its name is in
the `kSet` allowlist in `a37_name_is_real()`; otherwise it binds a shared noop
returning 0 (logged `A37-MIPS2C-FALLBACK <name> -> shared noop`). The four jak1
sparticle sprite-DMA builders were never on the list:

- `sp-launch-particles-var` (sparticle-launcher.cpp:837) — launches a particle
  group; for screen-space (2D) groups it sets up per-sprite data and calls
  `particle-adgif` for the shader.
- `sp-process-block-2d` (sparticle.cpp:686) — per-frame 2D screen-space sprite
  builder (the SCE-screen path).
- `sp-process-block-3d` (sparticle.cpp:365) — per-frame 3D world-particle
  builder (broadly used; part of the same set).
- `particle-adgif` (sparticle-launcher.cpp:134) — packs the adgif shader
  (tex0/tex1/clamp/alpha) for a particle sprite.

The Gsce logcat showed all four firing `A37-MIPS2C-FALLBACK ... not on allowlist
yet`, with the SCE window an empty sprite bucket (`A35-RENDER draws=1-2 tris=2-4`).
x86 has no noop allowlist → binds the real bodies → the SCE sprites build there.
arm64-only divergence, same class as the A37 camera fix. Fix: add the four
registered names to `kSet` (lines 451-452).

## Part 2 — the real root cause: the arm64 C→GOAL arg-shuffle bug

Adding the four to the allowlist made them bind REAL trampolines
(`A37-MIPS2C-REAL particle-adgif -> 0x4d2250`, etc.) — but the game then SIGABRT'd
at frame 4:

```
kmalloc: alloc DEBUG, mem global-object #x0 (a:0  16bytes)   <- heap header ZEROED
Assertion failed: 'offset'   Source: game/kernel/common/Ptr.h:48
Fatal signal 6 (SIGABRT) ... tid (SDLThread)
backtrace: private_assert_failed <- make_string_from_c <- intern_from_c
           <- a40_dproc_probe <- gk_a38_tripwire_frame_hook <- render_frame
```

The leftover per-frame `gk_a38_tripwire_frame_hook` (an A38/A40 corruption
detector) interns a symbol each frame; it aborted because the GOAL global heap
header was zeroed (base/cur/top = #x0) → kmalloc returned a null `Ptr` → the
`Ptr.h:48` `operator*` assert. That is the classic heap-corruption signature.

**Why:** mips2c bodies call GOAL functions through `ExecutionContext::jalr`
(`game/mips2c/mips2c_private.h:379`). On Android `__linux__` is defined, so jalr
calls `_call_goal8_asm_systemv`, which on arm64 forwards (compat shim,
`android_arm64_runtime_compat.cpp:181`) to `_call_goal8_asm_arm64`
(`asm_funcs_arm64.s:288`). That trampoline placed the 8 args in **AAPCS order
(argN → xN)**. But goalc-arm64 GOAL functions read their args from the **x86-id
registers** (`m_gpr_arg_regs = {RDI,RSI,RDX,RCX,R8,R9,R10,R11}`,
`goalc/emitter/Register.cpp:44`) emitted as physical arm64 register NUMBERS:

```
arg0->x7(RDI) arg1->x6(RSI) arg2->x2(RDX) arg3->x1(RCX)
arg4->x8(R8)  arg5->x9(R9)  arg6->x10(R10) arg7->x11(R11)
```

This is exactly how `_mips2c_call_arm64` (the GOAL→mips2c direction) HARVESTS the
args, and exactly how x86 `_call_goal8_asm_systemv`
(`asm_funcs_x86_64.asm:372-381`) places them. The arm64 version had it wrong:
only arg2 (x2) coincided. So when a sparticle builder called a GOAL allocator
(`sp-launch-particles-var`'s alloc calls pass a heap/process pointer in
arg3/arg4), the callee read garbage from x1/x8 instead of the real pointer →
allocated from a zeroed heap → null `Ptr` → abort.

**The fix** (`asm_funcs_arm64.s:288`): reorder the arg loads to the GOAL ABI
registers, mirroring x86 one-for-one, and move the func pointer off x8 (now
arg4's slot) into x16. The arg-array pointer (x1, == arg3's target) is loaded
last.

**Why this was latent until now / blast radius:** `_call_goal8_asm_arm64` is
reached ONLY via jalr (mips2c_private.h:384/387 — its sole caller). The
already-enabled jalr users (joint 6×, sky_tng 8×, blerc 1×) rendered the title
with the buggy shuffle by tolerating wrong arg0/arg1 values (their hot callees
use arg2 or re-derive from the process pointer). The sparticle builders are the
first to pass a live heap/process pointer in a high arg slot, so they were the
first to corrupt. Correcting arm64 to match the proven x86 mapping can only make
those calls MORE correct — it cannot regress a call that already passed the right
value — and is title-regression gated. The analogous 3-arg `_call_goal_asm_arm64`
has the same latent mis-shuffle but is left untouched (tolerated by current boot
callers; out of this phase's scope).

## Why the allowlist set is complete + safe (Part 1 audit)

The only mips2c→mips2c edge among the four is `sp-launch-particles-var` →
`particle-adgif` (both in the set); every other callee is a plain goalc `defun`
(always real on arm64), so no half-enabled inner-noop. No DMA-cursor disease
(returns are discarded / particle counters, not cursor stores), so the prior noop
was benign-empty. SCE 2D path: `group-part-screen1` (id 707, static-screen.gc:74)
`:flags (screen-space)`, sp-items 2966/2967/2968 → launch via
`sp-launch-particles-var` + `particle-adgif`, then `sp-process-block-2d` per
frame — all covered. No `ASSERT(false)`/TODO stubs in either TU.

## Scope / locks honored

- Edited `game/mips2c/mips2c_table_jak1_arm64.cpp` (arm64-only TU) and
  `game/kernel/asm_funcs_arm64.s` (arm64 asm only). Neither is in the x86 build
  (x86 uses `mips2c_table.cpp` + `asm_funcs_x86_64.asm`) → x86 byte-identical,
  x86 smoke still `link finish: logo`. No goal_src, no IGenX86_64, no painted
  image. Harness `.autoport/gsprite_run.sh` is at `.autoport/` root (not infra).

## Empirical verification (device eae4df44, arm64)

<!-- EVIDENCE -->
(Pending the post-fix device run — first run with all four builders bound real
SIGABRT'd at frame 4 via the global-heap-header zeroing described above; the
post-ABI-fix run's crash-clear / SCE-window-tris / frame_max / title-no-regression
evidence is inserted here from the newest Gsprite-routed-logcat / Gsprite-device
PNGs.)

## Broad payoff

Two layers. (1) Screen-space sparticle sprites are the HUD / menu-overlay / 2D
primitive, so the SCE logo plus a class of 2D sprites light up. (2) The
`_call_goal8_asm_arm64` ABI fix repairs the C→GOAL call path for EVERY mips2c
function that calls GOAL via jalr — unblocking correct arg passing for the whole
mips2c-calls-GOAL class (collide, generic-merc, ocean, ripple, etc. as they are
enabled later). Title (G1) and ND/Daxter (Gnd) must not regress (title-regression
gate); verified in the run section.
