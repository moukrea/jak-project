# Phase A40 — the frame-~522 boot ceiling is DEAD: the "hint-cursor walk"
# was a missing GOAL-ABI guarantee (callee-saved xmm8-15 → v24-v31 never
# preserved on arm64); print-game-text's line-Y advance lived in s24 across
# the draw-string call, came back clobbered, and the blank-line padding
# loop swept 12 MB of GOAL memory in one call. Fixed callee-side in the
# arm64 prologue/epilogue. Boot now sustains 3720+ frames at 60 fps with
# tris=63,612 (vs the eternal 82) and zero faults.

## What A39's instruction-level naming got right — and wrong

A39 named the residual SIGILL "an unreset display-frame dma cursor that
print-game-text walks 64 B/frame". This phase re-derived the mechanism
from scratch and falsified the framing in three steps, each with live
data (all logs referenced are committed or in /tmp on the build host):

1. The flip is NOT frozen. The arm64 codegen of display-sync's flip
   block (drawable.gc:1238-43) is byte-correct in the shipped CGOs
   (`str w9,[x16,#560]` / `str w11,[x16,#556]` at drawable.o seg
   0x7354/0x735c, disasm-verified from out/jak1-arm64/iso/GAME.CGO),
   and the A38 watch2=1 flip-cell trace on the CURRENT build (boot3,
   /tmp/a40-dproc-boot3.log) shows on-screen alternating 0↔1 every
   frame with coherent pre/post chains and only the two display-sync
   writer pcs. The "on-screen stuck at 0 / buf1 frozen at 0xcf2d40"
   readings in A38/A39 were PHASE-LOCKED 1 Hz sampling artifacts (the
   GL-thread probe fires at a fixed phase of the vsync handshake) —
   the third time this trap has bitten this project.
2. display-loop is NOT dead. The A40-DPROC probe (new, committed,
   default-off: debug.opengoal.a40.dproc) + new vsync/sync-path/send
   counters in android_gfx.cpp prove sends flow at 60/s for the whole
   boot (sends=522 at the old death; the old "zero sends" reading came
   from send_chain only logging call #1 and every 600th — boots died
   at ~520 calls, one print).
3. The "64 B/frame walk over 493 frames" arithmetic was numerology.
   The corruption is ONE catastrophic print-game-text invocation late
   in boot (first non-large-font text draw with a box, at the
   logo/hint moment): the mid-sweep dump (A40-SWEEP, boot7) shows the
   blank-line padding loop appending a 16-byte NEXT packet per
   iteration with origin.y FROZEN at 24.0 while sv-164 (the per-line
   advance) reads a sane 22.0 in the *final, innocent* frame — the
   sweeping invocation's advance was garbage. ~800k iterations sweep
   from the healthy global-buf base across buf1's header (the
   pre=0xcfe150 post=0x0 stomp A39 saw), the l0 level heap (the
   tris<=82 pin), and the 0x1904000+ band, native-speed, inside
   ~100 ms; the moment the cursor crosses draw-string's own code
   (0x190bb34), the next loop iteration calls draw-string and executes
   the freshly-written DMA tags: sig=4, lr=print-game-text+0xed8,
   every boot, "frame ~522".

## The root cause (named at ABI level)

GOAL's ABI treats xmm8-15 as callee-saved: thread-suspend banks exactly
that set, and do_goal_function_x86 backs up any used saved-xmm in the
prologue. The arm64 backend maps xmm8-15 → v24-v31 — which AAPCS makes
CALLER-saved — and preserved them NOWHERE:

- goalc-arm64 prologues never saved them (do_goal_function_arm64 had no
  used_saved_regs handling at all; A19 had replaced GPR prologue saves
  with the per-call stp bracket and the xmm half was simply dropped);
- the A19 call bracket only banks {x3,x5,x10,x11,x12,x23}.

So ANY value the register allocator parked in xmm8-15 across a call
came back clobbered whenever the callee touched v24-v31. The
boot-killing instance, read directly out of the text.o disasm: the
`(let ((f30-2 (+ origin-y sv-164)))` result lives in s24 across the
draw-string/set-font-color-alpha/dma-bucket-insert-tag calls
(text.gc:377-405; fadd at print-game-text seg 0x28fc, the origin.y
writeback `str s24,[x16,#16]` at 0x2f3c with NO q-save anywhere) —
draw-string's glyph math leaves its own s24 behind (for the observed
boots, exactly 24.0 = the y it read), so origin.y never advances and
the `(while (... (>= sv-156 origin-y)))` line loop never terminates.

## The fix (mechanism, x86-mirroring, two attempts)

1. First attempt — extend the call_r64 bracket with stp/ldp q24-q31:
   CORRECT but too expensive. +32 B per call site overflowed the GOAL
   global heap during linking (qemu died at 654 link finishes, assert
   'offset', "1883 bytes before stack"), and +128 B of stack per call
   depth blew small process suspend backups: thread-suspend's
   stack-used check `(break)` (gkernel.gc:606, the udf #0xbeef at
   gkernel+0x2448) fired at title-vis on device. Reverted (the
   IGenARM64.cpp comment documents why).
