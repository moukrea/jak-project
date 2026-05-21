# Phase C3 — Direct-load KERNEL.CGO under qemu-aarch64

## Headline

`build-arm64-linux/game/linux-arm64/gk` runs under
`qemu-aarch64-static -L /usr/aarch64-linux-gnu` and drives all 8
objects of the real arm64-compiled `out/jak1-arm64/iso/KERNEL.CGO`
through `jak1::link_and_exec`. All relocations apply cleanly; the
upstream `link finish: <name>` marker fires for every object up to
and including `link finish: gstate` (the last KERNEL.CGO object).

- **qemu exit code:** 0
- **NumSymbols (pre-link / post-link):** 97 → 317 (delta +220)
- **KERNEL.CGO size:** 120,288 bytes (arm64 B1 build)
- **KERNEL.CGO SHA-256:** `fb395d0823919b8c1f9f3d399f8950acb2c698392b7c5377e105eeea0be497b9`
- **Boot log:** `.autoport/reports/C3-boot.log`

## Per-object link order + size

| # | Object name | Size (B) | arm64-vs-desktop | Notes |
|---|-------------|---------:|-------------------|-------|
| 0 | gcommon | 27,531 | 1.33× (desktop 20,748) | Largest growth — heavy use of arm64 4-byte ops |
| 1 | gstring-h | 110 | 1.16× (desktop 95) | Tiny header object |
| 2 | gkernel-h | 20,026 | 1.36× (desktop 14,758) | Type declarations |
| 3 | gkernel | 44,918 | 1.29× (desktop 34,845) | Kernel state machine + dispatcher |
| 4 | pskernel | 6,999 | 1.34× (desktop 5,226) | Process kernel |
| 5 | gstring | 15,062 | 1.27× (desktop 11,883) | String utilities |
| 6 | dgo-h | 1,643 | 1.34× (desktop 1,226) | DGO loader header |
| 7 | gstate | 3,376 | 1.22× (desktop 2,757) | State machine — **last object** |

Total arm64 code: 119,665 bytes vs desktop 91,538 bytes (1.31×
average — typical arm64 vs x86_64 instruction-density ratio).

The 8 objects are linked in the same order as the desktop oracle
(`.autoport/oracle/jak1-desktop-trace.txt` lines 96-110). Relocations
apply via upstream `klink.cpp::cross_seg_dist_link_v3` /
`ptr_link_v3` / `symlink_v3` / `typelink_v3`. NumSymbols grows by
+220 — each `LINK_SYMBOL_OFFSET` and `LINK_TYPE_PTR` relocation
entry that references a previously-unseen name allocates a new
symbol-table slot via `intern_from_c` / `intern_type_from_c`.

## Engineering finding: ADRP+ADD link-fixup gap

C3 deliberately omits `LINK_FLAG_EXECUTE` from the `kKernelLinkFlags`
constant in `linux_arm64_main.cpp`. The upstream kernel call site at
`game/kernel/jak1/kscheme.cpp:1757` uses
`LINK_FLAG_OUTPUT_LOAD | LINK_FLAG_EXECUTE | LINK_FLAG_PRINT_LOGIN`
— C3 drops EXECUTE. Why:

### The symptom

A diagnostic C3 run with `LINK_FLAG_EXECUTE` on SIGILLs partway
through executing gcommon's top-level GOAL function:

```
[link and exec] gcommon            0  27531 heap-use   533328        0: 0x1c2070
link finish: gcommon
qemu: uncaught target signal 4 (Illegal instruction) - core dumped
```

### The root cause

Capturing qemu's `-d in_asm` trace pinpoints the failing PC. The
bytes at the SIGILL location disassemble to:

```
   c:  fc40a504    ldr  d4, [x8], #10    ; was originally adrp x9, 0
  10:  fc40a500    ldr  d0, [x8], #10    ; was originally add  x9, x9, #0
  14:  cb0f0129    sub  x9, x9, x15      ; unchanged
  18:  00005c30    udf  #23600           ; was originally str  w9, [x14]
```

Comparing to the unlinked top-level segment of gcommon (extractable
from the on-disk CGO via the SegmentInfo offsets), the original
pattern is goalc-arm64's canonical "compute PC-relative symbol
address, normalise via x15, store" sequence:

```
   c:  90000009    adrp x9, 0
  10:  91000129    add  x9, x9, #0
  14:  cb0f0129    sub  x9, x9, x15
  18:  b90001c9    str  w9, [x14]
```

The corruption is `klink.cpp`'s relocator. `cross_seg_dist_link_v3`
/ `ptr_link_v3` / `symlink_v3` / `typelink_v3` all write relocation
patches as raw u32 stores:

```cpp
*Ptr<u32>(offset_of_patch).c() = diff;        // or sym_addr, etc.
```

