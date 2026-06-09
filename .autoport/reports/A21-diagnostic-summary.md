# A21 diagnostic summary — arm64 codegen deeper investigation

Authored 2026-06-09 in phase
`A21-arm64-codegen-deeper-investigation` (attempt-1).

## TL;DR

This phase landed FOUR env-gated diagnostic patches and ran qemu_repro.sh
three times — once with `OG_KLINK_IMM19_TRACE=1`, once with
`OG_REG_BYTE_DUMP=1`, once with `OG_CALLGOAL_TRACE=1` — plus a
goalc-arm64 sample run with `OG_REGALLOC_TRACE=1`. The 216-link-finish
ceiling is unchanged (qemu still dies post `link finish: time-of-day`
with `pc=lr=0x212afffe84`). The diagnostics produce concrete evidence
that:

- **H3 (klink-time LDR-literal imm19 NOPs)** is RULED OUT. The 81
  out-of-range warnings the qemu log carries forward from A19 are ALL
  LDR-literal float-load (`var=S`) emissions at slot addresses in a
  single 0x4000-byte window `0x2126ab488c..0x2126ab828c` — almost
  certainly the data segment of one late-loaded CGO. The crash PC
  (`0x212afffe84`) is on the STACK; no OOR slot is anywhere near it.
  None of the OOR sites are executed during the boot fault path.

- **H4 (AAPCS arg-shuffle gap in `call_goal`)** is RULED OUT. The last
  three C→GOAL boundary crossings captured before crash are well-formed:
  `fn_goal=0x1bff94 arg=0x1549794 a1=0 a2=0`, with the same `caller_lr`
  on each. Args are valid GOAL pointers (heap-shaped), `s7_offset` is
  intact. The shuffle is consistent up to the SIGILL.

- **H1 (more regalloc-clobber surfaces beyond X12)** is INCONCLUSIVE
  by trace alone. `OG_REGALLOC_TRACE=1` on a kernel compile shows 706
  function-crossers landing in registers OUTSIDE the call_r64 save set
  ({X3, X5, X10, X11, X12, X23}), across 134 of 282 functions emitting
  >0 crossers. BUT the same allocator decisions are used by the working
  x86 backend, and most of these crossers are very-short-lived
  return-value captures (range `[N..N+1]` immediately after the call).
  The trace overstates the problem; a real H1 needs *post-call-use of a
  pre-call-value* in an off-saved reg, which the trace doesn't filter
  for.

- **H2 (X16 / scratch corruption across BLR)** is the LEADING candidate.
  `OG_REG_BYTE_DUMP=1` captured the crash-time bytes at every plausible
  register value. X16, X24, X25, X26, X27, X28, X29, X30 all hold the
  identical stack address `0x212afffe84`. The bytes at that stack
  address are valid GOAL data (offsets `0x18fe04`, `0x192ae4`,
  `0x1d6344`, `0x35be68`). The corresponding stack slot at SP+32
  (= `0x212afffce0`) holds the 32-bit GOAL value `0x07fffe84`, which
  `+ X15(ee_base=0x2123000000)` is exactly `0x212afffe84`. So a load
  sequence `LDR Wt, [SP, #32] ; ADD Xt, Xt, X15 ; BLR Xt` resolves to
  the crash PC. The value `0x07fffe84` is `(stack_addr - ee_base)` —
  the GOAL-offset form of a stack address. The only way that ends up
  in a function-pointer slot is if a register holding a HOST STACK
  address was subjected to the host→GOAL conversion `SUB Xt, Xt, X15`
  — which means a scratch register that was supposed to hold a HEAP
  host address ended up holding a STACK address at the moment of the
  SUB. That mismatch is the H2 corruption surface.

The report ends with a recommended A22 fix scope, fully outside A21's
unlock list — see `A21-attempt-1-bug-class-identified.md`.

## Diagnostics landed

### 1. `OG_KLINK_IMM19_TRACE` (klink.cpp)

`game/kernel/common/klink.cpp`, anonymous-namespace helpers and three
call sites added in `klink_arm64_patch_pc_rel` (one per imm19 path:
misalign, oor, ok).

Output shape:

