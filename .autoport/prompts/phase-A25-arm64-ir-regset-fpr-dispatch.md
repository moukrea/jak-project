# Phase A25 — arm64 IR_RegSet FPR/GPR dispatch fix + FMOV helpers (the actual fix landing phase)

## First step — read these

1. **`.autoport/reports/A24-attempt-1-bug-located-named-source.md` IN FULL.** This is the critical report. It contains:
   - The runtime tracer's positive fire event: `emit_pc=0x21231d713c`, `x30=0x212afffe84`, `goal_off=0x07fffe84`.
   - The annotated disasm window showing `MOV X30, X16` at pc-84 inside `throw-dispatch`.
   - The root cause: `IR_RegSet::do_codegen_arm64` (`goalc/compiler/IR.cpp:520-527`) unconditionally emits `mov_gpr64_gpr64` regardless of register class.
   - The shared `Register` enum mapping: XMM0..XMM15 have IDs 16..31, which `arm64_reg5()` maps to GPR IDs X16..X31. So `(.mov xmm14 src)` becomes `MOV X30, X(src_id)` — corrupting LR.
   - Why x86 boots: `regset_common` dispatches on class and emits `MOVQ XMM, XMM`.
   - Why the bug doesn't fire until link 217: `throw-dispatch` only runs on `(throw)`; boot reaches first throw post-`link finish: time-of-day`.
   - Other affected functions: `cpu-thread-resume`, `thread-suspend`, etc. (same `.mov xmm? temp-float` pattern).
2. `.autoport/reports/A24-investigation-trace.md` — full investigation path.
3. `goalc/compiler/IR.cpp:520-527` — `IR_RegSet::do_codegen_arm64`. The fix surface.
4. `goalc/compiler/IR.cpp` (search for `regset_common`) — the x86 dispatch pattern to mirror.
5. `goalc/emitter/IGenARM64.cpp` — existing emit helpers; need to add FMOV variants.
6. `goalc/emitter/Register.h` — register class definitions; `Register::is_xmm()` etc.

## Status

**Authored 2026-06-09 by the supervisor** after A24 attempt-1 located the root cause via Path C. **This is the FIRST true fix phase since A19** (which fixed the X12 clobber). 

Supervisor's pre-A25 reality checks (all PASS):
- A24 in completed, retries=1, fingerprint absent (clean single-attempt success).
- arm64 CGOs match A24-baseline-arm64-cgo-hashes.txt (sha256 verified).
- x86 CGOs byte-identical to A2 baseline.
- A18 trap `_Exit(13)` preserved, A19 X12 fix preserved (3 hits), A20 OG_OFFSET_TRACE preserved (6 sites), A23 tracer preserved (10 hits in IGenARM64.cpp, 6 in linux_arm64_main.cpp), A24 tracer infra in HEAD (epilogue + jmp_r64 + asm trampoline + inline trampoline + asm_funcs_arm64.s tracers).
- A24's report names a SPECIFIC emit_pc with arithmetic-verified evidence — diagnosis is unforgeable.

## The bug A25 must fix

`goalc/compiler/IR.cpp:520-527`:

```cpp
void IR_RegSet::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                 const AllocationResult& allocs,
                                 emitter::IR_Record irec) {
  auto dst = get_reg(m_dest, allocs, irec);
  auto src = get_reg(m_src, allocs, irec);
  // Always MOV (identity is harmless) — keeps the codegen body classifier-real.
  gen->add_instr(emitter::IGen::ARM64::mov_gpr64_gpr64(dst, src), irec);
}
```

This always emits `MOV X(dst.hw_id()), X(src.hw_id())`. The shared `Register` enum has GPRs at IDs 0-15 and XMMs at IDs 16-31. `arm64_reg5()` maps 1:1. So when GOAL author writes `(.mov xmm14 src)`, the codegen emits `MOV X30, X(src)` — corrupting LR.

The fix must dispatch on register class:

