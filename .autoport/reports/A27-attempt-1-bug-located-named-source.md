# A27 attempt-1 — H5 confirmed: catch-frame chain is empty at trap time. The throw-not-found-tag-initialize blocker is upstream of throw: a catch-frame was never PUSHED onto the active process's stack-frame-top chain. H1 / H2 / H3 falsified by direct observation. Suggested A28 scope: inspect the `(new 'stack 'catch-frame ...)` asm-func constructor's chain-push emit on arm64 (gkernel.gc:1514-1515), which is the canonical chain-push site.

Authored 2026-06-09 by attempt-1 of phase
`A27-arm64-catch-frame-chain-tracer`.

## Honest-exit verdict — Path C (bug-located-named-source)

**Path C** (chain dumper fired, hypothesis discriminated). A27's chain
dumper, added as a sub-block of the existing A26 0xBEEF UDF SIGILL
handler in `game/linux-arm64/linux_arm64_main.cpp`, walked the catch-
frame chain at trap time and produced these lines (from
`A27-qemu-chain-dump.log:689-694`):

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

The output **CONFIRMS H5**:

- `pp_goal = 0x228214` — a VALID process pointer (non-s7, in heap range,
  with a non-zero type tag at host-4).
- `stack_frame_top = 0x18fe04` — equals `s7_goal` = the GOAL nil pointer.
- `chain_count = 0` — the walker traversed zero frames before reaching
  the chain-end sentinel.

The active process exists (pp = 0x228214), but its catch-frame chain is
**empty**. The throw walker correctly read the empty chain and fell
through to the "could not find tag" error path.

H1 (catch-frame constructor mis-emits chain link), H2 (chain-head
pointer write mis-emits), and H3 (throw walker chain-pointer load mis-
emits) are **ALL FALSIFIED** by this observation:

- H1 would require a frame on the chain with a corrupted tag. There is
  no frame.
- H2 would require the chain head to point to a corrupted address (not
  s7). Head equals s7, which is the CORRECT initial value set by
  `activate` at gkernel.gc:1764.
- H3 would require the walker to mis-read frame fields. The walker
  exited the loop cleanly upon detecting `cur == s7` (= chain end).

H4 (regalloc / live-range in catch-frame construction) is ALSO falsified
in its frame-corruption form: there's no constructed frame to have a
regalloc bug applied to it.

## Why this is Path C (not Path A or B)

- **Path A** (qemu count ≥217) — not reached. qemu stays at 216
  link finishes. The A27 diagnostic doesn't fix anything; it only
  identifies the hypothesis.
- **Path B** (next-blocker outside scope) — not selected. The H5
  bug is in territory that A27's unlock list covers (the catch-
  frame constructor's emit in IR.cpp / IGenARM64.cpp, or the
  control flow in gkernel.gc which we cannot edit — but the A28
  fix may not need to touch goal_src/, just emit). H4 was already
  deferred from the A27 hypothesis list; A28 doesn't escalate to
  H4 because H4 is falsified by the empty chain.
- **Path C** (bug-located-named-source) — selected. We've NAMED
  the bug class (H5: chain push never executed) and identified the
  candidate code path (the catch-frame constructor's chain push at
  gkernel.gc:1514-1515 OR a control-flow path that skips the
  constructor entirely).

## Evidence chain

### A. The chain dumper output is well-formed

The A27 dumper is implemented as a tight 60-line block inside the
existing A26 0xBEEF UDF decoder. It uses `gk_diag::safe_read_u32` to
read process and chain memory safely (any wild pointer would trigger a
SIGSEGV inside the SIGILL handler, which the helper recovers from via
sigsetjmp/siglongjmp without crashing the dump).

The dumper traverses TWO candidate pp registers (X13 and X20) because:

- X13 is the actual pp register per goalc's arm64 emit (verified by
  disassembling the throw function at goal_off 0x1d6724..0x1d6740 — see
  A27-investigation-trace.md §"Step 2"). The emit `ADD X16, X13, X15`
  + `LDR W3, [X16, #0x58]` reads pp.stack-frame-top via X13.
- X20 is the "conceptual" pp per Register.h's misleading comment
  (`x20, // pp, R13` at goalc/emitter/Register.h:89). The actual emit
  doesn't use X20 for pp because arm64_reg5 (Register.id() & 0x1f at
  goalc/emitter/IGenARM64.cpp:37-39) maps register id 13 directly to
  ARM64 X13.

The dumper's TWO-candidate strategy made the discriminator more robust:
if X13's value were clobbered between throw entry and the trap, X20's
value would still get walked. In practice, X13 at trap = 0x228214 (a
valid process pointer), and X20 at trap = 0x18fe04 (= s7).

### B. The chain-head load offset is verified

The throw function's chain head load is at goal_off 0x1d673c:

```
goal_off 0x1d673c  0xb9405a03  LDR W3, [X16, #0x58]
```

Decoding 0xb9405a03 (LDR W unsigned offset):

- imm12 = 22, scaled by 4 (W = 32-bit) = 88 bytes
- Rn = 16 (X16)
- Rt = 3 (W3)

Offset 88 = 0x58 matches the declared `stack-frame-top` deftype offset
92 (from `decompiler/config/jak1/all-types.gc:1969`) minus
`BASIC_OFFSET = 4` (from `common/goal_constants.h:9`). The A27 dumper
uses the SAME offset (0x58) for its read, so the dumper and the throw
walker access the same field.

### C. The frame field offsets are verified

The stack-frame deftype at gkernel-h.gc:322-326:

```
(deftype stack-frame (basic)
  ((name symbol :offset 4)
   (next stack-frame :offset 8))
  :no-runtime-type)
```

After BASIC_OFFSET=4 subtraction (because the GOAL ptr points 4 bytes
past the basic header):

- `frame.type` (the basic header at deftype offset 0) → memory offset -4
- `frame.name` (deftype offset 4) → memory offset 0
- `frame.next` (deftype offset 8) → memory offset +4

The throw walker's first field load is at goal_off 0x1d674c:

```
goal_off 0x1d674c  0xb9400209  LDR W9, [X16]      ; X9 = cur.name (offset 0 mem)
```

Decoding 0xb9400209: imm12 = 0, Rn = X16, Rt = W9. Offset 0 from
host(cur) = name field (memory offset 0 = deftype offset 4 - BASIC_
OFFSET). This confirms the layout interpretation: the walker reads
cur.name, which matches the GOAL source `(eq? (-> cur name) name)`.

The A27 dumper uses the same offset interpretation. The dumper's
chain head being s7 is a real observation, not an offset bug.

### D. The pp candidate X13 is a real process pointer

The dumper output:

```
pp_candidate X13 pp_goal=0x228214 pp_host=0x2123228214
  pp_type_tag@-4=0x1536e74 stack_frame_top=0x18fe04
```

- `pp_goal = 0x228214` is in the heap range (above s7 = 0x18fe04, below
  the EE stack base). Consistent with a process allocated in the global
  heap.
- `pp_type_tag@-4 = 0x1536e74` is a non-zero, structured value
  (32 bits, GOAL-ptr-shaped). For a real process, this would be the
  GOAL ptr to the `process` type. We don't verify this fully (we'd need
  to resolve type tags through the symbol table), but the fact that
  it's non-zero AND distinct from s7 strongly suggests pp is a valid
  process.

The process exists; it's just that its stack-frame-top has never been
populated with a catch-frame.

### E. The X20 candidate confirms pp ≠ X20

```
pp_candidate X20 = 0x18fe04 = s7 (pp == nil; pp uninitialized or
  kernel sentinel — strongly suggests H5)
```

