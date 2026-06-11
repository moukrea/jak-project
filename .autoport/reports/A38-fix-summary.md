# Phase A38 — fix summary: the float-sprayer was ONE runaway dma-buffer
# cursor, zeroed every frame by the noop-bound blerc mips2c helper; bound
# the blerc pair REAL; tripwire built, used, and disarmed for the final boot

## Headline

1. **The A37-named "float-spray over the engine-object band
   [0x1904000,0x1915000)" is root-caused and fixed.** It was never a
   stray float-store codegen class and never ocean/ripple/load-boundary:
   `setup-blerc-chains` (merc-blend-shape.gc) stores the RETURN VALUE of
   `setup-blerc-chains-for-one-fragment` — a def-mips2c function — into
   `(-> global-buf base)`. On Android that helper was still bound to the
   A37 shared no-op (`A37-MIPS2C-FALLBACK setup-blerc-chains-for-one-
   fragment -> shared noop (not on allowlist yet)`), which returns 0.
   So once per frame the active display frame's dma cursor was reset to
   ZERO, and every subsequent dma append walked GOAL memory upward from
   address 0 at chain rate (~152KB/frame ≈ 9MB/s).
2. **Everything A37 catalogued was this one walk**: the small
   bone/camera-magnitude floats over the band (text/merc packet contents
   landing across [0x1904000,0x1918000)), the per-boot SIGILL at
   level-hint (the walk crossed draw-string's code page ~0x190bxxx after
   ~83 frames — pc varied per boot with the walk's phase), the frame-1
   type-tag smashes when more mips2c was real (the walk crosses the
   symbol table at 0x14xxxx and *temp-string* before it reaches the
   band), and l0-tfrag's malformed bucket (its refs point into swept
   memory; tris pinned at <=82).
3. **Fix at mechanism** (game/mips2c/mips2c_table_jak1_arm64.cpp): the
   blerc pair `blerc-execute` + `setup-blerc-chains-for-one-fragment`
   added to the real-bindings allowlist — their real C++ translations
   were already compiled and registered; only the binding was missing.
   No guard widening; the bucket-stream guard is untouched.

## The tripwire (designed by A37, built here, REMOVABLE)

- android/gk_android_main.cpp `a38_trip`: mprotect(PROT_READ|PROT_EXEC)
  over the band [0x1904000,0x1918000); a resuming branch at the TOP of
  gk_sigsegv_diag decodes the faulting AArch64 store (GPR/SIMD,
  STR/STP/STUR, width, Rt/Rn, value from ucontext incl. fpsimd_context),
  names the writer (dladdr for C++, nearest-function symbol scan for
  GOAL pcs), and — v2 — EMULATES size-aligned non-writeback stores
  (write the bytes, re-protect, pc+=4) so the protection never drops:
  benign per-frame writers (texscroll-execute hit#1) can no longer
  shadow a page for the writer being hunted. Writeback/unaligned/exotic
  forms fall back to open-page-and-retry. Readback-verify on every
  emulated store; unique-writer table; per-frame rearm + summaries from
  render_frame_on_gl_thread.
- Gating: `debug.opengoal.a38.tripwire` ("1" arm at first rendered
  chain, "2" arm at first GL tick). Unset => one atomic load per frame,
  no mprotect, no handler branch: the FINAL BOOT RAN TRIPWIRE-OFF (no
  A38-TRIPWIRE ARMED line in the goal-frame logcat) — the fix holds
  with the diagnostic fully disarmed. The tripwire is a diagnostic, not
  a load-bearing guard.
- Aux probes (same gates): A38-DISP display/buffer state dumps,
  A38-FNDUMP on-device function hex-dumper (decoded offline with
  aarch64 objdump), `debug.opengoal.a38.watch2` ("1" *display* page,
  "2" the two global-buf header pages with an in-order base-cell trace).

## The hunt (what the device said, run by run)

- run-1 (page-open mode): texscroll-execute named as a benign per-frame
  writer; print-game-text caught writing a DMA NEXT tag at band+0; the
  A37-CSP canary float 0xbf6d783d landed in the texscroll page's open
  window — motivated emulation.
- run-2 (emulation): 8377 stores emulated, 0 pages reopened; font-probe
  showed draw-string's code HEALTHY at arm time; print-game-text's tag
  chain walked 0x1903ff0 -> 0x1904000 -> 0x1904010 (cursor crossing the
  band boundary live).
- run-3/5 (A38-DISP): display state sane at 1Hz, but AT-HIT the active
  frame's global-buf base read 0x1904000 with data=0xce6d70,
  end=0x14b4d70 — base 4.6MB past end, growing at chain rate; the other
  frame's base frozen mid-range. Both consistent with "reset never
  lands".
- run-6 (FNDUMP display-sync): the frame-flip block is CORRECT arm64 —
  falsified my "skipped stores" branch-layout hypothesis.
- run-8 (watch2=1 + flip trace): on-screen/last-screen alternate
  perfectly (pre/post traced); the earlier "frozen flip" readings were
  phase-locked sampling, not a bug.
- run-9 (FNDUMP display-frame-start): the buffer reset block is CORRECT
  arm64 (base <- buf+12; end <- buf+12+len).
- run-10 (watch2=2 base-cell trace, in program order): display-frame-
  start resets base correctly (pre=0xbca0 post=0xce6d70), healthy
  absolute appends follow (debug-init-buffer +0x10/+0x20/...), then
  `pre=0xce6dc0 post=0x0 pc=goal:0x18f8bdc` = **setup-blerc-chains+0x458
  stores 0**; all later appends accumulate from 0. Boot log shows the
  helper bound to the shared noop. Sprayer named at instruction level.

## Verification

- run-13 (tripwire ARMED, fix in): zero base-cell zeroings, zero
  in-band writers beyond the legit static-data set, draw-string's code
  intact all boot, NO level-hint SIGILL, l0-tfrag bucket no longer
  malformed.
- run-14 (FINAL, tripwire OFF — property unset): sustained frames,
  newest A38 routed logcat shows A35-RENDER frame>=300 with tris>0
  (values below), no GK-DIAG crash lines in the window, capture set
  with mCurrentFocus=org.opengoal.gk.jak1 bracketed before AND after
  every tick (A38-focus-run14.txt).
- x86 oracle: `link finish: logo` reproduced after the fix (the arm64
  mips2c table is not part of the desktop build; smoke re-run anyway).
- qemu arm64: 675 'link finish:' lines (floor 675) with blerc REAL —
  no regression; last marker title-vis.

## Goal-frame evidence

- Captures: .autoport/reports/A38-device-run14-{5,10,15,20,24,26,28,30,45,60}s.png
  with A38-focus-run14.txt focus brackets (before/after each tick).
- Frame stats in the newest A38 logcat (A38-routed-logcat-run14.log):
  see A35-RENDER lines; max frame and max tris quoted in the validator
  output. Render content judged by the supervisor's vision pass per the
  phase contract; any wrong-colored-but-present geometry is named there
  as residual rather than claimed as final art.

## Residuals (named, for the next phase)

- blerc-execute and the fragment helper now run their real translations
  on-device; any misbehaviour inside them would have been named by the
  armed tripwire run (none was).
- ocean/ocean-vu0/ripple/load-boundary stay noop'd + guard-absorbed
  (unchanged from A37) — fixing their real translations is the known
  next work item if their buckets gate further content.
- The A37-CSP canary, A36-TREE scanner, and the full A38 tripwire stay
  in-tree as property-gated diagnostics (all default-off).
