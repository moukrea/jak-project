# Phase A34 — attempt 1 progress: post-title-vis sentinel deref root-caused & fixed (init_crc) + the spawn/state trampoline contract fixed (push-RA/.jr + .load-sym-to-SP)

## Headline

Two real, independent runtime-surface/codegen bugs stood between
`link finish: title-vis` and the display loop. Both are root-caused with
instruction-level evidence and fixed at the mechanism (no guards, no
stubs, no skipped init):

1. **`init_crc()` was never called on the custom boot paths** (Android
   goal_main + linux-arm64 harness) → every static-data `'()` linked to
   a freshly-interned ordinary `_empty_` symbol instead of the fixed
   empty pair → `get-continue-by-name` garbage-walked the test-zone
   continues list and did `(car 0)` → the A33-reported SIGSEGV at
   fault=EE_base-2.
2. **The x86 "push RA; jmp func" pattern in the GOAL kernel's
   spawn/state asm-funcs does not survive x86→arm64 translation** →
   every process death / `(go ...)` skips `return-from-thread-dead`,
   unravels the kernel stack discipline, and eventually pops the leaked
   trampoline with pp=0 → the second on-device SIGSEGV at
   fault=EE_base-4, 4 ms after title-vis. Plus a latent third: the
   `.load-sym sp *kernel-sp*` tails of return-from-thread/-dead and
   thread-suspend loaded the saved kernel SP into the literal **X4**
   instead of SP (id-4 translation existed for mov/add/sub only).

## Bug 1 — the A33 blocker: car-of-0 in get-continue-by-name

* Crash decode (A33-routed-logcat-attempt1.log): pc=0x7f01ce0b98 is
  `LDURSW X3, [X16,#-2]` with X16 = X11 + EE_base and X11 = 0 — a GOAL
  `(car 0)`; pair car lives at ptr-2 → fault 0x7efffffffe = EE_base-2.
  x14 = EE+0x14fd24 → s7 = 0x14fd24: the regs full of 0x14fd24 are
  `#f`, x1 = `#t`, x9 = 0x14fd1a = s7-10 = `'()` (the loop's
  termination compare value).
* Function identified from the diag's own lr-window word dump
  (disassembled offline): object **game-info** @0x1ce0680 (link bracket
  in the same logcat), function at 0x1ce0b40..0x1ce0c70 =
  **`get-continue-by-name`** — the disasm maps 1:1 to source:
  `*level-load-list*` value cell load, outer car → symbol → value →
  `(-> lli continues)` at +52, inner car at the crash pc, `string=`
  BLR at the LR site, cdr at +2, `'()` compares.
* The outer node at crash (x12=0x1d93b52) is the pair at the very end
  of level-info's allocation = the `(cons! *level-load-list*
  'test-zone)` head → **first iteration, test-zone**.
* New read-only **A34-PROBE** in the qemu harness (linux_arm64_main.cpp)
  walks `*level-load-list*` exactly like the device code. Before the
  fix (A34-qemu-probe-1.log): every `'()`-valued static field of all 27
  level-load-infos reads **0x193304**, the spine terminator too
  ("node[27] NOT A PAIR: 0x193304") — but the real empty pair is
  0x18fdfa (s7-10). 0x193304 is a symbol-slot address: `_empty_`
  interned as an ordinary symbol.
* Mechanism: jak1's `find_symbol_from_c` special-cases `_empty_` ONLY
  when `crc32(name) == EMPTY_HASH` (a compile-time constant). Desktop
  jak1::goal_main calls `init_crc()` (kboot.cpp:56); Android's
  goal_main and the harness never did, so crc_table stayed all-zero →
  crc32 returns wrong-but-self-consistent hashes → every symbol still
  interns/resolves fine — except the single hash-CONSTANT comparison.
  klink's symlink for static `'()` then interns a fresh `_empty_` →
  static `'()` != runtime `'()` → `(null? x)` never terminates the
  walk → low-memory garbage-walk → (car 0).
* Cross-check that the data/emitter/linker were never at fault: a v3
  link-table differ over the level-info object shows the x86 and arm64
  MAIN segments carry **byte-identical record sets** (1536 sym / 355
  type / 1241 ptr slots, zero diffs).
* Fix (gap-class, desktop-prelude parity):
  - `android/android_goal_main.cpp`: `init_crc()` + the masterConfig
    aspect/language/timeout/volume block right after `jak1::InitParms`
    (mirrors kboot.cpp:53-86; GOAL reads these via scf-get-* during
    display boot).
  - `game/linux-arm64/linux_arm64_main.cpp`: `init_crc()` at the end of
    `init_all_globals()` (must run after kscheme_init_globals_common,
    which zeroes the table).
* Verified in qemu (A34-qemu-fix-2.log): all 27 nodes decode perfectly —
  `packages/sound-banks/ambient/tasks/load-commands` read `'()`,
  `run-packages='()`/`wait-for-load=#t` for test-zone (probe field
  offsets corrected against the v3 object dump: +96/+108),
  `first-continue "title-start"` resolves for title, walk terminates on
  `'()`. 675 link-finishes, exit 0.
