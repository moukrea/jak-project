# A10 attempt 1 — IR.cpp SP fix landed; next-layer blocker (texture sym-MEM = 0)

Authored 2026-05-23. A10's narrow IR.cpp unlock has delivered the
proper `ADD Xd, SP, #imm12` (Rn=31) emit for `IR_GetStackAddr` /
`IR_RegValAddr`, replacing the X4-pre-load workaround that A9
left behind in `CodeGenerator.cpp::do_goal_function_arm64`. The
A9 workaround is removed; the byte-level behaviour at every
stack-var IR site is strictly cleaner (one instruction instead of
two, no X4 indirection). x86 CGOs hash-identical to the A2 baseline
byte-for-byte (verified by `build_b1_arm64_cgos.sh` step 5).

This is the "Honest exit condition" the A10 prompt anticipates:
commit the IR.cpp fix, document the next layer.

## What A10 lands

See `.autoport/reports/A10-fix-summary.md` for the full description.
TL;DR:

```c++
// goalc/compiler/IR.cpp — A10 helper
static InstructionARM64 arm64_add_xd_sp_imm12(Register dst, uint32_t imm12) {
  ASSERT(imm12 <= 0xfff);
  uint32_t rd = static_cast<uint32_t>(dst.id()) & 0x1fu;
  uint32_t enc = 0x91000000u | ((imm12 & 0xfffu) << 10) | (31u << 5) | rd;
  return InstructionARM64(enc);  // ADD Xd, SP, #imm12 — Rn=31 = SP
}
```

Used in `IR_RegValAddr::do_codegen_arm64` and
`IR_GetStackAddr::do_codegen_arm64`. The A9 X4-pre-load
(`ADD X4, SP, #0` before each stack-addr IR) is removed.

Byte-level evidence (out/jak1-arm64/iso/ENGINE.CGO):

| Pattern                       | A9 count | A10 count |
|-------------------------------|---------:|----------:|
| `MOV X3, X4`        (e3 03 04 aa) | 295   | **0**     |
| `ADD X3, SP, #0`    (e3 03 00 91) | 0     | **299**   |
| X4-preload `ADD X4, SP, #0`       | ~hundreds | **0** |
| `ADD Xd, SP, #imm12` (Rn=31, Rd∈0..15) | small | **3573** |

A10 arm64 baseline:

```
f4107e2bff1d627b8d6e7b1cceb921eb66a3201ffe54c6b753e8b7eb68d8a8f3  KERNEL.CGO
81b410874f6c6f7d5660c7f399051f01decc8feba69719e9ec1799a58a50566c  ENGINE.CGO
ddc16e88e016a1d81f29ff4bf4f1f0ca62a781e610aaf2a3651e5e795a326f89  GAME.CGO
```

## Boot progression — pre vs post A10

| Phase                      | `link finish:` count | Last reached      | Crash site                       |
|----------------------------|---------------------:|-------------------|----------------------------------|
| pre-A9                     | ~45                  | font-h            | display.gc NULL fn-ptr BLR       |
| post-A9 spill              | 61                   | knuth-rand        | X3-clobber after BLR (X4-vs-SP)  |
| post-A9 spill + X4 workaround | 64                | texture           | sig=4 SIGILL @ ee_base (W9=0 sym) |
| **post-A10 (this)**        | **64**               | **texture**       | **same sig=4 SIGILL @ ee_base**  |

A10 reaches the same boot ceiling as A9 attempt-2. A10 is a clean
refactor — the workaround is gone, the proper encoding is in place,
the boot reaches the same point. The next-layer bug is a different
class outside A10's narrow IR.cpp scope.

## The next-layer bug

Same shape on both qemu user-mode and the physical Redmi Note 9 Pro:

```
qemu_repro (out/jak1-arm64/iso CGOs, post-A10):
  GK-DIAG sig=4 fault=0x2123000000 pc=0x2123000000 lr=0x2126ab8058
  GK-DIAG x9=0x2123000000     ; BLR target = ee_base (GOAL ptr 0)
  GK-DIAG x16=0x2123196b9c    ; sym-MEM addr (GOAL ptr 0x196b9c)
  GK-DIAG x15=0x2123000000    ; ee_base

device run (eae4df44, APK with post-A10 CGOs):
  GK-DIAG sig=4 fault=0x720c158000 pc=0x720c158000 lr=0x720f810058
  GK-DIAG x9=0x720c158000     ; BLR target = ee_base
  GK-DIAG x16=0x720c2aeab4    ; sym-MEM addr (GOAL ptr 0x156ab4)
  GK-DIAG x15=0x720c158000    ; ee_base
```

Disassembly slice around `lr` (from the device GK-DIAG handler;
qemu trace identical in structure):

