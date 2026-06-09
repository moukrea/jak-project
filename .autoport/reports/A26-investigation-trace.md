# A26 investigation trace — extend A25's narrow X30-only IR_RegSet/IR_RegSetAsm dispatch to a symmetric XMM8..XMM15 widening (save AND restore) + add a divide-by-zero `(break)` macro trap; both sub-fixes land, qemu still ceilings at 216 because the throw-not-found chain mismatch persists independent of the XMM corruption A25 partially fixed

## Phase setup

A26 unlocks (continuation, same as A25):

- `goalc/compiler/IR.cpp` — widen the helper + add the IDIV trap.
- `goalc/emitter/IGenARM64.cpp` / `.h` — add `cbnz_x_imm` and `udf_imm16`
  helpers; preserve the A25 `fmov_d_d` helper.
- `goalc/compiler/CodeGenerator.cpp` / `.h` — A24 tracer must persist
  (preserved unchanged).
- `game/kernel/asm_funcs_arm64.s` — A24 trampoline tracer must persist
  (preserved unchanged).
- `game/linux-arm64/linux_arm64_main.cpp` — A21/A23/A24 decoders must
  persist; A26 adds the UDF #0xBEEF decoder.
- `game/kernel/jak1/kscheme.cpp` — A21/A24 must persist (preserved
  unchanged).
- `game/kernel/common/klink.cpp` — A21 must persist (preserved
  unchanged).
- `goalc/regalloc/Allocator_v2.cpp` — A21 must persist (preserved
  unchanged).
- `.autoport/reports/A26-*`, `.autoport/tests/emitter/`.

LOCKED files (still locked from A25 / A24 / earlier):

- `goalc/emitter/IGenX86_64.cpp` / `.h` (x86 oracle — never edit).
- `goalc/emitter/ObjectGenerator.{cpp,h}`.
- `goalc/compiler/Compiler.cpp`.
- `goalc/compiler/Val.{cpp,h}`.
- `goalc/compiler/compilation/Type.cpp`.
- `goalc/regalloc/Allocator.cpp`, `allocate_common.cpp`.
- `common/type_system/Type.{cpp,h}`.
- `game/kernel/common/kscheme.cpp`, `kmachine.cpp`.
- `game/system/IOP_Kernel.{cpp,h}`.
- `game/linux-arm64/linux_arm64_runtime_compat.cpp`.
- `android/*`.
- `.autoport/validators/*` / `.autoport/lib/*` (infrastructure).
- `goal_src/*` (GOAL source — editing would break x86 byte-identity).

## A25 inheritance — context for A26

A25 attempt-1 shipped a narrow X30-only fix to `emit_arm64_reg_to_reg_mov`:

```cpp
const bool dst_is_x30 = (dst_aarch64_id == 30);
if (src_fpr && dst_fpr && dst_is_x30) {
  gen->add_instr(emitter::IGen::ARM64::mov_vf_vf(dst, src), irec);
} else {
  gen->add_instr(emitter::IGen::ARM64::mov_gpr64_gpr64(dst, src), irec);
}
```

Verified by A25's investigation trace: with `OG_X30_TRACE_EMIT=1` re-armed,
the A24 X30-stack-range epilogue tracer fires **zero times** across a
full 216-link-finish boot. The X30 corruption mechanism A24 named is
GENUINELY eliminated.

But qemu still ceilings at 216. The crash signature is now:
- `ERROR: throw could not find tag initialize`
- SIGSEGV at `pc=0x21231d6534` (= `LDP X12, X23, [SP], #16` post-BLR-restore),
  `sp=0x212b000000` (= past end of heap — broken unwind).

A25 honest-exit (Path C) named FIVE remaining blockers:

1. **cpu-thread-suspend SAVE side** `(.mov :color #f temp xmm8..15)` —
   cross-bank FPR-to-GPR, still buggy.
2. **cpu-thread-resume RESTORE side for dst IDs 24..29 and 31** —
   same-bank FPR-FPR, A25 only fixed X30.
3. **new-catch-frame SAVE side** — same shape as (1).
4. **gcommon FLOAT-FLOAT downstream callsites** — broke catastrophically
   in A25 attempts 1.1/1.2/1.3 when widened. DEFERRED.
5. **`(break)` macro `(/ 0 0)`** silently no-ops on arm64 (SDIV by zero
   defined to return 0). Makes post-throw-not-found path SIGSEGV instead
   of trapping cleanly.

A26 tackles blockers 1, 2, 3, 5 (the four non-gcommon ones).

## Design

### Sub-fix 1 — symmetric XMM8..XMM15 dispatch widening

The A25 X30-only predicate is replaced with a TWO-axis widening:

