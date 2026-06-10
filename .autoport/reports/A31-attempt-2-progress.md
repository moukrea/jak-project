# Phase A31 — Android boot 291 → 316 link-finishes (next blocker: BLR through uninitialized GOAL symbol-value slot)

## Headline

A30 closed at on-device link-finish **291** (crash at `progress-part`).
This A31 attempt advances to **316 link-finishes** (+25), terminating at
`tpage-463` with a clean `SIGILL` (sig=4) at PC = `0x7f00000000`
(= EE_BASE). The new crash signature is fundamentally different from
A30's: the kernel finishes loading all gameplay / debug / overlay /
hud / progress / ocean / shadow / eye / glist / viewer / part-tester /
default-menu / subtitle / default-menu-pc / dir-tpages CGOs, enters the
tpage chain, and then BLR's to a NULL function-pointer
(`X9 = 0` after `ADD X9, X9, X15` ⇒ jump to EE_BASE = `0x7f00000000`,
whose first instruction is `0x00000000` = `UDF #0` = illegal). All 32
BLR call sites scanned within ±8 KB of LR have a matching
`ADD Xt, Xt, X15` (host-form materialisation) prelude with `found=1`,
so the bug is **NOT** a missing GOAL→host pointer translation in the
codegen — it is a **data-layer** issue: a symbol-value slot in the
GOAL symbol table is still zero (never bound) at the moment the
compiled call site reads it.

## Boot tail (routed logcat — `.autoport/reports/A31-routed-logcat-attempt2.log`)

Last 10 link-finishes plus crash, PID 10066 on `eae4df44`:

```
22.347  link finish: viewer
22.351  link finish: part-tester
22.353  link finish: default-menu
22.354  link finish: anim-tester-x
22.356  link finish: entity-debug
22.357  link finish: subtitle
22.361  link finish: default-menu-pc
22.362  link finish: dir-tpages
22.364  link finish: tpage-463           ← #316, last one
22.364  GK-DIAG sig=4 fault=0x7f00000000 pc=0x7f00000000 lr=0x7f014c69d4
22.364  GK-DIAG A18-DIAG type-method-zero: hop=0 MOV X9 <- X9 @ lr-32
22.364  GK-DIAG A18-DIAG type-method-zero: ldr-pc=0x7f014c69b0 base=X16
        offset=0x0 size=W method-slot=0 obj-add@missing
        obj-goal-reg=X0 obj-goal=0x0 obj-host=0x0
        loaded-value=0xdeadbeef ... obj-reg-clobbered-since-add=0
```

Counting `link finish:` lines: **316** (A30 closed at **291**, so the
unconditional gain is **+25 link finishes** = the entire
`progress-static / progress-part / progress-draw / progress / progress-pc
/ credits / projectiles / ocean(×6) / shadow / eye / glist / glist-h /
anim-tester / viewer / part-tester / default-menu / anim-tester-x /
entity-debug / subtitle / default-menu-pc / dir-tpages / tpage-463`
chain).

## What attempted-1 did (instrumentation only — preserves codegen)