* Device result: the EE_base-2 crash is GONE; boot still reaches 369
  link-finishes and advances past get-continue-by-name — then hits
  bug 2.

## Bug 2 — the next blocker, hit 4 ms after title-vis: spawn/state trampoline

* New GK-DIAG: sig=11 fault=0x7efffffffc (EE_base-4 = `(-> 0 type)`),
  pc=0x7f0018aedc, lr=0x7f0018aed4, X13=0, SP=EE+0x1a7fe0.
* pc maps to object **gkernel** @0x1892f0 (+0x1bec) = function #18 =
  **`return-from-thread-dead`** — its first real op is
  `(deactivate pp)`: `LDUR W9, [X13+EE-4]` with pp/X13 = **0**.
  LR = the function's own entry → it was entered by an asm-style
  `.ret` popping a stack word. SP at crash = **thread stack-top - 32 =
  exactly the slot where set-to-run-bootstrap pushes its
  return-from-thread-dead trampoline** (set-to-run resets
  `(-> thread sp)` to stack-top; bootstrap brackets X30 at -16 and
  pushes the trampoline at -32).
* Mechanism (instruction-level, from the on-disk CGO disasm of fns
  #17/#18/#19/#20/#21/#70 vs their x86 oracles): x86's
  set-to-run-bootstrap / reset-and-call / enter-state install a custom
  return address with `push temp` and tail-`jmp` into the spawned GOAL
  function; the function's final `ret` pops the trampoline. On arm64,
  GOAL functions return through the paired STP/LDP X29/X30 contract —
  entered via BR, they return to a STALE X30: return-from-thread-dead
  never runs, deactivate is skipped, the kernel's stack discipline
  unravels on the thread stack, and the leaked trampoline word is
  eventually popped by an unrelated epilogue with pp long clobbered.
  pp (id-13/R13) is reserved-special on every backend (Register.cpp) —
  compiled code never touches it; the X13-write audit over all 74
  gkernel functions shows the asm-funcs' pp writes pair 1:1 with x86.
  The break is purely the RA hand-off.
* Fix A (goalc/compiler/CodeGenerator.cpp + IR.h/IR.cpp): asm-func
  pre-scan — for each `IR_JumpReg`, walk back over only
  `IR_RegSetAsm`/`IR_AsmAdd`; if that lands on an `IR_AsmPush`, the
  jump is a call-with-custom-RA and the arm64 emission pops the pushed
  word into X30 (`LDR X30,[SP],#16`) before the BR — the callee's
  paired epilogue then returns to the trampoline, byte-for-byte the
  x86 behavior. Site inventory over frozen goal_src/jak1 (4 `.jr`
  sites): transforms set-to-run-bootstrap, reset-and-call,
  enter-state; leaves thread-resume untouched (kernel-context saves +
  SP writes intervene).
* Fix B (IR_GetSymbolValueAsm + IR_GetSymbolValue arm64): when the
  destination of a symbol-value load is the id-4/RSP-model register
  (`.load-sym sp *kernel-sp*` in the return-from-thread/-dead and
  thread-suspend tails), load via X1 (RCX-model — dead at all three
  frozen sites) and `MOV SP, X1`. Previously the value landed in the
  literal X4 and SP was never restored — every thread death/suspend
  would have walked a wild stack one BLR after fix A.
* Emission verified in the regenerated KERNEL.CGO: bootstrap now ends
  `LDR X30,[SP],#16; BR X3`; rft/rftd/suspend tails now
  `LDR W1,[X16]; MOV SP,X1; ADD SP,SP,X15; pops`.

## Builds, gates, hygiene

* B1 pipeline re-run after the goalc fixes: **x86 CGOs byte-identical
  to the A2 baseline** (step-7 hash check) — both fixes are arm64-only
  emission paths. arm64 TIT.DGO re-captured via the same
  `(make-group "iso")` flow; hash unchanged (no kernel asm in TIT).
  Only KERNEL.CGO changed; new hashes in
  A34-baseline-arm64-cgo-hashes.txt; APK assets synced.
* qemu gate after everything: **675 link-finishes, exit 0** with the
  A34-PROBE walk clean (A34-qemu-fix-3.log).
* x86 desktop smoke: `link finish: logo` reached (453 link-finishes in
  the 90 s window).
* gk_log_pipe routing untouched; egggameplus disabled for device runs
  and re-enabled after; eae4df44 only.

## Device runs

* Run 1 (init_crc fix only): 369 link-finishes; EE_base-2 crash GONE;
  new crash = bug 2 above (full GK-DIAG register/window dump quoted in
  this report's Bug 2 section; the rotating D4-boot.log was
  subsequently overwritten — the run-2/3 logs are preserved
  explicitly).
* Run 2: aborted before install — INSTALL_FAILED_INSUFFICIENT_STORAGE
  at 3043 MB free; cleared via pm trim-caches + uninstall (the MIUI
  near-full-/data recipe), 4.5 GB free after.
* Run 3 (both fixes): see A34-routed-logcat-attempt3.log +
  A34-device-*.png screencaps (2/4/6/10/20/40 s).

## Next blocker

(to be filled by the run-2 outcome)