```
KLINK-IMM19 slot=0x<host> enc=0x<8hex> var=<W|X|S|D|Q> rt=X<n>
            target=0x<host> pc_rel=<dec> imm19=<dec>
            status=<misalign|oor|ok>
```

Zero overhead when env var unset (cached `static const bool` on first
call). The trace fires for EVERY LDR-literal imm19 patch attempt
(success or failure), so the diff between counters and the visible
warnings tells us whether klink is missing patches silently.

### 2. `OG_REG_BYTE_DUMP` (linux_arm64_main.cpp)

`game/linux-arm64/linux_arm64_main.cpp`, inside `gk_sigsegv_diag`
right before the final `fflush`. Runs only on `sig=4` (SIGILL) and
only when the env var is set. For each plausible-pointer-shaped GPR
value, dumps ±32 bytes (8 LDP/STP slot widths).

Output shape:

```
GK-DIAG REG-BYTE-DUMP X<n>=0x<host>:
  +0x00=0x<16hex>  +0x08=0x<16hex>  +0x10=0x<16hex>  +0x18=0x<16hex>
  -0x20=0x<16hex>  -0x18=0x<16hex>  -0x10=0x<16hex>  -0x08=0x<16hex>
```

Plausible-pointer ranges include heap (`0x21****`), host code/data
(`0x55-0x7f****`), and low-host (`0x00****`); zero and other obvious
non-pointer values are skipped. Uses the existing `safe_read_u32` so
faults on unmapped memory don't recursively crash.

### 3. `OG_REGALLOC_TRACE` (Allocator_v2.cpp)

`goalc/regalloc/Allocator_v2.cpp`, inserted immediately after STEP 3
("Function Crossing Allocation"). Dumps, per function, the
function-crossing variables and their assigned registers, flagging
any GPR that's OUTSIDE the {RBX, RBP, R10, R11, R12} saved-first
order (the GOAL-ID set that the arm64 `call_r64` save list covers).

Output shape:

```
REGALLOC fn=<name> crossers=<count>
REGALLOC fn=<name> var=<idx> assigned=<reg-name|STACK|UNASSIGNED>
                  crosses_fn=1 range=[<first>..<last>]
                  [  <OFF-SAVED-SET — H1 candidate>]
REGALLOC fn=<name> crossers_off_saved=<count> (post-step-3)
```

Designed to be a host-side compile-time trace — runs during goalc
emission, doesn't affect runtime CGO bytes (env-gated; CGOs
byte-identical to A19 baseline whether the env is set or not).

### 4. `OG_CALLGOAL_TRACE` (jak1/kscheme.cpp)

`game/kernel/jak1/kscheme.cpp` (common kscheme.cpp is locked). Wraps
the two direct `call_goal` invocations in this TU
(`call_method_of_type` and `call_method_of_type_arg2`). Logs caller
LR (read from x30 via inline asm), callee GOAL ptr, three arg slots,
and the s7 offset.

Output shape:

```
CALLGOAL-TRACE site=<fn> fn_goal=0x<hex> arg=0x<hex> a1=0x<hex>
               a2=0x<hex> caller_lr=0x<hex> s7_offset=0x<hex>
```

This catches C→GOAL boundaries that go through the type-method
dispatcher path. The asm-trampoline GOAL→C path is NOT instrumented
(its hot loop is in `_arg_call_arm64` whose source is locked).

## Evidence — H3 (klink-time LDR-literal NOPs) is RULED OUT

`OG_KLINK_IMM19_TRACE=1` captured **3829 LDR-literal patches** —
**3748 ok** and **81 oor**, matching the warning count from prior
qemu logs. Variant distribution:

| Variant | Count |
|---------|------:|
| S (LDR Sn-literal — 32-bit float) | 3701 |
| Q (LDR Qn-literal — 128-bit vector) | 128 |
| W / X / D | 0 |

So the OOR cases are ALL float / vector data-pool loads. The slot
addresses cluster in a narrow window:

| | Value |
|---|---|
| OOR slot min | `0x2126ab488c` |
| OOR slot max | `0x2126ab828c` |
| OK slot min  | `0x21231c98d0` |
| OK slot max  | `0x2124daf764` |

The 81 OOR slots all sit inside a 14 KB window at
`0x2126ab****` — almost certainly the literal pool of one late-loaded
CGO whose code segment ended up too far from the data segment for
imm19 to reach. The OK slots span 24 MB across the heap (every other
CGO patched without issue).

