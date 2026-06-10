# Phase A33 — Fix summary: arm64 calling-convention/classing inversion — qemu 660 → 675 (`link finish: logo` reached in qemu arm64)

## Headline

The shared hud-classes-pc SIGSEGV (qemu ceiling 660 == device ceiling 354,
same DGO, same signal) is root-caused and FIXED. After the fix:

* qemu links **and executes** all three CGOs to completion — the old 660
  "ceiling" was the SIGSEGV during hud-classes-pc's top-level; now the run
  exits 0 with `A8 engine+game execute complete`.
* The harness gained the REAL next boot stage (TIT.DGO, 15 objects) and the
  qemu count is now **675**, including the canonical **`link finish: logo`**
  — the exact milestone the x86 desktop gate uses.
* x86 CGOs remain byte-identical to the A2 baseline (verified by
  build_b1_arm64_cgos.sh hash check) and the x86 desktop smoke still
  reaches `link finish: logo`.

## Reproduction (task 1)

`bash .autoport/lib/qemu_repro.sh .autoport/reports/A33-qemu-baseline.log`
reproduced the crash exactly: exit 139 (SIGSEGV), 660 link-finishes, last
`link finish: hud-classes-pc`, GK-DIAG:

```
GK-DIAG sig=11 fault=0x2146228b74 pc=0x21269a7a0c lr=0x21269a78e8
x8  = 0x23228b74   ← BOGUS GOAL ptr (top byte garbage)
x13 = 0x228844     ← self (the manipy process being spawned)
x15 = 0x2123000000 ← qemu EE base
```

Crash decode (from the diag's pc-window dump):

```
pc-20: ADD X16, X13, X15      ; (-> self ...)
pc-16: LDR W8, [X16, #0x74]   ; (-> self draw)            [draw-control]
pc-12: ADD X16, X8, X15
pc-8 : LDR W8, [X16, #0x50]   ; (-> draw sink-group)      ← reads 0x23228b74 from HEAP
pc-4 : ADD X16, X8, X15
pc+0 : LDR W8, [X16, #0]      ; (-> sink-group merc-sink) ← SEGV
```

The faulting GOAL function is `make-nodes-from-jg`
(goal_src/jak1/engine/common-obs/process-drawable.gc:123, object
`process-drawable` at GOAL 0x39a68a4, crash at +0x1168), reading
`(-> self draw sink-group merc-sink foreground-texture-page)` at line 161.
The corrupt field was WRITTEN earlier by `initialize-skeleton` line 375:
`(set! (-> s3-0 sink-group) (-> s1-0 foreground-sink-group v1-43))`.
hud-classes-pc's top-level triggers it via
`(activate-hud-pc *display-pool*)` → `process-spawn hud-battle-enemy` →
`init-particles!` → `hud-pc-make-icon` → `manipy-spawn` →
`initialize-skeleton`.

## Root cause (task 2)

New diagnostic built for this phase: the arm64-backend goalc's
`:disassemble` produced Zydis garbage (x86 decoder on A64 bytes); wired the
existing capstone decoder into `FunctionDebugInfo::disassemble_debug_info`
(goalc/debugger/disassemble.{h,cpp}, DebugInfo.cpp) to get IR-annotated
A64 dumps. The dump of `initialize-skeleton` pinned the corrupting store:

```
[0x10974] mov x16, x16        mov igpr-246, igpr-232      ; v1-43 — IN X16(!)
[0x10978] lsl x16, x16, #5    shl igpr-246, 5
[0x10980] movz x8, #0xb0
[0x10984] ldr x9, [sp, #0x10]                              ; reload spilled s1-0
[0x10988] add x8, x8, x9
[0x1098C] add x16, x16, x8    addi igpr-247, igpr-248      ; sink-group ptr in X16
[0x10990] add x16, x3, x15    move [igpr-7 + 80], igpr-247 ; ← X16 = host(s3-0): VALUE DESTROYED
[0x10994] str w16, [x16, #0x50]                            ; stores low32(HOST addr)!
```

`store_goal_gpr` (IGenARM64.cpp) uses **X16 as its paired-ADD addressing
scratch** (`a6_enc_add_x16_xn_xm`), and the register allocator had placed
the VALUE being stored in X16. The store therefore wrote
`low32(EE_base + s3-0)` = `0x23228b74` into `(-> draw sink-group)`
(s3-0 = 0x228b74, EE base 0x2123000000 — exact match with the crash dump).
On-device the EE base is 4 GB-aligned (0x7f00000000) so low32 is clean and
THIS instance is masked — but the same constraint family corrupts spill
slots there (A32's `LDR X7, [SP,#0]` → 0xfd596f80 = low32 of a host stack
address), which is why the device died at the same DGO with a different
immediate shape.

Why was an allocatable value in X16 at all? Three interacting defects, all
stemming from the fact that goalc carries **x86-model register ids
everywhere** (emitter::gRegInfo is the x86 register file on every backend;
the AArch64 bank split happens only at encode time via `id & 0x1f`):

1. **CallingConvention.cpp handed out XMM ids (16..24) for 128-bit
   args/returns on the arm64 backend too.** Those become regalloc
   CONSTRAINTS. `id & 0x1f` maps them onto X16/X17 (the emitter's
   addressing scratch), X18 (AAPCS platform register) and X20-X22 — which
   the arm64 mapping reserves for pp/st/offset. In initialize-skeleton,
   `res-lump-value`'s `uint128` return (process-drawable.gc:371,
   `:default (the-as uint128 1)`) constrained the call return to XMM0=16
   → X16; move-coalescing kept v1-43 in X16 through line 375.
