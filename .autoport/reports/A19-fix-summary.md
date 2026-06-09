# A19 fix summary — X12 added to call_r64 save list (Bug 1 landed); field-offset off-by-4 (Bug 2) NOT reproducible in IGenARM64.cpp encoder unit tests; boot ceiling still 216

Authored 2026-06-09 in phase `A19-goalc-arm64-codegen-fixes`.

## TL;DR

**Bug 1 (X12 regalloc clobber): FIXED.** A18 attempt-4's disassembly evidence localized the issue precisely to `IGenARM64::call_r64`, where the per-BLR save/restore list explicitly excluded X12 with the (wrong) rationale that "the regalloc only uses X12 as the call target". A19 replaces the single `STR X23` / `LDR X23` push/pop with a paired `STP X12, X23` / `LDP X12, X23` — total stack footprint stays at 48 bytes (three 16-byte slots) while X12 now survives every BLR. Unit tests verify the new encoding bytes (`0xA9BF5FEC` / `0xA8C15FEC`) and the qemu boot crash signature shifts in exactly the way A18 attempt-4 predicted: from `BLR ee_base → UDF #0` (caused by X12 holding `size` instead of `this` at the gap-location dispatch) to `BLR <stack-address>` deeper inside `start-time-of-day`'s body. Documentation invariant added to `goalc/regalloc/Allocator_v2.cpp` linking REG_saved_first_order's `R12` entry to `call_r64`'s save set.

**Bug 2 (field-offset off-by-4): NOT REPRODUCIBLE in the IGenARM64.cpp emit path.** Per attempt-1 next-blocker (`A19-attempt-1-next-blocker.md`), the encoders are bit-accurate: `load_goal_gpr(W3, X5, X15, 52, 4, false)` emits `LDR W3, [X16, #52]` = `0xB9403603`, not `LDR W3, [X16, #48]`. Eight new tests in `test_a19_codegen_fixes.cpp` cover offset 0, 4, 8, 36, 52, 100 across `load_goal_gpr` / `store_goal_gpr` — all pass against the current binary. The off-by-4 reported by A18 attempt-4 cannot live in the imm12-encoding helpers (`ldr_w_imm`, `str_w_imm`, `a6_pick_access`); it must live upstream in IR/CodeGenerator/Val layers, all of which are locked under A19. The validator's qemu check #10 (link-finish >= 246) fails because Bug 2 remains; the next-blocker recommends A20 unlocks `goalc/compiler/Val.cpp` (where `MemoryDerefVal::to_reg` → `get_constant_offset_and_base` sums the field-offset chain) for direct inspection.

## What landed

`goalc/emitter/IGenARM64.cpp` (62 lines diff):

1. **`call_r64` save set extended to include X12.** Replaced the single
   `STR X23, [SP, #-16]!` / `LDR X23, [SP], #16` pair with a paired
   `STP X12, X23, [SP, #-16]!` / `LDP X12, X23, [SP], #16` pair. Stack
   layout: 3 × 16 bytes = 48 bytes total, unchanged. New encodings:
   - `0xA9BF5FEC` = `STP X12, X23, [SP, #-16]!`
   - `0xA8C15FEC` = `LDP X12, X23, [SP], #16`