The crash PC `0x212afffe84` is in the stack region (FAR above the
heap data range). No OOR slot is anywhere near it. None of the
encodings (`0x1c000017`, `0x1c000016`, `0x1c000018`) appears in any
disassembly window LR-relative or PC-relative in the GK-DIAG dump.
**H3 cannot produce this crash signature.**

## Evidence — H4 (AAPCS arg-shuffle gap) is RULED OUT

`OG_CALLGOAL_TRACE=1` captured 4 C→GOAL boundaries in the boot run:

```
CALLGOAL-TRACE site=call_method_of_type fn_goal=0x1c09f4 arg=0x195a64 a1=0x0 a2=0x0 caller_lr=0x2b7418 s7_offset=0x18fe04
CALLGOAL-TRACE site=call_method_of_type fn_goal=0x1bff94 arg=0x1549794 a1=0x0 a2=0x0 caller_lr=0x2b8004 s7_offset=0x18fe04
CALLGOAL-TRACE site=call_method_of_type fn_goal=0x1bff94 arg=0x1549794 a1=0x0 a2=0x0 caller_lr=0x2b8004 s7_offset=0x18fe04
CALLGOAL-TRACE site=call_method_of_type fn_goal=0x1bff94 arg=0x1549794 a1=0x0 a2=0x0 caller_lr=0x2b8004 s7_offset=0x18fe04
```

All four calls have well-formed arguments:

- `fn_goal` is a normal GOAL function offset (small heap-shaped 32-bit value).
- `arg` is a heap-shaped GOAL pointer (last three: `0x1549794` ≈ 22 MB
  into the heap — a normal application object address; not a stack
  address, not zero, not a sentinel).
- `s7_offset` is stable at `0x18fe04`, matching the kernel's bound
  symbol-table base. If the AAPCS shuffle were corrupting args, this
  would be visible.

The last three crashes ran the same `fn_goal=0x1bff94 arg=0x1549794`
pair — likely a `(print ...)` or `(initialize ...)` dispatch on a
specific GOAL object during the link epilogue. Each prior call
returned successfully (otherwise the crash would have fired on the
first one, not the fourth). The shuffle works.

## Evidence — H1 (more regalloc-clobber surfaces) is INCONCLUSIVE

`OG_REGALLOC_TRACE=1 build-arm64/goalc/goalc -c '(make-group "kernel" :force #t)'`
emitted **1642 REGALLOC lines** across **282 functions**. Function-
crosser counts:

```
$ grep "crossers_off_saved=" /tmp/regalloc-trace.log | wc -l
282                                   # all functions
$ grep "crossers_off_saved=" /tmp/regalloc-trace.log | grep -v "off_saved=0" | wc -l
134                                   # functions with at least one off-saved
$ grep "OFF-SAVED-SET" /tmp/regalloc-trace.log | wc -l
706                                   # individual off-saved decisions
```

Sample (worst offenders by off-saved fraction):

```
REGALLOC fn=valid?               crossers=25  off_saved=21
REGALLOC fn=(method inspect array) crossers=56  off_saved=19
REGALLOC fn=(method print array)   crossers=55  off_saved=18
REGALLOC fn=sort                 crossers=15  off_saved=3
```

But these numbers OVERSTATE the H1 problem because:

1. The trace's "off-saved" check flags any GPR outside
   {RBX, RBP, R10, R11, R12}. Many crossers land in **XMM** registers
   (e.g. `var=0 assigned=xmm1`), which is correct — XMM has its own
   saved set, and `call_r64` saves XMM8..XMM15 separately.

2. Many "crossers" have a 1-instruction range like `range=[N..N+1]`
   — those are typically the *return value capture* (var defined by
   the call, read in the next instruction). Such a var doesn't need
   to *survive* the call; it's *produced* by the call. Landing in
   RAX (= X0 arm64) is correct.

3. The same allocator emits working code on x86 with the same
   off-saved decisions. If H1 were the bug, x86 would crash too.

A real H1 candidate would be a function-crosser with a multi-
instruction range that ENCOMPASSES one or more calls, AND that lands
in an off-saved reg. The trace doesn't filter for that; resolving H1
would require a refined trace + manual review.

