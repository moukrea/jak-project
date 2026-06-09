# Phase A26 — arm64 widen IR_RegSet dispatch to all XMM IDs (24..31) + add IDIV-by-zero trap so `(break)` macro actually traps

## First step — read these

1. **`.autoport/reports/A25-attempt-1-partial-fix.md` IN FULL.** This is the critical predecessor report. Key facts:
   - A25's X30-only narrow fix ELIMINATED throw-dispatch's LR corruption (A24 tracer fires 0 times now).
   - But qemu still ceilings at 216 because the SAVE side bug remains for XMM8..XMM15 (= GOAL IDs 24..31).
   - New failure: `ERROR: throw could not find tag initialize` → throw walks wrong catch chain → `(break)` macro silently no-ops on arm64 (SDIV by zero returns 0) → SP corrupted → SIGSEGV at LDP past heap end.
   - X24..X28 in crash dump all = `0x212afffe84` (same stack addr as A21-A23) — these are the SAVE-side residues from `(.mov temp xmm8..15)` reading uninitialized GPRs.
   - Five blockers explicitly named for A26 (page §"Five clear A26 blockers").
2. `.autoport/reports/A25-investigation-trace.md` — full 200-line investigation trace.
3. `.autoport/reports/A24-attempt-1-bug-located-named-source.md` — A24's original location of the X30 bug.
4. `goalc/compiler/IR.cpp` (search for `emit_arm64_reg_to_reg_mov`) — A25's narrow X30-only helper. A26 will widen this.
5. `goalc/compiler/IR.cpp` (search for `IR_IntegerMath::do_codegen_arm64`) — where IDIV/UDIV emit lives. A26 will add divide-by-zero trap.
6. `goalc/emitter/IGenARM64.cpp` (search for `idiv` / `sdiv`) — the actual SDIV emit.
7. `goal_src/jak1/kernel/gkernel-h.gc` (search for `defmacro break`) — see how `(break)` lowers to `(/ 0 0)`.

## Status

