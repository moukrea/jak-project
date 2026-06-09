# Phase A29 — arm64 boot sprint past the gsound IOP-RPC blocker (continue the A28 wide-sprint methodology)

## Why / methodology

A28's wide sprint broke the 8-phase 216 ceiling → **462 link-finishes** by fixing two arm64 asm-func bugs (RSP→SP, x86 call/ret semantics). A29 continues the SAME lean wide-sprint approach: wide unlocks, fix-until-it-boots, lean gates. Don't fragment into narrow phases.

## The starting blocker (well-localized)

qemu now boots to 462 link-finishes (last = `gsound`), then **dies**:

```
link finish: gsound
die: Assertion failed: 'rec->cmd.finished && rec->cmd.started'
```

The assertion is in **`game/system/IOP_Kernel.cpp`** — the IOP-kernel RPC emulation that bridges EE↔IOP (sound processor). When gsound's top-level runs its first sound RPC, the RPC command record's `started`/`finished` flags aren't both set as the handler expects.

Likely causes (in order of probability):
1. **RPC state-machine ordering** on arm64 — the command is dispatched/polled before the IOP thread marks it started, OR a threading/memory-ordering difference vs x86 (the IOP runs on its own emulated thread; check the IOP_Kernel scheduler + the `rec->cmd` lifecycle).
2. **mips2c-translated IOP code mis-emit** — gsound/overlord IOP routines are mips2c-translated C++; if the arm64 codegen for any of them is wrong (same class as A28's asm-func bugs), the RPC record gets corrupted. Check whether the gsound IOP routines go through goalc-arm64 or are pure C++ mips2c.
3. **Missing/!-init** — the RPC record isn't initialized before first use on this path.

Start by reading the assertion site in IOP_Kernel.cpp + the `rec->cmd` (started/finished) lifecycle + how the IOP thread is scheduled on linux-arm64 (game/linux-arm64/) vs x86. Compare to how x86 satisfies the assertion (x86 boots fine through gsound).

## Mandate

1. Fix the gsound IOP-RPC blocker. Get qemu past 462.
2. **Keep fixing** whatever blocks next (sound init, more IOP RPCs, display init, etc.) in this same session, until the boot reaches the display/renderer stage OR a GOAL-source change is needed OR budget runs low.
3. Iterate fix→build→qemu. Note each new ceiling.
4. The goal posts: ideally reach `link finish: logo` (the title-screen DGO) and beyond into the display loop. Every link-finish past 462 is progress.

You may reuse all A21-A28 tracer infra. Prefer fixing to instrumenting.

## Scope (same as A28)

**UNLOCKED**: everything EXCEPT the three hard locks below — all of goalc (except IGenX86_64), game/kernel, game/system (incl. IOP_Kernel.cpp), game/overlord, game/sound, game/linux-arm64, common/type_system, android, etc.

**LOCKED (do NOT edit)**:
- `goalc/emitter/IGenX86_64.{cpp,h}` — x86 emitter oracle (read to mirror, never edit).
- `goal_src/**` — GOAL source (shared with x86). A fix needing GOAL-source changes is out of scope — name it and stop.
- `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, other `.autoport/prompts/phase-*` (except A29).

## Anti-cheat (the only hard rules)

1. **x86 desktop still boots to `link finish: logo`** (CGO bytes may change; it must still boot).
2. No fake "link finish" printf in the kernel/runtime.
3. No `__attribute__((weak))`, no `abort()` additions (note: REMOVING/relaxing an existing assert that's firing is allowed IF it's the correct fix and you justify it — but don't just silence asserts to fake progress; the qemu count must advance because the boot genuinely runs further).
4. No dodge patterns (`gk_recover_to_renderer`, forced-recovery), no `*_stubs.cpp`.
5. No edits to goal_src/, IGenX86_64.*, or .autoport infra.

Note on the assertion: the cleanest fix may be to correctly sequence the RPC so the assertion passes (preferred), OR — if the assertion itself is wrong for the arm64/linux IOP emulation — to fix the emulation. Simply commenting out the assert and letting corrupt RPC state through is NOT a fix (the boot would crash later); only relax an assert if you've shown the underlying state is actually correct and the assert is over-strict.

## Deliverables (lean)

- **A29-fix-summary.md** (≥80 lines) if boot advances past 462: what you fixed, before/after, the new ceiling, next blocker.
- OR **A29-attempt-N-next-blocker.md** (≥80 lines) if you hit a GOAL-source/locked wall.
- OR **A29-attempt-N-progress.md** (≥80 lines) if you couldn't crack it.
- If CGOs changed: **A29-baseline-arm64-cgo-hashes.txt**.

Keep reports tight.

## Validator (`phase-A29-arm64-gsound-iop-rpc-sprint.sh`)

1. No goal_src / IGenX86_64 / infra edits.
2. No weak/abort-additions/dodge/stubs/fake-link.
3. x86 desktop smoke reaches `link finish: logo`.
4. qemu link-finish count ≥ 462 (no regression below A28). Report the new ceiling; if A29-fix-summary present, require > 462 (advance).
5. One A29 report ≥ 80 lines.

## Max settings

- `max_turns: 2500`, `max_retries: 3`. Budget ~$200/session.

## Strategic note

Past gsound, the boot enters: sound init → engine init → level/DGO loading → the title-screen (`logo`) → the display loop. Some of these may surface more arm64 codegen bugs (asm-func / register-class family) or more runtime-emulation gaps (IOP, DMA). Fix them in-session. The display loop itself can only be validated on real GPU (the device) — but reaching it in qemu (even headless) is the milestone that makes device-rendering testable. Push as far as you can.
