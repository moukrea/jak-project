# Phase A34 — attempt 2 progress: FOUR arm64 codegen bug classes root-caused & fixed (offset truncation: 620 sites; float conditionals comparing the wrong register bank: 605 sites; static-load LDR-literals that cannot span the heap: 304 dead loads; PS2 128-bit SIMD ops emitted as wrong-arrangement stand-ins), display loop + renderer thread reached on-device

## Headline

Attempt 1 ran out of turns before the post-fix device boot ever ran (a
Google Play Mainline reboot storm ate the device window — see
SUPERVISOR_JOURNAL 15:45). Attempt 2 ran it and root-caused + fixed
FOUR further arm64 codegen bug classes (bugs 3-6 below; attempt 1's
init_crc + trampoline fixes were bugs 1-2), each found by
instruction-level forensics on a live device crash:

1. **Silent offset truncation** (bug 3, commit 7a1e0b690): the emitter
   floor-divided unencodable GOAL access offsets into the scaled-imm12
   field (316 → 312), mis-addressing **620 loads/stores in GAME.CGO**.
2. **Float conditionals compared the wrong register bank** (bug 4,
   commit 6bf6288f6): `IR_ConditionalBranch::do_codegen_arm64` ignored
   `condition.is_float` and emitted integer `CMP Xa,Xb` — with floats
   living in the SIMD bank, every float branch in the game was decided
   by host C++ register junk. **605 compare sites in GAME.CGO** flip to
   real `FCMP`.

3. **Static float/vector loads emitted as LDR-literal** (bug 5, commit
   5d5ea19f8): imm19 reaches ±1 MB, but top-level `(define …)`
   initializer code references main-segment statics across tens of MB
   of heap — klink logged `LDR-literal imm19 out of range` **304
   times** per boot and left imm19=0 placeholders that loaded their own
   code bytes, silently poisoning static data. Now emitted as
   ADRP X16 + LDR Sd/Qd,[X16,#lo12] (the proven StaticVarAddr shape,
   ±4 GB); zero out-of-range lines in the post-fix qemu boot.
4. **PS2 128-bit SIMD ops were wrong-arrangement stand-ins** (bug 6,
   commit 9ef575893): the PEXT/PCPY family always emitted ZIP .16B,
   PSRLDQ/PSLLDQ were per-lane bit shifts, blend.vf ignored its mask —
   the uint128 res-tag bitfield extraction (via pcpyud) produced
   byte-doubled garbage "types". Now exact x86 VPUNPCK/EXT/INS mirrors.

Each fix moved the on-device boot measurably deeper into the title
flow:

| run | CGOs | links | died in |
|-----|------|-------|---------|
| 3 | attempt-1 fixes | 369 (title-vis) | master-track-target (bug 3) |
| 4/5/7-10 | +offset fix | 369 + renderer thread enters | cam-string :enter outro (bug 4) |
| 11 | +float-compare fix | 369 | type-type? on garbage type (bugs 5+6) |
| 12 | +LDR-literal fix | 369 | same site (bug 6 still present) |
| 13 | +SIMD-semantics fix | **427 — `logo-intro` linked** | gstring null-string compare from entity.gc (next blocker) |

Run 13 boots THROUGH the title-vis wall, spawns the camera system and
target, loads 58 more objects including the **ND-logo level
(`logo-intro`)**, with the display loop dispatching and the renderer
thread alive — then dies in a gstring compare handed a null string
from an entity.gc name-lookup (pid-8 process, status 'running; pc
byte-matched to KERNEL gstring, frame 0 to ENGINE entity).

**The renderer-stage verdict the mandate asked for**: the boot can no
longer be claimed "display runs but draws nothing" ambiguously — the
routed logcat states it outright:

```
android_renderer_run: NO GAME CONTENT RENDERER WIRED — maintaining
clear/swap loop only. The real OpenGL renderer port is bucket D in
REDESIGN.md.
```

