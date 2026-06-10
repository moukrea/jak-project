# Phase A33 — arm64 regalloc/spill sprint: fix the shared hud-classes-pc SIGSEGV (qemu 660 ceiling == device 354 ceiling)

## The convergence (why this is back in the fast loop)

A32 fixed Android's missing pc-helper bindings (`__pc-texture-upload-now`, `__read-ee-timer`, `__send-gfx-dma-chain` + the `__pc-get-mips2c` no-op rebind) and the on-device boot advanced 316 → 354. **The device now dies at `hud-classes-pc` with a SIGSEGV — the SAME DGO + signal where qemu's 660 run dies.** Both environments, same CGOs, same crash point: this is one shared bug, reproducible in qemu. **Use the fast qemu inner loop** (`bash .autoport/lib/qemu_repro.sh <log>`) — no device round-trips needed until the fix lands.

A32's crash characterization (`.autoport/reports/A32-fix-summary.md`, read it + `.autoport/reports/A32-routed-logcat-attempt2.log`): SIGSEGV at PC=0x7f0150113c with a **bogus `0xfd596f80` GOAL ptr spilled to `[SP, #0]`** — suspected **arm64 regalloc/spill bug**. `0xfd596f80` is not a valid GOAL offset (>128 MB heap) — it's either a truncated/sign-mangled 64-bit value, a float reinterpreted as a pointer, or a spill-slot collision (two values sharing [SP,#0]).

## Mandate

1. Reproduce in qemu (it dies at 660, last `link finish: hud-classes-pc`). Use the existing tracer arsenal (A21-A26: OG_REG_BYTE_DUMP, OG_X30_TRACE_EMIT, the 0xBEEF break trap, the A31 BLR-prelude scan is on the Android side but the GK-DIAG handlers in linux_arm64_main.cpp are rich) to capture the crash state. Disassemble around the crash PC and the spill site.
2. Root-cause the bogus spilled value: spill-slot collision in `goalc/regalloc/` (Allocator_v2 spill assignment)? a spill store/reload size mismatch (32 vs 64-bit) in the arm64 spill emit (CodeGenerator.cpp / IGenARM64.cpp)? an XMM-class value spilled through a GPR slot (the A24-A26 class-mismatch family — check `emit_arm64_reg_to_reg_mov` coverage for spill paths)? hud-classes-pc is a `-pc` DGO (PC-port GOAL code) — it may exercise a spill pattern nothing else does.
3. FIX it (real fix, no guards/stubs). Iterate fix → build goalc → regen CGOs (`bash .autoport/lib/build_b1_arm64_cgos.sh`) → qemu. **Keep fixing past 660** — every new ceiling is progress. The display loop / title screen is the far goal.
4. When qemu advances meaningfully: sync CGOs to the APK assets (`android/app/src/jak1/assets/iso_data/jak1/` from `out/jak1-arm64/iso/`), build + install on the device (d4_run.sh, ANDROID_SERIAL=eae4df44, egggameplus disable/re-enable dance), confirm the device advances past 354 too, capture routed logcat + a screencap to `.autoport/reports/A33-device-*.png`. If the device reaches the display loop → judge the screencap honestly (real game content vs black/clear).

## Scope

**UNLOCKED**: everything except hard locks — all of goalc (regalloc/, emitter/IGenARM64, compiler/) except IGenX86_64, game/**, android/**, common/**.

**LOCKED**: `goalc/emitter/IGenX86_64.{cpp,h}` (oracle), `goal_src/**`, `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, other phase prompts.

## Anti-cheat (only hard rules)

1. x86 desktop still boots to `link finish: logo`.
2. No fake link-finish/renderer output; no weak/abort-additions/dodge/`*_stubs.cpp`; no null-guarding the crash site to skip it.
3. No edits to goal_src/, IGenX86_64.*, .autoport infra.
4. Preserve the prior fix/diag infrastructure (gk_log_pipe, A32 pc-helper bindings, A21-A26 tracers, emit_arm64_reg_to_reg_mov dispatch).
5. qemu fix-path bar: **> 660** link-finishes. No-regression floor: ≥ 660. Device claims verified by screencap (black ≠ render).

## Deliverables (lean)

- **A33-fix-summary.md** (≥80 lines) if qemu advances past 660: root cause, the fix, new qemu ceiling, device result if tested (on-device count + screencap path), next blocker.
- OR **A33-attempt-N-progress.md / next-blocker.md** (≥80 lines): named root cause + evidence + exact file/function for the next phase.
- **A33-baseline-arm64-cgo-hashes.txt** if CGOs changed.

## Validator (`phase-A33-arm64-regalloc-spill-sprint.sh`)

Lean: no forbidden edits/cheats; x86 boots; qemu ≥ 660 (fix-summary requires > 660 + baseline file matching actual CGOs); one report ≥ 80 lines.

## Max settings

`max_turns: 2500`, `max_retries: 3`. Budget ~$250.

## Strategic note

This is the first phase on the new default model. The bug gates BOTH environments at once — fixing it advances qemu past 660 AND (after CGO sync) the device past 354, likely deep toward the display loop. The remaining distance to a rendered title screen: this regalloc/spill bug → any residual init crashes → display loop → renderer draws. Go.
