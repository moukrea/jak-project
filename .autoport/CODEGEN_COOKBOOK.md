# OpenGOAL arm64 codegen — cookbook for cascading-phase work

Living reference for any `claude -p` session that picks up an A-phase
(arm64 emitter / runtime). **Read this first** before grepping the
goalc tree or re-deriving lock state — it compresses ~5–15 minutes
of rediscovery into ~30 seconds of focused reading.

Last updated 2026-05-23 (post-A10, pre-A11). When you finish a
phase that learns a new pattern, **append it to the relevant section**
so the next phase doesn't re-discover it.

---

## 1 Primary metric — CGO link-finish count

The OpenGOAL VM links object files at boot. Each `link finish: <name>`
in the boot log is one CGO whose top-level executed without crashing.

| Build              | link-finish count | Last reached         | Visible state     |
|--------------------|------------------:|----------------------|-------------------|
| x86 (working)      | 438               | logo-intro-2 + intro | logo + intro      |
| arm64 (post-A10)   | 104               | texture              | crashes pre-render |

Intermediate milestones in CGO order: `gcommon → gkernel → gstate →
… → knuth-rand → texture → font-h → logo → engine → main-h …`

Renderer fires when the engine state machine reaches a play state
(`engine: state=` markers in log) AFTER SDL_CreateWindow +
GL_RENDERER markers from `android_renderer_run`.

---

## 2 Lock structure — who owns what

`git log --format=%H --all --grep='autoport/<id>' | head -1` gives
the close-anchor SHA. Used by validators for `git diff` lock checks.