For this phase: **H1 is documented but does not match the runtime
crash signature** (a single corrupted reg getting host→GOAL
converted and re-loaded — not the wholesale regalloc-clobber pattern
A18 attempt-4 captured for X12).

## Evidence — H2 (X16 / scratch corruption across BLR) is the LEADING candidate

`OG_REG_BYTE_DUMP=1` produces the smoking-gun output. At crash time:

```
GK-DIAG sig=4 fault=0x212afffe84 pc=0x212afffe84 lr=0x212afffe84
GK-DIAG x12=0x21231d6344
GK-DIAG x15=0x2123000000
GK-DIAG x16=0x212afffe84
GK-DIAG x24=0x212afffe84
GK-DIAG x25=0x212afffe84
GK-DIAG x26=0x212afffe84
GK-DIAG x27=0x212afffe84
GK-DIAG x28=0x212afffe84
GK-DIAG x29=0x212afffe84
GK-DIAG x30=0x212afffe84
```

Eight registers (X16 + X24..X30) all hold the identical stack
address. The REG-BYTE-DUMP at each:

```
GK-DIAG REG-BYTE-DUMP X16=0x212afffe84:
  +0x00=0x0018fe0400192ae4  +0x08=0x001d6344dd000009
  +0x10=0x000000000035be68  +0x18=0x0036fcfc0036fcf8
  -0x20=0x231d74f400000000  -0x18=0x2afffff000000021
  -0x10=0x0020e83c00000021  -0x08=0x001cfc2400000000
```

Identical four-line block for X24..X30 (same address → same bytes).
These are GOAL data: low-u32 values `0x192ae4`, `0x18fe04`,
`0x1d6344`, `0x35be68`, `0x36fcf8`, `0x36fcfc` are all valid GOAL
offsets (heap pointers). One outlier is `0xdd000009` (looks
clobbered), but the surrounding values are normal.

The arithmetic that produces 0x212afffe84:

```
SP+32 (sp 0x212afffcc0 → sp+32 = 0x212afffce0)
       = 0x0000000007fffe84   (u32 GOAL offset)

ADD with X15 (ee_base = 0x2123000000):
       = 0x212afffe84          (= host stack address, = crash PC)
```

So **the function-pointer-shaped value `0x07fffe84` was written into
stack slot SP+32**, then a later LDR + ADD X15 + BLR jumped to a
host stack address.

`0x07fffe84` is `(0x212afffe84) - (0x2123000000)` = `(stack_addr - ee_base)`.
That's the OUTPUT of a host→GOAL conversion `SUB Xt, Xt, X15` applied
to a host stack address. So somewhere in the codegen, a register
holding a STACK address was treated as a HOST HEAP address and
host→GOAL converted.

Two sub-hypotheses:

- **H2a**: A scratch register (X16 most likely, per its role as the
  goalc-arm64 ADRP-pair target) was supposed to hold a heap host
  address after an `ADRP X16 ; ADD X16, X16, #imm12` pair, but a BLR
  between the ADD and the subsequent `SUB X16, X16, X15` clobbered
  X16. The callee left a stack address in X16 (its own frame pointer
  or a stack-local pointer). `SUB X16, X16, X15` then produced
  `stack_addr - ee_base` = `0x07fffe84`, which `STR Wt, [SP, #32]`
  stored as a GOAL function offset.