2. **`Register::is_128bit_simd(ARM64)` was INVERTED**: it tested
   `Q0..Q15`, which alias `X0..X15` (= ids 0..15) in the ARM64_REG enum.
   For every x86-model id the answer was backwards, so EVERY function
   call's args/returns were mis-classed (GPR args became INT_128-class
   vregs, true 128-bit values became GPR_64-class pinned to XMM ids).
   This is also why A25's mover-widening attempts regressed: partial
   widening over untruthful classes broke producer/consumer bank pairing
   (the A25/A26 [24..31]-slot special cases were treating a symptom).
3. **`emit_arm64_reg_to_reg_mov` only bank-corrected the [24..31] id
   slot**, so float↔gpr argument and return moves emitted wrong-bank GPR
   movs (e.g. `mov x1, x23` for `mov ii128-225, ifpr-215` — the float
   `time` argument to res-lump-value passed stale X23 garbage; float
   RETURNS via IR_Return read the stale X alias too).

## The fix (task 3) — all x86-output-preserving

* `goalc/emitter/CallingConvention.cpp` — under `GOALC_BACKEND_ARM64`,
  every arg/return uses a GPR slot (128-bit truncates to 64, like every
  other 128-bit-through-GPR path on this backend). Caller
  (`get_function_calling_convention`) and callee (`get_arg_registers`)
  stay symmetric by construction.
* `goalc/emitter/Register.h` — `is_128bit_simd(ARM64)` now uses x86-model
  semantics (ids 16..31), un-inverting call-boundary classing.
* `goalc/compiler/compilation/Function.cpp` + `Type.cpp` — arm64 function
  and method returns always go through the GPR return reg (no
  `to_xmm128`/`change_class(INT_128)` pinning to XMM0=X16); the
  bitfield-128 inspector arg constraint moved off `get_xmm_arg_reg(0)`.
* `goalc/compiler/IR.cpp` — `emit_arm64_reg_to_reg_mov` now dispatches on
  the register BANK (x86-model id ≥ 16 = V bank): fp→fp `MOV Vd.16B`,
  FLOAT↔gpr `FMOV W↔S` + `SXTW` (mirroring the x86 oracle's
  movd+movsx), 128-bit cross-bank `FMOV X↔D` (mirroring movq), gpr→gpr
  unchanged (preserves the X14/s7 MOV+SUB fixup and id-4→SP handling).
  `IR_Return::do_codegen_arm64` routes through it (float returns were
  blind GPR movs before).
* `goalc/emitter/IGenARM64.cpp` — `ASSERT_MSG` guards in
  `store_goal_gpr` / `load_goal_gpr` / `a6_enc_add_x16_xn_xm`: any future
  non-GPR-bank id in a GOAL memory op fails the COMPILE loudly instead of
  silently corrupting the heap.
* `game/linux-arm64/linux_arm64_main.cpp` — optional Stage 4 loads
  `out/jak1-arm64/iso/TIT.DGO` (the real next boot stage; absent file =
  pre-A33 behavior exactly, so qemu_repro.sh callers without it see no
  change). The arm64 TIT.DGO is produced by the same `(make-group "iso")`
  pipeline and stashed next to the CGOs.
* Diagnostics: IR-annotated capstone disassembly for the arm64 goalc
  (goalc/debugger/) — `(asm-file ... :disassemble)` now emits real A64.

## Evidence

* Baseline: `.autoport/reports/A33-qemu-baseline.log` — exit 139, 660
  link-finishes, GK-DIAG at hud-classes-pc (the full register/insn dump
  quoted above).