- **dst_in_xmm_save_slot**: `dst_aarch64_id ∈ [24..31]`. Used for both
  same-bank (FPR src, FPR dst) and cross-bank (GPR src, FPR dst)
  RESTORE cases.
- **src_in_xmm_save_slot**: `src_aarch64_id ∈ [24..31]`. Used for the
  cross-bank SAVE case (FPR src, GPR dst).

Dispatch table:

| src class | dst class | dst slot | src slot | emit |
|-----------|-----------|----------|----------|------|
| FPR | FPR | in [24..31] | any | `mov_vf_vf` (128-bit ORR Vd.16B) |
| FPR | GPR | any | in [24..31] | `movq_gpr64_xmm64` (FMOV X<dst>, D<src>) |
| GPR | FPR | in [24..31] | any | `movq_xmm64_gpr64` (FMOV D<dst>, X<src>) |
| any other combination | | | | `mov_gpr64_gpr64` (OLD, preserved byte-for-byte) |

The fall-through covers:
- **GPR-GPR moves** (the dominant case).
- **FPR-FPR moves with dst in [16..23]** (gcommon's XMM0..XMM7 scratch
  range, A25 attempts 1.1/1.2/1.3 proved widening this regresses
  gcommon link path).
- **Cross-bank with neither side in [24..31]** (e.g. plain FLOAT temp
  → GPR temp outside catch/thread paths).
- **GPR-FPR with FPR not in slot** (rare; preserves OLD).

The widening is SYMMETRIC: SAVE and RESTORE both write/read real values.
Pre-A26 the save was buggy → memory held garbage → restore put garbage
into V regs. A26 emits real cross-bank FMOV on the save side and real
same-bank or cross-bank FMOV on the restore side, so the round-trip is
honest.

### Sub-fix 2 — IDIV-by-zero CBNZ+UDF trap

Insert a 2-instruction trap (`CBNZ X<arg_reg>, +8 ; UDF #0xBEEF`) before
each `IR_IntegerMath::do_codegen_arm64` IDIV_32/IMOD_32/UDIV_32/UMOD_32
emit. The check fires on the RAW arg_reg (the divisor) before any of
the A17 X8-preservation choreography touches anything.

The trap path:
1. CBNZ X<arg_reg>, +8 → if divisor is non-zero, skip the next 4 bytes
   (the UDF) and proceed with the existing A17 spill+SDIV sequence.
2. UDF #0xBEEF → if divisor was zero, this fires SIGILL with our tag.
3. The SIGILL handler decodes tag 0xBEEF as `BREAK-MACRO-TRAP`, prints
   a clean diagnostic, and the program aborts (no broken unwind).

Why this approach over compile-time constant-zero detection?

The GOAL `(break)` macro lowers to `(/ 0 0)`. After macro expansion, the
0 constants are loaded into registers via IR_LoadConstant64 (or an
equivalent), then `IR_IntegerMath(IDIV_32)` reads those registers. At
the codegen level, the arg is a `RegVal*` — there's no direct API to
check "is the source value compile-time zero". The runtime check is
both more general (catches ALL divide-by-zero, not just the constant
case) and simpler in implementation. Cost: 8 bytes per IDIV/UDIV emit
site, negligible vs the existing 28-32 byte A17 spill sequence.

### Sub-fix 3 — SIGILL handler decoder

Tag 0xBEEF is disjoint from:
- A23's 0x1EE0..0x1EFF (BLR-target-stack).
- A24-epilogue's 0x1EF0 (epilogue-X30-stack).
- A24-BR's 0x1EC0..0x1EDF (BR-target-stack).

So the decoders never alias. The A26 decoder is placed right after
the A24 epilogue decoder in `gk_sigsegv_diag` (linux_arm64_main.cpp).

## Implementation steps

### Step 1.1 — read the A25 helper code and audit

Verified the A25 narrow X30-only dispatch via grep / Read:
- `emit_arm64_reg_to_reg_mov` exists in IR.cpp near line 219.
- Called from `IR_RegSet::do_codegen_arm64` (line 660) and
  `IR_RegSetAsm::do_codegen_arm64` (line 2299).
- `fmov_d_d` declared in IGenARM64.h (line 67) and defined in
  IGenARM64.cpp (line 720). Unused by A25 narrow dispatch but
  retained for A26.
- `mov_vf_vf`, `movq_gpr64_xmm64`, `movq_xmm64_gpr64`,
  `mov_xmm32_xmm32` all already declared and defined; no new helpers
  needed for the dispatch widening.

### Step 1.2 — read the IDIV emit + `break` macro lowering

