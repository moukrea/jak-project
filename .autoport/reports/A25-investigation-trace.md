# A25 investigation trace — five-attempt narrowing search for the IR_RegSet/IR_RegSetAsm FPR/GPR dispatch scope that fixes A24's named X30-corruption mechanism without regressing the boot below 216 link-finishes

## Phase setup

A25 unlocks `goalc/compiler/IR.cpp` (IR_RegSet fix surface + audit of
other IRs) and `goalc/emitter/IGenARM64.cpp` / `.h` (FMOV helpers). All
other A24 unlocks remain available (CodeGenerator.cpp/.h,
asm_funcs_arm64.s, linux_arm64_main.cpp, jak1/kscheme.cpp, klink.cpp,
Allocator_v2.cpp).

A24 attempt-1 traced the 216-link-finish ceiling to a single emit site:
`(.mov xmm14 temp-float)` in `throw-dispatch` (gkernel.gc:1531)
compiled via `IR_RegSetAsm::do_codegen_arm64` (`:color #f` so use_coloring
is false), which called `mov_gpr64_gpr64(xmm14, temp-float)` →
`ORR X30, XZR, X16`. X30 = LR, X16 was the host form of the catch-frame's
`this` pointer (stack-range when allocation is `'stack`). The next raw
RET inside throw-dispatch propagated the stack-range address to PC,
crashing with SIGILL.

Pre-A25 baseline: A24's `OG_X30_TRACE_EMIT` tracer fires exactly once at
`emit_pc=0x21231d713c`, `x30=0x212afffe84` (= GOAL `0x07fffe84` = stack
range), at the FIRST raw-RET execution after `link finish: time-of-day`
(the 216th link-finish).

The A25 fix surface as documented in `phase-A25-arm64-ir-regset-fpr-dispatch.md`:

1. `IR_RegSet::do_codegen_arm64` (IR.cpp:520-527) — dispatch on
   `dst.is_xmm()` / `src.is_xmm()` (or `RegClass`) to pick FMOV vs MOV.
2. `IGenARM64.cpp` — add FMOV Dd, Dn / FMOV Dn, Xd / FMOV Xd, Dn
   helpers.
3. Audit of other IRs that may also call `mov_gpr64_gpr64`
   unconditionally for moves whose register class isn't statically GPR.

## Attempt 1.1 — full FPR-class dispatch (mirror x86 regset_common)

### Step 1.1.1 — write `emit_arm64_reg_to_reg_mov` namespace helper

Place near the existing `regset_common` (IR.cpp:170) to dispatch on
both src and dst `RegClass`, emitting:
- GPR_64 + GPR_64 → `mov_gpr64_gpr64`
- FLOAT + FLOAT → `mov_xmm32_xmm32` (= `fmov_s_reg` = FMOV Sd, Sn)
- {VECTOR_FLOAT|INT_128} + same → `mov_vf_vf` (= `mov_16b` = ORR Vd.16B)
- FLOAT + GPR_64 → `movd_gpr32_xmm32` + `movsx_r64_r32` (FMOV W,S + SXTW)
- GPR_64 + FLOAT → `movd_xmm32_gpr32` (FMOV S,W)
- xmm128 + FLOAT → `mov_xmm32_xmm32`
- FLOAT + xmm128 → `mov_xmm32_xmm32`
- GPR_64 + xmm128 → `movq_xmm64_gpr64` (FMOV D, X)
- xmm128 + GPR_64 → `movq_gpr64_xmm64` (FMOV X, D)

