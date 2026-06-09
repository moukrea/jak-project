# Phase A24 — arm64 epilogue X30 stack-range tracer (find the GOAL function whose frame got corrupted) + CodeGenerator.cpp epilogue audit

## First step — read these

1. `.autoport/CODEGEN_COOKBOOK.md`.
2. `.autoport/reports/A23-attempt-1-bug-located-named-source.md` — **A23's pivotal finding: H2-via-call_r64 FALSIFIED** (61204 instrumented BLR sites + 200+ link-finishes worth of runtime calls + ZERO tracer firings). The bug is NOT a `call_r64` BLR-to-stack — it's `RET` to a corrupted `X30`. The corruption enters via `LDP X29, X30, [SP], #N` in the function epilogue, reading a save slot that was written incorrectly during the function body.
3. `.autoport/reports/A23-investigation-trace.md` — A23's audit (350+ lines), including the threshold derivation (0x07000000 = 112 MB GOAL offset, comfortable margin above valid code at <10 MB and below stack at ~128 MB).
4. `.autoport/reports/A22-attempt-1-no-source-located.md` + A22-investigation-trace.md — A22's audit clearing `_call_goal_asm_arm64`, `_call_goal8_asm_arm64`, `_call_goal_on_stack_asm_arm64`, `make_function_from_c_arm64` inline trampoline. Also clearing `IR_FunctionCall::do_codegen_arm64`.
5. `.autoport/reports/A21-attempt-1-bug-class-identified.md` — A21's H2 verdict + arithmetic.
6. `goalc/compiler/CodeGenerator.cpp` — **the NEW unlocked file**. Find `do_goal_function_arm64` (or equivalent function-emit lowering for arm64). Look at its epilogue emit. Audit the standard arm64 function epilogue: `ADD SP, SP, #N` + `LDP X29, X30, [SP], #16` + `RET`.

## Status

**Authored 2026-06-09 by the supervisor** after A23 attempt-1 honest-exited via Path C with a strong, reproducible NEGATIVE result.

Supervisor's pre-A24 reality-check:

- A23 tracer infrastructure is verified honest: 61204 instrumentation sites in the CGOs (sha256-anchored at A23-baseline-arm64-cgo-hashes.txt), env-gated at goalc compile time (lazy-cached `std::getenv("OG_BLR_TARGET_TRACE_EMIT")`), real CMP-against-0x07000000 + B.LO + UDF-with-tag check (not a no-op).
- A23 tracer's null result is the smoking gun: NO `call_r64` BLR targeted a stack-range GOAL offset during a 216-link-finish boot run.
- The actual mechanism per A23's analysis: `LDP X29, X30, [SP], #N` in some function's epilogue loaded a corrupted `X30`; `RET` propagated the corruption to PC; SIGILL fired at the resulting host stack address.
- A23's evidence supporting this: bytes at `X12 - 0x18..X12 - 0x10` decode as `LDP X29, X30, [SP], #16; RET` — the canonical aarch64 goalc function epilogue.
- A24's job: instrument the function-epilogue emit to detect when LDP loads a stack-range X30, fire a UDF-with-tag SIGILL AT the LDP-site so the SIGILL handler can name the GOAL function whose frame is corrupted.

## The bug A24 must locate

Some STR/STP inside a GOAL function's body writes a value with the shape `0x0000_0000_07fffe84` to the X29/X30 save slot at `[SP, #0..15]` (the canonical save location in `do_goal_function_arm64`'s standard frame). The function's epilogue:

```
ADD SP, SP, #N        ; or implicit via LDP post-increment
LDP X29, X30, [SP], #16
RET                   ; PC = X30 = host stack address → SIGILL
```