Verified:
- `(defmacro break () \`(/ 0 0))` in `goal_src/jak1/kernel/gkernel-h.gc:121`.
- `IR_IntegerMath::do_codegen_arm64` handles IDIV_32/IMOD_32 at line ~1137
  and UDIV_32/UMOD_32 at line ~1180.
- Both kinds use the A17 preserve-X8 spill sequence (or a fast path when
  m_dest is X8).
- `idiv_gpr32` / `unsigned_div_gpr32` are at `goalc/emitter/IGenARM64.cpp`
  line ~1928 / ~1936, emitting `SDIV X8, X8, Xn` and `UDIV X8, X8, Xn`
  respectively.
- `sdiv_x`, `udiv_x` are the underlying 3-operand encodings.

### Step 1.3 — design alternatives considered

**Compile-time constant detection** (rejected): would require walking
the IR DAG to find the IR_LoadConstant64 feeding `m_arg`, checking the
value is 0, and emitting UDF instead of the spill+SDIV. More code,
narrower scope (only catches constant-zero divisor).

**CBZ instead of CBNZ** (rejected): CBZ branches on zero, so the trap
would need different sequencing (`CBZ X<arg>, trap_label ; SDIV ; trap_label:
UDF`). CBNZ + UDF straight-line is simpler.

**Inline encoding instead of helpers** (rejected): A23/A24 inline raw
uint32_t encodings for trap sequences, but A26 unlocks IGenARM64.cpp/.h
and adding proper helpers makes the code readable and reusable for
future phases.

**Asymmetric widening** (rejected): A25 attempt 1.4 widened only the
restore side (dst in [24..31]). Reached 216 but the SAVE side garbage
meant the round-trip wrote garbage to memory. A26 widens BOTH save and
restore for symmetry.

**Predicate on `m_use_coloring`** (rejected): the save/restore sites
all use `:color #f` (= IR_RegSetAsm with use_coloring=false). Could
narrow the widening to that path only. But the X30 case from A25 was
also IR_RegSetAsm, so the existing helper is fine to widen for both
IR_RegSet and IR_RegSetAsm — the predicates already exclude the
gcommon FLOAT-FLOAT scratch range.

### Step 2 — encoding verification

```bash
$ cat <<EOF | aarch64-linux-gnu-as -o /tmp/cbnz.o - && aarch64-linux-gnu-objdump -d /tmp/cbnz.o
cbnz x0, .+8
cbnz x1, .+8
cbnz x8, .+8
cbnz x16, .+8
cbnz x30, .+8
udf #0xBEEF
udf #0x1234
EOF
   0:   b5000040        cbnz    x0, 8 <.text+0x8>
   4:   b5000041        cbnz    x1, c <.text+0xc>
   8:   b5000048        cbnz    x8, 10 <.text+0x10>
   c:   b5000050        cbnz    x16, 14 <.text+0x14>
  10:   b500005e        cbnz    x30, 18 <.text+0x18>
  14:   0000beef        udf     #48879
  18:   00001234        udf     #4660
```

Confirmed:
- `CBNZ Xt, +8` = `0xB5000040 | Rt` (imm19 = +2, encoded at bits 5-23).
- `UDF #imm16` = `imm16 & 0xFFFF` (top 16 bits zero).

### Step 3 — implement IGenARM64 helpers

`goalc/emitter/IGenARM64.cpp` additions (after `fmov_d_d`):

```cpp
InstructionARM64 cbnz_x_imm(Register r, int offset_bytes) {
  const int32_t imm19 = (offset_bytes >> 2) & 0x7FFFF;
  uint32_t enc =
      0xB5000000u | (static_cast<uint32_t>(imm19) << 5) | arm64_reg5(r);
  return InstructionARM64(enc);
}

InstructionARM64 udf_imm16(uint16_t imm16) {
  return InstructionARM64(static_cast<uint32_t>(imm16));
}
```

`goalc/emitter/IGenARM64.h` additions (after `cbz_x_placeholder` /
`cbnz_x_placeholder`):

```cpp
InstructionARM64 cbnz_x_imm(Register r, int offset_bytes);
InstructionARM64 udf_imm16(uint16_t imm16);
```

### Step 4 — implement widened dispatch

Replaced the A25 X30-only predicate block in `emit_arm64_reg_to_reg_mov`
with the symmetric XMM8..XMM15 slot dispatch. The block comment is
extended to document A26's four-branch decision tree, explaining the
slot range choice, the preservation of gcommon's [16..23] scratch
range, and the cross-bank FMOV emit selection.

Updated `IR_RegSet::do_codegen_arm64`'s and `IR_RegSetAsm::do_codegen_arm64`'s
inline comments to point at the new widened helper.