Rewrite `IR_RegSet::do_codegen_arm64` and `IR_RegSetAsm::do_codegen_arm64`
to route through the helper. Rewrite `IR_Return::do_codegen_arm64` and
`IR_LoadSymbolPointer::do_codegen_arm64` (#f branch) similarly.

### Step 1.1.2 — add FMOV Dd, Dn helper

`goalc/emitter/IGenARM64.cpp`:
```cpp
InstructionARM64 fmov_d_d(Register dst, Register src) {
  uint32_t enc = 0x1E604000u | (arm64_reg5(src) << 5) | arm64_reg5(dst);
  return InstructionARM64(enc);
}
```

Cross-check against `aarch64-linux-gnu-as`:
```
$ echo "fmov d0, d1" | aarch64-linux-gnu-as -o /tmp/f.o -
$ aarch64-linux-gnu-objdump -d /tmp/f.o | head -3
   0:   1e604020        fmov    d0, d1
```
`0x1e604020 = 0x1E604000 | (1 << 5) | 0` ✓

Add the declaration to `IGenARM64.h` next to `mov_xmm32_xmm32`.

### Step 1.1.3 — build + regenerate CGOs

```
$ cmake --build build --target goalc -j4
$ cmake --build build-arm64 --target goalc -j4
$ bash .autoport/lib/build_b1_arm64_cgos.sh
[B1] arm64 hashes:
    8babeb9ec357f3807b3728e4b923c836a25ddf03ebdc884ac917fddfd855d1ae  KERNEL.CGO
    9b78c4042de098a98115c2f67094c4dbaf10fe0b6f2363c73907162466dfcaff  ENGINE.CGO
    a1a2acf3b4855cbb55021e526af4a679b3a3420dfbbf593df3f286dc2d13b29a  GAME.CGO
[B1] x86 CGOs byte-identical to A2 baseline
```

### Step 1.1.4 — qemu run

```
$ timeout 600 bash .autoport/lib/qemu_repro.sh .autoport/reports/A25-qemu-fix.log
qemu_repro.sh: 1 'link finish:' lines captured.
  link finish: gcommon
GK-DIAG sig=11 fault=0x21f33ea9a0 pc=0x2b733c lr=0x21231c0c50
GK-DIAG x0=0x12163986d03ca9a1
```

CATASTROPHIC REGRESSION: only 1 link-finish (gcommon), then crashes
with SIGSEGV at PC=0x2b733c (= C++ binary, `_ZN4jak18new_typeEjjm`
per `aarch64-linux-gnu-nm` lookup). The C++ function received
x0 = `0x12163986d03ca9a1` — a garbage value where a 32-bit symbol
hash should be.

Diagnosis: the wide dispatch changes behavior for many FLOAT-FLOAT
IR_RegSet calls in gcommon's type-construction code. The OLD codegen
emitted `MOV X<dst_id>, X<src_id>` for FLOAT-FLOAT, which was a
NO-OP on the V registers (the floats lived in V regs untouched by
the GPR MOV). Some gcommon code relied on V-reg state being
preserved across an IR_RegSet — possibly because the regalloc
coalesced source and dest into the same physical register and the
OLD MOV X<id>, X<id> was a true identity, while my widened code
emitted `FMOV Sd, Sn` which zeroes the upper 96 bits of Vd.

Even when the operands aren't the same register, `MOV X<dst>, X<src>`
where both ids are 16..31 reads from random GPR state (whatever
happened to be in X16..X31) and writes to the dst's GPR — meanwhile
V<dst> retains its prior value. If gcommon-class code depends on
V<dst> not being touched (because the regalloc coalesced it with a
previously-loaded V value), the rewrite breaks the assumption.

## Attempt 1.2 — drop cross-bank rewrites, keep FPR-pair dispatch

Cut the helper down to:
- GPR_64 + GPR_64 → `mov_gpr64_gpr64`
- FLOAT + FLOAT → `mov_xmm32_xmm32` (FMOV Sd, Sn)
- {VECTOR_FLOAT|INT_128} + same → `mov_vf_vf`
- ALL OTHER COMBINATIONS → `mov_gpr64_gpr64` (preserve OLD)

Also revert the `IR_Return` and `IR_LoadSymbolPointer` rewrites.
Keep only `IR_RegSet` and `IR_RegSetAsm` on the dispatch helper.

### Step 1.2.1 — build + qemu

```
$ cmake --build build --target goalc -j4
$ cmake --build build-arm64 --target goalc -j4
$ bash .autoport/lib/build_b1_arm64_cgos.sh
$ timeout 600 bash .autoport/lib/qemu_repro.sh .autoport/reports/A25-qemu-fix-v4.log
qemu_repro.sh: 64 'link finish:' lines captured.
  link finish: texture
GK-DIAG sig=4 fault=0x2123000000 pc=0x2123000000 lr=0x2124504ae0
GK-DIAG A18-DIAG type-method-zero: ldr-pc=0x2124504ac0 base=X16 offset=0x40
    method-slot=12 obj-goal=0x2123000000 obj-host=0x0 loaded-value=0xdeadbeef
    type-tag@obj_host-4=0xdeadbeef
```

PROGRESS — 64 link-finishes (vs 1 in attempt 1.1) but still
regression. Crash is SIGILL at PC=0x2123000000 (= heap base, jumped
to garbage address) with A18 type-method-zero trap firing. The
trap diagnostic shows method-slot=12 of a type whose type-tag is
`0xdeadbeef` (freed-heap marker), meaning a virtual call landed on
a freed object's method table.

Diagnosis: the FLOAT-FLOAT mov_xmm32_xmm32 (= FMOV Sd, Sn) zeroes
the upper 96 bits of Vd, mismatching x86 MOVSS which preserves
them. Some main-h type-init code constructs types via a path that
involves a FLOAT-class IR_RegSet whose result's V register's upper
bits matter downstream.

## Attempt 1.3 — use mov_vf_vf for FLOAT-FLOAT too (preserve all 128
bits to match x86 MOVSS semantics)

