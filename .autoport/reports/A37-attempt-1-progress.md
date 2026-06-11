# Phase A37 — attempt 1 progress: the camera blocker is DEAD (root cause was
# NOT goalc codegen — the entire jak1 mips2c surface was bound to a no-op on
# Android); *math-camera* camera-rot/trans/camera-temp now BIT-IDENTICAL to
# the x86 oracle on-device; SEVEN mechanisms fixed; goal frame still pending
# behind one freshly-named blocker (float-spray over the engine-object band
# once the deep draw paths engage)

## Headline

1. **A36's named blocker ("update-math-camera arm64 codegen divergence")
   is falsified and closed — and it was never codegen.** The A36 mem-op
   differ's "dropped +0x18C logtest" was an addressing-mode artifact
   (8-byte LDR at a non-8-scaled offset folds into `add x16,x16,#0x18c`;
   the improved differ in /tmp/a37/memop_diff2.py compensates and shows
   math-camera, cam-update, matrix, trigonometry, vector, transform,
   quaternion, cam-* ALL mem-op-identical to the oracle).
2. **The real producer chain**: update-math-camera never writes
   camera-temp. update-camera (cam-update.gc) computes it per frame as
   `camera-temp = camera-rot × perspective`; on the title screen both
   fov and inv-camera-rot come through the look-through-other path
   (`*camera-other-fov*/-matrix*/-trans*`), written by the `othercam`
   process from the title camera-anim actor's JOINT BONE TRANSFORM.
3. **Root cause**: game/mips2c/mips2c_table.cpp is excluded from the
   arm64 builds and both runtime-compat stubs made
   `LinkedFunctionTable::get()` return 0; A32 then rebound
   `__pc-get-mips2c` to a shared no-op. Every jak1 `def-mips2c` —
   including `calc-animation-from-spr` and
   `cspace<-parented-transformq-joint!`, the bone-transform producers —
   silently did nothing on Android. Joints stayed zero, othercam copied
   zeros, update-camera multiplied zeros: black frames with 64k tris.
4. **Field-level proof of the fix** (A37-CAM probe, device run 10+):
   - oracle  f=60: camrot3=(-543372.94 -194381.13 896867.75 1.0)
   - device  f=60: camrot3=(-543372.94 -194381.13 896867.75 1.0)  ← exact
   - invrot0/trans equally bit-identical; camera-temp rows fully
     populated (ct3 = camrot3·persp exactly — matrix*! exonerated).

## Mechanisms fixed (each named by forensics)

1. game/mips2c/mips2c_table_jak1_arm64.cpp (NEW, both arm64 builds):
   real LinkedFunctionTable::reg()/get() + the desktop jak1 callback map
   verbatim; reg() emits an AArch64 GOAL-heap trampoline
   (ldr x16/x12/x17 literals + br) — x86 wrote x86-64 bytes.
2. _mips2c_call_arm64 (asm_funcs_arm64.s) rewritten: register contract
   (x16=body, x12=stack size), ctx arg slots filled from the GOAL
   x86-id arg registers X7,X6,X2,X1,X8,X9,X10,X11 (A6 FFI parity), pp/st
   from live x13/x14, GOAL-relative ctx sp from x15, v0→x0 return, and
   x13/x14/x15 saved across the C++ body (AAPCS temporaries, unlike
   SysV R13-15). The old never-executed version read operands from
   wrong stack slots, branched to the stack-size register and swapped
   q-restores.
3. arm64 bug class #9: `ldp x12, x12` (equal destination registers) is
   CONSTRAINED UNPREDICTABLE — SIGILL on Snapdragon, silently accepted
   by qemu-user. The old helper had `ldp x8, x8` latent; run-4 hit it
   live at the first real mips2c return (pc=lr=blr+4 in the fp-walk).
4. Trampoline arena: reg() runs mid-DGO-link, and mid-link global-heap
   allocations get reused by later heap traffic on this loader path
   (run-9: the noop trampoline emitted at font-link was overwritten by
   per-frame DMA bucket tags; BLR into it SIGILLed). The arena (+ the
   shared noop) is now allocated once at the proven-stable early point
   (klink_a11_ensure_pc_mips2c_bound, pre-version-check).
5. android_gfx condvar UB: sync_cv was waited under dma_mutex
   (sync_path) but notified under sync_mutex (post_swap_tick/vsync) —
   one cv with two mutexes loses wakeups; the GOAL thread parked
   forever in sync_path the moment frames got heavier. One mutex now.
