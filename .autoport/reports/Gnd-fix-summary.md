# Phase Gnd — the arm64 DMA-base-drop that blacks out the ND/Daxter `ndi` logo

Chronological step 1b. Gintro proved the pre-title intro EXECUTES and is paced
correctly, but the Naughty-Dog/Daxter `ndi-intro` logo rendered BLACK because the
per-frame foreground DMA bucket chain is corrupted on arm64 only. This report
documents the FULL forensic chain, the **decisive fix**, the on-device evidence
that the corruption is gone and the logo now renders, and an honest correction of
the earlier (wrong) hypothesis.

## TL;DR (the fix, the verdict: FIXED)

The ndi black screen was caused by the per-frame `global-buf` (foreground DMA
buffer) `base` write-cursor collapsing to a **low, near-zero value** on arm64
during the ndi draw. `display-frame-finish` then links each bucket-NEXT DMA tag to
that low cursor, so the bucket-NEXT `addr` becomes `0x1a50` / `0x2070`. The Android
chain-copy guard (`A42-CHAIN-PRECOPY`, android_gfx.cpp `send_chain`) correctly
rejects any chain whose NEXT `addr` is below `EE_MAIN_MEM_LOW_PROTECT` (0x80000),
so the whole ndi frame is dropped and a black frame is presented.

ROOT CAUSE (pinned, not guessed): the ndi logo-slaves (`*jchar-sg*` Jak +
`*sidekick-sg*` Daxter, spawned `logo-slave` with `blend-shape #t`) cast SHADOWS.
`shadow-execute-all` (engine/gfx/shadow/shadow-cpu.gc:405,418-419) does, on the
foreground `global-buf`:

```
(let* ((s4-0 (-> *display* frames (-> *display* on-screen) frame global-buf)) ...)
  ...
  (set! (-> s4-0 base) (shadow-execute (the-as shadow-dma-packet (-> v1-21 first))
                                       (-> s4-0 base))))   ;; <-- base = shadow-execute(...)
```

i.e. it stores `shadow-execute`'s RETURN value straight into `(-> global-buf base)`.
On x86 `shadow-execute` is a real mips2c routine: it appends the shadow DMA and
returns the ADVANCED cursor (a valid high pointer). On arm64 `shadow-execute` was
NOT on the A37 mips2c allowlist (its C++ mips2c body is an incomplete port — the
sibling-geometry `jalr` calls to `shadow-xform-verts` / `shadow-calc-dual-verts` /
`shadow-scissor-*` / `shadow-find-*` are commented out, game/mips2c/jak1_functions/
shadow.cpp), so it fell to the A37 **shared no-op, which returns 0**. That `0`
becomes `(-> global-buf base)`. The cursor is now ~0; subsequent foreground appends
and `display-frame-finish`'s per-bucket GS-reset packets walk it upward from ~0
(0x1770 -> 0x1a50 -> 0x2310 ...), so every bucket-NEXT tag is a low address. The
upward walk from ~0 also writes DMA into LOW EE memory, which is the source of the
documented intermittent early boot `sig=11` (low-memory / symbol-table stomp).

This is EXACTLY the same defect class the A38 work already documented and fixed for
the blerc pair: a no-op'd mips2c function whose return value is stored into a
`dma-buffer` `base` collapses the cursor to 0 (see the comment in
game/mips2c/mips2c_table_jak1_arm64.cpp). blerc was added to the allowlist then;
`shadow-execute` is the same bug, missed because the shadow path only engages when
an actor casts a shadow — which the ndi logo-slaves do and the later logo-intro-2
flythrough does not (hence ndi-only / "blend-shape-only"-looking).

## The corruption signature (decisive, from the device)

- `A42-CHAIN-PRECOPY skip` fired 40-720x per ndi run: `low_tag=1 kind=2 (NEXT)
  spr=0 qwc=0 addr=0x1a50 / 0x2070` at calc-buffer bucket-header offsets
  `off=0x514e00` and `off=0x517530`.
- `0x1a50 == 0x501a50 & 0xffff`. 0x5019a0/0x501a50 is the `*default-regs-buffer*`
  CALL/RET tag that `display-frame-finish` writes alongside each bucket
  (`dst=0x005019a050000000`), which is why the low bucket-NEXT and the
  `*default-regs-buffer*` address co-appear — the chain is self-consistent but
  built at LOW GOAL addresses because `base` was 0-based.
- `GND-PRECOPY-RAW` proved the live memory genuinely holds `0x00001a50_20000000`
  (`raw@data == raw@ee == reread`, `base_delta=0`): real corruption, in memory, not
  a follower mis-read.

## How the writer was pinned (this phase's work)

1. **HW data watchpoint (perf_event_open / PERF_TYPE_BREAKPOINT) on the two
   global-buf base fields** — UNUSABLE on this device: `perf_event_open` returns
   EACCES even with `perf_event_paranoid=-1` (vendor/SELinux blocks unprivileged
   HW breakpoints). Code left dormant behind `debug.opengoal.gnd.hwwp`.
