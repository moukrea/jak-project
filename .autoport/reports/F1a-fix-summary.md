# Phase F1a — MERC RENDERS ON-DEVICE. Four mechanisms fixed (incl. arm64
# emitter bug class #12 and an Adreno driver fault defused at its exact
# trigger); the "camera tilt" framing FALSIFIED by a field-by-field oracle
# (matrices bit-identical; the pose is the course's legitimate parked
# shot); the remaining camera defect is excavated to one named link:
# the title-course joint pose freezes at the logo-loop respawn while its
# channels demonstrably play — next phase opens inside the GOAL joint
# decompress chain with all instruments already in place.

## Fix 1 — arm64 emitter bug class #12: swizzle_vf/shuffle_vf stand-ins
- IGenARM64's `swizzle_vf` emitted dup-lane (broadcast of ctrl&3);
  `shuffle_vf` ignored its pattern (plain mov). x86 truth: VSHUFPS
  dst,src,src,imm — a full 4-lane swizzle.
- IR_SwizzleVF lowers `.outer.product.a/b.vf` — 98 sites in jak1
  (vector-cross!, vector-flatten!, vector-reflect!*, the
  forward-up/down->inv-matrix camera/collision basis builders,
  cam-combiner orthonormalization) and bones.gc's `.cross.vf` (merc bone
  NORMAL matrices). Every cross product on Android computed (c,c,c,c), c
  = the true X component only.
- Fix: exact semantics via the free V0 scratch (ORR V0<-src, 4x INS
  Vd.S[t]<-V0.S[sel]), identity/broadcast fast paths; 9 encodings
  NDK-assembler-verified; composition check reproduces the Asm.cpp
  worked example cross(V1,V2)=(-4,8,-4) bit-exactly.
- All 28 CGO/DGOs regenerated (arm64) and reseeded everywhere; x86 CGOs
  byte-identical to the A2 baseline (sha256); qemu 675 'link finish:'
  lines (floor 675); x86 smoke `link finish: logo` PASS on every rebuild.

## Fix 2 — merc/generic/sprite ported (the phase's port mandate)
- Merc2 + Merc2BucketRenderer + Generic2 (4 TUs) + Generic2BucketRenderer
  + Sprite3/Sprite3_Distort/Sprite3_Glow/GlowRenderer compiled into
  libgk.so (52 Merc2 / 60 Generic2 / 52 Sprite3 symbols; validator gate
  Merc2>=5).
- 8 Merc2 buckets + 10 Generic2 buckets + SPRITE wired = the desktop jak1
  table shape (shared cores; EyeRenderer already live). Remaining skips:
  ocean x2, tie x2, shrub x2, shadow, depth-cue (named, one-shot logged).
- GLES fixed-index primitive-restart gates (TFragment's pattern) at 6
  sites across Merc2/Generic2_OpenGL/Sprite3/Sprite3_Distort/GlowRenderer.

## Fix 3 — the on-device crash ladder under the merc port (3 mechanisms)
1. glad gates glVertexAttribDivisor behind GL_VERSION_3_3, above the
   parsed "ES 3.2"; it is ES 3.0 core and the driver exports it. The
   sprite distort instancing BLR'd to 0 (run-2, GK-DIAG pc=0 in
   Sprite3::opengl_setup_distort+0x52c, GOT slot named). Resolved in the
   A36 fixup block; a programmatic audit proved it the ONLY >=3.3-gated
   symbol in the new TUs' call surface.
2. Merc2 reconstructed the EE base as `setup.data - setup.data_offset` —
   zero-copy-only math; under A42 chain-copy the bone matrices / mod
   effect data (referenced by GOAL address; bones runs after merc DMA)
   live outside the copy buffer (run-3 SIGSEGV handle_pc_model+0x378).
   Fix: `render_state->ee_main_memory` (the identical pointer under
   desktop zero-copy — x86 smoke PASS), same for model_mod_draws.
3. The Adreno fault: deterministic SIGSEGV inside libGLESv2_adreno
   (null+0x28, same pc every run) on one specific village merc
   glDrawElements (idx=117+64945, tex 0x225), no GL error (KHR_debug
   armed), fp-walk dead-ends in the blob. Eliminated in order: index
   range (in-bounds), GPU-vs-CPU content (glMapBufferRange memcmp ==,
   six draws + the killer draw itself), program/driver/draw shape (boot
   self-test draw survives), UBO overhang (clamped; killer has
   first_bone=0), title data (5 logo draws verified AND executed live).
   PROOF OF MECHANISM: with a read-only map+unmap immediately before it,
   the killer draw EXECUTED on exactly the frames the probe covered
   (run-16, 6-frame cap) and faulted on the first uncovered frame; a
   load-time-only sync decayed (run-17). The driver mishandles the
   chunk-uploaded BO at draw time unless a map forces finalization.
   FIX: one read-only glMapBufferRange(16B)+unmap of the index BO per
   level-bucket flush (Android-gated, Merc2::flush_draw_buckets) — n<=2
   per frame, no behavioral change.