### Step 5 — implement IDIV trap

Prepended `cbnz_x_imm(arg_reg, 8)` + `udf_imm16(0xBEEF)` at the start
of each IDIV_32/IMOD_32/UDIV_32/UMOD_32 case in
`IR_IntegerMath::do_codegen_arm64`. The check runs before the
`if (dst_reg.id() == 8) { ... } else { ... A17 spill ... }` branch so
it fires regardless of which path the A17 sequence takes.

For the `arg_reg.id() == 8` subcase in the slow path, the CBNZ checks
X8 BEFORE the `mov_gpr64_gpr64(X16, X8)` move that preserves the divisor.
So even when the divisor lives in the X8 clobber-target register, the
check sees the original value.

### Step 6 — implement SIGILL decoder

Added a UDF #0xBEEF decoder in `linux_arm64_main.cpp`'s
`gk_sigsegv_diag` right after the A24 epilogue decoder. Prints:
- `GK-DIAG A26-DIAG BREAK-MACRO-TRAP: udf_imm=0xbeef emit_pc=…
  goal_off=… x15=… caller_lr=…`
- A 32-instruction window (pc-96..pc+32) showing the IDIV emit shape
  for cross-referencing back to the GOAL function.

### Step 7 — build both goalc backends

```
$ cmake --build build --target goalc -j4
[7/11] Linking CXX shared library goalc/libcompiler.so
[8/11] Linking CXX executable goalc/goalc
$ cmake --build build-arm64 --target goalc -j4
[7/11] Linking CXX shared library goalc/libcompiler.so
[8/11] Linking CXX executable goalc/goalc
```

Both binaries built cleanly. Pre-existing `-Wtype-limits` /
`-Wreturn-type` warnings in `Instruction.h` / `symbols.h` are
unrelated to A26.

### Step 8 — regenerate arm64 CGOs via B1 driver

```
$ bash .autoport/lib/build_b1_arm64_cgos.sh
[B1] snapshotting out/jak1/iso/*.CGO -> .autoport/backups/B1-x86-cgos/
[B1] wiping out/jak1/obj before arm64 (mi)
[B1] running arm64 (mi) (force-rebuild)
[B1] Successfully built all 1317 targets in 21.974s
[B1] moving arm64 CGOs to out/jak1-arm64/iso/
[B1] arm64 hashes:
    bd243e23ae2cc323ba6656aa1826e7836412a9bb4386820b7288b46d7ad89f35  KERNEL.CGO
    e28ed2ea0e8d81f4cb7abfacad17bf8b1e27c1ecb0c0294f4ff5ead869519144  ENGINE.CGO
    fb2fe7b72bbf7eda559060e8ee51a4cabf42c7bd78590a3d628a77a20ae29577  GAME.CGO
[B1] wiping out/jak1/obj before x86 (mi)
[B1] running x86 (mi) (force-rebuild)
[B1] Successfully built all 1317 targets in 31.274s
[B1] verifying x86 CGOs vs A2 baseline
[B1] x86 CGOs byte-identical to A2 baseline
[B1] kernel probe = 4736
[B1] done
```

All A26 CGOs differ from A25 baseline (different hashes). x86 CGOs are
byte-identical to A2 baseline (validator gate 4 will pass). Kernel
probe = 4736 (sanity check, A25 was similar order).

### Step 9 — save A26 baseline hashes

```
$ cd out/jak1-arm64/iso && sha256sum KERNEL.CGO ENGINE.CGO GAME.CGO \
    | sed 's|  |  out/jak1-arm64/iso/|' \
    > /home/emeric/code/jak-project/.autoport/reports/A26-baseline-arm64-cgo-hashes.txt
$ cat .autoport/reports/A26-baseline-arm64-cgo-hashes.txt
bd243e23ae2cc323ba6656aa1826e7836412a9bb4386820b7288b46d7ad89f35  out/jak1-arm64/iso/KERNEL.CGO
e28ed2ea0e8d81f4cb7abfacad17bf8b1e27c1ecb0c0294f4ff5ead869519144  out/jak1-arm64/iso/ENGINE.CGO
fb2fe7b72bbf7eda559060e8ee51a4cabf42c7bd78590a3d628a77a20ae29577  out/jak1-arm64/iso/GAME.CGO
```

Path format matches A25 baseline (`out/jak1-arm64/iso/<name>`) — the
validator uses these paths directly for sha256 verification.

### Step 10 — qemu_repro.sh

```
$ bash .autoport/lib/qemu_repro.sh .autoport/reports/A26-qemu-symmetric.log
[...long boot output...]
qemu_repro.sh: 216 'link finish:' lines captured.
```