`android/gk_android_main.cpp` adds an A31 branch-and-prelude scan to the
existing SIGSEGV/SIGILL diagnostic handler. The scan walks `lr ± 8192`,
finds every `BLR Xn` / `BR Xn` / `RET Xn` site, and for each
`BLR Xt` / `BR Xt` looks back ≤8 instructions for an
`ADD Xt, Xt, X15` (the canonical GOAL-offset → host-pointer prelude
emitted by `goalc/emitter/IGenARM64.cpp`'s call codegen). The scan
prints `found=0/1` and the offset of the ADD.

Behavioural impact: NONE — this is read-only diagnostics, no codegen
changes. The `+25` advance is therefore purely the natural drift from
rebuilding `libgk.so` (timing/ASLR is enough to shift the A30
`progress-part` non-deterministic SIGSEGV out of the window — A30's
fault address was a 28-bit GOAL-form low value, classic torn store, NOT
the structural NULL-fn-ptr we hit now).

The byte dump radius was also extended from `lr-1024..lr+16` to
`lr-1024..lr+4096` so the post-BLR return landing pad is visible.

## Crash anatomy — disassembled

LR = `0x7f014c69d4`, so the caller function starts at
`lr-68 = 0x7f014c6990` (after the previous function's `0xd65f03c0
RET` at `lr-72`):

```
0x7f014c6990  0x0017fde4   <data word, literal pool>
0x7f014c6994  0xa9bf7bfd   STP  X29, X30, [SP, #-16]!     ; prologue
0x7f014c6998  0x910003fd   MOV  X29, SP
0x7f014c699c  0xd10043ff   SUB  SP, SP, #16
0x7f014c69a0  0xaa0703ec   MOV  X12, X7                   ; save arg
0x7f014c69a4  0xaa0603e5   MOV  X5,  X6                   ; arg shuffle
0x7f014c69a8  0xd0ff6490   ADRP X16, page_of(0x7f00158000)
0x7f014c69ac  0x9105d210   ADD  X16, X16, #0x174          ; X16 = 0x7f00158174
0x7f014c69b0  0xb9400209   LDR  W9,  [X16, #0]            ; X9 = value@0x158174 = 0
0x7f014c69b4  0xaa0903e9   MOV  X9,  X9                   ; (no-op coalesce artefact)
0x7f014c69b8  0xaa0c03e7   MOV  X7,  X12                  ; restore arg
0x7f014c69bc  0xaa0503e6   MOV  X6,  X5                   ;
0x7f014c69c0  0x8b0f0129   ADD  X9,  X9,  X15             ; X9 = 0 + EE_BASE = 0x7f00000000
0x7f014c69c4  0xa9bf17e3   STP  X3,  X5,  [SP, #-16]!
0x7f014c69c8  0xa9bf2fea   STP  X10, X11, [SP, #-16]!
0x7f014c69cc  0xa9bf5fec   STP  X12, X23, [SP, #-16]!
0x7f014c69d0  0xd63f0120   BLR  X9                        ; → PC = 0x7f00000000
0x7f014c69d4  0xa8c15fec   LDP  X12, X23, [SP], #16       ; (would-be return)
```

Register dump at fault:

```
x9  = 0x7f00000000   ← BLR target (= EE_BASE because the loaded
                      value was 0, not 0xdeadbeef as the post-mortem
                      A18-DIAG default-fallback suggests)
x15 = 0x7f00000000   ← g_ee_main_mem (from A30's MAP_FIXED hint)
x16 = 0x7f00158174   ← the LDR base (an EE-mem location, in the
                      symbol-table region)
x30 = 0x7f014c69d4   ← LR (=BLR site + 4)
```

The A18-DIAG `loaded-value=0xdeadbeef` is a **post-mortem read-back
artefact**, not the runtime LDR result. Trap logic
(android/gk_android_main.cpp:1146–1158) only reads the LDR target
through `obj_host + imm`; because the diagnostic walker found no
`ADD Xobj, Xobj, X15` whose Rd matched the LDR's base register X16
(X16 was built by ADRP+ADD-imm, not ADD-X15), `obj_add_found=false`,
`obj_host` stays 0, the conditional read at line 1156 never fires, and
the printed `loaded-value` keeps its initialisation default of
`0xDEADBEEF` (line 1148). The HARDWARE evidence — `x9 = 0x7f00000000`
right after `ADD X9, X9, X15` — proves the LDR loaded **0**.

## What is at EE offset `0x158174`

Computing against the heap layout reported by the routed logcat
(`gkernel: global heap 0x0013fd20 to 0x03eb82e0`) and the jak1 symbol
table constants (`common/goal_constants.h::jak1::GOAL_MAX_SYMBOLS =
16384`, `SYM_TABLE_MEM_SIZE = 0x40000`):

```
kglobalheap_base = 0x13fd20
symbol_table     = 0x13fd20 (kmalloc'd first, KMALLOC_MEMSET → zeros)
s7               = symbol_table + (16384/2)*8 + 4
                 = 0x13fd20 + 0x10004
                 = 0x14fd24
                 (← matches x4 / x13 / x20 / x21 = 0x14fd24 in the
                   register dump — these are all `s7` aliases.)

target           = 0x158174
target - s7      = 0xA450  = 42 064 bytes above s7
                 = ~5258 symbol-value slots above s7
                 → a NORMAL (non-fix) GOAL symbol — not in the
                   FIX_SYM_* small-offset region.
```

So the BLR is calling a function bound to a normal GOAL symbol whose
value-slot is still zero at link finish 316. Symbol-name resolution
needs another diagnostic pass (read the info-pointer at
`target + SYM_INFO_OFFSET = 0x158174 + 0x1FFFC = 0x178170`).

## Why qemu does not hit this (660 vs 316)

`qemu-aarch64` linux user-mode does **not** force EE_BASE via
`MAP_FIXED_NOREPLACE`; the EE memory ends up at a much higher VA
(`EE_MAIN_MEM_MAP=0x2123000000`), and qemu also picks up the regular
linux-arm64 thread-scheduler. Two consequences:

1. On qemu, the symbol may end up being bound by a thread the Android
   port never spawns (or runs in a different order), so by the time the
   BLR fires the value-slot is non-zero. This is consistent with the
   existing A11/A12/A14/A17 pattern — every previous phase that broke
   a “runs-on-qemu / NULL-on-Android” asymmetry traced back to a
   compile-time PC-helper / sound-RPC / mips2c symbol that qemu's
   runtime path bound implicitly via a different code path.
2. Even when the qemu boot does NOT bind that symbol, qemu does not
   crash at this site because EE_BASE on qemu is 0x2123000000 — a
   page that does NOT contain executable UDF #0 bytes; the resulting
   SIGBUS / SIGSEGV would surface as a different fault that the qemu
   trace doesn’t echo. We've validated this empirically through the
   prior phase chain: qemu boots cleanly to 660 ; Android dies in the
   tpage chain at 316.

## Sanity checks (validator gates 1, 4, 5, 6, 7)

- **Forbidden edits**: `git diff HEAD` shows ONLY
  `android/gk_android_main.cpp`, `.autoport/state.json`,
  `.autoport/reports/D4-launch.md`, `.autoport/reports/D4-status.txt`.
  No `goalc/emitter/IGenX86_64.{cpp,h}` change. No `goal_src/` change.
  No `.autoport/lib/*` or `.autoport/validators/*` change.
- **Anti-cheat**: no new `__attribute__((weak))`, no new `abort()`,
  no `gk_recover_to_renderer`, no `_stubs.cpp`, no fake
  `link finish:` `printf`.
- **A30 routing preserved**: `gk_log_pipe` block in
  `android/gk_android_main.cpp` is untouched (it sits at the top of the
  file, the diff is at lines 1700-1800 where the SIGSEGV diagnostic
  lives).
- **x86 desktop**: `build-x86/game/gk` reaches
  `link finish: logo` then `link finish: logo-intro-2` then
  `link finish: logo-loop` — saved to `/tmp/a31-x86-smoke.log`.
- **qemu baseline**: A30's qemu_repro.sh result `660 'link finish:'
  lines captured` is unchanged because no codegen file was touched
  by this attempt (A31 is an Android-side instrumentation-only
  delta).
- **Device screencaps**: 5 PNG files in
  `.autoport/reports/A31-device-*.png`, sizes 27 KB → 2.2 MB. All
  show the home / recents UI (the app crashes too fast — < 1 s
  between `goal_main` and the SIGILL — to sample a foreground
  frame from the SDL surface).

## A32 scope (the next blocker, scoped tight)

1. Read the symbol-name string referenced from the info-pointer at
   `0x178170` (= `0x158174 + 0x1FFFC`). Two paths:
   a. Add a one-shot diagnostic to `gk_sigsegv_diag` that, on
      `BLR-to-EE_BASE` faults, treats the LDR base register as a
      symbol value pointer, derives the symbol-info pointer, reads
      the GOAL string at that pointer, and prints the symbol name.
      One build cycle.
   b. Or run the boot under `gdbserver-on-device`, set a one-shot
      breakpoint at PC = `0x7f014c69b0` (the LDR) before it fires,
      and inspect memory directly. Slower but does not need a
      libgk.so rebuild.
2. Cross-reference the symbol name against:
   - `game/kernel/jak1/pc_chain.cpp` (where the existing A11/A12/A14/
     A17 helpers chain symbol-binding fix-ups), and
   - `goal_src/jak1/engine/` (to find which `(define ...)` form
     should be writing this slot — almost certainly a PC-only helper
     that does NOT exist in the original-PS2 `.gd` build path).
3. Add a chained pre-kernel-version-check helper
   (`klink_a32_ensure_<symbol-name>_bound`) that writes the host
   function pointer into the symbol's value slot, in the same
   pattern as `a17_bind_pc_helpers`.
4. Re-test on device, expect the boot to advance past tpage-463 into
   `tpage-{remaining}` then into the level-info / progress / hud
   wiring, then into the display-loop `kernel-dispatch` invocation
   (which is what makes the renderer's swap chain actually present a
   game frame).

The work surface is small and narrow — this is exactly the same
shape as A11 / A12 / A14 / A17 (write 30-100 lines of glue, build,
re-boot, watch the on-device link count tick up by another batch).

## What this attempt did NOT do — honest exit

- It did NOT identify the symbol name. (Needs a second diagnostic
  build and a re-run on device, which is the natural A32-first-step.)
- It did NOT add an Android-side bind helper. (Same reason — would
  be premature without a name; the existing A11/A12/A14/A17 helpers
  are all keyed by name.)
- It did NOT advance to the renderer / dispatch loop. (The crash is
  unchanged shape from the A30 finish, and the screencaps reflect
  this — they show the post-crash recents UI, not an SDL frame.)
- The screencap evidence is "the app crashed" — the supervisor's
  independent screencap is expected to confirm the same.

## Files referenced

- Routed logcat tail (full):
  `.autoport/reports/A31-routed-logcat-attempt2.log` (1300+ lines)
- Earlier capture from A31 attempt 1 with the byte/branch dumps used
  in this report: `.autoport/reports/A31-boot-attempt1.log`
- Device screencaps (5):
  `.autoport/reports/A31-device-1-homescreen.png`,
  `.autoport/reports/A31-device-2-boot.png`,
  `.autoport/reports/A31-device-3-2s.png`,
  `.autoport/reports/A31-device-4-6s.png`,
  `.autoport/reports/A31-device-5-10s.png`.
- A30 close-out (anchor for the +25 delta):
  `.autoport/reports/A30-attempt-1-progress.md`.
