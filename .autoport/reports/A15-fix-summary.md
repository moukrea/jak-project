# A15 fix summary — regalloc constraint: arm64 IDIV implicitly clobbers X8

## What changed

**File**: `goalc/regalloc/Allocator_v2.cpp` (the V2 register allocator, first
unlock of `goalc/regalloc/` since A1).

**Diff shape**: +43 lines, no deletions, no behaviour change outside
`#ifdef GOALC_BACKEND_ARM64`. x86 builds and x86 CGOs are unaffected
(verified by validator check 7 — x86 CGOs byte-identical to A2 baseline).

## The constraint

A new helper `is_arm64_idiv_class(const RegAllocInstr& instr)` returns
`true` when the instruction's `exclude` field is exactly `{RDX}`. Per
`grep '\.exclude\.(emplace_back|push_back)' goalc/`, **IR.cpp:816 is
the sole caller of `exclude.emplace_back` in the entire codebase**, and
it only sets `exclude={RDX}` for `IDIV_32 / IMOD_32 / UDIV_32 / UMOD_32`.
So this signature uniquely identifies IDIV-class IR ops.

In `check_register_assign_at` and `check_register_assign`, after the
normal clobber/exclude checks, the new constraint adds:

```cpp
#ifdef GOALC_BACKEND_ARM64
if (reg == emitter::Register(emitter::X8) && is_arm64_idiv_class(instr)) {
  if (cache.liveout_per_instr.at(instr_idx)[var_idx] && !instr.writes(var_idx)) {
    return false;
  }
}
#endif
```