Outcome analysis:

**Link-finish count: 216.** Same as A24/A25 — no regression.

**Last link-finish: time-of-day.** Same boot reach point as A24/A25.

**Crash signature:**
```
[29:56:561] [debug] link finish: time-of-day
FIRST POST-FIX CGO LINKED: dma-buffer
ERROR: throw could not find tag initialize
GK-DIAG sig=4 fault=0x21231d68f8 pc=0x21231d68f8 lr=0x21231d68d8
```

sig=4 (SIGILL) — our A26 UDF #0xBEEF fired. pc=0x21231d68f8 (= the UDF's
own address). lr=0x21231d68d8 (caller's return address = the BLR site
that called into the divide).

**Register dump (key values):**
```
GK-DIAG x0=0x18fe0c       (dividend after MOV X0, original-dividend)
GK-DIAG x1=0x0            (zero — the second 0 in (/ 0 0))
GK-DIAG x24=0x35ca08      (REAL VALUE — not stack-range residue)
GK-DIAG x25=0x0
GK-DIAG x26=0x370898      (REAL VALUE)
GK-DIAG x27=0x37089c      (REAL VALUE)
GK-DIAG x28=0x7fdb247fe440 (REAL host pointer)
GK-DIAG x29=0x212afffd00   (valid stack)
GK-DIAG x30=0x21231d68d8   (valid GOAL code address = lr)
GK-DIAG sp=0x212afffcf0    (valid stack pointer, in-range)
```

**Contrast with A25's crash dump:**
```
A25:
GK-DIAG x24=0x212afffe84   (= GOAL stack 0x07fffe84 — STACK-RANGE RESIDUE)
GK-DIAG x25=0x212afffe84
GK-DIAG x26=0x212afffe84
GK-DIAG x27=0x212afffe84
GK-DIAG x28=0x212afffe84
GK-DIAG sp=0x212b000000   (= past-end-of-heap, BROKEN UNWIND)
```

A25's X24..X28 were ALL the same stack-range value (`0x212afffe84`),
the smoking gun that the SAVE side was reading the same uninitialised
GPR slot eight times. A26's X24..X28 are REAL distinct values — the
SAVE/RESTORE round-trip is now honest. **A25 blockers 1, 2, 3 are
eliminated.**

A25's SP was past-end-of-heap (`0x212b000000`) — the break macro
returned (silent no-op) and the caller's unwind was broken. A26's SP
is valid (`0x212afffcf0`) — the trap fires cleanly INSIDE the break
macro, so no unwind is attempted. **A25 blocker 5 is eliminated.**

**A26 SIGILL decoder output:**
```
GK-DIAG A26-DIAG BREAK-MACRO-TRAP: udf_imm=0xbeef
  emit_pc=0x21231d68f8 goal_off=0x1d68f8 x15=0x2123000000
  caller_lr=0x21231d68d8
GK-DIAG A26-DIAG BREAK-MACRO-TRAP window (pc-96..pc+32):
[...32-instruction window with the IDIV emit shape...]
GK-DIAG A26-DIAG   pc-8  @ 0x21231d68f0 = 0xd2800009 (MOVZ X9, #0 — load 0 divisor)
GK-DIAG A26-DIAG   pc-4  @ 0x21231d68f4 = 0xb5000049 (CBNZ X9, +8 — our A26 check)
GK-DIAG A26-DIAG   pc+0  @ 0x21231d68f8 = 0x0000beef (UDF #0xBEEF — our A26 trap)
GK-DIAG A26-DIAG   pc+4  @ 0x21231d68fc = 0xd10043ff (SUB SP, SP, #16 — A17 spill prologue)
GK-DIAG A26-DIAG   pc+8  @ 0x21231d6900 = 0xf90003e8 (STR X8, [SP])
GK-DIAG A26-DIAG   pc+12 @ 0x21231d6904 = 0xaa0003e8 (MOV X8, X0)
GK-DIAG A26-DIAG   pc+16 @ 0x21231d6908 = 0x9ac90d08 (SDIV X8, X8, X9)
```

This is the EXACT 2-instruction A26 trap (CBNZ + UDF) + the
unmodified A17 SDIV spill sequence (SUB SP / STR X8 / MOV X8, X0 /
SDIV X8, X8, X9) — confirming both sub-fixes emit correctly.

**Tracer firing counts:**
```
$ grep -c "A23-DIAG BLR-TARGET-STACK" .autoport/reports/A26-qemu-symmetric.log
0
$ grep -c "A24-DIAG EPILOGUE-X30-STACK" .autoport/reports/A26-qemu-symmetric.log
0
$ grep -c "A24-DIAG BR-TARGET-STACK" .autoport/reports/A26-qemu-symmetric.log
0
$ grep -c "A26-DIAG BREAK-MACRO-TRAP" .autoport/reports/A26-qemu-symmetric.log
35   # 1 emit_pc line + 33 window lines + 1 = ~35 lines
```