`android/android_renderer.cpp` is an honest clear/swap stub by design
(the post-LARP redesign deleted the fake solid_color renderer; the
real GLES content port is REDESIGN.md's bucket D, not yet scheduled).
A frame with REAL game content is therefore structurally impossible in
this phase regardless of GOAL-side progress — the named "stage that
produces nothing" is the entire game-content renderer, absent by
explicit design note in the log line above.

## Run 3 (attempt-1 fixes, pre-truncation-fix CGOs)

* 369 link-finishes, last = title-vis, then SIGSEGV at
  16:03:20.739 — 11 ms after title-vis: `fault=0x7f20000024
  pc=0x7f01e02ff0 lr=0x7f01e0bd10`, x8=0x20000000, x2=x12=−30000.
* Attempt-1's two fixes both held: the A33 EE−2 (`init_crc`/`_empty_`)
  crash and the EE−4 (`return-from-thread-dead` pp=0) crash are GONE.
* Decode (offline byte-match of the GK-DIAG pc/lr windows against the
  on-disk CGOs — `/tmp/a34_find_bytes.py`, cgo_inspect.py function-tag
  walk): pc ∈ GAME.CGO OBJ#229 `cam-master` fn#4 =
  **`master-track-target`**, at its 3rd inlined `handle->process
  (-> self drawable-target)`; lr ∈ fn#15 (a `cam-master-active`
  handler); lr−pc = 0x8d20 matches the on-disk layout exactly.
* The faulting access: `LDRSW X1,[X16,#36]` — the pid compare of
  handle->process — with the deref'd "process" = 0x20000000 garbage.

## Bug 3 root cause — silent offset truncation in the arm64 emitter

* x86 oracle (out/jak1/iso GAME.CGO, same fn, same site):
  `mov 0x13c(%r15,%r13,1),%r9` — `drawable-target` is an 8-byte handle
  at byte offset **316**.
* arm64 emitted `ldr x9,[x16,#312]` — **4 bytes short**. 316 is not a
  multiple of 8, so it fits neither the scaled-imm12 form
  (`a6_fits_scaled_imm12`) nor LDUR/STUR's simm9 (−256..255); the
  third branch of `a6_pick_access` (IGenARM64.cpp) deliberately
  "approximated" the imm12 — floor(316/8)=39 → 312. The loaded
  "handle" was therefore [previous-field-word | drawable-target-low]:
  the `#f` null check tested the wrong word and the ppointer deref
  chased garbage.
* Why qemu/x86 never see it: qemu's harness stops at link+execute and
  never runs per-frame state handlers; x86 SIB encodes any byte
  displacement. Why the boot got this far anyway: most GOAL field
  offsets are naturally aligned; 620 sites in GAME.CGO (600 in
  ENGINE.CGO) were silently mis-addressed, all in code that either
  hadn't run yet or read tolerably-wrong values.
* Fix (goalc/emitter/IGenARM64.cpp, commit 7a1e0b690):
  `a6_offreg_access` now builds the full sequence — `ADD X16,addr,off;
  [ADD/SUB X16,X16,#hi12,LSL12;] [ADD/SUB X16,X16,#lo12;] access
  [X16,#0]` — for any offset in ±16 MB, used by all six GOAL accessors
  (load/store_goal_gpr, store_goal_vf, load_goal_xmm128,
  load/store_goal_xmm32). Every raw scaled helper
  (ldr/str x/w/h/b/sb/sh/sw/q/s) now ASSERTs exact encodability so any
  remaining truncating caller fails the goalc compile loudly.
* Verification: regenerated CGOs show cam-master reading
  `ADD X16,X16,#0x13c; LDR X9,[X16]`; zero asserts across all 1317
  targets; KERNEL.CGO byte-identical (kernel has no unaligned
  offsets); x86 CGOs byte-identical to the A2 baseline; qemu
  675 link-finishes exit 0 (A34-arm64-mi-fix2.log, /tmp/a34-qemu-fix4.log).

## Runs 4/5/7 (fixed CGOs on device)

* Boot: 369 link-finishes in ~4 s, `link finish: title-vis` at
  +0.000, **`android_renderer_run: entered` +1 ms** (renderer thread
  never started in any prior phase), SIGSEGV +18 ms:
  `fault=0x7efffffffc pc=0x7f004ecd08 lr=0x7f004ed248` — a NEW, later
  crash. Screencaps at +2/4/6/10/20/40 s (A34-device-*.png) show the
  MIUI home screen post-crash (the app dies before composing a frame).