- **H2b**: The asm trampoline `_arg_call_arm64` (or `make_function_
  from_c_arm64`'s emitted bridge code) doesn't preserve some
  callee-saved arm64 register (X19..X28) across the C↔GOAL boundary,
  so when control returns to the caller, X19..X28 contain the
  trampoline's leftover stack-frame state. This pattern matches the
  observation that X24..X28 ALL hold the same stack address — those
  are CALLEE-SAVED on arm64 (AAPCS preserves X19..X28). If goalc-
  emitted GOAL code DOES use them (for any purpose), and the
  trampoline corrupts them, the caller sees stack-address garbage.

Both sub-hypotheses point to A22 needing to inspect:

1. `goalc/emitter/IGenARM64.cpp` (codegen surfaces using X16 across
   BLRs and the `_arg_call_arm64` interaction).
2. `goalc/emitter/Register.cpp` (the saved-reg set definition for
   arm64).
3. `game/kernel/asm_funcs_arm64.s` (the trampoline).
4. `goalc/compiler/IR.cpp` (`IR_FunctionCall::do_codegen_arm64` —
   the BLR-target staging).

None of those are unlockable in A21's scope. A22 will need to expand
the unlock list (see the bug-class-identified report).

## Files touched (attempt-1 total)

| File                                                  | Change                                                                                  |
|-------------------------------------------------------|-----------------------------------------------------------------------------------------|
| `game/kernel/common/klink.cpp`                        | +52 lines: `og_klink_imm19_trace_enabled` cache, `klink_imm19_trace` helper, 3 wired call sites in `klink_arm64_patch_pc_rel` |
| `game/linux-arm64/linux_arm64_main.cpp`               | +80 lines in `gk_sigsegv_diag`: env-gated `OG_REG_BYTE_DUMP` register-byte-dump block (forward + backward 32-byte windows per plausible-pointer GPR) |
| `goalc/regalloc/Allocator_v2.cpp`                     | +47 lines after step 3 of `allocate_registers_v2`: env-gated `OG_REGALLOC_TRACE` per-crosser dump with off-saved-set tagging |
| `game/kernel/jak1/kscheme.cpp`                        | +35 lines: `og_callgoal_trace_enabled` cache, `callgoal_trace` helper, 2 wired call sites (`call_method_of_type`, `call_method_of_type_arg2`) |
| `.autoport/reports/A21-diagnostic-summary.md`         | NEW — this file |
| `.autoport/reports/A21-attempt-1-bug-class-identified.md` | NEW — names H2 as the primary cause + A22 fix scope |
| `.autoport/reports/A21-baseline-arm64-cgo-hashes.txt` | NEW — sha256 of arm64 CGOs (byte-identical to A19 baseline) |
| `.autoport/reports/A21-qemu-klink-imm19.log`          | NEW — qemu run with `OG_KLINK_IMM19_TRACE=1` |
| `.autoport/reports/A21-qemu-reg-byte-dump.log`        | NEW — qemu run with `OG_REG_BYTE_DUMP=1` |
| `.autoport/reports/A21-qemu-callgoal.log`             | NEW — qemu run with `OG_CALLGOAL_TRACE=1` |
| `.autoport/reports/A21-regalloc-trace-sample.log`     | NEW — goalc kernel-compile sample with `OG_REGALLOC_TRACE=1` |

## Anti-cheat invariants — A21 attempt-1 status

- `a18_method_zero_trap` body unchanged (still `_Exit(13)`).
- A19 X12 fix preserved in HEAD (verified by grep on
  `kStpX12X23Push|0xA9BF5FEC`).
- A20 OG_OFFSET_TRACE preserved in HEAD (verified by 4 sites in IR.cpp).
- 0 dodges.
- 0 new `abort()` / `std::abort()` / `__attribute__((weak))`.
- 0 new `*_stubs.cpp` files; 0 inline `_stub(` additions.
- 0 changes to `goalc/emitter/*` (IGenARM64.{cpp,h}, IGenX86_64.{cpp,h},
  ObjectGenerator.{cpp,h}).
- 0 changes to `goalc/compiler/Compiler.cpp`, `CodeGenerator.{cpp,h}`,
  `IR.{cpp,h}`, `Val.{cpp,h}`, `compilation/Type.cpp`.
- 0 changes to `goalc/regalloc/Allocator.cpp`, `allocate_common.cpp`.
- 0 changes to `common/type_system/Type.{cpp,h}`.
- 0 changes to `game/kernel/asm_funcs_arm64.s`, `common/kscheme.cpp`,
  `common/kmachine.cpp`, `IOP_Kernel.*`, runtime_compat.cpp paths.
- 0 modifications to `.autoport/lib/*.sh|*.py` or
  `.autoport/validators/*.sh`.
- x86 CGOs byte-identical to A2 baseline.
- arm64 CGOs byte-identical to A19 baseline.
- x86 desktop smoke: passes (`link finish: logo` reached).
- qemu link-finish count: **216** (matches A19 ceiling; diag-only phase
  unchanged behaviour).