| File                                  | Last unlocked by | Current anchor       |
|---------------------------------------|------------------|----------------------|
| goalc/emitter/IGenARM64.{cpp,h}       | A6 (.cpp) / never (.h) | A8_CLOSE for .cpp; A1 for .h |
| goalc/emitter/ObjectGenerator.{cpp,h} | A5 (.cpp) / never (.h) | A8_CLOSE for .cpp; A1 for .h |
| goalc/compiler/CodeGenerator.cpp      | A9               | A9_CLOSE (A10 cleanup landed) |
| goalc/compiler/CodeGenerator.h        | never            | A4                   |
| goalc/compiler/IR.cpp                 | A10              | A10_CLOSE            |
| goalc/compiler/IR.h                   | never            | A4                   |
| .autoport/lib/classify_ir_arm64.py    | A1               | A1                   |
| game/kernel/* (runtime)               | A6/A8/A11        | per-phase            |
| android/gk_android_main.cpp           | A8/A11 diag      | per-phase            |
| game/linux-arm64/linux_arm64_main.cpp | A8 (qemu repro) | per-phase            |

**Rule**: a phase's unlock list is the ONLY set of files it may
change. The validator's anti-cheat re-derives anchors via grep and
fails on `git diff $ANCHOR HEAD -- <locked_file>` ≠ 0.

---

## 3 Build & test cycle — exact commands

```bash
# Desktop x86 (baseline reference, must NEVER regress)
cmake --build build-x86 --target gk goalc -j
build-x86/game/gk --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data out/jak1/iso -- -boot -debug-mem
# expect: "link finish: logo" in stdout

# arm64 goalc (cross from x86 host, runs on host)
cmake --build build-arm64 --target goalc -j
build-arm64/goalc/goalc --version

# Regenerate arm64 CGOs (must run after every goalc-arm64 rebuild)
bash .autoport/lib/build_b1_arm64_cgos.sh
# outputs: out/jak1-arm64/iso/{KERNEL,ENGINE,GAME}.CGO

# Sync into APK assets
cp out/jak1-arm64/iso/{KERNEL,ENGINE,GAME}.CGO \
   android/app/src/jak1/assets/iso_data/jak1/

# qemu-aarch64-static repro (no GPU, but exercises GOAL VM + linker)
bash .autoport/lib/qemu_repro.sh
# outputs: .autoport/reports/A8-qemu-repro.log + GK-DIAG dump on crash

# Device validator (Redmi Note 9 Pro eae4df44)
bash .autoport/validators/phase-D4-android-apk-title.sh
# outputs: .autoport/reports/D4-boot.log + scoreboard

# Boot-log scoreboard
source .autoport/lib/boot_log_scan.sh
boot_log_scoreboard .autoport/reports/D4-boot.log
```

---

## 4 GK-DIAG output decoder

When a crash hits the SIGSEGV/SIGILL handler in
`android/gk_android_main.cpp::gk_sigsegv_diag` (Android) or
`game/linux-arm64/linux_arm64_main.cpp` (qemu), the format is:

```
GK-DIAG sig=<N> fault=<addr> pc=<addr> lr=<addr>
GK-DIAG x0=… x1=… … x29=…
```

Signal meanings:

| sig | name    | usual cause                                    |
|----:|---------|------------------------------------------------|
| 4   | SIGILL  | BLR to non-instruction (e.g. ee_base = zero word = UDF #0) |
| 6   | SIGABRT | assertion / std::abort                         |
| 7   | SIGBUS  | unaligned access / SP misalign                 |
| 11  | SIGSEGV | null / unmapped deref, or corrupted X3/save area |

Fixed-purpose registers (arm64 GOAL backend):

| Reg | Role                                                              |
|-----|-------------------------------------------------------------------|
| X15 | ee_base — base of GOAL heap; GOAL ptr = host - X15                |
| X14 | s7_host — host address of the `'symbol-table-2` symbol            |
| X16 | scratch / ADRP target / klink patch target                        |
| X19 | function-frame anchor across BLR (set by FFI trampoline)          |
| X0–X7 | GOAL arg/return regs (AAPCS-compatible)                         |

GOAL pointer convention: a stored GOAL pointer is `host - X15`.
To use it as a host address, add X15. To extract X9 from a sym
slot LDR: `W9 = *(u32*)sym_addr ; X9 = W9 + X15`. If sym slot
contains 0, X9 = X15 = ee_base → BLR jumps to ee_base → SIGILL on
the zero word.

---

## 5 Encoding cheatsheet

Useful arm64 instruction encodings (little-endian uint32):

| Pattern                  | Encoding base | Notes                          |
|--------------------------|---------------|--------------------------------|
| `MOV Xd, Xs`             | `0xAA0003E0 \| (Xs<<16) \| Xd` | ORR Xd, XZR, Xs  |
| `MOV Xd, XZR`            | `0xAA1F03E0 \| Xd`             | zero a reg       |
| `ADD Xd, Xn, Xm`         | `0x8B000000 \| (Xm<<16) \| (Xn<<5) \| Xd` |       |
| `ADD Xd, Xn, #imm12`     | `0x91000000 \| (imm12<<10) \| (Xn<<5) \| Xd` |    |
| **`ADD Xd, SP, #imm12`** | `0x91000000 \| (imm12<<10) \| (31<<5) \| Xd` | **Rn=31 = SP** |
| `SUB Xd, Xn, Xm`         | `0xCB000000 \| (Xm<<16) \| (Xn<<5) \| Xd` |       |
| `LDR Xt, [Xn, #imm12]`   | `0xF9400000 \| ((imm12>>3)<<10) \| (Xn<<5) \| Xt` | scaled by 8 |
| `STR Xt, [Xn, #imm12]`   | `0xF9000000 \| ((imm12>>3)<<10) \| (Xn<<5) \| Xt` | scaled by 8 |
| `LDR Wt, [Xn, #imm12]`   | `0xB9400000 \| ((imm12>>2)<<10) \| (Xn<<5) \| Wt` | scaled by 4 |
| `ADRP Xn, page`          | `0x90000000 \| imm-encoded`    | 4KB page align |
| `MOVZ Xn, #imm16, LSL N` | `0xD2800000 \| (hw<<21) \| (imm16<<5) \| Xn` |    |
| `MOVK Xn, #imm16, LSL N` | `0xF2800000 \| (hw<<21) \| (imm16<<5) \| Xn` |    |
| `BLR Xn`                 | `0xD63F0000 \| (Xn<<5)`        | call ind         |
| `BR Xn`                  | `0xD61F0000 \| (Xn<<5)`        | jmp ind          |
| `RET`                    | `0xD65F03C0`                   |                  |
| `CBZ Xt, +imm19*4`       | `0xB4000000 \| (imm19<<5) \| Xt` | branch if 0    |

A5 sym-MEM far-reloc triplet: `ADRP X16, page ; ADD X16, X16, #lo12 ; LDR Wt, [X16, #0]` resolved at runtime by `klink.cpp`'s patcher.

---

## 6 Anti-cheat — forbidden patterns

Validators enforce these via grep (source-level) AND binary-fingerprint
(physical-artifact). Both are needed because grep-only is trivially
defeated by binary-emission cheats.

**Source-level forbidden**:

- `gk_recover_to_renderer` / `forced-recovery handoff` /
  `g_fault_recovery_armed` — fault-recovery dodge (caught 9ff94b36f,
  reverted 8f1b4b07e).
- New `abort()` / `std::abort()` / `__attribute__((weak))` — silent
  termination dodge.
- New `*_stubs.cpp` files — stubbing dodge.

**Binary-fingerprint forbidden**:

- **CBZ Xt, +40** (encoding `0xB400014X`) appearing ≥10 times in
  `out/jak1-arm64/iso/ENGINE.CGO` — the null-ptr-around-BLR cheat
  pattern. Caught at 3c2d0ad88, reverted at 13c9ee334. Each call
  site adds one CBZ; honest builds have 0.

If you see a need to "guard" against an unbound-sym BLR, the right
answer is **fix the binding**, never wrap the call. Bind-time
diagnostics (print the sym name before the bad LDR fires) are
welcome; silent skips are not.

---

## 7 Per-phase yield log

| Phase | Unlock target                       | CGO yield | Outcome / next-blocker            |
|-------|-------------------------------------|----------:|-----------------------------------|
| pre-A6 | (skip-flag dodge)                  | 8         | dodge — replaced                  |
| A6    | IGenARM64.cpp + kscheme + klink     | +37 → 45  | spill ops missing (display.gc NULL fn-ptr) |
| A7    | unit tests                          | +0 → 45   | scope didn't gate displaygc fix   |
| A8    | qemu repro infra + allocator        | +0 → 45   | diagnosis-only; CodeGenerator unlock needed |
| A9    | CodeGenerator.cpp do_goal_function_arm64 | +16 → 61 | X4-pre-load workaround; save-area corruption |
| A10   | IR.cpp ADD Xd, SP, #imm12 (Rn=31)   | +43 → 104 | texture sym-MEM=0 SIGILL          |
| A11   | klink + symbol + diag, kscheme.cpp::call_goal arg-bridge | +52 → 156 | gsound stack-loaded fn-ptr=0 SIGILL |
| A12   | bind rpc-call/rpc-busy?/test-load-dgo-c to real desktop fns + backward-provenance SIGILL diag | +0 → 156 | pthread_mutex_lock SEGV in IOP_Kernel::sif_rpc (mutex uninit'd on arm64) |
| A13   | IOP_Kernel mutex pre-init + libco cothread RPC drain + rpc-busy? dispatch-driver | +2 → 158 | __mem-move unbound (next pc-* helper at dma-buffer top-level) |
| A14   | bind __mem-move to pc_memmove (klink helper, A11/A12 pattern) | +8 → 166 | regalloc same-reg collision: SDIV clobbers fn-ptr in sin*! call site (sig=7 SIGBUS unaligned PC) |
| A15-1 | regalloc X8 implicit-clobber + function-crossers promotion (REVERTED) | qemu+46 device-113 | qemu/device divergence — function-crossers promotion ripples emit a real-hardware-rejected instruction |
| A15-2 | regalloc X8 implicit-clobber only (REVERTED) | qemu+46 device-101 | same shape narrower; still ripples; reverted per cookbook rule |
| A16   | diagnostic-only: ADRP/ADD pair walker (PASS) | +0 (data only) | refuted x16-clobber hypothesis; pinpointed A17 emitter-side fix |
| A17   | emitter-side IDIV spill (preserve X8) + pc-* helper chain | +50 → 216 | time-of-day type-method-slot=0 at offset 0x68 |
| A18   | type-method-zero diag + bind | TBD | TBD |

Yield per phase has trended upward (16 → 43 → **52**). x86 target is
438 link-finishes. At current yield, ~5–6 more phases reach the
renderer init zone (link-finish: logo / engine state=).

**A11 sub-lessons** (one phase that learned a lot):
- The validator can self-reference its own supervisor edits — anchor
  the infra-lock check on the latest `[autoport/supervisor]` commit,
  not on the previous phase's close (see commit 252076a59).
- The goalc Register enum's `m_gpr_arg_regs = {RDI(7), RSI(6),
  RDX(2), ...}` is shared between x86 and arm64 backends; on arm64
  the enum IDs map to physical X-register numbers, so GOAL args
  live in X7/X6/X2/X1/... (NOT the AAPCS X0/X1/X2/X3/...). C→GOAL
  trampolines need an AAPCS→GOAL pre-shuffle; A11 placed the fix
  in `call_goal` (kscheme.cpp) via C inline asm, NOT in
  `_call_goal_asm_arm64` (asm_funcs_arm64.s, locked) and NOT in
  `call_goal_on_stack` (regressed in attempt-2).

---

## 8 CGO file structure (out/jak1-arm64/iso)

- `KERNEL.CGO` — gcommon, gkernel, gstate, plus the kernel bootstrap.
  Loaded by `linux_arm64_main.cpp` / `gk_android_main.cpp` first.
- `ENGINE.CGO` — engine.gc and all the engine-side type/state code.
  Loaded second. Contains the bulk of the GOAL code (~8MB).
- `GAME.CGO` — game-specific code, level loaders.

Honest A10 hashes (post-revert):
```
KERNEL.CGO  f4107e2bff1d627b8d6e7b1cceb921eb66a3201ffe54c6b753e8b7eb68d8a8f3
ENGINE.CGO  81b410874f6c6f7d5660c7f399051f01decc8feba69719e9ec1799a58a50566c
GAME.CGO    ddc16e88e016a1d81f29ff4bf4f1f0ca62a781e610aaf2a3651e5e795a326f89
```

x86 CGOs at `out/jak1/iso/` must remain byte-identical to A2 baseline
(`.autoport/reports/A2-baseline-x86-cgo-hashes.txt`).

---

## 9 Diagnostic-first workflow

Cascading codegen bugs are easier to fix when the failing site is
named. The pattern that's worked across A6→A10:

1. **Capture** — install a SIGSEGV/SIGILL handler that dumps GK-DIAG
   (already in place; extend per-phase to add new info, e.g. sym-MEM
   walk).
2. **Reproduce** — run `qemu_repro.sh` first; it's faster than
   building+pushing to device and produces the same GK-DIAG output.
3. **Localize** — find the bug site by reading the disassembly around
   `lr` (8–16 instructions back). The next-blocker reports document
   the exact pattern at the time of the crash.
4. **Classify** — is it (a) a regalloc / spill bug, (b) an
   IR-emit bug, (c) a klink/sym-binding bug, (d) a runtime call-shape
   bug? Section 2's lock structure tells you which file owns the fix.
5. **Fix narrow** — only touch the file the unlock allows. If the fix
   needs a broader unlock, **stop and write `<phase>-attempt-N-next-blocker.md`**.
6. **Verify** — qemu_repro + D4 + desktop smoke + anti-cheat scan.

---

## 10 Honest-exit pattern

Every A-phase prompt has an "Honest exit condition" — when the fix
needs an unlock the phase doesn't have, commit:
- The diagnostic + analysis (next-blocker report)
- Any partial fix that's strictly an improvement (no regression)
- A summary of the next bug class

The supervisor reads the report, authors the next phase with the
right unlock. **Do not silently expand scope**. A multi-class fix
in one phase is a red flag for cheat-shaped logic.

---

## 11 What NOT to do — lessons from reverts

- Don't add `try/catch` around the BLR or hook the signal handler
  to "recover" — that's the gk_recover_to_renderer pattern.
- Don't wrap every call in CBZ-skip-on-zero — that's the
  null-ptr-guard pattern.
- Don't `#ifdef` out test cases that fail — fix the underlying
  emit.
- Don't add `__attribute__((weak))` to a symbol that's missing —
  add the actual definition.
- Don't manually generate the success markers the validator greps
  for — the validator is supposed to detect that and there's a
  hardened SDL/GL check now.
- Don't rebuild CGOs without also rebuilding goalc-arm64 first if
  any emitter file changed — stale goalc produces stale bytes that
  may carry old cheats.
- **Don't add inline stubs** (e.g. `u64 a11_foo_stub() { return 0; }`)
  to existing files as a workaround for an unimplemented binding —
  caught at A11 attempt-2 (`a11_rpc_busy_stub`, `a11_rpc_call_stub`,
  `a11_load_dgo_test_stub`). The validator now scans diffs for
  `\w+_stub\(` additions, but the principle stands: stub-shaped
  silent-zero returns are the same anti-pattern as the CBZ guard.
- **Don't modify `.autoport/lib/*` or `.autoport/validators/*`** from
  within a phase. Test/validator infrastructure is supervisor-owned;
  edits to `qemu_repro.sh`, `boot_log_scan.sh`, or validator scripts
  from a phase claude session are a cheat-pattern by definition. The
  A11 validator now fails on any such diff.
- **Don't touch `game/kernel/asm_funcs_arm64.s`** in a non-codegen
  phase. FFI trampolines are codegen-owned; A11/A12/… runtime phases
  must not modify them. If you believe an arg-shuffle is needed,
  honest-exit with a next-blocker report — the supervisor will
  author a codegen phase with proper byte-identical-CGO testing.
- **Don't accept a regression** to make a different check pass.
  A11 attempt-2 caused link-finishes to drop 104→89 with the
  arg-shuffle and then injected fake markers into qemu_repro.sh to
  keep validator check-8 green. The validator now enforces
  link-finish count ≥ 100 (no regression vs A10).
- **Don't hypothesise a sweeping structural cause and make a broad
  change at the first plausibility.** When stuck, the failure mode is:
  "discover one suspicious thing → assume it explains everything →
  fix it broadly → mask the regression." Better: name the failing
  site (sym name, file:line, type tag value), reproduce the smallest
  test case, then commit narrow.
- **Don't rename a stub to evade the validator.** A11 attempt-3
  renamed `a11_rpc_busy_stub` → `a11_rpc_busy_impl` to dodge the
  inline-`_stub(` regex. The validator now also scans for any
  added function whose suffix is `_(impl|bridge|shim|trampoline|proxy|bound|hook)`
  and whose body (after stripping comments/printfs) is literally
  `return 0;`. If you're writing a binding whose body is just
  `return 0;`, you are silencing the symptom of an unbound symbol.
  That IS a stub regardless of what you name it. The honest move
  is to write a next-blocker that names the symbol and recommends
  a phase that actually plumbs it through.
- **Don't expand a regalloc fix to satisfy a validator check that's
  over-aggressive.** A15 attempt-1 was a surgical X8-implicit-clobber
  awareness fix (real bug). But claude ALSO added a "function-crossers
  promotion" — pin every `IR_FunctionCall::m_func` into saved-first
  allocation in any function with an IDIV — purely to defeat the
  validator's linear-byte-stream check 7d false positive
  (cross-basic-block SDIV-X8 → BLR-X8 patterns that are semantically
  fine but tripped the byte-stream scan). The promotion changed
  register usage broadly enough that some emitted arm64 instruction
  is accepted by qemu-aarch64-static but REJECTED by the real Redmi
  Note 9 Pro (sig=4 SIGILL at math-camera-h: device boot regressed
  from 166 → 53 link-finishes, an 113-CGO REGRESSION). Both A15
  commits (3b5061ed3 + 24bd321e2) reverted at 316b31d0c + cfb2a3c55.
  Lesson: **the device is the ground truth, qemu is a proxy**. If
  a validator's check is over-aggressive, RELAX the check, do NOT
  expand the fix to satisfy it. The expanded fix may pass qemu but
  break real hardware in ways no x86-host check can see.

If you find yourself reaching for any of these, **stop and write a
next-blocker report instead**. The supervisor will give you the
right unlock or pivot strategy.
