# Phase A32 — Fix summary: pc-* helper backport + mips2c-noop rebind unblock 316 → 354 link-finishes (+38)

## Headline

A31 closed at on-device link-finish **316** (SIGILL at `tpage-463`,
`BLR ee_base` through unbound symbol slot at GOAL ptr 0x158174 = the
texture-page top-level call to `__pc-texture-upload-now`).

A32 advances to **354 link-finishes** (+38 over A31, +63 over A30's
291), past:

* the texture-page chain (tpage-463 through the texture-upload object),
* the fuel-cell chain (fuel-cell, fuelcell-naked),
* the actor base chain (eichar, sidekick, deathcam, game-cnt,
  rigid-body{-h}, water-anim, dark-eco-pool, nav-enemy{-h}),
* the platforming basics (baseplat, basebutton, tippy, joint-exploder,
  babak, sharkey, orb-cache, plat, plat-button, plat-eco,
  ropebridge, ticky),
* and into the HUD layer (hud-classes-pc).

The on-device crash signature changed: A31's was **sig=4 (SIGILL)** at
`pc=0x7f00000000` (= ee_base, the canonical fn-ptr=0 BLR shape). A32's
new blocker is **sig=11 (SIGSEGV)** at `pc=0x7f0150113c` inside real
GOAL JIT code, attempting an `LDR W6, [X16, #0]` where X16 was built
from a bogus GOAL pointer 0xfd596f80. The crash class has moved off
the "unbound symbol" surface and into a JIT-code/regalloc/spill
surface — qualitatively new ground.

## Root cause named (A32 fix #1)

The A31 next-blocker report correctly identified the LDR at
`pc=0x7f014c69b0` reading from GOAL ptr 0x158174 = a symbol-value slot
that was zero at link-finish #316. What A31 could not name was *which
symbol*. The existing `gk_diag::dump_sym_name_at_slot(regs[16])` call
already in `gk_sigsegv_diag` (android/gk_android_main.cpp:1693) DOES
name it — the line is in the routed logcat tail at the SIGILL frame:

```
GK-DIAG A11-DIAG texture-sym-zero: slot=0x7f00158174 value=0x0
   info=0x7f00178170 hash=0xd2919088 str=0x14cb414
   name="__pc-texture-upload-now" in_sym_range=1
```

(`grep -aE` instead of `grep` was needed — the previous A31 read
treated the binary-tagged logcat as binary and suppressed the line.)

`__pc-texture-upload-now` is the GOAL helper that uploads a texture
page; it is declared in `goal_src/jak1/kernel-defs.gc:435` and called
by tpage-463's top-level form (the very-first texture-page CGO whose
post-link execution body invokes the helper — see also
`goal_src/jak1/engine/gfx/texture/texture.gc:1476`).

**Why it was unbound on Android but not on qemu**:
- The upstream `init_common_pc_port_functions`
  (`game/kernel/common/kmachine.cpp:1086`) registers ~150 pc-*
  helpers, including `__pc-texture-upload-now`. But
  `game/kernel/common/kmachine.cpp` is NOT compiled into the Android
  build (only `game/kernel/jak1/kmachine.cpp` is — see
  `android/CMakeLists.txt`).
- Android's override at
  `android/android_runtime_compat.cpp:827-844` deliberately skips ALL
  the pc-* registrations with the comment "Android Display/Gfx port
  pending".
- linux-arm64 qemu sidesteps this by chaining `a17_bind_pc_helpers`
  onto the pre-kernel-version-check hook
  (`game/linux-arm64/linux_arm64_main.cpp:180`), binding ~80 pc-*
  helpers as no-op. Android already has a parallel `a17_bind_pc_helpers`
  (`android/gk_android_main.cpp:369`) — but its list was **missing**
  the three symbols `__pc-texture-upload-now`, `__read-ee-timer`,
  `__send-gfx-dma-chain` that linux-arm64 added in A29
  (`linux_arm64_main.cpp:297-299`). That A29 update never propagated
  to the Android a17 list. The omission was confirmed by a list-diff:

```
$ comm -23 <(sort qemu-a17-syms) <(sort android-a17-syms)
__pc-texture-upload-now
__read-ee-timer
__send-gfx-dma-chain
# (plus file-stream-* which are bound elsewhere on Android via
#  game/kernel/jak1/kmachine.cpp:593-598, and __pc-get-mips2c +
#  __a29-mips2c-noop which are A32 fix #2 territory)
```

## Fix #1 — pc-* helper backport (android/gk_android_main.cpp)

Three new entries added to `a17_bind_pc_helpers` next to the existing
`__pc-texture-relocate` line, with an in-source comment block that
cites A31 + linux-arm64 line numbers. The new bindings:

```cpp
jak1::make_function_symbol_from_c("__pc-texture-upload-now", d);
jak1::make_function_symbol_from_c("__read-ee-timer", d);
jak1::make_function_symbol_from_c("__send-gfx-dma-chain", d);
```

where `d = (void*)a17_pc_default` — the existing GOAL no-op that
already gates the other ~80 pc-* helpers. The trace message at the
end of `a17_bind_pc_helpers` was updated to enumerate the three
additions so the routed logcat names them.

After this fix alone, the on-device boot advanced 316 → 325 (+9
link-finishes), past tpage-463 → texture-upload → tpage-1032 →
tpage-62 → tpage-1532 → fuel-cell, terminating at a sig=4 SIGILL whose
A11-DIAG output named the next unbound symbol:

```
GK-DIAG A11-DIAG texture-sym-zero: slot=0x7f0015d5fc value=0x0
   info=0x7f0017d5f8 hash=0x9e8b9ade str=0x14cb5f4
   name="adgif-shader<-texture-with-update!" in_sym_range=1
```

## Root cause #2 named (A32 fix #2)

`adgif-shader<-texture-with-update!` is a `def-mips2c` form
(`goal_src/jak1/engine/gfx/texture/texture.gc:1993`). At link time of
texture.gc (part of ENGINE.CGO), the expansion of `(def-mips2c name
...)` fires `(__pc-get-mips2c "name")` and binds the returned fn ptr
to the symbol.