**Authored 2026-06-09 by the supervisor** after A25 attempt-1 honest-exited via Path C with a clear list of 5 blockers. **A26 tackles 3 of those 5** (blockers 1, 2, 3, 5 from A25's report); blocker 4 (gcommon FLOAT-FLOAT regression) is deferred to a separate phase because of its much wider blast radius.

Supervisor pre-A26 reality-checks (all PASS):
- A25 in completed, retries=1, commit `75c2089ef` pushed to origin.
- arm64 CGOs match A25-baseline-arm64-cgo-hashes.txt (`b8a541e8..`/`4308cd13..`/`ee473357..`).
- x86 CGOs byte-identical to A2 baseline.
- A18/A19/A20/A21/A23/A24 invariants preserved.
- A25 helper `fmov_d_d` exists in HEAD (added but unused by A25's narrow dispatch — ready for A26 widening).

## The bug A26 must fix — two coupled problems

### Problem 1 — Save-side cross-bank emit for XMM8..XMM15 (= GOAL IDs 24..31)

In `cpu-thread-suspend`, `new-catch-frame`, and similar asm-funcs, GOAL emits:

```
(.mov :color #f temp xmm8)   ; SAVE: read xmm8 into temp
(.mov :color #f temp xmm9)
...
(.mov :color #f temp xmm15)
```

These lower to `IR_RegSetAsm` with `src.id() ∈ {24..31}` and `dst.id() ∈ {0..15}` (GPR). The current emit (post-A25 narrow fix) is `MOV X<dst>, X<src.id()&0x1f>` = `MOV X<dst>, X<24..31>`. But X24..X31 were NEVER WRITTEN by goalc-emitted code that originally produced the XMM value (which went to V<id>, not X<id>). So the temp register receives garbage.

The fix: when `src` is XMM-class (FLOAT / VECTOR_FLOAT / INT_128) and `dst` is GPR_64, emit `FMOV X<dst>, D<src.id()&0x1f>` = `movq_gpr64_xmm64(dst, src)` (which already exists in IGenARM64.cpp).

### Problem 2 — Restore-side for dst IDs 24..29 and 31 (A25 only handled ID 30)

Same `(.mov :color #f xmm? temp-float)` pattern in `cpu-thread-resume` / `thread-resume` / `throw-dispatch`'s tail; current emit is `MOV X<24..31>, X<src>` which writes to the wrong register file.

The fix: extend A25's `emit_arm64_reg_to_reg_mov` helper to dispatch on src/dst class ALWAYS (not just when `dst.id() == 30`). For src=GPR, dst=XMM: `FMOV D<dst.id()&0x1f>, X<src>` = `movq_xmm64_gpr64(dst, src)`. For src=XMM, dst=XMM: `mov_vf_vf` (128-bit) or `mov_xmm32_xmm32` (32-bit) depending on data width.

### Problem 3 — The gcommon FLOAT-FLOAT regression risk

A25 attempt 1.1 (full FPR dispatch) broke gcommon. The diagnosis (A25 report §"Why the X30-only narrow fix is the right A25 ship"): some gcommon-through-texture FLOAT-FLOAT IR_RegSet callsites rely on the OLD no-op-on-V semantics (where the OLD `MOV X<xmm_id>, X<xmm_id>` was a self-move that no-op'd, AND subsequent code didn't actually read the value).

A26 MUST audit these callsites. If they exist and re-broken, A26 must EITHER:
- (a) Patch them individually to use a class-explicit emit (e.g., insert an MOV X<temp>, V<id> first).
- (b) Make the dispatch context-aware (e.g., only apply when the IR is inside an `(.asm ...)` block).
- (c) Honest-exit Path C with the gcommon regression localized.

### Problem 4 — `(break)` macro silently no-ops on arm64

`gkernel-h.gc:121` defines:

```
(defmacro break ()
  '(/ 0 0))
```

On x86, `idiv` with divisor 0 raises `#DE` (Divide Error) → kernel signal handler treats as crash. On arm64, `sdiv x?, x?, xzr` returns 0 silently (per AArch64 spec). So `(break)` is a no-op on arm64. When A25's post-throw-not-found path falls through `(break)`, the macro doesn't trap — control returns from the macro into a corrupted-SP frame, eventually crashing at the next LDP.

The fix: in `goalc/compiler/IR.cpp` (specifically `IR_IntegerMath::do_codegen_arm64`) or in the arm64 SDIV/UDIV emit, check at emit time whether the divisor is known to be zero (e.g., constant `(/ 0 0)`). If so, emit a UDF with a distinctive tag (e.g., `UDF #0xBEEF`) instead of the SDIV. Or alternatively: emit a CBZ-divisor-then-UDF sequence in front of every IDIV/UDIV so that runtime divide-by-zero traps even when the divisor is computed.

The latter (runtime check) is more invasive but more thorough. For A26 pick the SIMPLER form: detect compile-time-constant zero divisor, emit UDF #0xBEEF. The break macro's `(/ 0 0)` is constant.

Either way: extend the SIGILL handler in `linux_arm64_main.cpp` to decode UDF #0xBEEF as `GK-DIAG A26-DIAG BREAK-MACRO-TRAP: pc=0x<...> caller_lr=0x<...>`.

## Investigation/fix steps

1. **Read A25 partial-fix report and investigation trace.** Understand the 5 blockers and which 3 (or 4) A26 tackles.

2. **Widen the dispatch helper** `emit_arm64_reg_to_reg_mov` in IR.cpp to handle ALL class combinations (not just X30). Mirror the x86 `regset_common` shape exactly:
   - GPR + GPR → `mov_gpr64_gpr64` (= ORR Xd, XZR, Xn) — unchanged.
   - FLOAT/VEC + FLOAT/VEC → `mov_vf_vf` (= ORR Vd.16B, Vn.16B, Vn.16B) — replaces OLD GPR MOV.
   - GPR + FLOAT/VEC → `movq_gpr64_xmm64` (= FMOV Xd, Dn).
   - FLOAT/VEC + GPR → `movq_xmm64_gpr64` (= FMOV Dd, Xn).
   - Any FLOAT-only (32-bit) case → use `mov_xmm32_xmm32` (= FMOV Sd, Sn).

3. **Audit gcommon-through-texture FLOAT-FLOAT callsites**:
   - `git grep -nE "IR_RegSet|IR_RegSetAsm" goalc/compiler/` for callers.
   - For each caller, check whether the source/dest can be XMM-class.
   - For each XMM-class case, check whether the OLD codegen behavior (GPR self-MOV no-op) was being relied upon. Look for nearby reads from X<xmm_id> (treating an XMM-class value as if it were a GPR).
   - If any such reliance is found, fix it (e.g., explicit FMOV X<gpr>, V<xmm_id>; then MOV X<dst>, X<gpr>). Or insert a comment explaining why the OLD behavior was correct and the new behavior also works.

4. **Add IDIV-by-zero trap**:
   - Find `IR_IntegerMath::do_codegen_arm64` for IDIV/UDIV cases.
   - At emit time, check whether divisor is a compile-time constant `0`.
   - If so, emit `UDF #0xBEEF` (encoding `0x0000BEEF`) instead of SDIV.
   - Extend SIGILL handler in `linux_arm64_main.cpp` to decode this tag.

5. **Build goalc** (both x86 and arm64).

6. **Regenerate arm64 CGOs** (env vars UNSET — no tracer needed):
   ```
   bash .autoport/lib/build_b1_arm64_cgos.sh
   ```

7. **Verify x86 byte-identical** to A2 baseline.

8. **Verify arm64 CGOs differ from A25-baseline** (the wider fix changes more bytes).

9. **Run qemu_repro.sh**. Expected outcome: **qemu link-finish count > 216**, OR a NEW crash signature that names the next bug. If the `(break)` macro now traps with `BREAK-MACRO-TRAP` GK-DIAG, that's positive — we'll see WHERE the throw walks fail.

10. **Save A26-baseline-arm64-cgo-hashes.txt**.

11. **Write A26 reports** (fix-summary / partial-fix / next-blocker, plus investigation-trace).

## Scope (locks)

**UNLOCKED for A26** (continuation):

- `goalc/compiler/IR.cpp` — widen dispatch + IDIV trap.
- `goalc/emitter/IGenARM64.cpp` / `.h` — A25 helpers preserved; A26 may add small helpers (e.g., `udf_imm16` if not already present).
- `goalc/compiler/CodeGenerator.cpp` / `.h` — A24 tracer must persist.
- `game/kernel/asm_funcs_arm64.s` — A24 trampoline tracer must persist.
- `game/linux-arm64/linux_arm64_main.cpp` — A21/A23/A24 decoders must persist; A26 adds UDF #0xBEEF decoder.
- `game/kernel/jak1/kscheme.cpp` — A21/A24 must persist.
- `game/kernel/common/klink.cpp` — A21 must persist.
- `goalc/regalloc/Allocator_v2.cpp` — A21 must persist.
- `.autoport/reports/A26-*`, `.autoport/tests/emitter/`.

**STILL LOCKED:**

- `goalc/emitter/IGenX86_64.cpp` / `.h` — x86 oracle, NEVER edit.
- `goalc/emitter/ObjectGenerator.cpp` / `.h`.
- `goalc/compiler/Compiler.cpp`.
- `goalc/compiler/Val.cpp` / `.h`.
- `goalc/compiler/compilation/Type.cpp`.
- `goalc/regalloc/Allocator.cpp`, `allocate_common.cpp` — shared regalloc.
- `common/type_system/Type.cpp` / `.h`.
- `game/kernel/common/kscheme.cpp`, `kmachine.cpp`.
- `game/system/IOP_Kernel.cpp` / `.h`.
- `game/linux-arm64/linux_arm64_runtime_compat.cpp`.
- `android/*`.
- `.autoport/validators/*` / `.autoport/lib/*`.
- `.autoport/supervisor.sh`, `.autoport/orchestrator.py`.
- `.autoport/prompts/phase-*-*.md` except `phase-A26-*`.
- `goal_src/` (GOAL source — would break x86 byte-identity).

## Anti-cheat invariants

- **x86 CGOs MUST be byte-identical to A2 baseline.** IR.cpp is SHARED; only `do_codegen_arm64` may be modified.
- **A18 trap `_Exit(13)`** preserved.
- **A19 X12 fix** preserved.
- **A20 OG_OFFSET_TRACE** preserved.
- **A21 4 diags** preserved.
- **A23 tracer infra** preserved.
- **A24 tracer infra** preserved (epilogue, asm trampoline, inline trampoline, ret(), jmp_r64, all decoders).
- **A25 `fmov_d_d` helper** preserved + A25's `emit_arm64_reg_to_reg_mov` helper preserved (it will be EXTENDED, not removed).
- 0 weak / abort / dodge / `_stubs.cpp` / inline `_stub(` / infra edits.

## Forbidden cheat patterns

### 1. Reverting A25's narrow dispatch to OLD unconditional MOV

**Cheat fingerprint**: a diff that removes the `emit_arm64_reg_to_reg_mov` helper or restores `gen->add_instr(mov_gpr64_gpr64(dst, src), irec);` as the body of `IR_RegSet::do_codegen_arm64`.

**Why it's a cheat**: undoes A25's verified fix.

**Honest version**: EXTEND the helper, don't revert it.

### 2. Hardcoded value-of-X30-or-X24 substitution

**Cheat fingerprint**: a diff that hardcodes specific register IDs (24, 25, 26, ..., 31) in IR.cpp's dispatch instead of using a class check.

**Why it's a cheat**: the dispatch should be based on the GOAL Register's class (`m_dest->ireg().reg_class`), not on the arm64 hardware ID. The class is the semantically correct discriminator.

### 3. Disabling A24 tracer

**Cheat fingerprint**: removing `epilogue_x30_trace_emit_enabled` or any `OG_X30_TRACE_EMIT` reference from CodeGenerator.cpp / IGenARM64.cpp / linux_arm64_main.cpp.

**Halt + revert + retry.**

### 4. Making IDIV-by-zero a silent no-op (preserves arm64 default behavior)

**Cheat fingerprint**: a diff that "fixes" the break macro by making it silently no-op (e.g., emit a NOP for `(/ 0 0)`).

**Why it's a cheat**: the WHOLE POINT of the break macro is to TRAP. Silent no-op is the current BUGGY behavior on arm64.

**Honest version**: emit `UDF #0xBEEF` so the kernel's SIGILL handler catches the break, prints diagnostic, and aborts.

### 5. Synthetic A26-baseline

**Cheat fingerprint**: A26-baseline-arm64-cgo-hashes.txt with hashes that don't match actual `sha256sum out/jak1-arm64/iso/*.CGO`.

**Halt + revert.**

### 6. Validator/lib edits

**Halt immediately.**

### 7. Fix-summary claiming advance without qemu output proof

**Cheat fingerprint**: A26-fix-summary.md claims fix landed but qemu_repro.sh output not pasted or shows count ≤ 216.

**Honest version**: PASTE the qemu_repro.sh exit output showing `'link finish:' lines captured` count > 216 (fix path) or showing the new BREAK-MACRO-TRAP output (partial-fix path with break trap).

### 8. Editing goal_src/*.gc

**Cheat fingerprint**: any diff to `goal_src/jak1/kernel/gkernel.gc`, `gkernel-h.gc`, etc.

**Why it's a cheat**: GOAL source is shared between x86 and arm64. Editing it changes x86 CGOs, breaking the byte-identity check. The fix MUST be in goalc's arm64 emit, not in GOAL source.

## Required deliverables

### Path A — Full fix landed (the desired outcome)

qemu boot count > 216 (any advance is a victory). Ship:

1. **A26-fix-summary.md** (≥250 lines): the widened dispatch code; gcommon audit findings; IDIV trap; new ceiling.
2. **A26-baseline-arm64-cgo-hashes.txt** — fresh sha256.
3. **A26-investigation-trace.md** (≥200 lines).

### Path B — Honest next-blocker

If A26's scope still isn't enough (need to unlock Allocator.cpp etc.):

1. **A26-attempt-N-next-blocker.md** (≥250 lines): names the specific file + function.
2. **A26-investigation-trace.md** (≥200 lines).
3. CGOs match A25 baseline (no shipped change).

### Path C — Partial-fix (BREAK macro fix lands but ceiling unchanged)

qemu still at 216 BUT the new BREAK-MACRO-TRAP fires (= a new failure mode is now visible, advancing the diagnostic story):

1. **A26-attempt-N-partial-fix.md** (≥250 lines): which sub-fix landed (IDIV trap, dispatch widening, both?); the new crash signature; the next blocker hypothesis.
2. **A26-baseline-arm64-cgo-hashes.txt** if shipped.
3. **A26-investigation-trace.md** (≥200 lines).

### Path D — Regression (worse than A25 baseline)

If A26 attempt causes qemu count < 200, revert and try a narrower scope:

1. **A26-attempt-N-regression.md** documenting what broke.
2. Revert all changes (CGOs back to A25 baseline).
3. **A26-investigation-trace.md**.

## Validator gates (full enforcement in `phase-A26-arm64-xmm-symmetric-and-break-trap.sh`)

1. Lock check vs A25 close anchor.
2. Anti-cheat: weak/abort/dodge/stubs/infra.
3. A18+A19+A20+A21+A23+A24 invariants preserved (grep-enforced).
4. A25 helpers preserved (`emit_arm64_reg_to_reg_mov`, `fmov_d_d`).
5. x86 CGOs byte-identical to A2 (HARD).
6. Required exit report (fix-summary / next-blocker / partial-fix / regression) + investigation-trace.md.
7. arm64 CGOs:
   - Fix path: CGOs differ from A25 baseline + A26-baseline present + qemu ≥ 217.
   - Partial path: CGOs differ from A25 + A26-baseline present + qemu ≥ 200 + BREAK-MACRO-TRAP fires.
   - Next-blocker: CGOs match A25 baseline.
   - Regression: CGOs match A25 baseline (reverted).
8. Desktop x86 smoke reaches `link finish: logo`.

## Max settings

- `max_turns: 1000`.
- `max_retries: 5`.

## Cost expectation

- Single-attempt fix: $100-300 (deeper scope than A25 narrow fix).
- 2-3 attempts: $200-600.
- Budget cap: $600.

## Strategic note

This is the SECOND fix phase since A19. A25's partial-fix narrowed the surface; A26 widens it. If A26 reaches Path A (qemu > 216), we'll have validated the systematic fix approach for the entire XMM/GPR class issue. If A26 reaches Path C with BREAK-MACRO-TRAP firing, we'll have made the post-throw crash visible — which advances diagnostics even without breaking the ceiling.

A27+ planning will depend on A26's outcome.
