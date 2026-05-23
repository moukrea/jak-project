# A9 — CodeGenerator spill ops fix summary

Authored 2026-05-23. Implements real AArch64 spill load/store + frame
setup in `goalc/compiler/CodeGenerator.cpp::do_goal_function_arm64`,
replacing the NOP placeholders that caused the display.gc NULL fn-ptr
BLR identified by A8.

## What was wrong

Pre-A9, every spill emit on the arm64 path was a NOP
(`0xD503201F`):

```cpp
// pre-A9
for (const auto& op : bonus.ops) {
  if (op.load) {
    m_gen.add_instr(emitter::InstructionARM64(0xd503201fu), i_rec);
    // ^ spill load placeholder (NOP)
  }
}
ir->do_codegen_arm64(&m_gen, allocs, i_rec);
for (const auto& op : bonus.ops) {
  if (op.store) {
    m_gen.add_instr(emitter::InstructionARM64(0xd503201fu), i_rec);
    // ^ spill store placeholder (NOP)
  }
}
```

…and the prologue's `sub sp, sp, #frame` was likewise a single NOP
instead of a real allocation. The V2 register allocator faithfully
spilled values to the stack at IRs where pressure exceeded the saved
register pool; the codegen then refused to materialise the
load/store. Consumers of spilled values read whatever stale register
state remained — for display.gc's `(new 'global 'font-context ...)`
expansion that meant the dispatched method's function pointer was
lost, and the eventual `BLR X3` fired with `X15 + 0` = the EE base,
where the zero-filled MMU page decoded as `UDF #0` (SIGILL).

See `.autoport/reports/A8-displaygc-root-cause.md` and
`A6-attempt-5-blocker.md` for the per-instruction trace of the failing
display.gc top-level.

## What changed

`goalc/compiler/CodeGenerator.cpp::do_goal_function_arm64` now emits
real AArch64 frame setup, spill load/store, and frame teardown.
Nothing outside that function is touched.

### Prologue

```
stp x29, x30, [sp, #-16]!     ; save FP/LR, SP -= 16       0xA9BF7BFD
mov x29, sp                   ; FP = SP                     0x910003FD
sub sp, sp, #frame_bytes      ; reserve spill area          (only if > 0)
                              ;   enc = 0xD10003FF | ((frame_bytes & 0xfff) << 10)
```