* Decode: pc ∈ ENGINE/GAME OBJ#18 `geometry` fn#37 =
  **`curve-evaluate!`**, second cond clause
  `(>= arg1 (-> arg4 (+ arg5 -1)))` with knots(arg4)=0 AND
  num-knots(arg5)=0 → reads GOAL −4 → EE−4. lr ∈ fn#41 =
  **`curve-closest-point`**, fn-local 0xb0 = the return of the first
  `curve-evaluate!` in its subdivision loop (its earlier
  `curve-length` call survives the same zero curve because
  `*(EE+0)`-as-float routes both boundary compares false).
* A34-DIAG (new in this attempt, android/gk_android_main.cpp commits
  02d6c92fd): on any GOAL-shaped fault, dump pp's identity + spline
  window, the `*camera*` master's outro window, and the X29 frame
  chain. Run-5/7 facts:
  - pp = 0x1d59b4: a camera-slave, status='suspended,
    state=`cam-free-floating`, next-state=#f, pid 25.
  - Its fields are CORRECTLY initialized: intro-t=1.0,
    intro-t-step=0.0, spline-exists=#f, cam-entity=#f, spline-curve
    all-zero — i.e. cam-slave-init/init-vars DID run (kills the
    "init skipped" theory).
  - `*camera*`=0x1d8b24: status='suspended, state=`cam-master-active`,
    pid 23, outro-curve all-zero, outro-t=outro-t-step=
    outro-exit-value=0.0 — cam-master-init ran to completion (kills
    the "cam-string enter reads garbage outro-t-step" theory; that
    guard `(!= outro-t-step 0.0)` is false).
* Both statically-reachable `curve-closest-point` callers are guarded
  by fields the dumps show clean (`cam-spline` :enter on cam-entity,
  `cam-curve-pos` on spline-exists) — so the caller must be identified
  dynamically: run 8 adds a GOAL frame-pointer chain walker
  (STP X29,X30 prologue → [X29]=prev-FP, [X29+8]=saved LR) to read the
  real call chain from the crash. Anchor for offline mapping:
  geometry's MAIN segment is loaded at GOAL 0x4e7490
  (= pc 0x4ecd08 − seg-local 0x5878).

## Runs 8-10 — naming the zero-curve caller (fp-walk forensics)

The zero-curve curve call 18 ms after title-vis. The fp-chain walk
(run 8) + corrected segment math give the true chain:

```
crash pc  = geometry fn#37 curve-evaluate! (knots=0, num-knots=0,
            2nd cond clause knots[num-knots-1] -> EE-4)
frame 0   = geometry fn#38 curve-get-pos! (the wrapper)   [base 0x4e74b0]
frame 1   = 0x1e22b08 — the curve-get-pos! CALLER (cam-master/cam-states
            heap region; exact site pending run-10 byte windows)
frame 2   = 0x1dfaae0 — cam-standard-event-handler territory
frame 3   = 0x1e0e6e8 — INSIDE the slave's installed event-hook
            (pp dump: event-hook = 0x1e0e674, frame 3 = +0x74)
frames 4/6= 0x4d12cc  — recurring event/dispatch helper
frame 5   = 0x1e0a0dc, frame 7 = 0x1ee5104 -> host C++ boundary
```

Hard facts that kill the easy theories (A34-DIAG dumps, x86-oracle
offset cross-check `movss %xmm7,0x944(%r15,%r13,1)` confirming the
dump's field decode):

* pp = camera-slave 0x1d59b4: status='suspended (event handler running
  in a suspended process — consistent with send-event), state =
  `cam-free-floating`, next-state = #f (a 'change-state-no-go shape),
  event-hook ALREADY swapped to a non-free-floating state's handler.
* The slave is correctly initialized: intro-t=1.0, intro-t-step=0.0,
  spline-exists=#f, cam-entity=#f, spline-curve zeroed.
* The master *camera* 0x1d8b24 is correctly initialized:
  state=cam-master-active, outro-curve all-zero, outro-t = outro-t-step
  = outro-exit-value = 0.0.
* Therefore EVERY statically-reachable curve-get-pos! call site's guard
  reads FALSE at crash time (cam-spline enter needs cam-entity, the
  cam-decel/cam-string outro paths need outro-t-step != 0,
  cam-curve-pos needs intro-t<1 or spline-exists) — yet one of them
  ran. Either a guard's load reads stale/garbage at guard time, or the
  state-object's enter field jumps into the middle of a function.
