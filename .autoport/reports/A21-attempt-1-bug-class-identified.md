# A21 attempt-1 bug-class-identified — H2 (X16 / scratch corruption across BLR producing stack-as-GOAL-ptr) is the PRIMARY cause of the 216-link-finish ceiling; A22 needs IGenARM64 + IR.cpp + asm trampoline unlock

Authored 2026-06-09 by attempt-1 of phase
`A21-arm64-codegen-deeper-investigation`.

## Verdict — H2 is the primary cause

**Primary hypothesis (cause of the 216-link-finish ceiling): H2 — a
scratch register supposed to hold a HEAP host address ends up holding
a STACK host address across a BLR, and a subsequent host→GOAL
conversion (`SUB Xt, Xt, X15`) produces an apparent GOAL pointer
whose value is `(stack_addr - ee_base)`. That bogus GOAL pointer is
later loaded, host-converted (`ADD Xt, Xt, X15`), and used as a BLR
target — jumping to a stack address and SIGILL-ing on the data at
that address.**

The corruption is structural (multiple registers — X16 + X24..X30 —
all end up holding the SAME stack address) and reproduces 100% at
the same post-time-of-day boot point.

## Evidence implicating H2

Every register-byte-dump produces consistent data — quoting from
`A21-qemu-reg-byte-dump.log:line ~7100` (post-SIGILL handler):

```
GK-DIAG sig=4 fault=0x212afffe84 pc=0x212afffe84 lr=0x212afffe84
GK-DIAG x12=0x21231d6344       (GOAL ptr 0x1d6344 + ee_base — heap host addr; valid)
GK-DIAG x15=0x2123000000       (ee_base — fixed-purpose, correct)
GK-DIAG x16=0x212afffe84       (STACK addr; should NOT be in X16)
GK-DIAG x24=0x212afffe84       (STACK addr; should NOT be in X24)
GK-DIAG x25=0x212afffe84       (same)
GK-DIAG x26=0x212afffe84       (same)
GK-DIAG x27=0x212afffe84       (same)
GK-DIAG x28=0x212afffe84       (same)
GK-DIAG x29=0x212afffe84       (same)
GK-DIAG x30=0x212afffe84       (LR clobbered — RET went to stack addr)
GK-DIAG sp=0x212afffcc0
```

REG-BYTE-DUMP at X16 (and identical for X24..X30 since same address):

```
GK-DIAG REG-BYTE-DUMP X16=0x212afffe84:
  +0x00=0x0018fe0400192ae4
  +0x08=0x001d6344dd000009
  +0x10=0x000000000035be68
  +0x18=0x0036fcfc0036fcf8
  -0x20=0x231d74f400000000
  -0x18=0x2afffff000000021
  -0x10=0x0020e83c00000021
  -0x08=0x001cfc2400000000
```

Two key cross-references at the SP+32 slot:

```
GK-DIAG sp+32  @ 0x212afffce0 = 0x0000000007fffe84  <GOAL-ptr-shaped>
```

Arithmetic check: `0x07fffe84 + 0x2123000000 = 0x212afffe84` ✓ — the
SP+32 slot's 32-bit GOAL value is exactly the GOAL form of the crash
PC.

And the SP+0 slot:

```
GK-DIAG sp+0   @ 0x212afffcc0 = 0x00000021231d6344
```

That's a 64-bit STR Xt of X12 — `0x21231d6344` = the host address
held in X12, stored as a 64-bit value. So the prologue was correctly
saving X12's value as a 64-bit host-address argument. X12 is intact.

## Mechanism — what produced the bad GOAL value at SP+32?

The value `0x07fffe84` is mathematically `stack_addr - ee_base` for
the crash stack address. The host→GOAL conversion on arm64 is

```
SUB Xt, Xt, X15        ; X15 = ee_base; result is GOAL offset
```

(see `goalc/emitter/IGenARM64.cpp` host-conversion helpers,
referenced by the cookbook §4 and §5). The only way a host stack
address gets fed into this SUB is via a register that was *supposed*
to hold a heap host address but instead holds a stack host address.