Semantics: treat X8 (Register(8)) as implicitly clobbered for IDIV-class
ops. The check mirrors the existing clobber-check at lines ~776 and
~870: if the candidate var is live-out at the IDIV but isn't written by
it, X8 cannot be its home (the SDIV/UDIV would silently overwrite the
var's value).

## Why this works (and why it's narrow)

**The bug** (from `A14-attempt-1-next-blocker.md`): the arm64 emitter
hardcodes the SDIV/UDIV destination to `Register(8)` = X8 (see
`goalc/emitter/IGenARM64.cpp::idiv_gpr32`), regardless of what register
the IR-level allocator chose for `m_dest`. But the IR's `to_rai()` only
exposes `exclude={RDX}` (= enum 2 = X2 on arm64), which is irrelevant to
the actual arm64 instruction. So the V2 allocator was free to park any
vreg in X8 across an IDIV, and the SDIV would clobber it.

At the `sin*!` call site the regalloc parked **v_fnptr** (the loaded
sym value, alive from the LDR W8 through the BLR X8 ~25 instructions
later) AND **v_div** (the SDIV destination for the degree-to-radian
`/10` conversion, single-use) both in X8. SDIV ran, X8 got
`(fn-ptr / 10)`, BLR jumped to ee_base + 0x84812 (unaligned), SIGBUS.

**The fix** narrowly makes the allocator aware that arm64 IDIV writes
X8 implicitly. For v_fnptr (live-out at the IDIV, not written by it),
the new check returns `false` → X8 is rejected as v_fnptr's home → the
allocator picks a different reg (or reloads the fn-ptr post-IDIV).

The IDIV's own `m_dest` is force-constrained to `emitter::RAX` by
`Math.cpp:462-466` (and `Math.cpp:630-634` for IMOD), which is enum 0 =
X0 on arm64 — so `m_dest` is never assigned to X8 itself, and the new
clobber check doesn't disrupt the IDIV destination's allocation.

## Disassembly snippet — before vs after at sin*!

**Before A15** (post-A14 ENGINE.CGO, from `A14-attempt-1-next-blocker.md`):

```
lr- 96  b9400208  ldr   w8,  [x16]      ; w8 = sin*! sym value = 0x52d0b4
lr- 80  9ac90d08  sdiv  x8,  x8,  x9    ; x8 = 0x52d0b4 / 10 = 0x84812   ← CLOBBER
lr- 28  aa0803e8  mov   x8,  x8         ; "preserve" the WRONG value
lr- 20  8b0f0108  add   x8,  x8,  x15   ; X8 = ee_base + 0x84812 (junk)
lr-  4  d63f0100  blr   x8              ; SIGBUS (unaligned PC)
```

**After A15** (post-fix ENGINE.CGO, the analogous call-site cluster at
`out/jak1-arm64/iso/ENGINE.CGO` offset `0xcd33c..0xcd3a4`):

```
cd33c:  9ac90d08  sdiv x8, x8, x9       ; SDIV result lands in X8
cd340..cd35c: (unrelated arithmetic + branch)
cd370:  90000010  adrp x16, 0xcd000     ; ── basic-block entry ──
cd374:  91000210  add  x16, x16, #0     ;    sym slot ADRP/ADD
cd378:  b9400209  ldr  w9, [x16]        ;    w9 = fn-ptr sym value (FRESH RELOAD)
cd37c:  aa0903e8  mov  x8, x9           ;    x8 = fresh fn-ptr
cd380..cd390: (arg shuffle)
cd394:  8b0f0108  add  x8, x8, x15      ;    GOAL → host
cd3a4:  d63f0100  blr  x8               ;    → real sin*! function
```

This matches **pattern (b)** from the A15 prompt's verification criteria:
the fn-ptr is reloaded from its sym slot before the BLR. The previous
`mov x8, x8 ; add x8, x8, x15 ; blr x8` chain (carrying the SDIV-
clobbered value) is gone.

## Yield

| Metric                           | A14 ceiling | A15 result |
|----------------------------------|------------:|-----------:|
| qemu-aarch64-static link-finishes |        166 |        212 |
| New CGOs linked past A14         |          0 |        +46 |
| ENGINE.CGO sha256                |  81b41087… |  a62bbf7f… |
| GAME.CGO sha256                  |  ddc16e88… |  100593cc… |
| KERNEL.CGO sha256                |  f4107e2b… |  f4107e2b… (unchanged — no IDIV in kernel CGOs) |

The +46 CGOs include `merc-blend-shape`, `ripple`, `joint-mod`, and
many other float/trig-heavy CGOs whose top-levels invoke `sin*!`,
`cos*!`, and other trig helpers that were latent on the same SDIV-
clobbers-fn-ptr pattern.

## What this does NOT do (anti-attempt-1 hygiene)

Per cookbook §11's A15-attempt-1 lesson, this fix is **narrow** — just
the X8 implicit-clobber awareness. It does NOT:

- Add a "function-crossers promotion" that pins every `IR_FunctionCall::m_func`
  to saved-first allocation in IDIV-containing functions (attempt-1's
  broad change, which caused sig=4 SIGILL at math-camera-h on the real
  Redmi Note 9 Pro despite qemu accepting it).
- Touch any other regalloc invariant (spill ops, AAPCS arg shuffles,
  function-crossers ordering).
- Modify the IR layer, codegen layer, emitter, runtime, or validator
  infrastructure.

The fix is structurally a 1-bit change to the regalloc's view of IDIV:
"X8 is also clobbered, not just RDX/X2."

## Next blocker (post-A15)

qemu_repro now crashes at sig=4 SIGILL with `pc=0x2123000000 = ee_base`
— the classic "BLR to ee_base" shape, i.e. another unbound symbol slot
(sym value = 0 → host addr = ee_base → UDF #0 → SIGILL). This is a
different bug class from A15 (sym-binding, not regalloc). The supervisor
should author the next phase to identify and bind the missing pc-* (or
similar) helper after `pckernel` linked but before the post-pckernel CGO
ran its top-level.

The last 10 linked CGOs before the new crash:

```
link finish: speedruns-h
link finish: game-info
link finish: game-save
link finish: settings
link finish: pc-anim-util
link finish: autosplit-h
link finish: autosplit
link finish: speedruns
link finish: pckernel-common
link finish: pckernel
```
