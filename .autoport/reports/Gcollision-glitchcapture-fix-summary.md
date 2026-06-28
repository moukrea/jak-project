# Gcollision-glitchcapture — fix summary

## One line
The owner's degenerate-contact collision glitch (Jak clips / ejects / under-maps) is a **goalc
arm64 codegen bug**: float `<` and `<=` comparisons returned the **wrong boolean on a NaN
operand** (FALSE where x86 returns TRUE). Fixed in `goalc/compiler/IR.cpp` by changing the
arm64 float condition codes `LT: MI→LT` and `LEQ: LS→LE`. x86 codegen untouched; goal_src 1-to-1.

## Root cause (named, op-proven on the real device)
GOAL compiles a float comparison to a compare + a conditional branch:
- **x86** (the 1-to-1 reference): `ucomiss a,b` then an **unsigned** jcc (floats are not signed
  integers, so `is_signed=false`): `LT=jb`, `LEQ=jbe`, `GT=ja`, `GEQ=jae`. `ucomiss` sets
  `CF=ZF=PF=1` on an **unordered** (NaN) compare, so on a NaN operand x86 `<` (`jb`, CF=1) and
  `<=` (`jbe`, CF|ZF) come out **TRUE**, while `>`/`>=` come out FALSE.
- **arm64** (goalc `IR_ConditionalBranch::do_codegen_arm64`): `fcmp a,b` then `b.cond`. The
  pre-fix code used `LT→b.MI` (N set) and `LEQ→b.LS` (¬C | Z). On a NaN `fcmp` sets `N=0,Z=0,
  C=1,V=1`, so `b.MI`/`b.LS` come out **FALSE** — the **opposite** of x86 for `<`/`<=`.

`GT→b.GT` and `GEQ→b.GE` already read N,V (unordered ⇒ false), matching x86 `ja`/`jae`, so they
were correct. Only `<` and `<=` diverged.

### Why this is THE collision glitch (mechanism → symptom)
1. At a degenerate / grazing contact a velocity/separation vector is zero-length, and the
   **unguarded** `vector-normalize!` (`goal_src/jak1/engine/math/vector.gc:599`, and the
   `(/ 0.0 0.0)` at `collide-shape.gc:740`) produces a **NaN** — *identically on both backends*
   (plain IEEE FDIV; the NaN is not itself a divergence).
2. That NaN becomes `coverage = (vector-dot sv-80 best-tri-normal)` in the target reaction
   (`collide-reaction-target.gc:139-140`).
3. The push-out logic then tests it: **`(< (-> arg0 coverage) 0.0)`** (`:141`) and
   **`(< (-> arg0 coverage) 0.9999)`** (`:145`).
   - **x86**: `(< NaN …)` = #t → **enters** the coverage-recovery + low-coverage-surface branch
     (re-flattens/re-normalizes, sets the wall/under-map classification) → correct push-out.
   - **arm64 (pre-fix)**: `(< NaN …)` = #f → **skips** that branch → NaN coverage persists and
     the surface is mis-classified → a finite-but-**wrong** push-out = the clip / eject / under-map.

This explains every prior dead-end:
- The **fmin/fmax fix** (Gcollision-nanroot, op-proven 576/576) is a **different op** — there is
  no fmin/fmax on this push-out path, so it could never sanitize the NaN here.
- The collision **arithmetic is bit-identical** arm64↔x86 (two independent disassembly audits:
  no rsqrt estimate, no FMA, no integer divide, FTZ off on both, no mips2c allowlist asymmetry),
  so every "divergent collision op" hunt correctly found nothing — the divergence is in a
  **conditional branch consuming the NaN**, not in the math.
- The post-frame reaction-output **capture saw finite values** because the NaN is a *consumed
  intermediate*; the wrong branch yields a finite-but-wrong push-out.
- It is **degenerate-only** (NaN only at zero-length contacts), matching "not headless-reachable
  on flat ground / only at grazing contacts," and matches the documented but deferred Gtitle
  bug `(>= c NaN)` wrongly #t (an inverted `>=` routes through `LT`).