Android binds `__pc-get-mips2c` to `a11_pc_get_mips2c_impl`
(`game/kernel/common/klink.cpp:425`), which returns
`Mips2C::gLinkedFunctionTable.get(name)`. But the
gLinkedFunctionTable is EMPTY on Android, because
`game/mips2c/mips2c_table.cpp` (the static init that calls each
mips2c TU's `link()` function to populate the table) is EXCLUDED from
the Android build per `android/CMakeLists.txt:254-258` — only the
individual mips2c function TUs are compiled in, and their `link()`
functions are never called. So `__pc-get-mips2c` returns 0 for every
name, every def-mips2c symbol gets value=0, and the first BLR through
any of them lands at ee_base → sig=4 SIGILL.

linux-arm64 qemu hits the same fundamental gap (same empty table) and
fixed it in A29 by rebinding `__pc-get-mips2c` to a no-op-returning
impl `a29_mips2c_get_noop` that caches a single no-op GOAL function
ptr in the `__a29-mips2c-noop` symbol slot and returns its offset for
every name. See `linux_arm64_main.cpp:163-178`. Android wasn't doing
this rebind, so it crashed at the first def-mips2c call site.

## Fix #2 — mips2c-noop rebind (android/gk_android_main.cpp)

Added `a32_mips2c_get_noop` (mirror of `a29_mips2c_get_noop`, caches
a no-op into `__a32-mips2c-noop`) and chained a single line into the
pre-version-check hook, RIGHT AFTER `klink_a11_ensure_pc_mips2c_bound`
(which sets up the initial binding to `a11_pc_get_mips2c_impl`):

```cpp
jak1::make_function_symbol_from_c("__pc-get-mips2c",
                                  (void*)a32_mips2c_get_noop);
```

The rebind overwrites the symbol value with the new no-op-returning
trampoline. Every subsequent `(def-mips2c name ...)` call evaluates
`(__pc-get-mips2c "name")` → `a32_mips2c_get_noop` → cached no-op fn
GOAL ptr → bound to the symbol. The BLRs through every def-mips2c
symbol now hit a callable function. Texture/shader/particle dispatches
become no-op, matching the current Android renderer surface (no real
GS — `android/android_renderer.cpp` is the dark-blue clear loop only).

## On-device evidence

Routed logcat (saved verbatim to
`.autoport/reports/A32-routed-logcat-attempt2.log`, 2639 lines):

```
10:28:49.728  gk_sdl_main: entered
10:28:49.728  A11-DIAG sym-bind-trace: chained klink_a11_ensure_pc_mips2c_bound
              + A32 a32_mips2c_get_noop rebind of __pc-get-mips2c
              + klink_a12_ensure_sound_rpc_bound
              + klink_a14_ensure_pc_memmove_bound
              + a17_bind_pc_helpers (+ A32 __pc-texture-upload-now /
                __read-ee-timer / __send-gfx-dma-chain)
              + klink_a18_install_method_zero_trap onto
              g_jak1_pre_kernel_version_check_hook
              (prev=0x72f47ed6a0; A13 IOP-init NOT chained here)
10:28:50.364  goal_main: entered argc=9
10:28:50.560  A11-DIAG sym-bind-trace: bound __pc-get-mips2c to
              a11_pc_get_mips2c_impl (function GOAL ptr 0x4d1644)
...
10:28:51.286  link finish: speaker
10:28:51.288  link finish: fuelcell-naked
10:28:51.304  link finish: eichar
10:28:51.309  link finish: sidekick
...
10:28:51.383  link finish: ropebridge
10:28:51.385  link finish: ticky
10:28:51.386  link finish: hud-classes-pc           ← #354, last link finish
10:28:51.390  GK-DIAG sig=11 fault=0x7ffd596f80 pc=0x7f0150113c
              lr=0x7f01502794
```

Counting `link finish:` lines: **354** (A31 closed at **316**, A30
at **291**, so the absolute gain over the prior phase is **+38**).

Device screencap saved as
`.autoport/reports/A32-device-1-after-fix.png` (4.5 MB). It shows the
device's home screen — the app crashed and the launcher returned to
foreground, identical to the A31 screencap shape. The SDL window's
dark-blue clear came up briefly during the boot but the crash fires
within ~1.7 s of `goal_main: entered` so a foreground frame isn't
visible at the 30 s sample point.

## What this fix does NOT yet achieve

The title-screen render is NOT reached. The CGO link chain is unblocked
through 354 entries, but the kernel-dispatch loop (the body that runs
`(*kernel-dispatch*)` to drive the renderer's frame pump) is still
not entered — the SIGSEGV at `hud-classes-pc` aborts the boot before
the dispatch loop fires. So even though we are now past
`link finish: logo`, the renderer's swap chain doesn't yet have GOAL
content to draw.

The Android renderer's `android_renderer.cpp` is also still the
minimal dark-blue clear loop with no `Gfx::GetCurrentRenderer()`
binding, so the new `__pc-texture-upload-now` / `__send-gfx-dma-chain`
bindings being no-op is exactly as expected for the current renderer
surface. Wiring a real Adreno-GLES renderer with real
`texture_upload_now` / `send_chain` implementations is a separate,
much larger workstream — A33's task is to clear the next CGO-link
crash, not to swap these no-ops for real impls.

## Next blocker (A33 mandate)

A new crash class, fully decoded from the routed logcat tail:

```
GK-DIAG sig=11 fault=0x7ffd596f80 pc=0x7f0150113c lr=0x7f01502794
```

Registers at fault (selected):
```
x0  = 0x2d65727574786574       ← "texture-" as 8 ASCII bytes (LE)
x6  = 0xfd596f80                ← BOGUS GOAL ptr (≫ 0x08000000 EE max)
x7  = 0xfd596f80                ← reloaded from [SP, #0] at pc-12
x10 = 0x2d65727574786574       ← same "texture-" word as x0
x15 = 0x7f00000000              ← EE_BASE (correct)
x16 = 0x7ffd596f80              ← X6 + X15 (host-side address)
x29 = 0x7f07fff9a0              ← FP, inside EE memory
sp  = 0x7f07fff970
```

Decoded instruction prelude (PC-32 .. PC+0):
```
pc-32  0xaa0603e6   MOV  X6, X6                   ; coalesce
pc-28  0xf94003e7   LDR  X7, [SP, #0]             ; reload spill (← bogus)
pc-24  0x8b0600e7   ADD  X7, X7, X6
pc-20  0xf90003e7   STR  X7, [SP, #0]
pc-16  0xd2800082   MOVZ X2, #4
pc-12  0xf94003e7   LDR  X7, [SP, #0]             ; reload again
pc-8   0xaa0703e6   MOV  X6, X7
pc-4   0x8b0f00d0   ADD  X16, X6, X15             ; GOAL→host conv
pc+0   0xb9400206   LDR  W6, [X16, #0]            ; ← SEGV (X16 unmapped)
```

This is no longer "unbound symbol fn-ptr=0". X15 is correct, the BLR
prelude is correct, but the GOAL pointer being host-converted (0xfd596f80
in X6) is far beyond the 128 MB EE memory window — the LDR through the
resulting X16=0x7ffd596f80 faults because nothing is mapped at that
host address. The "texture-" ASCII bytes in X0/X10 strongly suggest
this is a string-handling code path: probably a `length` or `data`
accessor on a string whose pointer arithmetic is going wrong on arm64
specifically (a regalloc spill bug similar to the A23/A24/A28 family,
or a struct-field codegen mismatch). The `LDR X7, [SP, #0]` reading
back a bogus value at pc-28 + pc-12 means the value was SPILLED there
already incorrect — the bug is *upstream* of this PC, in whichever
function wrote the SP+0 slot.

A33 mandate:
1. Identify which GOAL function lives at PC=0x7f0150113c (decoding
   from the LR=0x7f01502794 caller's prologue at lr+1020 = a typical
   `STP X29, X30, [SP, #-16]!; MOV X29, SP; ...` pattern would name
   the parent function via its constant-pool string-literal load).
2. Trace where the bogus 0xfd596f80 spill was written — backward
   from `STR X?, [SP, #0]` to the LDR/ADD/... that produced it.
3. If it's a known-shape regalloc bug (clobbered live-across-call
   spill, etc.), the IGenARM64 / RegAllocBasic fix is one of the
   existing arm64 codegen fixes; otherwise this is a new codegen
   surface and a new fix.
4. Build, run on device, expect to advance past hud-classes-pc into
   the next CGO chain.

## Sanity checks (validator gates)

* **No forbidden edits**: `git diff` shows ONLY
  `android/gk_android_main.cpp`. `goalc/emitter/IGenX86_64.{cpp,h}`,
  `goal_src/`, `.autoport/lib/`, `.autoport/validators/`,
  `.autoport/supervisor.sh`, `.autoport/orchestrator.py` all
  untouched.
* **Anti-cheat**: no new `__attribute__((weak))`, no `abort()`, no
  `gk_recover_to_renderer`, no `_stubs.cpp`, no fake
  `link finish:` `printf`.
* **A30 routing preserved**: `gk_log_pipe` block in
  `android/gk_android_main.cpp` (lines 126-294) was not touched —
  the routed-logcat lines in the evidence section above are produced
  by the same pipe that A30 installed.
* **x86 desktop**: gate run by the validator. Codegen was not touched.
* **qemu baseline**: gate run by the validator. Codegen was not
  touched, so qemu's 660 link-finish count is unchanged.
* **Device screencap**: present, 4.5 MB, post-crash home screen.

## Files referenced

- Source change:
  `android/gk_android_main.cpp` (a17_bind_pc_helpers +3 lines,
  a32_mips2c_get_noop new helper, pre-version-check hook +1 rebind line,
  trace message updates)
- Routed logcat tail (full):
  `.autoport/reports/A32-routed-logcat-attempt2.log` (2639 lines,
  PID 9114 on device eae4df44)
- Device screencap:
  `.autoport/reports/A32-device-1-after-fix.png` (post-crash, 4.5 MB).
- Anchor for the +38 delta:
  `.autoport/reports/A31-attempt-2-progress.md` (closing-state at
  316 link-finishes).
- A29 cross-reference (the linux-arm64 backport gap that A32 closed):
  `game/linux-arm64/linux_arm64_main.cpp:163-178` (a29_mips2c_get_noop)
  and `:297-299` (the three pc-* bindings).
