# A17 fix summary — emitter-side IDIV preserve-X8 spill; both qemu and the Redmi Note 9 Pro device advance from 166 → 212 link-finishes (+46 CGOs) without divergence

Authored 2026-05-24 in phase `A17-idiv-emitter-spill`.

## TL;DR

A14 surfaced a `sig=7 SIGBUS` at the `sin*!` call site on
both qemu (link-finish 166) and the Redmi Note 9 Pro device (also 166,
confirmed by A16 diagnostic). The root cause is the arm64 IDIV/UDIV
emit's hardcoded X8 dst+src1 write being invisible to the regalloc:
to_rai() for `IR_IntegerMath` only records `read/write m_dest, read
m_arg, exclude RDX`, so the allocator can park another live value
(notably the `m_func` of a subsequent `IR_FunctionCall`) in X8 across
the IDIV. The SDIV then clobbers that live value with the division
result, and the following BLR jumps to a corrupted pointer.

A15 attempted two regalloc-layer fixes (X8-implicit-clobber awareness,
plus function-crossers promotion) — both passed qemu but caused
**device** regressions of -113 and -101 CGOs respectively. A16's
diagnostic-only phase confirmed the bug is the same on both backends
(no CPU divergence at the baseline) and recommended an emitter-side
fix instead.

A17 implements that emitter-side fix:

- `goalc/emitter/IGenARM64.cpp` adds four new internal helpers
  (`idiv_spill_sub_sp_16`, `idiv_spill_str_x8_sp_0`,
  `idiv_spill_ldr_x8_sp_0`, `idiv_spill_add_sp_16`) plus an A17 block
  comment above `idiv_gpr32` documenting the preserve-X8 protocol. The
  `idiv_gpr32` / `unsigned_div_gpr32` bodies still emit a single SDIV /
  UDIV — the multi-instruction sequence is composed at the IR.cpp call
  site, as anticipated in the phase prompt's "the existing IR.cpp call
  site needs to be updated to emit the sequence inline" path.
- `goalc/compiler/IR.cpp::do_codegen_arm64` for IDIV_32 / IMOD_32 and
  UDIV_32 / UMOD_32 now emits one of two shapes depending on m_dest's
  allocated register:
  - `m_dest == X8` (id 8): the existing 1-instruction emit (just SDIV
    or UDIV). The regalloc explicitly assigned X8 to m_dest, so no
    other live value is parked there; no preserve needed.
  - `m_dest != X8`: a 6-instruction sequence
    ```
    sub  sp, sp, #16        ; idiv_spill_sub_sp_16   = 0xd10043ff
    str  x8, [sp, #0]       ; idiv_spill_str_x8_sp_0 = 0xf90003e8
    sdiv x8, x8, xN         ; idiv_gpr32(arg_reg)
    mov  Xdst, x8           ; copy result to m_dest's allocated reg
    ldr  x8, [sp, #0]       ; idiv_spill_ldr_x8_sp_0 = 0xf94003e8
    add  sp, sp, #16        ; idiv_spill_add_sp_16   = 0x910043ff
    ```
    This is exactly the supervisor's prescribed pseudo-code, with the
    X8-spill encoded as raw uint32_t words because SP (Rn=31) is not a
    standard GPR — the same approach the arm64 prologue uses in
    `CodeGenerator::do_goal_function_arm64` (raw `0xD10003FF | imm12<<10`
    for SUB SP).

Locked-file guarantees preserved end-to-end:
- `goalc/emitter/IGenARM64.h` (the .cpp is unlocked, the .h stays at
  A1 — verified).
- `goalc/regalloc/*` (no allocator change — the whole point of A17;
  verified).
- `goalc/emitter/ObjectGenerator.{cpp,h}`, `CodeGenerator.{cpp,h}`,
  `IR.h`, `klink.{cpp,h}`, `kscheme.cpp`, `kmachine.cpp`,
  `asm_funcs_arm64.s`, runtime-compat files, `IOP_Kernel` — all
  unchanged.
- `.autoport/lib/*` and `.autoport/validators/*` — untouched
  (supervisor-owned).

The IR.cpp change only adds emit-helper forward declarations and
wraps the four IDIV/UDIV switch arms; no other compiler IR or
regalloc code paths are modified.

## Post-fix evidence

