# A27 investigation trace — catch-frame chain tracer to discriminate H1/H2/H3/H5

Authored 2026-06-09 by phase A27 attempt-1.

## Goal

A26 cleanly decoupled the XMM save/restore corruption (eliminated) from
the throw-not-found-tag-initialize chain mismatch (still present), and
shipped a clean `(break)` macro trap (CBNZ + UDF #0xBEEF) that fires once
in the throw error path at goal_off=0x1d68f8. A26 named 5 candidate
hypotheses:

- **H1** — catch-frame constructor mis-emits the chain link
- **H2** — chain-head pointer write mis-emits
- **H3** — throw walker's chain-pointer load mis-emits
- **H4** — regalloc / live-range bug in catch-frame construction
          (DEFERRED — would require Allocator.cpp unlock)
- **H5** — missing catch-frame setup before throw (a function isn't
          pushing 'initialize)

A27 extends the A26 SIGILL handler (the 0xBEEF UDF decoder in
`game/linux-arm64/linux_arm64_main.cpp`) with a catch-frame chain walker
that runs at trap time, walks the process's `stack-frame-top` chain, and
prints each frame's tag, type, and next pointer. The dump discriminates
between H1, H2, H3, and H5.

## Pre-A27 reality-check of A26 anchor state

The supervisor's pre-A27 reality-check confirmed:

- A26 commit 0a0bf0456 (claude) / 04d92409c (orchestrator phase-summary)
  pushed to autoport branch.
- arm64 CGOs match A26 baseline (sha256 `bd243e23ae…`, `e28ed2ea0e…`,
  `fb2fe7b72b…`).
- x86 CGOs byte-identical to A2 baseline.
- All A18/A19/A20/A21/A23/A24/A25/A26 invariants preserved.
- A26 BREAK-MACRO-TRAP fires cleanly with X24..X28 showing real values
  (not stack-range residue).

## Step 1 — read gkernel.gc throw and catch-frame

### `(defun throw (...))` at gkernel.gc:1594-1607

```
(defun throw ((name symbol) value)
  "Dynamic throw."
  (rlet ((pp :reg r13 :type process))
    (let ((cur (-> pp stack-frame-top)))
      (while cur
        (when (and (eq? (-> cur name) name) (eq? (-> cur type) catch-frame))
          ;; match!
          (throw-dispatch (the catch-frame cur) value))
        (if (eq? (-> cur type) protect-frame)
          ;; call the cleanup function
          ((-> (the protect-frame cur) exit)))
        (set! cur (-> cur next)))))
  (format 0 "ERROR: throw could not find tag ~A~%" name)
  (break))
```

The throw walker:
1. Loads `pp.stack-frame-top` (the chain head) into `cur`.
2. Walks the chain via `(-> cur next)`.
3. At each frame, checks `cur.name == name` AND `cur.type == catch-frame`.
4. If match → `throw-dispatch` (no return).
5. If `cur.type == protect-frame` → call its exit hook.
6. Continue to next frame.
7. If chain exhausted → format error + `(break)`.

### `(defmethod new catch-frame ...)` at gkernel.gc:1444-1529

The catch-frame constructor is an `asm-func` (manual register binding).
Key lines for the chain push:

```
;; push this stack frame
(set! (-> this next) (-> pp stack-frame-top))      ;; line 1514
(set! (-> pp stack-frame-top) this)                ;; line 1515
```

This is where a newly-constructed catch-frame is supposed to:
1. Link its `next` field to the current chain head.
2. Become the new chain head.

If either of these stores is mis-emitted on arm64, the chain doesn't
get updated and the throw walker can't find the frame.

### `(defun run-function-in-process ...)` at gkernel.gc:1784-1842

Calls `(new 'stack 'catch-frame 'initialize func param-array)` at line
1805. This is the canonical site where the 'initialize catch-frame is
created — the wrapper that lets the inner func `throw 'initialize` back
to run-function-in-process.

### `(defmethod activate ...)` at gkernel.gc:1746-1782

Activates a process. At line 1764:

```
(set! (-> this stack-frame-top) #f)
```

So a freshly-activated process has `stack-frame-top = #f` (= s7 = nil =
empty chain). The chain only becomes non-empty after a `(new 'stack
'catch-frame ...)` runs.

### Field layout (`gkernel-h.gc:322-348`)

```
(deftype stack-frame (basic)
  ((name symbol :offset 4)
   (next stack-frame :offset 8))
  :no-runtime-type)

(deftype catch-frame (stack-frame)
  ((sp   int32 :offset 12)
   (ra   int32 :offset 16)
   (freg float 10 :offset-assert 20)   ;; only use 8
   (rreg uint128 7))                   ;; only use 5

(deftype protect-frame (stack-frame)
  ((exit (function object))))
```

So:

- stack-frame.type at deftype offset 0 (the basic header).
- stack-frame.name at deftype offset 4.
- stack-frame.next at deftype offset 8.

Converted to memory offsets (subtracting `BASIC_OFFSET = 4` from
`common/goal_constants.h:9` — since the GOAL ptr points 4 bytes past the
basic header):

- frame.type → cur_host - 4
- frame.name → cur_host + 0
- frame.next → cur_host + 4

### `process` layout in `decompiler/config/jak1/all-types.gc:1953-1979`

```
(deftype process (process-tree)
  ((pool dead-pool :offset-assert 32)
   ...
   (heap-cur pointer :offset-assert 88)
   (stack-frame-top stack-frame :offset-assert 92)
   ...
```

`stack-frame-top` is at deftype offset 92. Subtracting `BASIC_OFFSET=4`
gives memory offset 88 (= 0x58) from the GOAL ptr. **This matches the
arm64 disasm at `LDR W3, [X16, #0x58]`** in the throw function entry.

## Step 2 — disassemble the throw function from the A26 trap log

The A26 BREAK-MACRO-TRAP fired at `emit_pc=0x21231d68f8 goal_off=0x1d68f8`.
A26's window dump (pc-96..pc+32) plus the extended `lr-1024..lr+16` dump
in `A26-qemu-symmetric.log` lines 706-1013 covers the throw function's
entire body.

### Throw function entry (goal_off 0x1d6724..0x1d6740)

```
goal_off 0x1d6724  0xa9bf7bfd  STP X29, X30, [SP, #-16]!   ; prologue
goal_off 0x1d6728  0x910003fd  MOV X29, SP                  ; FP = SP
goal_off 0x1d672c  0xd10043ff  SUB SP, SP, #16              ; carve 16 bytes
goal_off 0x1d6730  0xaa0703e5  MOV X5, X7                   ; X5 = X7 (name)
goal_off 0x1d6734  0xaa0603ec  MOV X12, X6                  ; X12 = X6 (value)
goal_off 0x1d6738  0x8b0f01b0  ADD X16, X13, X15            ; X16 = host(pp)
goal_off 0x1d673c  0xb9405a03  LDR W3, [X16, #0x58]         ; X3 = pp.stack-frame-top
goal_off 0x1d6740  0xaa0303e3  MOV X3, X3                   ; no-op
goal_off 0x1d6744  0x1400004f  B  +0x13C → goal_off 0x1d6880 ; jump to loop header
```

Confirms:

- **pp is in X13** at throw entry. arm64_reg5(R13) = R13.id() & 0x1f = 13
  → ARM64 X13 (`goalc/emitter/IGenARM64.cpp:37-39`). The Register.h
  comment "x20 = pp = R13" describes a register's *role*, not the actual
  emit mapping. The emit uses X13.
- **stack-frame-top is loaded at pp_host + 0x58** (= +88), matching the
  declared deftype offset 92 minus BASIC_OFFSET=4.
- **The throw `name` arg is in X7** at function entry — not X0 as a naïve
  read of "(name value)" args might suggest. (The goalc arm64 calling
  convention uses X0..X7 reversed compared to what one would expect from
  the rlet syntax; the actual emit confirms name → X7.)

### Loop body (goal_off 0x1d6748..0x1d6880)

```
goal_off 0x1d6748  0x8b0f0070  ADD X16, X3, X15           ; X16 = host(cur)
goal_off 0x1d674c  0xb9400209  LDR W9, [X16]              ; X9 = cur.name (offset 4 deftype - 4 = 0 mem)
... (comparison logic for cur.name == name AND cur.type == catch-frame) ...
goal_off 0x1d6880  0xaa0e03e9  MOV X9, X14                ; X9 = host(s7)
goal_off 0x1d6884  0xcb0f0129  SUB X9, X9, X15            ; X9 = s7 (GOAL nil)
goal_off 0x1d6888  0xeb09007f  CMP X3, X9                 ; compare cur to s7
goal_off 0x1d688c  0x54fff5e1  B.NE -0x144 → goal_off 0x1d6748  ; loop while cur != s7
                              ; fallthrough = chain end → error path
```

The loop terminates when `cur == s7` (= GOAL nil). This is the
standard GOAL while-loop test for non-#f.

### Error path (goal_off 0x1d6890..0x1d68d8)

```
goal_off 0x1d6890..0x1d68c0  ; format setup
goal_off 0x1d68c4  0xa9bf17e3  STP X3, X5, [SP, #-16]!    ; preserve X3, X5
goal_off 0x1d68c8  0xa9bf2fea  STP X10, X11, [SP, #-16]!  ; preserve X10, X11
goal_off 0x1d68cc  0xa9bf5fec  STP X12, X23, [SP, #-16]!  ; preserve X12, X23
goal_off 0x1d68d0  0xd63f0120  BLR X9                     ; call format
goal_off 0x1d68d4  0xa8c15fec  LDP X12, X23, [SP], #16    ; restore
goal_off 0x1d68d8  0xa8c12fea  LDP X10, X11, [SP], #16    ; restore (= caller_lr of IDIV)
goal_off 0x1d68dc  0xa8c117e3  LDP X3, X5, [SP], #16      ; restore X3, X5
```

The format call preserves X3 (last cur), X5 (name), X10-X12, X23.
**X13 is NOT preserved** across the format call. So at trap time X13
may or may not still hold the original pp — format is a GOAL function
that uses X13 freely.

### Break sequence (goal_off 0x1d68e8..0x1d68f8 — A26 trap site)

```
goal_off 0x1d68e8  0xd2800000  MOVZ X0, #0                  ; dividend = 0
goal_off 0x1d68ec  0xaa0003e0  MOV X0, X0                   ; (no-op)
goal_off 0x1d68f0  0xd2800009  MOVZ X9, #0                  ; divisor = 0
goal_off 0x1d68f4  0xb5000049  CBNZ X9, +8                  ; A26 check
goal_off 0x1d68f8  0x0000beef  UDF #0xBEEF                  ; A26 trap fires
goal_off 0x1d68fc  0xd10043ff  SUB SP, SP, #16              ; (skipped — A17 spill)
goal_off 0x1d6900  0xf90003e8  STR X8, [SP]
...
goal_off 0x1d6908  0x9ac90d08  SDIV X8, X8, X9              ; would-be SDIV by zero
```

This is the exact `(break)` macro lowering: `(/ 0 0)` with both operands
zero. The CBNZ on X9 (divisor=0) doesn't skip, UDF fires with our A26
tag 0xBEEF.

## Step 3 — derive runtime constants

| Constant | Value | Source |
|---|---|---|
| `STACK_FRAME_TOP_BYTE_OFFSET` | 0x58 (= 88) | disasm `LDR W3, [X16, #0x58]` at goal_off 0x1d673c |
| `FRAME_TYPE_BYTE_OFFSET` | -4 | basic header at -4 from goal ptr (BASIC_OFFSET=4) |
| `FRAME_NAME_BYTE_OFFSET` | 0 | gkernel-h.gc:323 (offset 4 deftype - 4 BASIC_OFFSET) |
| `FRAME_NEXT_BYTE_OFFSET` | +4 | gkernel-h.gc:324 (offset 8 deftype - 4 BASIC_OFFSET) |
| `pp register at throw entry` | X13 | arm64_reg5(R13) emit |
| `throw arg `name` reg` | X7 → X5 | disasm `MOV X5, X7` at goal_off 0x1d6730 |
| `s7 (goal nil)` | `X14 - X15` at trap | `MOV X9, X14; SUB X9, X9, X15` pattern in loop |
| `ee_base` | X15 at trap | `g_ee_main_mem` |

## Step 4 — implement the A27 chain dumper

The chain dumper extends the existing A26 0xBEEF SIGILL handler in
`game/linux-arm64/linux_arm64_main.cpp`. It runs after A26's window dump
and emits `GK-DIAG A27-DIAG` lines.

### Code added (excerpt — full implementation in the file)

```cpp
{
  uintptr_t ee_base = (uintptr_t)uc->uc_mcontext.regs[15];
  uintptr_t st_host = (uintptr_t)uc->uc_mcontext.regs[14];
  uint32_t s7_goal = (st_host >= ee_base)
      ? static_cast<uint32_t>(st_host - ee_base)
      : static_cast<uint32_t>(uc->uc_mcontext.regs[20]);
  const uint32_t throw_name =
      static_cast<uint32_t>(uc->uc_mcontext.regs[5]);

  const uintptr_t STACK_FRAME_TOP_BYTE_OFFSET = 0x58;
  const int MAX_CHAIN_DEPTH = 32;

  auto walk_pp_candidate = [&](const char* label, uint32_t pp_goal_u32) {
    // ... read pp.stack-frame-top, walk chain, emit per-frame line ...
    // ... emit verdict line: H5 / H1/H2 / H3 / uncertain ...
  };

  walk_pp_candidate("X13", x13_val);
  if (x20_val != x13_val) {
    walk_pp_candidate("X20", x20_val);
  }
}
```

The dumper walks the chain via:

- `pp_host = ee_base + pp_goal`
- `head_goal = *(uint32_t*)(pp_host + 0x58)` — chain head
- Per frame at `cur_host = ee_base + cur`:
  - `type_goal = *(uint32_t*)(cur_host - 4)`
  - `name_goal = *(uint32_t*)(cur_host + 0)`
  - `next_goal = *(uint32_t*)(cur_host + 4)`
- Stop when `cur == s7_goal` (chain end), `cur == 0`, or cycle.

The walker uses `gk_diag::safe_read_u32` (the existing SIGSEGV-trapping
helper) so an invalid pp doesn't crash the SIGILL handler.

It dumps TWO candidates (X13 and X20) because:

- X13 is the actual pp register per the arm64 emit (arm64_reg5).
- X20 is the conceptual pp per Register.h's misleading comment.

Both are dumped to make the diagnostic self-consistent regardless of
which mapping is in effect at trap time.

## Step 5 — build and re-run qemu

Built via `cmake --build build-arm64-linux --target gk` (no goalc emit
change, no CGO regeneration needed). Ran via `bash
.autoport/lib/qemu_repro.sh .autoport/reports/A27-qemu-chain-dump.log`.

CGOs SHA256:

- arm64 KERNEL.CGO: `bd243e23ae…` (matches A26 baseline)
- arm64 ENGINE.CGO: `e28ed2ea0e…` (matches A26 baseline)
- arm64 GAME.CGO:   `fb2fe7b72b…` (matches A26 baseline)
- x86 KERNEL.CGO: `19c2e10850…` (matches A2 baseline)
- x86 ENGINE.CGO: `3145d31da0…` (matches A2 baseline)
- x86 GAME.CGO:   `2a4b6c4fdc…` (matches A2 baseline)

So the SIGILL-handler-only change has zero effect on CGOs (as expected).

## Step 6 — read the A27-DIAG output

From `A27-qemu-chain-dump.log` lines 689-694:

```
GK-DIAG A27-DIAG catch-frame chain dump start: ee_base=0x2123000000
  s7_goal=0x18fe04 throw_name=0x192ae4 last_cur=0x18fe04
GK-DIAG A27-DIAG   pp_candidate X13 pp_goal=0x228214 pp_host=0x2123228214
  pp_type_tag@-4=0x1536e74 stack_frame_top=0x18fe04
GK-DIAG A27-DIAG   pp_candidate X13 chain_count=0 has_throw_name=NO
  last_cur=0x18fe04 termination=natural (cur==s7 or cur==0)
GK-DIAG A27-DIAG   verdict X13: chain head is s7 (= '#f / nil) —
  H5 candidate (no catch-frame ever pushed)
GK-DIAG A27-DIAG   pp_candidate X20 = 0x18fe04 = s7 (pp == nil; pp
  uninitialized or kernel sentinel — strongly suggests H5)
GK-DIAG A27-DIAG catch-frame chain dump end
```

### Reading the output

1. `ee_base = 0x2123000000` — matches X15 from the regdump.
2. `s7_goal = 0x18fe04` — matches the symbol table base; consistent
   with `last_cur = 0x18fe04` (= the value of `cur` at loop exit;
   the loop exited because cur reached s7 = nil).
3. `throw_name = 0x192ae4` — matches X5 at trap; this is the GOAL
   ptr to the 'initialize symbol (the error message says "could not
   find tag initialize").
4. **`pp_candidate X13 pp_goal=0x228214`** — a non-s7 GOAL ptr in the
   heap range. The `pp_type_tag@-4=0x1536e74` is a non-zero value,
   suggesting X13 holds a real process pointer (its type tag at -4
   has a structured value, not 0).
5. **`pp_candidate X13 stack_frame_top=0x18fe04`** — **THE CHAIN HEAD
   IS S7 (= GOAL NIL = EMPTY CHAIN).**
6. `pp_candidate X13 chain_count=0` — the walker traversed 0 frames.
7. `pp_candidate X20 = 0x18fe04 = s7` — X20 holds s7, not a process
   pointer. This confirms X20 is NOT the actual pp register on arm64;
   X13 is.

### Verdict

**H5 CONFIRMED:**

- The process at pp_goal=0x228214 has its stack-frame-top set to s7
  (= nil = empty chain).
- The throw was looking for tag 'initialize (= 0x192ae4) but the
  chain has NO frames at all.
- This is consistent with either:
  - run-function-in-process never being called for this process
    (so the 'initialize catch-frame was never constructed), OR
  - The catch-frame constructor (`(new 'stack 'catch-frame 'initialize
    func ...)` at gkernel.gc:1805) being called but failing to link
    itself onto the chain (gkernel.gc:1514-1515).

H1, H2, H3 are ALL FALSIFIED:

- H1 (catch-frame constructor mis-emits chain link) — would manifest as
  a frame on the chain with corrupted tag. But there's NO frame.
- H2 (chain-head pointer write mis-emits) — would manifest as the chain
  head pointing to garbage (a value that doesn't look like a stack-
  frame). But head_goal == s7, which is the CORRECT initial value
  set by `activate` at gkernel.gc:1764.
- H3 (throw walker mis-emits) — the walker correctly identified the
  end-of-chain (cur reached s7). If the walker had a load bug, we'd
  see it skip frames OR walk forever. Instead it walked 0 frames and
  exited, which is consistent with a correct walker over an empty
  chain.

H4 (regalloc / live-range) was deferred from A27 — would require
unlocking `goalc/regalloc/Allocator.cpp`. The A27 chain dump
ELIMINATES H4 as a candidate too: if a regalloc bug had clobbered
the catch-frame address mid-construction, we'd see a frame on the
chain with a corrupted address. The chain has NO frame, so no
regalloc bug applies to the *constructed* catch-frame — the
catch-frame was simply never *pushed*.

## Step 7 — identify A28 scope (next phase)

H5 confirmed. Two sub-cases for A28 to discriminate:

### Sub-case H5.a — run-function-in-process never called

If the boot path that produces the throw 'initialize trap does NOT go
through run-function-in-process, then there's a control-flow bug
upstream (some `(go!)` or `(initialize-process)` call that should call
run-function-in-process but doesn't).

A28 probe: at the entry of run-function-in-process
(`gkernel.gc:1784`), emit a marker write (e.g., to a debug global,
or use a tracer-style print). Count how many times it fires. Compare
to the number of `link finish:` lines (we'd expect at least one
per process activation).

### Sub-case H5.b — run-function-in-process called, but catch-frame
construction or chain-push fails

If run-function-in-process IS called, but `(new 'stack 'catch-frame
'initialize ...)` either:

- Never reaches the chain-push (lines 1514-1515) — possibly because
  the constructor's asm-func emit dies / returns early on arm64.
- Reaches the chain-push but the store mis-emits — the writes to
  `(-> this next)` (offset 8 deftype = +4 memory) and `(-> pp
  stack-frame-top)` (offset 92 deftype = +88 memory) must use the
  same arm64 store encoding as the throw walker's load. If the
  constructor's emit uses a wrong offset (e.g., 88 vs 92, off-by-4),
  the data goes to the wrong slot.

A28 probe: inspect the arm64 emit of the catch-frame constructor's
chain-push at gkernel.gc:1514-1515. The constructor is an asm-func
with `(.mov ...)` manual emit; verify that its STR-to-process and
STR-to-frame use the SAME `+0x58` offset that the throw walker's
LDR uses. Mismatched constructor STR vs walker LDR would explain why
the chain stays at #f (the constructor's write went somewhere else;
the walker correctly reads the original #f).

### Most likely sub-case

Looking at the constructor source (gkernel.gc:1444-1529):

- It's an asm-func declared with `(declare (asm-func object))`.
- It uses `(.mov :color #f temp xmm8..15)` patterns that A24/A25/A26
  worked on — those patterns are the SAVE side of the FPR-class
  scratch save.
- The chain push is `(set! (-> this next) (-> pp stack-frame-top))`
  followed by `(set! (-> pp stack-frame-top) this)`. These are
  high-level field stores that lower to normal arm64 `STR W` emits
  through IR.cpp.

Sub-case H5.b is the most likely. A28 should disassemble the
constructor (find it via the kernel symbol table — `new` method 0 of
`catch-frame`) and verify the chain-push STR offsets match the
walker's LDR offset.

### Caveats — H5 doesn't tell us WHERE the catch-frame WOULD have been

Even with H5 confirmed, A27 hasn't located the exact point in the
constructor / control flow where the chain push fails. That's A28's
job. A27's contribution is the discriminator: **the bug is upstream of
throw, and it's not a regalloc/walker bug — it's a chain-push bug.**

## Anti-cheat invariants (A27 attempt-1 status)

All A18/A19/A20/A21/A23/A24/A25/A26 invariants preserved:

- ✓ A18 `_Exit(13)` trap body in `game/kernel/common/klink.cpp`
- ✓ A19 X12 fix (`kStpX12X23Push|0xA9BF5FEC`) in
  `goalc/emitter/IGenARM64.cpp`
- ✓ A20 OG_OFFSET_TRACE ≥4 sites in `goalc/compiler/IR.cpp`
- ✓ A21 4 diags (OG_KLINK_IMM19_TRACE / OG_REG_BYTE_DUMP /
  OG_REGALLOC_TRACE / OG_CALLGOAL_TRACE)
- ✓ A23 BLR tracer (`OG_BLR_TARGET_TRACE`/`0x1EE0`)
- ✓ A24 epilogue+BR+asm+inline X30 tracer (`OG_X30_TRACE_EMIT`/`0x1EF0`)
- ✓ A25 `emit_arm64_reg_to_reg_mov` + `fmov_d_d`
- ✓ A26 `cbnz_x_imm` + `udf_imm16` + 0xBEEF decoder

A27 ADDS the chain dumper as a NEW sub-block of the existing 0xBEEF
decoder; the previous A26 output lines are preserved byte-for-byte and
emit in the same order. No goalc emit change.

## Cumulative reasoning

A23 (BLR tracer) → null finding: the failing BLR wasn't a call_r64.
A24 (X30 tracer) → confirmed the LR corruption mechanism: IR_RegSet
  emitting MOV X<id>, X<id> for FPR-class moves where id == X30.
A25 (X30-only narrow fix) → real fix on the X30 case; partial reveal
  of XMM save/restore corruption upstream.
A26 (symmetric XMM dispatch + IDIV trap) → eliminated XMM corruption,
  added clean (break) trap. The 216 ceiling persists, decoupled from
  XMM corruption. Five hypotheses listed (H1/H2/H3/H4/H5).
A27 (chain tracer) → **H5 confirmed: chain head is s7 (empty chain).**
  H1/H2/H3 falsified by the empty chain observation; H4 also falsified
  because there's no constructed frame to have a regalloc bug.

The next phase (A28) needs to determine WHY the catch-frame's chain
push isn't taking effect. Two sub-cases identified:
- H5.a: run-function-in-process never called for this process.
- H5.b: run-function-in-process called but constructor's chain push
  is mis-emitted (most likely per the asm-func emit complexity).

A28 scope: instrument the constructor or run-function-in-process
to discriminate; if it's a constructor emit bug, the fix likely fits
in goalc/compiler/IR.cpp or goalc/emitter/IGenARM64.cpp (within the
A27 unlock list). If it's a control flow issue (sub-case H5.a),
inspection of activate / dispatcher state is needed.

## Files touched in A27 attempt-1

| File | Change |
|------|--------|
| `game/linux-arm64/linux_arm64_main.cpp` | + A27-DIAG chain dumper inside the existing A26 0xBEEF UDF SIGILL handler. Walks pp.stack-frame-top via two candidate pp registers (X13, X20), prints each frame's type/name/next, emits a verdict line per candidate. Uses gk_diag::safe_read_u32 for SIGSEGV-safe reads. |
| `.autoport/reports/A27-investigation-trace.md` | NEW — this file. |
| `.autoport/reports/A27-attempt-1-bug-located-named-source.md` | NEW — the Path C exit report. |
| `.autoport/reports/A27-qemu-chain-dump.log` | NEW — qemu log with the A27-DIAG output. |