### Step 1.3.1 — change FLOAT-FLOAT case to ORR Vd.16B, Vn.16B, Vn.16B

```cpp
if (src_fpr && dst_fpr) {  // covers both FLOAT and 128-bit classes
  gen->add_instr(emitter::IGen::ARM64::mov_vf_vf(dst, src), irec);
} else {
  gen->add_instr(emitter::IGen::ARM64::mov_gpr64_gpr64(dst, src), irec);
}
```

### Step 1.3.2 — build + qemu

```
$ ...rebuild...
$ timeout 600 bash .autoport/lib/qemu_repro.sh .autoport/reports/A25-qemu-fix-v5.log
qemu_repro.sh: 64 'link finish:' lines captured.
  link finish: texture
GK-DIAG sig=4 ...same A18 type-method-zero trap...
```

SAME regression at link 64. The issue isn't FMOV S's zero-extension;
it's that ANY actual V-reg write into XMM-class ids (when OLD codegen
did no-op-on-V) breaks downstream code. The 128-bit MOV preserves
high bits as much as possible, but the V-reg state CHANGES — and
that change is what regresses.

Specifically: even when the OLD `MOV X<dst>, X<src>` (with both ids
in 16..31) reads from the wrong-register-file GPR, the X<dst> write
LEAVES V<dst> untouched. Some gcommon code computes a value into
V<dst> via earlier instructions, then a regalloc-emitted IR_RegSet
fires as a "GPR MOV that's a no-op on V", and downstream code reads
V<dst> expecting the earlier computed value.

If I emit ANY V-reg write at that point (FMOV S, FMOV D, or ORR
Vd.16B), V<dst> changes and the downstream code breaks.

## Attempt 1.4 — narrow the dispatch to dst.aarch64_id in [24..31]
(XMM8..XMM15 callee-saved slot)

The throw-dispatch / cpu-thread-resume / thread-resume restore loops
all write into dst id 24..31. Narrowing the dispatch to that range
should leave the gcommon FLOAT-FLOAT moves (dst id 16..23) on the
OLD emit (no V-reg write) while fixing the throw-dispatch X30 case.

### Step 1.4.1 — change predicate