2. Final fix — callee-side, exactly like x86:
   - goalc/compiler/CodeGenerator.cpp do_goal_function_arm64: the
     prologue now banks every used saved-xmm with `str qN,[sp,#-16]!`
     (0x3C9F0FE0|rt, NDK-clang-verified) after the FP/LR push, and the
     epilogue restores them in reverse with `ldr qN,[sp],#16`
     (0x3CC107E0|rt) before the FP/LR pop. Classification is by the
     x86-model id range (XMM0..XMM15 = ids 16..31 → v16..v31) because
     Register::is_xmm(ARM64) is hardwired false.
   - game/kernel/common/memory_layout.h: GLOBAL_HEAP_END +8 MB (the
     [old-end, DEBUG_HEAP_START) gap is unused PC-port margin; GOAL
     never reads the constant; x86 CGOs stay byte-identical). Kept as
     headroom even though the callee-side fix's code growth is small.
   - 13 q-saves in all of text.o (vs 45 bracket pairs in attempt 1):
     only users pay, once per invocation.

## Verification

- x86 oracle: `link finish: logo` smoke PASSES (3 runs across the fix
  cycle); out/jak1/iso x86 CGOs hash-identical to the pre-phase
  snapshot after every arm64 regen (B1-style obj-cache wipe + x86
  goalc rebuild each time).
- qemu: 675 'link finish:' lines, exit 0 (floor 675; attempt 1's 654 +
  SIGABRT fully recovered).
- All 28 arm64 CGO/DGOs regenerated with the fixed goalc-arm64, synced
  to out/jak1-arm64/iso AND android/app/src/jak1/assets/iso_data/jak1
  (stale-asset rule), and re-seeded onto the device.
- Device (Redmi Note 9 Pro, eae4df44, org.opengoal.gk.jak1):
  - .autoport/reports/A40-routed-logcat-run1.log: frame=3720 (62 s,
    60 fps sustained — the old ceiling was ~522), tris=63612,
    draws=104, buckets_drawn=18, chain ~146 KB/frame, ZERO GK-DIAG
    sig= lines, zero SIGSEGV/SIGILL, 435 link finishes.
  - Captures A40-device-run1-{5,10,15,20,24,28,32,45,60}s.png with
    mCurrentFocus bracketed BEFORE and AFTER every tick
    (A40-focus-run1.txt): all 18 checks = org.opengoal.gk.jak1/
    MainActivity — no interloper pollution (xiaoji/ghplus/sshxmobile×2
    disabled for the run, re-enabled after, per protocol).

## Honest content verdict

The boot ceiling is gone and the renderer is drawing real geometry
(63,612 tris, 104 draws — the l0-tfrag pin died with the sweep), but
the visible frame is not yet the village flythrough: the screen shows
an ANIMATED row of glyph-sized grey quads center-screen (text drawn
without its font texture — pattern changes between the 15 s and 45 s
ticks) over a black 3D viewport, under the E2 touch overlay. tris is
static at 63,612 across seconds, i.e. a stable scene (title-screen
class), with the world geometry submitted but not visibly lit/
textured. The next blocker for the goal frame is the texture/upload
path for these buckets (the A35 skip-list still skips 15 bucket
classes; "draws=104" proves the dma→GLES path consumes them). The
supervisor's independent vision capture should judge the 15 s/45 s
frames; run1's PNGs are honest evidence of the current state.

## Diagnostics added this phase (all default-off, committed)

- debug.opengoal.a40.dproc: 1 Hz + at-crash dump of *run*/*dproc*/
  master-mode/prevent-from-run, the display process record (status/
  threads, v2 offsets with the boxed-basic -4 rule), both display
  frames' global-buf {field,base,end}, display-pool/active-pool walks,
  and the new android_gfx vsync/sync-path/send counters
  (gk_a40_shim_counters).
- debug.opengoal.a40.sweepdump: band-fault-time dump of
  print-game-text's live loop floats (sv-164/sv-156/sv-136, gp-0
  origin.y, font-context height) — the instrument that caught
  origin.y frozen mid-sweep.
- A40-SPWIN: crash-handler stack window (0x3c0 bytes, hex+float).
- Build: `./gradlew assembleJak1Debug -PslimIso=true` builds a ~77 MB
  APK without the 1.4 GB iso payload (assets-slim/ keeps fr3); seed
  device data once via adb push + run-as cp + the .extracted_v1
  sentinel. Iterating on libgk.so no longer needs 2.7 GB of device
  headroom (the phase burned hours on INSTALL_FAILED_INSUFFICIENT_
  STORAGE before this; storage threshold settings were temporarily
  lowered and have been restored).

## Falsifications recorded for the next phase

- "display-loop dead / suspend broken / dispatcher skip": all wrong —
  status='running samples were phase-locked, sends prove iteration.
- "klink adrp/ldr mispatch of the 14.0 constant": wrong — the +0x720
  apparent bias was my own wrong segment base (print-game-text is in
  text.o at base 0x1dca720, not font.o's 0x1909c60); the patched pair
  resolves to exactly the constant pool.
- A38-BASECELL "writers at 0x1904xxx" are legitimate band-RESIDENT
  engine functions (the band contains code: draw-string itself lives
  at 0x190bb34) — the band is not a pure data region.