* Fix v1 (3 CGOs): `.autoport/reports/A33-qemu-fix-v1.log` — exit 0,
  660 link-finishes, `A8 GAME.CGO link complete` + `A8 engine+game
  execute complete` — crash GONE; 660 is the 3-CGO object count
  (8 + 306 + 346), not a crash ceiling.
* Fix v2 (with TIT.DGO): `.autoport/reports/A33-qemu-fix-v2.log` — exit
  0, **675** link-finishes, tail: tpage-1609/416/415/397/1499, **logo**,
  logo-black, logo-cam, logo-volumes, ndi, ndi-cam, ndi-volumes,
  title-vis, then `A33 TIT.DGO link complete` + `A33 title execute
  complete`.
* arm64 CGO determinism: two independent `(make-group "iso" :force #t)`
  runs produced identical hashes (recorded in
  `A33-baseline-arm64-cgo-hashes.txt`, cross-checked against
  `B1-arm64-cgos.txt`).
* x86: `build_b1_arm64_cgos.sh` step-7 hash check passed ("x86 CGOs
  byte-identical to A2 baseline"); desktop smoke run reaches
  `link finish: logo` (453 link-finishes in the 90 s window).

## Device result (task 4) — 354 → 369 (+15), `link finish: logo` ON DEVICE

* APK assets synced: KERNEL/ENGINE/GAME.CGO + TIT.DGO (hashes in
  `A33-baseline-arm64-cgo-hashes.txt`; TIT.DGO sha
  4037d484ffde838d9987a99f24ac53a4bb7bbd5b5b2bf6375ee36cebc4f2fef4).
* Run protocol: eae4df44 only; com.xiaoji.egggameplus disabled
  (`pm disable-user --user 0`) before, re-enabled (`pm enable`) after;
  d4_run.sh wiped the `.extracted_v1` sentinel so the fresh arm64 CGOs +
  TIT.DGO actually re-extracted on device.
* Routed logcat: `.autoport/reports/A33-routed-logcat-attempt1.log`
  (copy of D4-boot.log). `grep -ac "link finish:"` = **369** (A32 closed
  at 354; +15 = exactly the title DGO). The tail names the chain:
  tpage-1609/416/415/397/1499 → **logo** → logo-black → logo-cam →
  logo-volumes → ndi → ndi-cam → ndi-volumes → title-vis. The DEVICE
  loaded TIT.DGO through its own real boot flow (not the qemu harness
  stage) — the post-GAME.CGO kernel progression now runs.
* Screencaps: `A33-device-4-1500ms.png` (landscape SDL surface up with
  the touch-controller overlay over a BLACK render area — honest call:
  surface alive, NO game content drawn, the crash fires before the
  renderer pump) and `A33-device-1-4s.png` (post-crash home screen).
  Black ≠ render: the title screen is NOT yet drawn.

## Next blocker (named for the next phase)

New on-device crash class AFTER `link finish: title-vis` (#369):

```
GK-DIAG sig=11 fault=0x7efffffffe pc=0x7f01ce0b98 lr=0x7f01ce0bd8
x15 = 0x7f00000000 (EE base)   x16 = 0x7f00000000
fault = EE_base + (s64)-2  →  the dereferenced GOAL "pointer" is the
64-bit literal -2
```

* The owning object is **game-info** (loaded at GOAL 0x1ce0680 per the
  `[link and exec]` bracket in the routed logcat; crash at +0x518,
  lr at +0x558 — same function).
* -2 / 0xfffffffe is a sentinel value (the INVALID_HANDLE / `(new
  'static 'handle)`-family constants live in this range), so the shape
  is "post-title boot code in game-info dereferences a handle/sentinel
  that was never populated on this runtime surface" — plausibly an
  auto-save / task / *game-info* sub-structure that the Android runtime
  hasn't initialized (mirrors the A32 lesson: qemu's harness stops at
  link/execute, the device runs the REAL post-link boot, so device-only
  crashes past this point are runtime-surface gaps, not codegen).
* qemu cross-check: the qemu harness executes the same TIT.DGO top-levels
  cleanly (675/675, exit 0) — the -2 deref happens in the POST-link boot
  progression (kernel dispatcher / game-info init), which only the device
  runs. A34 should reproduce by extending the device-side diag (the A18
  trap already names symbol slots) or by porting the kernel-dispatch step
  into the qemu harness.

## Validator

`bash .autoport/validators/phase-A33-arm64-regalloc-spill-sprint.sh` —
PASS (pre-device re-run): no forbidden edits; anti-cheat clean; report
present; x86 desktop smoke reaches `link finish: logo`; qemu count 675
(> 660, fix path) with `A33-baseline-arm64-cgo-hashes.txt` matching the
actual CGOs.