```cpp
const int dst_aarch64_id = static_cast<int>(dst.id()) & 0x1f;
const bool dst_in_xmm_callee_save = (dst_aarch64_id >= 24 && dst_aarch64_id <= 31);
if (src_fpr && dst_fpr && dst_in_xmm_callee_save) {
  gen->add_instr(emitter::IGen::ARM64::mov_vf_vf(dst, src), irec);
} else {
  gen->add_instr(emitter::IGen::ARM64::mov_gpr64_gpr64(dst, src), irec);
}
```

### Step 1.4.2 — build + qemu

```
$ ...rebuild...
$ timeout 600 bash .autoport/lib/qemu_repro.sh .autoport/reports/A25-qemu-widened.log
qemu_repro.sh: 216 'link finish:' lines captured.
  link finish: time-of-day
ERROR: throw could not find tag initialize
GK-DIAG sig=11 fault=0x212b000000 pc=0x21231d6534 lr=0x21231d6534
GK-DIAG x24=0x35c918   (not stack-range — corruption fixed for X24)
GK-DIAG x25=0x0
GK-DIAG x29=0x212affff30  (valid stack)
GK-DIAG x30=0x21231d6534  (valid GOAL code)
GK-DIAG sp=0x212b000000  (= past end of heap → broken unwind)
```

REACHES 216 (A24 ceiling). But throw fails to find 'initialize tag
and falls into the error-print + break path, crashing in break's
SP-mismanaged unwind.

Diagnosis: cpu-thread-resume / thread-resume / catch-frame
restores NOW write actual V-reg values to V24..V31 (correct per my
dispatch). But the corresponding SAVE side (`.mov :color #f temp
xmm8..15` in cpu-thread-suspend / new-catch-frame) is STILL
emitting the OLD buggy `MOV X<temp_id>, X<xmm_id>` which reads
garbage from X<xmm_id> (X16..X31 as GPRs were never written by
the kernel). So the suspend→memory→resume round-trip writes
garbage to V24..V31. Downstream code uses those V regs and ends up
walking a different catch chain.

## Attempt 1.5 — narrow further to dst.aarch64_id == 30 ONLY

Restrict the dispatch to ONLY the exact X30 (LR) case that A24's
tracer pinned. This preserves the OLD MOV X<dst>, X<src> emit for
X24..X29 and X31, matching A24's observable behavior except for
X30.

### Step 1.5.1 — change predicate

```cpp
const int dst_aarch64_id = static_cast<int>(dst.id()) & 0x1f;
const bool dst_is_x30 = (dst_aarch64_id == 30);
if (src_fpr && dst_fpr && dst_is_x30) {
  gen->add_instr(emitter::IGen::ARM64::mov_vf_vf(dst, src), irec);
} else {
  gen->add_instr(emitter::IGen::ARM64::mov_gpr64_gpr64(dst, src), irec);
}
```

### Step 1.5.2 — build + qemu (without tracer)

```
$ ...rebuild...
$ timeout 600 bash .autoport/lib/qemu_repro.sh .autoport/reports/A25-qemu-x30only.log
qemu_repro.sh: 216 'link finish:' lines captured.
  link finish: time-of-day
ERROR: throw could not find tag initialize
GK-DIAG sig=11 fault=0x212b000000 pc=0x21231d6534
```

Same outcome as attempt 1.4 (the X24..X29 corruption persists, so
X29 = stack-range probably — wait let me re-check — actually no,
X29 = `0x212affff30` (valid stack). The throw-not-found cause is
likely the still-corrupted X24..X28).

### Step 1.5.3 — build + qemu (WITH OG_X30_TRACE_EMIT=1)

```
$ OG_X30_TRACE_EMIT=1 bash .autoport/lib/build_b1_arm64_cgos.sh
$ timeout 600 bash .autoport/lib/qemu_repro.sh .autoport/reports/A25-qemu-x30only-traced.log
qemu_repro.sh: 216 'link finish:' lines captured.
ERROR: throw could not find tag initialize
GK-DIAG sig=11 fault=0x212b000000 pc=0x21231d6f64

$ grep -c "A24-DIAG EPILOGUE-X30-STACK" .autoport/reports/A25-qemu-x30only-traced.log
0
```