6. Bucket-stream guard (android_opengl_renderer.cpp): pre-walk each
   bucket with a step cap; malformed buckets (streams that never land
   on next_bucket — run-27 showed sky/tex/l0-tfrag wandering to
   offset 0 from noop-fed chain links) are named, counted, skipped and
   the follower re-seats on the boundary. Plus a whole-chain validator
   in render_frame_on_gl_thread. The GL thread can no longer be trapped
   by a bad chain (runs 23-26: infinite DmaFollower walk inside
   SkyRenderer once the real camera let the GOAL sky path go deep).
7. Hang forensics now permanent: frame-stall watchdog →
   SIGUSR2 ucontext dump (pc/lr/regs + dladdr) + fp-walk with per-frame
   symbolization on BOTH GOAL and GL threads; PCWIN/LRWIN instruction
   windows and a symbol-table reverse scan (A37-WHOSYM) in the fault
   handler; A37-CAM full camera-chain probe (device) mirrored by an
   OG_A37_CAM=1 probe in sceGraphicsInterface.cpp (oracle values).

## Graded mips2c enablement (current device set)

all registered jak1 bodies REAL except the four water/boundary groups
(ocean, ocean-vu0, ripple, load-boundary — excluded) and the per-name
log (A37-MIPS2C-REAL / -FALLBACK) makes the split visible per boot.
Bisect history: empty set = clean boot, frame 3480 (run 14);
+cspace = font-region stomp (15/16); pair+sky+bones still hung in the
sky bucket pre-guard (19-25); all-real = frame-1 type-tag corruption
(17/28..31); base+background-half isolated the corrupter into
ocean/ripple/load-boundary (32/33). Those four groups corrupt when real
AND poison chain links when noop'd — the guard absorbs the noop side.

## Device evidence (run 35 = record run; runs 1-35 logged)

- A37-routed-logcat-run35.log: frame=329 (gate ≥300 ✓), tris up to 82,
  aborts=0; per-boot residual: SIGILL at the level-hint → font path
  (below). Focus files record mCurrentFocus=org.opengoal.gk.jak1 before
  AND after every capture tick; captures at 5/10/15/20/24/26/28/30/45/60s.
- GAMEPLAY: enter title reached every boot with the REAL camera
  (logo-intro STR + VAG flow intact; A36-TREE viol-total=0).
- x86 smoke: `link finish: logo` ✓ (diag blocks in joint.cpp are
  #ifdef __aarch64__ — the oracle path is byte-identical).
- qemu: 675 link finishes (floor 675) with the REAL mips2c table live.

## NEXT BLOCKER (named): float-spray over the engine-object band

With the deep draw paths engaged, something sprays small float values
(bone/camera-magnitude, e.g. 0xbf4bc014 = -0.795) across
[~0x1904000..0x1915000) — engine object code/data (font lives there).
Effects: (a) per-boot SIGILL when level-hint's text call BLRs into
font's first function (target = font+6, caller text@0x1dcd4cc, slot
0x159344 — A37-WHOSYM names it every time); (b) ~20 buckets/frame
flagged malformed by the guard (incl. l0-tfrag, the village geometry —
why tris stays ≤82 and the goal frame is still pending); (c) when the
water/boundary bodies are real, the same class smashes type tags by
frame 1 (*temp-string* + text.o strings — the "~D~S.TXT unknown dest"
abort). The A37-CSP canary brackets the writes to the per-frame window;
attribution between the cspace body's own stores (proven bounded to
healthy bone arrays by the arg log: zero SUSPICIOUS hits) and a
concurrent thread is the first task of A38 — the watchpoint-grade tool
(re-arm canary + per-bucket diff, or PROT_READ mprotect tripwire on the
band) is the designed next step. Fix lights up l0-tfrag and the village
title scene; the camera is already waiting with oracle-exact values.

## Honest screencap statement

No real-content frame is claimed. The captures show the letterboxed
output black/transition with the touch overlay; boots cycle (link ~25s,
title ~2-6s with draws=3-4/tris≤82, then the font-stomp SIGILL and the
guard relaunch). The camera fix is proven at the field level (probe),
not yet on glass — the render gate is the newly-named spray, strictly
downstream of this phase's named objective.