* *(EE+0) = 0x20000000 (the run-3 "mystery constant" — GOAL address 0's
  actual content; explains low-memory garbage walks surviving instead
  of faulting).
* Run 10 widened each frame's window to 24 words: frame 1 byte-matched
  **cam-states.gc:1621 — cam-string's `:enter` outro branch** exactly
  (the `bd494a17` outro-exit-value load + `MOV X2,#0x92C` outro-curve
  address staging; the three relocated adrp/add pairs decode as
  [curve-get-pos!, *camera*, *camera*] — all correct).

## Bug 4 — float conditionals compared the wrong register bank

* With the call site named, the on-disk guard told the whole story:

  ```
  1442c: ldr s23, [x16, #2372]   ; S23 = (-> *camera* outro-t-step)
  14430: ldr s22, =0.0           ; S22 = 0.0
  14434: cmp x23, x22            ; INTEGER compare of X23/X22 (!)
  14438: b.eq <skip-outro>
  ```

  The float loads are correct (SIMD bank, S22/S23), but
  `IR_ConditionalBranch::do_codegen_arm64` ignored `condition.is_float`
  and emitted the integer `cmp_gpr64_gpr64` — comparing **X23 (a libgk
  C++ callee-saved value, 0x7981d513fc at crash) against X22 (a mirror
  of the EE base, 0x7f00000000)**. Never equal → the outro branch is
  taken on every Android boot regardless of the actual floats →
  curve-get-pos! runs on the master's all-zero outro-curve →
  curve-evaluate! reads knots[num-knots-1] = knots[-1] → EE-4. The
  at-crash dumps were all "correct" because the DATA was never wrong —
  the COMPARE was.
* This is the A33 register-bank family in value position: every float
  conditional in the game (`(< f g)`, `(>= f 0.0)`, …) was decided by
  whatever happened to be in the same-numbered X registers. Boot
  survived 369 links because link/init code is integer-dominated; the
  display loop is where float logic becomes load-bearing.
* Fix (goalc/compiler/IR.cpp, commit 6bf6288f6): float conditions emit
  `cmp_flt_flt` (FCMP Ss,Ss) with the FP condition-code mapping
  (LT→MI, LEQ→LS, GT→GT, GEQ→GE, EQ/NE unchanged; unordered compares
  come out false for the ordered kinds — the x86 COMISS unordered
  semantics differ only for NaN inputs, accepted for now and noted).
  605 GAME.CGO / 590 ENGINE.CGO compare sites change. x86 CGOs remain
  byte-identical to the A2 baseline; qemu 675 link-finishes exit 0;
  zero emitter asserts across all 1317 targets.

## Bug 5 — static loads through LDR-literal cannot span the heap

