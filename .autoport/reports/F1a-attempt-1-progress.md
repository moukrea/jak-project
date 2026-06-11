# Phase F1a — camera + merc: honest progress report (attempt 1)
#
# Headline: arm64 emitter bug class #12 found and fixed (swizzle_vf was a
# dup stand-in — every vector cross product on Android computed
# (cx,cx,cx)); the full merc/generic/sprite bucket family is PORTED,
# COMPILED, WIRED and the title-level merc draws EXECUTE on-device with
# bit-perfect data (GPU buffer == fr3 CPU copy, driver-verified); the
# camera "tilt" framing was FALSIFIED by a field-by-field oracle (the
# matrices are bit-identical at matched moments — the pose itself is
# legitimate; the real defect is the title course FREEZING at the
# logo-loop boundary, excavated to the joint-eval data path). Two named
# blockers remain, each one probe from mechanism.

## 1. Fixed and verified this phase

### 1a. arm64 emitter bug class #12 — swizzle_vf / shuffle_vf stand-ins
- goalc/emitter/IGenARM64.cpp `swizzle_vf` emitted `dup_4s_elem(dst, src,
  ctrl&3)` — a one-lane broadcast — where x86 emits VSHUFPS dst,src,src,imm
  (full 4-lane swizzle). `shuffle_vf` ignored its pattern entirely (mov).
- Blast radius: `IR_SwizzleVF` is the lowering of `.outer.product.a/b.vf`
  (98 sites in jak1: vector-cross!, vector-flatten!, vector-reflect!*,
  forward-up/down->inv-matrix — the camera/collision basis builders) and
  bones.gc's `.cross.vf` macro (merc bone NORMAL matrices). Every cross
  product computed (c,c,c,c) where c is only the true X component.
- Fix: exact VSHUFPS semantics via the free V0 scratch (ORR V0<-src +
  4x INS Vd.S[t]<-V0.S[sel]), identity/broadcast fast paths. All 9
  encodings NDK-assembler-verified; on-paper composition reproduces
  cross(V1,V2)=(-4,8,-4) on the Asm.cpp worked example bit-exactly.
- Regen: all 28 CGO/DGOs (arm64) rebuilt and reseeded (out/jak1-arm64/iso,
  device files/iso_data, full-assets dir). x86 CGOs byte-identical to the
  A2 baseline (sha256). qemu boot: 675 'link finish:' (floor 675). x86
  smoke: `link finish: logo` PASS after every shared-TU change.

### 1b. Merc/Generic/Sprite ported (validator: Merc2 syms >= 5 — actual 52)
- android/CMakeLists.txt: Merc2, Merc2BucketRenderer, Generic2 (x4 TUs),
  Generic2BucketRenderer, Sprite3, Sprite3_Distort, Sprite3_Glow,
  GlowRenderer compiled into libgk.so (52 Merc2 + 60 Generic2 + 52
  Sprite3 symbols).
- android_opengl_renderer.cpp: 8 Merc2 buckets + 10 Generic2 buckets +
  SPRITE wired exactly like the desktop jak1 table (shared Merc2/Generic2
  cores, EyeRenderer already live). Remaining SkipRenderers: ocean x2,
  tie x2, shrub x2, shadow, depth-cue (9 — named, one-shot logged).
