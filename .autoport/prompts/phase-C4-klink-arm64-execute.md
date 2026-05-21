# Phase C4 — klink arm64 ADRP+ADD fixups + gcommon executes under qemu

## What this phase delivers

A **runnable** aarch64-linux gk that, under `qemu-aarch64-static`,
goes one step beyond C3: re-enables `LINK_FLAG_EXECUTE` in the
KERNEL.CGO load, and **gcommon's top-level GOAL function actually
runs without SIGILL**. This requires fixing the bug C3 surfaced:
`game/kernel/common/klink.cpp`'s relocators write patches as raw u32
stores, but arm64 ADRP+ADD instructions have non-byte-aligned
imm21/imm12 fields. A4 taught `goalc/emitter/ObjectGenerator` to
patch them at compile time. C4 teaches `klink` to patch them at
runtime.

After C4: NumSymbols rises further (gcommon's top-level allocates
GOAL types + interns more symbols via `make-function-symbol-table`
etc.), the run still exits 0, and the boot log shows post-link
GOAL-side activity. Bucket D (Android port) inherits a working
runtime linker.

## Why this matters

Without C4, the arm64 CGOs are *loadable but unrunnable*. Bucket D
would hit this exact SIGILL the moment KERNEL.CGO links and the
runtime tries to call gcommon's top-level on Android. Better to fix
the runtime linker here, in the controlled qemu environment with the
oracle trace as the ground truth, than to discover it deep in bucket
D with the Bionic + GLES surface mixed in.

## Engineering background (from C3's discovery)

C3 attempted to flip `LINK_FLAG_EXECUTE` on. The qemu run SIGILLed
partway through gcommon's top-level GOAL function. Trace pinpointed
the failing instruction. The original goalc-arm64-emitted pattern
was:

```
   adrp x9, <symbol_page>
   add  x9, x9, #<symbol_offset_within_page>
   sub  x9, x9, x15                ; normalise via offset_reg
   str  w9, [x14]                  ; store GOAL pointer
```

After klink's u32 store-based relocator patched it, the bytes
became:

```
   c: fc40a504  ldr d4, [x8], #10     ; was ADRP x9, 0
  10: fc40a500  ldr d0, [x8], #10     ; was ADD x9, x9, #0
  14: cb0f0129  sub x9, x9, x15       ; unchanged (no reloc here)
  18: 00005c30  udf #23600            ; was STR w9, [x14]
```

The raw u32 store wrote the relocation target into the entire
4-byte slot, blowing the opcode bits and turning the instructions
into LDR-imm-post-index / UDF garbage. The fix is the same as A4
applied for ObjectGenerator: switch from `*p32 = value` to
"decode the kind of instruction at the patch site, mask + OR the
appropriate imm bits."

## Concrete deliverables

### 1. klink relocator widening

Edit `game/kernel/common/klink.cpp` (the four relocator functions:
`cross_seg_dist_link_v3`, `ptr_link_v3`, `symlink_v3`,
`typelink_v3`) so each one:

- Recognises the arm64 instruction at the patch site by sniffing
  the top bits of the u32 already there (10010xxx = ADRP/ADR,
  1001000x = ADD imm12, 11111000010 = LDR-imm12-unscaled, etc.).
- For ADRP: split the 21-bit page-delta into immhi (bits 23:5) and
  immlo (bits 30:29), mask + OR into the original instruction word.
- For ADD imm12 / LDR imm12 / STR imm12: mask the bottom 12 bits of
  the patch value into bits 21:10 of the instruction word.
- For pre-existing raw u32 stores (the GOAL pointer-to-pointer
  relocs that ALL backends share): keep the existing path — these
  are GOAL data words, not arm64 instructions.

The discrimination happens at runtime in klink. There's no
compile-time flag distinguishing "this slot is a u32 data store" vs
"this slot is an arm64 instruction immediate" — klink already has
the LINK_TABLE entry kind, and the entry kind plus the high bits of
the slot value are sufficient to disambiguate.

### 2. Re-enable LINK_FLAG_EXECUTE

In `game/linux-arm64/linux_arm64_main.cpp`, change the link flags
from `LINK_FLAG_OUTPUT_LOAD | LINK_FLAG_PRINT_LOGIN` to
`LINK_FLAG_OUTPUT_LOAD | LINK_FLAG_EXECUTE | LINK_FLAG_PRINT_LOGIN`.

