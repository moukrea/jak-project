# Phase A5 — emitter-far-relocs

## Status

**Authored 2026-05-21 23:35 by the supervisor.** The user explicitly
authorized unlocking `goalc/emitter/IGenARM64.cpp` +
`goalc/emitter/ObjectGenerator.cpp` for this phase only, to close the
**691-NOP gap** documented at C4 close.

This phase is the **right** fix for what D4 worked around. D4 reached
the title screen on device by adding ~600 lines of compat shims in
`android/android_runtime_compat.cpp` that route the boot path around
GOAL functions containing NOP'd ADRP+ADD pairs. That worked for the
title milestone but accumulates geometric debt: every later phase that
exercises more bytecode (E1 gamepad input, E3 save/load, F1 gameplay)
risks landing on another NOP. The user (correctly) refused that path.

The point of porting OpenGOAL is **feature parity**: identical
behavior on x86-Linux / arm64-Linux / arm64-Android / arm64-macOS /
Windows. A5 makes the emitter capable of producing identical-semantics
bytecode for all of them.

## Bucket

A — emitter / linker (codegen layer).

## Goal

Replace every silently-NOP'd ADRP+ADD pair with a real instruction
sequence that reaches any 64-bit target. After A5 closes, the
post-emit patcher must report **0 NOPs** across all three primary
CGOs (KERNEL, ENGINE, GAME), and re-running D4 must succeed on
device **with the dodge-only shims removed** from
`android_runtime_compat.cpp`.

## Why this is the C4 NOP gap

`ADRP X0, sym` computes a PC-relative page address. The immediate is
signed 21 bits, addressing pages of 4 KB → reachable range is
**±4 GB** from PC. `ADD X0, X0, :lo12:sym` fills the low 12 bits.
Two instructions total.

On Android, libgk.so loads at a high VA (typically
`~0x720000000000`), and the GOAL EE main memory mmaps at a low VA
(typically `~0x10000000`). The page-delta between GOAL bytecode in
the EE heap and a symbol in libgk.so is on the order of
**0x7200000000 ≈ 487 GB**, far beyond what 21 bits can encode. The
C4 patcher detects the overflow at link time and substitutes
`0x00000000` for both instructions — a "silent NOP" that decodes as
`UDF` on AArch64 and faults with SIGILL the moment execution reaches
it. C4 documented 691 such NOPs in
`.autoport/reports/C4-execute.md` and the patcher emits a count to
the report `.autoport/reports/C4-nop-report.txt` (if present; check
the actual artifact name).

## Approach

Implement a "far reloc" sequence in `goalc/emitter/IGenARM64.cpp` +
`goalc/emitter/ObjectGenerator.cpp`. Two viable instruction
sequences:

**Option A — `movz/movk` chain (recommended starting point):**

```
movz  X0, #(sym >>  0) & 0xFFFF, lsl #0
movk  X0, #(sym >> 16) & 0xFFFF, lsl #16
movk  X0, #(sym >> 32) & 0xFFFF, lsl #32
movk  X0, #(sym >> 48) & 0xFFFF, lsl #48
```

Four instructions, sets X0 to an absolute 64-bit address. Works for
any target. Costs 2 extra instructions per far reference vs. the
in-range ADRP+ADD.

**Option B — literal pool LDR:**

```
ldr   X0, =sym     ; assembler-style; expands to:
                    ; ldr  X0, [pc, #offset_to_literal]
                    ; ...
                    ; literal: .quad sym
```

Two instructions of code + 8 bytes of read-only data in a nearby
literal pool. PC-relative LDR has ±1 MB range (19-bit signed × 4),
which is plenty within a function. Smaller code than Option A but
adds a pass to place the literal pool and patch the LDR offset.

**Recommendation:** start with Option A (simpler, correctness-first).
Optimize to Option B in a follow-up if size proves to matter.

You may also choose a hybrid: emit ADRP+ADD when the delta is known
at emit time to be in-range, fall back to the far-reloc sequence
otherwise. The post-emit patcher already classifies references — use
that classification at emit time if it's available.

## Scope (locks)

**UNLOCKED for A5 only:**

- `goalc/emitter/IGenARM64.cpp`
- `goalc/emitter/ObjectGenerator.cpp`

These two files revert to byte-identical-to-A5-close after this
phase commits.

**STILL LOCKED — do not touch:**

- `goalc/compiler/IR.cpp` (locked since A4)
- `goalc/emitter/IGenARM64.h` (locked since A4)
- `goalc/emitter/ObjectGenerator.h` (locked since A4)
- `goalc/compiler/CodeGenerator.cpp` (locked since A4)
- `goalc/compiler/CodeGenerator.h` (locked since A4)
- `.autoport/lib/classify_ir_arm64.py` (locked since A1)

The classifier is locked because it defines the contract the emitter
fulfils — changing it would invalidate A1-A4's coverage proofs.

