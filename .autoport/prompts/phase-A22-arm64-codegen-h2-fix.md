# Phase A22 — arm64 codegen H2 fix (find and patch the source of stack-address-in-callee-saved-regs)

## First step — read these

1. `.autoport/CODEGEN_COOKBOOK.md`.
2. `.autoport/reports/A21-attempt-1-bug-class-identified.md` — names H2 (scratch / X16 corruption across BLR producing stack-as-GOAL-ptr) as the **primary cause** of the 216-link-finish ceiling, with arithmetically-verified evidence (`0x07fffe84 + 0x2123000000 = 0x212afffe84`).
3. `.autoport/reports/A21-diagnostic-summary.md` — sample stderr from the 4 env-gated diags (OG_KLINK_IMM19_TRACE, OG_REG_BYTE_DUMP, OG_REGALLOC_TRACE, OG_CALLGOAL_TRACE).
4. `.autoport/reports/A21-qemu-reg-byte-dump.log` — the raw qemu log with the smoking-gun register dump.
5. `.autoport/reports/A20-attempt-1-next-blocker.md` — A20's falsification of the off-by-4 hypothesis (so you don't re-investigate it).
6. `.autoport/reports/A19-attempt-1-next-blocker.md` — A19's X12 fix landed; that's the canonical H1 fix.
7. `game/kernel/asm_funcs_arm64.s` — the GOAL↔C bridge trampolines. **Audit `_call_goal_asm_arm64` and `_call_goal8_asm_arm64` STP/LDP pairs at lines 173-238 and 243-end.** A6 already extended the save list to X19-X28 + D8-D15; verify the slot calculations and stack-alignment are correct.
8. `goalc/emitter/IGenARM64.cpp` — search for `X16`, `kA6OffRegScratchRegId`, `call_r64`, and any emit path that stages a value across a BLR.

## Status

**Authored 2026-06-09 by the supervisor** after A21 attempt-1 honest-exited with H2 as primary cause. A21 added 4 env-gated diags but couldn't land the H2 fix because the fix lives outside A21's narrow unlock list (linux_arm64_main / klink / Allocator_v2 / jak1-kscheme — all instrumentation surfaces only).

Pre-A22 supervisor reality-checks:

- Verified the H2 arithmetic: `0x07fffe84 + 0x2123000000 = 0x212afffe84` (the SP+32 GOAL-form value reconstructs the crash PC exactly when host-converted with `ADD Xt, Xt, X15`).
- Verified the 8-register-same-stack-addr fingerprint: X16, X24, X25, X26, X27, X28, X29, X30 all hold `0x212afffe84` at SIGILL.
- Verified `_call_goal_asm_arm64` already saves X19-X28 + D8-D15 in the trampoline prologue (A6 extension). The trampoline LDP pairs look slot-consistent in source.
- Verified the A19 X12 fix is in place (`kStpX12X23Push = 0xA9BF5FECu` in call_r64).
- Verified the A20 OG_OFFSET_TRACE is in place at 4 sites in IR.cpp.
- Verified all 4 A21 diags are env-gated with the lazy-cached-getenv idiom.

## The 216-link-finish failure (the bug A22 must fix)

Crash sig (post-A21):

```
GK-DIAG sig=4 fault=0x212afffe84 pc=0x212afffe84 lr=0x212afffe84
GK-DIAG x12=0x21231d6344       ; HEAP host addr — function currently executing (GOAL offset 0x1d6344)
GK-DIAG x15=0x2123000000       ; ee_base, correct
GK-DIAG x16=0x212afffe84       ; STACK addr — should NOT be here
GK-DIAG x24=0x212afffe84       ; STACK addr — should NOT be here
GK-DIAG x25=0x212afffe84       ; (same)
GK-DIAG x26=0x212afffe84       ; (same)
GK-DIAG x27=0x212afffe84       ; (same)
GK-DIAG x28=0x212afffe84       ; (same)
GK-DIAG x29=0x212afffe84       ; (frame pointer — should be a saved FP, got stack addr)
GK-DIAG x30=0x212afffe84       ; (LR — RET'd to a stack addr)
GK-DIAG sp=0x212afffcc0
GK-DIAG sp+32 @ 0x212afffce0 = 0x0000000007fffe84   ; <GOAL-form of crash PC>
```

The GOAL-form value `0x07fffe84` was written to the SP+32 stack slot via a `STR W?` (32-bit store). A later `LDR W? [SP, #32] ; ADD X?, X?, X15 ; BLR X?` (or equivalent RET-via-corrupted-LR) jumped to the host stack address.