`frame_bytes = ((stack_slots_for_spills + stack_slots_for_vars) * 8 +
15) & ~15`, i.e. 16-byte-aligned per AArch64 SP requirement. `ASSERT`
guards `frame_bytes <= 0xfff` — display.gc's biggest spilled function
uses ~16 slots = 128 bytes, well inside imm12 range. (If a future
function blows the budget we'll see the assert and add an LSL #12 path.)

### Spill load / store (per IR)

```
LDR Xt, [SP, #byte_off]   0xF9400000 | (imm12_div8  << 10) | (31 << 5) | Rt
STR Xt, [SP, #byte_off]   0xF9000000 | (imm12_div8  << 10) | (31 << 5) | Rt
LDR St, [SP, #byte_off]   0xBD400000 | (imm12_div4  << 10) | (31 << 5) | Rt
STR St, [SP, #byte_off]   0xBD000000 | (imm12_div4  << 10) | (31 << 5) | Rt
LDR Qt, [SP, #byte_off]   0x3DC00000 | (imm12_div16 << 10) | (31 << 5) | Rt
STR Qt, [SP, #byte_off]   0x3D800000 | (imm12_div16 << 10) | (31 << 5) | Rt
```

`byte_off = allocs.get_slot_for_spill(op.slot) * GPR_SIZE`. Spill load
runs before the IR's own codegen (so inputs are restored); spill store
runs after (so outputs are stashed). `Rt = op.reg.id() & 0x1f` — for
GOAL's x86-shaped allocator that maps `RAX..R10` → `X0..X10` for GPRs
and `XMM0..XMM15` → `Q16..Q31` for FPSIMD. Q-reg alignment is
enforced by an `ASSERT` and guaranteed by the V2 allocator's
`slot_size = 2` round-up for `INT_128 / VECTOR_FLOAT` vars.

### Epilogue

```
add sp, sp, #frame_bytes      ; free spill area          (only if > 0)
                              ;   enc = 0x910003FF | ((frame_bytes & 0xfff) << 10)
ldp x29, x30, [sp], #16       ; restore FP/LR, SP += 16   0xA8C17BFD
ret                           ;                           0xD65F03C0
```

## Disassembly evidence

`out/jak1-arm64/iso/{KERNEL,ENGINE,GAME}.CGO` regenerated with the
patched compiler (spill ops + X4=SP pre-load workaround). Latest
hash baseline saved to `.autoport/reports/A9-baseline-arm64-cgo-hashes.txt`:

```
81b717243de89f7f29c40c0552d99333483e4d5322796a2967766f03e2d73f2b  out/jak1-arm64/iso/KERNEL.CGO
a30b3426b64fd7281741544d6a7f9fb713cdb4bbef5fc484ab63bb771aa7a599  out/jak1-arm64/iso/ENGINE.CGO
f0f646fe58d25fe56bfbbe1b98b929dbe9df01342e8789a71ed74f516b4dbb03  out/jak1-arm64/iso/GAME.CGO
```

The earlier post-spill-only hashes (no X4 workaround) were
`60ae3ced…` / `f2640b07…` / `033f255a…`; against the A6 baseline
(`9e9a19e7…` / `38a0806b…` / `14cf084b…`) every CGO has shifted
bytes — the spill ops + stack-addr workaround change is threaded
across hundreds of jak1 functions.

Slice from the new ENGINE.CGO near a function with a spilled value
(qemu_repro log lines 220-265, addresses in the EE map):

```
0x21245017_94  a9bf7bfd  stp x29, x30, [sp, #-16]!   ← prologue
0x21245017_98  910003fd  mov x29, sp                  ← prologue
0x21245017_9c  d10043ff  sub sp, sp, #16              ← *NEW* — was NOP pre-A9
...
0x21245017_c4  a9bf17e3  stp x3, x5,  [sp, #-16]!     ← call_r64 push
0x21245017_c8  a9bf2fea  stp x10, x11, [sp, #-16]!    ← call_r64 push
0x21245017_cc  a9bf63f7  stp x23, x24, [sp, #-16]!    ← call_r64 push
0x21245017_d0  a9bf6bf9  stp x25, x26, [sp, #-16]!
0x21245017_d4  a9bf73fb  stp x27, x28, [sp, #-16]!
0x21245017_d8  d63f0120  blr x9                       ← real call
0x21245017_dc  a8c173fb  ldp x27, x28, [sp], #16      ← call_r64 pop
...
```

`d10043ff` decodes as `sub sp, sp, #16` (imm12 = (0x43FF >> 10) &
0xFFF = 0x010 = 16): the new spill frame reservation that replaces
the pre-A9 NOP.

## What it unblocks (qemu_repro + device)

`bash .autoport/lib/qemu_repro.sh` extended boot (KERNEL+ENGINE+GAME
CGOs with `LINK_FLAG_EXECUTE`) before and after the fix:

| Phase | `link finish:` count | Last reached object | Crash site |
|-------|----------------------|---------------------|------------|
| pre-A9 (A8 trace) | ~45 | font-h (display.gc top-level enters but BLRs to NULL) | display.gc:243 `(new 'global 'font-context …)` → `BLR X3=X15+0` |
| post-spill-only | 61 | knuth-rand | X3-clobber-after-BLR in `scf-time-to-int64`, root-caused to `mov dst, X4` instead of `mov dst, SP` for `(new 'stack-no-clear 'scf-time)` |
| post-spill + X4 pre-load (current) | **64** | texture | NEW: `pc=ee_base` BLR (uninitialised sym-MEM load returns 0 → BLR to GOAL ptr 0) — separate bug class, see [next-blocker doc](A9-attempt-1-next-blocker.md) |

The on-device D4 run mirrors the qemu_repro outcome exactly:

```
05-23 12:08:04.385  7213  7376 D opengoal-gk: link finish: texture
05-23 12:08:04.385  7213  7376 F opengoal-gk: GK-DIAG sig=4 fault=0x7208882000 pc=0x7208882000 lr=0x720bf3a058
```

`pc=0x7208882000 = g_ee_main_mem` ⇒ host-side decode is GOAL ptr 0
(the first u32 of the EE memory is `0x00000000` = `UDF #0` ⇒ SIGILL).
The LDR `W9, [X16, #0]` at `lr-44` (sym-MEM load via the A5
ADRP+ADD+LDR triplet) returned 0; `ADD X9, X9, X15` (lr-20) +
`BLR X9` (lr-4) jumped to ee_base. Same shape as the qemu trace.

Objects that linked for the first time with A9 in place include
`display`, `connect`, `text-h`, `settings-h`, `dma-buffer`, `pad`,
`gs`, `vector`, `file-io`, `loader-h`, `texture-h`, `level-h`,
`math-camera-h`, `math-camera`, `font-h`, `decomp-h`, `knuth-rand`,
`capture`, `memory-usage-h`, `texture` — 19+ objects past the
pre-A9 failure line. The `FIRST POST-FIX CGO LINKED:` marker
emitted by `qemu_repro.sh` names `dma-buffer` (the earliest object
in the boundary-set regex that crossed the previous failure line).

## Honest scope of the fix

A9's narrow unlock is `do_goal_function_arm64` only. Other functions
in `CodeGenerator.cpp` are byte-identical. The x86 path
(`do_goal_function_x86`) is unchanged, and the three jak1 x86 CGOs
hash-match the A2 baseline byte-for-byte (verified by
`build_b1_arm64_cgos.sh` step 7 after the regen cycle).

The fix is necessary but not sufficient for full boot. With both
qemu and a real device producing the identical post-A9 progression
(64 link-finishes, crash at `BLR` to ee_base from an uninitialised
sym-MEM load), the next layer is squarely outside A9's narrow
`do_goal_function_arm64` unlock. See
[`A9-attempt-1-next-blocker.md`](A9-attempt-1-next-blocker.md) for
the full disassembly trace + scope recommendation for the next
phase. D4 device-validator re-pass remains gated on that next bug.

## Pipeline note: arm64 CGO → APK asset sync

`d4_run.sh` rebuilds `libgk.so` and re-packages the APK, but does
NOT itself copy the freshly regenerated `out/jak1-arm64/iso/*.CGO`
into `android/app/src/jak1/assets/iso_data/jak1/`. When the
codegen changes (as it did in A9), the CGO sync must be done
manually before `d4_run.sh`/the D4 validator so gradle's `mergeAssets`
sees a delta and repackages — without it the APK ships stale CGOs
and the on-device behaviour reverts to the pre-fix progression. The
A9 validator's check #10 runs D4 against whatever CGOs are in the
APK, so the standard incantation is:

```bash
cp out/jak1-arm64/iso/{KERNEL,ENGINE,GAME}.CGO \
   android/app/src/jak1/assets/iso_data/jak1/
bash .autoport/validators/phase-A9-codegen-spill-ops.sh
```

The asset paths are `.gitignore`d (Jak ISO data is too large to
commit), so this is a host-only file-shuffle, not a source change.