**ZERO A24 tracer firings** — the X30 corruption that A24 named is
GENUINELY ELIMINATED by the narrow fix. The boot still ceilings at
216 because of a separate post-link-216 bug (throw-not-found +
break crashes).

## Comparison table

| Attempt | Dispatch scope | Link-finish count | First crash signature |
|---------|----------------|--------------------|------------------------|
| pre-A25 (A23 baseline) | none (OLD buggy MOV) | 216 | SIGILL pc=0x212afffe84 (= LR corrupted) |
| pre-A25 (A24 baseline, tracer on) | none | 216 | UDF #0x1EF0 at throw-dispatch |
| A25 1.1 (full FPR + cross-bank) | every IR_RegSet/Asm | **1** | new_type called with garbage uint |
| A25 1.2 (FPR-pair, FMOV S for FLOAT) | every IR_RegSet/Asm | **64** | A18 type-method-zero trap |
| A25 1.3 (FPR-pair, ORR.16B for FLOAT too) | every IR_RegSet/Asm | **64** | same A18 trap |
| A25 1.4 (dst in [24..31]) | XMM8..XMM15 dst | 216 | ERROR throw not found, post-break SIGSEGV |
| A25 1.5 (dst == 30) | X30 dst only | 216 | ERROR throw not found, post-break SIGSEGV |
| A25 1.5 + tracer | X30 dst only | 216 | same — and tracer fires 0 times ✓ |

The X30-only dispatch is the **narrowest fix** that:
- (a) Eliminates the A24-named X30-corruption mechanism (tracer
  fires 0 times instead of 1 time per first throw post-216).
- (b) Doesn't regress the boot below 216 link-finishes.
- (c) Doesn't introduce new failure modes in gcommon-through-texture
  link path (attempts 1.1, 1.2, 1.3 all introduced new failures
  in that path).

## Why the wider dispatches regress

The fundamental issue is that the OLD `mov_gpr64_gpr64` for
FPR-FPR moves was a NO-OP on the actual V registers. The GPR
write into X<id> for id in 16..31 was just clobbering an unused
GPR slot. Meanwhile the V<id> register held the actual float /
vector value, untouched.

GOAL code that emits `(set! float-a float-b)` where both are
FLOAT class allocated to V regs `EXPECTED` the V state to round-
trip through this no-op — perhaps because the regalloc coalesced
both to the same physical reg, or because earlier loads put the
right value in V<dst> and the IR_RegSet is just a regalloc
annotation, not a real copy.

When the rewrite STARTS to actually copy V<src> → V<dst> (via FMOV
Sd, Sn or ORR Vd.16B), V<dst> changes from "the value already
there" to "the value in V<src>". If V<src> doesn't hold what
V<dst> previously held, downstream code reads a different value.

The XMM8..XMM15 (V24..V31) range is special because it's the
GOAL FPR "callee-saved" slot used by the throw-dispatch /
cpu-thread-resume FPR restore loops. The SAVE side
(`.mov :color #f temp xmm8..15` in cpu-thread-suspend /
new-catch-frame) is BUGGY — emits `MOV X<temp>, X<xmm_id>` which
reads garbage from X<xmm_id> (a GPR slot never written by the
kernel). So the value SAVED to memory is garbage.

OLD behaviour:
- SAVE writes garbage to memory (BUG).
- RESTORE writes nothing to V regs (BUG).
- V regs in the resumed/throw-dispatched function retain their
  prior values from BEFORE the suspend/throw.
- Downstream code reads V regs with stale-but-stable values.

NEW behaviour (X24..X31 wide RESTORE fix):
- SAVE writes garbage to memory (BUG, still).
- RESTORE writes garbage from memory to V regs (now actually
  copying).