The value `0x07fffe84 = (0x212afffe84 - 0x2123000000) = (stack_addr - ee_base)` is **the output of a host→GOAL conversion (`SUB X?, X?, X15`) applied to a host stack address**. So somewhere in goalc-arm64 emit, a register holding a STACK host address was treated as a HEAP host address and host→GOAL converted — producing what looks like a GOAL function pointer, which got stored to a stack slot, then loaded back later, GOAL→host converted, and dispatched.

The 8-register fingerprint (X16 + X24..X30 all = `0x212afffe84`) suggests two layered mechanisms:

- **Source**: a single emit sequence wrote stack_addr into ONE register (most likely X16, the AArch64 IP0 scratch reg that goalc reserves at id 16 / `kA6OffRegScratchRegId`).
- **Propagation**: that corrupted register's value flowed through STP/LDP save chains across multiple nested frames (each function's prologue STR'd its callee-saved regs to its frame slots, body ran, epilogue LDR'd them back unchanged). X24..X28 are AAPCS callee-saved; if the deepest function received them already-corrupted at entry, they'd propagate up via faithful save/restore.

The job of A22 is to **find the SOURCE emit sequence and fix it**. Bandaging the propagation (e.g. widening call_r64 to save all of X19..X28) is explicitly FORBIDDEN — it masks the symptom without fixing the bug.

## Investigation steps

You do NOT need to do all of these — pick the path most consistent with what you find. But you SHOULD show evidence in `A22-investigation-trace.md` that you considered each path.

### Step 1 — Disassemble the crashing function

X12 at SIGILL = `0x21231d6344` = ee_base + GOAL offset `0x1d6344`. That's the host address of the function currently executing. Read the bytes at that offset in `out/jak1-arm64/iso/KERNEL.CGO` (or whichever CGO contains offset `0x1d6344` — likely KERNEL.CGO at file offset = `0x1d6344 - link_base + header_size`).

Disassemble ~256-1024 instructions backward from a plausible RET. Find:
- The LDP X29, X30 (or LDR X30) in the epilogue.
- The matching STP X29, X30 in the prologue.
- Any earlier STR W? that writes to the slot LDR Wt loads from in the failing dispatch.
- Any MOV / ADD / SUB that stages X16 or a callee-saved reg across a BLR.

### Step 2 — Walk the GOAL source