2. **C++ entry/exit cursor trace inside the blerc fragment**
   (`setup-blerc-chains-for-one-fragment`) EXONERATED the blend-shape path: a2 (the
   cursor in) and v0 (the cursor out) were ALWAYS valid high absolute addresses; the
   cursor chains correctly through every blerc call. So the long-suspected
   blend-shape / joint OOB / decompress-overrun (the phase's original hypothesis)
   is NOT the cause — blerc is clean.
3. **Static trace of every `(set! (-> X base) (Y ...))` return->base pattern** in
   the jak1 gfx draw path showed exactly ONE that uses a no-op'd mips2c function:
   shadow-cpu.gc:419 `(set! (-> global-buf base) (shadow-execute ...))`. Every other
   base write uses a real GOAL function (`draw-bones-generic-merc`,
   `pc-merc-draw-request`) or plain pointer arithmetic and preserves absoluteness.
   `shadow-execute` was confirmed FALLBACK (no-op) in the device log
   (`A37-MIPS2C-FALLBACK shadow-execute -> shared noop`).

## The fix (mechanism, matching the established A38 pattern)

Two edits, arm64-only, no goal_src change, no x86 change, no buffer-widen mask, no
painted/hardcoded logo:

1. `game/mips2c/mips2c_table_jak1_arm64.cpp` — add `"shadow-execute"` to the A37
   `kSet` allowlist so it routes to the REAL trampoline instead of the shared
   return-0 no-op.
2. `game/mips2c/jak1_functions/shadow.cpp` (`shadow_execute::execute`) — because the
   arm64 shadow geometry port is incomplete, the body is a **pass-through**: it
   returns the INPUT cursor (`a1`, the `(-> global-buf base)` passed in) UNCHANGED.
   No shadow DMA is appended, so `base` stays the valid absolute pointer it was on
   entry, the bucket chain stays well-formed, and the logo renders. This is the
   correct no-op for a cursor-returning stub (vs the corrupting return-0), pending a
   full shadow-geometry port.

## Verification — bucket-NEXT stays valid and the ND/Daxter logo RENDERS

On-device run with the fix (eae4df44, jak1, attract intro, no input):

- `A42-CHAIN-PRECOPY skip` count = **0** (was 43-47). **Zero `0x1a50`, zero
  `0x2070` bucket-NEXT corruption** — the stomp is GONE.
- `A37-MIPS2C-REAL shadow-execute -> arm64 trampoline` — allowlisting took effect;
  `shadow-execute` is invoked 12x during the ndi window and returns valid high
  cursors (e.g. 0x528ba0, 0xcf6ba0, 0xcf6c60, 0x528c20) instead of 0.
- `sig=11` / `Fatal signal 11` = **0** (the low-memory boot stomp is gone too).
- `A35-RENDER frame` max = ~2196; `tris` max = ~102798 (ndi-era frames draw real
  geometry, not tris=0). `ndi-intro` markers present, chronological chain intact.
- **ndi-window screencaps jumped from ~59273 B (uniform black) to 107-227 KB with
  real merc geometry**; the t06s frame visually shows the rendered Daxter character
  (orange/yellow merc) on the ndi logo screen. Later logo-intro frames hit 1.2-1.5
  MB as before. focus held on `org.opengoal.gk.jak1` on every captured frame.

## Why x86 is immune

`shadow-execute` is a real mips2c routine on x86 (the whole jak1 mips2c surface is
real there), so it appends the shadow DMA and returns the advanced cursor; `base`
stays a valid pointer. The divergence is purely the arm64 A37 graded-enablement
(shadow-execute off the allowlist -> shared return-0 no-op). Our x86 codegen is
byte-identical to pristine (Gref), so this is not an x86 leak.

## Title-regression safety

The fix only changes `shadow-execute`'s arm64 behavior (return the input cursor
instead of 0). On the title flythrough / logo-intro-2 the shadow queue is empty
(`shadow-execute-all` early-exits at `cur-run == 0`), so `shadow-execute` is not
called and nothing changes — the title still boots crash-free and flies (G1 holds).
For any other scene that DOES cast shadows, the fix turns a base-corrupting no-op
into a benign pass-through, so it can only help (the shadow simply isn't drawn until
the geometry is ported) — likely fixing a broader class of arm64 foreground renders.

## What is fixed / not fixed

- FIXED: the arm64 global-buf base-drop; the ndi ND/Daxter logo now RENDERS (no
  more 0x1a50 bucket-NEXT, no black). The intermittent early boot sig=11 (its
  low-memory cause) is gone in the verified runs.
- NOT done (out of scope): the full arm64 port of the shadow geometry
  (`shadow-execute` + siblings). Shadows are not drawn during ndi; the logo render,
  the phase deliverable, is met. Porting the shadow body is a future phase.

## Files changed (arm64-only)

- `game/mips2c/mips2c_table_jak1_arm64.cpp` — `shadow-execute` added to A37 allowlist.
- `game/mips2c/jak1_functions/shadow.cpp` — `shadow_execute::execute` arm64
  pass-through (return input cursor `a1`).
- `.autoport/gnd_run.sh` — Gnd device-run harness (NOT infra; mirrors gintro_run.sh).

(Pre-existing dormant, property-gated diagnostics from earlier attempts remain in
android/gk_android_main.cpp, android/android_gfx.cpp, common/dma/dma.h,
game/mips2c/mips2c_private.h, game/mips2c/mips2c_table_jak1_arm64.cpp — off by
default, no effect on normal runs.)