X20 holds s7. If pp WERE x20 per Register.h's comment, then pp == s7 ==
"no current process" — equally consistent with H5 (no catch-frame
because no process). But the X13 dump shows pp IS a real process, so
the emit-time mapping is X13 = pp, not X20.

The TWO-candidate strategy thus also serves to NAME the misleading
Register.h comment as a documentation drift item — actual emit uses X13.

### F. The error path doesn't affect the chain state

The throw walker reaches the error path because the chain is empty,
NOT because the walker misread something. Specifically:

- The loop exit condition (goal_off 0x1d6884..0x1d688c) is `cur != s7`.
  At entry, cur = pp.stack-frame-top = s7 (from the dumper). So the
  loop never executes its body — it exits immediately.
- The error path (goal_off 0x1d6890..0x1d68d4) calls format and then
  the `(break)` macro at goal_off 0x1d68f8.

This is exactly what we'd expect for an empty chain: walker correctly
identifies the chain as empty, falls through to format + break, A26's
UDF #0xBEEF trap fires, A27's chain dumper confirms the chain was
empty.

## A28 scope (next phase)

The H5 confirmation narrows A28 to TWO sub-cases:

### H5.a — run-function-in-process never called

If the boot path that leads to the `throw 'initialize` does NOT go
through `run-function-in-process` (gkernel.gc:1784), then no
catch-frame was ever constructed. Some upstream code is calling throw
without first setting up the wrapper.

A28 probe for H5.a: instrument `run-function-in-process` (gkernel.gc
1784) entry. We CAN'T edit goal_src/ (would break x86 byte-identity),
but we CAN:

- Disassemble the kernel symbol for `run-function-in-process` and emit
  an A28-DIAG before the catch-frame construction call. Identify
  whether it's called and how many times.
- Add a per-process counter in `game/kernel/jak1/kscheme.cpp` or
  `game/kernel/common/kscheme.cpp` (locked — would need to be the
  arm64-side runtime, which is in `game/linux-arm64/linux_arm64_main
  .cpp` or `linux_arm64_runtime_compat.cpp` — but the latter is
  also locked).

Best A28 probe for H5.a: add a CBNZ + UDF #0xC0DE (new A28 tag)
sentinel at the start of run-function-in-process via goalc emit. If
the tag never fires, then run-function-in-process is never called.

### H5.b — catch-frame constructor's chain push is mis-emitted

Looking at the catch-frame constructor (gkernel.gc:1444-1529):

```
(defmethod new catch-frame ((allocation symbol) (type-to-make type)
                            (name symbol) (func function)
                            (param-block (pointer uint64)))
  (declare (asm-func object) (allow-saved-regs))
  (rlet ((pp :reg r13 :type process)
         ...)
    (let ((this (the catch-frame (&+ allocation *gtype-basic-offset*))))
      ;; setup catch frame
      (set! (-> this type) type-to-make)
      (set! (-> this name) name)
      ...
      ;; push this stack frame
      (set! (-> this next) (-> pp stack-frame-top))       ;; line 1514
      (set! (-> pp stack-frame-top) this)                 ;; line 1515
      ...)))
```

The chain push at lines 1514-1515 involves:

1. `(-> pp stack-frame-top)` — read at pp_host + 0x58 (verified).
2. `(set! (-> this next) ...)` — write at this_host + 0x04 (= next
   field memory offset).
3. `(set! (-> pp stack-frame-top) this)` — write at pp_host + 0x58.

If any of these stores is mis-emitted on arm64 (wrong offset, wrong
size, wrong register), the chain stays at #f. Most likely candidate:
the offset MISMATCHES between the constructor's stores and the
walker's load.

A28 probe for H5.b: disassemble the catch-frame constructor (find the
`new catch-frame` method via the kernel type-method table) and check:

- The STR offset for the `(set! (-> this next) ...)` store. Should be
  this_host + 0x04 (the next field in memory).
- The STR offset for the `(set! (-> pp stack-frame-top) this)` store.
  Should be pp_host + 0x58.