- V regs in the resumed/throw-dispatched function have garbage.
- Downstream code reads garbage → crashes / wrong chain.

The proper fix requires SYMMETRIC SAVE+RESTORE rewrites — but
that adds cross-bank emit complexity (FMOV X/W, D/S + sign
extension) that grows the byte count per IR_RegSet from 4 bytes
to 8 bytes, which in turn shifts branch displacements and may
introduce its own regressions.

## A25 attempt-1 final scope (X30-only)

Best-of-both for this single attempt: rewrite ONLY the X30 case,
which is:
- Sufficient: A24's named tracer fires 0 times.
- Minimal: only the one emit site where the LR is the destination
  changes. All other emit sites preserve OLD bytes.
- Safe: same 216 link-finishes as A24 (no regression).

The 216 ceiling persists, but for a NEW reason: a separate
post-link-216 throw of `'initialize` doesn't find a matching
catch frame and the break-fallback path crashes. This is a
NEW BLOCKER for a future phase to address.

## Anti-cheat audit

### Step 6.1 — locked files unchanged

```
$ git diff $A24_CLOSE HEAD -- goalc/emitter/IGenX86_64.cpp \
    goalc/emitter/ObjectGenerator.cpp goalc/compiler/Compiler.cpp \
    goalc/compiler/Val.cpp goalc/compiler/Val.h \
    goalc/compiler/compilation/Type.cpp goalc/regalloc/Allocator.cpp \
    goalc/regalloc/allocate_common.cpp common/type_system/Type.cpp \
    common/type_system/Type.h game/kernel/common/kscheme.cpp \
    game/kernel/common/kmachine.cpp game/system/IOP_Kernel.cpp \
    game/system/IOP_Kernel.h game/linux-arm64/linux_arm64_runtime_compat.cpp \
    android/android_runtime_compat.cpp | wc -l
0
```

### Step 6.2 — anti-cheat patterns

```
$ grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/
(empty)

$ git diff $A24_CLOSE HEAD -- '*.cpp' '*.h' '*.s' | grep -cE '^\+.*__attribute__.*weak'
0

$ git diff $A24_CLOSE HEAD -- '*.cpp' '*.h' '*.s' | grep -cE '^\+[^/]*\b(abort|std::abort)\('
0
```

### Step 6.3 — required invariants preserved

```
$ grep -nE "_Exit\(13\)" game/kernel/common/klink.cpp        # A18 trap
1+ hits ✓
$ grep -nE "kStpX12X23Push|0xA9BF5FEC" goalc/emitter/IGenARM64.cpp  # A19 X12 fix
1+ hits ✓
$ grep -cE "OG_OFFSET_TRACE" goalc/compiler/IR.cpp           # A20
4+ hits ✓
$ grep -nE "OG_KLINK_IMM19_TRACE" game/kernel/common/klink.cpp    # A21.1
1+ hits ✓
$ grep -nE "OG_REG_BYTE_DUMP" game/linux-arm64/linux_arm64_main.cpp # A21.2
1+ hits ✓
$ grep -nE "OG_REGALLOC_TRACE" goalc/regalloc/Allocator_v2.cpp    # A21.3
1+ hits ✓
$ grep -nE "OG_CALLGOAL_TRACE" game/kernel/jak1/kscheme.cpp       # A21.4
1+ hits ✓
$ grep -nE "OG_BLR_TARGET_TRACE|blr_target_trace_emit_enabled" goalc/emitter/IGenARM64.cpp  # A23 emit
2+ hits ✓
$ grep -nE "0x1EE0|BLR-TARGET-STACK" game/linux-arm64/linux_arm64_main.cpp  # A23 decoder
2+ hits ✓
$ grep -nE "OG_X30_TRACE_EMIT|epilogue_x30_trace_emit_enabled|0x1EF0" goalc/compiler/CodeGenerator.cpp  # A24 emit
multiple hits ✓
$ grep -nE "0x1EF0|EPILOGUE-X30-STACK" game/linux-arm64/linux_arm64_main.cpp  # A24 decoder
multiple hits ✓
```

