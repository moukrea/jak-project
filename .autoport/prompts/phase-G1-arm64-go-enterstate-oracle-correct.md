# Phase G1 — make the arm64 `go`/`enter-state` control transfer OBJECTIVELY CORRECT vs the x86 oracle (recover the title; keep the cinematic)

## Why this phase exists (read carefully — this is a methodology reset)

The previous phase (F1f) fixed the `go`/`enter-state` control transfer *enough* to play the new-game cinematic and spawn Jak ONCE (run19: 344 target positions, 0 crash), but it **regressed the title screen into a crash** and was never verified against the x86 oracle. `enter-state`/`go` is the engine's universal state-transition mechanism — title attract, cinematics, and gameplay ALL use it — so a fix that's right for one path and wrong for another destabilizes everything. We will not "verify by Jak spawning"; we verify by **oracle equivalence**.

## Hard facts (use them)

- **Regression signature (device, title):** `GK-DIAG sig=11 fault=0x7effffffec pc=0x75b286f2e4 lr=0x75b286f2c0`. `fault=0x7effffffec` is a near-top-of-range/stack address = **control transfer to a garbage address** = a corrupted return address / wrong RA save-restore in some `enter-state`/return path. This is NOT the old F1e reveal crash (`fault=0x28`, fixed).
- **Where the change lives:** the go-transfer edit is in **`goalc/compiler/CodeGenerator.cpp`** (commit `19bb8e50a`: "pop the pushed RA into X30 at enter-state's .jr") PLUS uncommitted kernel asm in **`game/kernel/asm_funcs_arm64.s`** and **`game/kernel/jak1/klink.cpp`** / **`game/mips2c/mips2c_table_jak1_arm64.cpp`** (now versioned in WIP commit `5b70c8d59`). A compiler change recompiles every `enter-state`/`go` in the whole engine — broad blast radius.
- **Last VERIFIED-stable title:** commit `e1f35fc0c` (F1e close — title flies, reveal crash fixed, 3×149s clean boots, input bridge + menus working). Use it as the regression baseline.
- **The gain to preserve if possible:** WIP `5b70c8d59` plays the new-game intro cinematic (Daxter animates in human form) and spawns Jak. (Jak falling through the floor / not visibly rendering is a SEPARATE collision/render defect — OUT OF SCOPE here, that's G2.)

## Mandate (oracle-driven, in order)

1. **Oracle-diff the mechanism.** The GOAL `go` / `enter-state` / state-return / `.jr` path compiles to a WORKING x86 build (`build-x86/game/gk` exists). Disassemble and diff the compiled `enter-state` and its return/`.jr` path **x86 vs arm64** (the A26/A27/bug-#13 method: oracle disasm diff, break-traps, RA/SP tracing). The arm64 RA save/restore + control-flow contract MUST match x86 semantics. `fault=0x7effffffec` tells you a return address is being restored from / jumped to garbage in SOME enter-state path — find which path and why x86 gets it right and arm64 doesn't.
2. **Bisect the blast radius.** Build matrix over {`CodeGenerator.cpp` go-change present/reverted, `asm_funcs_arm64.s` change present/reverted} against (a) title boots+flies (no `sig=11`), and (b) cinematic plays. Identify the minimal change set that satisfies BOTH, or proves they conflict.
3. **PRIORITY FLOOR (non-negotiable): the title MUST end stable.** A stable flying title with NO cinematic BEATS a crashing title. If you cannot make the oracle-correct `go` fix coexist with a stable title within this phase, **revert the regressor** (restore `e1f35fc0c`-equivalent behavior), confirm the title flies crash-free, and document the correct go-fix as the residual for a follow-up. Do NOT ship a crashing title.
4. **STRETCH: oracle-correct `go` that keeps BOTH.** Land the enter-state/RA fix so it matches x86 AND (a) the title flies crash-free AND (b) the new-game cinematic still plays. Verify the cinematic on device.
5. **Rebuild discipline:** if any CGO changes, regen + sync ALL 28 CGO/DGOs to APK assets. x86 CGOs byte-identical; x86 boots to `link finish: logo`; qemu ≥ 675. Preserve ALL prior fixes (F1c modulo/MSUB, F1e Adreno sync, F1d input bridge).
6. **Use the worker subagents** (researcher for the oracle disasm diff, implementer for the precise emit edit, tester for the build/qemu/device runs) per the WORK ECONOMY preamble.
7. **`G1-fix-summary.md`** (≥80 lines): the oracle disasm diff (x86 vs arm64 enter-state/return), the root cause of `fault=0x7effffffec`, the bisect matrix, the fix (or the documented revert + residual), and the title-stable + cinematic evidence (device boots, focus brackets, frames labeled by VERIFIED content).

## Rules / Anti-cheat (hard)

Locks: `goalc/emitter/IGenX86_64.{cpp,h}` (x86 oracle — NEVER edit), `goal_src/**` (shared, correct on x86), `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, `.claude/agents/**`, other phase prompts. You MAY edit `goalc/compiler/CodeGenerator.cpp`, `goalc/emitter/IGenARM64.cpp`, `game/kernel/asm_funcs_arm64.s`, `game/kernel/jak1/klink.cpp`, `game/mips2c/*arm64*` (the arm64 mechanism). No fault-swallow / no skipping states / no hardcoded poses. `export ANDROID_SERIAL=eae4df44` only; keyguard check; reversible app disables with guaranteed RE-ENABLE; pgrep leftover run scripts before device runs. The supervisor re-captures independently and judges the title by pixels.

## Validator (`phase-G1-arm64-go-enterstate-oracle-correct.sh`) — STRICT, TITLE-REGRESSION GATE

PASS requires a real **`G1-fix-summary.md`** (≥80 lines; MUST reference `enter-state`/`go`/control-transfer AND the oracle disasm diff AND `0x7effffffec`) PLUS the newest `G1-routed-logcat-*.log` showing **ZERO `sig=11` / signal 11**, frame ≥ 300, tris > 0, set-master-mode reached, PLUS the newest `G1-focus-*.txt` ending on `org.opengoal.gk.jak1` (title stable, app foreground). Plus standard gates: no forbidden edits (IGenX86_64 / goal_src / infra); x86 smoke to `link finish: logo`; qemu ≥ 675; gk_log_pipe; nm renderer syms; ≥ 1 `G1-device-*.png`. Whether the title actually flies (and whether the cinematic still plays) is judged by the supervisor's own eyes. The cinematic is a documented BONUS — the hard gate is a **stable, crash-free, flying title**.

## Max settings

`max_turns: 1200`, `max_retries: 3`. (Tighter than F1f — single defect, oracle-bounded. If it can't be done in 1200 honestly, block and report; don't churn.)

## Strategic note

This is the linchpin. `enter-state`/`go` underlies title, cinematic, and gameplay; get it oracle-correct and three things stabilize at once. The x86 build is the ground truth sitting in `build-x86/` — diff against it, don't guess. Recover the flying title first (hard floor), then make the transfer correct enough to also keep the cinematic. Then G2 takes collision/visible-Jak.