- GLES gates (same class as TFragment's): fixed-index primitive restart in
  Merc2/Generic2_OpenGL/Sprite3/Sprite3_Distort/GlowRenderer (6 sites).

### 1c. On-device merc crash ladder — three layers fixed at mechanism
- Layer 1 (run-2): BLR-to-0 in Sprite3::opengl_setup_distort+0x52c — glad
  gates glVertexAttribDivisor behind GL_VERSION_3_3, above the parsed
  "ES 3.2", but it is ES 3.0 CORE. Resolved in the A36 fixup block
  (android_gfx.cpp). Programmatic audit: it was the ONLY >=3.3-gated
  entry point in the whole new-TU call surface.
- Layer 2 (run-3): SIGSEGV Merc2::handle_pc_model+0x378 — Merc2
  reconstructed the EE base as `setup.data - setup.data_offset`, valid
  only under desktop zero-copy; under A42 chain-copy the bone matrices
  (referenced by GOAL address, bones runs after merc DMA) live outside
  the copy buffer. Fix: `render_state->ee_main_memory` (bit-identical
  pointer on desktop zero-copy; x86 smoke PASS). Same fix in
  model_mod_draws (signature now takes the EE base).
- Layer 3 (runs 4-8): deterministic SIGSEGV INSIDE libGLESv2_adreno
  (fault null+0x28) on the FIRST village-level merc glDrawElements —
  see "blocker A" below. Bisection instruments added: F1A-BUCKET
  breadcrumb in the SIGSEGV dump, F1A-MERC-DRAW last-draw param capture,
  KHR_debug driver callback, F1A-MERC-VERIFY (CPU min/max + GPU
  glMapBufferRange memcmp), boot-time minimal-draw self-test, file-knob
  bisection (f1a_merc_nodraw/noubo/notex via run-as touch, no rebuild).
- Hardening kept: UBO bind-range end-clamp (the fixed 128-matrix window
  could overrun the bone buffer for end-of-buffer draws — a real latent
  bug on all backends, desktop silently kept a stale binding).

## 2. The camera — what the oracle actually said

### 2a. The "+85° tilt / rolled world" framing is DEAD
- A36-TFRAG-CAM matched-moment diff (first village1 tfrag-init, x86 vs
  device): rotation rows, trans, hvdf, fog, cam3.y/z/w ALL BIT-IDENTICAL.
  The only delta is the X projection scale: 0.419 (desktop 4:3 window) vs
  0.251 (device 2400x1080) — ratio exactly 5/3 = the PC port's intended
  aspect-adaptive FOV. Nothing in the matrix can roll the world; the
  "tilt" is the camera legitimately pitched up inside the hut at the
  PARKED pose both backends share early in the course.
- Desktop pose-over-time reference (A37-CAM now periodic every 600
  frames, mirrored on Android): parked at (-543372.9, 194381.1, ~897k)
  until f~600, FLYING from f=1200 (trans/rot change every sample).

### 2b. Android freezes at the logo-loop boundary — chain fully excavated
- Run-10/11/12 series (150 s each, zero faults): Android follows the same
  early path ~600 frames late, then FREEZES at (-543372.9, 189225.1,
  874363.8) from f~1800 (logo-loop start) forever.
- F1A-CAMJOINT probe (alive-list walk, per-HB): the logo + camera-slave
  channels PLAY the whole time — frame-group pointers refresh per spool
  part, frame-num advances then cycles exactly like a looping 22-part
  spool; clone-anim-once SUCCEEDS (slave draw-status: hidden clear,
  no-anim clear, has-joint-channels set); othercam is alive and
  refreshing the look-through watchdog (lto=1) and copying the watched
  joint — which never moves. A42-STRCLK: str clock advancing +17/vblank,
  18-22 logo-loop part links at desktop cadence, zero loader stalls.
- F1A-CALCANIM counter: calc-animation-from-spr is called ZERO times in
  150 s — on BOTH backends (desktop twin env-gated) — wrong suspect,
  eliminated; the title path decompresses via the GOAL-side
  joint-control-channel-group-eval!/do-joint-math chain.
- VERDICT (blocker B): channel state healthy + eval invoked + output pose
  constant from the logo-loop respawn on ==> the divergence is INSIDE the
  GOAL-compiled joint decompression chain (joint.gc decompress/
  matrix-from-control path) — prime suspect: another arm64 emitter
  stand-in/semantics gap in the bit-unpack ops that code uses (the exact
  pattern of bug classes #11 and #12). Next probe: dump the camera
  joint's decompressed TRS per HB on both backends; then diff the
  decompress GOAL functions' op usage against the emitter (same census
  method that caught #11/#12).
- Also observed: at the logo-loop respawn, the volumes/black logo-slaves
  (the JAK AND DAXTER lettering meshes) deactivate on Android (3 slaves
  -> 1) — secondary thread for why the logo would still be absent in the
  loop scene even with merc drawing; un-investigated.

## 3. Blocker A — the village-level merc draw kills the Adreno driver
- 100% deterministic: first frame with village1 foreground content
  (chain 21KB->131KB), bucket l1-pris-merc, di=0/53, tex=0x225,
  first_bone=0, idx=117+64945, plain strip, no envmap, no mod.
- The driver reports NO GL error (KHR_debug armed, synchronous); the
  fp-walk dead-ends inside libGLESv2_adreno (fault null+0x28, same pc
  every run).
- Boot self-test (minimal 3-vertex MERC2 draw, same VAO/program/UBO
  shape): SURVIVES, err=0 — program + driver + draw shape are fine.
- F1A-MERC-VERIFY on the TITLE level's 6 first draws: indices sane
  (min/max within 22518 verts, restart sentinels present), GPU index
  buffer == fr3 CPU copy (glMapBufferRange memcmp), err=0 — and run-13
  EXECUTED those title draws live without crashing. The fault is
  specific to the VILLAGE level's first pris draw.
- Next probe (queued): re-scope F1A-MERC-VERIFY to non-title levels (the
  6-slot cap was consumed by title draws) — if village gpu-match=0, the
  upload sheared (loader-side mechanism); if =1, the draw is legal data
  the driver chokes on and the fix is a GLES-side restructuring of that
  draw (e.g. splitting the strip at restart boundaries CPU-side).

## 4. Evidence inventory
- 14 device runs (F1a-device-runN-*.png, F1a-focus-runN.txt brackets,
  F1a-routed-logcat-runN.log). Newest survives-to-150s logcats: run-10/
  11/12 (max-frame 8760-9000, tris>0, ZERO sig= lines); crash-window
  logcats: run-4..8, run-13 (frame 322-323, tris=82).
- Camera series: /tmp/f1a-x86-camdump*.log + A37-CAM/A36-TFRAG-CAM-HB in
  run-10/11/12 logcats; merc draw oracles: F1A_MERC_DUMP x86 logs vs
  F1A-MERC-DRAW/VERIFY device lines.
- DGO hashes: .autoport/reports/F1a-arm64-cgo-hashes.txt (28 files);
  x86 CGOs == A2 baseline; qemu 675; x86 smoke PASS (latest build).
- Interlopers (xiaoji, ghplus, sshxmobile x2) disabled per run and
  re-enabled by trap — verified after every run.

## 5. Honest residuals / next phase entry points
1. Blocker A: village merc draw — one verify-line away from naming
   sheared-upload vs legal-data-driver-fault. All instruments in place.
2. Blocker B: title-course joint decompression freeze at logo-loop —
   suspect family identified (GOAL joint decompress ops on arm64); next
   is a TRS-per-HB dump + an op census of joint.gc's decompress chain
   against IGenARM64 (the #11/#12 method).
3. The logo lettering slaves deactivate at the loop scene on Android
   (3 logo-slaves -> 1) — feeds the missing-logo symptom; uninvestigated.
4. Sprite/Generic render content untested beyond "no crash, no GL error"
   (they executed in runs 10-13 without incident).
5. PRESS START text: not reachable until the course holds (it appears at
   the settled title); attract text renders (A41/A42 evidence).
6. Camera aspect: the 5/3 x-scale difference is intended PC-port
   widescreen behavior; flag for the supervisor's visual judgement of
   "correct title" on a 20:9 panel.