C3 had this explicitly forbidden by anti-cheat. C4's validator
inverts that check: LINK_FLAG_EXECUTE **must** be set.

### 3. c4_run.sh — qemu run with EXECUTE on

`.autoport/lib/c4_run.sh` is a clone of c3_run.sh with the bumped
flags. Produces:

- `.autoport/reports/C4-boot.log` — qemu stdout
- `.autoport/reports/C4-exit.txt` — qemu exit code (must be 0)

### 4. Post-execute markers

The boot log must contain:

- All 8 `link finish: <name>` markers (carried over from C3)
- `linux-arm64: C4 KERNEL.CGO execute complete (NumSymbols=N, post-execute-delta=+M)`
  — claude inserts this from `linux_arm64_main.cpp` after the link-
  and-exec call returns. N must exceed 500 (gcommon's top-level
  allocates type slots + interns symbols beyond C3's static-link
  count of 317).
- **No SIGILL / SIGSEGV / abort markers anywhere in the log.**

### 5. Markdown report

`.autoport/reports/C4-execute.md` documents:
- The 4 klink relocator changes (cite line numbers)
- NumSymbols before/after (317 → ?)
- Top 5 instruction-kind dispatches the new code path handled
  (e.g., "ADRP: 47 patches, ADD imm12: 47, LDR imm12: 12, …")
- Whether any klink dispatch hit a not-yet-handled instruction
  (must be zero — the dispatcher aborts on unknown kinds, not
  silently no-ops)

### 6. C3 boot-log preservation