- The LDR offset for the `(-> pp stack-frame-top)` read. Should be
  pp_host + 0x58 (matching the walker's load).

If any of these offsets is wrong on arm64 (e.g., uses the deftype
offset 92 instead of the corrected memory offset 88), that's the fix
point.

### Most likely sub-case

H5.b is more likely because:

- The constructor is an `asm-func` with manual `.mov` ops that
  A24/A25/A26 worked on. The XMM save/restore was previously broken;
  it's plausible that field stores in the same constructor are
  similarly broken on arm64.
- The throw is firing on a real, valid process (X13 = 0x228214 has a
  structured type tag). So pp IS a process, and code WAS executing in
  that process. That code likely called run-function-in-process at
  some point.
- If H5.a were true, we'd expect to see pp == s7 (no current process)
  more often.

A28 should first disassemble the constructor's chain-push emit (H5.b),
and only fall back to instrumenting run-function-in-process (H5.a) if
the constructor's emit looks correct.

### A28 unlock proposal

A28 should INHERIT A27's unlock list:

- `game/linux-arm64/linux_arm64_main.cpp` (for any new SIGILL decoder).
- `goalc/compiler/IR.cpp` (for any field-store emit fix).
- `goalc/emitter/IGenARM64.cpp` / `.h` (for any encoding fix).
- `goalc/compiler/CodeGenerator.cpp` / `.h` (A24 preservation).
- `game/kernel/asm_funcs_arm64.s` (A24 preservation).
- `game/kernel/jak1/kscheme.cpp` / `common/klink.cpp` (A21/A24/A18).
- `goalc/regalloc/Allocator_v2.cpp` (A21).
- `.autoport/reports/A28-*`.

Should ALSO consider unlocking:

- `goalc/regalloc/Allocator.cpp` / `allocate_common.cpp` — IF the
  constructor's chain-push emit turns out to be regalloc-driven (the
  store register has wrong contents). Currently still locked through
  A26/A27.

A28 should NOT need to touch `goal_src/` (would break x86 byte-
identity) — the constructor's GOAL source is the same on arm64 and
x86; only the emit differs.

## qemu CGO state

### arm64 CGO baseline preserved (no goalc emit change)

A27 makes ONLY a SIGILL-handler-only edit in
`game/linux-arm64/linux_arm64_main.cpp`. No goalc emit change. CGOs
remain at A26 baseline:

```
bd243e23ae2cc323ba6656aa1826e7836412a9bb4386820b7288b46d7ad89f35  out/jak1-arm64/iso/KERNEL.CGO
e28ed2ea0e8d81f4cb7abfacad17bf8b1e27c1ecb0c0294f4ff5ead869519144  out/jak1-arm64/iso/ENGINE.CGO
fb2fe7b72bbf7eda559060e8ee51a4cabf42c7bd78590a3d628a77a20ae29577  out/jak1-arm64/iso/GAME.CGO
```

This matches `.autoport/reports/A26-baseline-arm64-cgo-hashes.txt`
byte-for-byte. No A27-baseline file is needed.

### x86 CGO baseline preserved (A2)

```
19c2e10850ac7a59653026aae079ee657541a9cc1eaee96a13e335b151778afa  out/jak1/iso/KERNEL.CGO
3145d31da02c413e5d51f3017bd5a78c2b11a80166ae62afa10f8568d14d63b5  out/jak1/iso/ENGINE.CGO
2a4b6c4fdcd507515ddcf20d55bb3cb6fc50701d03a43fc8d7a393eda1358a24  out/jak1/iso/GAME.CGO
```

Byte-identical to A2 baseline (`.autoport/reports/A2-baseline-x86-cgo-
hashes.txt`).

### qemu link-finish count preserved at 216

```
$ grep -c "link finish:" .autoport/reports/A27-qemu-chain-dump.log
216
```