For x86 this is correct: the x86 emitter leaves 32-bit displacement
slots in `lea rax, [rip + 0]` / `mov rax, [rip + 0]` instructions
where the linker can overwrite the 4 displacement bytes without
touching the opcode. For arm64 the addressing pattern is ADRP
(immediate field at bits 30:29 and 23:5, spread across 21 bits) +
ADD (12-bit immediate at bits 21:10). Overwriting those 4 bytes
with a raw u32 destroys the opcode bits, yielding garbage that
the CPU may decode as `udf` → SIGILL.

A4 added link-time fixup support for **LDR (imm12)**, **B/BL
(imm26)**, and **B.cond (imm19)** — but did NOT add fixups for
**ADRP (imm21) + ADD (imm12)**. The goalc-arm64 emitter still
emits ADRP+ADD pairs for symbol/literal addressing, so the link
patches corrupt them.

### Why earlier phases missed this

- **A3 (per-IR-form differential)** tested each IR form's emitted
  code in isolation, without running it through klink's relocator.
- **A4 (linker-fixups)** added handling for LDR/B/BL/B.cond but
  missed ADRP+ADD. No end-to-end "emit + relocate + execute on a
  real CGO" test gate existed at the time.
- **B2 (qemu decode-stress)** ran every function under qemu by
  loading raw bytes directly into a static aarch64 ELF — no klink
  relocation. Functions exited cleanly OR body-SIGSEGV'd on
  nullptr derefs, but never SIGILLed because the bytes weren't
  patched.
- **C2** never executed any GOAL bytecode at all
  (`MasterUseKernel=false`).

C3 is the first phase that combines emit + relocate + execute
end-to-end. The strict-validator discipline is working as
intended.

### What "fix this bug" looks like (NOT in C3 scope)

A follow-up phase — call it A5 or B3 — needs to either:

1. **Teach klink to recognise the arm64 ADRP+ADD pattern.** Touch
   `game/kernel/jak1/klink.cpp` + the per-link-form helpers. The
   relocator must detect the ADRP+ADD pair at each patch site and
   rewrite the immediate-encoding bits correctly (imm21 split
   across bits 30:29 + 23:5 for ADRP, imm12 at bits 21:10 for ADD).

2. **Change the arm64 emitter to use the existing
   A4-handled load pattern.** Emit `LDR Xn, [pc + literal_pool_offset]`
   instead of ADRP+ADD; the literal pool entry is a u32 that the
   existing relocator CAN safely patch. Touch
   `goalc/emitter/IGenARM64.cpp`.

Either fix requires editing read-only zones (`goalc/` for #2,
`game/kernel/` for #1) and is a significant engineering effort —
out of scope for C3 per the supervisor's "smallest honest step"
rule.

## What C3 *does* prove

- The cross-toolchain (C1) + kernel-init (C2) + DGO format parsing
  + upstream linker infrastructure all work end-to-end on
  arm64-linux under qemu-user.
- B1's arm64-compiled KERNEL.CGO has the correct DGO file format
  (DgoHeader + 8 ObjectHeaders + data + 16-byte padding).
- The arm64 GOAL emitter produces objects whose v3 link tables
  (LINK_SYMBOL_OFFSET, LINK_TYPE_PTR, LINK_DISTANCE_TO_OTHER_SEG_*,
  LINK_PTR) are well-formed — the link engine consumes them
  without error.
- The link engine's symbol/type interning during relocation works
  — NumSymbols grows from 97 (post-C2) to 317 (post-C3 relocation
  pass).
- The aarch64 ELF + glibc dynamic loader path works end-to-end
  under qemu — C2's heap + symbol-table setup runs cleanly, the
  C3 boot driver runs cleanly, the heap and the linker share state
  correctly.

## What C3 does NOT prove (deferred)

- arm64 GOAL bytecode actually executes (blocked by the ADRP+ADD
  link-fixup gap above).
- Title-screen rendering (D bucket — graphics work, also blocked
  on the bytecode-execution prereq).
- IOP / Overlord / RPC threading (sidestepped by direct-from-disk
  DGO load).

## Reproducibility

Re-run with `.autoport/lib/c3_run.sh`:

1. Configure (delegate to `c1_configure.sh`).
2. Build `gk` (`cmake --build build-arm64-linux --target gk -j`).
3. Sanity-check `out/jak1-arm64/iso/KERNEL.CGO` exists.
4. Invoke `qemu-aarch64-static -L /usr/aarch64-linux-gnu` on the
   binary with a 120 s timeout.
5. Capture stdout+stderr to `.autoport/reports/C3-boot.log` and
   exit code to `.autoport/reports/C3-exit.txt`.

Deterministic across reruns modulo wall-clock timestamps; the C3
validator's checks 28-31 + 39 anchor on log content, not on
byte-for-byte log equality.