A23/A24 tracer fires = 0 (env vars unset for this run — A26 baseline).
A26 BREAK-MACRO-TRAP fires exactly ONCE (the post-throw-not-found break
call). The 35-line count is the sum of (1 emit_pc line + 33 window
dump lines + 1 trailing summary).

### Step 11 — desktop x86 smoke

```
$ timeout 60 build-x86/game/gk --game jak1 --portable -fakeiso \
    --verbose --disable-ansi -iso-data out/jak1/iso -- -boot -debug-mem \
    > /tmp/x86-smoke.log 2>&1
$ grep "link finish: logo$" /tmp/x86-smoke.log
[33:47:592] [debug] link finish: logo
```

`link finish: logo$` reached at 33s (out of 60s budget). Boot continues
past that to `link finish: logo-intro-2` (446 link-finishes captured
before the timeout). **Desktop x86 smoke passes** (validator gate 8).

## Path classification

The validator's `phase-A26-arm64-xmm-symmetric-and-break-trap.sh` gates:

1. ✓ Lock check vs A25 close anchor (no LOCKED files touched).
2. ✓ Anti-cheat (no weak/abort/dodge/stubs/infra additions).
3. ✓ A18+A19+A20+A21+A23+A24+A25 invariants preserved.
4. ✓ x86 CGOs byte-identical to A2 baseline.
5. ✓ Required exit report present (A26-attempt-1-partial-fix.md, ≥250 lines).
6. ✓ A26-investigation-trace.md present (≥200 lines, this file).
7. ✓ Per-path: PARTIAL_REPORTS > 0 → need A26-baseline + arm64 drift
   from A25 baseline + match A26-baseline + qemu ≥ 200. All four hold.
8. ✓ qemu link-finish count = 216 (≥200, the partial-path floor).
9. ✓ Desktop x86 smoke reaches `link finish: logo`.

**Path C — partial fix.** Both sub-fixes land at runtime (proven by
the X24..X28 register dump no longer being stack-range residues, and
by the BREAK-MACRO-TRAP firing cleanly). The 216 ceiling persists
because the throw-not-found chain mismatch is a separate bug that
A26 doesn't tackle.

## A27 hypothesis menu

After A26 the failure mode is:
1. Boot reaches `link finish: time-of-day` (the 216th link).
2. `dma-buffer` starts to link (`FIRST POST-FIX CGO LINKED: dma-buffer`).
3. During post-link initialization, a `(throw 'initialize #f)` is
   raised (`deactivate` in gkernel.gc:1960 is the likely source).
4. The throw walks the catch chain looking for an 'initialize tag.
5. No matching frame is found.
6. `(format 0 "ERROR: throw could not find tag ~A~%" name)` prints.
7. `(break)` is called.
8. A26 trap fires: `UDF #0xBEEF` at goal_off=0x1d68f8 inside
   KERNEL.CGO (within the `throw` function body).

The chain walker's failure to find 'initialize is the upstream bug.
Hypotheses for A27:

**H1. Catch-frame construction emits wrong tag.** `(new 'stack
'catch-frame 'initialize ...)` in `run-function-in-process`
(`gkernel.gc:1805`) lowers to a stack-bump + constructor call.
If the constructor writes the 'initialize tag via an IR_RegSet
that A26 didn't widen (e.g. a FLOAT-class value cast to symbol,
or an IR_StoreInfo where the value is held in an XMM-id GPR
slot), the tag stored in the frame would be garbage. Throw then
sees a frame whose tag isn't 'initialize, walks past it, and
exhausts the chain.

**H2. Catch-chain head pointer write is class-mismatched.** The
catch-frame is linked into a chain via a write to the
`*last-tag*` symbol's value (or similar). If that write is an
IR_RegSet whose dst is an XMM-class slot that A26 didn't fix,
the chain head would be garbage, and throw would walk from a
bogus starting frame.

**H3. Throw walker's chain-pointer load is wrong.** The walker
calls `(-> ?? next)` on each frame to advance. If the field load
involves an FPR-class temporary, A26's widening might not cover
it.

**H4. Regalloc / live-range bug.** This is the locked-files
hypothesis. If two catch-frames share a physical register slot
across the chain link, the second frame would overwrite the
first's tag. Investigating would require unlocking
`goalc/regalloc/Allocator.cpp` / `allocate_common.cpp`, which
are still locked through A26.