## The x86 oracle on the real operands (NAMED, BEFORE → AFTER)
`cmp_oracle.cpp` runs the EXACT goalc-emitted instructions on BOTH backends — on the **real
device (eae4df44)** and the x86 host — over the captured operand set, including the exact
**0.0/0.0 NaN** the collision normalize produces (computed at runtime so it is not folded).
- **BEFORE**: 84 / 726 rows diverge (arm64 ≠ x86) — every one with a NaN operand (LT 21, LEQ 21,
  EQ 21, NE 21). The collision row: x86 `(< NaN 0.0)=#t` vs **arm64 `(< NaN 0.0)=#f`** (wrong).
- **AFTER**: arm64 == x86 on **all 42 LT/LEQ rows** (incl. `(< NaN 0.0)=#t`), with **zero
  regression** on finite/Inf/±0 operands (only the unordered result changed).
- Residual (42 rows, EQ/NE-with-NaN): x86's `je`/`jne` treat unordered as EQUAL (ZF=1) — a
  separate x86 flag quirk. **Out of scope**: not on the collision push-out path (the ranked
  divergent sites are all `<`), float `=`/`!=` with a NaN operand is rare, and matching it needs
  a multi-instruction V-flag fold-in on every float ==/!= branch that risks the delicate
  float-branch codegen (cf. the A34 SIGSEGV history). Documented, intentionally not changed.

## The change (translation layer only)
`goalc/compiler/IR.cpp`, `IR_ConditionalBranch::do_codegen_arm64`, float conditions only:
```
LT  : ARM_COND_MI  ->  ARM_COND_LT   // N!=V  : a<b OR unordered  == x86 jb
LEQ : ARM_COND_LS  ->  ARM_COND_LE   // Z|N!=V: a<=b OR unordered == x86 jbe
```
`GT`/`GEQ` unchanged (already match x86). `do_codegen_x86` is byte-untouched. **No goal_src
edit** — the bug is purely in the arm64 backend; the GOAL source and the x86 build remain the
1-to-1 reference. One codegen site covers both the branch form and the boolean-value form
(`compile_condition_as_bool` reuses `IR_ConditionalBranch`).

## Build / deploy / gates
- **x86 unbroken**: `build-x86` rebuilt; smoke reaches `link finish: logo` (arm64-only change ⇒
  x86 output byte-identical; the x86 oracle / `.autoport/gold` stay pristine).
- **Full consistent arm64 build**: `build-arm64/goalc` (and `build/goalc`) rebuilt with the fix;
  `build_arm64_full_consistent.sh` rebuilt all **28** CGOs/DGOs (ENGINE.CGO carries the fixed
  `collide-reaction-target` / `collide-shape` comparisons; its arm64 sha differs from the x86
  oracle ENGINE.CGO, confirming the codegen change landed). Deployed to eae4df44 and
  `deploy_verify.sh eae4df44` PASS.
- **Owner gate**: the owner play-tests the fixed build (their eye is the final gate).

## Temp instrumentation REMOVED (clean build)
The phase's temporary collision-dump instrumentation was **removed** from
`game/kernel/jak1/kmachine.cpp` before the final build so the deployed libgk is clean and
carries no per-frame capture overhead:
- `collision_glitch_capture_tick()` (the glitch-triggered reaction-math dump) and its
  declaration + per-frame call site in `pc_set_levels` — **deleted**.
- the prior `pad_replay_dump_collision_state()` collision-state dump and its
  `pad_replay::set_state_dump_callback(...)` registration — **deleted**.
No leftover collision-dump instrumentation remains in HEAD; the only substantive change vs the
phase anchor is the `goalc/compiler/IR.cpp` codegen fix. The diagnostic harnesses
(`cmp_oracle.cpp` and its outputs) live under `.autoport/reports/Gcollision-glitchcapture/` as
evidence, not in the game build.

## Files
- Fix: `goalc/compiler/IR.cpp` (`IR_ConditionalBranch::do_codegen_arm64`).
- Evidence: `.autoport/reports/Gcollision-glitchcapture/` — `cmp_oracle.cpp`, `cmp_x86.txt`,
  `cmp_arm.txt`, `cmp_oracle_summary.txt`, `cc_drive_dump.txt`, `report.txt`.
- Removed: temp instrumentation in `game/kernel/jak1/kmachine.cpp`.