The candidate STR/STP could be:
- A `(stack)`-allocated value that's stored too high in the frame (overlapping the X29/X30 slot).
- A regalloc spill to a slot that aliases the X29/X30 save slot due to bad SP arithmetic.
- A trampoline (asm_funcs_arm64.s — A22 audited clean, but A22's audit was symbolic; runtime check would re-verify).
- A `make_function_from_c_arm64` inline trampoline (jak1/kscheme.cpp — A22 audited clean).
- Some `__attribute__((naked))` C function that's called from GOAL but doesn't preserve X29/X30 correctly (unlikely since AAPCS preserves them, but worth checking).

**A24's tracer narrows the source to ONE specific GOAL function (the one whose epilogue fires the UDF), then the function's emit can be disassembled to find the offending STR/STP.**

## Tracer design

### Where to emit the check

In `goalc/compiler/CodeGenerator.cpp`, find the function-emit lowering for arm64. The relevant function is likely `do_goal_function_arm64` (or `emit_function_epilogue_arm64`, or it may be inline in another function). The epilogue emit produces:

```
ADD SP, SP, #N            ; reset SP to entry-relative position
LDP X29, X30, [SP], #16   ; restore caller's FP and LR (and post-inc SP by 16)
RET                       ; jump to caller's LR
```

When `OG_X30_TRACE_EMIT=1` is set in goalc's environment at compile time, modify the epilogue to insert a 5-instruction check between the LDP and the RET:

```
LDP X29, X30, [SP], #16
; A24 — X30 stack-range check (env-gated at goalc compile time)
SUB  X17, X30, X15            ; X17 = X30's GOAL offset (host - ee_base)
MOVZ X16, #0x0700, LSL #16    ; X16 = 0x07000000 (stack-range floor, same as A23)
CMP  X17, X16                 ; flags set per X30_GOAL vs threshold
B.LO ret_ok                   ; if X30_GOAL < threshold, normal RET
UDF  #0x1EF0                  ; distinctive tag for A24 epilogue trap
ret_ok:
RET
```

Encoding (same threshold + encoding pattern as A23):

- `SUB X17, X30, X15`: SUB Xd, Xn, Xm with d=17, n=30, m=15 → `0xCB000000 | (15<<16) | (30<<5) | 17 = 0xCB0F03D1`.
- `MOVZ X16, #0x0700, LSL #16`: `0xD2A0E010` (verified in A23).
- `CMP X17, X16` = `SUBS XZR, X17, X16` → `0xEB000000 | (16<<16) | (17<<5) | 31 = 0xEB10023F`.
- `B.LO +2 insns (+8 bytes)`: `0x54000000 | (2<<5) | 3 = 0x54000043`.
- `UDF #0x1EF0`: `0x00001EF0`.

X16/X17 are scratch (dead at function exit by AAPCS). The check is gated AT GOALC COMPILE TIME so unset → byte-identical to A23 baseline; set → CGOs differ from A23 baseline (and need a new A24 baseline).

### SIGILL handler decode

Extend `gk_sigsegv_diag` in `game/linux-arm64/linux_arm64_main.cpp` (already unlocked since A21). Add a new match for `udf_imm == 0x1EF0` (UDF instruction format: top 16 bits = 0, low 16 bits = imm16):

```cpp
if ((udf_enc & 0xFFFF0000u) == 0 && (udf_enc & 0xFFFFu) == 0x1EF0u) {
    uintptr_t x30 = uc->uc_mcontext.regs[30];
    uintptr_t x15 = uc->uc_mcontext.regs[15];
    uintptr_t goal_off = (x15 != 0 && x30 >= x15) ? (x30 - x15) : x30;
    fprintf(stderr,
            "GK-DIAG A24-DIAG EPILOGUE-X30-STACK: emit_pc=0x%lx "
            "x30=0x%lx goal_off=0x%lx x15=0x%lx caller_lr=0x%lx\n",
            (unsigned long)pc, (unsigned long)x30,
            (unsigned long)goal_off, (unsigned long)x15,
            (unsigned long)lr);
    // Dump 256-byte windows around emit_pc (function epilogue + body backward)
    // to identify the function's emit shape. The disasm just before emit_pc
    // is the LDP X29, X30; the disasm before THAT is the function body.
    for (intptr_t d = -256; d <= 0; d += 4) {
        uintptr_t a = pc + d;
        uint32_t w = 0;
        if (gk_diag::safe_read_u32(a, &w)) {
            fprintf(stderr,
                    "GK-DIAG A24-DIAG   pc%+ld @ 0x%lx = 0x%08x\n",
                    (long)d, (unsigned long)a, w);
        }
    }
}
```

The 256-byte backward window dumps the function epilogue + the tail of the function body. The disasm should reveal:
- The LDP X29, X30 (and maybe the ADD SP).
- The most recent STR/STP into a stack slot. If that STR/STP is to `[SP, #0]` or `[X29, #-N]` and writes a stack-range value, that's the offending instruction.

### Cross-referencing emit_pc to the GOAL function

The runtime maintains link blocks in `g_link_block_list` (kernel/common/klink.cpp). Each link block has a base PC and a length. Walking the list to find which block contains `emit_pc` identifies the loaded CGO + the function within. From there, the goalc symbol-debug-info can decode the function name.

**Implementation option A** (simpler): from inside the SIGILL handler, just walk `g_link_block_list` and print the matching link block's name. The SIGILL handler is in linux_arm64_main.cpp (unlocked); the link block list is in klink.cpp (locked). Access via an exported symbol:

```cpp
extern "C" void gk_a24_lookup_emit_pc(uintptr_t emit_pc) {
    // Walk g_link_block_list, find match, print
}
```

**Implementation option B** (more conservative): just dump emit_pc + caller_lr + the disasm window. Cross-reference offline by running `klink-arm64-dump` or similar.

Option A is more useful; option B is acceptable if the link block list access is fragile in signal context.

## Investigation steps

1. **Read CodeGenerator.cpp's function-emit lowering for arm64.** Find the epilogue emit. Document its current shape.
2. **Implement the env-gated X30 tracer** (5 instructions: SUB X17 X30 X15, MOVZ X16, CMP, B.LO, UDF #0x1EF0).
3. **Extend linux_arm64_main.cpp's SIGILL handler** to decode UDF #0x1EF0.
4. **Build goalc with `OG_X30_TRACE_EMIT=1`**, regenerate CGOs via `build_b1_arm64_cgos.sh`. Verify the tracer signature (`MOVZ X16, #0x0700, LSL #16` = bytes `10 E0 A0 D2 LE`, but at a DIFFERENT instruction-offset than A23's tracer — count occurrences and compare to function count to verify per-function-epilogue placement).
5. **Run qemu_repro.sh**. If the tracer fires, GK-DIAG A24-DIAG output names the offending epilogue's emit_pc.
6. **Walk emit_pc → GOAL function**. Either programmatically (option A) or offline (option B).
7. **Disassemble the named GOAL function's body** to find the STR/STP that corrupts the X29/X30 save slot.
8. **Identify the bug** (regalloc spill aliasing? Bad (stack ...) form? Trampoline bug?).
9. **Fix or honest-exit** with named source surface.

## Scope (locks)

**UNLOCKED for A24:**

- **NEW:** `goalc/compiler/CodeGenerator.cpp` / `.h` — function-epilogue emit (the primary fix surface).
- Continue: `goalc/emitter/IGenARM64.cpp` / `.h` (A23 call_r64 tracer must persist; new helpers may be added for the epilogue tracer).
- Continue: `goalc/compiler/IR.cpp` (OG_OFFSET_TRACE must persist).
- Continue: `game/kernel/asm_funcs_arm64.s` (no fix expected here; A22 cleared it).
- Continue: `game/linux-arm64/linux_arm64_main.cpp` (A21 OG_REG_BYTE_DUMP must persist; A23 UDF #0x1EE0 decoder must persist; A24 adds UDF #0x1EF0 decoder).
- Continue: jak1/kscheme.cpp (A21 OG_CALLGOAL_TRACE must persist).
- Continue: klink.cpp (A21 OG_KLINK_IMM19_TRACE must persist; A24 MAY expose a link-block-list lookup helper).
- Continue: Allocator_v2.cpp (A21 OG_REGALLOC_TRACE must persist).
- `.autoport/reports/A24-*`, `.autoport/tests/emitter/`.

**STILL LOCKED:**

- `goalc/emitter/IGenX86_64.cpp` / `.h` — x86 oracle, NEVER edit.
- `goalc/emitter/ObjectGenerator.cpp` / `.h`.
- `goalc/compiler/Compiler.cpp`.
- `goalc/compiler/Val.cpp` / `.h` — A22 cleared (no off-by-4); A23 audited (no stack-form leak via call_r64); A24 doesn't need it.
- `goalc/compiler/compilation/Type.cpp` — A22 cleared; A23 audited; A24 doesn't need it.
- `goalc/regalloc/Allocator.cpp`, `allocate_common.cpp`.
- `common/type_system/Type.cpp` / `.h`.
- `game/kernel/common/kscheme.cpp`, `kmachine.cpp`.
- `game/system/IOP_Kernel.cpp` / `.h`.
- `game/linux-arm64/linux_arm64_runtime_compat.cpp`.
- `android/*`.
- `.autoport/validators/*` / `.autoport/lib/*` — NEVER edit.
- `.autoport/prompts/phase-*-*.md` except `phase-A24-*`.
- `.autoport/supervisor.sh`, `.autoport/orchestrator.py`.

## Anti-cheat invariants

- **x86 CGOs MUST be byte-identical to A2 baseline.** CodeGenerator.cpp is SHARED — any edit that affects x86 emit breaks the regression check.
- **A18 trap body** `std::_Exit(13)` preserved in klink.cpp.
- **A19 X12 fix** `kStpX12X23Push|0xA9BF5FEC` preserved in IGenARM64.cpp.
- **A20 OG_OFFSET_TRACE** ≥4 sites preserved in IR.cpp.
- **A21 4 diags** preserved.
- **A23 tracer infrastructure** must persist: `OG_BLR_TARGET_TRACE` (or `blr_target_trace_emit_enabled`) in IGenARM64.cpp + `0x1EE0` or `BLR-TARGET-STACK` in linux_arm64_main.cpp.
- 0 `__attribute__((weak))` / `abort()` / dodge / `_stubs.cpp` / inline `_stub(` / infra edits.

## Forbidden cheat patterns

### 1. Disabling the standard arm64 epilogue (e.g., replacing LDP X29,X30 with hard-coded values)

**Cheat fingerprint**: a CodeGenerator.cpp edit that removes the LDP X29, X30 from the epilogue or replaces it with explicit MOVZ X30, #0.

**Why it's a cheat**: that breaks every GOAL function. The standard epilogue is correct; the bug is that the SAVE SLOT contents are wrong due to a STR/STP in the body. Fixing the SLOT wouldn't fix the body bug.

**Honest version**: leave the LDP in place. Add the env-gated check post-LDP.

### 2. Always-true CMP (no-op tracer)

**Cheat fingerprint**: a CMP that compares against a value the X30 GOAL offset can never reach (e.g., `MOVZ X16, #0xFFFF, LSL #48` = 64-bit max), making the B.LO always taken so the UDF never fires.

**Why it's a cheat**: defeats the diagnostic. Same threshold (0x07000000) as A23's tracer maintains comparability.

### 3. Hardcoded RET to a known-good address

**Cheat fingerprint**: replacing `RET` with `B abs_addr` where abs_addr is some known-good return point.

**Why it's a cheat**: shortcircuits the bug by jumping somewhere safe. Doesn't fix the X30 corruption.

### 4. Removing A23 tracer to "clean up"

**Cheat fingerprint**: a diff that removes `blr_target_trace_emit_enabled()` or the `OG_BLR_TARGET_TRACE_EMIT` env-gate from IGenARM64.cpp.

**Why it's a cheat**: A23's tracer is permanent infrastructure. Removing it would defeat re-verifying A23's null result in future phases.

### 5. Validator/lib edits

**Halt immediately**.

### 6. Synthetic A24-baseline file

**Cheat fingerprint**: A24-baseline-arm64-cgo-hashes.txt with hashes that don't match actual sha256sum.

**Halt + revert + retry**.

### 7. "Bug found" report that doesn't NAME the GOAL function

**Cheat fingerprint**: a fix-summary or bug-located report that says "bug is in some epilogue" without naming the specific GOAL function via emit_pc cross-reference.

**Honest version**: the tracer's emit_pc must be cross-referenced to a specific GOAL function name. If the cross-reference is offline (option B), document the offline process and provide the named function.

## Required deliverables

### Path A — Real fix landed

qemu boot count ≥217. Ship:

1. **A24-fix-summary.md** (≥250 lines): NAMES the GOAL function, the offending STR/STP, the fix (likely in CodeGenerator.cpp or IGenARM64.cpp).
2. **A24-baseline-arm64-cgo-hashes.txt** — sha256sum of the post-fix CGOs.
3. Source-level fix.
4. **A24-investigation-trace.md** (≥200 lines).

### Path B — Honest next-blocker

If fix is in a file outside A24's unlock. Ship:

1. **A24-attempt-N-next-blocker.md** (≥250 lines): names the specific file + function.
2. **A24-investigation-trace.md** (≥200 lines).
3. CGOs match A24 baseline (with tracer ship) or A23 baseline (without).

### Path C — Bug-located, named source (MOST LIKELY)

If tracer fires and names the GOAL function, but the fix is non-trivial (e.g., requires a refactor that's not in A24's scope). Ship:

1. **A24-attempt-N-bug-located-named-source.md** (≥250 lines): names the GOAL function, the disasm window, the offending STR/STP candidate, the proposed A25 fix scope.
2. **A24-investigation-trace.md** (≥200 lines).
3. Tracer landed (CGOs differ from A23 baseline).
4. A24-baseline file present.

### Path D — No-source-located

Tracer fires but emit_pc → function cross-reference fails. Ship:

1. **A24-attempt-N-no-source-located.md** (≥250 lines): explain the failure, propose A25 strategy.
2. **A24-investigation-trace.md** (≥200 lines).

### Path E — Tracer-doesn't-fire (similar to A23 outcome)

If the X30 tracer doesn't fire (X30 is never stack-range at any epilogue):

This would be very surprising given A23's evidence, but if it happens:

1. **A24-attempt-N-tracer-doesnt-fire.md** (≥250 lines): explains what the negative result implies (e.g., RET also isn't the source; maybe it's a direct B X<n> from somewhere; or maybe the SIGILL is from `BR Xn` not `RET`).
2. **A24-investigation-trace.md** (≥200 lines).

## Validator gates (full enforcement in `phase-A24-arm64-epilogue-x30-tracer.sh`)

1. Lock check vs A23 close anchor.
2. Anti-cheat: weak/abort/dodge/stubs/infra.
3. A18+A19+A20+A21+A23 invariants preserved (A23 = `OG_BLR_TARGET_TRACE`/`blr_target_trace_emit_enabled` in IGenARM64.cpp AND `0x1EE0`/`BLR-TARGET-STACK` in linux_arm64_main.cpp).
4. x86 CGOs byte-identical to A2 (HARD).
5. Required exit report (one of fix-summary / next-blocker / bug-located-named-source / no-source-located / tracer-doesnt-fire) + investigation-trace.md.
6. arm64 CGOs:
   - If fix-summary or bug-located present: CGOs differ from A23 baseline + A24-baseline present.
   - Otherwise: CGOs match A23 baseline.
7. qemu boot count: ≥217 (fix path) OR ≥200 (other paths).
8. Tracer infra (A24-specific): `OG_X30_TRACE_EMIT` or `epilogue_x30_trace_emit_enabled` in CodeGenerator.cpp (or IGenARM64.cpp helper) + `0x1EF0` or `EPILOGUE-X30-STACK` in linux_arm64_main.cpp.
9. Desktop x86 smoke reaches `link finish: logo`.

## Max settings

- `max_turns: 1200` (CodeGenerator.cpp audit + tracer + symbol resolution + disasm walk).
- `max_retries: 5`.

## Cost expectation

- Tracer implementation + run + decode + name: $100-300 per attempt.
- 2-3 attempts typical: $200-700.
- Supervisor budget cap on this transition: $700.

## Strategic note

A24 is the third successive A* phase that's investigation-heavy without a fix landing. The strategic estimate remains: 3-8 A* phases before arm64 reaches `link finish: logo`. If A24's tracer also fails to identify the source (Path D or E), the supervisor should consider whether to escalate the diagnostic approach (e.g., a guard-page-based memory-corruption catcher) or pause to consult the user.