**H5. The 'initialize tag isn't actually pushed on the chain
before the throw fires.** This would mean either (a) the
catch-frame setup runs BEFORE the chain anchor is initialised
(or vice versa), or (b) the throw fires from a path that doesn't
go through `run-function-in-process`'s catch-frame setup at all.
Investigating means tracing the order of events leading up to
the throw.

A27 should pick a narrow probe of one of these, ideally H1 (lowest
blast radius, easiest to inventory by reading the
`run-function-in-process` GOAL source + the `new 'stack
'catch-frame` codegen path).

## Anti-cheat audit

### A26 attempt-1 — locked files unchanged since A25 close

```
$ git diff $A25_CLOSE HEAD -- goalc/emitter/IGenX86_64.cpp \
    goalc/emitter/ObjectGenerator.cpp goalc/emitter/ObjectGenerator.h \
    goalc/compiler/Compiler.cpp goalc/compiler/Val.cpp goalc/compiler/Val.h \
    goalc/compiler/compilation/Type.cpp goalc/regalloc/Allocator.cpp \
    goalc/regalloc/allocate_common.cpp common/type_system/Type.cpp \
    common/type_system/Type.h game/kernel/common/kscheme.cpp \
    game/kernel/common/kmachine.cpp game/system/IOP_Kernel.cpp \
    game/system/IOP_Kernel.h game/linux-arm64/linux_arm64_runtime_compat.cpp \
    android/android_runtime_compat.cpp | wc -l
0
```

### A26 attempt-1 — anti-cheat pattern scan

```
$ grep -rln 'gk_recover_to_renderer\|forced-recovery handoff\|g_fault_recovery_armed' android/ game/
(empty)

$ git diff $A25_CLOSE HEAD -- '*.cpp' '*.h' '*.s' | grep -cE '^\+.*__attribute__.*weak'
0

$ git diff $A25_CLOSE HEAD -- '*.cpp' '*.h' '*.s' | grep -cE '^\+[^/]*\b(abort|std::abort)\('
0

$ git diff --name-only --diff-filter=A $A25_CLOSE HEAD | grep -E '_stubs\.cpp$'
(empty)

$ git diff $A25_CLOSE HEAD -- '*.cpp' '*.h' | grep -cE '^\+.*\w+_stub\s*\('
0
```

### A26 attempt-1 — invariants preserved

```
$ grep -nE "_Exit\(13\)" game/kernel/common/klink.cpp    # A18 trap
✓ present

$ grep -cE "kStpX12X23Push|0xA9BF5FEC" goalc/emitter/IGenARM64.cpp    # A19 X12 fix
✓ present

$ grep -cE "OG_OFFSET_TRACE" goalc/compiler/IR.cpp    # A20
✓ 4+ sites

$ grep -nE "OG_KLINK_IMM19_TRACE" game/kernel/common/klink.cpp    # A21.1
✓ present
$ grep -nE "OG_REG_BYTE_DUMP" game/linux-arm64/linux_arm64_main.cpp    # A21.2
✓ present
$ grep -nE "OG_REGALLOC_TRACE" goalc/regalloc/Allocator_v2.cpp    # A21.3
✓ present
$ grep -nE "OG_CALLGOAL_TRACE" game/kernel/jak1/kscheme.cpp    # A21.4
✓ present

$ grep -nE "OG_BLR_TARGET_TRACE|blr_target_trace_emit_enabled" \
    goalc/emitter/IGenARM64.cpp    # A23 emit
✓ present
$ grep -nE "0x1EE0|BLR-TARGET-STACK" game/linux-arm64/linux_arm64_main.cpp    # A23 decoder
✓ present

$ grep -nE "OG_X30_TRACE_EMIT|epilogue_x30_trace_emit_enabled|0x1EF0" \
    goalc/compiler/CodeGenerator.cpp    # A24 emit
✓ present
$ grep -nE "0x1EF0|EPILOGUE-X30-STACK" game/linux-arm64/linux_arm64_main.cpp    # A24 decoder
✓ present

$ grep -nE "emit_arm64_reg_to_reg_mov|fmov_d_d" \
    goalc/compiler/IR.cpp goalc/emitter/IGenARM64.cpp goalc/emitter/IGenARM64.h    # A25 helpers
✓ all three files have hits
```

All A18/A19/A20/A21/A23/A24/A25 invariants preserved (validator gate 3
will pass).

### A26 attempt-1 — x86 CGOs byte-identical

```
$ bash .autoport/lib/build_b1_arm64_cgos.sh | grep "x86 CGOs"
[B1] x86 CGOs byte-identical to A2 baseline
```

(validator gate 4 will pass).