- RESULT (runs 18/19): past the eternal frame-323 wall — ZERO faults,
  draws=143, tris=22340 per frame at the village scene (vs draws=3/
  tris=82 before the merc port came alive). Run-18's app was killed at
  11 s by the PREVIOUS run's trailing force-stop (script overlap, not a
  defect); run-19 is the clean full-length pass: 150 s, max-frame=8820
  (~60 fps), max-tris=28547, zero sig= lines, 13/13 focus brackets on
  org.opengoal.gk.jak1.

## The camera — the mandate's framing vs what the oracle proved
- A36-TFRAG-CAM matched-moment diff (x86 vs device, first village1
  tfrag-init): rotation/trans/hvdf/fog/cam3.yzw BIT-IDENTICAL; the sole
  delta is the X projection scale 0.419 vs 0.251 = exactly 5/3 =
  (2400/1080)/(640/480) — the PC port's intended aspect-adaptive FOV.
  Nothing in the matrix rolls the world: the reported "+85 deg tilt" is
  the camera legitimately pitched up at the course's PARKED pose, which
  desktop holds at the same coordinates until f~600 (A37-CAM periodic
  series, both backends).
- Android's defect: the course pose follows the early path then FREEZES
  at (-543372.9, 189225.1, 874363.8) from the logo-loop respawn (~f1800)
  while on desktop it flies from f=1200.
- Excavated chain (150 s instrumented runs 10/11/12, F1A-CAMJOINT pool
  walk): spool streams at desktop cadence (A42-STRCLK +17/vblank, 18-22
  logo-loop links, zero stalls); the logo + camera-slave channels PLAY
  (frame-group pointers refresh per part, frame-num advances then cycles
  exactly like a looping 22-part spool); clone-anim-once SUCCEEDS
  (draw-status: hidden clear, no-anim clear, has-joint-channels set);
  othercam is alive, refreshes the look-through watchdog, and copies the
  watched joint-4 bone — which never moves. calc-animation-from-spr is
  called ZERO times on BOTH backends during the title (counter probe;
  wrong suspect, eliminated).
- VERDICT: the freeze lives inside the GOAL-compiled joint decompress /
  matrix-from-control chain for the respawned logo-loop scene — prime
  suspect another arm64 emitter semantics gap (the exact shape of bug
  classes #11/#12). Next phase entry: TRS-per-HB dump of the camera
  joint + an op census of joint.gc's decompress chain against IGenARM64.
- Secondary find: at the logo-loop respawn the volumes/black logo-slaves
  (the JAK AND DAXTER lettering) deactivate on Android (3 slaves -> 1) —
  the missing-logo symptom has its own thread to pull.

## Evidence
- 19 device runs: F1a-device-runN-*.png, F1a-focus-runN.txt (pre+post
  mCurrentFocus brackets per tick), F1a-routed-logcat-runN.log.
  Survivor logcats: run-10/11/12 (frame 8760-9000, zero sig=) and run-19
  (the clean post-fix pass; frame>=300, tris>0 — validator gates).
- Interlopers (xiaoji, ghplus, sshxmobile x2) disabled per run,
  re-enabled by trap; verified after each run.
- Oracles: x86 smoke PASS (rebuilt after every shared-TU change), qemu
  675 with the regenerated CGOs, x86 CGO sha256 == A2 baseline,
  F1A_MERC_DUMP desktop twin vs device F1A-MERC-DRAW/VERIFY.
- DGO hashes: .autoport/reports/F1a-arm64-cgo-hashes.txt (28 files).

## What the frames show / honest deltas vs the full mandate
- Village terrain + time-of-day render as in A42; merc content now draws
  (draws x47, tris x270 per frame at the village scene vs pre-fix).
  Whether the J&D logo is VISIBLE in a capture window: the logo's 5
  merc draws verify+execute, but the lettering slaves deactivate at the
  loop scene and the camera freeze keeps the course from its flying
  shots — visual confirmation of the logo is for the supervisor's
  capture set; this report does not claim it.
- Horizon: HORIZONTAL in the matrix sense (proved bit-identical to
  desktop at matched moments); the parked pose's pitch makes the visual
  horizon sit outside several captures. Camera MOTION (different ticks =
  different locales) is NOT yet achieved — that is blocker B, scoped to
  one named chain with instruments in place.
- PRESS START: unreached until the course holds (attract text renders).
