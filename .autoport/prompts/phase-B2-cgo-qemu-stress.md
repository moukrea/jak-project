# Phase B2 — Decode-stress all jak1 arm64 functions under qemu-aarch64

## What this phase delivers

Proof that **every function** in every arm64 CGO from B1 — KERNEL.CGO
(197 fns), ENGINE.CGO (3845 fns), GAME.CGO (4199 fns); ≈ 8,241 total —
satisfies two invariants when handled by qemu-aarch64:

1. **Disasm-clean**: `aarch64-linux-gnu-objdump -d` over the function
   bytes produces zero `.inst 0x...` pseudo-ops (the disassembler's
   way of saying "I don't recognise this 4-byte encoding"). Any
   unknown opcode means goalc-arm64 emitted invalid arm64 — a real
   encoder bug.
2. **No SIGILL on execution**: the function bytes, loaded into a
   minimal qemu-aarch64 harness with x0=0 and a writable stack,
   execute to completion (`ret`) without raising **SIGILL**. SIGSEGV
   IS tolerated per-function (a function that dereferences x0 will
   fault on a null arg; that's a runtime expectation, not an encoder
   bug) provided the SIGSEGV occurs strictly *after* the function
   prologue's `stp` (i.e., the function got to its first own
   instruction).

The deliverable is `.autoport/reports/B2-stress.json` with one entry
per function and a summary roll-up. A SIGILL count > 0 is a hard fail;
SIGSEGV in the prologue is a hard fail; everything else is documented.

## Why this matters

B1 proved the CGO files have plausible structure (size, ret density,
function count). B2 proves the bytes are **executable arm64** — the
encoder didn't emit any opcodes the CPU doesn't recognise, didn't
generate misaligned branches, didn't produce truncated function
bodies. After B2, jak1's arm64 CGOs are runtime-ready (modulo the
Bionic / GLES diff to Android, which is bucket D's problem).

If B2 surfaces any SIGILLs, those are real encoder bugs in A2's
work that A3's per-cluster synthetic tests didn't catch (likely
because the test functions exercised the "happy path" of each
encoder; jak1 source may hit corner-case operand combinations).
The fix lives in A2/IGenARM64 territory — A4 is downstream, so a
SIGILL in B2 is a defect in **A2 specifically**. The supervisor
will halt and reopen A2 with the corner case as a new test.

## Concrete deliverables

### 1. Stress harness `.autoport/lib/b2_stress.{sh,py}`

The harness:

1. For each CGO at `out/jak1-arm64/iso/{KERNEL,ENGINE,GAME}.CGO`:
   - Use `cgo_inspect.py` to walk the v3 link table and enumerate
     every main-segment function (name + byte offset + length).
   - For each function, extract the bytes.

