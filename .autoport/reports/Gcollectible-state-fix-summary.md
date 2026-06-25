# Gcollectible-state — fix summary

Phase **Gcollectible-state** (OWNER 2026-06-25): on the arm64 Android port, **green
eco RESPAWNS after collect** (acts un-consumed / infinite-money-like) and **crate
DEBRIS flickers** (appear/disappear loop). Both differ from the original x86 build.
x86-first, fixed the arm64 divergence in the translation layer; `goal_src` stays
1-to-1.

## TL;DR — one root cause for both symptoms

Green-eco pickups (`health` / `eco-pill`) and crates are **entity-actors**. When
collected/broken they run a terminal `die` state whose `:code` **falls off the end**
(returns) — at which point the kernel must **deactivate** the process. On arm64 that
deactivation never happened, so the process re-ran its `die` state every ~4 s
forever: it re-called `drop-pickup` (re-spawning the green eco → "respawns / not
consumed") and re-spawned its crate-explode particle group (→ "debris flicker").
**The respawn and the flicker are the same bug.** One arm64 codegen fix resolves
both.

## Why the process never deactivated (the arm64 divergence)

`enter-state` (kernel, `goal_src/jak1/kernel/gstate.gc:355-386`, branch 3) sets up a
state's `:code` with a hand-rolled trampoline:

```
.mov sp, (-> pp main-thread stack-top)   ; reset stack
.push return-from-thread-dead            ; push the deactivate trampoline as RA
.jr  func                                ; jump into :code  (simulated call)
```

- **x86**: when `:code` returns, its `ret` **pops** the pushed word → lands on
  `return-from-thread-dead` → `(deactivate pp)`. Correct.
- **arm64**: GOAL functions use the register-RA contract (paired `STP/LDP` of X30;
  `ret` returns to **X30**, never pops a stack word). The pushed word is therefore
  never consumed — `:code` returns to a **stale X30**, `return-from-thread-dead`
  never runs, the process is never deactivated, the kernel keeps its `die`
  next-state and re-dispatches it → infinite ~4 s re-entry.

This is the documented "G2 residual." F1f tried to fix it by re-enabling a pop-RA
scan in `do_goal_function_arm64` that emitted `LDR X30,[SP],#16` — but the **+16 SP
advance** shifted suspend-looping states 16 bytes and **regressed the title**, so G1
reverted it (`goalc/compiler/CodeGenerator.cpp:585-607`). The crate/eco path is the
rare "terminal state that dies by falling off the end," so it stayed broken.

## The fix (arm64 codegen only; no x86 emitter; `goal_src` 1-to-1)

Re-enable the pop-RA for **`enter-state` only**, using a **new no-SP-adjust
encoding** `LDR X30,[SP]` (`0xF94003FE`) instead of `LDR X30,[SP],#16`
(`0xF84107FE`). It delivers the pushed `return-from-thread-dead` into X30 **without
moving SP**, so:

- a `:code` that **falls off the end** RETs to `return-from-thread-dead` →
  `deactivate` (crate/eco fixed, arm64 == x86), while
- **suspend-looping states keep the byte-identical SP** of today's stale-X30 path
  (they never return), so the F1f +16 title regression **cannot** recur — provably,
  because nothing about SP changes for them.

`enter-state` is the lone non-asm-func with a `.push RA;.jr` trampoline (the other
sites — `reset-and-call`, `set-to-run-bootstrap` — are asm-funcs already covered by
`do_asm_function_arm64`, and keep the +16 form). The scan is gated by
`env->name()=="enter-state"`, so no other function is touched.

### Files changed (all arm64-only; `goalc/emitter/IGenX86_64.*` untouched)

- `goalc/compiler/IR.h` — add `IR_JumpReg::mark_arm64_pop_ra_no_sp()` + member
  `m_arm64_pop_ra_no_sp`.
- `goalc/compiler/IR.cpp` — `IR_JumpReg::do_codegen_arm64` emits `LDR X30,[SP]`
  (`0xF94003FE`, no SP move) when `m_arm64_pop_ra_no_sp`, else the existing
  `LDR X30,[SP],#16` (`0xF84107FE`).
- `goalc/compiler/CodeGenerator.cpp` — parameterize `mark_push_jr_pop_ra_arm64`
  with `no_sp_adjust`; call it for `enter-state` in `do_goal_function_arm64`.

The change affects **arm64 codegen only** (`do_goal_function_arm64`); the x86 path
(`do_goal_function_x86`) is untouched, so x86 output is byte-identical and the x86
golden stays pristine (`link finish: logo`).

## x86-first deterministic evidence (state-anchored, not framerate-indexed)

A temporary 3-point lifecycle probe was baked into `entity.gc`
(`GDBG-PES` at `process-entity-status!` dead, `GDBG-DEACT` at
`entity-deactivate-handler`, `GDBG-BIRTH` at `birth!`) and compiled into both
backends. The SAME action — break ONE crate at Geyser Rock — was run on each:

| broken crate            | GDBG-PES type=crate | GDBG-DEACT type=crate |
|-------------------------|---------------------|-----------------------|
| x86 (original, correct) | **1**               | **1** (eq=#t)         |
| arm64 BEFORE fix        | **108** (~4 s loop) | **0** (never)         |
| arm64 AFTER fix         | **1**               | **1** (eq=#t)         |

First divergent state = the **missing deactivation** on arm64; AFTER == x86. The
dead bit (perm-status `0x4`) was already set+sticky on arm64 (`pre=#x44`), so the
bug was never the dead-mark — it was the un-fired process deactivation, confirmed by
host goalc disassembly showing the GOAL-function codegen of
`process-entity-status!` / `birth?` / the die bodies is x86==arm64-equivalent.

## Verification

- **Crate fix**: BEFORE 108/0 → AFTER 1/1 (deactivates once, stops); no eco re-drop,
  no debris re-spawn, no crate respawn (`GDBG-BIRTH crate = 0`).
- **Title / suspend-state regression gate**: title + attract render, vblank climbs
  to 43801, zero crashes — a live proof, since `enter-state` runs for every state
  transition, that the no-SP fix does not regress suspend states.
- **Clean HEAD build**: `deploy_verify.sh eae4df44` PASS (device provably runs the
  fresh HEAD libgk); boot + title + gameplay crash-free (no signal 11/6/4).
- **x86 smoke**: `link finish: logo`. `.autoport/gold` pristine.

## Temporary instrumentation — REMOVED

The 3 `GDBG-*` probes added to `goal_src/jak1/engine/entity/entity.gc` were
**reverted** (`git checkout`) before the final build; `git status -- goal_src` is
empty and `grep GCOLLECT-PROBE` over `entity.gc` returns 0. **No leftover
instrumentation** remains in `goal_src`. The deployed CGOs and the committed source
are clean; the only code change is the three `goalc/compiler/*` files above.

Owner eye/ear = final.