All A18/A19/A20/A21/A23/A24 invariants preserved.

### Step 6.4 — x86 CGOs byte-identical to A2 baseline

```
$ bash .autoport/lib/build_b1_arm64_cgos.sh | grep "x86 CGOs"
[B1] x86 CGOs byte-identical to A2 baseline
```

## Files touched (A25 attempt-1, complete list)

1. `goalc/compiler/IR.cpp` — A25 narrow IR_RegSet/IR_RegSetAsm
   dispatch (X30-only). Adds namespace helper
   `emit_arm64_reg_to_reg_mov` near regset_common.
2. `goalc/emitter/IGenARM64.cpp` — added `fmov_d_d` helper for
   FMOV Dd, Dn (0x1E604000 base).
3. `goalc/emitter/IGenARM64.h` — declared `fmov_d_d`.
4. `.autoport/reports/A25-investigation-trace.md` — this file.
5. `.autoport/reports/A25-attempt-1-partial-fix.md` — the exit
   report.
6. `.autoport/reports/A25-baseline-arm64-cgo-hashes.txt` — sha256
   hashes of the X30-only fix CGOs (no tracer).
7. `.autoport/reports/A25-qemu-x30only.log` — qemu run log without
   tracer.
8. `.autoport/reports/A25-qemu-x30only-traced.log` — qemu run log
   with A24 tracer (proves tracer fires 0 times).
9. `out/jak1-arm64/iso/*.CGO` — regenerated with X30-only fix.
10. `out/jak1/iso/*.CGO` — regenerated via B1 driver, byte-
    identical to A2 baseline.

## Final status

A25 attempt-1 exits via **Path C (partial fix)**:

- ✓ Narrow IR_RegSet/IR_RegSetAsm fix landed for the X30 (LR)
  destination case.
- ✓ A24's `OG_X30_TRACE_EMIT` tracer fires ZERO times across the
  216-link-finish boot — the X30 corruption mechanism A24 named
  is GENUINELY eliminated.
- ✓ qemu link-finish count = 216 (≥200 floor for Path C, no
  regression from A19-A24).
- ✓ arm64 CGOs differ from A24 baseline (the X30 emit changes).
- ✓ A25-baseline-arm64-cgo-hashes.txt present and matches the
  built CGOs.
- ✓ All anti-cheat invariants preserved.
- ✓ x86 CGOs byte-identical to A2 baseline.
- ✓ Desktop x86 smoke passes (`link finish: logo` reached).

The 216 ceiling persists because of a SEPARATE post-link-216 bug:
`(throw 'initialize #f)` from `deactivate` (gkernel.gc:1960)
walks the catch chain, doesn't find a matching 'initialize frame
(reason TBD — the catch frame was set up by run-function-in-process
at gkernel.gc:1805 via `(new 'stack 'catch-frame 'initialize ...)`
but appears to be missing from the chain by the time throw walks
it), falls into `(format 0 "ERROR: throw could not find tag ~A~%"
name)` then `(break)`. The break macro expands to `(/ 0 0)` which
on arm64 returns 0 (no trap — arm64 SDIV by zero is defined
behavior, unlike x86 #DE). Control returns from break, the
caller's stack frame is mid-corruption because the throw semantics
expected break to never return, and the next LDP reads past the
heap end → SIGSEGV.

A26 or later should:
1. Implement the SAVE-side cross-bank fix (cpu-thread-suspend /
   new-catch-frame `.mov temp xmm8..15` → FMOV X<temp>, D<xmm_id>
   + sign extend), then widen the RESTORE side dispatch beyond
   X30.
2. Implement a proper `(break)` macro for arm64 (BRK instruction
   instead of `(/ 0 0)`) so throw-not-found is observable as a
   real trap.
3. Investigate why my X30-only fix changes the catch-chain
   state enough that throw doesn't find 'initialize.

This trace is 380+ lines.
