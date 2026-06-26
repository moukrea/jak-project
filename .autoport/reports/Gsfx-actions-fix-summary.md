# Gsfx-actions — fix summary

## Owner report (2026-06-25)
On the arm64 device, breaking a crate (`wcrate-break`/`icrate-break`/…) and
collecting orbs (`buzzer-pickup`), blue-eco and green-eco produce **NO SOUND**;
the x86 build plays them. Directive: per-source / per-sound-name, find which
action `snd-play` triggers produce 0 on device and fix the arm64 divergence in
the translation layer (goal_src stays 1-to-1).

## Methodology — x86-first, per-sound-name capture (deterministic, not "it ran")
A previous phase (Gaudio-sfx) already proved the 989snd synth → AAudio path is
functional (a forced snd-play hit the x86 full-volume peak on device). So the
silence had to be UPSTREAM of the synth — in *which* sound the RPC asks for. I
added a small **gated debug probe** to the 989snd PLAY handler
(`game/overlord/jak1/srpc.cpp`, `RPC_Player`, case `PLAY`) that logs, per PLAY
command: the raw 16-byte `cmd->play.name` (printable + hex), `sound_id`,
`volume`, `pitch`, `bend`, `trans`, falloff, `mask`, the `LookupSoundIndex`
result, and the returned voice handle. Gated off by default
(`OPENGOAL_SFX_PROBE=1` / `debug.opengoal.sfx.probe=1`).

I captured the SAME sounds on the x86 desktop build (ground truth) and on the
arm64 device (eae4df44), at the title flythrough and in Geyser Rock gameplay
(warp via `debug.opengoal.f1.warp`, drive + spin-attack to break a real crate).

## What the measurement PROVED (the first divergent value)
- x86: action sounds pack into a correct 16-byte name and resolve to a real bank
  index — `wcrate-break` idx=65, `icrate-break` 66, `scrate-break` 67,
  `dcrate-break` 69, `buzzer-pickup` 352, `cell-prize` 192, `water-drop` 415.
- arm64 DEVICE, same scene: ~68% of in-game positional SFX arrived with a
  **corrupted name** — a host/GOAL pointer instead of the packed string, e.g.
  `hex=801fe62374000000…` (= 0x74_23e61f80, a host pointer, ×9878) and
  `hex=b4ec1800000000…` (= 0x18ecb4, a GOAL pointer, ×2628). `LookupSoundIndex`
  does a 16-byte `memcmp`, so a pointer never matches a name → `idx=-1` → the
  PLAY is dropped → SILENT. An immediate `(sound-play "water-drop")` was ABSENT
  on device entirely (count 0) while firing hundreds of times on x86.
- The first divergent value is therefore `cmd->play.name`: correct on x86,
  pointer-garbage on arm64.

## Root cause (goalc arm64 codegen) — proven by disassembly
`sound-name` is `(deftype sound-name (uint128) …)` — a **128-bit VALUE** type,
passed by value in a SIMD/XMM-model register. In goalc, register ids are
**x86-model throughout** (XMM0..XMM15 = ids 16..31; the AArch64 bank split is
encode-time only). `Register::is_gpr(ARM64)` (goalc/emitter/Register.h) tests the
arm64-native range `X0..X30` = ids 0..31 — which **also covers the x86-model XMM
id range 16..31**. So on arm64 `is_gpr` is wrongly true for every XMM-id register.

The function/method ARGUMENT classifier used
`arg_regs.at(i).is_gpr(m_instr_set) ? GPR_64 : INT_128`, so on arm64 **every
128-bit value argument was mis-classed `GPR_64`**. A minimal repro (uint128 arg,
an intervening call, store into a struct field) disassembled on both backends:
```
BEFORE (arm64): fmov x3, d17        ; mov igpr-3, igpr-0   <- 128-bit arg TRUNCATED to a 64-bit GPR;
                                    ;                         high half lost + clobbered across the call
AFTER  (arm64): mov v24.16b, v17.16b; mov ii128-3, ii128-0  <- FULL 128-bit value in a V register,
                str q24, [sp,#-0x10]!;                          saved across the call, then
                str q24, [x16,#0x10] ;                          FULL 128-bit store of the name.
```
This is the same x86-model-vs-arm64-native id inversion A33 fixed for
`is_128bit_simd`, but the argument classer was left on `is_gpr`. (The RETURN-value
classer already used `is_128bit_simd` — only arguments were wrong, which is why
`string->sound-name`'s *result* survived but `(-> this name)` / immediate
`(sound-play "x")` *arguments* did not.)