2. For each (cgo, fn) tuple:
   - **Disasm step**: run `aarch64-linux-gnu-objdump -D -b binary
     -m aarch64 <bytes>` (or the equivalent: wrap as elf and -d).
     Count any `.inst 0x...` or `.word 0x...` lines → that's the
     "unknown opcode" count. Must be 0.
   - **Execute step**: wrap the bytes in a minimal AArch64-elf
     harness (`b2_harness.S`) that:
       - sets up an 8 KB stack
       - sets x0=0, x1..x7=0 (zero-arg call)
       - sets x30 (link register) to a "safe exit" trampoline
       - jumps into the function bytes (`br xfn`)
       - the trampoline does `mov x8, #93; svc #0` (exit syscall)
         with x0 = whatever the function returned
   - Run the elf under `qemu-aarch64-static`. Capture exit status:
       - exit code 0-255: returned cleanly (with that value)
       - 132 (= 128+4): SIGILL (HARD FAIL)
       - 139 (= 128+11): SIGSEGV (tolerated if disasm clean AND
         occurred after the function's first 4 bytes)
       - 137 (= 128+9): timed out (we set a 0.5s timeout per fn)
       - other: classify and record

3. **Report**: write `.autoport/reports/B2-stress.json`:
   ```json
   {
     "phase": "B2-cgo-qemu-stress",
     "summary": {
       "total_functions":       8241,
       "tested_via_disasm":     8241,
       "disasm_clean":          8241,
       "executed_under_qemu":   8241,
       "exit_clean":            <n>,
       "sigsegv_post_prologue": <n>,
       "sigsegv_in_prologue":   0,
       "sigill":                0,
       "timeout":               <n>,
       "other":                 <n>
     },
     "per_cgo": { "KERNEL.CGO": {...}, ... },
     "failures": [ {"cgo": ..., "fn": ..., "kind": ..., "addr": ...} ]
   }
   ```

4. Plus `.autoport/reports/B2-stress.md` headline:
   > Decode-stressed N functions across 3 CGOs. SIGILL=0, prologue-
   > SIGSEGV=0, body-SIGSEGV=K (tolerated), timeout=T, clean=C,
   > unknown-opcode=0.

### 2. The qemu harness

`test/arm64/b2_harness.S` — a tiny AArch64 assembly stub:

```
.global _start
_start:
    // Set up stack.
    mov   x29, sp
    // Zero call regs.
    mov   x0, #0
    mov   x1, #0
    ...
    // Load function address from a known location (passed by the
    // wrapper script via .data) into x10.
    adrp  x10, fn_addr
    add   x10, x10, :lo12:fn_addr
    ldr   x10, [x10]
    // Set link register to safe exit.
    adr   x30, safe_exit
    // Jump in.
    br    x10
safe_exit:
    // x0 already holds the return value.
    mov   x8, #93                  // syscall exit_group
    svc   #0
```

The function bytes are concatenated as a second section. A small Python
script per-fn (`.autoport/lib/b2_wrap_fn.py`) writes the elf with
the function at a known address. Reuse the elf-wrap pattern from
`.autoport/lib/build_a2_smoke.sh`.

## Anti-cheat constraints

1. **Do not modify codegen** — IR.cpp, IGenARM64.cpp, ObjectGenerator.{cpp,h}
   are all locked since A4. The validator diffs against A4's commit.
   If B2 surfaces a SIGILL, the right move is to **fail the phase**
   and let the supervisor reopen A2 with the corner case as a new
   smoke test. Do NOT silently fix the encoder bug in B2.
2. **Do not skip functions silently.** Every function in every CGO
   must appear in the per-fn JSON. If you can't even disassemble a
   function (cgo_inspect fails), record it as a parse error — that's
   a B1 bug to reopen, not a B2 skip.
3. **Do not lower the SIGILL threshold.** Zero is zero.
4. **SIGSEGV in the prologue is also forbidden.** If the function's
   `stp` or `mov x29, sp` segfaults, the stack mapping is wrong
   in the harness; fix the harness. Don't silently call those
   "tolerated."
5. **Do not run multiple `(mi)` in parallel.** B1 had a race on
   `out/jak1/iso/` because two driver runs collided. B2 must read
   from `out/jak1-arm64/iso/` (read-only) and never invoke goalc.
   No mutation of CGOs in this phase.
6. **The harness must be reproducible.** Re-running it on the same
   CGOs produces the same per-function classification. The validator
   re-runs and compares the summary.

## Files you will create / modify

| Path | Purpose |
|---|---|
| `.autoport/lib/b2_stress.sh` | top-level driver |
| `.autoport/lib/b2_stress.py` | per-function loop + report generator |
| `.autoport/lib/b2_wrap_fn.py` | per-fn elf builder |
| `test/arm64/b2_harness.S` | qemu entry stub |
| `.autoport/reports/B2-stress.json` | per-fn report |
| `.autoport/reports/B2-stress.md` | summary headline |

Read-only: everything in `goalc/`, `out/jak1-arm64/iso/`,
`out/jak1/iso/`.

## Pitfalls

- **8,000+ qemu spawns**: even at 50 ms each that's ~7 minutes.
  Consider batching: a single qemu run that takes a function-index
  on the command line and exits with the function's result, with
  parallelism via xargs (`-P 4`). Per-fn elf-builds can also batch
  (one ld invocation per CGO with all functions as separate
  sections, then dlopen each).
- **`adrp` page-relative load** in the harness assumes the elf
  loader places `.data` (where fn_addr lives) within ±4GB of `.text`.
  qemu-user does this by default. If the harness ever segfaults at
  the first `adrp`, that's the harness bug, not a codegen bug.
- **Functions that loop forever** under the harness (no early exit
  path; just keep looping) will hit the 0.5s timeout. Record as
  "timeout"; tolerate up to ~50 timeouts (the GOAL kernel has some
  legitimate infinite loops gated on external state).
- **A function whose first instruction is a branch** (e.g., a tail
  call) may jump into uninitialised memory. The harness's safe_exit
  is the link-register fallback; if the function ignores x30 and
  branches absolutely, qemu will fault. Record as
  `sigsegv_post_prologue` — but note in the failures list whether
  the function's first instruction was a branch (some are; that's
  fine).
- **Function size 16 bytes** = prologue + epilogue only (no body).
  These trivially `ret`. They count toward both `disasm_clean` and
  `exit_clean`.

## Reading list

- `.autoport/reports/B1-cgo-structure.json` — the function counts,
  sizes, sample disasm
- `.autoport/lib/cgo_inspect.py` — function-table parsing
- `.autoport/lib/build_a2_smoke.sh` — elf-wrap pattern
- `.autoport/lib/build_a3_diff.sh` — harness execution pattern
- `test/arm64/a4_kernel_probe.c` — minimal AArch64 harness example
- Phase 24 commit `c6572b9c6` — for goalc-arm64's calling convention
  (which the harness must match)

## Done definition

`.autoport/validators/phase-B2-cgo-qemu-stress.sh` exits 0. Checks:

- `B2-stress.json` exists, parses, has the summary above.
- `summary.sigill == 0`.
- `summary.sigsegv_in_prologue == 0`.
- `summary.disasm_clean == summary.total_functions` (every function
  disassembled cleanly).
- `summary.total_functions ≥ 8000` (sanity: matches B1's counts
  within reason).
- `summary.executed_under_qemu == summary.total_functions` (every
  function attempted under qemu).
- Per-CGO breakdown adds up to the totals.
- Harness reproducible (re-run, summary matches).
- No codegen modifications since A4.
- Classifier still locked since A1.
- Desktop gk smoke test still reaches `link finish: logo`.