| Metric                              | A11 baseline | A14 ceiling | A17 (this)  |
|-------------------------------------|-------------:|------------:|------------:|
| qemu_repro link-finish count        | 156          | 166         | **212**     |
| Redmi Note 9 Pro link-finish count  | (untested)   | 166         | **212**     |
| qemu/device divergence              | n/a          | 0           | **0**       |
| Desktop x86 link-finish (smoke)     | 438+         | 438+        | 438+        |
| arm64 CGO byte-identity vs A11      | match        | match       | **differ**  |
| x86 CGO byte-identity vs A2         | match        | match       | match       |

Last 10 CGOs linked under qemu (identical sequence on device):

```
loader
task-control-h
speedruns-h
game-info
game-save
settings
pc-anim-util
autosplit-h
autosplit
speedruns
pckernel-common
pckernel
```

Net advance: **+46 CGOs (166 → 212)** on both qemu and the
real Cortex-A76 device. The A15 failure mode (qemu passes but device
regresses) is conclusively avoided: byte changes are confined to
IDIV/UDIV sites (one ~6-instruction sequence per call site), the
regalloc's view of register liveness is identical to A14 (because
X8 use is now invisible to it), and no allocation ripples occur in
unrelated functions.

New arm64 CGO hashes (saved to
`.autoport/reports/A17-baseline-arm64-cgo-hashes.txt`):

```
73a83075e5d536cf701abf5a4678137e23e2b8686cbcd5e498630da15a7a52b5  KERNEL.CGO
cf20410db162f8c1e5ee58496caec95421d3733db745281b66a617141a8190ca  ENGINE.CGO
270d6d63cedaf97704c4e595206659d71e4ef7d21836e22fe5fa9b350e31de64  GAME.CGO
```

## What A17 exposes — next-blocker: `pc-get-os` unbound

Both backends now crash AT THE SAME NEW SITE, link-finish 212+,
during `pckernel` top-level execution (the CGO immediately after
`pckernel-common`). Crash signature is the classic unbound-pc-helper
pattern A11/A12/A14 already dealt with:

**qemu**:
```
GK-DIAG sig=4 fault=0x2123000000 pc=0x2123000000 lr=0x2124d51248
GK-DIAG x9=0x2123000000   ←← BLR target = ee_base
GK-DIAG x15=0x2123000000  ←← ee_base
GK-DIAG A11-DIAG texture-sym-zero: slot=0x2123000000 value=0x0 ... name="<empty>" in_sym_range=0
```

**Redmi Note 9 Pro**:
```
GK-DIAG sig=4 fault=0x720a9c2000 pc=0x720a9c2000 lr=0x720aeb4568
GK-DIAG x9=0x720a9c2000   ←← BLR target = ee_base
GK-DIAG x15=0x720a9c2000  ←← ee_base
GK-DIAG A11-DIAG texture-sym-zero: slot=0x720ab1a314 value=0x0
  info=0x720ab3a310 hash=0x8bd2908c str=0x4f3434 name="pc-get-os" in_sym_range=1
```

On the device the A11 diagnostic names the unbound sym precisely:
**`pc-get-os`** (hash `0x8bd2908c`). The sym slot exists but has value 0
because no `make_function_symbol_from_c("pc-get-os", …)` call ever
registers it. The A5 sym-MEM `LDR W9, [X16, #0]` returns 0,
`ADD X9, X9, X15` makes `X9 = ee_base`, and `BLR X9` lands at the
first word of the EE map (typically a zero word = `UDF #0`).

`pc-get-os` is one of the OS-introspection pc-* helpers — the GOAL
kernel queries it during `pckernel` initialization to determine the
host OS (Windows / Linux / macOS / unknown) for save-game path
selection and similar runtime decisions. The corresponding desktop
implementation lives in `game/kernel/common/kmachine.cpp` along with
the other pc-* helpers `pc_*` already-known-to-be-skipped on
linux-arm64 / android-arm64.

The fix shape is identical to A11/A12/A14: a klink helper in
`game/kernel/common/klink.cpp` wired via the pre-version-check hook
in both `linux_arm64_main.cpp` and `gk_android_main.cpp`, with a
local impl that returns the correct enum value for the host OS.