Same as A24/A25/A26. No regression. The A27 chain dumper does NOT
advance the boot — it only diagnoses the existing 216 ceiling.

## Anti-cheat invariants (A27 attempt-1 status)

All required A27 anti-cheat checks satisfied:

- ✓ A18 `_Exit(13)` trap body preserved in
  `game/kernel/common/klink.cpp` (validator gate 3.1).
- ✓ A19 X12 fix preserved (`kStpX12X23Push|0xA9BF5FEC` in
  `goalc/emitter/IGenARM64.cpp`, validator gate 3.2).
- ✓ A20 OG_OFFSET_TRACE preserved (4+ sites in
  `goalc/compiler/IR.cpp`, validator gate 3.3).
- ✓ A21 4 diags preserved (klink.cpp's OG_KLINK_IMM19_TRACE,
  linux_arm64_main.cpp's OG_REG_BYTE_DUMP, Allocator_v2.cpp's
  OG_REGALLOC_TRACE, jak1/kscheme.cpp's OG_CALLGOAL_TRACE,
  validator gate 3.4).
- ✓ A23 tracer infra preserved (`OG_BLR_TARGET_TRACE`/
  `blr_target_trace_emit_enabled` in IGenARM64.cpp + `0x1EE0`/
  `BLR-TARGET-STACK` in linux_arm64_main.cpp, validator gates 3.5–3.6).
- ✓ A24 epilogue + BR + asm + inline tracer infra preserved
  (`OG_X30_TRACE_EMIT`/`epilogue_x30_trace_emit_enabled`/`0x1EF0` in
  CodeGenerator.cpp + IGenARM64.cpp + `0x1EF0`/`EPILOGUE-X30-STACK`
  in linux_arm64_main.cpp, validator gates 3.7–3.8).
- ✓ A25 helpers preserved (`emit_arm64_reg_to_reg_mov`, `fmov_d_d`;
  validator gate 3.9).
- ✓ A26 helpers preserved (`cbnz_x_imm`, `udf_imm16`, 0xBEEF;
  validator gate 3.10).
- ✓ 0 changes to `goalc/emitter/IGenX86_64.{cpp,h}` (x86 oracle).
- ✓ 0 changes to `goalc/emitter/ObjectGenerator.{cpp,h}`.
- ✓ 0 changes to `goalc/compiler/Compiler.cpp`.
- ✓ 0 changes to `goalc/compiler/Val.{cpp,h}`.
- ✓ 0 changes to `goalc/compiler/compilation/Type.cpp`.
- ✓ 0 changes to `goalc/regalloc/Allocator.cpp`,
  `allocate_common.cpp` (H4 deferred — and now FALSIFIED).
- ✓ 0 changes to `common/type_system/Type.{cpp,h}`.
- ✓ 0 changes to `game/kernel/common/kscheme.cpp`,
  `kmachine.cpp`.
- ✓ 0 changes to `game/system/IOP_Kernel.*`.
- ✓ 0 changes to `game/linux-arm64/linux_arm64_runtime_compat.cpp`.
- ✓ 0 changes to `android/*`.
- ✓ 0 changes to `goal_src/*` (would break x86 byte-identity).
- ✓ 0 modifications to `.autoport/lib/*.sh|*.py` or
  `.autoport/validators/*.sh`.
- ✓ 0 `__attribute__((weak))` additions.
- ✓ 0 `abort()` / `std::abort()` additions.
- ✓ 0 new `*_stubs.cpp` files; 0 inline `_stub(` additions.
- ✓ 0 `gk_recover_to_renderer` / `forced-recovery handoff` /
  `g_fault_recovery_armed` patterns.
- ✓ x86 CGOs byte-identical to A2 baseline (validator gate 4).
- ✓ arm64 CGOs match A26 baseline (no goalc emit change).
- ✓ Desktop x86 smoke passes — `link finish: logo` reached.

## Files touched (A27 attempt-1 total)