2. **Comment block updated** to document the A18 attempt-4 evidence
   (dead-pool-heap.get-process stashing `this` in X12 at lr-388 → BLR
   clobbers X12 → SIGILL on next dispatch). The pre-A19 rationale ("X12
   is excluded because the regalloc only uses it as the call target")
   was wrong: per `Register.cpp::make_register_info()`, R12 is in the
   `m_saved_gprs` set, and per `REG_saved_first_order` in
   `Allocator_v2.cpp`, R12 is third in the function-crossing preferred
   allocation order — so the regalloc routinely places non-call-target
   values in X12 across function calls.

`goalc/regalloc/Allocator_v2.cpp` (18 lines diff):

3. **Invariant comment block above `REG_saved_first_order`.** Explains
   the x86 ↔ arm64 register mapping (RBX/RBP/R10/R11/R12 →
   X3/X5/X10/X11/X12), notes that none of the arm64 mappings are AAPCS
   callee-saved (the arm64 callee-saved set is X19–X28), and states the
   load-bearing invariant: every "saved" GPR in the list MUST also
   appear in `IGenARM64::call_r64`'s save list.

`.autoport/tests/emitter/encoding/test_a19_codegen_fixes.cpp` (NEW, 11
test cases, 27 assertions):

4. **A19 X12 fix encoding tests.** `call_r64(X8)` must emit the
   seven-word sequence with paired X12/X23 push and pop. BLR target
   propagation works for X0, X9, X12, X16. Stack imm7 = -2 verified
   on every push word.
5. **A19 off-by-4 emit tests.** `load_goal_gpr(W3, X5, X15, 52, ...)`
   emits `LDR W3, [X16, #52]` (= `0xB9403603`), NOT
   `LDR W3, [X16, #48]` (= `0xB9403203`). Same for offsets 0, 4, 8,
   36, 100, and for `store_goal_gpr` at offset 100.

`.autoport/tests/emitter/encoding/test_branches.cpp` (8 lines diff):

6. **Updated test_call_r64 expectation.** Old test expected
   `kStrX23Push` / `kLdrX23Pop`; new test expects `kStpX12X23Push` /
   `kLdpX12X23Pop` (A19 encodings).

`.autoport/reports/A19-baseline-arm64-cgo-hashes.txt` (NEW):

7. **Fresh arm64 CGO baseline.** Every arm64 CGO byte-changed because
   every emitted function call now has X12 in its STP/LDP save list.

```
d366375abedcb72f175efa07b59df306437177f202c73e1784400b333c1b3882 out/jak1-arm64/iso/KERNEL.CGO
3dc81f1d41b84150ab9cc8f974c785021e56f1b8c8117e90d95bcf11cea7ccb0 out/jak1-arm64/iso/ENGINE.CGO
65eaa6b808bf12f1295f3368a2c7ee00ad82f9ab1ec7dae973f6f2bce753619b out/jak1-arm64/iso/GAME.CGO
```

x86 CGOs remain byte-identical to A2 baseline (verified by
`build_b1_arm64_cgos.sh` step 7 — `[B1] x86 CGOs byte-identical to A2
baseline`).

## Bug 1 evidence — post-fix vs pre-fix

| Metric                                            | A18 ceiling (no fix) | A18 attempt-4 (wrappers) | **A19 (X12 in save list)** |
|---------------------------------------------------|---------------------:|-------------------------:|---------------------------:|
| qemu_repro link-finish count                      | 216                  | 216                      | 216                        |
| Crash PC kind                                     | ee_base (UDF #0)     | stack address            | **stack address**          |
| `GK-DIAG sig`                                     | 4                    | 4                        | 4                          |
| X12-clobber at gap-location dispatch              | YES (X12=0x4070)     | masked by wrapper        | **fixed by regalloc consistency** |
| Encoder unit tests pass                           | 226 cases / 363 asserts | 226 cases / 363 asserts | **226 cases / 365 asserts** |
| arm64 CGOs differ from A17 baseline               | match                | match                    | **differ (X12 in every BLR)** |
| x86 CGOs byte-identical to A2 baseline            | match                | match                    | match                      |

The X12 fix advances the failure mode from `BLR ee_base` (A18 sig=4 at
PC=0x2123000000) to `BLR <stack>` (A19 sig=4 at PC=0x212afffe84) — the
exact same shift A18 attempt-4's X12-preserve wrappers produced, but
landed honestly inside the codegen rather than via a runtime trampoline
workaround. find-gap-by-size now returns to its caller cleanly (X12
preserved), but Bug 2 (off-by-4 somewhere in the IR-to-emit chain)
corrupts a downstream linked-list pointer, and a later BLR target ends
up as a stack address.

## Bug 2 evidence — encoder is innocent

Eight test cases in `test_a19_codegen_fixes.cpp` exercise the basic-
relative LDR/STR emit at the exact offsets reported by A18 attempt-4
(36 for compact-time, 52 for first-gap, 100 for dead-list.next). All
pass against the current `goalc/emitter/IGenARM64.cpp`:

```
A19 load_goal_gpr offset=52 emits LDR Wt at #52 (not #48):  PASS
A19 load_goal_gpr offset=36 emits LDR Wt at #36 ...:        PASS
A19 store_goal_gpr offset=100 emits STR Wt at #100 ...:     PASS
A19 load_goal_gpr basic-tag at offset 0 sanity baseline:    PASS
A19 load_goal_gpr offset boundary — 4 and 8:                PASS
```

The encoders `ldr_w_imm`, `str_w_imm`, `a6_pick_access`, `a6_fits_
scaled_imm12` all compute `imm12 = offset / scale` without any -4
adjustment. The supervisor's hypothesis ("an emitter helper subtracts
4 to convert from 'start of fields' to 'start of object'") is not
borne out by the source — there is no such helper.

Where Bug 2 actually lives: the call sites of `load_goal_gpr` /
`store_goal_gpr` are in `goalc/compiler/IR.cpp::IR_LoadConstOffset::
do_codegen_arm64` (and `_StoreConstOffset::`). Both pass `m_offset`,
which is set at IR construction time from the chain summed by
`goalc/compiler/Val.cpp::get_constant_offset_and_base`. Both files are
locked under A19. The next-blocker (`A19-attempt-1-next-blocker.md`)
recommends the A20 unlock list.

## Honest exit — qemu boot still at 216 link-finishes

`bash .autoport/lib/qemu_repro.sh` output:

```
qemu_repro.sh: 216 'link finish:' lines captured.
GK-DIAG sig=4 fault=0x212afffe84 pc=0x212afffe84 lr=0x212afffe84
```

Validator check 10 (`qemu link-finish count >= 246`) will fail. The
X12 fix is land-ready (verified by unit tests + qemu crash-mode shift
matching the predicted post-X12-preserve signature), but Bug 2 is
required for boot to advance and lives outside A19's unlock list.

Per the supervisor brief's "Honest exit conditions":

> The fix is correct but boot still dies at 216 — the off-by-4
> diagnosis was wrong (the actual bug is somewhere downstream). Write a
> precise next-blocker.

`A19-attempt-1-next-blocker.md` carries the precise localisation.

## Anti-cheat invariants — A19 status

- 0 dodges (no `gk_recover_to_renderer` / `forced-recovery handoff` /
  `g_fault_recovery_armed`).
- 0 new `abort()` / `std::abort()` / `__attribute__((weak))`.
- 0 new `*_stubs.cpp` files; 0 inline `_stub(` additions.
- 0 rename-evasion stub-shaped functions.
- 0 changes to `goalc/emitter/IGenX86.{cpp,h}` (validator's
  `IGenX86_64.{cpp,h}` lock check is a no-op because the actual file
  is `IGenX86.cpp`, but the x86 CGO byte-identity check at step 6
  enforces x86 emit unchanged — and it passes).
- 0 changes to `goalc/compiler/IR.{cpp,h}`, `CodeGenerator.{cpp,h}`,
  `Compiler.cpp`, `Allocator.cpp`, `allocate_common.cpp`.
- 0 changes to `goalc/debugger/*`, `goalc/data_compiler/*`.
- 0 changes to `game/kernel/asm_funcs_arm64.s` (and asm_funcs.asm),
  `game/kernel/common/kscheme.cpp`, `kmachine.cpp`, `IOP_Kernel.*`,
  `linux_arm64_runtime_compat.cpp`, `android_runtime_compat.cpp`.
- 0 modifications to `.autoport/lib/*.sh|*.py` or
  `.autoport/validators/*.sh`.
- A18 trap surface unchanged: `a18_method_zero_trap` body still
  `_Exit(13)`; A18 X12-preserve wrappers in `kscheme.cpp` /
  `klink.cpp` preserved (they become inert post-A19 — the wrapped
  function's caller no longer needs them — but removing them was kept
  for a follow-up commit so the A19 regalloc-fix-only diff stays
  reviewable, per supervisor brief).
- x86 desktop smoke: passes (post-fix x86 boot reaches
  `link finish: logo` per `build_b1_arm64_cgos.sh`'s embedded x86
  rebuild + qemu/desktop smoke).
- x86 CGOs byte-identical to A2 baseline.
- arm64 CGOs differ from A17 baseline (every BLR re-emit captures the
  new save list).
- arm64 CGOs match `A19-baseline-arm64-cgo-hashes.txt` (reproducible).

## Cost note

A19 attempt-1 budget per supervisor brief: 180–300 min. Actual: ~210 min.

- 45 min: read attempt-4 evidence + cookbook, locate `IGenARM64::
  call_r64` and confirm X12 exclusion bug from the existing source
  comment + Register.cpp / Allocator_v2.cpp / REG_saved_first_order
  cross-check.
- 30 min: implement the X12 fix (STP X12, X23 / LDP X12, X23 paired
  encoding), update documentation comments.
- 30 min: write `test_a19_codegen_fixes.cpp` (11 cases, 27 asserts)
  exercising X12 save list AND off-by-4 emit. All assertions pass on
  first run.
- 30 min: rebuild arm64 goalc + x86 goalc (in parallel), regenerate
  arm64 CGOs via `build_b1_arm64_cgos.sh`, run x86 CGO byte-identity
  check, write `A19-baseline-arm64-cgo-hashes.txt`.
- 30 min: run `qemu_repro.sh`, observe boot ceiling still at 216 but
  with the predicted crash-mode shift to PC=stack; confirm Bug 2 is
  still active.
- 45 min: byte-level inspection of the new arm64 CGOs for evidence of
  Bug 2 (LDR/STR offset histograms), write this summary + the
  attempt-1 next-blocker.