The A16 ADRP-pair walker dump on the device confirms `clobbered-
between FALSE` for every pair in the lr-window — X16 reaches the
sym slot LDR intact, the load happens, and the load's W9 result is
0 because the sym was never bound. No X16 clobber, no IDIV-X8 issue,
no regalloc divergence — purely a missing binding.

## Validator status

Local A17 validator checks 1–8 + 7d + 9b pass; check 9 (full D4
end-to-end validator exit 0) currently fails because the new
`pc-get-os` crash trips D4's broader-crash-detection (signal handler
fires → GK-DIAG marker burst exceeds the 10-line threshold). This
mirrors A14's situation at its respective +8 CGO advance — the
boot-ceiling check (devicelink-finishes > 166) passes by a wide
margin (212 > 166, well above the 20-CGO regression threshold the
A17 prompt sets) but the D4 renderer-reach check cannot succeed
until the next-blocker is bound.

The supervisor's honest-exit criterion ("any qemu-vs-device
divergence ≥ 20 link-finishes") evaluates to 0 here — both backends
hit exactly 212 — so the A17 commit should NOT be reverted. The
expected next phase (A18) is to bind `pc-get-os` using the
A11/A12/A14 klink-helper pattern, which should advance the boot
ceiling further into the `pckernel` initialization tail and beyond.

## Anti-cheat invariants — A17 status

- 0 dodges, 0 abort/weak additions, 0 new `_stubs.cpp`, 0 inline
  `_stub(` additions, 0 rename-evasion stub-shaped functions.
- 0 modifications to ObjectGenerator, CodeGenerator, IR.h, regalloc,
  asm trampoline, kscheme.cpp, kmachine.cpp, IOP_Kernel.{cpp,h},
  runtime-compat files, klink.{cpp,h}.
- 0 modifications to `.autoport/lib/*` / `.autoport/validators/*`.
- x86 CGOs byte-identical to A2 baseline (the IDIV emit change is
  inside `IR_IntegerMath::do_codegen_arm64`, not `do_codegen_x86`).
- arm64 CGOs byte-differ from A11 baseline (the emit change landed —
  required by validator check 5).
- The byte change is structural: every IDIV_32 / IMOD_32 / UDIV_32 /
  UMOD_32 emit site in the arm64 backend now produces ~6 instructions
  instead of 1 (when m_dest != X8). All other IR emit paths are
  unchanged, so byte diffs cluster around IDIV sites and don't ripple
  through unrelated function bodies.
- ENGINE.CGO CBZ-Xt,+40 fingerprint scan: 0 hits (no null-ptr-around-
  call cheat pattern introduced).

## Files touched

| File                                  | Change                       |
|---------------------------------------|------------------------------|
| `goalc/emitter/IGenARM64.cpp`         | Add A17 block comment + 4 new spill helpers (`idiv_spill_sub_sp_16`, `idiv_spill_str_x8_sp_0`, `idiv_spill_ldr_x8_sp_0`, `idiv_spill_add_sp_16`); update `idiv_gpr32` / `unsigned_div_gpr32` body comments |
| `goalc/compiler/IR.cpp`               | Forward-declare the 4 spill helpers; rewrite IDIV_32/IMOD_32/UDIV_32/UMOD_32 cases in `do_codegen_arm64` to emit the 6-instruction preserve-X8 sequence (or 1-instr fast path when m_dest == X8) |
| `out/jak1-arm64/iso/{KERNEL,ENGINE,GAME}.CGO` | regenerated (byte-differ from A11) |
| `android/app/src/jak1/assets/iso_data/jak1/{KERNEL,ENGINE,GAME}.CGO` | synced to APK |
| `.autoport/reports/A17-baseline-arm64-cgo-hashes.txt` | new — A17 arm64 CGO sha256 baseline |
| `.autoport/reports/A17-fix-summary.md` | this file                    |

## Cost note

The phase prompt budgeted "~90-120 min" and noted weekly rate at
88%. Actual time: roughly the budgeted range. The emit change itself
is ~30 LoC plus four short raw-encoded helpers, all of which
followed mechanically from the supervisor's prescribed pseudo-code
and the existing arm64 prologue's SP-encoding pattern. The bulk of
the cycle was the build + CGO regen + qemu_repro + D4-on-device
sequence, which exercised the full path end-to-end on the real
Redmi Note 9 Pro before declaring the fix landed.