## The fix (translation layer only — goalc; goal_src untouched, 1-to-1)
Classify a 128-bit value argument by `is_128bit_simd` (already x86-model-correct
on BOTH backends, and already used for the return value), not by the arm64-broken
`is_gpr`:
```
-  arg_regs.at(i).is_gpr(m_instr_set) ? RegClass::GPR_64 : RegClass::INT_128
+  arg_regs.at(i).is_128bit_simd(m_instr_set) ? RegClass::INT_128 : RegClass::GPR_64
```
- `goalc/compiler/compilation/Function.cpp` — 2 sites (defun arg constraint + param).
- `goalc/compiler/compilation/Type.cpp` — 2 sites (defmethod arg constraint + param).
- NOT `goalc/emitter/IGenX86_64.*` (locked); `is_gpr`/`is_xmm` themselves are left
  unchanged so the rest of the booting arm64 codegen (prologue, spills, IGenARM64
  asserts) is untouched — minimal blast radius.

### x86-neutral by construction (Tier-A safe)
Every x86 argument register is a GPR (`RDI,RSI,RDX,RCX,R8,R9,R10,R11` = ids
1..11) or an XMM (`XMM1..XMM8` = ids 17..24). Over that set `is_gpr` and
`is_128bit_simd` are exact complements, so the new expression yields the IDENTICAL
RegClass for every x86 arg → IDENTICAL x86 codegen and bytes. (A first Tier-A
check vs the ancient pristine gold 704972dd6 reported diffs, but those are
PRE-EXISTING goal_src divergences — e.g. `kernel/gstate.gc` → KERNEL.CGO,
`levels/title/title-obs.gc` → TIT.DGO from earlier phases — NOT this fix; the
fix's x86 RegClass output is provably unchanged.)

## What changed on the device (AFTER)
Full consistent 28-file arm64 CGO/DGO set rebuilt with the fixed goalc (1317
targets, zero codegen asserts) and promoted to the device known-good backup
(`.autoport/backups/device-knowngood-cgos-20260622`; the old set kept as
`…-pre-gsfx-0`). Re-running the probe on the device:
- garbage pointer-name count = **0** (was thousands).
- `wcrate-break` plays with the correct name + a valid bank id (real crate break).
- `water-drop` reappeared (idx=415); `eco-bg-blue` (blue eco), `pill-pickup`
  (green-eco pill), and every footstep/material/action SFX now resolve (idx>=0).
- device lookup distribution: no `idx=-1` in the top — names resolve again.
- boot crash-free to title + Geyser Rock; deploy_verify PASS.

## Temporary instrumentation — REMOVED
The investigation probe was throwaway and has been **deleted** from the tree:
- `game/overlord/jak1/srpc.cpp` was reverted with `git checkout` — the
  `[SFX-PROBE]` `lg::warn` lines, the `sfx_probe_enabled()` / `sfx_name_dump()`
  helpers, and the `<cstdlib>` / `<sys/system_properties.h>` probe includes are
  GONE. Verified: `grep -rn 'SFX-PROBE|sfx_probe_enabled|sfx_name_dump|
  OPENGOAL_SFX_PROBE|debug.opengoal.sfx.probe' game/ android/` returns no
  remaining instrumentation, and the deployed clean HEAD build emits **0**
  `SFX-PROBE` lines in device logcat. No leftover debug spam remains.
- The only retained source change is the 4-site goalc argument-classing fix.
- Investigation harness scripts under `.autoport/` (gsfx_*.sh) are kept as
  reproducible test artifacts; they touch no tracked build inputs.

## Verification summary
- x86: `gk -boot` reaches `link finish: logo` (fix is x86-neutral).
- arm64: full consistent CGO set builds with 0 asserts; device boots crash-free
  to gameplay; per-name capture shows garbage→correct, idx -1→idx>=0.
- Device eae4df44: clean probe-removed HEAD libgk; deploy_verify PASS; 3-min
  smoke 0 sig; SFX-PROBE absent from the clean build.
- Owner ear = final: crate-break / orb / blue-eco / green-eco now reach the
  speaker (correct name → bank hit → voice). goal_src stays 1-to-1.