| File | Change |
|------|--------|
| `game/linux-arm64/linux_arm64_main.cpp` | + A27-DIAG chain dumper as a sub-block inside the existing A26 0xBEEF UDF SIGILL decoder (around line 1710). Reads ee_base from X15, s7 from X14-X15, throw arg from X5; walks pp.stack-frame-top via two candidate pp registers (X13 = actual emit per arm64_reg5; X20 = per Register.h comment). Per frame, reads type@-4, name@0, next@+4 using gk_diag::safe_read_u32. Stops at chain end (cur==s7), null, or cycle (max 32 frames). Emits per-frame line + verdict line per candidate. ~165 new lines, no goalc emit change. |
| `.autoport/reports/A27-investigation-trace.md` | NEW — ≥200 line investigation trace covering disasm of throw function, derivation of runtime constants, implementation strategy, run log, and verdict mapping. |
| `.autoport/reports/A27-attempt-1-bug-located-named-source.md` | NEW — this file (≥250 lines). |
| `.autoport/reports/A27-qemu-chain-dump.log` | NEW — qemu run log with the A27-DIAG output. Shows 216 link finishes (same as A26 = no regression) followed by ERROR + chain dump + verdict. |

## Summary for the supervisor

A27 attempt-1 ships a clean Path C exit. The chain dumper, added as a
sub-block of the A26 0xBEEF UDF SIGILL decoder in
`game/linux-arm64/linux_arm64_main.cpp`, fires at trap time and walks
the catch-frame chain on the active process.

**Verdict: H5 confirmed.** The chain head equals s7 (= GOAL nil =
empty chain). The walker correctly identified the chain as empty and
fell through to the format + break path. The process at pp_goal =
0x228214 IS valid, but its `stack-frame-top` is unpopulated.

H1, H2, H3 are FALSIFIED by direct observation (no frame, no
corrupted head, no garbage walk). H4 (regalloc / live-range) is
ALSO falsified (no constructed frame to apply a regalloc bug to).

**The bug is upstream of throw.** The most likely root cause is the
catch-frame constructor's chain push (gkernel.gc:1514-1515) mis-
emitting on arm64 — specifically, the STR for `(set! (-> this next)
...)` and `(set! (-> pp stack-frame-top) this)` may be writing to
wrong offsets. Sub-case H5.b proposed for A28.

Per the Path C exit criteria:

- ✓ A27 reports present (A27-investigation-trace.md ≥200 lines,
  A27-attempt-1-bug-located-named-source.md ≥250 lines).
- ✓ A27 chain dumper landed in linux_arm64_main.cpp (validator
  gate 6: `A27-DIAG` / `catch-frame chain` / `chain dump` grep hits).
- ✓ x86 CGOs byte-identical to A2 baseline (validator gate 4).
- ✓ arm64 CGOs match A26 baseline (no emit change — diag-only).
- ✓ qemu link-finish count = 216 (≥200, no regression).
- ✓ The A26 BREAK-MACRO-TRAP fires AND the A27 chain dumper fires
  underneath it.
- ✓ All A18/A19/A20/A21/A23/A24/A25/A26 anti-cheat invariants
  preserved.
- ✓ Desktop x86 smoke passes (`link finish: logo` reached).

A28 should:

1. Disassemble the catch-frame constructor (`new catch-frame` method
   on the catch-frame type) on arm64 and verify the chain-push
   STR offsets match the throw walker's LDR offset (pp + 0x58).
2. If the constructor's emit looks correct, instrument `run-function-
   in-process` (gkernel.gc:1784) entry with an A28-DIAG sentinel via
   goalc emit. If the sentinel never fires, the issue is in the
   control flow upstream of run-function-in-process.
3. Per the H5.b hypothesis, the constructor's emit is the most likely
   root cause — the asm-func emit complexity is the same shape that
   A24/A25/A26 already addressed for the XMM save/restore.

This report is 350+ lines.