```cpp
void IR_RegSet::do_codegen_arm64(emitter::ObjectGenerator* gen,
                                 const AllocationResult& allocs,
                                 emitter::IR_Record irec) {
  auto dst = get_reg(m_dest, allocs, irec);
  auto src = get_reg(m_src, allocs, irec);
  if (dst.is_xmm() && src.is_xmm()) {
    gen->add_instr(emitter::IGen::ARM64::fmov_d_d(dst, src), irec);  // FMOV Dd, Dn
  } else if (dst.is_xmm() && !src.is_xmm()) {
    gen->add_instr(emitter::IGen::ARM64::fmov_d_x(dst, src), irec);  // FMOV Dn, Xd
  } else if (!dst.is_xmm() && src.is_xmm()) {
    gen->add_instr(emitter::IGen::ARM64::fmov_x_d(dst, src), irec);  // FMOV Xd, Dn
  } else {
    gen->add_instr(emitter::IGen::ARM64::mov_gpr64_gpr64(dst, src), irec);  // MOV Xd, Xn
  }
}
```

The dispatch shape mirrors x86's `regset_common`.

## FMOV helpers to add in IGenARM64.cpp

ARM64 FMOV encodings (see ARM ARM C7.2.143):

1. **FMOV Dd, Dn** (double-precision FPR-to-FPR move):
   - Encoding: `0x1E604000 | (Rn<<5) | Rd`
   - Operates on D-form registers (low 64 bits of V regs).

2. **FMOV Dn, Xd** (GPR-to-FPR move):
   - Encoding: `0x9E670000 | (Rn<<5) | Rd`
   - sf=1, type=01, mode=110 — 64-bit GPR to D.

3. **FMOV Xd, Dn** (FPR-to-GPR move):
   - Encoding: `0x9E660000 | (Rn<<5) | Rd`
   - sf=1, type=01, mode=110-inv — D to 64-bit GPR.

(There are also Sd variants — `FMOV Sd, Sn` for 32-bit float — that may need to be added for completeness. But the immediate fix only needs the 64-bit versions for `IR_RegSet`.)

**Cross-check the encodings** against `aarch64-linux-gnu-as` output:
```
echo "fmov d0, d1; fmov d0, x1; fmov x0, d1" | aarch64-linux-gnu-as -o /tmp/fmov.o -
aarch64-linux-gnu-objdump -d /tmp/fmov.o
```

Verify the bytes match before committing.

## What about IR_Return, IR_GetSymbolValueAsm, etc.?

A24's investigation noted that other IRs may also have the same bug (using `mov_gpr64_gpr64` unconditionally). A25 should audit them. Specifically:

- **`IR_Return::do_codegen_arm64`** — verify if it can be invoked with an XMM source.
- **`IR_GetSymbolValueAsm::do_codegen_arm64`** — verify.
- **`IR_LoadSymbolPointer::do_codegen_arm64`** — verify.
- **`IR_GetSymbolColor::do_codegen_arm64`** — verify.

If they have the same bug, fix them too. If not, document the audit in the fix-summary.

Other `.mov xmm? src` call sites in GOAL source (to verify the fix resolves them):
- `gkernel.gc:1531` `throw-dispatch` — the primary fix site.
- `gkernel.gc` (search for `.mov.*xmm`) — `cpu-thread-resume`, `cpu-thread-suspend` if present.
- `gkernel.gc` `new catch-frame` — uses XMM save pattern.

## Investigation/fix steps

1. **Read** the IR.cpp's `regset_common` (the x86 dispatch shape) and verify the proposed arm64 dispatch matches.

2. **Add FMOV helpers** to `IGenARM64.cpp` and `IGenARM64.h`. Cross-check encodings against `aarch64-linux-gnu-as` (recommended).

3. **Modify `IR_RegSet::do_codegen_arm64`** to dispatch on `Register::is_xmm()` for both operands.

4. **Audit other IRs** with `git grep -nE 'mov_gpr64_gpr64' goalc/compiler/`. For each, check if its source/dest registers can be XMM. Fix if needed.

5. **Build goalc** (both x86 and arm64).

6. **Regenerate arm64 CGOs** (env-gates UNSET — A24 tracer not needed for fix verification):
   ```
   bash .autoport/lib/build_b1_arm64_cgos.sh
   ```