* Run 11 (bug-4 fix on device): boot again 369 links + renderer entry,
  new crash 6 ms after renderer entry: fault=EE+0x1b1b1418,
  pc=GOAL 0x18370c. The (by now routine) fp-walk + 24-word windows +
  byte matcher named the chain in one pass: gkernel event dispatch →
  `logic-target` (the target/player spawn, pid-12 process in status
  'initialize) → `process-drawable` init-from-entity →
  `res` get-property-* → **gcommon `type-type?`** walking a type-parent
  chain whose "type" is garbage 0x1b1b1414.
* The routed logcat held the cause in plain sight: 304×
  `klink-arm64: LDR-literal imm19 out of range at 0x7f03...` during
  linking. game/kernel/common/klink.cpp:381 logs and ABORTS the patch
  when the pc-relative distance exceeds imm19 (±1 MB) — the placeholder
  (imm19=0) then loads the instruction's own bytes. The emitters:
  `IR_StaticVarLoad::do_codegen_arm64` was the only remaining
  LDR-literal producer (float + vector-float statics); top-level
  initializer code lives tens of MB from main-segment statics.
* Fix (goalc/compiler/IR.cpp, commit 5d5ea19f8): emit
  ADRP X16 + LDR Sd/Qd,[X16,#page-low-12] with both instructions
  link-recorded — the exact shape IR_StaticVarAddr already uses, and
  both patchers already classify LDR_St/LDR_Qt imm12 (scales 4/16).
  Post-fix qemu boot logs ZERO out-of-range lines (was >0), 675
  link-finishes exit 0, x86 byte-identical, no emitter asserts.
## Bug 6 — the PS2 128-bit ops were classifier-passing stand-ins

* Run 12 (bug-5 fix on device, ZERO out-of-range klink lines) crashed
  at the SAME type-type? pc with the same chain — so the garbage
  "type" had a second source. Disassembling `get-property-value`'s
  `(-> tag elt-type)` (a uint128 res-tag bitfield, bits 64-95):

  ```
  c0: ldr q24, [x16]              ; the 128-bit res-tag
  c8: zip2 v23.16b, v24.16b, v24.16b   ; "pcpyud" stand-in (!)
  cc: fmov x3, d23 ; lsl/lsr #32       ; low 32 of the wrong bytes
  ```

  The bitfield extraction lowers through `pcpyud` (x86 VPUNPCKHQDQ —
  move the high qword down). The A2-era arm64 stand-ins emitted
  ZIP .16B for the WHOLE PEXT/PCPY family ("any non-NOP NEON
  instruction satisfies the realness check") — a byte-interleave of
  the upper halves, i.e. byte-doubled garbage instead of the high
  qword. The same stand-ins back joint/bones/matrix/collide/ocean/font
  math; PSRLDQ/PSLLDQ byte shifts were per-lane bit shifts; blend.vf
  (vector-h.gc) ignored its mask and second source entirely.
* Fix (commit 9ef575893): exact x86 mirrors —
  PEXTL/U B→ZIP1/2 .16B, H→.8H, W→.4S, PCPYLD/UD→ZIP1/2 .2D;
  vpsrldq/vpslldq → MOVI V0,#0 + EXT (V0 is outside the GOAL SIMD bank);
  blend_vf → INS-based per-lane select honoring the mask.
  vpackuswb/vpshuflw/hw stand-ins remain — no jak1 goal_src users.
* Gates: zero asserts / 1317 targets, x86 byte-identical, qemu 675
  exit 0. Device run 13 in flight.

## Run 13 outcome + exact next blocker

* 427 link-finishes (up from 369): the title continue's level loads
  proceed — last link `logo-intro` (the Naughty Dog logo level). The
  camera master survives in `cam-master-active` (its A34-DIAG dump in
  the run-13 crash shows clean state), the target spawned, the display
  loop dispatches processes every frame.
* Crash ~4 s into boot: `fault=0x7efffffffc` (the `(-> 0 type)` shape)
  at pc=GOAL 0x4c5234 ∈ KERNEL.CGO `gstring` (byte-matched; a string
  compare reading its argument's type tag with the argument = 0),
  called from ENGINE `entity` (frame-0 byte-match — an entity
  name-lookup walk), in a pid-8 process with status 'running. I.e. an
  entity-by-name-style lookup hands a NULL string to a gstring
  compare during the logo/title flow — the next un-run code path's
  divergence, same forensics loop applies (fp-walk + windows name it
  in one device cycle).
* Screencaps A34-device-{1-2s..6-40s}.png (run 13) + archived
  run3-/run4- sets: the app shows the MIUI home screen post-crash; no
  game content is possible this phase per the renderer verdict above.

## Hygiene

* x86 desktop smoke: green (validator-run); qemu 675 exit 0 after
  EVERY fix (no regression); gk_log_pipe + all A11-A33 diag infra
  intact; zero emitter asserts across all regens.
* Device: eae4df44 only; egggameplus disabled per-run and re-enabled
  by each run script's EXIT trap; .extracted_v1 wiped per install so
  APK-bundled CGOs actually land; APK asset CGOs synced from
  out/jak1-arm64/iso (hashes in A34-baseline-arm64-cgo-hashes.txt).
* Commits: 7a1e0b690 (offset truncation fix + baselines), 02d6c92fd +
  follow-ups (A34-DIAG process/master dumps, fp-chain walk, per-frame
  byte windows), 6bf6288f6 (float-condition FCMP), 5d5ea19f8
  (static-load ADRP+LDR), 9ef575893 (PS2 128-bit op semantics).
* Phase tally: SIX distinct arm64 codegen/runtime bug classes fixed
  across attempts 1+2 (init_crc prelude, push-RA/.jr trampoline +
  .load-sym-to-SP, offset truncation, float-condition bank, static
  LDR-literal range, SIMD stand-in semantics) — every one found by
  instruction-level forensics on live device crashes and fixed at the
  mechanism, no guards or stubs.

