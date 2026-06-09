# Phase A27 — arm64 catch-frame chain tracer (discriminate H1/H2/H3/H5 for the throw-not-found-tag-initialize blocker)

## First step — read these

1. **`.autoport/reports/A26-attempt-1-partial-fix.md`** — A26's Path C exit with the 5 candidate hypotheses for the 217+ blocker:
   - H1: catch-frame constructor mis-emits the chain link.
   - H2: chain-head pointer write mis-emits.
   - H3: throw walker's chain-pointer load mis-emits.
   - H4: regalloc/live-range bug in catch-frame construction (would require Allocator.cpp unlock — DEFER).
   - H5: missing catch-frame setup before throw (a function isn't pushing 'initialize).
2. `.autoport/reports/A26-investigation-trace.md` — full A26 investigation.
3. `.autoport/reports/A25-attempt-1-partial-fix.md` — A25 context.
4. `goal_src/jak1/kernel/gkernel.gc` (search for `defun throw`, `defun-debug try`, `new catch-frame`, `*catch-frame-stack*`) — the throw and catch-frame runtime.
5. `goal_src/jak1/kernel/gkernel-h.gc` (search for `catch-frame`, `try`, `throw`) — the data layout.
6. `goal_src/jak1/engine/util/types.gc` if applicable.
7. `game/linux-arm64/linux_arm64_main.cpp` — A21/A23/A24/A26 SIGILL decoders. A27 will extend the A26 BREAK-MACRO-TRAP decoder.

## Status

**Authored 2026-06-09 by the supervisor** after A26 attempt-1 cleanly decoupled the XMM corruption (A24/A25 mechanism) from the chain mismatch. A26's BREAK-MACRO-TRAP fires 35 times in the boot, exactly once at the `throw` function tail when `(break)` fires after `throw could not find tag initialize`. **A27's job is to figure out WHY the chain doesn't have the 'initialize tag.**

Supervisor pre-A27 reality-checks (all PASS):
- A26 in completed, retries=1, commit `0a0bf0456` (claude) / `04d92409c` (orchestrator phase-summary) pushed.
- arm64 CGOs match A26-baseline.
- x86 CGOs byte-identical to A2.
- A18/A19/A20/A21/A23/A24/A25 invariants preserved.
- A26 sub-fixes verified: X24-X28 show real values, BREAK-MACRO-TRAP fires cleanly.

## The hypotheses A27 must discriminate

| ID | Hypothesis | Tell-tale evidence |
|----|------------|---------------------|
| H1 | Catch-frame constructor mis-emits chain link | Chain has the frame but its `tag` field is corrupted |
| H2 | Chain-head pointer write mis-emits | Chain head doesn't point to the latest frame |
| H3 | Throw walker's chain load mis-emits | Walker reads garbage at each frame |
| H5 | 'initialize catch-frame is never pushed | Chain is empty OR has frames but none has 'initialize tag |
| H4 | Regalloc/live-range bug | (defer — would need Allocator.cpp unlock) |

## A27 approach — extend BREAK-MACRO-TRAP decoder

The simplest discriminating instrumentation is to extend the existing A26 SIGILL decoder for tag 0xBEEF to ALSO dump the catch-frame chain at trap time. Steps:

1. **Find the chain head symbol**:
   - In jak1, the catch-frame chain head is stored in a thread-local symbol (likely `*catch-frame-stack*` per `gkernel.gc`'s `defmacro try` / `defun throw`).
   - The symbol table is `s7` + offset. The kernel keeps a list of `(symbol-name → symbol-offset)` mappings.
   - In the SIGILL handler, we can either (a) look up the symbol by its precomputed offset (statically determined from `gkernel.gc` source), or (b) read a runtime export.
   - Easiest path: in `gkernel.gc`, the chain head is at a stable symbol offset that we can determine by disassembling the existing throw walker (which already loads the head). The disasm window in the A26 BREAK-MACRO-TRAP output shows the IDIV at pc=0x21231d68f8 — the surrounding code is the throw tail. A few instructions before that is the chain-walker loop.

2. **Walk the chain**:
   - Once we have the head pointer, walk `next` pointers (probably at offset 0 or 4 in the catch-frame struct).
   - At each frame, print the `tag` (probably at offset 4 or 8) and `handler` (a function ptr).

3. **Print the throw tag arg**:
   - The throw function receives the tag in an arg register (likely R0 via the AAPCS-to-GOAL shuffle). The disasm window can identify which reg.
   - Print "throw looking for tag: 0x<tag-goal-form>" at trap time.

4. **Print the chain count + 'initialize presence**:
   - Walk the chain, count frames.
   - For each, check if `tag == 'initialize_symbol_offset` (also a known constant from gkernel.gc).
   - Print: `chain has N frames; 'initialize present: yes/no`.

The diagnostic output should be enough to discriminate:
- **Empty chain** → H5 (catch-frame never pushed).
- **Non-empty chain, no 'initialize, throw looking for 'initialize** → H1/H2/H3 (frame pushed but lost from chain OR walker can't see it).
- **'initialize on chain, throw still can't find it** → H3 (walker bug).

## Investigation steps

### Step 1 — Disassemble the throw function

The A26 BREAK-MACRO-TRAP output shows `emit_pc=0x21231d68f8 goal_off=0x1d68f8 caller_lr=0x21231d68d8`. So the throw function lives around GOAL offset 0x1d6800-0x1d6900. Read the bytes around that range from `out/jak1-arm64/iso/KERNEL.CGO` and disassemble. Identify:
- The chain head load (LDR Rt, [Xb, #imm]).
- The chain walker loop (CBZ Rt, end; LDR Rt_next, [Rt, #0]; CMP tag; B.EQ found; MOV Rt, Rt_next; B loop).
- The "tag not found" exit (the fallthrough to break).

### Step 2 — Find the chain head symbol offset

The chain head load in the disasm uses an offset into `s7` (the symbol table base, kept in X14 / R14 on arm64 per the existing trampoline shuffles). Determine the byte offset. That offset identifies the symbol.

Cross-reference with `goal_src/jak1/kernel/gkernel-h.gc` to find the symbol name (likely `*catch-frame-stack*` or `*catch*`).

### Step 3 — Find the catch-frame struct layout

In `goal_src/jak1/kernel/gkernel-h.gc`, find the `catch-frame` deftype. Note the field offsets for `next` (chain link) and `tag` (symbol).

### Step 4 — Add A27 chain dumper to the BREAK-MACRO-TRAP decoder

In `linux_arm64_main.cpp`, extend the A26 0xBEEF handler:

```cpp
if ((udf_enc & 0xFFFFu) == 0xBEEFu) {
  // ...existing A26 output...
  
  // A27: catch-frame chain dump
  uintptr_t x14 = (uintptr_t)uc->uc_mcontext.regs[14];  // = s7_host
  uintptr_t x15 = (uintptr_t)uc->uc_mcontext.regs[15];  // = ee_base
  const uint32_t CATCH_FRAME_HEAD_SYM_OFFSET = 0x????;  // from disasm
  const uint32_t CATCH_FRAME_NEXT_OFFSET = 0x??;        // from gkernel-h.gc
  const uint32_t CATCH_FRAME_TAG_OFFSET = 0x??;
  const uint32_t INITIALIZE_TAG_GOAL = 0x????;          // from disasm/source
  
  uint32_t head_goal = 0;
  gk_diag::safe_read_u32(x14 + CATCH_FRAME_HEAD_SYM_OFFSET, &head_goal);
  
  fprintf(stderr, "A27-DIAG catch-frame chain dump: head_goal=0x%x\n", head_goal);
  
  int count = 0;
  bool has_initialize = false;
  uint32_t cur = head_goal;
  while (cur != 0 && count < 32) {
    uintptr_t cur_host = x15 + cur;
    uint32_t next_goal = 0, tag_goal = 0;
    gk_diag::safe_read_u32(cur_host + CATCH_FRAME_NEXT_OFFSET, &next_goal);
    gk_diag::safe_read_u32(cur_host + CATCH_FRAME_TAG_OFFSET, &tag_goal);
    fprintf(stderr, "A27-DIAG   frame[%d] goal=0x%x next=0x%x tag=0x%x\n",
            count, cur, next_goal, tag_goal);
    if (tag_goal == INITIALIZE_TAG_GOAL) has_initialize = true;
    cur = next_goal;
    count++;
  }
  fprintf(stderr, "A27-DIAG chain count=%d has_initialize=%s\n",
          count, has_initialize ? "YES" : "NO");
  
  // Print the throw tag arg (likely X0 or X7 — check disasm)
  uintptr_t throw_tag_reg = (uintptr_t)uc->uc_mcontext.regs[0];  // adjust based on disasm
  fprintf(stderr, "A27-DIAG throw was looking for tag=0x%lx\n", (unsigned long)throw_tag_reg);
}
```

The constants must be derived from the actual disasm + source — they're not guessable.

### Step 5 — Build, regenerate, run qemu

No CGO byte change (the SIGILL decoder lives only in the gk binary). Just rebuild gk-arm64 and re-run qemu_repro.sh.

### Step 6 — Read the A27-DIAG output

The chain dump tells us which hypothesis is true:

- `chain count=0` → H5 confirmed. Next phase fixes the catch-frame setup.
- `chain count>0 has_initialize=NO` and throw was looking for 'initialize → H1 or H2 (frame's tag is corrupted OR a frame was lost from the chain). Compare each frame's tag to expected values.
- `has_initialize=YES` but throw still failed → H3 confirmed. The walker is reading the chain wrong.

### Step 7 — Write report

Path A: fix landed (qemu>=217 — would require fixing the identified bug in IR.cpp / IGenARM64.cpp, possibly the chain emit).
Path B: next-blocker (e.g., H4 confirmed, Allocator.cpp unlock needed).
Path C: bug-located-named-source (H1/H2/H3/H5 confirmed with specific evidence).

## Scope (locks)

**UNLOCKED for A27** (continuation):

- `game/linux-arm64/linux_arm64_main.cpp` — extend A26 0xBEEF decoder with chain dumper.
- `goalc/compiler/IR.cpp` — for any small emit fix if the bug is in chain emit and fits here.
- `goalc/emitter/IGenARM64.cpp` / `.h` — same.
- `goalc/compiler/CodeGenerator.cpp` / `.h` — A24 must persist.
- `game/kernel/asm_funcs_arm64.s` — A24 must persist.
- `game/kernel/jak1/kscheme.cpp` — A21/A24 must persist; A27 may add a chain-dump helper here if needed.
- `game/kernel/common/klink.cpp` — A21 must persist.
- `goalc/regalloc/Allocator_v2.cpp` — A21 must persist.
- `.autoport/reports/A27-*`.

**STILL LOCKED:**

- All x86 emit, ObjectGenerator, Compiler.cpp, Val.cpp/.h, compilation/Type.cpp.
- `goalc/regalloc/Allocator.cpp` / `allocate_common.cpp` — **explicitly deferred (H4 unlock)**.
- common/type_system/Type.cpp/.h.
- game/kernel/common/kscheme.cpp / kmachine.cpp.
- game/system/IOP_Kernel.*.
- linux_arm64_runtime_compat.cpp.
- android/*.
- validators/lib.
- `goal_src/*` (GOAL source — would break x86 byte-identity).

## Anti-cheat invariants

All A18/A19/A20/A21/A23/A24/A25/A26 invariants preserved.

- A18 `_Exit(13)` trap body.
- A19 X12 fix `kStpX12X23Push`.
- A20 OG_OFFSET_TRACE ≥4 sites.
- A21 4 diags.
- A23 tracer + decoder.
- A24 tracer + decoder.
- A25 `emit_arm64_reg_to_reg_mov` + `fmov_d_d`.
- A26 XMM widening preserved (`dst_in_xmm_save_slot`/`src_in_xmm_save_slot` predicates) + `cbnz_x_imm` + `udf_imm16` helpers + 0xBEEF decoder.

## Forbidden cheat patterns

1. **No-op chain dumper** — returns same output regardless of actual chain state. Halt.
2. **Magic constants without disasm justification** — every magic offset/tag must be derived from the actual KERNEL.CGO disasm + gkernel.gc source. Document the derivation in the report.
3. **Removing A23/A24/A26 tracer infrastructure**.
4. **Editing `goal_src/`** (would break x86 byte-identity).
5. **Unlocking Allocator.cpp** without explicit supervisor authorization (H4 deferred).
6. **Validator/lib edits**.

## Required deliverables

### Path A — Real fix landed

qemu boot count > 216. Ship:

1. **A27-fix-summary.md** (≥250 lines): the identified bug, the fix, the disasm verification, the new ceiling.
2. **A27-baseline-arm64-cgo-hashes.txt** if CGOs changed.
3. **A27-investigation-trace.md** (≥200 lines).

### Path C — Bug-located-named-source (most likely)

Tracer fires, hypothesis confirmed. Ship:

1. **A27-attempt-N-bug-located-named-source.md** (≥250 lines): the chain dump output, which hypothesis is confirmed, proposed A28 scope.
2. **A27-investigation-trace.md** (≥200 lines).
3. CGOs MAY match A26 baseline (if no goalc emit change) OR a new A27 baseline (if SIGILL handler change indirectly affects something).

### Path B — Next-blocker

Fix requires file outside A27 unlock list (e.g., Allocator.cpp).

1. **A27-attempt-N-next-blocker.md** (≥250 lines).
2. **A27-investigation-trace.md** (≥200 lines).

### Path D — No-source-located

Chain dump inconclusive, hypothesis not discriminable.

1. **A27-attempt-N-no-source-located.md** (≥250 lines).
2. **A27-investigation-trace.md** (≥200 lines).

## Validator gates

Same anti-cheat + invariant gates as A26, plus:
1. A27 chain dumper landed in linux_arm64_main.cpp (grep for `A27-DIAG` / `catch-frame chain dump`).
2. x86 CGOs byte-identical to A2.
3. arm64 CGOs MAY match A26 baseline (if pure SIGILL handler change) OR new A27 baseline.
4. qemu boot count ≥ 200 (no regression) OR ≥ 217 (advance, on fix path).

## Max settings

- `max_turns: 800`.
- `max_retries: 5`.

## Cost expectation

- Single-attempt diagnostic: $30-100 (smaller scope than A24-A26 fix-attempt iterations).
- Budget cap: $250.

## Strategic note

A27 is another diagnostic phase to NAME the next bug. If H5 is true (chain empty), the fix is probably in IR.cpp (chain push emit). If H1/H2/H3, the fix may need Allocator.cpp unlock (= H4). In that case, A28 would need supervisor consultation with the user about expanding scope.

Cumulative cost after A27 estimate: $530-630. Still within original $500-2000 budget but consuming the middle. If A28 needs Allocator.cpp, expect another $200-400 of work.