7. **Verify x86 CGOs unchanged**: sha256sum out/jak1/iso/*.CGO must match A2 baseline.

8. **Verify arm64 CGOs differ from A24 baseline** (the fix changes emit):
   ```
   diff <(sha256sum out/jak1-arm64/iso/*.CGO) .autoport/reports/A24-baseline-arm64-cgo-hashes.txt
   ```

9. **Run qemu_repro.sh**. Expected outcome: **qemu link-finish count > 216** (real advance).

10. **Optional: re-run with `OG_X30_TRACE_EMIT=1`** (regenerate CGOs with that env set first) to verify no other epilogue X30 corruptions remain.

11. **Save A25-baseline-arm64-cgo-hashes.txt** with the new sha256 hashes.

12. **Write A25-fix-summary.md** (≥250 lines) and **A25-investigation-trace.md** (≥200 lines).

## Scope (locks)

**UNLOCKED for A25 (continuation):**

- `goalc/compiler/IR.cpp` — IR_RegSet fix + audit other IRs.
- `goalc/emitter/IGenARM64.cpp` / `.h` — add FMOV helpers.
- `goalc/compiler/CodeGenerator.cpp` / `.h` — A24's tracer must persist.
- `game/kernel/asm_funcs_arm64.s` — A24's trampoline tracer must persist.
- `game/linux-arm64/linux_arm64_main.cpp` — A21/A23/A24 decoders must persist.
- `game/kernel/jak1/kscheme.cpp` — A21 + A24 inline tracer must persist.
- `game/kernel/common/klink.cpp` — A21 diag must persist.
- `goalc/regalloc/Allocator_v2.cpp` — A21 diag must persist.
- `.autoport/reports/A25-*`, `.autoport/tests/emitter/`.

**STILL LOCKED:**

- `goalc/emitter/IGenX86_64.cpp` / `.h` — x86 oracle, NEVER edit.
- `goalc/emitter/ObjectGenerator.cpp` / `.h`.
- `goalc/compiler/Compiler.cpp`.
- `goalc/compiler/Val.cpp` / `.h` — A22+A23 cleared.
- `goalc/compiler/compilation/Type.cpp` — A22+A23 cleared.
- `goalc/regalloc/Allocator.cpp`, `allocate_common.cpp` — shared.
- `common/type_system/Type.cpp` / `.h`.
- `game/kernel/common/kscheme.cpp`, `kmachine.cpp`.
- `game/system/IOP_Kernel.cpp` / `.h`.
- `game/linux-arm64/linux_arm64_runtime_compat.cpp`.
- `android/*`.
- `.autoport/validators/*`, `.autoport/lib/*`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`.
- `.autoport/prompts/phase-*-*.md` except `phase-A25-*`.

## Anti-cheat invariants

- **x86 CGOs MUST be byte-identical to A2 baseline.** IR.cpp is SHARED; any edit that affects x86 emit breaks the regression check. Use `if (!dst.is_xmm() && !src.is_xmm())` to KEEP the existing x86 path (which is in `do_codegen_x86`, not `do_codegen_arm64`).
- **A18 trap body** `std::_Exit(13)` preserved.
- **A19 X12 fix** `kStpX12X23Push|0xA9BF5FEC` preserved.
- **A20 OG_OFFSET_TRACE** ≥4 sites preserved in IR.cpp.
- **A21 4 diags** preserved.
- **A23 tracer infrastructure** must persist in IGenARM64.cpp + linux_arm64_main.cpp.
- **A24 tracer infrastructure** must persist (epilogue check in CodeGenerator.cpp + UDF #0x1EF0 decoder in linux_arm64_main.cpp + any other A24-added tracers).
- 0 `__attribute__((weak))` / `abort()` / dodge / `_stubs.cpp` / inline `_stub(` / infra edits.

## Forbidden cheat patterns

### 1. Stub FMOV (always emits same encoding)

**Cheat fingerprint**: an FMOV helper that returns a constant byte sequence regardless of the operand registers.

**Why it's a cheat**: the helper must produce different encodings for different operand IDs. Otherwise it's a no-op.

**Honest version**: parameterize on `Rd` and `Rn`. Verify with hand-encoded test cases.

### 2. x86 emit changes via shared IR.cpp

**Cheat fingerprint**: the fix dispatches on register class in `do_codegen_x86` too, changing x86 output.

**Why it's a cheat**: x86 already works. The fix must be arm64-only.

**Honest version**: add the dispatch ONLY in `do_codegen_arm64`. Keep `do_codegen_x86` unchanged.

### 3. Wholesale rewrite of IR_RegSet

**Cheat fingerprint**: a diff that adds 100+ lines to `IR_RegSet`, changes its struct, etc.

**Why it's a cheat**: the fix is a 4-line dispatch + a few helper functions. Larger diffs indicate scope creep.

**Honest version**: minimal change. Add FMOV helpers + dispatch.

### 4. Removing A23/A24 tracer infrastructure

**Cheat fingerprint**: a diff that removes `blr_target_trace_emit_enabled`, `epilogue_x30_trace_emit_enabled`, or the SIGILL handler decoders.

**Why it's a cheat**: the tracers are permanent investigation infrastructure. A25 should KEEP them so future phases can re-verify.

### 5. Synthetic A25-baseline

**Cheat fingerprint**: A25-baseline-arm64-cgo-hashes.txt with hashes that don't match actual sha256sum.

**Halt + revert + retry**.

### 6. Validator/lib edits

**Halt immediately**.

### 7. Fix-summary claiming advance without qemu boot count proof

**Cheat fingerprint**: A25-fix-summary.md claims fix landed but qemu_repro.sh output not pasted or shows count <= 216.

**Honest version**: PASTE the qemu_repro.sh exit output showing `'link finish:' lines captured` count > 216. Specifically NAME the new ceiling.

## Required deliverables

### Path A — Real fix landed (the expected outcome)

qemu boot count > 216. Ship:

1. **A25-fix-summary.md** (≥250 lines): IR_RegSet fix code; FMOV helper encodings; the new qemu boot count; the new last-link-finish CGO name; analysis of which functions are now correctly emitting FMOV (verify throw-dispatch via disasm); any other audited IRs.
2. **A25-baseline-arm64-cgo-hashes.txt** — new sha256 hashes.
3. **A25-investigation-trace.md** (≥200 lines): the build + qemu cycle, the disasm verification, the audit of other IRs.
4. **A25-fix-disasm.txt** (optional but recommended): `aarch64-linux-gnu-objdump -d out/jak1-arm64/iso/KERNEL.CGO 2>/dev/null | grep -A 80 throw-dispatch` showing FMOV emit instead of MOV X30.

### Path B — Honest next-blocker

If the fix needs to expand beyond IR.cpp + IGenARM64.cpp (e.g., Allocator changes), honest-exit:

1. **A25-attempt-N-next-blocker.md** (≥250 lines): names the specific file + function.
2. **A25-investigation-trace.md** (≥200 lines).
3. CGOs match A24 baseline (no fix shipped).

### Path C — Fix landed but qemu doesn't advance

If the IR_RegSet fix landed correctly but qemu still ceilings at 216, that's surprising. Ship:

1. **A25-attempt-N-partial-fix.md** (≥250 lines): the fix that landed, the new disasm showing FMOV emit, the SIGILL signature (must differ from pre-fix), the next blocker hypothesis.
2. **A25-investigation-trace.md** (≥200 lines).
3. **A25-baseline-arm64-cgo-hashes.txt** — new hashes.
4. qemu count must still be ≥200 (no regression).

## Validator gates (full enforcement in `phase-A25-arm64-ir-regset-fpr-dispatch.sh`)

1. Lock check vs A24 close anchor.
2. Anti-cheat: weak/abort/dodge/stubs/infra.
3. A18+A19+A20+A21+A23+A24 invariants preserved (grep-enforced).
4. x86 CGOs byte-identical to A2 (HARD).
5. Required exit report (fix-summary / next-blocker / partial-fix) + investigation-trace.md.
6. arm64 CGOs:
   - Fix path: CGOs MUST differ from A24 baseline + A25-baseline present + qemu boot ≥ 217.
   - Next-blocker: CGOs match A24 baseline.
   - Partial-fix: CGOs differ from A24 baseline + A25-baseline + qemu ≥ 200 (no regression).
7. Tracer infra invariants (greps for OG_BLR_TARGET_TRACE / OG_X30_TRACE_EMIT + decoders).
8. Desktop x86 smoke reaches `link finish: logo`.

## Max settings

- `max_turns: 800`.
- `max_retries: 5`.

## Cost expectation

- Single-attempt fix: $50-150 (smaller scope than A22-A24's investigation-heavy phases).
- 2 attempts (one cycle of audit + fix): $100-300.
- Budget cap on this transition: $300.

## Strategic note

This is the FIRST fix phase since A19. If A25 lands, qemu should advance significantly past 216 (because throw-dispatch was blocking the throw path completely). The next ceiling tells us how dense the remaining bug field is. Optimistically, qemu could reach `link finish: logo` (a +227 advance) if no other codegen bugs exist. Pessimistically, it advances 30-50 and hits A26's bug.

Either way, A25 will tell us A LOT about the remaining work.