`.autoport/reports/C3-boot.log` must remain byte-identical (claude
shouldn't accidentally re-run c3_run.sh and overwrite it). The
validator checks this hash against C3's commit.

## Anti-cheat constraints

1. **Touchable files** (a deliberate widening of the codegen-lock):
   - `game/kernel/common/klink.cpp` — the runtime relocator (4
     functions). This is the ONE legitimate exception to the
     codegen-lock since A4; document it in the commit message.
   - `game/linux-arm64/linux_arm64_main.cpp` — flags change.
   - `.autoport/lib/c4_run.sh` — new.
   - `.autoport/reports/C4-*` — new.

2. **Untouchable files** (still locked):
   - `goalc/compiler/IR.cpp`
   - `goalc/emitter/IGenARM64.{cpp,h}`
   - `goalc/emitter/ObjectGenerator.{cpp,h}`
   - `goalc/compiler/CodeGenerator.{cpp,h}`
   - `.autoport/lib/classify_ir_arm64.py`
   - `out/jak1/iso/*.CGO` (the x86 oracle)
   The validator diffs each against its locked baseline.

3. **No signal-handler trickery.** A SIGILL during execution must
   abort the run (qemu exits non-zero). Wrapping the call in a
   sigaction that ignores SIGILL is forbidden — the validator
   would still see the qemu exit code, but additionally we grep
   for `signal\(.*SIGILL` and `sigaction.*SIGILL` in
   linux_arm64_main.cpp and reject if present.

4. **No silently disabling LINK_FLAG_EXECUTE for some objects.**
   The link flags must be a single constant applied uniformly to
   all 8 KERNEL.CGO objects. Per-object flag tweaks (e.g., "skip
   EXECUTE for gcommon but enable it for the rest") are forbidden.
   Validator greps for any conditional `LINK_FLAG_EXECUTE`
   reference besides the one constant assignment.

5. **No NumSymbols rigging.** The boot log's
   `NumSymbols=N` value must come from the live runtime via a
   `SymbolTable::size()` (or equivalent) call after link-and-exec.
   Hard-coded values in linux_arm64_main.cpp are forbidden;
   validator greps for literal "NumSymbols=" string in the source.

6. **The kStateSeq / weak_jak1_ / engine: state= patterns remain
   absolutely forbidden everywhere** (same as A4 onward).

## Files you will create / modify

| Path | Purpose |
|---|---|
| `game/kernel/common/klink.cpp` | extend 4 relocator fns with arm64 instr-aware patching |
| `game/linux-arm64/linux_arm64_main.cpp` | enable LINK_FLAG_EXECUTE; add post-execute log |
| `.autoport/lib/c4_run.sh` | qemu run driver with EXECUTE flags |
| `.autoport/reports/C4-boot.log` | qemu stdout |
| `.autoport/reports/C4-exit.txt` | qemu exit code |
| `.autoport/reports/C4-execute.md` | engineering report (klink changes, NumSymbols, kind histogram) |

## Pitfalls

- **The 4 relocator functions in klink.cpp are not identical** —
  each handles a slightly different relocation kind (cross-segment
  distance, pointer, symbol-link, type-link). The arm64-aware
  patching code should ideally be a shared helper called from all
  4, not 4 copies of the same logic.

- **klink runs on the EE main thread**. Adding heavy logic per
  relocation slows down link-time. There are tens of thousands of
  reloc entries across the 8 KERNEL.CGO objects. The
  instruction-kind dispatcher should be O(1) (a small switch on
  the high bits), not a loop or string compare.

- **ADRP's page-delta might exceed signed 21-bit range** for
  certain pathological CGOs (the link target's segment + the patch
  site's segment are >2 MB apart). The dispatcher must check and
  fail loudly on overflow rather than silently truncating —
  reporting "ADRP page-delta out of range" lets a future phase add
  a veneer rather than producing wrong code.

- **The LDR-literal pre-execute path** (used by IR_StaticVarLoad
  per A4's docs) writes a 19-bit immediate. A4 added that fixup at
  goalc emit time. klink should NOT see LDR-literal reloc entries
  for arm64-compiled code (goalc emitted them already). If C4
  hits an LDR-literal in klink, that's a goalc-arm64 emit-time
  bug, not a klink bug; the dispatcher should fail loudly.

- **NumSymbols delta should be positive but bounded.** Empirical
  expectation: gcommon's top-level interns ~100-200 new symbols
  (types like vector / matrix / quaternion / pair / list-h
  plus user-defined helpers). Floor at +200. Cap at +2000 (any
  more means the symbol table is being spammed, probably a loop
  bug).

## Reading list

- `.autoport/reports/C3-title.md` — claude's writeup of the bug
- `.autoport/reports/C3-boot.log` — the SIGILL-free relocate run
- C3 commit `7ed86d8a1` — the engineering finding section
- `game/kernel/common/klink.cpp` — the relocator functions to widen
- `goalc/emitter/ObjectGenerator.cpp` — A4's compile-time
  counterpart of what klink needs to do at runtime
- `.autoport/lib/c3_run.sh` — clone this for c4_run.sh
- ARM ARM C6.2.10 (ADRP), C6.2.4 (ADD imm), C6.2.93 (LDR imm)

## Done definition

`.autoport/validators/phase-C4-klink-arm64-execute.sh` exits 0.
Checks:

1-40. The full C3 invariant set (every check carried over).
41. `.autoport/lib/c4_run.sh` exists, executable, exits 0.
42. C4 boot log shows all 8 `link finish:` markers.
43. C4 boot log contains
    `linux-arm64: C4 KERNEL.CGO execute complete (NumSymbols=N, post-execute-delta=+M)`
    with N ≥ 517 (C3's 317 + a 200-symbol floor) and M between 200
    and 2000.
44. **NO SIGILL / SIGSEGV / abort / UDF in the C4 boot log** —
    grep -qE 'Illegal instruction|SIGILL|SIGSEGV|signal 4|signal 11|terminate called|Aborted|qemu: uncaught' returns nothing.
45. `linux_arm64_main.cpp`'s link flags constant includes
    `LINK_FLAG_EXECUTE` (the inverse of C3's check).
46. `linux_arm64_main.cpp` source contains zero
    `signal(.*SIGILL|sigaction.*SIGILL` matches.
47. The literal text `NumSymbols=` appears in
    `linux_arm64_main.cpp` exactly ONCE (the assignment from the
    live symbol-table value), not as a hard-coded literal.
48. `game/kernel/common/klink.cpp` diff vs A4 shows ≥ 30 added lines
    and adds the keywords `ADRP|adrp` and `imm12` and a switch- or
    if-else discrimination on the patch-site value.
49. Goalc emitter files (`IR.cpp`, `IGenARM64.{cpp,h}`,
    `ObjectGenerator.{cpp,h}`, `CodeGenerator.{cpp,h}`) still
    byte-identical to A4.
50. `.autoport/lib/classify_ir_arm64.py` byte-identical to A1.
51. x86 CGOs at `out/jak1/iso/` hash-match A2 baseline.
52. Desktop gk smoke test still reaches `link finish: logo`.
53. `.autoport/reports/C4-execute.md` exists, contains the keyword
    `ADRP` and `NumSymbols`.
54. The instruction-kind histogram in C4-execute.md sums to ≥
    100 (the relocator handled ≥100 arm64 instruction patches —
    real coverage of the patch sites).