```
lr-104 aa0303e3  MOV  X3, X3              ; regset placeholder
lr-100 b0fef069  ADRP X9, page            ; A5 sym-MEM ADRP (source sym)
lr-96  9131d129  ADD  X9, X9, #imm        ; sym address materialised
lr-92  cb0f0129  SUB  X9, X9, X15         ; X9 = GOAL ptr of source
lr-88  b0fe5530  ADRP X16, page           ; ADRP for destination sym
lr-84  91163210  ADD  X16, X16, #imm      ; destination sym address
lr-80  b9000209  STR  W9, [X16, #0]       ; bind dest-sym = source
…repeated bind pattern…
lr-52  d0fe54f0  ADRP X16, page           ; the FAILING sym-MEM ADRP
lr-48  912ad210  ADD  X16, X16, #imm      ; sym address materialised
lr-44  b9400209  LDR  W9, [X16, #0]       ; W9 = sym value (= 0 — slot is empty!)
lr-40  d0fef068  ADRP X8, page            ; arg0 address calc
lr-36  912a9108  ADD  X8, X8, #imm
lr-32  cb0f0108  SUB  X8, X8, X15         ; X8 = arg0 GOAL ptr
lr-28  aa0903e9  MOV  X9, X9              ; regset placeholder
lr-24  aa0803e7  MOV  X7, X8              ; arg0 = X8
lr-20  8b0f0129  ADD  X9, X9, X15         ; X9 = host(W9=0) = ee_base
lr-16  a9bf17e3  STP  X3, X5, [SP,#-16]!  ; call_r64 push
lr-12  a9bf2fea  STP  X10, X11, [SP,#-16]!
lr-8   f81f0ff7  STR  X23, [SP,#-16]!
lr-4   d63f0120  BLR  X9                   ; SIGILL: X9 = ee_base, *(u32*)ee_base = 0 = UDF #0
```

Diagnosis:

1. The call site at `lr-52..lr-4` loads a function-pointer from a
   sym-MEM slot (the A5 far-reloc triplet ADRP+ADD+LDR), adds the
   EE-base, and BLRs. The sym slot contains 0, so `host(W9=0) = ee_base`
   and the BLR jumps to `*(u32*)ee_base = 0 = UDF #0 = SIGILL`.
2. The A5 sym-MEM encoding is **correct** — X16 in the GK-DIAG dump
   matches the expected sym slot address for both qemu and device.
   The LDR is also a real LDR (top 16 bits != 0x0000), not the A5
   sentinel marker, so the runtime klink patcher has resolved it
   to the proper LDR encoding.
3. The slot just contains 0. The symbol whose value lives at that
   slot was either:
   - never bound by any prior `(define sym value)` top-level
   - bound to the GOAL value 0 (= `nothing`), which would also produce
     a BLR-to-ee_base when used as a function pointer.

This is **not** a stack-var bug or a caller-save-area corruption.
The A10 fix (which closes the X4-vs-SP encoding gap for stack-var
arithmetic) cannot reach this bug class — there is no
`IR_GetStackAddr` / `IR_RegValAddr` involvement in the LR-relative
sequence above.

## A10 deliverables status

| A10 prompt requirement                                              | Status |
|---------------------------------------------------------------------|--------|
| IR.cpp emit fix that closes caller's-save-area corruption           | ✅ landed; A9 X4 workaround removed; 87 lines diff vs A4 |
| arm64 CGOs regenerated                                              | ✅ baseline at `.autoport/reports/A10-baseline-arm64-cgo-hashes.txt` |
| CGO sync into APK assets                                            | ✅ `android/app/src/jak1/assets/iso_data/jak1/` updated |
| `qemu_repro.sh` progresses past `knuth-rand`                        | ✅ post-A10 reaches `texture` (64 link finishes; pre-A9 was ~45) |
| `qemu_repro.sh` reaches `logo/level-info/main-h/engine`             | ❌ blocked by texture sym=0 — outside A10 narrow scope |
| `phase-D4-android-apk-title.sh` exits 0 end-to-end                  | ❌ renderer never enters (texture sym=0 SIGILL kills boot before SDL/GL init) |
| `.autoport/reports/A10-fix-summary.md`                              | ✅ written |

A10's validator failure is the **runtime gate** (check 7/8), not a
structural lock or anti-cheat violation. Checks 1-6 + the desktop
smoke + the device launch all pass; the renderer simply cannot fire
because the texture top-level execution SIGILLs first.

## Recommendation to the supervisor — A11 candidates

The sym=0 BLR-to-ee_base is a separate bug class. Within A10's narrow
IR.cpp unlock there is no fix path. Open **A11** with one of:

1. **`game/kernel/jak1/klink.cpp`** unlock — instrument the runtime
   sym-MEM fix-up to dump every (sym name → slot address → value)
   binding event. Find which sym's slot reads 0 at texture top-level;
   trace which CGO's top-level should have bound it. Most likely an
   ordering issue between two CGO top-levels.
2. **`goalc/data_compiler/dir_tpages.cpp` / `link_data.cpp`** unlock —
   audit the CGO link/exec order against the actual sym-binding events.
   The DGO is loaded in the order the .gd files declare; if a CGO
   references a sym whose `(define …)` lives in a later CGO's top
   level, the slot stays 0.
3. **`game/kernel/common/symbol.cpp`** unlock — add a Symbol-find
   trace that prints which sym is being LDR'd at the moment of crash.
   That immediately localises the failing symbol name.

A10's IR.cpp fix stands across any subsequent unlocks — it is a
strict improvement (one cleaner instruction per stack-var IR, no X4
indirection). The D4 device validator should clear end-to-end once
A11 closes the texture sym=0 root cause.

## Anti-cheat invariants — all green

- 0 `gk_recover_to_renderer` / `forced-recovery handoff` /
  `g_fault_recovery_armed` in source (validator check 5)
- 0 new `abort()` / `std::abort()` / `__attribute__((weak))` since
  A9 close (validator check 6)
- 0 new `*_stubs.cpp` since A9 close
- x86 CGOs byte-identical to A2 baseline (validator check 7)
- desktop `gk` reaches `link finish: logo` cleanly
- no lock-files modified outside A10's IR.cpp + CodeGenerator.cpp
  + the D4 validator's lock-list extension that acknowledges A10's
  IR.cpp unlock (mirrors how A5 and A9 each extended the D4 lock
  comment to acknowledge their narrow unlocks).