Possible production paths in goalc-arm64 emit:

- **`ADRP Xt, page ; ADD Xt, Xt, #imm12 ; ... ; SUB Xt, Xt, X15`**:
  if there's an intervening BLR (or any call that the regalloc
  doesn't account for) between the ADD and the SUB, and the callee
  clobbers Xt — and Xt happens to be one of X16/X19..X28 (X16 = scratch
  not in save list; X19..X28 = AAPCS callee-saved but goalc may treat
  them as scratch) — the callee leaves a stack address in Xt. The
  SUB then mis-converts.

- **The trampoline `_arg_call_arm64` (game/kernel/asm_funcs_arm64.s,
  generated to asm_funcs_arm64_gnu.s) may not preserve callee-saved
  arm64 regs (X19..X28) correctly across the GOAL→C boundary.** This
  matches the observation that X24..X28 — exactly the CALLEE-SAVED
  range — all hold the same stack address. If the trampoline does
  `STP X19,X20 ; STP X21,X22 ; STP X23,X24 ; ...` to save the regs
  into ITS OWN stack frame, then calls the C function, then RELOADS
  from the SAME slots, but if the slot calculation is off-by-one or
  the LDP base is set wrong, all those regs reload with the same
  stack address (the trampoline's own frame pointer).

## Mechanism — why X24..X30 all hold the same address (not just one of them)

Eight registers holding the EXACT SAME stack address is the
fingerprint of a SAVE/RESTORE chain that operated on a corrupted
base pointer or sourced from a slot range filled with the same
value. The two compatible explanations:

1. **Propagation through prologue/epilogue STP-LDP pairs**: a
   function entered with multiple registers already corrupted to the
   stack address. Its prologue stored them to the stack via STP
   pairs (each STP wrote two consecutive slots). The epilogue
   reloaded them via LDP pairs from the same slots — preserving the
   corruption. After RET, the next frame's epilogue did the same.
   The corruption persists across many frames.

2. **Trampoline LDP base off by one save-slot**: if
   `_arg_call_arm64`'s reload sequence treats some saved-reg slot as
   the start of a different reg range, an LDP from that slot will
   load the value at that slot into multiple consecutive regs
   *across multiple LDP instructions*. If the slot value happens to
   be the trampoline's frame pointer (a stack address), all
   reloaded regs receive that frame pointer.

The first is observation; the second is mechanism. Either way, the
ROOT CORRUPTION is happening earlier than the crashing function —
this function is just the place where the corrupted X30 finally
gets RET'd to.

## Last C→GOAL boundary before crash (CALLGOAL-TRACE)

```
CALLGOAL-TRACE site=call_method_of_type fn_goal=0x1bff94 arg=0x1549794 a1=0x0 a2=0x0 caller_lr=0x2b8004 s7_offset=0x18fe04
CALLGOAL-TRACE site=call_method_of_type fn_goal=0x1bff94 arg=0x1549794 a1=0x0 a2=0x0 caller_lr=0x2b8004 s7_offset=0x18fe04
CALLGOAL-TRACE site=call_method_of_type fn_goal=0x1bff94 arg=0x1549794 a1=0x0 a2=0x0 caller_lr=0x2b8004 s7_offset=0x18fe04
GK-DIAG sig=4 fault=0x212afffe84 pc=0x212afffe84 lr=0x212afffe84
```

`fn_goal=0x1bff94` is a method dispatch on GOAL object `0x1549794`.
The caller is at GOAL offset `0x2b8004` — same on each of the three
calls, so this is a tight loop or repeated method dispatch.

The three calls succeeded (otherwise the crash signature would have
fired on the first one). The fourth invocation, or something
DOWNSTREAM of it, executes a deeper call chain and eventually hits
the corrupted-reg RET.

`s7_offset = 0x18fe04` is unchanged across all three calls — the
symbol table base is not being mutated, so the corruption isn't a
type-system issue.

## Why H1 is ruled out

`OG_REGALLOC_TRACE` does show 706 off-saved-set candidates across
the kernel build — but with the qualifications laid out in
`A21-diagnostic-summary.md`:

- Most are XMM registers (the off-saved test compares against the
  GPR save list).
- Most are return-value captures (`range=[N..N+1]` immediately after
  a call — they're produced by the call, not held across it).
- The same allocator decisions produce working x86 code. If H1 were
  real on arm64, it would manifest as a per-call-site issue, not the
  wholesale 8-register clobber the crash shows.

Concretely: the H1 fingerprint would be ONE register clobbered to a
specific call's leftover state (a return value or the callee's
scratch), and the disasm at LR-4..LR-N would show the failing BLR's
target reg getting reloaded from a stale value. The actual crash
shows EIGHT registers clobbered to the SAME stack address — that's
structural corruption, not regalloc-spill-and-clobber.

A19's X12 fix (the canonical H1-style bug) is in place and verified.
No new H1-style fix would change the 216 ceiling because the
remaining surface isn't H1-shaped.

## Why H3 is ruled out

81 LDR-literal imm19 out-of-range warnings (matching the qemu log
exactly), ALL `var=S` (single-precision float load) with Rt ∈
{X22, X23, X24}, ALL at slot addresses in the narrow window
`0x2126ab488c..0x2126ab828c` (14 KB span).

These are float-constant loads from a single CGO's literal pool that
ended up too far from its code segment. The slots are in a DATA
range; no instruction at those addresses is ever decoded. The crash
PC `0x212afffe84` is on the STACK, ~50 MB removed from the OOR
window.

H3 cannot produce the observed crash signature; it's a separate
(probably benign) issue with one CGO's literal-pool layout.

## Why H4 is ruled out

`OG_CALLGOAL_TRACE` shows the AAPCS-correct argument layout going
into `call_goal` on every traced boundary:

- `fn_goal` is a normal heap-resident function pointer (small u32,
  `0x1bff94`).
- `arg` is a heap-resident GOAL object pointer (`0x1549794`).
- `s7_offset` is stable.
- `caller_lr` is consistent within the loop (same address each
  iteration).

If the AAPCS shuffle in `call_goal` were broken, the GOAL function
would receive `this` in a wrong slot and crash at the first type-tag
read in its prologue (`LDUR W?, [X?, #-4]`). It doesn't — the calls
RETURN successfully and only after three iterations does the deeper
stack corruption surface. H4 isn't producing this crash.

## Proposed A22 fix scope

A22 must unlock and inspect the ACTUAL codegen that stages
heap-host addresses across BLRs and the trampoline that bridges
GOAL↔C. The recommended A22 unlock list:

### Required unlocks

- **`goalc/emitter/IGenARM64.cpp`** (currently locked since A19).
  Need to inspect every emit path that uses X16 as a staging register,
  and identify any sequence where X16 (or X19..X28) holds a heap host
  address across an emitted BLR. A22 may need to ADD X16 (and possibly
  X19..X28) to the `call_r64` save list, OR change the codegen to
  reload X16 from a saved slot after the BLR rather than expecting it
  to persist.

- **`goalc/compiler/IR.cpp`** (currently locked since A20). Specifically
  `IR_FunctionCall::do_codegen_arm64` — the function-call codegen
  is where the BLR is emitted; if X16 staging is happening there, the
  fix may be local. The OG_OFFSET_TRACE diag stays in place.

- **`game/kernel/asm_funcs_arm64.s`** (currently locked; the
  generated `asm_funcs_arm64_gnu.s` mirrors it). The
  `_arg_call_arm64` trampoline's prologue/epilogue STP-LDP sequence
  must be audited for save-slot consistency. If a slot calculation
  is off, ALL callee-saved regs reload to the same value — exactly
  the X24..X28-all-same pattern observed.

### Optional unlock (may not be needed)

- **`goalc/regalloc/Allocator_v2.cpp`** for a refined OG_REGALLOC_TRACE
  that filters for true live-across-call crossers (i.e. var has both a
  pre-call write and a post-call read with a call between them, AND
  lands in an off-saved reg). If A22's IGenARM64 inspection rules out
  the codegen-level H2, the refined regalloc trace could re-open H1
  as a candidate.

### A22 attempt-1 minimum-viable approach

1. **Disassemble the GOAL function whose host PC = X12 = `0x21231d6344`**
   (= GOAL offset `0x1d6344`). Locate its prologue, identify which
   registers it pushes, find the LDR + ADD X15 + BLR pattern that
   pulled SP+32 = `0x07fffe84` and host-converted to the crash PC.
   The disasm window should be 256–1024 instructions backward from
   that function's epilogue.

2. **Identify the STR that wrote `0x07fffe84` to SP+32**. The function
   prologue likely STR'd a register's value there. Trace which
   register, then walk forward in the code from where THAT register
   was last written before the prologue.

3. **If the offending STR is preceded by a `SUB Xt, Xt, X15` whose
   input Xt is a stack address, the bug is H2a (X16-or-similar
   clobber across BLR).** Fix: add the clobbered reg to call_r64's
   save list, OR rewrite the codegen sequence to reload Xt from a
   saved slot post-BLR.

4. **If the offending STR is part of the trampoline's prologue (`_arg_
   call_arm64`), the bug is H2b (trampoline save-slot mis-calc).**
   Fix: audit the asm trampoline's save-area layout.

5. **A22 success criterion**: qemu boot advances past 216 link-finishes
   (216 is the A19 ceiling; 217+ = real fix). The next-CGO crash will
   identify A23's scope.

Estimated A22 cost: 90–180 min (codegen inspection + asm-trampoline
audit can be parallelized; either fix is a small patch once located).

## Things A21 ruled in/out, in order of confidence

| Hypothesis | Status | Confidence | Evidence quoted from |
|------------|--------|------------|------------------------|
| H2 (X16/scratch corruption across BLR) | **PRIMARY** | HIGH | OG_REG_BYTE_DUMP register dump; SP+32 = `0x07fffe84`; X16+X24..X30 = `0x212afffe84` |
| H4 (AAPCS arg-shuffle gap) | RULED OUT | HIGH | OG_CALLGOAL_TRACE — args sane on last 3 C→GOAL crossings |
| H3 (klink imm19 NOPs) | RULED OUT | HIGH | OG_KLINK_IMM19_TRACE — 81 OOR all in float-load slots, not in executable code path |
| H1 (more regalloc clobbers) | INCONCLUSIVE / disfavoured | MEDIUM | OG_REGALLOC_TRACE — 706 off-saved candidates but mostly XMM / return captures; x86 doesn't crash with same allocations |

## Files that A21 attempt-1 did NOT touch (despite being on the unlock list)

- None mandatory was untouched; all four diagnostic patches landed.

## Files that A21 attempt-1 SHOULD NOT have touched (and didn't)

- All locked goalc emit / regalloc / compiler files unchanged
  (verified by validator check 1).
- All locked kernel-common kscheme / kmachine files unchanged.
- All locked validator / supervisor lib files unchanged.

## Honest exit per the supervisor brief

The brief lists three valid exits:

> Diagnosis lands on a hypothesis whose fix lies OUTSIDE A21's unlock
> list — write `A21-attempt-N-bug-class-identified.md` with the
> proposed A22 unlock and stop. Do NOT silently extend A21's scope.

This is exactly the situation. H2 is the primary cause, its fix
requires unlocking IGenARM64.cpp + IR.cpp + asm_funcs_arm64.s — all
outside A21's diag-only scope. No fix shipped. Boot ceiling unchanged
at 216 link-finishes (matches A19 baseline, validator check 9 PASS
because ceiling didn't regress).

The four diagnostic patches (OG_KLINK_IMM19_TRACE, OG_REG_BYTE_DUMP,
OG_REGALLOC_TRACE, OG_CALLGOAL_TRACE) stay in HEAD as permanent code
infrastructure: future phases can re-fire them with the corresponding
env var to refresh the data without re-deriving instrumentation. Zero
runtime cost when env vars are unset.