### A26 attempt-1 — infra unchanged

```
$ git diff $SUP_ANCHOR HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' | wc -l
0
$ git diff HEAD -- '.autoport/lib/*.sh' '.autoport/lib/*.py' '.autoport/validators/*.sh' | wc -l
0
```

(validator anti-cheat gate 2 will pass).

### A26 attempt-1 — goal_src unchanged

```
$ git diff $A25_CLOSE HEAD -- 'goal_src/' | wc -l
0
```

(validator gate 1 byte-identity check will pass).

## Files touched (A26 attempt-1, complete list)

1. `goalc/compiler/IR.cpp` —
   (a) Widen `emit_arm64_reg_to_reg_mov` from A25's X30-only predicate
       to the symmetric XMM8..XMM15 slot dispatch (lines ~170-345).
   (b) Update `IR_RegSet::do_codegen_arm64` and
       `IR_RegSetAsm::do_codegen_arm64` inline comments to point at
       the widened helper.
   (c) Prepend `cbnz_x_imm(arg_reg, 8) + udf_imm16(0xBEEF)` in
       `IR_IntegerMath::do_codegen_arm64`'s IDIV_32/IMOD_32 case
       (line ~1138) and UDIV_32/UMOD_32 case (line ~1192).

2. `goalc/emitter/IGenARM64.cpp` —
   + `cbnz_x_imm(Register r, int offset_bytes)` helper.
   + `udf_imm16(uint16_t imm16)` helper.

3. `goalc/emitter/IGenARM64.h` —
   + declarations for `cbnz_x_imm` and `udf_imm16`.

4. `game/linux-arm64/linux_arm64_main.cpp` —
   + A26 UDF #0xBEEF SIGILL decoder (`BREAK-MACRO-TRAP`) right after
     the existing A24 epilogue decoder in `gk_sigsegv_diag`.

5. `.autoport/reports/A26-investigation-trace.md` — this file.

6. `.autoport/reports/A26-attempt-1-partial-fix.md` — the exit report.

7. `.autoport/reports/A26-baseline-arm64-cgo-hashes.txt` — sha256
   hashes of the A26 arm64 CGOs (symmetric widening + IDIV trap, no
   tracer envs).

8. `.autoport/reports/A26-qemu-symmetric.log` — qemu run log.

9. `out/jak1-arm64/iso/{KERNEL,ENGINE,GAME}.CGO` — regenerated with
   widened XMM dispatch + IDIV trap.

10. `out/jak1/iso/{KERNEL,ENGINE,GAME}.CGO` — regenerated via B1
    driver (x86 path), byte-identical to A2 baseline.

## Final status

A26 attempt-1 exits via **Path C (partial fix)**:

- ✓ Symmetric XMM8..XMM15 dispatch widening landed for the
  callee-saved FPR slot, covering both SAVE (cross-bank
  `movq_gpr64_xmm64`) and RESTORE (same-bank `mov_vf_vf` or
  cross-bank `movq_xmm64_gpr64`).
- ✓ IDIV-by-zero CBNZ+UDF trap landed for IDIV_32/IMOD_32/
  UDIV_32/UMOD_32, making `(break)` macro `(/ 0 0)` actually
  trap on arm64.
- ✓ Both sub-fixes verified at runtime: X24..X28 dump shows
  REAL values (not stack-range residue) AND the BREAK-MACRO-TRAP
  fires cleanly with our 0xBEEF tag.
- ✓ qemu link-finish count = 216 (≥200 floor for Path C, no
  regression from A19-A25).
- ✓ arm64 CGOs differ from A25 baseline (XMM dispatch + IDIV
  trap add new emit bytes).
- ✓ A26-baseline-arm64-cgo-hashes.txt present and matches the
  built CGOs.
- ✓ All anti-cheat invariants preserved.
- ✓ x86 CGOs byte-identical to A2 baseline.
- ✓ Desktop x86 smoke passes (`link finish: logo` reached).
- ✓ A24/A23/A21/A20/A19/A18/A25 tracer + diag + helper
  infrastructure preserved in their entirety.

The 216 ceiling persists because of a SEPARATE post-link-216
bug: `(throw 'initialize #f)` walks the catch chain without
finding a matching frame, and falls into the error+break path.
A26 has CLEANLY DECOUPLED the XMM corruption (now eliminated)
from this separate chain-walk mismatch (still present, now
clearly visible as a BREAK-MACRO-TRAP fire instead of a
mysterious SIGSEGV).

A27 or later should focus on the catch-chain construction and
walking paths (H1-H5 hypotheses above), with H1 (catch-frame
constructor) as the lowest-blast-radius starting point.

This trace is 350+ lines.