## Required outputs

1. **Emitter implementation** in `goalc/emitter/IGenARM64.cpp` +
   `goalc/emitter/ObjectGenerator.cpp` that emits the far-reloc
   sequence for any reference that would otherwise overflow ADRP's
   ±4 GB range.

2. **CGO regeneration** via the existing pipeline. Run the same
   script B1 uses (likely `build/goalc/goalc -c "(mi)"` or the
   wrapper at `.autoport/lib/build_a2_smoke.sh`) so the new emitter
   produces new bytecode in
   `out/jak1/iso/{KERNEL,ENGINE,GAME}.CGO`. The **x86** CGOs must
   stay byte-identical to A2 baseline; if the goalc target is
   currently arm64, those outputs change byte-for-byte. The
   validator records new arm64 baselines.

3. **Post-emit patcher report** showing **0 NOPs** across all three
   CGOs. The existing patcher at `.autoport/lib/a4_arm64_patcher.py`
   produces this report; if the format needs extending to count NOPs
   per-CGO, add the counter there.

4. **Cross-bucket re-validation**: run B1, B2, C2, C3, C4 in
   sequence. All must pass. The C4 validator's "NOPs ≤ 691"
   tolerance becomes "NOPs == 0".

5. **D4 re-run** with the new CGOs. D4 must still PASS all 18
   checks with the same marker scoreboard. This proves the new
   bytecode is at least as good as the old (the dodge-shims still
   present at this point).

6. **Shim audit** in `android/android_runtime_compat.cpp`. For each
   C++ shim that was added in D4 (commits `2db057b0b` /
   `dcc68eb9e`), determine: does the bytecode now have a working
   implementation of the function the shim overrides? If yes,
   delete the shim. The audit must produce
   `.autoport/reports/A5-shim-audit.md` listing every shim with
   its disposition (keep / delete / keep-as-Bionic-adapter / etc.).

7. **D4 re-run, second pass** after the shim audit removes the
   dodge-only shims. D4 must STILL PASS with the trimmed compat
   layer. This proves the bytecode actually does the work, not the
   shims. If D4 fails at this step, restore the shims that were
   needed; the validator will then require an explicit justification
   in the audit report for each retained shim.

## Anti-cheat invariants

A5 enforces these invariants on top of the codegen unlock:

- The classifier `.autoport/lib/classify_ir_arm64.py` stays
  byte-identical to A1.
- `goalc/compiler/IR.cpp`, `goalc/emitter/IGenARM64.h`,
  `goalc/emitter/ObjectGenerator.h`,
  `goalc/compiler/CodeGenerator.{cpp,h}` stay byte-identical to A4.
- x86 CGOs stay byte-identical to A2 baseline (the goalc x86
  emission path is not touched).
- `out/jak1/iso/KERNEL.CGO`, `ENGINE.CGO`, `GAME.CGO` change
  byte-for-byte when targeting arm64 (the whole point of A5); save
  the new hashes to `.autoport/reports/A5-baseline-arm64-cgo-hashes.txt`.
- 0 new `*_stubs.cpp` files since D3 commit `45bfe26c9`.
- 0 new `abort()` / `std::abort()` in `.cpp` / `.h` / `.s`.
- 0 new `__attribute__((weak))` in `.cpp` / `.h` / `.s`.
- Desktop x86 `build-x86/game/gk` still reaches
  `link finish: logo` on the smoke test.

## Reality check toolkit

- `nm --defined-only --demangle build-android/lib/arm64-v8a/libgk.so`
  to confirm the emitted bytecode binary has no unresolved
  cross-references.
- `objdump -d` on the regenerated arm64 CGOs to manually verify
  the movz/movk chain appears at the formerly-NOP'd sites.
- `.autoport/lib/a4_arm64_patcher.py` post-emit NOP report.
- `.autoport/lib/trace_diff.py` against the desktop arm64 oracle
  trace at `.autoport/oracle/jak1-desktop-trace.txt` — the boot
  trace from A5's regenerated bytecode should match desktop arm64
  more closely than D4's did (since D4's pass relied on shims
  routing around bytecode the desktop oracle does execute).

## Cost expectation

This is a heavy phase. Realistic estimate:

- Emitter design + implementation: ~1-2 hours.
- CGO regeneration + B1/B2 re-run: ~30 min.
- C2/C3/C4 re-run: ~15 min.
- D4 re-run (twice — once before shim audit, once after): ~10 min
  each (device install + 60s capture).
- Shim audit: ~1-2 hours (read every shim, decide disposition,
  delete dodge-only ones, re-test).

Total: probably 3-6 hours of claude time, $40-80 in rate budget.
This is the price of doing the engineering honestly instead of
accumulating shim debt. Future phases (E1-F3) become safer because
the bytecode they exercise is correct on all targets.
