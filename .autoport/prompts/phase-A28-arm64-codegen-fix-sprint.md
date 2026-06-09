# Phase A28 — arm64 codegen fix sprint (METHODOLOGY RESET: wide unlocks, lean gates, fix-until-it-boots)

## Why this phase is different

A21–A27 were narrow one-bug-per-phase diagnostic phases with heavy scaffolding. That was too slow. **A28 changes the methodology: wide latitude, fix as many arm64 codegen bugs as you find in one session, iterate until qemu advances or you've made a real attempt.** Don't write diagnostic-only reports — FIX THINGS.

You have broad authority. Read GOAL source, disassemble CGOs, fix multiple emit paths, change the regalloc if needed. The only hard rules are the four anti-cheat invariants below.

## The bug to start with (well-localized by A27)

**H5.b — the `(new catch-frame ...)` constructor's chain-push is mis-emitted on arm64.** A27 confirmed the catch-frame chain is EMPTY at the `throw 'initialize` trap (pp.stack-frame-top = s7/nil; chain_count=0). The constructor at `gkernel.gc:1444-1529` should push the frame:

```
(set! (-> this next) (-> pp stack-frame-top))   ; line 1514: this.next = pp.stack-frame-top
(set! (-> pp stack-frame-top) this)             ; line 1515: pp.stack-frame-top = this
```

A27 verified the field offsets the throw WALKER uses:
- `pp.stack-frame-top` at pp_host + 0x58 (deftype offset 92 − BASIC_OFFSET 4 = 88 = 0x58).
- `frame.next` at this_host + 0x04 (deftype offset 8 − 4).
- `frame.name` at this_host + 0x00 (deftype offset 4 − 4).

**Start by disassembling the `new catch-frame` method on arm64** (find it via the kernel type-method table, or scan KERNEL.CGO for the constructor). Check the STR offsets for the two chain-push stores against what the walker reads. The constructor is an `asm-func` with manual `.mov` ops — the same territory where A24/A25/A26 found XMM/class-mismatch bugs. Likely failure modes:
- The store offset is wrong (uses deftype offset 92 instead of memory offset 88, or vice-versa).
- The store size is wrong (STR X vs STR W).
- The `pp` register (r13/X13) holds the wrong value at the store, OR a `.mov`-class-mismatch corrupts `this` or `pp` before the store.
- The store is skipped entirely due to a control-flow / regalloc bug.

If H5.b doesn't pan out, check H5.a (run-function-in-process is never reached). A27 thinks H5.b is more likely.

## Mandate

1. Find the catch-frame chain-push bug. Fix it.
2. If the fix reveals MORE arm64 codegen bugs at the same or next ceiling, **fix those too in this same phase**. Don't stop at one bug. Don't author a diagnostic-only exit if you can keep fixing.
3. Rebuild goalc (x86 + arm64), regenerate arm64 CGOs, run qemu_repro. Repeat the fix→build→test loop as many times as your budget allows.
4. Stop when: qemu advances past 216 (ideally a lot), OR you've hit a bug that genuinely needs GOAL-source changes (which are locked), OR you've run low on budget.

You may reuse the A21–A27 tracer infrastructure (OG_BLR_TARGET_TRACE, OG_X30_TRACE_EMIT, the 0xBEEF break trap, the A27 chain dumper) to debug — they're all in HEAD. You may add new ad-hoc tracers if helpful, but prefer FIXING to instrumenting.

## Scope — what you can and cannot touch

**UNLOCKED (edit freely):**
- `goalc/**` EXCEPT `goalc/emitter/IGenX86_64.{cpp,h}` — including `IGenARM64.{cpp,h}`, `IR.{cpp,h}`, `CodeGenerator.{cpp,h}`, `Val.{cpp,h}`, `compilation/Type.cpp`, `regalloc/Allocator.cpp`, `regalloc/Allocator_v2.cpp`, `allocate_common.cpp`, `emitter/Register.{cpp,h}`, `emitter/ObjectGenerator.{cpp,h}`, `Compiler.cpp`. **Allocator.cpp is now UNLOCKED** — if the right fix is a class-aware regalloc change, do it.
- `game/kernel/**` — arm64 kernel runtime, klink, kscheme (common + jak1), kmachine, asm_funcs_arm64.s.
- `game/linux-arm64/**` — the linux-arm64 runtime + SIGILL handler.
- `game/system/**`.
- `common/type_system/**` — if a type-layout fix is needed.
- `android/**` — if an Android-side fix helps.
- `.autoport/reports/A28-*`, `.autoport/tests/**`.

**STILL LOCKED (do NOT edit):**
- `goalc/emitter/IGenX86_64.{cpp,h}` — the x86 emitter is the ORACLE. Never change it. (You may READ it to mirror its dispatch patterns.)
- `goal_src/**` — GOAL source is shared with x86 and authoritative. A fix that needs GOAL-source changes is out of scope — name it in the report and stop.
- `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py` — supervisor infrastructure.
- `.autoport/prompts/phase-*` except `phase-A28-*`.

## Anti-cheat invariants (the ONLY hard rules)

1. **x86 desktop still boots.** After your changes, `build-x86/game/gk --game jak1 --portable -fakeiso ... -boot` must still reach `link finish: logo`. (Note: x86 CGO bytes MAY change if you touch shared code — that's allowed, as long as x86 still boots correctly. This is the methodology change: we test x86 by BOOTING it, not by byte-identity.)
2. **No fake "link finish" output.** Don't printf link-finish lines. The qemu count must come from the real kernel.
3. **No `__attribute__((weak))`, no `abort()`/`std::abort()` additions, no `gk_recover_to_renderer`/forced-recovery dodge, no `*_stubs.cpp`.**
4. **No edits to `.autoport/lib`, `.autoport/validators`, `goal_src/`, or `IGenX86_64.*`.**

That's it. Everything else is fair game.

## Deliverables (lean)

### Path A — boot advances
qemu link-finish count > 216. Ship:
1. **A28-fix-summary.md** (≥80 lines — concise is fine): what you fixed, the disasm before/after, the new ceiling, the next bug if visible.
2. **A28-baseline-arm64-cgo-hashes.txt** — sha256 of the arm64 CGOs.
3. If x86 CGOs changed: note it + paste the x86 smoke result proving it still boots.

### Path B — fix landed but needs GOAL-source or another locked surface
1. **A28-attempt-N-next-blocker.md** (≥80 lines): what you fixed, what's still blocking, what locked file the next fix needs.

### Path C — couldn't crack it this session
1. **A28-attempt-N-progress.md** (≥80 lines): what you tried, what you ruled out, the sharpest next hypothesis.

All paths: keep reports tight. No 250-line essays. Evidence + decisions.

## Validator (lean — `phase-A28-arm64-codegen-fix-sprint.sh`)

1. No `goal_src/` edits, no `IGenX86_64.*` edits, no infra edits.
2. No weak/abort/dodge/stubs additions.
3. **x86 desktop smoke reaches `link finish: logo`** (this replaces the byte-identity check).
4. qemu link-finish count ≥ 216 (no regression); report which ceiling reached.
5. One A28 report present.
6. If Path A: A28-baseline file present + qemu ≥ 217.

## Max settings

- `max_turns: 2500` (long sprint — iterate the fix/build/test loop many times).
- `max_retries: 3`.

## Budget

- This is a sprint — spend up to ~$200 in one go if you're making progress. Don't stop after one fix if you can keep advancing.

## Strategic note (for you, the implementer)

The 216 ceiling has been blocked by a CHAIN of arm64 codegen bugs in the same class (XMM/GPR register-file conflation + asm-func emit issues), found one at a time across A24–A27. They're all in `(asm-func ...)` GOAL code (throw-dispatch, cpu-thread-*, catch-frame constructor) that uses manual `.mov`/field-store ops the arm64 backend mis-lowers. There may be 2–5 more of these. **Fix as many as you can in this one session.** Each one you fix without a full phase cycle saves ~$50 and a day of wall-clock. Go.