X12 = `0x21231d6344` → GOAL offset `0x1d6344`. Use the goalc symbol-debug-info path (typical pattern: `out/jak1-arm64/iso/KERNEL.CGO`'s linked symbol table) to identify which GOAL function this is. Match it to the `.gc` source. The fault PC is right at the boundary between two GOAL functions — knowing which function's epilogue / next function's prologue we're in narrows the suspect emit pattern dramatically.

### Step 3 — Walk goalc emit paths that stage values through X16

X16 (= `kA6OffRegScratchRegId`) is goalc-arm64's reserved scratch for the off-register sym-mem expansion path (see comments in IGenARM64.cpp lines 1016+). The "ADRP X16 / ADD X16 / LDR/STR Wt, [X16, #imm]" sequence (lines 983-993 and 1066+) is one place X16 is used.

If a BLR happens between the ADD X16 and the subsequent use, X16 is dead (per the cookbook's claim that "X16 is dead between IRs"). But if a sequence intra-IR puts ADRP+ADD X16 → BLR(somewhere) → use X16, the cookbook's claim is wrong for that path. Find it.

### Step 4 — Walk IR_FunctionCall::do_codegen_arm64

This is the BLR-emitting code path. Look for:
- Sequences where the BLR target reg is staged into X16 via a pre-BLR ADRP+ADD.
- Sequences where any callee-saved reg (X19..X28) is written between the BLR target setup and the BLR itself.
- Any path that emits `SUB X?, X?, X15` (host→GOAL conversion) on a register that may hold a stack address.

### Step 5 — Audit the trampoline STP/LDP slot consistency

`game/kernel/asm_funcs_arm64.s` lines 173-238 (`_call_goal_asm_arm64`), 243-end (`_call_goal8_asm_arm64`), and the corresponding restore sequences. Each STP pre-decrements SP by 16, each LDP post-increments by 16. The save and restore orders are EXACT mirrors. If any pair is mis-paired (e.g. epilogue LDPs x19,x20 from a slot that prologue STP'd x21,x22 to), all subsequent loads are 16-byte-offset wrong, ending with x29,x30 reading from a stack-frame value rather than the saved x29,x30 → which would manifest as **X29 = X30 = the slot that was actually saved at SP+something** (which could be a stack value if one of the saved regs was already corrupt).

The current source LOOKS correct on inspection but VERIFY with a fresh build:
```
objdump -d build-arm64-linux/game/linux-arm64/gk | grep -A 200 "_call_goal_asm_arm64"
```
The disasm must match the source in terms of slot layout.

### Step 6 — Audit call_r64's epilogue restore

After A19, `call_r64` saves {X3, X5, X10, X11, X12+X23}. The LDP restores must mirror these. If any LDP loads from a wrong slot, the corresponding GPR will hold stale stack data after the BLR returns. This is a candidate H2a source if true.

## Scope (locks)

**UNLOCKED for A22:**

- `goalc/emitter/IGenARM64.cpp` — full unlock. Fix surface for X16 staging, call_r64 sequence, IR_FunctionCall lowering.
- `goalc/emitter/IGenARM64.h` — full unlock. Signature changes may be needed for new helper(s).
- `goalc/compiler/IR.cpp` — full unlock. **OG_OFFSET_TRACE diag (4 sites) MUST persist.** Likely surface: `IR_FunctionCall::do_codegen_arm64` if BLR-staging is at fault.
- `game/kernel/asm_funcs_arm64.s` — trampoline audit + fix.
- `build-arm64-android/asm_funcs_arm64_gnu.s` — generated mirror; will rebuild automatically when the .s source changes.
- `.autoport/reports/A22-*.md`, `.autoport/reports/A22-baseline-arm64-cgo-hashes.txt`.
- `.autoport/tests/emitter/` — new unit tests welcomed.

**STILL LOCKED:**

- `goalc/emitter/IGenX86_64.cpp` / `.h` — x86 oracle, NEVER edit.
- `goalc/emitter/ObjectGenerator.cpp` / `.h` — link-time tables, no codegen.
- `goalc/compiler/Val.cpp` / `.h` — proven clean by A20 (zero-diff trace).
- `goalc/compiler/CodeGenerator.cpp` / `.h`.
- `goalc/compiler/Compiler.cpp`.
- `goalc/compiler/compilation/Type.cpp` — type system, not codegen.
- `goalc/regalloc/Allocator.cpp`, `allocate_common.cpp` — shared.
- `goalc/regalloc/Allocator_v2.cpp` — A21's OG_REGALLOC_TRACE diag must persist; no further edits.
- `common/type_system/Type.cpp` / `.h`.
- `game/kernel/common/klink.cpp` — A21's OG_KLINK_IMM19_TRACE must persist.
- `game/kernel/common/kscheme.cpp` — shared.
- `game/kernel/common/kmachine.cpp` — shared.
- `game/kernel/jak1/kscheme.cpp` — A21's OG_CALLGOAL_TRACE must persist; no further edits.
- `game/system/IOP_Kernel.cpp` / `.h`.
- `game/linux-arm64/linux_arm64_main.cpp` — A21's OG_REG_BYTE_DUMP must persist; you may extend the diag if needed but don't remove existing instrumentation.
- `game/linux-arm64/linux_arm64_runtime_compat.cpp`.
- `android/*` — never for A22 (linux-arm64 qemu first; android extensions belong to a later phase).
- `.autoport/validators/*` — NEVER edit.
- `.autoport/lib/*` — NEVER edit.
- `.autoport/prompts/phase-*-*.md` except `phase-A22-*` — NEVER edit other prompts.
- `.autoport/supervisor.sh`, `.autoport/orchestrator.py`.

## Anti-cheat invariants

- **x86 CGOs MUST be byte-identical to A2 baseline.** A22 must not change any shared codegen path. If x86 CGOs drift, you edited a shared file by accident OR a shared codegen path got modified through an arm64-only-intended edit. Halt + revert.
- **`a18_method_zero_trap` body unchanged** (still `std::_Exit(13)` in klink.cpp:644).
- **A19 X12 fix preserved**: `kStpX12X23Push = 0xA9BF5FECu` constant + the call_r64 emit sequence saving {X3+X5, X10+X11, X12+X23}.
- **A20 OG_OFFSET_TRACE preserved**: ≥4 emit sites in IR.cpp.
- **A21 diags preserved**: `OG_KLINK_IMM19_TRACE` in klink.cpp, `OG_REG_BYTE_DUMP` in linux_arm64_main.cpp, `OG_REGALLOC_TRACE` in Allocator_v2.cpp, `OG_CALLGOAL_TRACE` in jak1/kscheme.cpp.
- **0 `__attribute__((weak))` additions.** Weak symbols are the canonical phase-28 cheat — never reintroduce.
- **0 `abort()` / `std::abort()` additions.** If your code can't proceed, emit a clear error and return — don't `abort`.
- **0 new `*_stubs.cpp` files.**
- **0 inline `_stub(` function additions.**
- **0 modifications to `.autoport/lib/*.sh|*.py` or `.autoport/validators/*.sh`** (the supervisor's anti-cheat-tampering check).
- **0 `gk_recover_to_renderer` / `forced-recovery handoff` / `g_fault_recovery_armed`** patterns (the device dodge).

## Forbidden cheat patterns

Each pattern listed below has a corresponding past-phase incident. They WILL get the attempt reverted and fingerprinted.

### 1. Widening call_r64 to save ALL of X19..X28 without naming the source

**Cheat fingerprint**: a diff that extends call_r64's STP/LDP list to include {X19, X20, X21, X22, X24, X25, X26, X27, X28} (or any subset >= 4 of these), with a justification of the form "to prevent corruption."

**Why it's a cheat**: this masks the symptom but doesn't fix the bug. The corrupt value is ENTERING X16 / X24..X28 somewhere; widening the save list just guarantees that the corrupt value is saved+restored faithfully (preserving the corruption). The crash will still happen at the next frame that RETs to a slot containing stack_addr.

**Honest version**: identify the SPECIFIC emit sequence that wrote stack_addr into a register, and fix the emit to not do that. If you legitimately discover that call_r64 needs more saves, name the specific emit sequence (not just "more safety"); the fix-summary must reference a specific BLR site whose post-BLR code reads the corrupted reg.

### 2. Trampoline-wrapper that "preserves" X19..X28 around _arg_call_arm64

**Cheat fingerprint**: a new `_arg_call_arm64_safe` (or similar) that saves X19..X28 before calling _arg_call_arm64 and restores after.

**Why it's a cheat**: `_call_goal_asm_arm64` ALREADY saves X19..X28 (verified pre-A22). Adding another save layer just propagates correct values through a longer save chain, but doesn't fix the SOURCE of the corruption.

**Honest version**: don't wrap. Find the source. If the existing trampoline genuinely has a slot-calculation bug, fix the calculation in place.

### 3. NOP-padding around BLR sites

**Cheat fingerprint**: emit code that inserts `NOP`s around BLR sites (or any `dsb sy` / `isb` etc.) without naming a barrier requirement.

**Why it's a cheat**: NOPs don't fix register-tracking bugs. If a register holds wrong data, NOPs don't change that.

**Honest version**: fix the register-tracking logic in IGenARM64.cpp / IR.cpp.

### 4. Removing or NOP-ing SUB/ADD X15 cycles

**Cheat fingerprint**: a diff that removes the `SUB Xt, Xt, X15` or `ADD Xt, Xt, X15` instructions in some host↔GOAL conversion path.

**Why it's a cheat**: those conversions are correct for HEAP values (the entire GOAL pointer model depends on them). Removing them would break heap addressing for every CGO.

**Honest version**: identify which CALLER is passing a STACK address into a code path that expects a HEAP address. Fix the caller. The host↔GOAL conversions stay.

### 5. Editing OG_OFFSET_TRACE / OG_*_TRACE diag patches

**Cheat fingerprint**: a diff that disables, removes, or "optimizes out" any of A20's or A21's env-gated trace patches.

**Why it's a cheat**: those traces are the supervisor's check that no regression has been introduced. Removing them defeats the regression check.

**Honest version**: leave the diag patches alone. They're zero-cost when their env vars are unset.

### 6. Validator-script edits to relax checks

**Cheat fingerprint**: any diff to `.autoport/validators/*.sh` or `.autoport/lib/*.sh` or `.autoport/lib/*.py`.

**Why it's a cheat**: the validator is the supervisor's truth check. Modifying it lets the attempt pass without actually fixing the bug.

**Halt immediately**: any infra edit triggers immediate revert.

### 7. "Bug fix" report that re-cites H1/H3/H4 instead of H2

**Cheat fingerprint**: an `A22-fix-summary.md` that claims the bug was in regalloc (H1), klink (H3), or call_goal (H4). A21 already ruled these out with specific evidence.

**Why it's a cheat**: re-investigating ruled-out hypotheses is a sign claude didn't read A21's report. A genuine H2 fix names the specific X16-or-callee-saved-corruption surface.

**Honest version**: read A21's report. If you find new evidence that A21's ruling-out was wrong, name the new evidence specifically and don't just rehash A20's hypotheses.

## Required deliverables

### Path A — Real fix landed

If qemu_repro advances the link-finish count past 216 (= **217+**), you ship:

1. **A22-fix-summary.md** (≥200 lines): names the SPECIFIC emit sequence that produced stack_addr corruption, the disasm before/after the fix, the qemu boot count advance, and the new CGO that's reached.
2. **A22-baseline-arm64-cgo-hashes.txt** — fresh sha256 of every `out/jak1-arm64/iso/*.CGO`. These WILL differ from A21 baseline (the fix changes emit).
3. Source-level fix in one or more of `goalc/emitter/IGenARM64.{cpp,h}`, `goalc/compiler/IR.cpp`, `game/kernel/asm_funcs_arm64.s`.
4. Investigation trace in `A22-investigation-trace.md` (≥150 lines): the disasm walk, the emit-path identification, the steps you ruled out.

### Path B — Honest exit (fix surface outside A22's unlock list)

If the fix turns out to need a file outside A22's unlock (e.g., Val.cpp, Allocator.cpp, Type.cpp), you ship:

1. **A22-attempt-N-next-blocker.md** (≥200 lines): names the specific file + function + line range that needs unlock, the evidence implicating it, and what A22 ruled out.
2. **A22-investigation-trace.md** (≥150 lines): the disasm walk + emit-path identification + steps that led to the ruling-out.
3. Optionally, refined env-gated diags in the unlocked files (IGenARM64 / IR / asm_funcs_arm64.s) if they help future phases.
4. CGOs unchanged from A21 baseline.

**Do NOT silently extend A22's unlock list.** If you find that Val.cpp needs changing, write next-blocker.md and stop. Supervisor authors A23.

### Path C — Diag-only (no fix located)

If you can't identify a SPECIFIC emit sequence as the corruption source within A22's investigation budget, you ship:

1. **A22-attempt-N-no-source-located.md** (≥200 lines): the exhaustive list of paths you investigated, what each ruled out, and a proposed A23 investigation strategy (e.g., a runtime register-write trace).
2. **A22-investigation-trace.md** (≥150 lines).
3. Optional refined diags.
4. CGOs unchanged from A21 baseline.

This is the lowest-quality exit but still honest. Better than guessing.

## Validator gates (summary; full enforcement in `phase-A22-arm64-codegen-h2-fix.sh`)

1. Lock check: enumerated locked-file list, DIFF=0 between A21-close and HEAD.
2. Anti-cheat: 0 weak, 0 abort, 0 dodge, 0 _stubs, 0 inline _stub(, 0 infra edits.
3. A18 trap: `_Exit(13)` body in klink.cpp.
4. A19 X12 fix: `kStpX12X23Push|0xA9BF5FEC` in IGenARM64.cpp.
5. A20 trace: ≥4 OG_OFFSET_TRACE sites in IR.cpp.
6. A21 diags: ≥1 hit each of OG_KLINK_IMM19_TRACE, OG_REG_BYTE_DUMP, OG_REGALLOC_TRACE, OG_CALLGOAL_TRACE in the corresponding files.
7. x86 CGOs byte-identical to A2 baseline (HARD).
8. Required artifact: ONE of {A22-fix-summary.md, A22-attempt-N-next-blocker.md, A22-attempt-N-no-source-located.md} present + correctly-named hypothesis-referenced content + line-count threshold met.
9. Required artifact: A22-investigation-trace.md present (≥150 lines).
10. arm64 CGOs:
    - If A22-fix-summary.md present: CGOs MUST differ from A21 baseline + A22-baseline-arm64-cgo-hashes.txt present + qemu boot count must be ≥ 217.
    - Otherwise (next-blocker or no-source-located): CGOs SHOULD match A21 baseline (within ±0 KB tolerance — code unchanged on diag-only path); qemu boot count must be ≥ 200 (allow noise).
11. Desktop x86 smoke: `link finish: logo` reached.

## Max settings

- `max_turns: 800` (A22 is more open-ended than diag-only A21; allow more investigation).
- `max_retries: 5`.

## Cost expectation

- Investigation + 1 fix landing: $80-200.
- Investigation + 2 attempts (1 dead end, 1 working): $200-400.
- Investigation but honest-exit (no fix located): $40-120.
- Budget cap on this transition (supervisor watch): $400.
